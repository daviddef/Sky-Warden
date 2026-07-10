// SkyWarden — WeatherReading.swift PATCH
// Add .weatherKit to WeatherSource enum.
// Replace the WeatherSource enum in WeatherReading.swift with this version.

// MARK: - Updated WeatherSource (4 sources now)
// ─── REPLACE the existing WeatherSource enum in WeatherReading.swift ──────────

/*
enum WeatherSource: String, CaseIterable, Identifiable {
    case openMeteo   = "Open-Meteo"
    case openWeather = "OpenWeather"
    case weatherKit  = "WeatherKit"     // ← NEW
    case bom         = "BOM"

    var id: String { rawValue }

    var short: String {
        switch self {
        case .openMeteo:   return "OM"
        case .openWeather: return "OW"
        case .weatherKit:  return "WK"   // ← NEW
        case .bom:         return "BOM"
        }
    }

    var colorHex: String {
        switch self {
        case .openMeteo:   return "5BA3D4"
        case .openWeather: return "F5A623"
        case .weatherKit:  return "3DD68C"   // ← Apple green
        case .bom:         return "C084FC"   // ← reassigned to purple
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openWeather: return true
        case .weatherKit:  return true   // ← requires Apple Dev account + JWT
        default:           return false
        }
    }

    /// Human-readable setup note shown in Sources tab
    var setupNote: String {
        switch self {
        case .openMeteo:   return "Free · No API key required"
        case .openWeather: return "Free tier: 1,000 calls/day"
        case .weatherKit:  return "Free with Apple Developer account ($99/yr)"
        case .bom:         return "Free · Australian Bureau of Meteorology"
        }
    }
}
*/

// ─── ADD to WeatherAggregator.fetchAllWeather() ───────────────────────────────
// Inside the withTaskGroup block, add:
/*
    group.addTask { [self] in
        do    { return .success(try await WeatherKitService().fetch(location: location)) }
        catch { return .failure(error) }
    }
*/

// ─── WeatherKit vs WeatherKitSwift ───────────────────────────────────────────
// Apple provides TWO ways to use WeatherKit:
//
// 1. WeatherKit Swift framework (iOS 16+):
//    - import WeatherKit
//    - Simpler API, handles JWT automatically
//    - Only works from native iOS/macOS/watchOS code
//    - Requires WeatherKit capability in Xcode → Signing & Capabilities
//
// 2. WeatherKit REST API (what WeatherKitService.swift implements):
//    - Works from any platform
//    - You manage JWT signing yourself
//    - Better for: server-side, Android, web
//    - More control over response shape
//
// RECOMMENDATION FOR THIS APP:
// Use the Swift framework on iOS/watchOS (simpler, no JWT code):
//
// import WeatherKit
// import CoreLocation
//
// let weatherService = WeatherService()
// let weather = try await weatherService.weather(for: location)
// let current  = weather.currentWeather
// let hourly   = weather.hourlyForecast
// let daily    = weather.dailyForecast
//
// Then map:
//   current.temperature.value         → Double (°C if locale set)
//   current.precipitationIntensity     → Measurement<UnitSpeed>
//   current.wind.speed.value           → Double (km/h)
//   current.uvIndex.value              → Int
//   current.condition                  → WeatherCondition enum
//
// The REST service in WeatherKitService.swift is kept for completeness
// and for any server-side validation use case.

// ─── Config.xcconfig additions ────────────────────────────────────────────────
/*
// WeatherKit (REST API path — skip if using Swift framework)
WEATHERKIT_KEY_ID     = YOUR_KEY_ID_HERE
WEATHERKIT_SERVICE_ID = com.yourname.skywarden
WEATHERKIT_TEAM_ID    = YOUR_TEAM_ID_HERE

// GNews (optional — for weather news tab)
// https://gnews.io — free tier: 100 requests/day
GNEWS_API_KEY = YOUR_KEY_HERE
*/

// ─── Info.plist additions ─────────────────────────────────────────────────────
/*
<key>NSCalendarsUsageDescription</key>
<string>SkyWarden reads your calendar to warn you about weather affecting your outdoor events.</string>

<key>NSCalendarsFullAccessUsageDescription</key>
<string>SkyWarden checks your upcoming outdoor events and flags weather that may affect them.</string>
*/

// ─── Xcode Capabilities to add ───────────────────────────────────────────────
/*
✅ WeatherKit                    (for WeatherKit Swift framework)
✅ Background App Refresh        (already added)
✅ Push Notifications            (for astro event alerts)
✅ App Groups → group.com.yourname.skywarden  (for Watch data sharing)
*/
