// Sky Warden — severe-weather / hazard warnings
//
// Australian state emergency services publish open (CC-BY) GeoJSON warning
// feeds — no key. We fetch the ones relevant to the user's state, decide which
// warnings actually cover their location, and surface them.
//
// The geometry test is the load-bearing part: a false negative hides a real
// bushfire or flood warning from someone standing inside its polygon, so it is
// pure and heavily tested. BOM is deliberately excluded — its feeds are
// non-commercial and scraping is prohibited.

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Severity

/// Normalised across sources. Ordered so the worst sorts first.
enum WarningSeverity: Int, Comparable, Codable {
    case advice = 0        // "Advice", "Minor", "Moderate"
    case watchAndAct = 1   // "Watch and Act", "Severe"
    case emergency = 2     // "Emergency Warning", "Extreme"
    case unknown = -1

    static func < (a: WarningSeverity, b: WarningSeverity) -> Bool { a.rawValue < b.rawValue }

    /// Maps the many wordings the feeds use onto our three levels.
    static func from(_ raw: String?) -> WarningSeverity {
        switch (raw ?? "").lowercased() {
        case let s where s.contains("emergency") || s.contains("extreme") || s.contains("evacuate"):
            return .emergency
        case let s where s.contains("watch and act") || s.contains("watch & act") || s.contains("severe"):
            return .watchAndAct
        case let s where s.contains("advice") || s.contains("minor") || s.contains("moderate")
            || s.contains("information") || s.contains("avoid"):
            return .advice
        default:
            return .unknown
        }
    }

    var label: String {
        switch self {
        case .emergency:   "Emergency Warning"
        case .watchAndAct: "Watch and Act"
        case .advice:      "Advice"
        case .unknown:     "Warning"
        }
    }

    var colorHex: String {
        switch self {
        case .emergency:   "E05555"   // red
        case .watchAndAct: "F5A623"   // amber
        case .advice:      "5BA3D4"   // blue
        case .unknown:     "7BA7C4"
        }
    }

    var emoji: String {
        switch self {
        case .emergency:   "🚨"
        case .watchAndAct: "⚠️"
        case .advice:      "ℹ️"
        case .unknown:     "⚠️"
        }
    }
}

// MARK: - Geometry

/// A warning's area, reduced to the one question that matters: is the user in it?
indirect enum WarningArea {
    case point(CLLocationCoordinate2D, radiusKm: Double)
    /// GeoJSON polygon: first ring is the outer boundary, the rest are holes.
    case polygon(rings: [[CLLocationCoordinate2D]])
    case collection([WarningArea])

    func contains(_ p: CLLocationCoordinate2D) -> Bool {
        switch self {
        case let .point(centre, radiusKm):
            return WarningGeometry.haversineKm(centre, p) <= radiusKm
        case let .polygon(rings):
            guard let outer = rings.first, WarningGeometry.pointInRing(p, outer) else { return false }
            // Inside the outer boundary but not inside any hole.
            return !rings.dropFirst().contains { WarningGeometry.pointInRing(p, $0) }
        case let .collection(areas):
            return areas.contains { $0.contains(p) }
        }
    }
}

enum WarningGeometry {
    /// Standard even-odd ray casting. Planar (lat/lon treated as x/y) — fine at
    /// warning scale in Australia, which is nowhere near a pole or the
    /// antimeridian.
    static func pointInRing(_ p: CLLocationCoordinate2D, _ ring: [CLLocationCoordinate2D]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let yi = ring[i].latitude, xi = ring[i].longitude
            let yj = ring[j].latitude, xj = ring[j].longitude
            if (yi > p.latitude) != (yj > p.latitude),
               p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}

// MARK: - Warning

struct WeatherWarning: Identifiable {
    let id: String
    let title: String
    let severity: WarningSeverity
    let category: String          // "Bushfire", "Flood", "Storm", …
    let sourceOrg: String         // "QFD", "NSW RFS", "VicEmergency"
    let instruction: String?      // "call to action" text where the feed provides it
    let updated: Date?
    let url: String?

    var color: Color { Color(hex: severity.colorHex) }
}
