// SkyWarden — Tide & Moon Services

import Foundation
import CoreLocation

// MARK: - WorldTides Service
// Docs: https://www.worldtides.info/api
// Cost: ~$3/mo for 1000 API hits (very low — cache aggressively)

struct WorldTidesService {

    private let baseURL = "https://www.worldtides.info/api/v3"
    private let apiKey: String

    init() {
        self.apiKey = Bundle.main.object(forInfoDictionaryKey: "WORLDTIDES_API_KEY") as? String ?? ""
    }

    /// Goes through the disk cache. The aggregator asked for tides on every
    /// 10-minute weather refresh, on every forced pull-to-refresh, on every
    /// background wake and on every cold launch — each one a paid call returning
    /// identical numbers, because tides are astronomical and we fetch two days
    /// at a time. The 6-hour TTL cuts that to ~4 calls/day/device worst case.
    func fetch(location: CLLocation, days: Int = 2) async throws -> TideDay {
        try await DiskCache.through(key: DiskCache.gridKey("tides", location), ttl: CacheTTL.tides) {
            try await fetchUncached(location: location, days: days)
        }
    }

    func fetchUncached(location: CLLocation, days: Int = 2) async throws -> TideDay {
        guard WeatherProxy.isEnabled || !apiKey.isEmpty else {
            throw ServiceError.missingData("WORLDTIDES_API_KEY")
        }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let items: [URLQueryItem] = [
            .init(name: "heights",  value: ""),
            .init(name: "extremes", value: ""),
            .init(name: "lat",      value: "\(lat)"),
            .init(name: "lon",      value: "\(lon)"),
            .init(name: "days",     value: "\(days)"),
            .init(name: "datum",    value: "LAT"),  // Lowest Astronomical Tide
        ]

        guard let request = WeatherProxy.request(source: "worldtides", directBase: baseURL,
                                                 items: items, keyParam: "key", keyValue: apiKey) else {
            throw ServiceError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let raw = try JSONDecoder().decode(WorldTidesResponse.self, from: data)
        return try parse(raw, location: location)
    }

    private func parse(_ r: WorldTidesResponse, location: CLLocation) throws -> TideDay {
        let events: [TideEvent] = (r.extremes ?? []).prefix(8).map { e in
            TideEvent(
                time:   Date(timeIntervalSince1970: TimeInterval(e.dt)),
                height: e.height,
                type:   e.type == "High" ? .high : .low
            )
        }

        // Build curve from height samples
        let curve: [TideCurvePoint] = (r.heights ?? []).map { h in
            TideCurvePoint(
                time:   Date(timeIntervalSince1970: TimeInterval(h.dt)),
                height: h.height
            )
        }

        // WorldTides returns the station as a name string; distance isn't
        // provided without the stations dataset, so derive it from the
        // response coordinate (the actual station location it resolved to).
        let respLat = r.responseLat ?? location.coordinate.latitude
        let respLon = r.responseLon ?? location.coordinate.longitude
        let distanceKm = location.distance(from: CLLocation(latitude: respLat, longitude: respLon)) / 1000
        let stationName = (r.station?.isEmpty == false) ? r.station! : "Nearest station"
        let station = TideStation(
            id:          stationName,
            name:        stationName,
            latitude:    respLat,
            longitude:   respLon,
            distanceKm:  distanceKm
        )

        return TideDay(
            date:         Date(),
            events:       events,
            curvePoints:  curve,
            station:      station
        )
    }
}

// MARK: - WorldTides response models
private struct WorldTidesResponse: Decodable {
    let extremes:    [WTExtreme]?
    let heights:     [WTHeight]?
    let station:     String?     // WorldTides returns the station NAME as a string
    let responseLat: Double?
    let responseLon: Double?
}
private struct WTExtreme: Decodable { let dt: Int; let height: Double; let type: String }
private struct WTHeight:  Decodable { let dt: Int; let height: Double }

// MARK: - Moon Service (calculation-based, no API needed)
// Uses standard astronomical algorithms (Jean Meeus, Astronomical Algorithms)

struct MoonService {

    func moonData(for date: Date = Date()) -> MoonData {
        let jd = julianDay(from: date)
        let age = moonAge(julianDay: jd)
        let illumination = moonIllumination(age: age)
        let phase = MoonData.MoonPhase.from(age: age)

        let nextFull = nextPhaseDate(after: date, targetAge: 14.765)
        let nextNew  = nextPhaseDate(after: date, targetAge: 0)

        let rise = moonRise(julianDay: jd)
        let set  = moonSet(julianDay: jd)

        return MoonData(
            date:          date,
            phase:         phase,
            illumination:  illumination,
            age:           age,
            riseTime:      rise,
            setTime:       set,
            nextFullMoon:  nextFull,
            nextNewMoon:   nextNew
        )
    }

    // MARK: - Astronomical calculations

