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
        IntradayRanges(hourly: consensus.hourlyForecast, current: [
            .temp: consensus.temperature,
            .rain: consensus.rainProbability,
            .wind: consensus.windSpeed,
            .uv:   consensus.uvIndex,
        ])
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

// MARK: - Intraday ranges

/// Each metric as a min→max track with the current reading riding it in a bubble,
/// echoing the Detailed dial's ring markers. Answers "where does right now sit in
/// today's span?" at a glance: the track runs low→high, tinted by the comfort ramp
/// across that span, the ends carry the low and high, and the comfort-outlined
/// bubble sits where the current value falls between them.
private struct IntradayRanges: View {
    let hourly: [ConsensusHourly]
    let current: [ComfortMetric: Double]

    private struct Row { let metric: ComfortMetric; let values: [Double]; let current: Double }

    var body: some View {
        let window = Array(hourly.prefix(24))
        let rows: [Row] = window.count >= 3 ? [
            Row(metric: .temp, values: window.map(\.temperature),    current: current[.temp] ?? 0),
            Row(metric: .rain, values: window.map(\.rainProbability), current: current[.rain] ?? 0),
            Row(metric: .wind, values: window.map(\.windSpeed),      current: current[.wind] ?? 0),
            Row(metric: .uv,   values: window.compactMap(\.uvIndex), current: current[.uv] ?? 0),
        ].filter { !$0.values.isEmpty } : []

        return Group {
            if rows.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 15) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in rangeRow(row) }
                }
            }
        }
    }

    private func rangeRow(_ row: Row) -> some View {
        let lo = row.values.min() ?? row.current
        let hi = row.values.max() ?? row.current
        let span = hi - lo
        // Where the current reading sits, 0 = low end … 1 = high end. When the day
        // is flat (no real span) the bubble rests in the middle rather than pinning
        // to an arbitrary end.
        let t: CGFloat = span > 0.5 ? CGFloat(min(max((row.current - lo) / span, 0), 1)) : 0.5

        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(row.metric.emoji).font(.system(size: 12))
                Text(row.metric.label).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Sky.text).lineLimit(1).fixedSize()
            }
            .frame(width: 58, alignment: .leading)

            Text(row.metric.format(lo))
                .font(.system(size: 11)).foregroundColor(Sky.muted)
                .frame(width: 34, alignment: .trailing)

            GeometryReader { geo in
                let w = geo.size.width
                let bubbleW: CGFloat = 58
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Comfort.comfortColor(row.metric.score(lo)),
                                     Comfort.comfortColor(row.metric.score(hi))],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 5).opacity(0.9)
                        .frame(maxHeight: .infinity, alignment: .center)
                    bubble(row)
                        .offset(x: min(max(t * w - bubbleW / 2, 0), max(w - bubbleW, 0)))
                }
            }
            .frame(height: 30)

            Text(row.metric.format(hi))
                .font(.system(size: 11)).foregroundColor(Sky.muted)
                .frame(width: 34, alignment: .leading)
        }
    }

    /// The current reading, styled like a Detailed dial ring marker: icon + value
    /// in a dark capsule ringed in the metric's comfort colour.
    private func bubble(_ row: Row) -> some View {
        HStack(spacing: 3) {
            Text(row.metric.emoji).font(.system(size: 10))
            Text(row.metric.format(row.current))
                .font(.system(size: 11, weight: .bold)).foregroundColor(Sky.white)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Sky.navy))
        .overlay(Capsule().stroke(Comfort.comfortColor(row.metric.score(row.current)), lineWidth: 1.5))
        .fixedSize()
    }
}
