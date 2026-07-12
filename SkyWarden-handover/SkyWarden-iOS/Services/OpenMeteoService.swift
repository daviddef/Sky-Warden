// Sky Warden — Open-Meteo multi-model service
// Free, no API key.
//
// One request returns the SAME variables from six independent numerical weather
// models (ECMWF, NOAA GFS, DWD ICON, MET Norway, Environment Canada GEM, UK Met
// Office). Each becomes its own source, so the disagreement engine compares the
// world's major forecast models rather than several resellers of one model.
//
// Not every model publishes every variable — UKMO has no precipitation
// probability, and only GFS and MET Norway publish UV. Those come back `nil`.
//
// Response keys are suffixed per model (`temperature_2m_ecmwf_ifs025`), which is
// dynamic, so we read the JSON as a dictionary rather than via Decodable.

import Foundation
import CoreLocation

struct OpenMeteoService {

    private let baseURL = "https://api.open-meteo.com/v1/forecast"

    /// The model whose hourly/daily detail drives the Today/Week/Scene tabs.
    static let primary: WeatherSource = .ecmwf

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> [WeatherReading] {
        let items: [URLQueryItem] = [
            .init(name: "latitude",           value: "\(location.coordinate.latitude)"),
            .init(name: "longitude",          value: "\(location.coordinate.longitude)"),
            .init(name: "hourly",             value: hourlyFields),
            .init(name: "daily",              value: dailyFields),
            .init(name: "models",             value: WeatherSource.models.compactMap(\.openMeteoModel).joined(separator: ",")),
            .init(name: "timezone",           value: "auto"),
            .init(name: "forecast_days",      value: "7"),
            .init(name: "wind_speed_unit",    value: "kmh"),
            .init(name: "temperature_unit",   value: "celsius"),
            .init(name: "precipitation_unit", value: "mm"),
        ]

        guard let request = WeatherProxy.request(source: "openmeteo", directBase: baseURL, items: items) else {
            throw ServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.decodingError("Open-Meteo root")
        }
        return parse(root)
    }

