// SkyWarden — Apple WeatherKit (native framework)
// Preferred path per HANDOVER.md: use the `import WeatherKit` Swift framework
// rather than the REST API — no manual JWT signing, Apple handles auth via the
// WeatherKit capability (Signing & Capabilities → WeatherKit).
//
// Requires: iOS 16+, the WeatherKit capability, and a paid Apple Developer
// account for the App ID. Without those it throws at runtime and the aggregator
// simply drops this source (graceful degradation).

import Foundation
import CoreLocation
import WeatherKit

struct WeatherKitService {

    private let service = WeatherService.shared

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> WeatherReading {
        let weather = try await service.weather(for: location)
        return map(weather)
    }

    // MARK: - Map WeatherKit → WeatherReading
    private func map(_ w: Weather) -> WeatherReading {
        let current = w.currentWeather

        let hourly: [HourlyReading] = w.hourlyForecast.forecast.prefix(24).map { h in
            HourlyReading(
                time:            h.date,
                temperature:     h.temperature.converted(to: .celsius).value,
                rainProbability: h.precipitationChance * 100,
                rainAmount:      h.precipitationAmount.converted(to: .millimeters).value,
                windSpeed:       h.wind.speed.converted(to: .kilometersPerHour).value,
                condition:       condition(from: h.condition),
                uvIndex:         Double(h.uvIndex.value)
            )
        }

        let daily: [DailyReading] = w.dailyForecast.forecast.prefix(7).map { d in
            DailyReading(
                date:            d.date,
                tempMax:         d.highTemperature.converted(to: .celsius).value,
                tempMin:         d.lowTemperature.converted(to: .celsius).value,
                rainProbability: d.precipitationChance * 100,
                rainAmount:      d.precipitationAmount.converted(to: .millimeters).value,
                windSpeed:       d.wind.speed.converted(to: .kilometersPerHour).value,
                condition:       condition(from: d.condition),
                uvIndexMax:      Double(d.uvIndex.value),
                sunrise:         d.sun.sunrise,
                sunset:          d.sun.sunset
            )
        }

        return WeatherReading(
            source:          .weatherKit,
            fetchedAt:       Date(),
            temperature:     current.temperature.converted(to: .celsius).value,
            feelsLike:       current.apparentTemperature.converted(to: .celsius).value,
            tempMin:         daily.first?.tempMin,
            tempMax:         daily.first?.tempMax,
            rainProbability: hourly.first?.rainProbability ?? 0,
            rainAmount:      current.precipitationIntensity.value,
            windSpeed:       current.wind.speed.converted(to: .kilometersPerHour).value,
            windGust:        current.wind.gust?.converted(to: .kilometersPerHour).value,
            windDirection:   Int(current.wind.direction.converted(to: .degrees).value),
            humidity:        current.humidity * 100,
            uvIndex:         Double(current.uvIndex.value),
            visibility:      current.visibility.converted(to: .kilometers).value,
            pressure:        current.pressure.converted(to: .hectopascals).value,
            condition:       condition(from: current.condition),
            hourlyForecast:  hourly,
            dailyForecast:   daily
        )
    }

    // MARK: - WeatherKit.WeatherCondition → app WeatherCondition
    private func condition(from c: WeatherKit.WeatherCondition) -> WeatherCondition {
        switch c {
        case .clear, .hot:                                  return .clearSky
        case .mostlyClear:                                  return .mostlyClear
        case .partlyCloudy:                                 return .partlyCloudy
        case .mostlyCloudy, .breezy, .windy:                return .mostlyCloudy
        case .cloudy:                                       return .overcast
        case .foggy, .haze, .smoky:                         return .fog
        case .drizzle, .freezingDrizzle:                    return .drizzle
        case .rain, .sunShowers, .freezingRain:             return .rain
        case .heavyRain:                                    return .heavyRain
        case .thunderstorms, .isolatedThunderstorms,
             .scatteredThunderstorms, .strongStorms,
             .hurricane, .tropicalStorm:                    return .thunderstorm
        case .snow, .flurries, .heavySnow, .blizzard,
             .blowingSnow, .sleet, .hail, .wintryMix,
             .sunFlurries:                                  return .snow
        default:                                            return .partlyCloudy
        }
    }
}
