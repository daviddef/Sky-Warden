// SkyWarden — Week + Sources tabs

import SwiftUI

// MARK: - Week View
struct WeekView: View {
    let daily: [ConsensusDaily]
    let disagreementCount: Int

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if disagreementCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundColor(Sky.amber)
                        Text("\(disagreementCount) day\(disagreementCount == 1 ? "" : "s") have source disagreements — check ⚠️ rows")
                            .font(SkyType.micro).foregroundColor(Sky.amber)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sky.amberBg).clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }

                VStack(spacing: 0) {
                    ForEach(Array(daily.enumerated()), id: \.element.id) { (i, day) in
                        DailyRow(day: day, isFirst: i == 0)
                        if i < daily.count - 1 {
                            Divider().background(Sky.surface).padding(.horizontal, 16)
                        }
                    }
                }
                .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)

                Text("⚠️ CHECK = weather sources disagree on this day")
                    .font(SkyType.micro).foregroundColor(Sky.muted)
                    .padding(.top, 10).padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
    }
}

private struct DailyRow: View {
    let day: ConsensusDaily
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(day.dayLabel)
                .font(SkyType.body).fontWeight(isFirst ? .semibold : .regular)
                .foregroundColor(isFirst ? Sky.white : Sky.text)
                .frame(width: 44, alignment: .leading)
            Image(systemName: day.condition.icon)
                .font(.system(size: 22)).foregroundColor(Sky.text).frame(width: 28)
            if day.hasDisagreement {
                Text("⚠️ CHECK").font(.system(size: 9, weight: .bold)).foregroundColor(Sky.amber)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Sky.amberBg).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "drop.fill").font(.system(size: 9))
                    .foregroundColor(day.rainProbability > 40 ? Sky.rain : Sky.muted)
                Text("\(Int(day.rainProbability.rounded()))%").font(SkyType.caption)
                    .foregroundColor(day.rainProbability > 40 ? Sky.rain : Sky.muted)
            }
            .frame(width: 44)
            HStack(spacing: 4) {
                Text(Units.tempString(day.tempMax)).font(SkyType.body).fontWeight(.medium).foregroundColor(Sky.white)
                Text(Units.tempString(day.tempMin)).font(SkyType.body).foregroundColor(Sky.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(isFirst ? Sky.rain.opacity(0.06) : Color.clear)
    }
}

// MARK: - Sources View (transparency: per-ring comfort bars + source breakdown)
struct SourcesView: View {
    let consensus: ConsensusWeather
    @State private var expanded: ComfortMetric?