    // MARK: - Parse
    private func parse(_ root: [String: Any]) -> [WeatherReading] {
        let hourly = root["hourly"] as? [String: Any] ?? [:]
        let daily  = root["daily"]  as? [String: Any] ?? [:]
        let hourTimes = (hourly["time"] as? [String] ?? []).compactMap(Self.omTime.date(from:))
        let dayTimes  = (daily["time"] as? [String] ?? []).compactMap(Self.omDay.date(from:))
        guard !hourTimes.isEmpty else { return [] }

        // The hour that best represents "now".
        let now = Date()
        let nowIdx = hourTimes.lastIndex { $0 <= now } ?? 0

        return WeatherSource.models.compactMap { source -> WeatherReading? in
            guard let model = source.openMeteoModel else { return nil }

            let temp    = doubles(hourly, "temperature_2m", model)
            let feels   = doubles(hourly, "apparent_temperature", model)
            let hum     = doubles(hourly, "relative_humidity_2m", model)
            let pop     = doubles(hourly, "precipitation_probability", model)
            let precip  = doubles(hourly, "precipitation", model)
            let code    = doubles(hourly, "weather_code", model)
            let wind    = doubles(hourly, "wind_speed_10m", model)
            let windDir = doubles(hourly, "wind_direction_10m", model)
            let gust    = doubles(hourly, "wind_gusts_10m", model)
            let uv      = doubles(hourly, "uv_index", model)
            let press   = doubles(hourly, "surface_pressure", model)

            // A model that returned no temperature simply isn't available here.
            guard let current = temp[safe: nowIdx] ?? nil else { return nil }

            let hourlyReadings: [HourlyReading] = (nowIdx..<min(nowIdx + 24, hourTimes.count)).map { i in
                HourlyReading(
                    time:            hourTimes[i],
                    temperature:     temp[safe: i]?.flatMap { $0 } ?? current,
                    rainProbability: pop[safe: i]?.flatMap { $0 },
                    rainAmount:      precip[safe: i]?.flatMap { $0 } ?? 0,
                    windSpeed:       wind[safe: i]?.flatMap { $0 } ?? 0,
                    condition:       Self.condition(from: Int(code[safe: i]?.flatMap { $0 } ?? 0)),
                    uvIndex:         uv[safe: i]?.flatMap { $0 }
                )
            }

            let dTempMax = doubles(daily, "temperature_2m_max", model)
            let dTempMin = doubles(daily, "temperature_2m_min", model)
            let dPop     = doubles(daily, "precipitation_probability_max", model)
            let dSum     = doubles(daily, "precipitation_sum", model)
            let dWind    = doubles(daily, "wind_speed_10m_max", model)
            let dCode    = doubles(daily, "weather_code", model)
            let dUV      = doubles(daily, "uv_index_max", model)
            let dSunrise = strings(daily, "sunrise", model)
            let dSunset  = strings(daily, "sunset", model)

            let dailyReadings: [DailyReading] = dayTimes.indices.map { i in
                DailyReading(
                    date:            dayTimes[i],
                    tempMax:         dTempMax[safe: i]?.flatMap { $0 } ?? current,
                    tempMin:         dTempMin[safe: i]?.flatMap { $0 } ?? current,
                    rainProbability: dPop[safe: i]?.flatMap { $0 },
                    rainAmount:      dSum[safe: i]?.flatMap { $0 } ?? 0,
                    windSpeed:       dWind[safe: i]?.flatMap { $0 } ?? 0,
                    condition:       Self.condition(from: Int(dCode[safe: i]?.flatMap { $0 } ?? 0)),
                    uvIndexMax:      dUV[safe: i]?.flatMap { $0 },
                    sunrise:         dSunrise[safe: i].flatMap { $0 }.flatMap(Self.omTime.date(from:)),
                    sunset:          dSunset[safe: i].flatMap { $0 }.flatMap(Self.omTime.date(from:))
                )
            }

            return WeatherReading(
                source:          source,
                fetchedAt:       Date(),
                temperature:     current,
                feelsLike:       feels[safe: nowIdx]?.flatMap { $0 } ?? current,
                tempMin:         dailyReadings.first?.tempMin,
                tempMax:         dailyReadings.first?.tempMax,
                rainProbability: pop[safe: nowIdx]?.flatMap { $0 },
                rainAmount:      precip[safe: nowIdx]?.flatMap { $0 } ?? 0,
                windSpeed:       wind[safe: nowIdx]?.flatMap { $0 } ?? 0,
                windGust:        gust[safe: nowIdx]?.flatMap { $0 },
                windDirection:   Int(windDir[safe: nowIdx]?.flatMap { $0 } ?? 0),
                humidity:        hum[safe: nowIdx]?.flatMap { $0 } ?? 0,
                uvIndex:         uv[safe: nowIdx]?.flatMap { $0 },
                visibility:      nil,
                pressure:        press[safe: nowIdx]?.flatMap { $0 },
                condition:       Self.condition(from: Int(code[safe: nowIdx]?.flatMap { $0 } ?? 0)),
                hourlyForecast:  hourlyReadings,
                dailyForecast:   dailyReadings
            )
        }
    }

    // MARK: - Dynamic key access
    /// `nil` entries are genuine JSON nulls — variables the model doesn't publish.
    private func doubles(_ dict: [String: Any], _ base: String, _ model: String) -> [Double?] {
        (dict["\(base)_\(model)"] as? [Any])?.map { $0 as? Double } ?? []
    }
    private func strings(_ dict: [String: Any], _ base: String, _ model: String) -> [String?] {
        (dict["\(base)_\(model)"] as? [Any])?.map { $0 as? String } ?? []
    }

