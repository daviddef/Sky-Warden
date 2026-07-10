// SkyWarden — WeatherReading
// Raw data from a single weather source

import Foundation

// MARK: - Source identity
enum WeatherSource: String, CaseIterable, Identifiable {
    case openMeteo   = "Open-Meteo"
    case openWeather = "OpenWeather"
    case weatherKit  = "WeatherKit"
    case bom         = "BOM"

    var id: String { rawValue }
    var short: String {
        switch self {
        case .openMeteo:   return "OM"
        case .openWeather: return "OW"
        case .weatherKit:  return "WK"
        case .bom:         return "BOM"
        }
    }
    // Source identity palette (HANDOVER.md → Design tokens)
    var colorHex: String {
        switch self {
        case .openMeteo:   return "5BA3D4"   // blue
        case .openWeather: return "F5A623"   // amber
        case .weatherKit:  return "3DD68C"   // Apple green
        case .bom:         return "C084FC"   // purple
        }
    }
    var requiresAPIKey: Bool {
        switch self {
        case .openWeather: return true
        case .weatherKit:  return true       // Apple Developer account + capability
        default:           return false
        }
    }
    /// Human-readable setup note shown in the Sources tab.
    var setupNote: String {
        switch self {
        case .openMeteo:   return "Free · No API key required"
        case .openWeather: return "Free tier: 1,000 calls/day"
        case .weatherKit:  return "Free with Apple Developer account"
        case .bom:         return "Free · Australian Bureau of Meteorology"
        }
    }
}

// MARK: - Condition categories (normalised across sources)
enum WeatherCondition: String, Codable {
    case clearSky       = "Clear"
    case mostlyClear    = "Mostly Clear"
    case partlyCloudy   = "Partly Cloudy"
    case mostlyCloudy   = "Mostly Cloudy"
    case overcast       = "Overcast"
    case drizzle        = "Drizzle"
    case rain           = "Rain"
    case heavyRain      = "Heavy Rain"
    case thunderstorm   = "Thunderstorm"
    case fog            = "Fog"
    case snow           = "Snow"

    var icon: String {
        switch self {
        case .clearSky:     return "sun.max.fill"
        case .mostlyClear:  return "sun.min.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .mostlyCloudy: return "cloud.fill"
        case .overcast:     return "smoke.fill"
        case .drizzle:      return "cloud.drizzle.fill"
        case .rain:         return "cloud.rain.fill"
        case .heavyRain:    return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .fog:          return "cloud.fog.fill"
        case .snow:         return "snowflake"
        }
    }

    var emoji: String {
        switch self {
        case .clearSky:     return "☀️"
        case .mostlyClear:  return "🌤"
        case .partlyCloudy: return "⛅"
        case .mostlyCloudy: return "🌥"
        case .overcast:     return "☁️"
        case .drizzle:      return "🌦"
        case .rain:         return "🌧"
        case .heavyRain:    return "🌧"
        case .thunderstorm: return "⛈"
        case .fog:          return "🌫"
        case .snow:         return "❄️"
        }
    }
}

// MARK: - Single source reading (current conditions)
struct WeatherReading: Identifiable {
    let id = UUID()
    let source: WeatherSource
    let fetchedAt: Date

    // Temperature
    let temperature: Double      // °C
    let feelsLike: Double        // °C
    let tempMin: Double?         // °C (daily)
    let tempMax: Double?         // °C (daily)

    // Precipitation
    let rainProbability: Double  // 0–100
    let rainAmount: Double       // mm/hr

    // Wind
    let windSpeed: Double        // km/h
    let windGust: Double?        // km/h
    let windDirection: Int       // degrees 0–360

    // Atmosphere
    let humidity: Double         // 0–100
    let uvIndex: Double
    let visibility: Double?      // km
    let pressure: Double?        // hPa

    // Condition
    let condition: WeatherCondition

    // Hourly forecast (next 24h)
    var hourlyForecast: [HourlyReading]

    // Daily forecast (next 7 days)
    var dailyForecast: [DailyReading]

    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 600 // 10 minutes
    }
}

// MARK: - Hourly reading
struct HourlyReading: Identifiable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let rainProbability: Double
    let rainAmount: Double
    let windSpeed: Double
    let condition: WeatherCondition
    let uvIndex: Double
}

// MARK: - Daily reading
struct DailyReading: Identifiable {
    let id = UUID()
    let date: Date
    let tempMax: Double
    let tempMin: Double
    let rainProbability: Double
    let rainAmount: Double
    let windSpeed: Double
    let condition: WeatherCondition
    let uvIndexMax: Double
    let sunrise: Date?
    let sunset: Date?
}

// MARK: - Wind direction helper
extension Int {
    /// Converts degrees to compass bearing string
    var compassBearing: String {
        let directions = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                          "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let index = Int((Double(self) / 22.5).rounded()) % 16
        return directions[index]
    }
}
