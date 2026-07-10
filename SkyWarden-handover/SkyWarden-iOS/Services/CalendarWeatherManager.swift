// SkyWarden — Calendar Weather Integration
// Reads Apple Calendar events via EventKit, identifies outdoor events,
// cross-references the 7-day forecast, and produces weather impact warnings.

import Foundation
import EventKit
import CoreLocation

// MARK: - Impact level
enum WeatherImpact: Int, Comparable {
    case clear = 0   // ✅ Good conditions
    case minor = 1   // 🌦 Minor concern
    case watch = 2   // ⚠️ Watch this
    case major = 3   // 🚨 Major impact

    static func < (lhs: WeatherImpact, rhs: WeatherImpact) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .clear: return "✅"
        case .minor: return "🌦"
        case .watch: return "⚠️"
        case .major: return "🚨"
        }
    }

    var label: String {
        switch self {
        case .clear: return "Looking good"
        case .minor: return "Minor concern"
        case .watch: return "Worth watching"
        case .major: return "Major impact"
        }
    }
}

// MARK: - Flagged calendar event
struct WeatherEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let impact: WeatherImpact
    let forecast: ConsensusDaily?      // matching daily forecast
    let warningText: String?
    let hasSourceDisagreement: Bool    // flag if forecast sources disagree for this day

    var dateLabel: String {
        if Calendar.current.isDateInToday(startDate)    { return "Today" }
        if Calendar.current.isDateInTomorrow(startDate) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: startDate)
    }

    var timeLabel: String {
        if isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: startDate)
    }
}

// MARK: - Calendar Weather Manager
@MainActor
final class CalendarWeatherManager: ObservableObject {
    @Published var weatherEvents: [WeatherEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let store = EKEventStore()

    // Keywords that suggest an outdoor event
    private let outdoorKeywords: [String] = [
        "soccer", "football", "cricket", "rugby", "tennis", "golf", "swim",
        "beach", "park", "surf", "paddle", "kayak", "bike", "cycle", "run",
        "walk", "hike", "bbq", "barbecue", "picnic", "outdoor", "garden",
        "pool", "festival", "market", "sport", "training", "race", "event",
        "fishing", "camping", "trail", "athletics", "excursion",
    ]

    // MARK: - Request access
    func requestAccess() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let granted = try? await store.requestFullAccessToEvents()
            authorizationStatus = granted == true ? .fullAccess : .denied
        } else {
            authorizationStatus = status
        }
    }

    // MARK: - Analyse events against forecast
    func analyse(forecast: [ConsensusDaily]) async {
        guard authorizationStatus == .fullAccess else { return }

        // Fetch next 7 days of events from all calendars
        let now   = Date()
        let end   = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        let flagged: [WeatherEvent] = events.compactMap { event in
            guard isOutdoorEvent(event) else { return nil }

            // Find matching daily forecast
            let matchingForecast = forecast.first { daily in
                Calendar.current.isDate(daily.date, inSameDayAs: event.startDate)
            }

            let impact = assessImpact(event: event, forecast: matchingForecast)
            let warning = generateWarning(event: event, forecast: matchingForecast, impact: impact)

            return WeatherEvent(
                id:                   event.eventIdentifier,
                title:                event.title ?? "Untitled",
                startDate:            event.startDate,
                endDate:              event.endDate,
                isAllDay:             event.isAllDay,
                impact:               impact,
                forecast:             matchingForecast,
                warningText:          warning,
                hasSourceDisagreement:matchingForecast?.hasDisagreement ?? false
            )
        }

        // Sort by impact descending, then by date
        weatherEvents = flagged.sorted {
            if $0.impact != $1.impact { return $0.impact > $1.impact }
            return $0.startDate < $1.startDate
        }
    }

    // MARK: - Outdoor detection
    private func isOutdoorEvent(_ event: EKEvent) -> Bool {
        let text = [event.title, event.notes, event.location]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return outdoorKeywords.contains { text.contains($0) }
    }

    // MARK: - Impact assessment
    private func assessImpact(event: EKEvent, forecast: ConsensusDaily?) -> WeatherImpact {
        guard let f = forecast else { return .clear }

        // Major: severe conditions
        if f.rainProbability > 70 { return .major }
        if f.windSpeed > 40       { return .major }
        if [.thunderstorm, .heavyRain].contains(f.condition) { return .major }

        // Watch: moderate concern or source disagreement
        if f.rainProbability > 40 || f.windSpeed > 25 { return .watch }
        if f.hasDisagreement && f.rainProbability > 20 { return .watch }

        // Minor: light showers or light wind
        if f.rainProbability > 20 { return .minor }
        if f.windSpeed > 15       { return .minor }

        return .clear
    }

    // MARK: - Warning text generation
    private func generateWarning(event: EKEvent, forecast: ConsensusDaily?, impact: WeatherImpact) -> String? {
        guard let f = forecast, impact != .clear else { return nil }

        var parts: [String] = []

        if f.rainProbability > 50 {
            parts.append("\(Int(f.rainProbability.rounded()))% chance of rain")
        } else if f.rainProbability > 20 {
            parts.append("light shower possible (\(Int(f.rainProbability.rounded()))%)")
        }

        if f.windSpeed > 30 {
            parts.append("strong winds \(Units.windString(f.windSpeed, withUnit: true))")
        } else if f.windSpeed > 20 {
            parts.append("\(Units.windString(f.windSpeed, withUnit: true)) winds")
        }

        if f.hasDisagreement {
            parts.append("sources disagree — check closer to the date")
        }

        guard !parts.isEmpty else { return nil }

        switch impact {
        case .major: return "⚡ " + parts.joined(separator: " and ") + "."
        case .watch: return parts.joined(separator: " and ").capitalized + "."
        case .minor: return parts.joined(separator: " and ").capitalized + "."
        case .clear: return nil
        }
    }
}
