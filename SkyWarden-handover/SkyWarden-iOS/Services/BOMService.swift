// Sky Warden — BOM (Bureau of Meteorology) Service
// Australian observations. No API key.
//
// Endpoint: https://www.bom.gov.au/fwo/{product}/{product}.{wmo}.json
//   · Served over HTTPS (BOM redirects HTTP → HTTPS, so no ATS exception is needed).
//   · BOM returns 403 without a User-Agent header.
//   · The file is a 72-hour time series for ONE station; data[0] is the latest obs.
//
// BOM covers Australia only. Outside it we throw `.notApplicable` so the
// aggregator skips the source rather than reporting it as "unavailable".

import Foundation
import CoreLocation

struct BOMService {

    struct Station {
        let lat: Double, lon: Double
        let product: String, wmo: String, name: String
    }

    // Each (product, wmo) pair verified to return HTTP 200.
    private static let stations: [Station] = [
        .init(lat: -27.50, lon: 153.00, product: "IDQ60801", wmo: "94576", name: "Brisbane"),
        .init(lat: -27.40, lon: 153.10, product: "IDQ60801", wmo: "94578", name: "Brisbane Airport"),
        .init(lat: -28.20, lon: 153.50, product: "IDQ60801", wmo: "94592", name: "Coolangatta"),
        .init(lat: -33.90, lon: 151.20, product: "IDN60901", wmo: "94768", name: "Sydney"),
        .init(lat: -35.30, lon: 149.20, product: "IDN60903", wmo: "94926", name: "Canberra"),
        .init(lat: -37.80, lon: 145.00, product: "IDV60801", wmo: "95936", name: "Melbourne"),
        .init(lat: -31.90, lon: 115.90, product: "IDW60801", wmo: "94608", name: "Perth"),
        .init(lat: -34.90, lon: 138.60, product: "IDS60801", wmo: "94648", name: "Adelaide"),
        .init(lat: -42.90, lon: 147.30, product: "IDT60801", wmo: "94970", name: "Hobart"),
        .init(lat: -12.40, lon: 130.90, product: "IDD60801", wmo: "94120", name: "Darwin"),
    ]

    /// Rough Australian bounding box (includes Tasmania and Cape York).
    static func covers(_ location: CLLocation) -> Bool {
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        return lat <= -9 && lat >= -44 && lon >= 112 && lon <= 154
    }

    static func nearestStation(to location: CLLocation) -> Station {
        stations.min {
            location.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon)) <
            location.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lon))
        } ?? stations[0]
    }

    // MARK: - Fetch
    func fetch(location: CLLocation) async throws -> WeatherReading {
        guard Self.covers(location) else {
            throw ServiceError.notApplicable("BOM covers Australia only")
        }

        let station = Self.nearestStation(to: location)
        let path = "https://www.bom.gov.au/fwo/\(station.product)/\(station.product).\(station.wmo).json"
        guard let url = URL(string: path) else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("SkyWarden/1.0 (iOS)", forHTTPHeaderField: "User-Agent")  // BOM 403s without this

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let raw = try JSONDecoder().decode(BOMResponse.self, from: data)
        return try parse(raw)
    }

    // MARK: - Parse
    private func parse(_ r: BOMResponse) throws -> WeatherReading {
        guard let obs = r.observations?.data?.first else {
            throw ServiceError.missingData("BOM observations")
        }

        let temp      = obs.airTemp ?? 0
        let apparent  = obs.apparentT ?? temp
        let humidity  = obs.relHum ?? 0
        let windSpeed = obs.windSpdKmh ?? 0        // already km/h — do NOT convert
        // "0.0" when dry, "-" when unavailable.
        let recentRain = obs.rainTrace.flatMap(Double.init) ?? 0

        // BOM observations are current conditions, not a forecast — this is a
        // coarse likelihood derived from recent rainfall and humidity.
        let rainProb: Double = {
            if recentRain > 5 { return 80 }
            if recentRain > 1 { return 50 }
            if humidity > 80  { return 30 }
            return 10
        }()

        return WeatherReading(
            source:          .bom,
            fetchedAt:       Date(),
            temperature:     temp,
            feelsLike:       apparent,
            tempMin:         nil,   // observation feed carries no forecast
            tempMax:         nil,
            rainProbability: rainProb,
            rainAmount:      recentRain,
            windSpeed:       windSpeed,
            windGust:        obs.gustKmh,
            windDirection:   Self.degrees(fromCompass: obs.windDir) ?? 0,
            humidity:        humidity,
            uvIndex:         nil,   // BOM observations carry no UV
            visibility:      obs.visKm.flatMap(Double.init),
            pressure:        obs.pressQnh,
            condition:       Self.condition(cloud: obs.cloud, weather: obs.weather,
                                            rain: recentRain, humidity: humidity),
            hourlyForecast:  [],
            dailyForecast:   []
        )
    }

    // MARK: - Helpers

    /// BOM reports wind direction as a compass string ("S", "SSE"), not degrees.
    static func degrees(fromCompass dir: String?) -> Int? {
        guard let dir, dir != "-", dir.uppercased() != "CALM" else { return nil }
        let points = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                      "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        guard let i = points.firstIndex(of: dir.uppercased()) else { return nil }
        return Int((Double(i) * 22.5).rounded())
    }

    /// `weather` is usually "-"; `cloud` ("Clear", "Partly cloudy", …) is the useful field.
    static func condition(cloud: String?, weather: String?, rain: Double, humidity: Double) -> WeatherCondition {
        let w = (weather ?? "").lowercased()
        if w.contains("thunder")     { return .thunderstorm }
        if w.contains("heavy rain")  { return .heavyRain }
        if w.contains("drizzle")     { return .drizzle }
        if w.contains("rain") || w.contains("shower") { return .rain }
        if w.contains("fog") || w.contains("mist")    { return .fog }
        if w.contains("snow")        { return .snow }

        let c = (cloud ?? "").lowercased()
        if c.contains("overcast")      { return .overcast }
        if c.contains("mostly cloudy") { return .mostlyCloudy }
        if c.contains("partly")        { return .partlyCloudy }
        if c.contains("mostly clear") || c.contains("mostly sunny") { return .mostlyClear }
        if c.contains("clear") || c.contains("sunny") { return .clearSky }

        // No cloud/weather report — infer from what we do have.
        if rain > 10 { return .heavyRain }
        if rain > 1  { return .rain }
        if humidity > 80 { return .mostlyCloudy }
        return .partlyCloudy
    }
}

// MARK: - BOM response models
private struct BOMResponse: Decodable { let observations: BOMObservations? }
private struct BOMObservations: Decodable { let data: [BOMObservation]? }

private struct BOMObservation: Decodable {
    let airTemp:    Double?
    let apparentT:  Double?
    let relHum:     Double?
    let windSpdKmh: Double?
    let windDir:    String?
    let gustKmh:    Double?
    let pressQnh:   Double?
    let weather:    String?
    let cloud:      String?
    let rainTrace:  String?
    let visKm:      String?

    enum CodingKeys: String, CodingKey {
        case airTemp    = "air_temp"
        case apparentT  = "apparent_t"
        case relHum     = "rel_hum"
        case windSpdKmh = "wind_spd_kmh"
        case windDir    = "wind_dir"
        case gustKmh    = "gust_kmh"
        case pressQnh   = "press_qnh"
        case weather, cloud
        case rainTrace  = "rain_trace"
        case visKm      = "vis_km"
    }
}
