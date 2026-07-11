// Sky Warden — Simple Now view
//
// The answer to "users find it complicated". Same data as the dial, reframed as
// the fastest possible read of "what's today and what should I do":
//
//   hero      the comfort verdict word (ramp-coloured) + temperature + feels-like
//   sentence  one plain-language line
//   advice    a few chips — umbrella / sunscreen / jacket — only when they matter
//   ranges    temp / rain / wind / UV each as a min→max track with the current
//             reading riding it in a comfort-ringed bubble (the dial's ring markers)
//   footer    confidence in plain words, only loud when sources disagree
//   outlook   a quiet next-days peek
//
// Everything is a tap target into the Detailed (dial) view.

import SwiftUI

struct SimpleNowView: View {
    let consensus: ConsensusWeather
    let failedSources: [WeatherSource]
    let confidence: Double
    let placeName: String?
    var vsLastYear: Double? = nil
    var userReport: UserReport? = nil
    var onOpenDetail: (() -> Void)? = nil
    var onTapTemperature: (() -> Void)? = nil

    private var comfort: ComfortData { ComfortData(consensus: consensus) }

    var body: some View {
        VStack(spacing: 16) {
            hero
            Text(SimpleSummary.sentence(for: comfort, consensus: consensus))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Sky.text).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            adviceChips
            uvAdvice
            timeline
            confidenceFooter
            outlook
        }
        .padding(.top, 14).padding(.bottom, 8)
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
    // Denser than before: the verdict is a small eyebrow, the temperature leads at
    // a trimmed size, and feels-like / condition / "vs last year" share one quiet
    // line beneath — so the block says more in less height. Tap the number for the
    // hour-by-hour overlay.
    private var hero: some View {
        let score = Comfort.overallScore(comfort)
        return VStack(spacing: 3) {
            Text(Comfort.overallLabel(score).uppercased())
                .font(.system(size: 14, weight: .bold)).kerning(1.5)
                .foregroundColor(Comfort.overallColor(score))
            Text(Units.tempString(consensus.temperature))
                .font(.system(size: 62, weight: .thin, design: .rounded))
                .foregroundColor(Sky.white)
                .contentShape(Rectangle())
                .onTapGesture { onTapTemperature?() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens today's hourly detail")
            Text("feels \(Units.tempString(consensus.feelsLike)) · \(consensus.condition.rawValue.lowercased())")
                .font(.system(size: 13)).foregroundColor(Sky.muted)
            vsLastYearLine
        }
    }

    /// "2° warmer than last year" — today's high vs last year's on this day.
    @ViewBuilder private var vsLastYearLine: some View {
        if let d = vsLastYear, abs(d) >= 1 {
            let warmer = d > 0
            let delta = Int(abs(Units.tempDelta(d)).rounded())
            HStack(spacing: 4) {
                Image(systemName: warmer ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(delta)° \(warmer ? "warmer" : "cooler") than last year")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(warmer ? Sky.amber : Sky.tide)
            .padding(.top, 1)
        }
    }

    // MARK: - Advice chips
    private var adviceChips: some View {
        let chips = SimpleSummary.advice(for: comfort, consensus: consensus)
        return FlowChips(chips: chips)
    }

    // MARK: - UV advice (Slip · Slop · Slap · Seek · Slide)
    // Surfaced on the summary only when today's UV actually gets high, with the
    // protection window worked out from the hourly UV ≥ 3.
    @ViewBuilder private var uvAdvice: some View {
        if let peak = IntradayPeak.of(.uv, hourly: consensus.hourlyForecast), peak.value >= 6 {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("☀️").font(.system(size: 12))
                    Text(uvWindow().map { "Sun protection \($0)" }
                         ?? "Sun protection — UV peaks \(Int(peak.value.rounded()))")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Sky.amber)
                }
                HStack(spacing: 0) {
                    ForEach([("👕", "Slip"), ("🧴", "Slop"), ("🧢", "Slap"),
                             ("🌳", "Seek"), ("🕶", "Slide")], id: \.1) { icon, word in
                        VStack(spacing: 3) {
                            Text(icon).font(.system(size: 18))
                            Text(word).font(.system(size: 10, weight: .semibold)).foregroundColor(Sky.text)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 8)
                .background(Sky.amber.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Sky.amber.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16)
        }
    }

    /// The window of the day where UV ≥ 3, e.g. "10am–2pm".
    private func uvWindow() -> String? {
        let hot = consensus.hourlyForecast.filter { ($0.uvIndex ?? 0) >= 3 }
        guard let first = hot.first, let last = hot.last, first.time != last.time else { return nil }
        return "\(IntradayPeak.hourLabel(first.time))–\(IntradayPeak.hourLabel(last.time))"
    }

    // MARK: - Timeline
    @AppStorage(DisplayKey.simpleStyle) private var simpleStyle = SimpleStyle.bars.rawValue

    private var timeline: some View {
        // A fresh user correction wins over the consensus for the reading it
        // touches — "it says raining, it's dry" should show dry. The range/gauge
        // still spans the day's forecast; only the current-reading bubble moves.
        var current: [ComfortMetric: Double] = [
            .temp: consensus.temperature,
            .rain: consensus.rainProbability,
            .wind: consensus.windSpeed,
            .uv:   consensus.uvIndex,
        ]
        if let r = userReport {
            if let v = r.rainPercent { current[.rain] = v }
            if let v = r.temperature { current[.temp] = v }
            if let v = r.windSpeed  { current[.wind] = v }
        }
        return Group {
            if SimpleStyle(rawValue: simpleStyle) == .gauges {
                IntradayGauges(hourly: consensus.hourlyForecast, current: current)
            } else {
                IntradayRanges(hourly: consensus.hourlyForecast, current: current,
                               feelsLike: consensus.feelsLike)
            }
        }
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
    // The moat's wedge: when the sources agree, say so plainly and confidently;
    // when they don't, name the split and its range and frame it as a decision
    // ("worth a backup plan") rather than hiding the uncertainty behind one number.
    private var confidenceFooter: some View {
        let flags = comfort.rings.filter(\.hasFlag)
        let agree = flags.isEmpty
        return HStack(spacing: 6) {
            Circle().fill(agree ? Comfort.good : Sky.amber).frame(width: 6, height: 6)
            if agree {
                Text("\(consensus.sources.count) sources agree · confident")
                    .font(.system(size: 11)).foregroundColor(Sky.muted)
            } else {
                Text(disagreementSentence(flags))
                    .font(.system(size: 11.5, weight: .medium)).foregroundColor(Sky.amber)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24).padding(.top, 2)
    }

    private func disagreementSentence(_ flags: [RingReading]) -> String {
        guard let worst = flags.max(by: { $0.spread < $1.spread }) else { return "" }
        let label = worst.metric.label.lowercased()
        if let (lo, hi) = worst.minMax, worst.metric.format(lo) != worst.metric.format(hi) {
            return "Sources split on \(label): \(worst.metric.format(lo))–\(worst.metric.format(hi)) — worth a backup plan"
        }
        return "Sources disagree on \(label) — worth a backup plan"
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
    var feelsLike: Double? = nil

    private struct Row {
        let metric: ComfortMetric
        let values: [Double]
        let current: Double
        var feels: Double? = nil
    }

    var body: some View {
        let window = Array(hourly.prefix(24))
        let rows: [Row] = window.count >= 3 ? [
            Row(metric: .temp, values: window.map(\.temperature),    current: current[.temp] ?? 0, feels: feelsLike),
            Row(metric: .rain, values: window.map(\.rainProbability), current: current[.rain] ?? 0),
            Row(metric: .wind, values: window.map(\.windSpeed),      current: current[.wind] ?? 0),
            Row(metric: .uv,   values: window.compactMap(\.uvIndex), current: current[.uv] ?? 0),
        ].filter { !$0.values.isEmpty } : []

        return Group {
            if rows.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in rangeRow(row) }
                }
            }
        }
    }

    private func rangeRow(_ row: Row) -> some View {
        let lo = row.values.min() ?? row.current
        let hi = row.values.max() ?? row.current
        let span = hi - lo
        // Position on the track, 0 = low end … 1 = high end. A flat day (no real
        // span) rests the bubble mid-track rather than pinning it to an end.
        let frac: (Double) -> CGFloat = { v in
            span > 0.5 ? CGFloat(min(max((v - lo) / span, 0), 1)) : 0.5
        }
        let t = frac(row.current)
        let feelsT = row.feels.map(frac)

        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(row.metric.emoji).font(.system(size: 15))
                Text(row.metric.label).font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Sky.text).lineLimit(1).fixedSize()
            }
            .frame(width: 68, alignment: .leading)

            Text(row.metric.format(lo))
                .font(.system(size: 15)).foregroundColor(Sky.muted)
                .frame(width: 36, alignment: .trailing)

            GeometryReader { geo in
                let w = geo.size.width
                let bubbleW: CGFloat = 66
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Comfort.comfortColor(row.metric.score(lo)),
                                     Comfort.comfortColor(row.metric.score(hi))],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 16)
                    // Feels-like, shown only when it visibly parts from the reading —
                    // a ghost marker so temperature carries both truths at once.
                    if let ft = feelsT, abs(ft - t) > 0.06 {
                        Circle().strokeBorder(Sky.white.opacity(0.75), lineWidth: 2)
                            .frame(width: 13, height: 13)
                            .offset(x: ft * w - 6.5)
                    }
                    bubble(row)
                        .offset(x: min(max(t * w - bubbleW / 2, 0), max(w - bubbleW, 0)))
                }
            }
            .frame(height: 38)

            Text(row.metric.format(hi))
                .font(.system(size: 15)).foregroundColor(Sky.muted)
                .frame(width: 36, alignment: .leading)
        }
    }

    /// The current reading, styled like a Detailed dial ring marker: icon + value
    /// in a dark capsule ringed and lit in the metric's comfort colour.
    private func bubble(_ row: Row) -> some View {
        let c = Comfort.comfortColor(row.metric.score(row.current))
        return HStack(spacing: 4) {
            Text(row.metric.emoji).font(.system(size: 13))
            Text(row.metric.format(row.current))
                .font(.system(size: 19, weight: .bold)).foregroundColor(Sky.white)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(Sky.navy))
        .overlay(Capsule().stroke(c, lineWidth: 2))
        .shadow(color: c.opacity(0.45), radius: 7, y: 2)
        .fixedSize()
    }
}

