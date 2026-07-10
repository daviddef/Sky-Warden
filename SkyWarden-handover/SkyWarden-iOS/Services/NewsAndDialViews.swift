// SkyWarden — Weather News Service + Multi-Ring Dial View

import Foundation
import SwiftUI
import CoreLocation

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Weather News
// ────────────────────────────────────────────────────────────────────────────

struct WeatherNewsItem: Identifiable, Codable {
    let id: String
    let headline: String
    let excerpt: String
    let source: String
    let url: URL
    let publishedAt: Date
    let impact: NewsImpact

    var timeLabel: String {
        let secs = Int(Date().timeIntervalSince(publishedAt))
        if secs < 3600  { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }

    enum NewsImpact: String, Codable {
        case high    // Severe storm, cyclone, flood — surfaces on Now tab
        case medium  // Heavy rain, wind advisory
        case low     // General interest
    }
}

// MARK: - News fetcher
// Sources: BOM Warnings RSS, ABC Weather RSS, Weatherzone (scrape)
// Aggregated via GNews API or NewsAPI (free tier: 100 requests/day)
// Key stored as NEWSAPI_KEY in Config.xcconfig

struct WeatherNewsService {

    private let newsAPIBase = "https://gnews.io/api/v4/search"

    /// `region` and `countryCode` come from reverse geocoding — nothing here is
    /// hardcoded to Australia.
    func fetchLocalNews(location: CLLocation,
                        region: String?,
                        countryCode: String?) async -> [WeatherNewsItem] {
        let apiKey = (Bundle.main.object(forInfoDictionaryKey: "GNEWS_API_KEY") as? String) ?? ""
        // Need either the proxy (key server-side) or a local key; else fall back to BOM RSS.
        guard WeatherProxy.isEnabled || !apiKey.isEmpty else {
            return await fetchBOMWarnings()
        }

        let query = ["weather", region, "forecast"].compactMap { $0 }.joined(separator: " ")
        var items: [URLQueryItem] = [
            .init(name: "q",    value: query),
            .init(name: "lang", value: "en"),
            .init(name: "max",  value: "5"),
        ]
        if let countryCode, !countryCode.isEmpty {
            items.append(.init(name: "country", value: countryCode.lowercased()))
        }

        guard let request = WeatherProxy.request(source: "gnews", directBase: newsAPIBase,
                                                 items: items, keyParam: "apikey", keyValue: apiKey) else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let raw = try? JSONDecoder().decode(GNewsResponse.self, from: data)
        else { return [] }

        let iso = ISO8601DateFormatter()
        return raw.articles.prefix(2).compactMap { a in
            guard let articleURL = URL(string: a.url),
                  let pub = iso.date(from: a.publishedAt)
            else { return nil }

            return WeatherNewsItem(
                id:          a.url,
                headline:    a.title,
                excerpt:     a.description,
                source:      a.source.name,
                url:         articleURL,
                publishedAt: pub,
                impact:      classifyImpact(headline: a.title)
            )
        }
    }

    // MARK: - BOM RSS fallback (no key needed)
    private func fetchBOMWarnings() async -> [WeatherNewsItem] {
        // BOM provides state warning summaries as RSS
        // QLD: http://www.bom.gov.au/fwo/IDQ65000.warnings_qld.xml
        // Parse as XML and return top 2 items
        // For now returns empty — implement with XMLParser in production
        return []
    }

