// Sky Warden — weather map tiles
//
// NASA GIBS serves open imagery with no API key and no licence agreement, which
// is why it's the layer we can actually ship. Measured behaviour (2026-07):
//
//   Himawari / GOES infrared   10-min cadence, ~40–60 min latency, z4–z5
//   IMERG 30-min precipitation 30-min cadence, ~6 h latency,        z3–z5
//
// So this is a *weather-system* view (≈4 km/px), not a street-level radar. It
// answers "is that band of cloud heading for me", not "is it raining on my
// street". Honest labelling matters more than pretending otherwise.
//
// Real radar (BOM, RainViewer) needs a licence — BOM's anonymous feeds are
// personal/in-house use only, and RainViewer's free tier is personal use. Those
// slot in behind `RadarProvider` once an agreement exists.

import Foundation
import CoreLocation
import MapKit
import UIKit

// MARK: - Layer definitions

struct TileLayerSpec {
    let id: String            // GIBS layer identifier
    let matrixSet: String
    let ext: String
    let minZ: Int
    let maxZ: Int
    let stepMinutes: Int      // native cadence
    let searchBackMinutes: Int// how far back to hunt for the newest frame
}

enum WeatherMapLayer: String, CaseIterable, Identifiable {
    case cloud, rainfall
    var id: String { rawValue }

    var title: String { self == .cloud ? "Cloud" : "Rainfall" }

    /// What the user is actually looking at — never oversell it.
    var caption: String {
        switch self {
        case .cloud:    "Infrared cloud top · ~4 km · updates every 10 min"
        case .rainfall: "GPM IMERG precipitation · ~10 km · ~6 h behind"
        }
    }

    var attribution: String {
        switch self {
        case .cloud:    "Imagery: NASA GIBS · Himawari (JMA) / GOES (NOAA)"
        case .rainfall: "Imagery: NASA GIBS · GPM IMERG"
        }
    }

    /// The geostationary satellite that can see this longitude. Each one only
    /// covers its own disc, so a user in Europe gets no live cloud layer.
    static func geostationaryLayer(forLongitude lon: Double) -> String? {
        switch lon {
        case 80...200, -180 ..< -160: "Himawari_AHI_Band13_Clean_Infrared"
        case -100 ..< -20:            "GOES-East_ABI_Band13_Clean_Infrared"
        case -160 ..< -100:           "GOES-West_ABI_Band13_Clean_Infrared"
        default:                      nil
        }
    }

    func spec(forLongitude lon: Double) -> TileLayerSpec? {
        switch self {
        case .cloud:
            guard let id = Self.geostationaryLayer(forLongitude: lon) else { return nil }
            return TileLayerSpec(id: id, matrixSet: "GoogleMapsCompatible_Level6", ext: "png",
                                 minZ: 4, maxZ: 5, stepMinutes: 10, searchBackMinutes: 180)
        case .rainfall:
            return TileLayerSpec(id: "IMERG_Precipitation_Rate_30min",
                                 matrixSet: "GoogleMapsCompatible_Level6", ext: "png",
                                 minZ: 3, maxZ: 5, stepMinutes: 30, searchBackMinutes: 720)
        }
    }
}

// MARK: - Service

struct WeatherMapService {
    static let base = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best"

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    /// GIBS is WMTS: the path is {z}/{row}/{col} — row is y, col is x.
    static func tileURL(_ spec: TileLayerSpec, frame: Date, z: Int, x: Int, y: Int) -> URL? {
        URL(string: "\(base)/\(spec.id)/default/\(stamp.string(from: frame))/\(spec.matrixSet)/\(z)/\(y)/\(x).\(spec.ext)")
    }

    /// Floors a date to the layer's native cadence.
    static func floor(_ date: Date, toStep minutes: Int) -> Date {
        let bucket = Double(minutes * 60)
        let t = (date.timeIntervalSince1970 / bucket).rounded(.down)
        return Date(timeIntervalSince1970: t * bucket)
    }

