// Sky Warden — Now tab
// Rating banner · comfort dial · confidence widget · pills · on-this-day · hourly.
// Nothing else lives here (moon/tides/etc. have their own tabs) per the handover.

import SwiftUI
import CoreLocation

struct HomeView: View {
    let consensus: ConsensusWeather
    let failedSources: [WeatherSource]
    let location: CLLocation
    let placeName: String?
    var tideDay: TideDay? = nil
    var moonData: MoonData? = nil
    /// Lets the summary grid jump straight to the tab it summarises.
    var onOpenTab: ((ContentView.Tab) -> Void)? = nil

    @State private var selectedMetric: ComfortMetric?
    @State private var onThisDay: OnThisDay?
    @AppStorage(DisplayKey.dialStyle) private var dialStyleRaw = DialStyle.radial.rawValue

    private var dialStyle: DialStyle { DialStyle(rawValue: dialStyleRaw) ?? .radial }

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

                Group {
                    switch dialStyle {
                    case .radial:
                        RadialDialView(data: comfort, temperature: consensus.temperature,
                                       confidence: confidence, selected: $selectedMetric)
                    case .arc:
                        ComfortDialView(data: comfort, selected: $selectedMetric)
                    }
                }
                .padding(.top, 8)

                // Sits with the rings it describes, not further down the page.
                confidenceWidget.padding(.horizontal, 16).padding(.top, 2)

                pills.padding(.horizontal, 16).padding(.top, 10)