    private func classifyImpact(headline: String) -> WeatherNewsItem.NewsImpact {
        let h = headline.lowercased()
        if h.contains("cyclone") || h.contains("flood") || h.contains("severe") ||
           h.contains("warning") || h.contains("emergency") { return .high }
        if h.contains("heavy rain") || h.contains("storm") || h.contains("wind") { return .medium }
        return .low
    }
}

private struct GNewsResponse: Decodable {
    let articles: [GNewsArticle]
}
private struct GNewsArticle: Decodable {
    let title: String
    let description: String
    let url: String
    let publishedAt: String
    let source: GNewsSource
}
private struct GNewsSource: Decodable { let name: String }

// ────────────────────────────────────────────────────────────────────────────
// MARK: - 5-Ring Dial SwiftUI View
// ────────────────────────────────────────────────────────────────────────────

// Ring configuration — outermost to innermost
struct RingConfig: Identifiable {
    let id: String
    let label: String
    let unit: String
    let arcColor: (Double) -> Color    // value 0–1 → colour
    let trackColor: Color
    let lineWidth: CGFloat
}

let skyRings: [RingConfig] = [
    RingConfig(
        id: "consensus", label: "Consensus", unit: "%",
        arcColor: { v in Sky.confidenceColor(v) },
        trackColor: Sky.surface, lineWidth: 8
    ),
    RingConfig(
        id: "temp", label: "Temp", unit: "°C",
        arcColor: { v in
            // Cold (blue) → warm (orange) → hot (red)
            if v < 0.3 { return Color(hex: "5BA3D4") }
            if v < 0.6 { return Color(hex: "3DD68C") }
            if v < 0.8 { return Color(hex: "F5A623") }
            return Color(hex: "E05555")
        },
        trackColor: Color(hex: "2D1515"), lineWidth: 8
    ),
    RingConfig(
        id: "rain", label: "Rain", unit: "%",
        arcColor: { v in
            // White when dry, deepening blue with rain
            Color(
                red: 1.0 - v * 0.65,
                green: 1.0 - v * 0.35,
                blue: 1.0
            )
        },
        trackColor: Color(hex: "0D1F2D"), lineWidth: 8
    ),
    RingConfig(
        id: "tide", label: "Tide", unit: "m",
        arcColor: { v in
            // Low (grey) → mid (teal) → high (bright teal)
            Color(
                red: 0.0,
                green: 0.3 + v * 0.5,
                blue: 0.4 + v * 0.36
            )
        },
        trackColor: Color(hex: "0D2825"), lineWidth: 8
    ),
    RingConfig(
        id: "wind", label: "Wind", unit: "km/h",
        arcColor: { v in
            // Calm (soft lavender) → strong (vivid purple)
            Color(
                red: 0.4 + v * 0.3,
                green: 0.2 - v * 0.1,
                blue: 0.7 + v * 0.3
            )
        },
        trackColor: Color(hex: "1A1535"), lineWidth: 8
    ),
]

struct FiveRingDialView: View {
    let consensus: ConsensusWeather
    let tideHeight: Double
    let tideMax: Double
    @Binding var selectedRing: String?

    // Ring radii: outermost first
    private let baseRadius: CGFloat = 106
    private let ringSpacing: CGFloat = 16
    private let dialSize: CGFloat = 260
    private let arcSweep: Double = 300
    private let arcStartDeg: Double = 120  // start at bottom-left