    // Open-Meteo returns naive local times ("2026-07-10T13:00") that
    // ISO8601DateFormatter rejects, so parse with explicit formats.
    static let omTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()
    static let omDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - WMO code → WeatherCondition
    static func condition(from code: Int) -> WeatherCondition {
        switch code {
        case 0:          return .clearSky
        case 1:          return .mostlyClear
        case 2:          return .partlyCloudy
        case 3:          return .overcast
        case 45, 48:     return .fog
        case 51, 53, 55: return .drizzle
        case 61, 63:     return .rain
        case 65, 66, 67: return .heavyRain
        case 71...77:    return .snow
        case 80, 81:     return .rain
        case 82:         return .heavyRain
        case 85, 86:     return .snow
        case 95...99:    return .thunderstorm
        default:         return .partlyCloudy
        }
    }

    // MARK: - Field lists
    private var hourlyFields: String {
        ["temperature_2m","apparent_temperature","relative_humidity_2m",
         "precipitation_probability","precipitation","weather_code",
         "wind_speed_10m","wind_direction_10m","wind_gusts_10m",
         "uv_index","surface_pressure"].joined(separator: ",")
    }
    private var dailyFields: String {
        ["weather_code","temperature_2m_max","temperature_2m_min",
         "precipitation_sum","precipitation_probability_max",
         "wind_speed_10m_max","uv_index_max","sunrise","sunset"].joined(separator: ",")
    }
}

// MARK: - Errors
enum ServiceError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case missingData(String)
    case decodingError(String)
    /// The source doesn't cover this location (e.g. BOM outside Australia).
    /// Not a failure — the aggregator skips it silently.
    case notApplicable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL"
        case .httpError(let c):    return "HTTP \(c)"
        case .missingData(let f):  return "Missing field: \(f)"
        case .decodingError(let m):return "Decode error: \(m)"
        case .notApplicable(let m):return m
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Precipitation nowcast (the "rain starts in ~15 min" job)
// ────────────────────────────────────────────────────────────────────────────
// The most-missed thing since Dark Sky: minute-scale "when does the rain start /
// stop, here". Open-Meteo's minutely_15 gives 15-min precipitation for the coming
// two hours at the exact point — cheaper and more precise than reading it off a
// radar tile — and it already routes through our cache.

struct PrecipNowcast: Equatable {
    /// 15-minute precipitation (mm) starting at the current block.
    let steps: [Step]
    struct Step: Equatable { let time: Date; let mm: Double }

    /// Any measurable rain in a 15-min block. Deliberately low so a light shower
    /// still triggers the "starting soon" heads-up.
    static let wet = 0.1

    var rainingNow: Bool { (steps.first?.mm ?? 0) >= Self.wet }

    /// The next flip between wet and dry in the window, and when.
    var nextChange: (starts: Bool, at: Date)? {
        guard let now = steps.first else { return nil }
        let nowWet = now.mm >= Self.wet
        for s in steps.dropFirst() where (s.mm >= Self.wet) != nowWet {
            return (starts: !nowWet, at: s.time)
        }
        return nil
    }

    /// Minutes until that change, rounded to 5, or nil if there's no change ahead.
    var minutesToChange: Int? {
        guard let c = nextChange else { return nil }
        let m = Int((c.at.timeIntervalSinceNow / 60 / 5).rounded()) * 5
        return m >= 0 ? m : nil
    }

    /// The heads-up line, or nil when there's nothing worth saying (dry and staying
    /// dry, or raining with no end in the window — the hourly view covers those).
    var headline: String? {
        guard let change = nextChange, let mins = minutesToChange else { return nil }
        let when = mins <= 5 ? "in a few minutes" : "in about \(mins) min"
        return change.starts ? "Rain starting \(when)" : "Rain easing \(when)"
    }
}

struct NowcastService {
    private let baseURL = "https://api.open-meteo.com/v1/forecast"

