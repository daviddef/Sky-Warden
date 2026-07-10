// SkyWarden — BOM (Bureau of Meteorology) Service
// Uses BOM's unofficial JSON API (the same feed the BOM app uses)
// No API key required. AU only.
// Endpoint: http://www.bom.gov.au/fwo/{stationCode}.json

import Foundation
import CoreLocation

struct BOMService {

    // MARK: - Station lookup
    // BOM stations nearest to major AU cities — expanded via reverse geocode in production
    private static let stations: [(lat: Double, lon: Double, code: String, state: String)] = [
        // QLD
        (-27.48, 153.04, "IDQ60901", "QLD"),   // Brisbane
        (-27.91, 153.35, "IDQ60901", "QLD"),   // Gold Coast / Hope Island region
        // NSW
        (-33.87, 151.21, "IDN60901", "NSW"),
        // VIC
        (-37.81, 144.96, "IDV60901", "VIC"),
        // WA
        (-31.95, 115.86, "IDW60901", "WA"),
        // SA
        (-34.93, 138.60, "IDS60901", "SA"),
        // TAS
        (-42.88, 147.32, "IDT60901", "TAS"),
        // NT
        (-12.46, 130.84, "IDD60901", "NT"),
    ]

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> WeatherReading {
        let station = nearestStation(to: location)
        let urlString = "http://www.bom.gov.au/fwo/\(station.code).json"

        // NOTE: BOM uses HTTP not HTTPS for their data feeds.
        // Add NSAllowsArbitraryLoads or specific domain exception in Info.plist:
        // NSExceptionDomains → www.bom.gov.au → NSExceptionAllowsInsecureHTTPLoads = YES
        guard let url = URL(string: urlString) else { throw ServiceError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let raw = try JSONDecoder().decode(BOMResponse.self, from: data)
        return try parse(raw, station: station)
    }

    // MARK: - Parse
    private func parse(_ r: BOMResponse, station: (lat: Double, lon: Double, code: String, state: String)) throws -> WeatherReading {
        guard let obs = r.observations?.data?.first else {
            throw ServiceError.missingData("BOM observations")
        }

        let temp      = obs.airTemp ?? 0
        let apparent  = obs.apparentT ?? temp
        let humidity  = obs.relHum ?? 0
        let windSpeed = (obs.windSpd ?? 0) * 3.6    // knots → km/h... actually BOM uses km/h already
        let windDir   = obs.windDirDeg ?? 0
        let pressure  = obs.pressQnh

        // BOM doesn't provide rain probability directly in observation feed
        // Use a conservative estimate based on relative humidity + recent rainfall
        let recentRain = obs.rain_trace.flatMap { Double($0.replacingOccurrences(of: "-", with: "0")) } ?? 0
        let rainProb: Double = {
            if recentRain > 5 { return 80 }
            if recentRain > 1 { return 50 }
            if humidity > 80  { return 30 }
            return 10
        }()

        let condition = bomCondition(from: obs.weather ?? "", temp: temp, rain: recentRain, humidity: humidity)

        return WeatherReading(
            source:          .bom,
            fetchedAt:       Date(),
            temperature:     temp,
            feelsLike:       apparent,
            tempMin:         nil,   // not in observation feed; add via forecast product
            tempMax:         nil,
            rainProbability: rainProb,
            rainAmount:      recentRain,
            windSpeed:       windSpeed,
            windGust:        obs.gustKmh,
            windDirection:   windDir,
            humidity:        humidity,
            uvIndex:         0,     // not in BOM observation JSON
            visibility:      obs.vis_km.flatMap { Double($0) },
            pressure:        pressure,
            condition:       condition,
            hourlyForecast:  [],    // BOM hourly requires separate forecast product
            dailyForecast:   []
        )
    }

    // MARK: - BOM condition string → WeatherCondition
    private func bomCondition(from weather: String, temp: Double, rain: Double, humidity: Double) -> WeatherCondition {
        let w = weather.lowercased()
        if w.contains("thunder") { return .thunderstorm }
        if w.contains("heavy rain") || rain > 10 { return .heavyRain }
        if w.contains("rain") || rain > 1 { return .rain }
        if w.contains("drizzle") { return .drizzle }
        if w.contains("fog") || w.contains("mist") { return .fog }
        if w.contains("snow") { return .snow }
        if w.contains("overcast") { return .overcast }
        if w.contains("mostly cloudy") || w.contains("cloudy") { return .mostlyCloudy }
        if w.contains("partly cloudy") || humidity > 60 { return .partlyCloudy }
        if w.contains("clear") || w.contains("sunny") { return .clearSky }
        return .partlyCloudy
    }

    // MARK: - Find nearest station
    private func nearestStation(to location: CLLocation) -> (lat: Double, lon: Double, code: String, state: String) {
        return Self.stations.min(by: { a, b in
            let la = CLLocation(latitude: a.lat, longitude: a.lon)
            let lb = CLLocation(latitude: b.lat, longitude: b.lon)
            return location.distance(from: la) < location.distance(from: lb)
        }) ?? Self.stations[0]
    }
}

// MARK: - BOM Response models
private struct BOMResponse: Decodable {
    let observations: BOMObservations?
}

private struct BOMObservations: Decodable {
    let data: [BOMObservation]?
}

private struct BOMObservation: Decodable {
    let airTemp:    Double?
    let apparentT:  Double?
    let relHum:     Double?
    let windSpd:    Double?
    let windDirDeg: Int?
    let gustKmh:    Double?
    let pressQnh:   Double?
    let weather:    String?
    let rain_trace: String?
    let vis_km:     String?

    enum CodingKeys: String, CodingKey {
        case airTemp    = "air_temp"
        case apparentT  = "apparent_t"
        case relHum     = "rel_hum"
        case windSpd    = "wind_spd_kmh"
        case windDirDeg = "wind_dir_deg"
        case gustKmh    = "gust_kmh"
        case pressQnh   = "press_qnh"
        case weather    = "weather"
        case rain_trace = "rain_trace"
        case vis_km     = "vis_km"
    }
}
