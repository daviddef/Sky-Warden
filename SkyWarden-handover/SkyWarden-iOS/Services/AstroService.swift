// SkyWarden — Astronomical Events Service
// Sources: NASA JPL Horizons API, Time and Date AS, IAU MPC
// Covers: eclipses, meteor showers, planetary oppositions, comets, ISS passes

import Foundation
import CoreLocation

// MARK: - Astronomical event model
struct AstroEvent: Identifiable, Codable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date?
    let type: AstroEventType
    let description: String
    let visibilityNote: String?
    let rarity: AstroRarity
    let peakTime: Date?

    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    var daysUntil: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0)
    }
}

enum AstroEventType: String, Codable {
    case solarEclipse    = "Solar Eclipse"
    case lunarEclipse    = "Lunar Eclipse"
    case meteorShower    = "Meteor Shower"
    case planetaryEvent  = "Planetary Event"   // opposition, conjunction, elongation
    case comet           = "Comet"
    case asteroid        = "Asteroid"
    case issPass         = "ISS Pass"
    case conjunction     = "Conjunction"
    case occultation     = "Occultation"
    case aurora          = "Aurora"

    var icon: String {
        switch self {
        case .solarEclipse:   return "sun.max.fill"
        case .lunarEclipse:   return "moonphase.full.moon"
        case .meteorShower:   return "sparkles"
        case .planetaryEvent: return "circle.hexagongrid.fill"
        case .comet:          return "wand.and.stars"
        case .asteroid:       return "oval.fill"
        case .issPass:        return "airplane"
        case .conjunction:    return "moon.stars.fill"
        case .occultation:    return "circle.fill"
        case .aurora:         return "aqi.medium"
        }
    }

    var emoji: String {
        switch self {
        case .solarEclipse:   return "🌑"
        case .lunarEclipse:   return "🌕"
        case .meteorShower:   return "☄️"
        case .planetaryEvent: return "🪐"
        case .comet:          return "🌠"
        case .asteroid:       return "🪨"
        case .issPass:        return "🛸"
        case .conjunction:    return "✨"
        case .occultation:    return "🔭"
        case .aurora:         return "🌌"
        }
    }
}

enum AstroRarity: String, Codable {
    case rare     // once in years/decades (eclipses, bright comets)
    case notable  // annual but significant (oppositions, close conjunctions)
    case regular  // every year (meteor showers, equinoxes)
    case frequent // multiple times/year (ISS passes, common conjunctions)

    var label: String {
        switch self {
        case .rare:     return "Rare event"
        case .notable:  return "Notable"
        case .regular:  return "Annual"
        case .frequent: return ""
        }
    }

    var color: String {
        switch self {
        case .rare:     return "C084FC"  // purple
        case .notable:  return "D4C47A"  // moon gold
        case .regular:  return "7BA7C4"  // muted
        case .frequent: return "4ECDC4"  // tide
        }
    }
}

// MARK: - Astronomical events service
struct AstroService {

    // MARK: - Hardcoded near-future events (update annually or via API)
    // In production: fetch from:
    //   - NASA JPL Horizons: https://ssd.jpl.nasa.gov/api/horizons.api
    //   - IAU Meteor Showers: https://www.imo.net/resources/calendar/
    //   - Time and Date AS API: https://www.timeanddate.com/services/api/
    //   - In-The-Sky.org API

