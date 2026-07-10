// SkyWarden — WeatherKit REST API Service
// Apple's own weather data. Free with an Apple Developer account.
// Docs: https://developer.apple.com/documentation/weatherkitrestapi
//
// Setup:
//   1. developer.apple.com → Certificates → WeatherKit → create a Service ID
//   2. Download the .p8 private key
//   3. Generate a signed JWT per request (or cache for up to 30 min)
//   4. Add to Config.xcconfig:
//        WEATHERKIT_KEY_ID      = your_key_id
//        WEATHERKIT_SERVICE_ID  = com.yourname.skywarden  (your Service ID)
//        WEATHERKIT_TEAM_ID     = your_apple_team_id
//   5. Embed the .p8 file in the app bundle (add to target, do NOT commit to git)

import Foundation
import CoreLocation
import CryptoKit

// Reference implementation of the WeatherKit REST path (manual ES256 JWT signing).
// The app uses the native framework (`WeatherKitService` in WeatherKitNativeService.swift)
// instead; this is kept for server-side / cross-platform use and to document the
// JWT flow. It is not wired into WeatherAggregator.
final class WeatherKitRESTService {

    private let baseURL = "https://weatherkit.apple.com/api/v1"

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> WeatherReading {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let token = try generateJWT()
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        // WeatherKit returns all datasets in one call
        let datasets = "currentWeather,hourlyForecast,dailyForecast"
        let urlString = "\(baseURL)/weather/\(language)/\(lat)/\(lon)?dataSets=\(datasets)&timezone=Australia/Brisbane"
        guard let url = URL(string: urlString) else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError.httpError(code)
        }