// MARK: - Intraday gauges

/// The same four readings as a 2×2 of 270° gauges (the "Radial" Simple style). Each
/// arc sweeps from the day's low toward its high, filled to where the current
/// reading sits and lit in its comfort colour; the reading sits big in the centre,
/// the low and high tuck under the opening.
private struct IntradayGauges: View {
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in gauge(row) }
                }
            }
        }
    }

    private func gauge(_ row: Row) -> some View {
        let lo = row.values.min() ?? row.current
        let hi = row.values.max() ?? row.current
        let span = hi - lo
        let t = span > 0.5 ? min(max((row.current - lo) / span, 0), 1) : 0.5
        let c = Comfort.comfortColor(row.metric.score(row.current))

        return VStack(spacing: 0) {
            ZStack {
                // 270° track, gap at the bottom.
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Sky.surface, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * t)
                    .stroke(c, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: c.opacity(0.5), radius: 5)
                VStack(spacing: 1) {
                    Text(row.metric.emoji).font(.system(size: 13))
                    Text(row.metric.format(row.current))
                        .font(.system(size: 25, weight: .bold)).foregroundColor(Sky.white)
                    Text(row.metric.label)
                        .font(.system(size: 10, weight: .medium)).foregroundColor(Sky.muted)
                }
            }
            .frame(height: 116)
            .overlay(alignment: .bottom) {
                HStack {
                    Text(row.metric.format(lo)).foregroundColor(Sky.muted)
                    Spacer()
                    Text(row.metric.format(hi)).foregroundColor(Sky.muted)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 26)
            }
        }
    }
}
