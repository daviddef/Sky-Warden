// SkyWarden — Comfort model
// Direct port of the prototype's RINGS scoring curves (calibrated against
// Brisbane thermal-comfort, Lawson wind, Cancer Council UV and SE-QLD humidity
// research). Each metric maps its value to a comfort score in −1.0…+1.0:
//   +1 → very comfortable (needle left, 9 o'clock)
//    0 → borderline       (needle up,   12 o'clock)
//   −1 → uncomfortable    (needle right, 3 o'clock)

import SwiftUI

enum ComfortMetric: String, CaseIterable, Identifiable {
    case temp, rain, wind, uv, humidity
    var id: String { rawValue }

    var label: String {
        switch self {
        case .temp: "Temp"; case .rain: "Rain"; case .wind: "Wind"
        case .uv: "UV";     case .humidity: "Humid"
        }
    }
    var emoji: String {
        switch self {
        case .temp: "🌡"; case .rain: "💧"; case .wind: "💨"
        case .uv: "☀️";   case .humidity: "💦"
        }
    }
    var colorGood: Color {
        switch self {
        case .temp: Sky.green; case .rain: Sky.rain; case .wind: Sky.wind
        case .uv: Sky.amber;   case .humidity: Sky.tide
        }
    }
    var colorBad: Color {
        switch self {
        case .rain: Sky.rain; case .wind: Sky.wind
        default:    Sky.red
        }
    }
    /// Spread (max−min across sources) at/above which a minor flag appears.
    var disagreementThreshold: Double {
        switch self {
        case .temp: 2; case .rain: 15; case .wind: 10; case .uv: 1; case .humidity: 10
        }
    }

    // MARK: - Scoring curves (ported verbatim from the JSX prototype)
    func score(_ v: Double) -> Double {
        switch self {
        case .temp:
            if v >= 22 && v <= 28 { return 1 }
            if v < 22 {
                if v >= 17 { return (v - 17) / 5 }
                if v >= 12 { return (v - 12) / 5 - 1 }
                return -1
            } else {
                if v <= 33 { return 1 - (v - 28) / 5 }
                if v <= 38 { return -(v - 33) / 5 }
                return -1
            }
        case .rain:
            if v <= 15 { return 1 }
            if v <= 35 { return 1 - (v - 15) / 20 }
            if v <= 60 { return -(v - 35) / 25 }
            return -1
        case .wind:
            if v <= 12 { return 1 }
            if v <= 25 { return 1 - (v - 12) / 13 }
            if v <= 45 { return -(v - 25) / 20 }
            return -1
        case .uv:
            if v <= 2 { return 1 }
            if v <= 5 { return 1 - (v - 2) / 3 }
            if v <= 8 { return -(v - 5) / 4.5 }
            if v <= 11 { return -0.6 - (v - 8) * 0.13 }
            return -1
        case .humidity:
            if v >= 40 && v <= 65 { return 1 }
            if v < 40 {
                if v >= 30 { return (v - 30) / 10 }
                if v >= 20 { return (v - 20) / 10 - 1 }
                return -1
            } else {
                if v <= 75 { return 1 - (v - 65) / 10 }
                if v <= 85 { return -(v - 75) / 10 }
                return -1
            }
        }
    }

    func comfortLabel(_ v: Double) -> String {
        switch self {
        case .temp:
            if v >= 22 && v <= 28 { return "Ideal" }
            if v < 17 { return "Cool" }
            if v < 22 { return "Slightly cool" }
            return v <= 33 ? "Warm" : "Hot"
        case .rain:
            if v <= 15 { return "Unlikely" }
            if v <= 35 { return "Possible" }
            return v <= 60 ? "Likely" : "Probable"
        case .wind:
            if v <= 12 { return "Calm" }
            if v <= 25 { return "Breezy" }
            return v <= 45 ? "Windy" : "Strong"
        case .uv:
            if v <= 2 { return "Low" }
            if v <= 5 { return "Moderate" }
            if v <= 7 { return "High" }
            return v <= 10 ? "Very High" : "Extreme"
        case .humidity:
            if v >= 40 && v <= 65 { return "Comfortable" }
            if v < 40 { return "Dry" }
            return v <= 75 ? "Muggy" : "Oppressive"
        }
    }

