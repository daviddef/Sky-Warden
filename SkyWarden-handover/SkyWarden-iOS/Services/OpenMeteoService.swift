// SkyWarden — Open-Meteo Service
// Free, no API key. Excellent hourly resolution.
// Docs: https://open-meteo.com/en/docs

import Foundation
import CoreLocation

struct OpenMeteoService {

    private let baseURL = "https://api.open-meteo.com/v1/forecast"

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> WeatherReading {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let items: [URLQueryItem] = [
            .init(name: "latitude",          value: "\(lat)"),
            .init(name: "longitude",         value: "\(lon)"),
            .init(name: "current",           value: currentFields),
            .init(name: "hourly",            value: hourlyFields),
            .init(name: "daily",             value: dailyFields),
            .init(name: "timezone",          value: "auto"),
            .init(name: "forecast_days",     value: "7"),
            .init(name: "wind_speed_unit",   value: "kmh"),
            .init(name: "temperature_unit",  value: "celsius"),
            .init(name: "precipitation_unit",value: "mm"),
        ]

        guard let request = WeatherProxy.request(source: "openmeteo", directBase: baseURL, items: items) else {
            throw ServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let raw = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return try parse(raw)
    }

    // MARK: - Parse
    private func parse(_ r: OpenMeteoResponse) throws -> WeatherReading {
        guard let current = r.current else { throw ServiceError.missingData("current") }

        let wmoCode    = current.weatherCode ?? 0
        let condition  = condition(from: wmoCode)
        let windDir    = Int(current.windDirection10m ?? 0)
        let temp       = current.temperature2m ?? 0
        let apparent   = current.apparentTemperature ?? temp
        let humidity   = current.relativeHumidity2m ?? 0
        let windSpeed  = current.windSpeed10m ?? 0
        let precipitation = current.precipitation ?? 0

        // Hourly
        let hourlyReadings = parseHourly(r.hourly)

        // Daily
        let dailyReadings = parseDaily(r.daily)

        return WeatherReading(
            source:          .openMeteo,
            fetchedAt:       Date(),
            temperature:     temp,
            feelsLike:       apparent,
            tempMin:         dailyReadings.first?.tempMin,
            tempMax:         dailyReadings.first?.tempMax,
            rainProbability: Double(r.hourly?.precipitationProbability?.first ?? 0),
            rainAmount:      precipitation,
            windSpeed:       windSpeed,
            windGust:        current.windGusts10m,
            windDirection:   windDir,
            humidity:        humidity,
            uvIndex:         r.daily?.uvIndexMax?.first,
            visibility:      nil,
            pressure:        current.surfacePressure,
            condition:       condition,
            hourlyForecast:  hourlyReadings,
            dailyForecast:   dailyReadings
        )
    }

    // Open-Meteo returns naive local times like "2026-07-10T13:00" (no seconds,
    // no offset) — ISO8601DateFormatter rejects these, so use an explicit format.
    private static let omTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    private func parseHourly(_ h: OpenMeteoHourly?) -> [HourlyReading] {
        guard let h, let times = h.time else { return [] }
        let iso = Self.omTime

        return times.prefix(24).enumerated().compactMap { (i, timeStr) in
            guard let date = iso.date(from: timeStr) else { return nil }
            return HourlyReading(
                time:             date,
                temperature:      h.temperature2m?[safe: i] ?? 0,
                rainProbability:  Double(h.precipitationProbability?[safe: i] ?? 0),
                rainAmount:       h.precipitation?[safe: i] ?? 0,
                windSpeed:        h.windSpeed10m?[safe: i] ?? 0,
                condition:        condition(from: h.weatherCode?[safe: i] ?? 0),
                uvIndex:          h.uvIndex?[safe: i] ?? 0
            )
        }
    }

    private func parseDaily(_ d: OpenMeteoDaily?) -> [DailyReading] {
        guard let d, let times = d.time else { return [] }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return times.enumerated().compactMap { (i, timeStr) in
            guard let date = df.date(from: timeStr) else { return nil }

            var sunrise: Date? = nil
            var sunset: Date? = nil
            let iso = Self.omTime
            if let sr = d.sunrise?[safe: i] { sunrise = iso.date(from: sr) }
            if let ss = d.sunset?[safe: i]  { sunset  = iso.date(from: ss) }

            return DailyReading(
                date:             date,
                tempMax:          d.temperature2mMax?[safe: i] ?? 0,
                tempMin:          d.temperature2mMin?[safe: i] ?? 0,
                rainProbability:  Double(d.precipitationProbabilityMax?[safe: i] ?? 0),
                rainAmount:       d.precipitationSum?[safe: i] ?? 0,
                windSpeed:        d.windSpeed10mMax?[safe: i] ?? 0,
                condition:        condition(from: d.weatherCodeMax?[safe: i] ?? 0),
                uvIndexMax:       d.uvIndexMax?[safe: i] ?? 0,
                sunrise:          sunrise,
                sunset:           sunset
            )
        }
    }

    // MARK: - WMO code → WeatherCondition
    // https://open-meteo.com/en/docs#weathervariables
    private func condition(from code: Int) -> WeatherCondition {
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
    private var currentFields: String {
        ["temperature_2m","apparent_temperature","relative_humidity_2m",
         "precipitation","weather_code","wind_speed_10m","wind_direction_10m",
         "wind_gusts_10m","surface_pressure"].joined(separator: ",")
    }
    private var hourlyFields: String {
        ["temperature_2m","precipitation_probability","precipitation",
         "weather_code","wind_speed_10m","uv_index"].joined(separator: ",")
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

// MARK: - Decodable response models
private struct OpenMeteoResponse: Decodable {
    let current: OpenMeteoCurrent?
    let hourly:  OpenMeteoHourly?
    let daily:   OpenMeteoDaily?
}

private struct OpenMeteoCurrent: Decodable {
    let temperature2m:        Double?
    let apparentTemperature:  Double?
    let relativeHumidity2m:   Double?
    let precipitation:        Double?
    let weatherCode:          Int?
    let windSpeed10m:         Double?
    let windDirection10m:     Double?
    let windGusts10m:         Double?
    let surfacePressure:      Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m       = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity2m  = "relative_humidity_2m"
        case precipitation       = "precipitation"
        case weatherCode         = "weather_code"
        case windSpeed10m        = "wind_speed_10m"
        case windDirection10m    = "wind_direction_10m"
        case windGusts10m        = "wind_gusts_10m"
        case surfacePressure     = "surface_pressure"
    }
}

private struct OpenMeteoHourly: Decodable {
    let time:                      [String]?
    let temperature2m:             [Double]?
    let precipitationProbability:  [Int]?
    let precipitation:             [Double]?
    let weatherCode:               [Int]?
    let windSpeed10m:              [Double]?
    let uvIndex:                   [Double]?

    enum CodingKeys: String, CodingKey {
        case time                     = "time"
        case temperature2m            = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case precipitation            = "precipitation"
        case weatherCode              = "weather_code"
        case windSpeed10m             = "wind_speed_10m"
        case uvIndex                  = "uv_index"
    }
}

private struct OpenMeteoDaily: Decodable {
    let time:                        [String]?
    let weatherCodeMax:              [Int]?
    let temperature2mMax:            [Double]?
    let temperature2mMin:            [Double]?
    let precipitationSum:            [Double]?
    let precipitationProbabilityMax: [Int]?
    let windSpeed10mMax:             [Double]?
    let uvIndexMax:                  [Double]?
    let sunrise:                     [String]?
    let sunset:                      [String]?

    enum CodingKeys: String, CodingKey {
        case time                        = "time"
        case weatherCodeMax              = "weather_code"
        case temperature2mMax            = "temperature_2m_max"
        case temperature2mMin            = "temperature_2m_min"
        case precipitationSum            = "precipitation_sum"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case windSpeed10mMax             = "wind_speed_10m_max"
        case uvIndexMax                  = "uv_index_max"
        case sunrise                     = "sunrise"
        case sunset                      = "sunset"
    }
}
