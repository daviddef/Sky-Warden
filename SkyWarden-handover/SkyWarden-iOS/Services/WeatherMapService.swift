// Sky Warden — weather map tiles
//
// Three layers, two providers. Measured behaviour (2026-07):
//
//   Radar (RainViewer)         10-min cadence, ~5 min latency,  useful to z10
//   Himawari / GOES infrared   10-min cadence, ~40–60 min latency, z4–z5
//   IMERG 30-min precipitation 30-min cadence, ~4–6 h latency,     z3–z5
//
// Radar is the only layer that answers "is it raining on my street". The other
// two are weather-system views at ~4 km and ~10 km, and are labelled as such.
//
// LICENSING — read before shipping publicly:
//   NASA GIBS       open, no key, no agreement. Safe to ship.
//   RainViewer      free tier is PERSONAL USE. A public App Store release needs
//                   their commercial plan. Fine for TestFlight on our own
//                   devices; it is a licensing blocker, not a technical one.
//   BOM             no public tile service at all; the anonymous feeds are
//                   personal/in-house only. A real licence goes through
//                   webreg@bom.gov.au.

import Foundation
import CoreLocation
import MapKit
import UIKit

// MARK: - Layer definitions

/// A single animation frame. The provider decides what `token` means: a GIBS
/// WMTS timestamp, or a RainViewer catalogue path (its frames are content-
/// addressed, so they can't be derived from the clock).
struct MapFrame: Hashable {
    let date: Date
    let token: String
}

struct TileLayerSpec {
    enum Provider { case gibs, rainViewer }
    /// Infrared needs remapping to alpha; radar and precipitation ship transparent.
    enum PostProcess { case none, infraredCloud }

    let provider: Provider
    let id: String              // GIBS layer identifier; unused by RainViewer
    let matrixSet: String
    let post: PostProcess
    let minZ: Int               // zoom used to probe for the newest frame
    let maxZ: Int               // deepest zoom the server actually serves
    let stepMinutes: Int        // native cadence
    let searchBackMinutes: Int  // how far back to hunt for the newest frame
    let frameCount: Int
    /// Metres across for the initial camera — radar rewards a tighter view.
    let regionMetres: CLLocationDistance
}

enum WeatherMapLayer: String, CaseIterable, Identifiable {
    case radar, cloud, rainfall
    var id: String { rawValue }

    var title: String {
        switch self {
        case .radar: "Radar"
        case .cloud: "Cloud"
        case .rainfall: "Rainfall"
        }
    }

    /// What the user is actually looking at — never oversell it.
    var caption: String {
        switch self {
        case .radar:    "Ground radar · ~1 km · updates every 10 min"  // detail stops at z7; deeper just enlarges
        case .cloud:    "Infrared cloud top · ~4 km · updates every 10 min"
        case .rainfall: "GPM IMERG precipitation · ~10 km · ~6 h behind"
        }
    }

    var attribution: String {
        switch self {
        case .radar:    "Radar: RainViewer · rainviewer.com"
        case .cloud:    "Imagery: NASA GIBS · Himawari (JMA) / GOES (NOAA)"
        case .rainfall: "Imagery: NASA GIBS · GPM IMERG"
        }
    }

    var footnote: String {
        switch self {
        case .radar:    "Radar composites national networks — including BOM's here. Gaps mean no radar in range, not no rain."
        case .cloud:    "A weather-system view, not a street-level radar."
        case .rainfall: "Satellite-estimated, not measured. Coarse and hours behind."
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
        case .radar:
            // z7 is a hard ceiling: past it the free tilecache serves a tile that
            // reads "Zoom Level Not Supported", which would be painted straight
            // onto the map. Deeper zooms upsample z7 instead.
            return TileLayerSpec(provider: .rainViewer, id: "radar", matrixSet: "", post: .none,
                                 minZ: 6, maxZ: 7, stepMinutes: 10, searchBackMinutes: 0,
                                 frameCount: 10, regionMetres: 500_000)
        case .cloud:
            guard let id = Self.geostationaryLayer(forLongitude: lon) else { return nil }
            return TileLayerSpec(provider: .gibs, id: id, matrixSet: "GoogleMapsCompatible_Level6",
                                 post: .infraredCloud, minZ: 4, maxZ: 5, stepMinutes: 10,
                                 searchBackMinutes: 180, frameCount: 10, regionMetres: 1_400_000)
        case .rainfall:
            return TileLayerSpec(provider: .gibs, id: "IMERG_Precipitation_Rate_30min",
                                 matrixSet: "GoogleMapsCompatible_Level6", post: .none,
                                 minZ: 3, maxZ: 5, stepMinutes: 30, searchBackMinutes: 720,
                                 frameCount: 6, regionMetres: 1_400_000)
        }
    }
}

