// Sky Warden — display units
//
// The engines always work in metric: the comfort curves are calibrated in °C
// (Brisbane thermal-comfort research) and km/h (Lawson wind criteria), and the
// disagreement thresholds are metric too. Units are a *display* concern only —
// never convert before scoring.

import Foundation

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var label: String { self == .celsius ? "°C" : "°F" }
}

enum WindUnit: String, CaseIterable, Identifiable {
    case kmh, mph, knots
    var id: String { rawValue }
    var label: String {
        switch self {
        case .kmh: "km/h"; case .mph: "mph"; case .knots: "kn"
        }
    }
}

enum UnitKey {
    static let temperature = "unit.temperature"
    static let wind        = "unit.wind"
}

enum Units {
    static var temperature: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: UnitKey.temperature) ?? "") ?? .celsius
    }
    static var wind: WindUnit {
        WindUnit(rawValue: UserDefaults.standard.string(forKey: UnitKey.wind) ?? "") ?? .kmh
    }

    // MARK: - Temperature

    /// Converts an absolute temperature from °C into the user's unit.
    static func temp(_ celsius: Double) -> Double {
        temperature == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    /// Converts a temperature *difference* (a spread, or an "on this day" delta).
    /// A difference scales by 9/5 and must NOT take the +32 offset.
    static func tempDelta(_ celsiusDelta: Double) -> Double {
        temperature == .fahrenheit ? celsiusDelta * 9 / 5 : celsiusDelta
    }

    /// "18°" — the degree glyph without the unit letter, for dense UI.
    static func tempString(_ celsius: Double) -> String {
        "\(Int(temp(celsius).rounded()))°"
    }

    /// "+3°" / "−2°" for a difference.
    static func tempDeltaString(_ celsiusDelta: Double) -> String {
        let d = Int(tempDelta(celsiusDelta).rounded())
        return "\(d > 0 ? "+" : "")\(d)°"
    }

    /// Difference between two temperatures **as displayed**. Both are rounded to
    /// the shown integer first, so the delta always agrees with the two numbers
    /// on screen (60° vs 72° reads −12°, never −13° from unrounded inputs).
    static func displayTempDelta(_ celsiusA: Double, _ celsiusB: Double) -> Int {
        Int(temp(celsiusA).rounded()) - Int(temp(celsiusB).rounded())
    }

    // MARK: - Wind

    /// Converts a wind speed from km/h into the user's unit.
    static func windValue(_ kmh: Double) -> Double {
        switch wind {
        case .kmh:   kmh
        case .mph:   kmh * 0.621371
        case .knots: kmh * 0.539957
        }
    }

    /// "11" or "11 km/h".
    static func windString(_ kmh: Double, withUnit: Bool = false) -> String {
        let v = Int(windValue(kmh).rounded())
        return withUnit ? "\(v) \(wind.label)" : "\(v)"
    }
}