        let raw = try JSONDecoder().decode(WKResponse.self, from: data)
        return try parse(raw)
    }

    // MARK: - Parse
    private func parse(_ r: WKResponse) throws -> WeatherReading {
        guard let current = r.currentWeather else {
            throw ServiceError.missingData("currentWeather")
        }

        let condition = wkCondition(from: current.conditionCode)
        let windSpeed = current.wind.speed * 3.6   // m/s → km/h

        let hourly: [HourlyReading] = (r.hourlyForecast?.hours ?? []).prefix(24).map { h in
            HourlyReading(
                time:             h.forecastStart,
                temperature:      h.temperature,
                rainProbability:  h.precipitationChance * 100,
                rainAmount:       h.precipitationAmount,
                windSpeed:        h.wind.speed * 3.6,
                condition:        wkCondition(from: h.conditionCode),
                uvIndex:          Double(h.uvIndex)
            )
        }

        let daily: [DailyReading] = (r.dailyForecast?.days ?? []).map { d in
            DailyReading(
                date:             d.forecastStart,
                tempMax:          d.temperatureMax,
                tempMin:          d.temperatureMin,
                rainProbability:  d.precipitationChance * 100,
                rainAmount:       d.precipitationAmount,
                windSpeed:        (d.daytimeForecast?.wind.speed ?? 0) * 3.6,
                condition:        wkCondition(from: d.conditionCode),
                uvIndexMax:       Double(d.maxUvIndex),
                sunrise:          d.sunrise,
                sunset:           d.sunset
            )
        }

        return WeatherReading(
            source:          .weatherKit,
            fetchedAt:       Date(),
            temperature:     current.temperature,
            feelsLike:       current.temperatureApparent,
            tempMin:         daily.first?.tempMin,
            tempMax:         daily.first?.tempMax,
            rainProbability: hourly.first?.rainProbability ?? 0,
            rainAmount:      current.precipitationIntensity,
            windSpeed:       windSpeed,
            windGust:        current.wind.gust.map { $0 * 3.6 },
            windDirection:   current.wind.direction,
            humidity:        current.humidity * 100,
            uvIndex:         Double(current.uvIndex),
            visibility:      current.visibility / 1000,
            pressure:        current.pressure,
            condition:       condition,
            hourlyForecast:  hourly,
            dailyForecast:   daily
        )
    }

    // MARK: - WeatherKit condition codes → WeatherCondition
    // Full list: https://developer.apple.com/documentation/weatherkitrestapi/conditioncode
    private func wkCondition(from code: String) -> WeatherCondition {
        switch code {
        case "Clear":                           return .clearSky
        case "MostlyClear":                     return .mostlyClear
        case "PartlyCloudy":                    return .partlyCloudy
        case "MostlyCloudy":                    return .mostlyCloudy
        case "Cloudy", "Overcast":              return .overcast
        case "Foggy", "Haze":                   return .fog
        case "Drizzle", "FreezingDrizzle":      return .drizzle
        case "Rain", "SunShowers":              return .rain
        case "HeavyRain", "FreezingRain":       return .heavyRain
        case "Thunderstorms", "ScatteredThunderstorms",
             "IsolatedThunderstorms",
             "StrongStorms":                    return .thunderstorm
        case "Snow", "Flurries", "BlowingSnow",
             "HeavySnow", "Sleet":              return .snow
        default:                                return .partlyCloudy
        }
    }

    // MARK: - JWT generation
    // WeatherKit REST requires a signed ES256 JWT on every request.
    // The JWT is valid for up to 30 minutes; cache and reuse it.

    private var cachedToken: (token: String, expiry: Date)?

    private func generateJWT() throws -> String {
        // Return cached token if still valid
        if let cached = cachedToken, cached.expiry > Date().addingTimeInterval(60) {
            return cached.token
        }

        guard
            let keyID       = Bundle.main.object(forInfoDictionaryKey: "WEATHERKIT_KEY_ID")      as? String,
            let serviceID   = Bundle.main.object(forInfoDictionaryKey: "WEATHERKIT_SERVICE_ID")  as? String,
            let teamID      = Bundle.main.object(forInfoDictionaryKey: "WEATHERKIT_TEAM_ID")     as? String
        else {
            throw ServiceError.missingData("WeatherKit config keys")
        }

        // Load .p8 private key from bundle
        guard let keyURL  = Bundle.main.url(forResource: "AuthKey_\(keyID)", withExtension: "p8"),
              let keyData  = try? Data(contentsOf: keyURL),
              let keyString = String(data: keyData, encoding: .utf8)
        else {
            throw ServiceError.missingData("WeatherKit .p8 key file")
        }

        let now = Date()
        let expiry = now.addingTimeInterval(1800)  // 30 minutes

        // Build JWT header + payload
        let header = ["alg": "ES256", "id": "\(teamID).\(serviceID)", "kid": keyID]
        let payload: [String: Any] = [
            "iss": teamID,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(expiry.timeIntervalSince1970),
            "sub": serviceID,
        ]

        let headerB64  = try base64url(JSONSerialization.data(withJSONObject: header))
        let payloadB64 = try base64url(JSONSerialization.data(withJSONObject: payload))
        let signingInput = "\(headerB64).\(payloadB64)"

        // Sign with ES256 using the P8 private key
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: keyString)
        let signature  = try privateKey.signature(for: Data(signingInput.utf8))
        let sigB64     = base64url(signature.rawRepresentation)

        let token = "\(signingInput).\(sigB64)"
        cachedToken = (token, expiry)
        return token
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - WeatherKit response models
private struct WKResponse: Decodable {
    let currentWeather:  WKCurrent?
    let hourlyForecast:  WKHourlyForecast?
    let dailyForecast:   WKDailyForecast?
}

private struct WKCurrent: Decodable {
    let conditionCode:          String
    let temperature:            Double
    let temperatureApparent:    Double
    let humidity:               Double
    let precipitationIntensity: Double
    let pressure:               Double
    let uvIndex:                Int
    let visibility:             Double
    let wind:                   WKWind
}

private struct WKHourlyForecast: Decodable {
    let hours: [WKHour]
}

private struct WKHour: Decodable {
    let forecastStart:       Date
    let conditionCode:       String
    let temperature:         Double
    let precipitationChance: Double
    let precipitationAmount: Double
    let uvIndex:             Int
    let wind:                WKWind
}

private struct WKDailyForecast: Decodable {
    let days: [WKDay]
}

private struct WKDay: Decodable {
    let forecastStart:       Date
    let conditionCode:       String
    let temperatureMax:      Double
    let temperatureMin:      Double
    let precipitationChance: Double
    let precipitationAmount: Double
    let maxUvIndex:          Int
    let sunrise:             Date?
    let sunset:              Date?
    let daytimeForecast:     WKDaytimeForecast?
}

private struct WKDaytimeForecast: Decodable {
    let wind: WKWind
}

private struct WKWind: Decodable {
    let speed:     Double
    let direction: Int
    let gust:      Double?
}
