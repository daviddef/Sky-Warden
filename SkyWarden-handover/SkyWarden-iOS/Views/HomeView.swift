// SkyWarden — Now tab
// Rating banner · comfort dial · pills · confidence strip · on-this-day · hourly.
// Nothing else lives here (moon/tides/etc. have their own tabs) per the handover.

import SwiftUI
import CoreLocation

struct HomeView: View {
    let consensus: ConsensusWeather
    let failedSources: [WeatherSource]
    let location: CLLocation
    let placeName: String?

    @State private var selectedMetric: ComfortMetric?
    @State private var onThisDay: OnThisDay?

    private var comfort: ComfortData { ComfortData(consensus: consensus) }

    // Confidence recomputed from the dial's own five-ring flags (matches the rings).
    private var confidence: Double {
        let w: [ComfortMetric: Double] = [.temp: 0.3, .rain: 0.3, .wind: 0.2, .uv: 0.1, .humidity: 0.1]
        let penalty = comfort.rings.reduce(0.0) { acc, r in
            acc + (r.isMajor ? (w[r.metric] ?? 0.1) * 0.9
                             : r.isMinor ? (w[r.metric] ?? 0.1) * 0.4 : 0)
        }
        return max(0, 1 - penalty)
    }
    private var flagCount: Int { comfort.rings.filter(\.hasFlag).count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ratingBanner
                    .padding(.horizontal, 20).padding(.top, 14)

                ComfortDialView(data: comfort, selected: $selectedMetric)
                    .padding(.top, 8)

                pills.padding(.horizontal, 16).padding(.top, 8)

                if !failedSources.isEmpty {
                    FailedSourcesNotice(sources: failedSources)
                        .padding(.horizontal, 16).padding(.top, 10)
                }

                confidenceStrip.padding(.horizontal, 16).padding(.top, 10)
                onThisDayCard.padding(.horizontal, 16).padding(.top, 10)
                hourly.padding(.top, 12)

                Spacer(minLength: 20)
            }
        }
        .task(id: location.coordinate.latitude) {
            onThisDay = try? await HistoricalService().onThisDay(location: location)
        }
    }

    // MARK: - Rating banner
    private var ratingBanner: some View {
        let r = ratingText(for: comfort,
                           season: currentSeason(latitude: location.coordinate.latitude),
                           place: placeName ?? "your area")
        return HStack(alignment: .top, spacing: 10) {
            Text(r.emoji).font(.system(size: 28))
            Text(r.text)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Sky.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Pills (mirror the ring taps, bigger touch target)
    private var pills: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(comfort.rings) { r in
                let color = Comfort.needleColor(r.metric, r.score)
                let isTapped = selectedMetric == r.metric
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMetric = isTapped ? nil : r.metric
                    }
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Text(r.metric.emoji).font(.system(size: 17))
                            Text(r.metric.format(r.value))
                                .font(.system(size: 16, weight: .bold)).foregroundColor(color)
                        }
                        if r.hasFlag {
                            Text("\(r.isMajor ? "🚨" : "⚠️") varies")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(r.isMajor ? Sky.red : Sky.amber)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.vertical, 10).padding(.horizontal, 6)
                    .background(isTapped ? color.opacity(0.13) : Sky.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(isTapped ? color.opacity(0.45) : .clear, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Confidence strip
    private var confidenceStrip: some View {
        let color = confidence >= 0.8 ? Sky.green : confidence >= 0.5 ? Sky.amber : Sky.red
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Sky.card).frame(height: 4)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * confidence, height: 4)
                }
            }
            .frame(height: 4)
            Text("\(Int((confidence * 100).rounded()))% conf")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(color)
            if flagCount > 0 {
                Text("⚠️ \(flagCount) vary").font(.system(size: 11)).foregroundColor(Sky.amber)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Sky.surface).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - On this day
    private var onThisDayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📅 ON THIS DAY")
                .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
            HStack(spacing: 0) {
                column(value: "\(Int(consensus.temperature.rounded()))°", diff: nil,
                       label: "today", big: true, first: true)
                column(value: onThisDay?.oneYear,  label: "1 yr ago")
                column(value: onThisDay?.fiveYear, label: "5 yrs ago")
                column(value: onThisDay?.average,  label: "30yr avg")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func column(value: Double?, label: String) -> some View {
        let today = consensus.temperature
        let diff = value.map { today - $0 }
        return column(
            value: value.map { "\(Int($0.rounded()))°" } ?? "—",
            diff: diff,
            label: label, big: false, first: false
        )
    }

    private func column(value: String, diff: Double?, label: String, big: Bool, first: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: big ? 20 : 15, weight: big ? .ultraLight : .light, design: .rounded))
                .foregroundColor(big ? Sky.white : Sky.text)
            if let diff, abs(diff) >= 0.5 {
                let d = Int(diff.rounded())
                Text("\(d > 0 ? "+" : "")\(d)°")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(d > 0 ? Sky.red : d < 0 ? Sky.rain : Sky.muted)
            } else {
                Text(" ").font(.system(size: 9))
            }
            Text(label).font(.system(size: 8)).foregroundColor(Sky.muted)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if !first { Rectangle().fill(Sky.surface).frame(width: 1) }
        }
    }

    // MARK: - Hourly strip
    private var hourly: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOURLY")
                .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(consensus.hourlyForecast.prefix(12).enumerated()), id: \.element.id) { i, h in
                        VStack(spacing: 3) {
                            Text(i == 0 ? "Now" : h.hourLabel)
                                .font(.system(size: 10)).foregroundColor(Sky.muted)
                            Text(h.condition.emoji).font(.system(size: 18)).padding(.vertical, 3)
                            Text("\(Int(h.temperature.rounded()))°")
                                .font(.system(size: 13, weight: .medium)).foregroundColor(Sky.white)
                            Text("\(Int(h.rainProbability.rounded()))%")
                                .font(.system(size: 9)).foregroundColor(Sky.rain)
                        }
                        .frame(minWidth: 52)
                        .padding(.vertical, 8).padding(.horizontal, 6)
                        .background(i == 0 ? Sky.surface : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Failed sources notice
private struct FailedSourcesNotice: View {
    let sources: [WeatherSource]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 12)).foregroundColor(Sky.muted)
            Text("\(sources.map(\.short).joined(separator: ", ")) unavailable — consensus from remaining sources")
                .font(.system(size: 10)).foregroundColor(Sky.muted)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Sky.surface).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Reusable section header (used by other tabs too)
struct SectionHeader: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(SkyType.sectionHead).foregroundColor(Sky.muted)
            .textCase(.uppercase).kerning(0.8)
    }
}
