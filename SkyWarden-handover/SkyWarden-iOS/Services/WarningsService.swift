// Sky Warden — warnings fetch + filter
//
// Fetches the open GeoJSON warning feeds for the user's state, decodes the
// geometry, keeps only the warnings whose area actually covers the user, and
// returns them worst-first. Each feed labels its fields differently, so a small
// per-source adapter maps its properties onto WeatherWarning.
//
// Coverage today: QLD (cleanest schema, home turf), NSW RFS, VicEmergency — all
// CC-BY, all keyless. Adding a state is one Feed entry plus an adapter.

import Foundation
import CoreLocation

struct WarningsService {

    /// A source feed and how to read one of its features.
    struct Feed {
        let org: String
        let url: URL
        /// AU state bounding boxes — skip a feed entirely when the user is far
        /// from it, so we don't fetch NSW's feed for someone in Perth.
        let bbox: (latMin: Double, latMax: Double, lonMin: Double, lonMax: Double)
        let parse: (GeoFeature) -> (title: String, severity: WarningSeverity,
                                    category: String, instruction: String?, updated: Date?, url: String?)?
    }

    static let feeds: [Feed] = [
        Feed(org: "QFD",
             url: URL(string: "https://publiccontent-gis-psba-qld-gov-au.s3.amazonaws.com/content/Feeds/BushfireCurrentIncidents/bushfireAlert.json")!,
             bbox: (-29.5, -9.5, 137.5, 154.5),
             parse: { f in
                 guard let title = f.string("WarningTitle") ?? f.string("Header") else { return nil }
                 return (title,
                         WarningSeverity.from(f.string("WarningLevel") ?? f.string("WarningType_Level")),
                         f.string("EventType") ?? "Bushfire",
                         f.string("CallToAction") ?? f.string("Impacts"),
                         f.date("PublishDateLocal_ISO") ?? f.date("ItemDateTimeLocal_ISO"),
                         nil)
             }),
        Feed(org: "NSW RFS",
             url: URL(string: "https://www.rfs.nsw.gov.au/feeds/majorIncidents.json")!,
             bbox: (-37.6, -28.1, 140.9, 153.7),
             parse: { f in
                 guard let title = f.string("title") else { return nil }
                 // NSW packs the structured detail into an HTML `description`.
                 let desc = f.string("description") ?? ""
                 let level = Self.field("ALERT LEVEL", in: desc) ?? f.string("category")
                 return (title,
                         WarningSeverity.from(level),
                         Self.field("TYPE", in: desc) ?? "Incident",
                         Self.field("STATUS", in: desc),
                         f.date("pubDate"),
                         f.string("link"))
             }),
        Feed(org: "VicEmergency",
             url: URL(string: "https://emergency.vic.gov.au/public/osom-geojson.json")!,
             bbox: (-39.2, -33.9, 140.9, 150.1),
             parse: { f in
                 guard let title = f.string("sourceTitle") ?? f.string("name") else { return nil }
                 return (title,
                         WarningSeverity.from(f.string("severity") ?? f.string("status")),
                         f.string("category1") ?? "Incident",
                         f.string("category2"),
                         f.date("updated") ?? f.date("created"),
                         f.string("url"))
             }),
    ]

