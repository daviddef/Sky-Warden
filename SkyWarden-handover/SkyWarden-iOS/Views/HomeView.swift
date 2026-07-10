// Sky Warden — Now tab
// Rating banner · comfort dial · sources widget · pills · at-a-glance · hourly.
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
    @State private var warnings: [WeatherWarning] = []
    @AppStorage(DisplayKey.dialStyle) private var dialStyleRaw = DialStyle.arc.rawValue

    private var dialStyle: DialStyle { DialStyle(rawValue: dialStyleRaw) ?? .arc }

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
                if !warnings.isEmpty {
                    WarningsBanner(warnings: warnings)
                        .padding(.horizontal, 16).padding(.top, 12)
                }

                ratingBanner
                    .padding(.horizontal, 20).padding(.top, 14)

                Group {
                    switch dialStyle {
                    case .radial:
                        RadialDialView(data: comfort, temperature: consensus.temperature,
                                       confidence: confidence, selected: $selectedMetric)
                    case .arc:
                        ComfortDialView(data: comfort, temperature: consensus.temperature,
                                        confidence: confidence, selected: $selectedMetric)
                    }
                }
                .padding(.top, 8)

                // The source count and disagreements already live in the "Sources
                // agreeing" row of at-a-glance, so no separate strip here.

                pills.padding(.horizontal, 16).padding(.top, 10)

                tabSummary.padding(.horizontal, 16).padding(.top, 12)

                hourly.padding(.top, 12)

                Spacer(minLength: 20)
            }
        }
        .task(id: location.coordinate.latitude) {
            onThisDay = try? await HistoricalService().onThisDay(location: location)
        }
        .task(id: location.coordinate.latitude) {
            warnings = await WarningsService().warnings(near: location)
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
        let nextTide = tideDay?.events.first { $0.time > Date() }
        let days = Array(consensus.dailyForecast.prefix(5))

        return VStack(alignment: .leading, spacing: 6) {
            Text("AT A GLANCE")
                .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)

            VStack(spacing: 0) {
                standardRow(.today, "thermometer.medium", "Today",
                            value: today.map { "\(Units.tempString($0.tempMax)) / \(Units.tempString($0.tempMin))" },
                            detail: today?.condition.rawValue.lowercased())
                divider
                weekRow(days)                       // the five-day icon strip
                divider
                standardRow(.tides, "water.waves", "Next tide",
                            value: nextTide.map(\.heightDisplay),
                            detail: nextTide.map { "\($0.type.rawValue.lowercased()) at \($0.timeDisplay)" })
                divider
                standardRow(.uv, "sun.max", "UV index",
                            value: consensus.uvIndex.isFinite ? "\(Int(consensus.uvIndex.rounded()))" : nil,
                            detail: ComfortMetric.uv.comfortLabel(consensus.uvIndex).lowercased())
                divider
                standardRow(.sky, "moon.stars", "Moon",
                            value: moonData.map { "\(Int(($0.illumination * 100).rounded()))%" },
                            detail: moonData?.phase.rawValue.lowercased())
                divider
                standardRow(.sources, "antenna.radiowaves.left.and.right", "Sources agreeing",
                            value: "\(consensus.sources.count)/\(consensus.sources.count + failedSources.count)",
                            detail: flagCount == 0 ? "no disagreements" : "\(flagCount) metric\(flagCount == 1 ? "" : "s") vary")
                divider
                onThisDayRow                        // compact history, no tab
            }
            .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var divider: some View {
        Rectangle().fill(Sky.surface).frame(height: 1).padding(.leading, 41)
    }

    // A tappable row that opens a detail tab.
    private func standardRow(_ tab: ContentView.Tab, _ icon: String, _ title: String,
                             value: String?, detail: String?) -> some View {
        Button { onOpenTab?(tab) } label: {
            HStack(spacing: 11) {
                // Monochrome symbols, not emoji: a column of coloured glyphs is
                // noise, and the tab bar already owns emoji.
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                    .foregroundColor(Sky.muted).frame(width: 18)
                Text(title).font(.system(size: 13)).foregroundColor(Sky.text)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundColor(Sky.muted)
                        .lineLimit(1).layoutPriority(-1)
                }
                Text(value ?? "—").font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(value == nil ? Sky.muted : Sky.white).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Sky.muted.opacity(0.6))
            }
            .padding(.vertical, 10).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(onOpenTab == nil)
        .accessibilityLabel("\(title), \(value ?? "unavailable"). Opens \(tab.label).")
    }

    /// The week at a glance: the next five days as icon cells, each with its day,
    /// weather glyph and high/low, opening the Week tab.
    private func weekRow(_ days: [ConsensusDaily]) -> some View {
        Button { onOpenTab?(.week) } label: {
            HStack(spacing: 11) {
                Image(systemName: "calendar").font(.system(size: 13, weight: .medium))
                    .foregroundColor(Sky.muted).frame(width: 18)
                if days.isEmpty {
                    Text("Next days").font(.system(size: 13)).foregroundColor(Sky.text)
                    Spacer(); Text("—").foregroundColor(Sky.muted)
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                            VStack(spacing: 2) {
                                Text(i == 0 ? "Today" : String(day.dayLabel.prefix(3)))
                                    .font(.system(size: 8.5)).foregroundColor(Sky.muted).lineLimit(1)
                                Text(day.condition.emoji).font(.system(size: 17))
                                Text("\(Int(day.tempMax.rounded()))°")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(Sky.white)
                                Text("\(Int(day.tempMin.rounded()))°")
                                    .font(.system(size: 9)).foregroundColor(Sky.muted)
                            }
                            .frame(maxWidth: .infinity)
                            // A calendar dot when the sources disagree on this day.
                            .overlay(alignment: .top) {
                                if day.hasDisagreement {
                                    Circle().fill(Sky.amber).frame(width: 4, height: 4).offset(y: -1)
                                }
                            }
                        }
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Sky.muted.opacity(0.6))
            }
            .padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(onOpenTab == nil)
        .accessibilityLabel("Next \(days.count) days. Opens the Week tab.")
    }

    /// On this day, shrunk from its own card to one compact row: how today's
    /// temperature compares with a year ago, five years ago and the 30-year normal.
    private var onThisDayRow: some View {
        func cell(_ v: Double?, _ label: String) -> some View {
            let diff = v.map { Units.displayTempDelta(consensus.temperature, $0) }
            return VStack(spacing: 1) {
                Text(v.map { Units.tempString($0) } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Sky.text)
                if let diff, diff != 0 {
                    Text("\(diff > 0 ? "+" : "")\(diff)°")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(diff > 0 ? Sky.red : Sky.rain)
                } else {
                    Text(v == nil ? " " : "0°").font(.system(size: 8)).foregroundColor(Sky.muted)
                }
                Text(label).font(.system(size: 7.5)).foregroundColor(Sky.muted)
            }
        }
        return HStack(spacing: 11) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .medium))
                .foregroundColor(Sky.muted).frame(width: 18)
            Text("On this day").font(.system(size: 13)).foregroundColor(Sky.text)
            Spacer(minLength: 8)
            cell(onThisDay?.oneYear, "1yr")
            cell(onThisDay?.fiveYear, "5yr")
            cell(onThisDay?.average, "30yr")
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .accessibilityLabel("On this day: a year ago, five years ago, and the 30 year average.")
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
