// SkyWarden — Tide & Moon Models

import Foundation

// MARK: - Tide event
struct TideEvent: Identifiable, Codable {
    let id: UUID
    init(time: Date, height: Double, type: TideType) {
        self.id = UUID(); self.time = time; self.height = height; self.type = type
    }
    let time: Date
    let height: Double          // metres
    let type: TideType

    enum TideType: String, Codable {
        case high = "High"
        case low  = "Low"
    }

    var heightDisplay: String { String(format: "%.1fm", height) }

    var timeDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: time)
    }
}

// MARK: - Tide day (all events for one day + curve data)
struct TideDay: Identifiable, Codable {
    let id: UUID
    init(date: Date, events: [TideEvent], curvePoints: [TideCurvePoint], station: TideStation) {
        self.id = UUID(); self.date = date; self.events = events
        self.curvePoints = curvePoints; self.station = station
    }
    let date: Date
    let events: [TideEvent]
    let curvePoints: [TideCurvePoint]   // interpolated for chart
    let station: TideStation
}

struct TideCurvePoint: Codable {
    let time: Date
    let height: Double
}

// MARK: - Tide station
struct TideStation: Identifiable, Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceKm: Double?
}

// MARK: - Moon data
struct MoonData {
    let date: Date
    let phase: MoonPhase
    let illumination: Double    // 0.0–1.0
    let age: Double             // days since new moon (0–29.5)

    let riseTime: Date?
    let setTime: Date?
    let nextFullMoon: Date
    let nextNewMoon: Date

    var illuminationPercent: Int { Int((illumination * 100).rounded()) }
    var daysToFull: Int { Calendar.current.dateComponents([.day], from: date, to: nextFullMoon).day ?? 0 }

    enum MoonPhase: String, CaseIterable {
        case newMoon        = "New Moon"
        case waxingCrescent = "Waxing Crescent"
        case firstQuarter   = "First Quarter"
        case waxingGibbous  = "Waxing Gibbous"
        case fullMoon       = "Full Moon"
        case waningGibbous  = "Waning Gibbous"
        case lastQuarter    = "Last Quarter"
        case waningCrescent = "Waning Crescent"

        var emoji: String {
            switch self {
            case .newMoon:        return "🌑"
            case .waxingCrescent: return "🌒"
            case .firstQuarter:   return "🌓"
            case .waxingGibbous:  return "🌔"
            case .fullMoon:       return "🌕"
            case .waningGibbous:  return "🌖"
            case .lastQuarter:    return "🌗"
            case .waningCrescent: return "🌘"
            }
        }

        /// Derive phase from age (days since new moon)
        static func from(age: Double) -> MoonPhase {
            switch age {
            case 0..<1.85:       return .newMoon
            case 1.85..<7.38:    return .waxingCrescent
            case 7.38..<8.92:    return .firstQuarter
            case 8.92..<14.77:   return .waxingGibbous
            case 14.77..<16.31:  return .fullMoon
            case 16.31..<22.15:  return .waningGibbous
            case 22.15..<23.69:  return .lastQuarter
            default:             return .waningCrescent
            }
        }
    }
}

// MARK: - Sun data
struct SunData {
    let date: Date
    let sunrise: Date
    let sunset: Date
    let solarNoon: Date
    let daylightDuration: TimeInterval

    var sunriseDisplay: String { formatted(sunrise) }
    var sunsetDisplay: String  { formatted(sunset) }
    var daylightLabel: String {
        let h = Int(daylightDuration / 3600)
        let m = Int((daylightDuration.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h)h \(m)m"
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
