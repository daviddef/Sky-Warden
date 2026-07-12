// SkyWarden — Shared identifiers & cross-target data model
// Compiled into BOTH the iOS app and the watchOS app so the phone can WRITE
// the latest weather snapshot and the Watch complication can READ it back.

import Foundation

// MARK: - Stable identifiers (single source of truth)
// Bundle ID: com.defranceski.skywarden  (see HANDOVER.md → App identity)
enum SkyWardenID {
    /// App Group used to share data between the phone app and the Watch.
    /// Must match the App Groups entitlement on BOTH targets.
    static let appGroup = "group.com.defranceski.skywarden"

    /// UserDefaults key inside the App Group suite holding the JSON snapshot.
    static let latestWeatherKey = "latestWeather"

    /// BGTaskScheduler identifier for periodic background refresh.
    /// Must be listed in Info.plist → BGTaskSchedulerPermittedIdentifiers.
    static let backgroundRefreshTask = "com.defranceski.skywarden.refresh"
}

// MARK: - Shared snapshot (written by iOS app, read by the Watch complication)
struct StoredWeatherData: Codable {
    let fetchedAt:         Date
    let temperature:       Int
    let conditionSFSymbol: String
    let conditionEmoji:    String
    let rainPercent:       Int
    let confidencePercent: Int
    /// Overall comfort as a 0–100 fill (0 = poor, 100 = great), for the watch ring.
    var comfortPercent:    Int = 50
    let hasDisagreement:   Bool
    let nextTide:          String?
    let moonEmoji:         String
    let moonPhase:         String
}

// MARK: - App Group access helpers
extension UserDefaults {
    /// Shared suite used for phone ⇄ Watch data. `nil` if the App Group
    /// entitlement is missing (e.g. running unsigned) — callers degrade gracefully.
    static var skyWardenShared: UserDefaults? {
        UserDefaults(suiteName: SkyWardenID.appGroup)
    }

    private static let lastLatKey = "lastLatitude"
    private static let lastLonKey = "lastLongitude"

    /// Persists the most recent forecast coordinate so the background task can
    /// refresh without waiting on a fresh location fix.
    func storeLastCoordinate(latitude: Double, longitude: Double) {
        set(latitude,  forKey: Self.lastLatKey)
        set(longitude, forKey: Self.lastLonKey)
    }

    var lastCoordinate: (latitude: Double, longitude: Double)? {
        guard object(forKey: Self.lastLatKey) != nil else { return nil }
        return (double(forKey: Self.lastLatKey), double(forKey: Self.lastLonKey))
    }
}