    /// Julian Day Number from Date
    private func julianDay(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Moon age in days (0 = new moon, 14.765 = full moon, 29.53 = next new)
    private func moonAge(julianDay jd: Double) -> Double {
        let knownNewMoon = 2451549.5    // Jan 6, 2000 new moon
        let synodicPeriod = 29.53058867
        let daysSince = jd - knownNewMoon
        return daysSince.truncatingRemainder(dividingBy: synodicPeriod).magnitude
            .truncatingRemainder(dividingBy: synodicPeriod)
    }

    /// Illumination fraction (0.0–1.0) from moon age
    private func moonIllumination(age: Double) -> Double {
        let synodicPeriod = 29.53058867
        let phase = (age / synodicPeriod) * 2 * .pi
        return (1 - cos(phase)) / 2
    }

    /// Approximate date of next moon phase at targetAge days
    private func nextPhaseDate(after date: Date, targetAge: Double) -> Date {
        let synodicPeriod: Double = 29.53058867 * 86400  // seconds
        var candidate = date
        let stepSize: Double = 3600  // 1 hour steps
        for _ in 0..<(30 * 24) {    // search up to 30 days ahead
            candidate = candidate.addingTimeInterval(stepSize)
            let jd  = julianDay(from: candidate)
            let age = moonAge(julianDay: jd)
            if abs(age - targetAge) < 0.1 { return candidate }
        }
        return date.addingTimeInterval(synodicPeriod / 2)
    }

    /// Very rough moon rise (±30 min accuracy — use an API for precision)
    private func moonRise(julianDay jd: Double) -> Date? {
        // Simplified: returns nil; replace with SunCalc algorithm for production
        return nil
    }

    private func moonSet(julianDay jd: Double) -> Date? {
        return nil
    }
}

// MARK: - Sun Service (using Open-Meteo's daily sunrise/sunset)
// Sunrise/sunset come free from Open-Meteo's daily response — no separate service needed.
// The OpenMeteoService already extracts these into DailyReading.sunrise / .sunset.

// MARK: - Open-Meteo Marine tides (free, keyless)
//
// WorldTides bills per call and ran out of credits. Open-Meteo's Marine API gives
// `sea_level_height_msl` — the tidal sea level relative to mean sea level — free,
// keyless, and worldwide. We read the hourly curve and find the highs and lows
// ourselves (parabolic interpolation puts the turning points to sub-hour
// accuracy), producing the same TideDay the rest of the app already consumes.

struct OpenMeteoTideService {
    private let base = "https://marine-api.open-meteo.com/v1/marine"

    func fetch(location: CLLocation, days: Int = 2) async -> TideDay? {
        let key = DiskCache.gridKey("tides-om", location)
        if let hit = DiskCache.load(TideDay.self, key: key, ttl: CacheTTL.tides) { return hit }

        guard var comps = URLComponents(string: base) else { return nil }
        comps.queryItems = [
            .init(name: "latitude",      value: String(location.coordinate.latitude)),
            .init(name: "longitude",     value: String(location.coordinate.longitude)),
            .init(name: "hourly",        value: "sea_level_height_msl"),
            .init(name: "timeformat",    value: "unixtime"),
            .init(name: "timezone",      value: "GMT"),
            .init(name: "forecast_days", value: String(days)),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MarineResponse.self, from: data)
        else { return nil }

        let points: [TideCurvePoint] = zip(decoded.hourly.time, decoded.hourly.sea_level_height_msl)
            .compactMap { t, h in
                guard let h else { return nil }
                return TideCurvePoint(time: Date(timeIntervalSince1970: TimeInterval(t)), height: h)
            }
        // A grid cell with no ocean nearby returns all-nil — that's genuinely "no
        // tide here", so bail rather than invent a flat line.
        guard points.count > 3 else { return nil }

        let station = TideStation(id: "open-meteo", name: "Open-Meteo marine model",
                                  latitude: location.coordinate.latitude,
                                  longitude: location.coordinate.longitude, distanceKm: 0)
        let day = TideDay(date: Date(), events: extremes(points), curvePoints: points, station: station)
        DiskCache.save(day, key: key)
        return day
    }

    /// Highs and lows are the turning points of the curve; parabolic interpolation
    /// on the three samples around each one recovers the time and height between
    /// the hourly grid (a tide peak rarely lands on the hour).
    private func extremes(_ p: [TideCurvePoint]) -> [TideEvent] {
        var out: [TideEvent] = []
        for i in 1..<(p.count - 1) {
            let a = p[i - 1].height, b = p[i].height, c = p[i + 1].height
            let isHigh = b > a && b >= c
            let isLow  = b < a && b <= c
            guard isHigh || isLow else { continue }
            let denom = a - 2 * b + c
            let offset = denom != 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / denom)) : 0
            let interval = p[i + 1].time.timeIntervalSince(p[i].time)
            out.append(TideEvent(time: p[i].time.addingTimeInterval(offset * interval),
                                 height: b - 0.25 * (a - c) * offset,
                                 type: isHigh ? .high : .low))
        }
        return out
    }

    private struct MarineResponse: Decodable {
        struct Hourly: Decodable { let time: [Int]; let sea_level_height_msl: [Double?] }
        let hourly: Hourly
    }
}