    /// Latency varies (GOES has gaps; Himawari runs ~40–60 min behind), so find
    /// the newest frame that actually serves a tile instead of assuming a lag.
    static func latestFrame(_ spec: TileLayerSpec, near coord: CLLocationCoordinate2D) async -> Date? {
        let z = spec.minZ
        let (x, y) = tileIndex(coord, z: z)
        var candidate = floor(Date(), toStep: spec.stepMinutes)
        let steps = spec.searchBackMinutes / spec.stepMinutes

        for _ in 0..<steps {
            if let url = tileURL(spec, frame: candidate, z: z, x: x, y: y),
               await tileExists(url) { return candidate }
            candidate = candidate.addingTimeInterval(-Double(spec.stepMinutes * 60))
        }
        return nil
    }

    private static func tileExists(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 6
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// `count` frames ending at `latest`, oldest first.
    static func frames(endingAt latest: Date, spec: TileLayerSpec, count: Int) -> [Date] {
        (0..<count).map { latest.addingTimeInterval(-Double($0 * spec.stepMinutes * 60)) }.reversed()
    }

    /// Slippy-map tile index for a coordinate.
    static func tileIndex(_ c: CLLocationCoordinate2D, z: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(z))
        let x = Int((c.longitude + 180) / 360 * n)
        let latRad = c.latitude * .pi / 180
        let y = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n)
        return (max(0, x), max(0, y))
    }

    /// The deepest tile GIBS actually serves that *contains* the requested one,
    /// plus where inside it the request sits.
    ///
    /// MapKit asks for z6 on a phone showing ~1400 km, but these layers stop at
    /// z5. Setting `MKTileOverlay.maximumZ` does NOT make MapKit scale the last
    /// available level up — it just stops requesting tiles entirely, and the
    /// overlay silently never draws. So we resolve the ancestor ourselves.
    ///
    /// `dz` is how many levels we climbed; the request occupies cell
    /// (`ox`, `oy`) of the 2^dz × 2^dz grid inside the ancestor, `oy` counted
    /// from the top.
    static func ancestor(z: Int, x: Int, y: Int, maxZ: Int)
    -> (z: Int, x: Int, y: Int, dz: Int, ox: Int, oy: Int) {
        let dz = max(0, z - maxZ)
        let sx = x >> dz, sy = y >> dz
        return (z - dz, sx, sy, dz, x - (sx << dz), y - (sy << dz))
    }
}


// MARK: - Source-tile cache
//
// The animation mounts one overlay per frame and shows them by raising alpha.
// MapKit cancels the in-flight tile loads of a renderer the moment it turns
// invisible, so at a 1.2 s cadence no frame ever finished downloading and the
// layer stayed blank forever. Caching the *rendered* tile didn't help — the
// download never completed to be cached.
//
// So cache the upstream tile instead, and warm it before playback. A frame is
// only a handful of tiles at z5 (each spans ~1000 km), so this is cheap, and
// afterwards `loadTile` answers from memory without touching the network.
final class TileSource {
    static let shared = TileSource()
    private let images = NSCache<NSURL, UIImage>()
    private let missing = NSCache<NSURL, NSNumber>()   // GIBS 404s outside the satellite disc

    func cached(_ url: URL) -> CGImage? { images.object(forKey: url as NSURL)?.cgImage }
    func isKnownMissing(_ url: URL) -> Bool { missing.object(forKey: url as NSURL) != nil }

    /// Returns nil when the tile genuinely doesn't exist (and remembers that).
    func load(_ url: URL) async -> CGImage? {
        if let hit = cached(url) { return hit }
        if isKnownMissing(url) { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data), let cg = image.cgImage else {
            missing.setObject(1, forKey: url as NSURL)
            return nil
        }
        images.setObject(image, forKey: url as NSURL)
        return cg
    }

    /// Pulls every source tile the given frames need to cover `region`, so the
    /// animation can flip between them without a single network round-trip.
    func warm(spec: TileLayerSpec, frames: [Date], region: MKCoordinateRegion) async {
        let z = spec.maxZ
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        // Mercator blows up at the poles; the imagery stops well before them anyway.
        let (x0, y0) = WeatherMapService.tileIndex(.init(latitude: min(84, north), longitude: west), z: z)
        let (x1, y1) = WeatherMapService.tileIndex(.init(latitude: max(-84, south), longitude: east), z: z)
        let n = 1 << z

        var urls: [URL] = []
        for f in frames {
            for x in x0...max(x0, x1) where x < n {
                for y in y0...max(y0, y1) where y < n {
                    if let u = WeatherMapService.tileURL(spec, frame: f, z: z, x: x, y: y) { urls.append(u) }
                }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for u in urls { group.addTask { _ = await self.load(u) } }
        }
    }
}

// MARK: - MapKit overlay

final class GIBSTileOverlay: MKTileOverlay {
    let spec: TileLayerSpec
    let frame: Date
    private var isInfrared: Bool { spec.id.contains("Infrared") }