    /// Display only — `v` is always metric (°C, km/h).
    func format(_ v: Double) -> String {
        switch self {
        case .temp: return Units.tempString(v)
        case .wind: return Units.windString(v)
        case .rain, .humidity: return "\(Int(v.rounded()))%"
        case .uv: return "\(Int(v.rounded()))"
        }
    }

    /// Formats a spread/difference. Temperature deltas scale by 9/5 with no offset.
    func formatDelta(_ v: Double) -> String {
        switch self {
        case .temp: return "\(Int(Units.tempDelta(v).rounded()))"
        case .wind: return Units.windString(v)
        default:    return "\(Int(v.rounded()))"
        }
    }
}

// MARK: - Colour helpers
enum Comfort {

    /// The one comfort ramp: hue means how good this is, and nothing else.
    ///
    /// Previously each metric carried its own hue and drifted toward red as it
    /// worsened, so five rings meant five hues at five saturations, and colour
    /// stopped meaning anything by itself. Here green is good, red is not, and a
    /// dim desaturated blue-grey is the borderline — receding into the
    /// background exactly where the reading is unremarkable.
    ///
    /// Diverging, so: two hues and a neutral midpoint, never a hue in the
    /// middle. Validated with the dataviz palette checker against the navy
    /// surface — worst adjacent CVD separation ΔE 38.5 under protanopia (target
    /// ≥ 12), every stop over 3:1 contrast, and lightness falls monotonically
    /// from each pole into the neutral so the ramp survives greyscale.
    static let good    = Color(hex: "3DD68C")
    static let neutral = Color(hex: "5A7089")
    static let poor    = Color(hex: "FF7A6E")

    /// score: +1 comfortable … 0 borderline … −1 uncomfortable
    static func comfortColor(_ score: Double) -> Color {
        let s = max(-1, min(1, score))
        return s >= 0 ? mix(neutral, good, s) : mix(neutral, poor, -s)
    }

    /// Kept for the Week and Sources tabs, where per-metric identity still
    /// matters because several metrics share a single row.
    static func needleColor(_ metric: ComfortMetric, _ score: Double) -> Color {
        score >= 0
            ? mix(metric.colorGood, .white, score * 0.15)
            : mix(metric.colorGood, Sky.red, abs(score) * 0.85)
    }

    static func overallScore(_ d: ComfortData) -> Double {
        d.rings.map { $0.score }.reduce(0, +) / Double(max(1, d.rings.count))
    }
    static func overallLabel(_ s: Double) -> String {
        s >= 0.7 ? "Great" : s >= 0.3 ? "Good" : s >= 0 ? "OK" : s >= -0.5 ? "Rough" : "Poor"
    }
    /// The icon's orange circle, doing its real job: one colour for "how good is
    /// today", on the same ramp as every ring.
    static func overallColor(_ s: Double) -> Color { comfortColor(s) }
    /// Comfort score → dial angle in degrees (0° = top, −90° = left/good, +90° = right).
    static func angle(_ score: Double) -> Double { -score * 90 }

    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = a.rgba, cb = b.rgba
        return Color(
            red:   ca.r + (cb.r - ca.r) * t,
            green: ca.g + (cb.g - ca.g) * t,
            blue:  ca.b + (cb.b - ca.b) * t
        )
    }
}

extension Color {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}

// MARK: - Per-ring reading (assembled from consensus + raw source readings)
struct RingReading: Identifiable {
    let metric: ComfortMetric
    let value: Double
    let minMax: (Double, Double)?
    let perSource: [(source: WeatherSource, value: Double)]
    let spread: Double

    var id: String { metric.rawValue }
    var score: Double { metric.score(value) }
    var isMajor: Bool { spread >= metric.disagreementThreshold * 2 }
    var isMinor: Bool { spread >= metric.disagreementThreshold && !isMajor }
    var hasFlag: Bool { spread >= metric.disagreementThreshold }
}

// MARK: - Comfort data (the whole dial's inputs), built from ConsensusWeather
struct ComfortData {
    let rings: [RingReading]

    func ring(_ m: ComfortMetric) -> RingReading? { rings.first { $0.metric == m } }

