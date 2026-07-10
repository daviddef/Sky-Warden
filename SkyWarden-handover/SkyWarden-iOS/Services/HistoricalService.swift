// SkyWarden — Historical "On This Day"
// Open-Meteo ERA5 archive (free, no key, back to 1940).
// Returns this-calendar-day's max temperature 1 year ago, 5 years ago, and the
// 1991–2020 WMO climate normal for the same day.

import Foundation
import CoreLocation

struct OnThisDay {
    let oneYear: Double?
    let fiveYear: Double?
    let average: Double?   // 30-year normal for this calendar day
}

struct HistoricalService {
    private let baseURL = "https://archive-api.open-meteo.com/v1/archive"

    func onThisDay(location: CLLocation, now: Date = Date()) async throws -> OnThisDay {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)

        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            .init(name: "latitude",  value: "\(location.coordinate.latitude)"),
            .init(name: "longitude", value: "\(location.coordinate.longitude)"),
            .init(name: "start_date", value: "1991-01-01"),
            .init(name: "end_date",   value: String(format: "%04d-%02d-%02d", year - 1, month, day)),
            .init(name: "daily",      value: "temperature_2m_max"),
            .init(name: "timezone",   value: "auto"),
        ]
        guard let url = comps.url else { throw ServiceError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let raw = try JSONDecoder().decode(ArchiveResponse.self, from: data)
        guard let times = raw.daily?.time, let temps = raw.daily?.temperature2mMax else {
            throw ServiceError.missingData("archive daily")
        }

        // Map "YYYY-MM-DD" → max, keeping only this calendar day.
        let suffix = String(format: "-%02d-%02d", month, day)
        var byYear: [Int: Double] = [:]
        var normals: [Double] = []
        for (i, t) in times.enumerated() where t.hasSuffix(suffix) {
            guard let v = temps[safe: i] ?? nil else { continue }
            if let y = Int(t.prefix(4)) {
                byYear[y] = v
                if (1991...2020).contains(y) { normals.append(v) }
            }
        }

        let avg = normals.isEmpty ? nil : normals.reduce(0, +) / Double(normals.count)
        return OnThisDay(
            oneYear:  byYear[year - 1],
            fiveYear: byYear[year - 5],
            average:  avg
        )
    }
}

private struct ArchiveResponse: Decodable {
    let daily: ArchiveDaily?
}
private struct ArchiveDaily: Decodable {
    let time: [String]?
    let temperature2mMax: [Double?]?
    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax = "temperature_2m_max"
    }
}