    func fetch(location: CLLocation) async -> PrecipNowcast? {
        let items: [URLQueryItem] = [
            .init(name: "latitude",             value: String(location.coordinate.latitude)),
            .init(name: "longitude",            value: String(location.coordinate.longitude)),
            .init(name: "minutely_15",          value: "precipitation"),
            .init(name: "forecast_minutely_15", value: "8"),
            .init(name: "past_minutely_15",     value: "0"),
            .init(name: "precipitation_unit",   value: "mm"),
            .init(name: "timeformat",           value: "unixtime"),
            .init(name: "timezone",             value: "GMT"),
        ]
        guard let request = WeatherProxy.request(source: "openmeteo", directBase: baseURL, items: items),
              let (data, resp) = try? await URLSession.shared.data(for: request),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(NowcastResponse.self, from: data)
        else { return nil }

        let steps = zip(decoded.minutely_15.time, decoded.minutely_15.precipitation)
            .map { PrecipNowcast.Step(time: Date(timeIntervalSince1970: TimeInterval($0)), mm: $1) }
        return steps.isEmpty ? nil : PrecipNowcast(steps: steps)
    }

    private struct NowcastResponse: Decodable {
        struct M15: Decodable { let time: [Int]; let precipitation: [Double] }
        let minutely_15: M15
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Air quality + pollen
// ────────────────────────────────────────────────────────────────────────────
// Now baseline, not premium — Apple ships it, so users expect it. Open-Meteo's
// air-quality API is keyless and global for AQI/particulates; pollen is CAMS
// Europe only, so it appears where it exists and is silent elsewhere. Different
// host from the forecast proxy, so this calls direct with a 30-min client cache.

struct AirQuality: Codable, Equatable {
    let usAqi: Double
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?
    let no2: Double?
    let pollen: [String: Double]     // e.g. "grass_pollen" → grains/m³ (Europe)

    var category: String {
        switch usAqi {
        case ..<51:  return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for sensitive"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very unhealthy"
        default:     return "Hazardous"
        }
    }
    var colorHex: String {
        switch usAqi {
        case ..<51:  return "3DD68C"   // green
        case ..<101: return "F5A623"   // amber
        case ..<151: return "FF8C42"   // orange
        case ..<201: return "E05555"   // red
        case ..<301: return "A78BFA"   // purple
        default:     return "8B5A6B"   // maroon
        }
    }
    /// Fraction along a 0–200 dial, clamped — the healthy half is the first quarter.
    var dialFraction: Double { min(1, max(0, usAqi / 200)) }

    /// The most-elevated pollen, if any is worth mentioning (Europe only).
    var topPollen: (name: String, level: String)? {
        guard let hit = pollen.filter({ $0.value >= 20 }).max(by: { $0.value < $1.value }) else { return nil }
        let level = hit.value >= 150 ? "very high" : hit.value >= 50 ? "high" : "moderate"
        return (hit.key.replacingOccurrences(of: "_pollen", with: ""), level)
    }
}

struct AirQualityService {
    private let base = "https://air-quality-api.open-meteo.com/v1/air-quality"

    func fetch(location: CLLocation) async -> AirQuality? {
        let key = DiskCache.gridKey("aqi", location, precision: 0.1)
        if let hit = DiskCache.load(AirQuality.self, key: key, ttl: 1800) { return hit }

        guard var comps = URLComponents(string: base) else { return nil }
        comps.queryItems = [
            .init(name: "latitude",  value: String(location.coordinate.latitude)),
            .init(name: "longitude", value: String(location.coordinate.longitude)),
            .init(name: "current",   value: "us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide,grass_pollen,birch_pollen,ragweed_pollen"),
            .init(name: "timezone",  value: "GMT"),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let c = root["current"] as? [String: Any],
              let aqi = (c["us_aqi"] as? NSNumber)?.doubleValue
        else { return nil }

        func d(_ k: String) -> Double? { (c[k] as? NSNumber)?.doubleValue }
        var pollen: [String: Double] = [:]
        for p in ["grass_pollen", "birch_pollen", "ragweed_pollen"] { if let v = d(p) { pollen[p] = v } }

        let aq = AirQuality(usAqi: aqi, pm25: d("pm2_5"), pm10: d("pm10"),
                            ozone: d("ozone"), no2: d("nitrogen_dioxide"), pollen: pollen)
        DiskCache.save(aq, key: key)
        return aq
    }
}