    init(consensus: ConsensusWeather) {
        let readings = consensus.rawReadings
        let hourly = consensus.hourlyForecast

        func value(_ m: ComfortMetric) -> Double {
            switch m {
            case .temp: consensus.temperature
            case .rain: consensus.rainProbability
            case .wind: consensus.windSpeed
            case .uv: consensus.uvIndex
            case .humidity: consensus.humidity
            }
        }
        /// `nil` when this source doesn't report the metric — it is then excluded
        /// from the ring's dots and its disagreement spread.
        func sourceValue(_ r: WeatherReading, _ m: ComfortMetric) -> Double? {
            switch m {
            case .temp: r.temperature
            case .rain: r.rainProbability
            case .wind: r.windSpeed
            case .uv: r.uvIndex
            case .humidity: r.humidity
            }
        }
        // Today's forecast min/max, used to place the two tick marks per ring.
        func minMax(_ m: ComfortMetric) -> (Double, Double)? {
            switch m {
            case .temp:
                guard let day = consensus.dailyForecast.first else { return nil }
                return (day.tempMin, day.tempMax)
            case .rain:
                let xs = hourly.map(\.rainProbability); return range(xs)
            case .wind:
                let xs = hourly.map(\.windSpeed); return range(xs)
            case .uv:
                // Only a couple of models publish UV at all.
                let xs = readings.flatMap { $0.hourlyForecast.compactMap(\.uvIndex) }; return range(xs)
            case .humidity:
                return nil   // humidity has no per-hour forecast in the model
            }
        }
        func range(_ xs: [Double]) -> (Double, Double)? {
            guard let lo = xs.min(), let hi = xs.max(), lo != hi else { return nil }
            return (lo, hi)
        }

        rings = ComfortMetric.allCases.map { m in
            let per: [(source: WeatherSource, value: Double)] = readings.compactMap { r in
                guard let v = sourceValue(r, m) else { return nil }
                return (source: r.source, value: v)
            }
            // Trimmed with 4+ sources so extra models don't inflate the spread.
            let spread = robustSpread(per.map(\.value)) ?? 0
            return RingReading(metric: m, value: value(m), minMax: minMax(m),
                               perSource: per, spread: spread)
        }
    }
}

// MARK: - Rating banner text (ported from ratingText())
struct RatingText { let text: String; let emoji: String }

func ratingText(for d: ComfortData, season: String, place: String) -> RatingText {
    let os = Comfort.overallScore(d)
    guard let worst = d.rings.min(by: { $0.score < $1.score }) else {
        return RatingText(text: "Gathering conditions…", emoji: "🌤")
    }
    let temp = d.ring(.temp)?.value ?? 0
    let rain = Int((d.ring(.rain)?.value ?? 0).rounded())

    if os >= 0.75 {
        return RatingText(text: "A perfect \(season)'s day in \(place) — comfortable and clear.", emoji: "😎")
    }
    if os >= 0.4 {
        switch worst.metric {
        case .rain: return RatingText(text: "Decent but \(rain)% rain chance — keep an eye on the sky.", emoji: "🌦")
        case .uv:   return RatingText(text: "Nice day but UV is \(worst.metric.comfortLabel(worst.value)) — sun protection essential.", emoji: "🧴")
        case .temp where temp < 17:
            return RatingText(text: "Cool day at \(Int(temp.rounded()))° — pack a layer.", emoji: "🧥")
        default:    return RatingText(text: "Good conditions with a few things to watch.", emoji: "🙂")
        }
    }
    switch worst.metric {
    case .rain: return RatingText(text: "Rain likely (\(rain)%) — plan around the showers.", emoji: "🌧")
    case .temp where temp > 35:
        return RatingText(text: "Heatwave — \(Int(temp.rounded()))°. Limit outdoor activity midday.", emoji: "🔥")
    default:    return RatingText(text: "Mixed conditions today. Check the detail tabs.", emoji: "😐")
    }
}

/// Season from the current month, correct for either hemisphere.
/// Northern-hemisphere months are offset by six so July reads as summer there
/// and winter in Australia.
func currentSeason(latitude: Double, date: Date = Date()) -> String {
    var month = Calendar.current.component(.month, from: date)
    if latitude >= 0 { month = (month + 5) % 12 + 1 }
    switch month {
    case 12, 1, 2: return "summer"
    case 3, 4, 5:  return "autumn"
    case 6, 7, 8:  return "winter"
    default:       return "spring"
    }
}
