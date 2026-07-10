// SkyWarden — OpenWeatherMap Service
// Requires free API key: https://openweathermap.org/api
// Uses One Call API 3.0 (free tier: 1000 calls/day)

import Foundation
import CoreLocation

struct OpenWeatherService {

    private let baseURL = "https://api.openweathermap.org/data/3.0/onecall"
    private let apiKey: String

    init() {
        // Read from Config.xcconfig via Info.plist
        self.apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENWEATHER_API_KEY") as? String ?? ""
    }

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> WeatherReading {
        guard !apiKey.isEmpty else { throw ServiceError.missingData("OPENWEATHER_API_KEY") }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            .init(name: "lat",     value: "\(lat)"),
            .init(name: "lon",     value: "\(lon)"),
            .init(name: "appid",   value: apiKey),
            .init(name: "units",   value: "metric"),
            .init(name: "exclude", value: "minutely,alerts"),
        ]

        guard let url = components.url else { throw ServiceError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let raw = try JSONDecoder().decode(OWResponse.self, from: data)
        return parse(raw)
    }

    // MARK: - Parse
    private func parse(_ r: OWResponse) -> WeatherReading {
        let current = r.current
        let condition = owCondition(from: current.weather.first?.id ?? 800)

        let hourlyReadings: [HourlyReading] = (r.hourly ?? []).prefix(24).map { h in
            HourlyReading(
                time:             Date(timeIntervalSince1970: TimeInterval(h.dt)),
                temperature:      h.temp,
                rainProbability:  (h.pop ?? 0) * 100,
                rainAmount:       h.rain?.oneH ?? 0,
                windSpeed:        h.windSpeed * 3.6,   // m/s → km/h
                condition:        owCondition(from: h.weather.first?.id ?? 800),
                uvIndex:          h.uvi ?? 0
            )
        }

        let dailyReadings: [DailyReading] = (r.daily ?? []).map { d in
            DailyReading(
                date:             Date(timeIntervalSince1970: TimeInterval(d.dt)),
                tempMax:          d.temp.max,
                tempMin:          d.temp.min,
                rainProbability:  (d.pop ?? 0) * 100,
                rainAmount:       d.rain ?? 0,
                windSpeed:        d.windSpeed * 3.6,
                condition:        owCondition(from: d.weather.first?.id ?? 800),
                uvIndexMax:       d.uvi,
                sunrise:          Date(timeIntervalSince1970: TimeInterval(d.sunrise ?? 0)),
                sunset:           Date(timeIntervalSince1970: TimeInterval(d.sunset ?? 0))
            )
        }

        return WeatherReading(
            source:          .openWeather,
            fetchedAt:       Date(),
            temperature:     current.temp,
            feelsLike:       current.feelsLike,
            tempMin:         dailyReadings.first?.tempMin,
            tempMax:         dailyReadings.first?.tempMax,
            rainProbability: (hourlyReadings.first?.rainProbability ?? 0),
            rainAmount:      current.rain?.oneH ?? 0,
            windSpeed:       current.windSpeed * 3.6,  // m/s → km/h
            windGust:        current.windGust.map { $0 * 3.6 },
            windDirection:   current.windDeg,
            humidity:        Double(current.humidity),
            uvIndex:         current.uvi ?? 0,
            visibility:      current.visibility.map { Double($0) / 1000 },
            pressure:        Double(current.pressure),
            condition:       condition,
            hourlyForecast:  hourlyReadings,
            dailyForecast:   dailyReadings
        )
    }

    // MARK: - OWM condition codes → WeatherCondition
    private func owCondition(from id: Int) -> WeatherCondition {
        switch id {
        case 800:        return .clearSky
        case 801:        return .mostlyClear
        case 802:        return .partlyCloudy
        case 803:        return .mostlyCloudy
        case 804:        return .overcast
        case 300...321:  return .drizzle
        case 500...501:  return .rain
        case 502...504:  return .heavyRain
        case 511:        return .rain
        case 520...531:  return .rain
        case 600...622:  return .snow
        case 700...781:  return .fog
        case 200...232:  return .thunderstorm
        default:         return .partlyCloudy
        }
    }
}

// MARK: - Decodable models
private struct OWResponse: Decodable {
    let current: OWCurrent
    let hourly:  [OWHourly]?
    let daily:   [OWDaily]?
}

private struct OWCurrent: Decodable {
    let dt:         Int
    let temp:       Double
    let feelsLike:  Double
    let pressure:   Int
    let humidity:   Int
    let uvi:        Double?
    let visibility: Int?
    let windSpeed:  Double
    let windDeg:    Int
    let windGust:   Double?
    let weather:    [OWWeather]
    let rain:       OWRain?

    enum CodingKeys: String, CodingKey {
        case dt, temp, pressure, humidity, uvi, visibility, weather, rain
        case feelsLike  = "feels_like"
        case windSpeed  = "wind_speed"
        case windDeg    = "wind_deg"
        case windGust   = "wind_gust"
    }
}

private struct OWHourly: Decodable {
    let dt:        Int
    let temp:      Double
    let pop:       Double?
    let uvi:       Double?
    let windSpeed: Double
    let weather:   [OWWeather]
    let rain:      OWRain?

    enum CodingKeys: String, CodingKey {
        case dt, temp, pop, uvi, weather, rain
        case windSpeed = "wind_speed"
    }
}

private struct OWDaily: Decodable {
    let dt:        Int
    let sunrise:   Int?
    let sunset:    Int?
    let temp:      OWTemp
    let pop:       Double?
    let rain:      Double?
    let windSpeed: Double
    let uvi:       Double
    let weather:   [OWWeather]

    enum CodingKeys: String, CodingKey {
        case dt, sunrise, sunset, temp, pop, rain, uvi, weather
        case windSpeed = "wind_speed"
    }
}

private struct OWTemp: Decodable {
    let min: Double
    let max: Double
}

private struct OWWeather: Decodable {
    let id:          Int
    let main:        String
    let description: String
}

private struct OWRain: Decodable {
    let oneH: Double?
    enum CodingKeys: String, CodingKey { case oneH = "1h" }
}