// MARK: - Service

struct WeatherMapService {
    static let gibsBase = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best"
    static let rainViewerCatalogue = "https://api.rainviewer.com/public/weather-maps.json"

    /// The free tilecache ignores this (and the snow flag) — measured 2026-07:
    /// tiles for colour 0, 4 and 7 are byte-identical; only the `smooth` flag
    /// changes the output. Its fixed ramp is beige (light) → blue → cyan →
    /// yellow (heaviest), which is why the Map tab ships a legend: a user would
    /// otherwise read cyan as "light".
    static let radarColourScheme = 4

    /// Sampled from the tiles themselves, weakest to strongest.
    static let radarRamp: [(r: Double, g: Double, b: Double)] = [
        (146, 136, 113), (206, 192, 135), (0, 119, 170), (81, 197, 232), (255, 224, 0),
    ]

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    static func tileURL(_ spec: TileLayerSpec, frame: MapFrame, z: Int, x: Int, y: Int) -> URL? {
        switch spec.provider {
        case .gibs:
            // GIBS is WMTS: the path is {z}/{row}/{col} — row is y, col is x.
            return URL(string: "\(gibsBase)/\(spec.id)/default/\(frame.token)/\(spec.matrixSet)/\(z)/\(y)/\(x).png")
        case .rainViewer:
            // token is the full frame prefix, e.g. https://…/v2/radar/9f16bd631a61
            return URL(string: "\(frame.token)/256/\(z)/\(x)/\(y)/\(radarColourScheme)/1_1.png")
        }
    }

    // MARK: Frame discovery

    static func frames(_ spec: TileLayerSpec, near coord: CLLocationCoordinate2D) async -> [MapFrame] {
        switch spec.provider {
        case .rainViewer: return await rainViewerFrames(spec)
        case .gibs:       return await gibsFrames(spec, near: coord)
        }
    }

    /// RainViewer frame paths are content-addressed hashes, so they must be read
    /// from the catalogue rather than derived from the clock.
    static func rainViewerFrames(_ spec: TileLayerSpec) async -> [MapFrame] {
        guard let url = URL(string: rainViewerCatalogue),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = root["host"] as? String,
              let radar = root["radar"] as? [String: Any],
              let past = radar["past"] as? [[String: Any]]
        else { return [] }

        return past.suffix(spec.frameCount).compactMap { entry in
            guard let t = entry["time"] as? Double, let path = entry["path"] as? String else { return nil }
            return MapFrame(date: Date(timeIntervalSince1970: t), token: host + path)
        }
    }

    /// GIBS latency varies (GOES has gaps; Himawari runs ~40–60 min behind), so
    /// find the newest frame that actually serves a tile instead of assuming a lag.
    static func gibsFrames(_ spec: TileLayerSpec, near coord: CLLocationCoordinate2D) async -> [MapFrame] {
        guard let latest = await latestGIBSFrame(spec, near: coord) else { return [] }
        return frameDates(endingAt: latest, spec: spec, count: spec.frameCount)
            .map { MapFrame(date: $0, token: stamp.string(from: $0)) }
    }

    static func latestGIBSFrame(_ spec: TileLayerSpec, near coord: CLLocationCoordinate2D) async -> Date? {
        let z = spec.minZ
        let (x, y) = tileIndex(coord, z: z)
        var candidate = floor(Date(), toStep: spec.stepMinutes)
        let steps = spec.searchBackMinutes / spec.stepMinutes

        for _ in 0..<steps {
            let probe = MapFrame(date: candidate, token: stamp.string(from: candidate))
            if let url = tileURL(spec, frame: probe, z: z, x: x, y: y), await tileExists(url) { return candidate }
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

    /// Floors a date to the layer's native cadence.
    static func floor(_ date: Date, toStep minutes: Int) -> Date {
        let bucket = Double(minutes * 60)
        let t = (date.timeIntervalSince1970 / bucket).rounded(.down)
        return Date(timeIntervalSince1970: t * bucket)
    }

    /// `count` frames ending at `latest`, oldest first.
    static func frameDates(endingAt latest: Date, spec: TileLayerSpec, count: Int) -> [Date] {
        (0..<count).map { latest.addingTimeInterval(-Double($0 * spec.stepMinutes * 60)) }.reversed()
    }

    // MARK: Tile geometry

    /// Slippy-map tile index for a coordinate.
    static func tileIndex(_ c: CLLocationCoordinate2D, z: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(z))
        let x = Int((c.longitude + 180) / 360 * n)
        let latRad = c.latitude * .pi / 180
        let y = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n)
        return (max(0, x), max(0, y))
    }

