// Sky Warden — Simple Now view
//
// The answer to "users find it complicated". Same data as the dial, reframed as
// the fastest possible read of "what's today and what should I do":
//
//   hero      the comfort verdict word (ramp-coloured) + temperature + feels-like
//   sentence  one plain-language line
//   advice    a few chips — umbrella / sunscreen / jacket — only when they matter
//   timeline  one shared morning→night axis with rain / wind / UV as ramp bars,
//             each with its peak marked
//   footer    confidence in plain words, only loud when sources disagree
//
// Everything is a tap target into the Detailed (dial) view.

import SwiftUI

struct SimpleNowView: View {
    let consensus: ConsensusWeather
    let failedSources: [WeatherSource]
    let confidence: Double
    let placeName: String?
    var onOpenDetail: (() -> Void)? = nil

    private var comfort: ComfortData { ComfortData(consensus: consensus) }

    var body: some View {
        VStack(spacing: 22) {
            hero
            Text(SimpleSummary.sentence(for: comfort, consensus: consensus))
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Sky.text).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            adviceChips
            timeline
            confidenceFooter
            outlook
        }
        .padding(.top, 18).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(heroBackdrop, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail?() }
    }

    /// A soft time-of-day wash behind the hero — dawn amber, midday blue, dusk
    /// violet, night deep — so the Simple view feels alive without clutter. It
    /// fades to nothing before the content below, keeping text clean.
    private var heroBackdrop: some View {
        let hour = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let h = Double(hour.hour ?? 12) + Double(hour.minute ?? 0) / 60
        let top: Color
        switch h {
        case 5..<7.5:   top = Color(hex: "8B5A6B")   // dawn
        case 7.5..<16:  top = Color(hex: "3E7AB0")   // day
        case 16..<18.5: top = Color(hex: "B0587A")   // dusk
        default:        top = Color(hex: "1B2748")   // night
        }
        return LinearGradient(colors: [top.opacity(0.35), .clear],
                              startPoint: .top, endPoint: .bottom)
            .frame(height: 300)
            .allowsHitTesting(false)
    }

    // MARK: - Hero
    private var hero: some View {
        let score = Comfort.overallScore(comfort)
        return VStack(spacing: 2) {
            Text(Comfort.overallLabel(score).uppercased())
                .font(.system(size: 15, weight: .bold)).kerning(1.5)
                .foregroundColor(Comfort.overallColor(score))
            Text(Units.tempString(consensus.temperature))
                .font(.system(size: 78, weight: .thin, design: .rounded))
                .foregroundColor(Sky.white)
            Text("feels like \(Units.tempString(consensus.feelsLike)) · \(consensus.condition.rawValue.lowercased())")
                .font(.system(size: 13)).foregroundColor(Sky.muted)
        }
    }

    // MARK: - Advice chips
    private var adviceChips: some View {
        let chips = SimpleSummary.advice(for: comfort, consensus: consensus)
        return FlowChips(chips: chips)
    }

    // MARK: - Timeline
    private var timeline: some View {
        IntradayTimeline(hourly: consensus.hourlyForecast)
            .padding(.horizontal, 16)
    }

    // MARK: - Next-days outlook
    /// A quiet peek at the next few days so "what about the weekend?" is answered
    /// without leaving the screen — the hi is tinted by the comfort ramp, the lo
    /// stays muted, the emoji carries the sky. The whole view already taps into
    /// Detail; the Week tab holds the full run.
    private var outlook: some View {
        let cal = Calendar.current
        let days = Array(consensus.dailyForecast
            .filter { $0.date >= cal.startOfDay(for: Date()) && !cal.isDateInToday($0.date) }
            .prefix(4))
        return Group {
            if days.count >= 2 {
                VStack(spacing: 12) {
                    Rectangle().fill(Sky.muted.opacity(0.15)).frame(height: 1)
                        .padding(.horizontal, 24)
                    HStack(spacing: 0) {
                        ForEach(days) { d in
                            VStack(spacing: 5) {
                                Text(d.dayLabel)
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Sky.muted)
                                Text(d.condition.emoji).font(.system(size: 20))
                                HStack(spacing: 3) {
                                    Text(Units.tempString(d.tempMax))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Comfort.comfortColor(ComfortMetric.temp.score(d.tempMax)))
                                    Text(Units.tempString(d.tempMin))
                                        .font(.system(size: 12)).foregroundColor(Sky.muted)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Confidence footer
    private var confidenceFooter: some View {
        let flags = comfort.rings.filter(\.hasFlag)
        let agree = flags.isEmpty
        return HStack(spacing: 6) {
            Circle().fill(agree ? Comfort.good : Sky.amber).frame(width: 6, height: 6)
            if agree {
                Text("\(consensus.sources.count) sources agree")
                    .font(.system(size: 11)).foregroundColor(Sky.muted)
            } else {
                Text("sources disagree on \(flags.map { $0.metric.label.lowercased() }.joined(separator: ", "))")
                    .font(.system(size: 11)).foregroundColor(Sky.amber)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Advice + summary generation

enum SimpleSummary {
    struct Chip: Identifiable { let emoji: String; let text: String; let color: Color; var id: String { text } }

    /// A few actionable chips, only when they clear a threshold. If nothing
    /// needs doing, one reassuring chip rather than an empty row.
    static func advice(for comfort: ComfortData, consensus: ConsensusWeather) -> [Chip] {
        var out: [Chip] = []
        let hourly = consensus.hourlyForecast

        if let rain = IntradayPeak.of(.rain, hourly: hourly), rain.value >= 40 {
            out.append(Chip(emoji: "☂️", text: "Umbrella \(IntradayPeak.hourLabel(rain.time))", color: Sky.rain))
        }
        if let uv = IntradayPeak.of(.uv, hourly: hourly), uv.value >= 6 {
            out.append(Chip(emoji: "🧴", text: "Sunscreen \(IntradayPeak.hourLabel(uv.time))", color: Sky.amber))
        }
        if let wind = IntradayPeak.of(.wind, hourly: hourly), wind.value >= 30 {
            out.append(Chip(emoji: "💨", text: "Windy \(IntradayPeak.hourLabel(wind.time))", color: Sky.wind))
        }
        // Temperature advice from the current comfort.
        if consensus.temperature < 15 {
            out.append(Chip(emoji: "🧥", text: "Warm layer", color: Comfort.poor))
        } else if consensus.temperature > 33 {
            out.append(Chip(emoji: "🥵", text: "Beat the heat", color: Comfort.poor))
        }

        if out.isEmpty {
            out.append(Chip(emoji: "✓", text: "Nothing needed today", color: Comfort.good))
        }
        return out
    }

    /// [feel] — [top action]. [rain clause]. Kept short and human.
    static func sentence(for comfort: ComfortData, consensus: ConsensusWeather) -> String {
        let t = consensus.temperature
        let feel: String
        switch t {
        case ..<10:  feel = "Cold"
        case ..<16:  feel = "Cool"
        case ..<24:  feel = "Mild"
        case ..<31:  feel = "Warm"
        default:     feel = "Hot"
        }
        let windy = consensus.windSpeed >= 25 ? ", breezy" : ""

        var clauses: [String] = ["\(feel)\(windy) day"]

        // The single most notable action.
        if let rain = IntradayPeak.of(.rain, hourly: consensus.hourlyForecast), rain.value >= 40 {
            clauses.append("rain likely \(IntradayPeak.hourLabel(rain.time))")
        } else if consensus.rainProbability < 20 {
            clauses.append("staying dry")
        }
        if let uv = IntradayPeak.of(.uv, hourly: consensus.hourlyForecast), uv.value >= 8 {
            clauses.append("strong sun around \(IntradayPeak.hourLabel(uv.time))")
        }

        return clauses.joined(separator: " — ") + "."
    }
}

// MARK: - Chip flow layout

private struct FlowChips: View {
    let chips: [SimpleSummary.Chip]
    var body: some View {
        // Two-per-row is plenty for the handful we ever show; keeps it centred.
        let rows = stride(from: 0, to: chips.count, by: 2).map { Array(chips[$0..<min($0 + 2, chips.count)]) }
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { chip in
                        HStack(spacing: 6) {
                            Text(chip.emoji).font(.system(size: 15))
                            Text(chip.text).font(.system(size: 13, weight: .semibold)).foregroundColor(Sky.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(chip.color.opacity(0.16))
                        .overlay(Capsule().stroke(chip.color.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Intraday timeline

/// One shared morning→night axis. Temperature leads (it's the headline), then
/// rain / wind / UV. Each hour is a segment tinted by that metric's comfort, and
/// the peak hour is marked and labelled.
private struct IntradayTimeline: View {
    let hourly: [ConsensusHourly]

    private struct Row { let label: String; let metric: ComfortMetric; let icon: String; let values: [(Date, Double?)] }

    var body: some View {
        let window = Array(hourly.prefix(14))
        if window.count >= 3 {
            let rows = [
                Row(label: "Temp", metric: .temp, icon: "🌡", values: window.map { ($0.time, $0.temperature) }),
                Row(label: "Rain", metric: .rain, icon: "💧", values: window.map { ($0.time, $0.rainProbability) }),
                Row(label: "Wind", metric: .wind, icon: "💨", values: window.map { ($0.time, $0.windSpeed) }),
                Row(label: "UV",   metric: .uv,   icon: "☀️", values: window.map { ($0.time, $0.uvIndex) }),
            ]
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in bar(row, window: window) }
                axis(window)
            }
        } else {
            EmptyView()
        }
    }

    private func bar(_ row: Row, window: [ConsensusHourly]) -> some View {
        let peak = IntradayPeak.of(row.metric, hourly: hourly)
        // The right-hand callout: the peak's VALUE and time, or the current
        // reading when nothing peaks — so every row says something concrete.
        let callout: String
        if let peak {
            callout = "\(row.metric.format(peak.value)) \(IntradayPeak.hourLabel(peak.time))"
        } else if let first = row.values.first?.1 {
            callout = row.metric.format(first)
        } else {
            callout = "—"
        }
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(row.icon).font(.system(size: 12))
                Text(row.label).font(.system(size: 11, weight: .semibold)).foregroundColor(Sky.text)
            }
            .frame(width: 54, alignment: .leading)

            GeometryReader { geo in
                let w = geo.size.width / CGFloat(row.values.count)
                ZStack(alignment: .leading) {
                    HStack(spacing: 1.5) {
                        ForEach(Array(row.values.enumerated()), id: \.offset) { _, v in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(segmentColor(row.metric, v.1))
                                .frame(height: 18)
                        }
                    }
                    if let peak, let i = window.firstIndex(where: { $0.time == peak.time }) {
                        // A capped marker over the peak hour, so it reads clearly.
                        Capsule().fill(Sky.white)
                            .frame(width: 2.5, height: 24)
                            .offset(x: (CGFloat(i) + 0.5) * w - 1.25)
                    }
                }
            }
            .frame(height: 24)

            Text(callout)
                .font(.system(size: 10, weight: .medium)).foregroundColor(peak == nil ? Sky.muted : Sky.text)
                .frame(width: 58, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func segmentColor(_ metric: ComfortMetric, _ value: Double?) -> Color {
        guard let value else { return Sky.surface.opacity(0.4) }
        // A touch more saturated than before so the shape reads at a glance.
        return Comfort.comfortColor(metric.score(value)).opacity(0.95)
    }

    private func axis(_ window: [ConsensusHourly]) -> some View {
        HStack {
            Text(IntradayPeak.hourLabel(window.first!.time))
            Spacer()
            Text(IntradayPeak.hourLabel(window[window.count / 2].time))
            Spacer()
            Text(IntradayPeak.hourLabel(window.last!.time))
        }
        .font(.system(size: 9)).foregroundColor(Sky.muted)
        .padding(.leading, 62).padding(.trailing, 66)
    }
}