    var body: some View {
        ZStack {
            // Rings (outermost → innermost)
            ForEach(Array(skyRings.enumerated()), id: \.element.id) { (i, ring) in
                let radius = baseRadius - CGFloat(i) * ringSpacing
                let value  = ringValue(ring.id)
                let isSelected = selectedRing == ring.id

                RingArc(
                    radius:      radius,
                    center:      CGPoint(x: dialSize / 2, y: dialSize / 2),
                    startDeg:    arcStartDeg,
                    sweepDeg:    arcSweep,
                    fillFraction: value,
                    fillColor:   ring.arcColor(value),
                    trackColor:  ring.trackColor,
                    lineWidth:   isSelected ? 11 : ring.lineWidth
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        selectedRing = selectedRing == ring.id ? nil : ring.id
                    }
                }
            }

            // Centre content
            VStack(spacing: 4) {
                if let sel = selectedRing, let ring = skyRings.first(where: { $0.id == sel }) {
                    Text(displayValue(sel))
                        .font(SkyType.mediumTemp)
                        .foregroundColor(ring.arcColor(ringValue(sel)))
                    Text(ring.label.uppercased())
                        .font(SkyType.micro)
                        .foregroundColor(Sky.muted)
                        .kerning(0.8)
                    Text(ring.unit)
                        .font(SkyType.micro)
                        .foregroundColor(Sky.muted)
                } else {
                    Text(consensus.temperatureDisplay)
                        .font(SkyType.largeTemp)
                        .foregroundColor(Sky.white)
                    Text(consensus.condition.rawValue)
                        .font(SkyType.caption)
                        .foregroundColor(Sky.muted)
                    Text("\(Int((consensus.confidence * 100).rounded()))% consensus")
                        .font(SkyType.micro)
                        .foregroundColor(Sky.confidenceColor(consensus.confidence))
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: dialSize, height: dialSize)
    }

    // MARK: - Value mapping (0.0 – 1.0)
    private func ringValue(_ id: String) -> Double {
        switch id {
        case "consensus": return consensus.confidence
        case "temp":      return min(1, max(0, consensus.temperature / 45.0))
        case "rain":      return consensus.rainProbability / 100.0
        case "tide":      return tideMax > 0 ? min(1, tideHeight / tideMax) : 0
        case "wind":      return min(1, consensus.windSpeed / 80.0)
        default:          return 0
        }
    }

    private func displayValue(_ id: String) -> String {
        switch id {
        case "consensus": return "\(Int((consensus.confidence * 100).rounded()))%"
        case "temp":      return "\(Int(consensus.temperature.rounded()))°"
        case "rain":      return "\(Int(consensus.rainProbability.rounded()))%"
        case "tide":      return String(format: "%.1fm", tideHeight)
        case "wind":      return "\(Int(consensus.windSpeed.rounded()))"
        default:          return ""
        }
    }
}

// MARK: - Ring Arc shape
struct RingArc: View {
    let radius: CGFloat
    let center: CGPoint
    let startDeg: Double      // where arc starts (degrees clockwise from 12)
    let sweepDeg: Double      // total arc sweep
    let fillFraction: Double  // 0.0–1.0
    let fillColor: Color
    let trackColor: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            // Track (empty arc)
            Arc(center: center, radius: radius, startDeg: startDeg, endDeg: startDeg + sweepDeg)
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Fill
            if fillFraction > 0.01 {
                Arc(center: center, radius: radius,
                    startDeg: startDeg,
                    endDeg: startDeg + sweepDeg * fillFraction)
                    .stroke(fillColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .animation(.easeOut(duration: 0.5), value: fillFraction)
            }
        }
    }
}

// MARK: - Arc path helper
struct Arc: Shape {
    let center: CGPoint
    let radius: CGFloat
    let startDeg: Double
    let endDeg: Double

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(
                center:     center,
                radius:     radius,
                startAngle: .degrees(startDeg - 90),   // 0 = 12 o'clock
                endAngle:   .degrees(endDeg - 90),
                clockwise:  false
            )
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Watch Complication (Updated: Temp + Rain rings)
// ────────────────────────────────────────────────────────────────────────────

// In SkyWardenComplications.swift, update CircularComplicationView:
// Replace the existing body with this two-ring version showing Temp + Rain.
//
// Ring layout (inside out):
//   Inner ring: Rain probability (white → blue)
//   Outer ring: Temperature (blue cold → green mild → orange warm → red hot)
//
// This is already implemented in SkyWardenComplications.swift:
//   rings array now contains .temp (outer) and .rain (inner)
//
// The WatchComplication preview in the prototype shows the correct rendering.
// No additional Swift changes needed here beyond what's in SkyWardenComplications.swift.

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Ring Legend View (below the dial)
// ────────────────────────────────────────────────────────────────────────────

struct RingLegendView: View {
    @Binding var selectedRing: String?
    let consensus: ConsensusWeather
    let tideHeight: Double
    let tideMax: Double

    var body: some View {
        // Two rows of pills to avoid wrapping
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(skyRings.prefix(3)) { ring in
                    RingPill(ring: ring, isSelected: selectedRing == ring.id) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedRing = selectedRing == ring.id ? nil : ring.id
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(skyRings.suffix(2)) { ring in
                    RingPill(ring: ring, isSelected: selectedRing == ring.id) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedRing = selectedRing == ring.id ? nil : ring.id
                        }
                    }
                }
            }
        }
    }
}

private struct RingPill: View {
    let ring: RingConfig
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ring.arcColor(0.6))
                    .frame(width: 7, height: 7)
                Text(ring.label)
                    .font(SkyType.micro)
                    .foregroundColor(isSelected ? Sky.white : Sky.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected
                ? ring.arcColor(0.6).opacity(0.2)
                : Sky.surface)
            .overlay(
                Capsule().stroke(
                    isSelected ? ring.arcColor(0.6).opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
    }
}