    init(spec: TileLayerSpec, frame: Date) {
        self.spec = spec
        self.frame = frame
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        // Deliberately no minimumZ/maximumZ: `maximumZ` does NOT make MapKit
        // scale the deepest available level up, it makes MapKit stop requesting
        // tiles altogether, and the overlay silently never draws. `loadTile`
        // resolves the ancestor itself instead.
        canReplaceMapContent = false
    }

    /// Rendered, masked tiles — keyed by the *requested* path, since several
    /// requests share one upstream ancestor.
    private static let rendered = NSCache<NSString, NSData>()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "\(spec.id)|\(frame.timeIntervalSince1970)|\(path.z)/\(path.x)/\(path.y)" as NSString
        if let hit = Self.rendered.object(forKey: key) { result(hit as Data, nil); return }

        let a = WeatherMapService.ancestor(z: path.z, x: path.x, y: path.y, maxZ: spec.maxZ)
        guard let url = WeatherMapService.tileURL(spec, frame: frame, z: a.z, x: a.x, y: a.y) else {
            result(nil, nil); return
        }

        // Warmed by TileSource.warm, so this is normally a synchronous cache hit
        // and MapKit gets its tile before it can cancel us.
        func finish(_ source: CGImage?) {
            guard let source,
                  let tile = Self.upsample(source, dz: a.dz, ox: a.ox, oy: a.oy),
                  let out = isInfrared ? Self.cloudMask(tile) : UIImage(cgImage: tile).pngData()
            else {
                // Draw nothing outside the satellite disc — never an opaque slab,
                // which would wash out the whole basemap.
                result(nil, nil); return
            }
            Self.rendered.setObject(out as NSData, forKey: key)
            result(out, nil)
        }

        if let source = TileSource.shared.cached(url) { finish(source); return }
        if TileSource.shared.isKnownMissing(url) { result(nil, nil); return }
        Task { finish(await TileSource.shared.load(url)) }
    }

    /// Blows cell (`ox`, `oy`) of the ancestor up to a full 256px tile.
    /// Drawn via an offset scale rather than `CGImage.cropping`, so we never have
    /// to reason about whether crop rects are top-left or bottom-left origin:
    /// the whole ancestor is scaled to 2^dz tiles wide and slid so the wanted
    /// cell lands on the canvas. CoreGraphics user space is y-up, hence the
    /// `n - 1 - oy` flip on the row.
    private static func upsample(_ image: CGImage, dz: Int, ox: Int, oy: Int) -> CGImage? {
        guard dz > 0 else { return image }
        let n = 1 << dz
        let side = 256.0
        guard let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: -Double(ox) * side,
                                   y: -Double(n - 1 - oy) * side,
                                   width: Double(n) * side, height: Double(n) * side))
        return ctx.makeImage()
    }

    /// Infrared arrives as a *fully opaque* greyscale image — warm ground is
    /// mid-grey (~139), not black — so alpha-blending or screen-blending it lifts
    /// the whole basemap into a washed-out haze. Instead we remap brightness
    /// (i.e. cloud-top coldness) onto alpha, so only actual cloud is drawn and
    /// the map underneath stays legible.
    ///
    /// Luminance below `floorLum` → transparent; above `ceilLum` → solid cloud.
    /// The floor sits just above the ground's median so land doesn't wash out,
    /// and alpha is gamma-lifted so mid-level cloud reads rather than hazing.
    private static func cloudMask(_ image: CGImage,
                                  floorLum: Double = 144,
                                  ceilLum: Double = 190) -> Data? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        for i in stride(from: 0, to: px.count, by: 4) {
            let lum = 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
            let t = max(0, min(1, (lum - floorLum) / (ceilLum - floorLum)))
            let a = pow(t, 0.65)
            // Premultiplied: paint cloud as near-white, scaled by its own alpha.
            px[i] = UInt8(230 * a); px[i + 1] = UInt8(240 * a); px[i + 2] = UInt8(255 * a)
            px[i + 3] = UInt8(a * 255)
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out).pngData()
    }
}