    private var comfort: ComfortData { ComfortData(consensus: consensus) }
    private var confidence: Double {
        let w: [ComfortMetric: Double] = [.temp: 0.3, .rain: 0.3, .wind: 0.2, .uv: 0.1, .humidity: 0.1]
        let penalty = comfort.rings.reduce(0.0) { acc, r in
            acc + (r.isMajor ? (w[r.metric] ?? 0.1) * 0.9 : r.isMinor ? (w[r.metric] ?? 0.1) * 0.4 : 0)
        }
        return max(0, 1 - penalty)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                confidenceCard
                ForEach(comfort.rings) { ringRow($0) }
                PeoplesWeather()
            }
            .padding(16)
        }
    }

    private var confidenceCard: some View {
        let color = confidence >= 0.8 ? Sky.green : confidence >= 0.5 ? Sky.amber : Sky.red
        return VStack(spacing: 8) {
            HStack {
                Text("📡 SOURCE CONFIDENCE").font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(WeatherSource.allCases) { s in
                        HStack(spacing: 3) {
                            Circle().fill(Color(hex: s.colorHex)).frame(width: 5, height: 5)
                            Text(s.short).font(.system(size: 8)).foregroundColor(Sky.muted)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Sky.surface).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Sky.surface).frame(height: 6)
                        Capsule().fill(color).frame(width: geo.size.width * confidence, height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(Int((confidence * 100).rounded()))%").font(.system(size: 13, weight: .bold)).foregroundColor(color)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func ringRow(_ r: RingReading) -> some View {
        let color = Comfort.needleColor(r.metric, r.score)
        let isOpen = expanded == r.metric
        return VStack(spacing: 0) {
            Button { withAnimation(.spring(response: 0.3)) { expanded = isOpen ? nil : r.metric } } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text(r.metric.emoji).font(.system(size: 18))
                        Text(r.metric.label).font(.system(size: 13)).foregroundColor(Sky.text)
                        Spacer()
                        if r.hasFlag {
                            Text("\(r.isMajor ? "🚨" : "⚠️") \(r.metric.formatDelta(r.spread))")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(r.isMajor ? Sky.red : Sky.amber)
                        }
                        Text(r.metric.format(r.value)).font(.system(size: 14, weight: .bold)).foregroundColor(color)
                    }
                    HStack(spacing: 5) {
                        Text("good ◀").font(.system(size: 7)).foregroundColor(Sky.green.opacity(0.7))
                        ComfortMiniBar(score: r.score, color: color)
                        Text("▶ not").font(.system(size: 7)).foregroundColor(Sky.red.opacity(0.7))
                        Text(r.metric.comfortLabel(r.value)).font(.system(size: 10, weight: .semibold)).foregroundColor(color)
                    }
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 6) {
                    Divider().background(Sky.surface).padding(.top, 10)
                    ForEach(r.perSource, id: \.source) { s in
                        let sc = r.metric.score(s.value)
                        let nc = Comfort.needleColor(r.metric, sc)
                        let diff = s.value - r.value
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: s.source.colorHex)).frame(width: 7, height: 7)
                                Text(s.source.short).font(.system(size: 10)).foregroundColor(Sky.muted)
                            }
                            .frame(width: 44, alignment: .leading)
                            ComfortMiniBar(score: sc, color: nc)
                            Spacer(minLength: 0)
                            Text(r.metric.format(s.value)).font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Sky.white).frame(width: 34, alignment: .trailing)
                            if abs(diff) >= 0.5 {
                                Text("\(diff > 0 ? "+" : "")\(r.metric.formatDelta(diff))")
                                    .font(.system(size: 10))
                                    .foregroundColor(abs(diff) >= r.metric.disagreementThreshold ? Sky.amber : Sky.muted)
                                    .frame(width: 26, alignment: .trailing)
                            } else {
                                Spacer().frame(width: 26)
                            }
                        }
                    }
                    HStack {
                        Text("Consensus (trimmed mean)").font(.system(size: 10)).foregroundColor(Sky.muted)
                        Spacer()
                        Text(r.metric.format(r.value)).font(.system(size: 12, weight: .bold)).foregroundColor(Sky.white)
                    }
                    .padding(.top, 4)
                    .overlay(alignment: .top) { Divider().background(Sky.surface) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(isOpen ? Sky.surface : Sky.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOpen ? color.opacity(0.4) : .clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Comfort mini bar (good ◀ … ▶ not)
struct ComfortMiniBar: View {
    let score: Double
    let color: Color
    private let half: CGFloat = 44

    var body: some View {
        let fill = max(2, CGFloat(abs(score)) * half)
        ZStack(alignment: .leading) {
            Capsule().fill(Sky.navy).frame(width: half * 2, height: 4)
            Rectangle().fill(Sky.white.opacity(0.3)).frame(width: 1, height: 4).offset(x: half)
            RoundedRectangle(cornerRadius: 2).fill(color)
                .frame(width: fill, height: 4)
                .offset(x: score >= 0 ? half - fill : half)
        }
        .frame(width: half * 2, height: 4)
    }
}

// MARK: - People's Weather (local vote; community totals need the backend)
struct PeoplesWeather: View {
    @State private var vote: String?
    private let options: [(key: String, emoji: String)] = [
        ("great", "😎"), ("good", "🙂"), ("ok", "😐"), ("bad", "😬"), ("awful", "🥵")
    ]
    private var todayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "crowdVote-\(f.string(from: Date()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("👥 PEOPLE'S WEATHER").font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
            Text("How does it actually feel outside right now?")
                .font(.system(size: 12)).foregroundColor(Sky.text)
            HStack(spacing: 8) {
                ForEach(options, id: \.key) { opt in
                    Button { setVote(opt.key) } label: {
                        Text(opt.emoji).font(.system(size: 26))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(vote == opt.key ? Sky.tide.opacity(0.2) : Sky.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(vote == opt.key ? Sky.tide : .clear, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .opacity(vote == nil || vote == opt.key ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(vote == nil ? "Anonymous · one vote per day" : "Thanks! Community totals arrive with the People's Weather backend.")
                .font(.system(size: 9)).foregroundColor(Sky.muted)
        }
        .padding(14).background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { vote = UserDefaults.standard.string(forKey: todayKey) }
    }

    private func setVote(_ key: String) {
        vote = key
        UserDefaults.standard.set(key, forKey: todayKey)
    }
}