    func upcomingEvents(near location: CLLocation, months: Int = 30) async -> [AstroEvent] {
        // Curated near-future set filtered to the requested window and SE-QLD
        // visibility. Placeholder until wired to NASA JPL Horizons / IAU feeds.

        let cal = Calendar.current
        let now = Date()

        var events: [AstroEvent] = [
            AstroEvent(
                id: "perseid-2026",
                title: "Perseid Meteor Shower",
                date: dateFrom(year: 2026, month: 8, day: 12, hour: 22, minute: 0),
                endDate: dateFrom(year: 2026, month: 8, day: 13, hour: 4, minute: 0),
                type: .meteorShower,
                description: "Up to 100 meteors/hr at peak. Northern-hemisphere shower — reduced rates (~30/hr) from Australia but still worth a look.",
                visibilityNote: "Best after midnight, looking north",
                rarity: .regular,
                peakTime: dateFrom(year: 2026, month: 8, day: 12, hour: 3, minute: 0)
            ),
            AstroEvent(
                id: "saturn-opposition-2026",
                title: "Saturn at Opposition",
                date: dateFrom(year: 2026, month: 9, day: 14, hour: 20, minute: 0),
                endDate: nil,
                type: .planetaryEvent,
                description: "Saturn at its closest and brightest for the year. Rings visible through binoculars. Up all night.",
                visibilityNote: "Rises at sunset — excellent from SE Qld",
                rarity: .notable,
                peakTime: dateFrom(year: 2026, month: 9, day: 14, hour: 23, minute: 30)
            ),
            AstroEvent(
                id: "geminid-2026",
                title: "Geminid Meteor Shower",
                date: dateFrom(year: 2026, month: 12, day: 14, hour: 21, minute: 0),
                endDate: dateFrom(year: 2026, month: 12, day: 15, hour: 4, minute: 0),
                type: .meteorShower,
                description: "The year's most reliable shower — up to 120 meteors/hr, bright and slow. Good rates from the southern hemisphere.",
                visibilityNote: "Radiant high in the evening sky from SE Qld",
                rarity: .regular,
                peakTime: dateFrom(year: 2026, month: 12, day: 14, hour: 23, minute: 0)
            ),
            AstroEvent(
                id: "lunar-eclipse-2026-08",
                title: "Partial Lunar Eclipse",
                date: dateFrom(year: 2026, month: 8, day: 28, hour: 18, minute: 12),
                endDate: dateFrom(year: 2026, month: 8, day: 28, hour: 20, minute: 22),
                type: .lunarEclipse,
                description: "A partial lunar eclipse with the Moon rising already in shadow over eastern Australia.",
                visibilityNote: "Visible low in the east from SE Queensland",
                rarity: .rare,
                peakTime: dateFrom(year: 2026, month: 8, day: 28, hour: 19, minute: 18)
            ),
            AstroEvent(
                id: "solar-eclipse-2028-07",
                title: "Total Solar Eclipse",
                date: dateFrom(year: 2028, month: 7, day: 22, hour: 14, minute: 36),
                endDate: nil,
                type: .solarEclipse,
                description: "Total solar eclipse with the path of totality crossing Sydney. Up to 5 minutes of totality — a rare Australian mainland eclipse.",
                visibilityNote: "Totality from Sydney — deep partial from the Gold Coast",
                rarity: .rare,
                peakTime: nil
            ),
        ]

        // Filter to upcoming within requested window
        let windowEnd = cal.date(byAdding: .month, value: months, to: now)!
        return events
            .filter { $0.date >= now && $0.date <= windowEnd }
            .sorted { $0.date < $1.date }
    }

    // MARK: - NASA JPL Horizons API (production integration)
    // For eclipses, comet visibility, and planetary positions:
    //
    // func fetchJPLHorizons(body: String, location: CLLocation) async throws -> [AstroEvent] {
    //     let url = "https://ssd.jpl.nasa.gov/api/horizons.api?format=json&COMMAND=\(body)&OBJ_DATA=YES&MAKE_EPHEM=YES&EPHEM_TYPE=OBSERVER&CENTER=coord&COORD_TYPE=GEODETIC&SITE_COORD='\(location.coordinate.longitude),\(location.coordinate.latitude),0'&START_TIME='2025-07-01'&STOP_TIME='2026-01-01'&STEP_SIZE='1d'"
    //     ...
    // }

    // MARK: - Helper
    private func dateFrom(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        comps.timeZone = TimeZone(identifier: "Australia/Brisbane")
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - Notifications for upcoming rare events
struct AstroNotificationScheduler {

    func schedule(events: [AstroEvent]) {
        let center = UNUserNotificationCenter.current()

        for event in events where event.rarity == .rare || event.rarity == .notable {
            // 3-day warning
            schedule(event: event, daysBefore: 3, center: center)
            // Day-before reminder
            schedule(event: event, daysBefore: 1, center: center)
        }
    }

    private func schedule(event: AstroEvent, daysBefore: Int, center: UNUserNotificationCenter) {
        guard let triggerDate = Calendar.current.date(
            byAdding: .day, value: -daysBefore, to: event.date
        ), triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(event.type.emoji) \(event.title)"
        content.body  = daysBefore == 1
            ? "Tomorrow! \(event.description)"
            : "In \(daysBefore) days — \(event.description)"
        content.sound = .default
        content.categoryIdentifier = "ASTRO_EVENT"

        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(event.id)-\(daysBefore)d",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}

// Required import for notifications
import UserNotifications
