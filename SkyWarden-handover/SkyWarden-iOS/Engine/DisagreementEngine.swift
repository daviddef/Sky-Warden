// SkyWarden — DisagreementEngine
// Compares readings across sources and produces disagreement flags + confidence score

import Foundation

struct DisagreementEngine {

    // MARK: - Thresholds
    struct Thresholds {
        static let tempMinor: Double   = 2.0   // °C
        static let tempMajor: Double   = 5.0   // °C
        static let rainMinor: Double   = 15.0  // %
        static let rainMajor: Double   = 30.0  // %
        static let windMinor: Double   = 10.0  // km/h
        static let windMajor: Double   = 20.0  // km/h
    }

    // MARK: - Main analysis function
    func analyse(_ readings: [WeatherReading]) -> (
        disagreements: [FieldDisagreement],
        confidence: Double,
        worstSeverity: DisagreementSeverity
    ) {
        guard readings.count >= 2 else {
            return ([], readings.isEmpty ? 0.0 : 1.0, .none)
        }

        var disagreements: [FieldDisagreement] = []

        // Temperature
        if let d = checkTemperature(readings) { disagreements.append(d) }

        // Rain probability
        if let d = checkRain(readings) { disagreements.append(d) }

        // Wind speed
        if let d = checkWind(readings) { disagreements.append(d) }

        // Condition category
        if let d = checkCondition(readings) { disagreements.append(d) }

        let confidence = calculateConfidence(readings: readings, disagreements: disagreements)
        let worst = disagreements.map(\.severity).max() ?? .none

        return (disagreements, confidence, worst)
    }

    // MARK: - Per-field checks

    private func checkTemperature(_ readings: [WeatherReading]) -> FieldDisagreement? {
        let temps = readings.map(\.temperature)
        guard let spread = spread(temps) else { return nil }

        let severity: DisagreementSeverity
        switch spread {
        case ..<Thresholds.tempMinor: return nil
        case ..<Thresholds.tempMajor: severity = .minor
        default: severity = .major
        }

        let perSource = Dictionary(
            uniqueKeysWithValues: readings.map { ($0.source, "\(Int($0.temperature.rounded()))°C") }
        )
        return FieldDisagreement(
            fieldKey: "temperature",
            fieldLabel: "Temperature",
            severity: severity,
            perSource: perSource
        )
    }

    private func checkRain(_ readings: [WeatherReading]) -> FieldDisagreement? {
        let rains = readings.map(\.rainProbability)
        guard let spread = spread(rains) else { return nil }

        let severity: DisagreementSeverity
        switch spread {
        case ..<Thresholds.rainMinor: return nil
        case ..<Thresholds.rainMajor: severity = .minor
        default: severity = .major
        }

        let perSource = Dictionary(
            uniqueKeysWithValues: readings.map { ($0.source, "\(Int($0.rainProbability.rounded()))%") }
        )
        return FieldDisagreement(
            fieldKey: "rain",
            fieldLabel: "Rain chance",
            severity: severity,
            perSource: perSource
        )
    }

    private func checkWind(_ readings: [WeatherReading]) -> FieldDisagreement? {
        let winds = readings.map(\.windSpeed)
        guard let spread = spread(winds) else { return nil }

        let severity: DisagreementSeverity
        switch spread {
        case ..<Thresholds.windMinor: return nil
        case ..<Thresholds.windMajor: severity = .minor
        default: severity = .major
        }

        let perSource = Dictionary(
            uniqueKeysWithValues: readings.map { ($0.source, "\(Int($0.windSpeed.rounded())) km/h") }
        )
        return FieldDisagreement(
            fieldKey: "wind",
            fieldLabel: "Wind speed",
            severity: severity,
            perSource: perSource
        )
    }

    private func checkCondition(_ readings: [WeatherReading]) -> FieldDisagreement? {
        let conditions = readings.map(\.condition)
        let unique = Set(conditions.map(\.rawValue))
        guard unique.count > 1 else { return nil }

        // Check if the difference is meaningful (adjacent categories don't flag)
        let categories = conditions.map { conditionCategory($0) }
        let uniqueCategories = Set(categories)
        guard uniqueCategories.count > 1 else { return nil }

        let perSource = Dictionary(
            uniqueKeysWithValues: readings.map { ($0.source, $0.condition.rawValue) }
        )
        return FieldDisagreement(
            fieldKey: "condition",
            fieldLabel: "Conditions",
            severity: .minor,
            perSource: perSource
        )
    }

    // MARK: - Confidence score

    /// Confidence = weighted score penalised for each disagreement and its severity
    private func calculateConfidence(
        readings: [WeatherReading],
        disagreements: [FieldDisagreement]
    ) -> Double {
        let sourceCount = Double(readings.count)
        guard sourceCount >= 2 else { return sourceCount }

        var score = 1.0
        let weights: [String: Double] = [
            "temperature": 0.35,
            "rain":        0.30,
            "wind":        0.20,
            "condition":   0.15,
        ]

        for d in disagreements {
            let weight = weights[d.fieldKey] ?? 0.1
            switch d.severity {
            case .none:  break
            case .minor: score -= weight * 0.4
            case .major: score -= weight * 0.9
            }
        }

        // Bonus if all 3 sources are present and agree
        if sourceCount >= 3 && disagreements.isEmpty {
            score = min(1.0, score + 0.05)
        }

        return max(0.0, min(1.0, score))
    }

    // MARK: - Helpers

    private func spread(_ values: [Double]) -> Double? {
        guard let min = values.min(), let max = values.max() else { return nil }
        return max - min
    }

    /// Groups conditions into coarse categories (adjacent fine categories don't trigger a flag)
    private func conditionCategory(_ condition: WeatherCondition) -> Int {
        switch condition {
        case .clearSky, .mostlyClear:           return 0  // fine
        case .partlyCloudy, .mostlyCloudy:      return 1  // cloudy
        case .overcast:                          return 2  // overcast
        case .drizzle:                           return 3  // light precip
        case .rain, .heavyRain, .thunderstorm:  return 4  // rain
        case .fog:                               return 5  // fog
        case .snow:                              return 6  // snow
        }
    }
}

// MARK: - Disagreement history (for the Sources tab log)
struct DisagreementEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let fieldLabel: String
    let severity: DisagreementSeverity
    let perSource: [WeatherSource: String]
}