    /// Returns the warnings covering `location`, worst severity first.
    func warnings(near location: CLLocation) async -> [WeatherWarning] {
        let p = location.coordinate
        let relevant = Self.feeds.filter {
            p.latitude >= $0.bbox.latMin && p.latitude <= $0.bbox.latMax &&
            p.longitude >= $0.bbox.lonMin && p.longitude <= $0.bbox.lonMax
        }
        guard !relevant.isEmpty else { return [] }

        var out: [WeatherWarning] = []
        await withTaskGroup(of: [WeatherWarning].self) { group in
            for feed in relevant {
                group.addTask { await Self.fetch(feed, covering: p) }
            }
            for await ws in group { out.append(contentsOf: ws) }
        }
        // Worst first; within a level, most-recent first.
        return out.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity
                                       : ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast)
        }
    }

    private static func fetch(_ feed: Feed, covering p: CLLocationCoordinate2D) async -> [WeatherWarning] {
        var req = URLRequest(url: feed.url)
        req.timeoutInterval = 10
        req.setValue("SkyWarden/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let features = GeoFeature.decode(data) else { return [] }

        return features.compactMap { f -> WeatherWarning? in
            guard f.area.contains(p), let parsed = feed.parse(f) else { return nil }
            return WeatherWarning(id: "\(feed.org):\(parsed.title):\(f.id)",
                                  title: parsed.title, severity: parsed.severity,
                                  category: parsed.category, sourceOrg: feed.org,
                                  instruction: parsed.instruction, updated: parsed.updated, url: parsed.url)
        }
    }

    /// Pulls `KEY: value` out of NSW's HTML description blob.
    static func field(_ key: String, in html: String) -> String? {
        guard let r = html.range(of: "\(key): ") else { return nil }
        let after = html[r.upperBound...]
        let end = after.firstIndex(where: { $0 == "<" || $0 == "\n" }) ?? after.endIndex
        let value = after[..<end].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Minimal GeoJSON

/// One GeoJSON feature, reduced to its area and a bag of string/date properties.
struct GeoFeature {
    let id: String
    let area: WarningArea
    private let props: [String: Any]

    func string(_ key: String) -> String? {
        if let s = props[key] as? String, !s.isEmpty { return s }
        if let n = props[key] as? NSNumber { return n.stringValue }
        return nil
    }

    private static let iso = ISO8601DateFormatter()
    private static let iso2: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    func date(_ key: String) -> Date? {
        guard let s = string(key) else { return nil }
        return GeoFeature.iso.date(from: s) ?? GeoFeature.iso2.date(from: s)
    }

    /// Decodes a FeatureCollection into features, handling Point / Polygon /
    /// MultiPolygon / GeometryCollection. Uses JSONSerialization because the
    /// property bags are wildly heterogeneous across feeds.
    static func decode(_ data: Data) -> [GeoFeature]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return nil }

        return features.enumerated().compactMap { (i, feat) in
            guard let geom = feat["geometry"] as? [String: Any],
                  let area = parseGeometry(geom) else { return nil }
            let props = feat["properties"] as? [String: Any] ?? [:]
            let id = (props["guid"] ?? props["UniqueID"] ?? props["id"] ?? "\(i)")
            return GeoFeature(id: "\(id)", area: area, props: props)
        }
    }

    private static func parseGeometry(_ geom: [String: Any]) -> WarningArea? {
        guard let type = geom["type"] as? String else { return nil }
        switch type {
        case "Point":
            guard let c = geom["coordinates"] as? [Double], c.count >= 2 else { return nil }
            // A point incident is relevant to nearby suburbs, not just its pixel.
            return .point(CLLocationCoordinate2D(latitude: c[1], longitude: c[0]), radiusKm: 50)
        case "Polygon":
            guard let rings = ringsOf(geom["coordinates"]) else { return nil }
            return .polygon(rings: rings)
        case "MultiPolygon":
            guard let polys = geom["coordinates"] as? [Any] else { return nil }
            let areas = polys.compactMap { ringsOf($0).map { WarningArea.polygon(rings: $0) } }
            return areas.isEmpty ? nil : .collection(areas)
        case "GeometryCollection":
            guard let geoms = geom["geometries"] as? [[String: Any]] else { return nil }
            let areas = geoms.compactMap(parseGeometry)
            return areas.isEmpty ? nil : .collection(areas)
        default:
            return nil
        }
    }

    /// GeoJSON coordinates are [lon, lat]. A polygon's coordinates are an array
    /// of rings, each an array of positions.
    private static func ringsOf(_ any: Any?) -> [[CLLocationCoordinate2D]]? {
        guard let rings = any as? [Any] else { return nil }
        let parsed: [[CLLocationCoordinate2D]] = rings.compactMap { ring in
            (ring as? [Any])?.compactMap { pos -> CLLocationCoordinate2D? in
                guard let c = pos as? [Double], c.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: c[1], longitude: c[0])
            }
        }
        return parsed.isEmpty ? nil : parsed
    }
}
