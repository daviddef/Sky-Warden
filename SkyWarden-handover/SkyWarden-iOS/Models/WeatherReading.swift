// Sky Warden — WeatherReading
// Raw data from a single weather source.
//
// A "source" is a genuinely independent forecast, not a reseller. Six of them are
// the world's major numerical weather models (served by Open-Meteo in one keyless
// call); the rest are commercial/platform forecasts and a national observation
// network. Independence is the point: sources that share an upstream model agree
// because they're the same model, which would inflate the confidence score.
//
// Sources report only what they measure. Anything a source doesn't publish is
// `nil` — never a stand-in zero, which would corrupt the consensus and raise a
// false "sources disagree" flag.

import Foundation

// MARK: - Source identity
enum WeatherSource: String, CaseIterable, Identifiable {
    // Independent numerical weather models (one Open-Meteo request, no key)
    case ecmwf = "ECMWF"
    case gfs   = "GFS"
    case icon  = "ICON"
    case metno = "MET Norway"
    case gem   = "GEM"
    case ukmo  = "UK Met Office"
    // Commercial / platform forecasts
    case openWeather = "OpenWeather"
    case weatherKit  = "WeatherKit"
    // National observation network
    case bom = "BOM"

    var id: String { rawValue }

    /// Open-Meteo model identifier, for the sources that are NWP models.
    var openMeteoModel: String? {
        switch self {
        case .ecmwf: "ecmwf_ifs025"
        case .gfs:   "gfs_seamless"
        case .icon:  "icon_seamless"
        case .metno: "metno_seamless"
        case .gem:   "gem_seamless"
        case .ukmo:  "ukmo_seamless"
        default:     nil
        }
    }

    /// The six models fetched together in a single Open-Meteo request.
    static var models: [WeatherSource] { allCases.filter { $0.openMeteoModel != nil } }

    var short: String {
        switch self {
        case .ecmwf: "ECM"; case .gfs: "GFS"; case .icon: "ICON"
        case .metno: "MET"; case .gem: "GEM"; case .ukmo: "UKMO"
        case .openWeather: "OW"; case .weatherKit: "WK"; case .bom: "BOM"
        }
    }

    /// Forecast, or measurement of what is actually happening. This is the one
    /// distinction that changes how you read a number: when BOM says 19° and the
    /// models say 22°, BOM is not a dissenting opinion — it is the thermometer.
    enum Kind: Hashable { case forecast, observation }

    var kind: Kind { self == .bom ? .observation : .forecast }

    /// Nine sources used to carry nine hues. They could not be told apart: a
    /// search over OKLCH found the best achievable nine-way separation was
    /// ΔE 4.8 under protanopia, against a floor of 8 — because protan/deutan
    /// vision collapses the hue circle onto one axis, and no nine hues survive
    /// it. The shipped palette measured ΔE 8.6 (GEM vs MET Norway).
    ///
    /// So colour stopped pretending to identify the source and now encodes the
    /// only thing about a source that changes its meaning. Which source it is
    /// comes from the short label printed beside every dot. Measured with the
    /// dataviz checker: these two separate at ΔE 29.4 under protanopia, and
    /// neither collides with the comfort ramp (worst all-pairs ΔE 15.2, which is
    /// good↔poor itself).
    var colorHex: String {
        switch kind {
        case .forecast:    "5BA3D4"   // blue — a model's opinion
        case .observation: "C9E0F0"   // near-white ink — measured, not predicted
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openWeather, .weatherKit: true
        default: false
        }
    }

    /// Who runs the model / service — shown in Settings and the Sources tab.
    var setupNote: String {
        switch self {
        case .ecmwf: "European Centre · global model · free"
        case .gfs:   "NOAA, United States · global model · free"
        case .icon:  "DWD, Germany · global model · free"
        case .metno: "MET Norway · global model · free"
        case .gem:   "Environment Canada · global model · free"
        case .ukmo:  "UK Met Office · global model · free"
        case .openWeather: "Free tier: 1,000 calls/day"
        case .weatherKit:  "Free with Apple Developer account"
        case .bom:         "Australian Bureau of Meteorology · observations"
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
    /// `nil` when the source publishes no probability of precipitation
    /// (UK Met Office; BOM, which reports observations rather than a forecast).
    let rainProbability: Double? // 0–100
    let rainAmount: Double       // mm/hr

    // Wind
    let windSpeed: Double        // km/h
    let windGust: Double?        // km/h
    let windDirection: Int       // degrees 0–360

    // Atmosphere
    let humidity: Double         // 0–100
    /// `nil` when the source doesn't measure UV (most NWP models, BOM).
    let uvIndex: Double?
    let visibility: Double?      // km
    let pressure: Double?        // hPa

    // Condition
    let condition: WeatherCondition

    var hourlyForecast: [HourlyReading]
    var dailyForecast: [DailyReading]

    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 600 }
}

// MARK: - Hourly reading
struct HourlyReading: Identifiable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let rainProbability: Double?
    let rainAmount: Double
    let windSpeed: Double
    let condition: WeatherCondition
    let uvIndex: Double?
}

// MARK: - Daily reading
struct DailyReading: Identifiable {
    let id = UUID()
    let date: Date
    let tempMax: Double
    let tempMin: Double
    let rainProbability: Double?
    let rainAmount: Double
    let windSpeed: Double
    let condition: WeatherCondition
    let uvIndexMax: Double?
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