    /// The deepest tile the server actually serves that *contains* the requested
    /// one, plus where inside it the request sits.
    ///
    /// MapKit asks for zooms past a layer's deepest level, and
    /// `MKTileOverlay.maximumZ` does NOT make it scale the last one up — it makes
    /// MapKit stop requesting tiles entirely, and the overlay silently never
    /// draws. So we resolve the ancestor ourselves.
    ///
    /// `dz` is how many levels we climbed; the request occupies cell (`ox`, `oy`)
    /// of the 2^dz × 2^dz grid inside the ancestor, `oy` counted from the top.
    static func ancestor(z: Int, x: Int, y: Int, maxZ: Int)
    -> (z: Int, x: Int, y: Int, dz: Int, ox: Int, oy: Int) {
        let dz = max(0, z - maxZ)
        let sx = x >> dz, sy = y >> dz
        return (z - dz, sx, sy, dz, x - (sx << dz), y - (sy << dz))
    }

    /// The zoom MapKit will request for a given camera. Derived from the map
    /// itself rather than guessed, so the warm-up caches exactly the tiles that
    /// are about to be asked for.
    static func zoomLevel(visibleMapRect rect: MKMapRect, widthPoints: Double) -> Int {
        guard rect.size.width > 0, widthPoints > 0 else { return 0 }
        let z = log2(MKMapSize.world.width / rect.size.width * widthPoints / 256)
        return max(0, Int(ceil(z)))
    }

    /// Inclusive tile bounds covering a map rect at zoom `z`.
    static func tileBounds(_ rect: MKMapRect, z: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        let n = Double(1 << z)
        let per = MKMapSize.world.width / n
        let x0 = Int((rect.minX / per).rounded(.down)), x1 = Int(((rect.maxX - 1) / per).rounded(.down))
        let y0 = Int((rect.minY / per).rounded(.down)), y1 = Int(((rect.maxY - 1) / per).rounded(.down))
        let hi = (1 << z) - 1
        return (max(0, x0), min(hi, x1), max(0, y0), min(hi, y1))
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
// So cache the upstream tile instead, and warm every frame before playback.
// Afterwards `loadTile` answers from memory without touching the network.
final class TileSource {
    static let shared = TileSource()
    private let images = NSCache<NSURL, UIImage>()
    private let missing = NSCache<NSURL, NSNumber>()   // tiles the provider genuinely doesn't have

    init() { images.totalCostLimit = 96 * 1024 * 1024 }

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
        images.setObject(image, forKey: url as NSURL, cost: data.count)
        return cg
    }

    /// Pulls every source tile the given frames need to cover `rect` at the zoom
    /// MapKit is about to request, so the animation can flip between frames
    /// without a single network round-trip.
    func warm(spec: TileLayerSpec, frames: [MapFrame], rect: MKMapRect, zoom: Int) async {
        let z = min(zoom, spec.maxZ)
        let b = WeatherMapService.tileBounds(rect, z: z)
        guard b.x1 >= b.x0, b.y1 >= b.y0 else { return }

        var urls: [URL] = []
        for f in frames {
            for x in b.x0...b.x1 {
                for y in b.y0...b.y1 {
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

final class WeatherTileOverlay: MKTileOverlay {
    let spec: TileLayerSpec
    let frame: MapFrame

    init(spec: TileLayerSpec, frame: MapFrame) {
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

    /// Rendered tiles — keyed by the *requested* path, since several requests
    /// can share one upstream ancestor.
    private static let rendered = NSCache<NSString, NSData>()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "\(spec.id)|\(frame.token)|\(path.z)/\(path.x)/\(path.y)" as NSString
        if let hit = Self.rendered.object(forKey: key) { result(hit as Data, nil); return }

        let a = WeatherMapService.ancestor(z: path.z, x: path.x, y: path.y, maxZ: spec.maxZ)
        guard let url = WeatherMapService.tileURL(spec, frame: frame, z: a.z, x: a.x, y: a.y) else {
            result(nil, nil); return
        }
        let post = spec.post

        // Warmed by TileSource.warm, so this is normally a synchronous cache hit
        // and MapKit gets its tile before it can cancel us.
        func finish(_ source: CGImage?) {
            guard let source,
                  let tile = Self.upsample(source, dz: a.dz, ox: a.ox, oy: a.oy),
                  let out = post == .infraredCloud ? Self.cloudMask(tile) : UIImage(cgImage: tile).pngData()
            else {
                // Draw nothing where the provider has no data — never an opaque
                // slab, which would wash out the whole basemap.
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
