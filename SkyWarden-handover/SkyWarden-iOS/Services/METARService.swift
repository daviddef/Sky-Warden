// Sky Warden — global observation truth via aviationweather.gov METARs
//
// The forecast-skill ledger scores each source's past forecasts against a real
// thermometer. In Australia that's BOM; everywhere else there was nothing, so
// the moat only worked at home. METARs fix that: airport observations, ~1 h
// latency, a dense global network, and US-government PUBLIC DOMAIN — no licence
// to negotiate.
//
// This feeds the ledger's TRUTH only, never the displayed consensus: the nearest
// airport can be tens of km away, so it must not move the temperature we show
// for the user's exact spot. It's a reference for scoring, not a local reading.

import Foundation
import CoreLocation

struct METARService {

    struct Station: Equatable {
        let icao: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let tempC: Double
        let windKmh: Double
        let time: Date

        static func == (a: Station, b: Station) -> Bool {
            a.icao == b.icao && a.time == b.time
        }
    }

    /// The freshest usable observation near `location`, as ledger truth, or nil.
    func observation(near location: CLLocation, now: Date = Date()) async -> (station: Station, truth: [SkillMetric: Double])? {
        let c = location.coordinate
        // ~±0.9° ≈ 100 km box — enough to catch a regional airport without pulling
        // in one so far away it's meaningless.
        let pad = 0.9
        let bbox = "\(c.latitude - pad),\(c.longitude - pad),\(c.latitude + pad),\(c.longitude + pad)"
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?bbox=\(bbox)&format=json") else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("SkyWarden/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let stations = Self.parse(data)
        guard let best = Self.nearest(stations, to: location, now: now) else { return nil }
        return (best, Self.truth(best))
    }

    // MARK: - Pure parsing / selection (testable without a network)

    static func parse(_ data: Data) -> [Station] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let icao = m["icaoId"] as? String,
                  let lat = (m["lat"] as? NSNumber)?.doubleValue,
                  let lon = (m["lon"] as? NSNumber)?.doubleValue,
                  let temp = (m["temp"] as? NSNumber)?.doubleValue,
                  let time = (m["reportTime"] as? String).flatMap(parseTime) else { return nil }
            // wspd is in KNOTS; the app works in km/h.
            let windKt = (m["wspd"] as? NSNumber)?.doubleValue ?? 0
            return Station(icao: icao, name: (m["name"] as? String) ?? icao,
                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                           tempC: temp, windKmh: windKt * 1.852, time: time)
        }
    }

    /// Report times arrive as "2026-07-11T00:20:00.000Z" (fractional seconds) —
    /// which the default ISO8601 formatter REJECTS — or occasionally as
    /// "2026-07-11 00:00:00" (space, UTC). Try all three; a station whose time
    /// won't parse is dropped rather than dated to 1970 and wrongly called stale.
    static func parseTime(_ s: String) -> Date? {
        if let d = isoFractional.date(from: s) { return d }
        if let d = isoPlain.date(from: s) { return d }
        return spaceTime.date(from: s)
    }
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let spaceTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// The closest station that is both near enough and fresh enough to be a
    /// meaningful truth. A stale or far report is worse than no truth at all —
    /// it would teach the ledger the wrong lesson.
    static func nearest(_ stations: [Station], to location: CLLocation,
                        maxKm: Double = 100, maxAgeMinutes: Double = 90, now: Date = Date()) -> Station? {
        stations
            .filter { now.timeIntervalSince($0.time) <= maxAgeMinutes * 60 && now.timeIntervalSince($0.time) >= -600 }
            .map { ($0, WarningGeometry.haversineKm(location.coordinate, $0.coordinate)) }
            .filter { $0.1 <= maxKm }
            .min { $0.1 < $1.1 }?.0
    }

    static func truth(_ s: Station) -> [SkillMetric: Double] {
        [.temp: s.tempC, .wind: s.windKmh]
    }
}