                tabSummary.padding(.horizontal, 16).padding(.top, 12)

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
    //
    // A pill's fill IS its comfort: the more uncomfortable the metric, the more
    // the ramp's red floods the tile. Comfortable metrics stay quiet. The word
    // ("Oppressive", "Calm") carries the same meaning, so nothing is colour-alone.
    private var pills: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5), spacing: 5) {
            ForEach(comfort.rings) { r in
                // Same ramp as the dial: hue is comfort, never metric identity.
                let color = Comfort.comfortColor(r.score)
                let discomfort = max(0, -r.score)          // 0 = fine, 1 = miserable
                let isTapped = selectedMetric == r.metric
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMetric = isTapped ? nil : r.metric
                    }
                } label: {
                    VStack(spacing: 1) {
                        // Five across leaves ~62pt per tile, so the contents stack
                        // and the disagreement flag becomes a dot rather than a word.
                        ZStack(alignment: .topTrailing) {
                            Text(r.metric.emoji).font(.system(size: 15))
                            if r.hasFlag {
                                Circle().fill(r.isMajor ? Sky.red : Sky.amber)
                                    .frame(width: 5, height: 5).offset(x: 6, y: -1)
                            }
                        }
                        Text(r.metric.format(r.value))
                            .font(.system(size: 14, weight: .bold))
                            // On a heavily tinted fill the hue no longer contrasts.
                            .foregroundColor(discomfort > 0.45 ? Sky.white : color)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(r.metric.comfortLabel(r.value))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(discomfort > 0.45 ? Sky.white.opacity(0.85) : Sky.muted)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.vertical, 8).padding(.horizontal, 3)
                    .background(pillFill(color, discomfort: discomfort, tapped: isTapped))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(isTapped ? 0.7 : 0.18 + 0.42 * discomfort),
                                lineWidth: isTapped ? 1.8 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.metric.label), \(r.metric.format(r.value)), \(r.metric.comfortLabel(r.value))"
                                    + (r.hasFlag ? ", sources disagree" : ""))
            }
        }
    }

    private func pillFill(_ color: Color, discomfort: Double, tapped: Bool) -> some View {
        // Comfortable metrics barely tint; a bad one saturates its tile.
        let alpha = 0.07 + 0.34 * discomfort + (tapped ? 0.08 : 0)
        return ZStack {
            Sky.surface
            color.opacity(alpha)
        }
    }

    // MARK: - Confidence widget
    //
    // Replaces both the old full-width strip and the "OW, WK unavailable"
    // banner: a missing source is only interesting as a dent in confidence and
    // a source count, not as its own paragraph.
    private var confidenceWidget: some View {
        let color = confidence >= 0.8 ? Comfort.good : confidence >= 0.5 ? Sky.amber : Comfort.poor
        let used = consensus.sources.count
        let total = used + failedSources.count
        return HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Sky.card, lineWidth: 3).frame(width: 18, height: 18)
                Circle().trim(from: 0, to: confidence)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
            }
            Text("\(Int((confidence * 100).rounded()))% confidence")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(color)

            Text("·").foregroundColor(Sky.muted).font(.system(size: 11))
            Text("\(used)/\(total) sources")
                .font(.system(size: 11)).foregroundColor(Sky.muted)

            if flagCount > 0 {
                Text("·").foregroundColor(Sky.muted).font(.system(size: 11))
                Text("\(flagCount) vary").font(.system(size: 11)).foregroundColor(Sky.amber)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Sky.surface).clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tab summary
    //
    // The bridge from the visual layer to the detail tabs: one real line per tab,
    // tap to go there. Values are measured or an em dash — none invent a number
    // to look complete.
    //
    // A list, not a grid. Grid tiles force every value into the same small box,
    // so "High 1.8m" and "0" get equal weight and nothing lines up; the eye has
    // to re-anchor on each tile. Rows share one baseline and one right edge, so
    // the values form a single scannable column, and the secondary text has room
    // to say something useful instead of being truncated.
    private var tabSummary: some View {
        let today = consensus.dailyForecast.first
        let week = consensus.dailyForecast.prefix(7)
        let wetDays = week.filter { $0.rainProbability >= 50 }.count
        let nextTide = tideDay?.events.first { $0.time > Date() }

        let rows: [SummaryRow] = [
            .init(tab: .today, icon: "thermometer.medium",
                  value: today.map { "\(Units.tempString($0.tempMax)) / \(Units.tempString($0.tempMin))" },
                  title: "Today", detail: today?.condition.rawValue.lowercased()),
            .init(tab: .week, icon: "calendar",
                  value: week.isEmpty ? nil : (wetDays == 0 ? "All dry" : "\(wetDays) wet"),
                  title: "Next \(week.count) days", detail: week.isEmpty ? nil : "chance of rain over 50%"),
            .init(tab: .tides, icon: "water.waves",
                  value: nextTide.map(\.heightDisplay),
                  title: "Next tide",
                  detail: nextTide.map { "\($0.type.rawValue.lowercased()) at \($0.timeDisplay)" }),
            .init(tab: .uv, icon: "sun.max",
                  value: consensus.uvIndex.isFinite ? "\(Int(consensus.uvIndex.rounded()))" : nil,
                  title: "UV index", detail: ComfortMetric.uv.comfortLabel(consensus.uvIndex).lowercased()),
            .init(tab: .sky, icon: "moon.stars",
                  value: moonData.map { "\(Int(($0.illumination * 100).rounded()))%" },
                  title: "Moon", detail: moonData?.phase.rawValue.lowercased()),
            .init(tab: .sources, icon: "antenna.radiowaves.left.and.right",
                  value: "\(consensus.sources.count)/\(consensus.sources.count + failedSources.count)",
                  title: "Sources agreeing",
                  detail: flagCount == 0 ? "no disagreements" : "\(flagCount) metric\(flagCount == 1 ? "" : "s") vary"),
        ]

        return VStack(alignment: .leading, spacing: 6) {
            Text("AT A GLANCE")
                .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    Button { onOpenTab?(row.tab) } label: {
                        HStack(spacing: 11) {
                            // Monochrome symbols, not emoji: six coloured glyphs in
                            // a column is noise, and the tab bar already owns emoji.
                            Image(systemName: row.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Sky.muted)
                                .frame(width: 18)

                            Text(row.title)
                                .font(.system(size: 13)).foregroundColor(Sky.text)

                            Spacer(minLength: 8)

                            if let detail = row.detail {
                                Text(detail)
                                    .font(.system(size: 10)).foregroundColor(Sky.muted)
                                    .lineLimit(1).layoutPriority(-1)
                            }
                            Text(row.value ?? "—")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(row.value == nil ? Sky.muted : Sky.white)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold)).foregroundColor(Sky.muted.opacity(0.6))
                        }
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenTab == nil)
                    .accessibilityLabel("\(row.title), \(row.value ?? "unavailable"). Opens \(row.tab.label).")

                    if i < rows.count - 1 {
                        Rectangle().fill(Sky.surface).frame(height: 1).padding(.leading, 41)
                    }
                }
            }
            .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private struct SummaryRow: Identifiable {
        let tab: ContentView.Tab
        let icon: String
        let value: String?
        let title: String
        let detail: String?
        var id: String { tab.rawValue }
    }

    // MARK: - On this day
    private var onThisDayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📅 ON THIS DAY")
                .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
            HStack(spacing: 0) {
                column(value: Units.tempString(consensus.temperature), diff: nil,
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
        // Delta computed from the rounded, displayed values so it agrees with them.
        let diff = value.map { Units.displayTempDelta(consensus.temperature, $0) }
        return column(
            value: value.map { Units.tempString($0) } ?? "—",
            diff: diff,
            label: label, big: false, first: false
        )
    }

    private func column(value: String, diff: Int?, label: String, big: Bool, first: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: big ? 20 : 15, weight: big ? .ultraLight : .light, design: .rounded))
                .foregroundColor(big ? Sky.white : Sky.text)
            if let diff, diff != 0 {
                Text("\(diff > 0 ? "+" : "")\(diff)°")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(diff > 0 ? Sky.red : Sky.rain)
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
                            Text(Units.tempString(h.temperature))
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
