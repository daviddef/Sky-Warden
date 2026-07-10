// SkyWarden — ConsensusWeather
// The merged, scored output the UI displays

import Foundation

// MARK: - Disagreement severity
enum DisagreementSeverity: Int, Comparable {
    case none  = 0
    case minor = 1   // ⚠️  sources vary slightly
    case major = 2   // 🚨  sources strongly disagree

    static func < (lhs: DisagreementSeverity, rhs: DisagreementSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .none:  return ""
        case .minor: return "⚠️"
        case .major: return "🚨"
        }
    }

    var label: String {
        switch self {
        case .none:  return "All sources agree"
        case .minor: return "Sources vary"
        case .major: return "Sources strongly disagree"
        }
    }
}

// MARK: - Per-field disagreement
struct FieldDisagreement: Identifiable {
    let id = UUID()
    let fieldKey: String           // "temperature", "rain", "wind"
    let fieldLabel: String         // "Temperature"
    let severity: DisagreementSeverity
    let perSource: [WeatherSource: String]   // source → display string

    var sortedSources: [(WeatherSource, String)] {
        perSource.sorted { $0.key.rawValue < $1.key.rawValue }
    }
}

// MARK: - Consensus (merged) weather
struct ConsensusWeather {
    // Provenance
    let sources: [WeatherSource]          // which sources contributed
    let fetchedAt: Date
    let confidence: Double                // 0.0 – 1.0
    let disagreements: [FieldDisagreement]
    let worstSeverity: DisagreementSeverity

    // Current conditions (consensus values)
    let temperature: Double
    let feelsLike: Double
    let rainProbability: Double
    let rainAmount: Double
    let windSpeed: Double
    let windDirection: Int
    let humidity: Double
    let uvIndex: Double
    let condition: WeatherCondition

    // Ranges (when sources disagree)
    let temperatureRange: ClosedRange<Double>?
    let rainRange: ClosedRange<Double>?
    let windRange: ClosedRange<Double>?

    // Forecasts (merged)
    var hourlyForecast: [ConsensusHourly]
    var dailyForecast: [ConsensusDaily]

    // Raw readings for Sources tab
    let rawReadings: [WeatherReading]

    // MARK: - Computed helpers
    var hasDisagreements: Bool { !disagreements.isEmpty }

    var confidenceLabel: String {
        switch confidence {
        case 0.85...: return "High confidence"
        case 0.6..<0.85: return "Moderate confidence"
        default: return "Low confidence — check sources"
        }
    }

    var temperatureDisplay: String { "\(Int(temperature.rounded()))°" }
    var rainDisplay: String { "\(Int(rainProbability.rounded()))%" }
    var windDisplay: String { "\(Int(windSpeed.rounded())) \(windDirection.compassBearing)" }

    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 600 }
    var lastUpdatedLabel: String {
        let secs = Int(Date().timeIntervalSince(fetchedAt))
        if secs < 60 { return "Just now" }
        if secs < 3600 { return "\(secs / 60) min ago" }
        return "\(secs / 3600)h ago"
    }
}

// MARK: - Hourly consensus
struct ConsensusHourly: Identifiable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let rainProbability: Double
    let condition: WeatherCondition
    let windSpeed: Double
    let hasDisagreement: Bool

    var hourLabel: String {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f.string(from: time).lowercased()
    }
}

// MARK: - Daily consensus
struct ConsensusDaily: Identifiable {
    let id = UUID()
    let date: Date
    let tempMax: Double
    let tempMin: Double
    let rainProbability: Double
    let windSpeed: Double
    let condition: WeatherCondition
    let hasDisagreement: Bool

    var dayLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tmrw" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

// MARK: - Fetch state
enum FetchState {
    case idle
    case loading
    case loaded(ConsensusWeather)
    case partialLoad(ConsensusWeather, [WeatherSource])  // loaded but some sources failed
    case failed(Error)
}
