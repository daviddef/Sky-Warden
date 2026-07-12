// Sky Warden — Now tab
// Rating banner · comfort dial · sources widget · pills · at-a-glance · hourly.
// Nothing else lives here (moon/tides/etc. have their own tabs) per the handover.

import SwiftUI
import CoreLocation
import EventKit
import UserNotifications

struct HomeView: View {
    let consensus: ConsensusWeather
    let failedSources: [WeatherSource]
    let location: CLLocation
    let placeName: String?
    var tideDay: TideDay? = nil
    var moonData: MoonData? = nil
    var region: String? = nil
    var countryCode: String? = nil
    /// Lets the summary grid jump straight to the tab it summarises.
    var onOpenTab: ((ContentView.Tab) -> Void)? = nil
    var refresh: (() async -> Void)? = nil

    @State private var selectedMetric: ComfortMetric?
    @State private var onThisDay: OnThisDay?
    @State private var warnings: [WeatherWarning] = []
    @State private var showTodayOverlay = false
    @State private var showWeekSheet = false
    @State private var showFeedback = false
    @State private var userReport: UserReport?
    @State private var nowcast: PrecipNowcast?
    @State private var airQuality: AirQuality?
    @StateObject private var signals = HomeSignals()
    @AppStorage("display.nowSimple") private var simpleMode = true
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

    /// Today's forecast high vs last year's high on this calendar day, in °C — the
    /// "2° warmer than last year" line. Nil until the history loads.
    private var vsLastYear: Double? {
        guard let ly = onThisDay?.oneYear, let hi = consensus.dailyForecast.first?.tempMax else { return nil }
        return hi - ly
    }

    /// The always-there way in to correcting the forecast — "it says raining, it's
    /// dry". Compact so it shares the signals row; turns into a tick once you've
    /// reported. Its full accessibility label keeps the prompt for VoiceOver.
    @ViewBuilder private var reportChip: some View {
        let reported = userReport != nil
        Button { showFeedback = true } label: {
            HStack(spacing: 5) {
                Image(systemName: reported ? "checkmark.seal.fill" : "hand.raised").font(.system(size: 12))
                Text(reported ? "Reported" : "Report").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(reported ? Sky.tide : Sky.muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Sky.card.opacity(reported ? 1 : 0.55))
            .overlay(Capsule().stroke((reported ? Sky.tide : Sky.muted).opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain).fixedSize()
        .accessibilityLabel(reported ? "You reported \(reportSummary(userReport!)). Edit."
                                      : "Report the actual conditions")
    }

    /// The Dark Sky signature: a prominent heads-up when rain is about to start or
    /// stop here in the next couple of hours. Silent when nothing's imminent.
    @ViewBuilder private var nowcastBanner: some View {
        if let n = nowcast, let line = n.headline {
            HStack(spacing: 10) {
                Text(n.rainingNow ? "🌦" : "🌧").font(.system(size: 19))
                Text(line).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Sky.rain.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16).padding(.top, 12)
        }
    }

    private func reportSummary(_ r: UserReport) -> String {
        var parts: [String] = []
        if let rain = r.rainPercent { parts.append(rain == 0 ? "dry" : "\(Int(rain))% rain") }
        if let t = r.temperature { parts.append(Units.tempString(t)) }
        if let w = r.windSpeed { parts.append("\(Units.windString(w)) wind") }
        if let c = r.condition, let cond = WeatherCondition(rawValue: c) { parts.append(cond.rawValue.lowercased()) }
        return parts.isEmpty ? "conditions" : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if !warnings.isEmpty {
                    WarningsBanner(warnings: warnings)
                        .padding(.horizontal, 16).padding(.top, 12)
                }

                nowcastBanner

                // One compact row: the report action pinned on the left, the ambient
                // signals (moon, tide, calendar, sky, news) scrolling beside it — so
                // the weather itself isn't pushed down by two rows of chrome.
                SignalsStrip(calendarEvents: signals.calendarEvents, tideDay: tideDay,
                             moonData: moonData, astro: signals.astro, news: signals.news,
                             onOpenTab: onOpenTab, leading: AnyView(reportChip))
                    .padding(.top, 12)

                if simpleMode {
                    SimpleNowView(consensus: consensus, failedSources: failedSources,
                                  confidence: confidence, placeName: placeName,
                                  vsLastYear: vsLastYear, userReport: userReport,
                                  onOpenDetail: { withAnimation { simpleMode = false } },
                                  onTapTemperature: { showTodayOverlay = true })
                    Spacer(minLength: 20)
                } else {
                    detailedContent
                }
            }
            .task(id: location.coordinate.latitude) {
                onThisDay = try? await HistoricalService().onThisDay(location: location)
            }
            .task(id: location.coordinate.latitude) {
                warnings = await WarningsService().warnings(near: location)
            }
            .task(id: location.coordinate.latitude) {
                await signals.load(location: location, region: region, country: countryCode,
                                   forecast: consensus.dailyForecast)
            }
            .task(id: location.coordinate.latitude) {
                userReport = UserReportStore.shared.report(for: location)
            }
            .task(id: location.coordinate.latitude) {
                nowcast = await NowcastService().fetch(location: location)
                if let n = nowcast {
                    PrecipNotifier.shared.consider(n, place: placeName ?? "your area")
                }
            }
            .task(id: location.coordinate.latitude) {
                airQuality = await AirQualityService().fetch(location: location)
            }
        }
        .refreshable { await refresh?() }
        .overlay {
            if showTodayOverlay {
                TodayOverlay(hourly: consensus.hourlyForecast, isPresented: $showTodayOverlay)
            }
            if showFeedback {
                FeedbackOverlay(consensus: consensus, existing: userReport, isPresented: $showFeedback,
                                onSubmit: { r in
                                    UserReportStore.shared.save(r, for: location)
                                    userReport = r.isEmpty ? nil : r
                                },
                                onClear: {
                                    UserReportStore.shared.clear(for: location)
                                    userReport = nil
                                })
            }
        }
        .sheet(isPresented: $showWeekSheet) {
            NavigationStack {
                ZStack {
                    Sky.navy.ignoresSafeArea()
                    WeekView(daily: consensus.dailyForecast,
                             disagreementCount: consensus.dailyForecast.filter(\.hasDisagreement).count)
                }
                .navigationTitle("7 days").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showWeekSheet = false }.foregroundColor(Sky.tide)
                    }
                }
                .toolbarBackground(Sky.ink, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var detailedContent: some View {
        Group {
            VStack(spacing: 0) {
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
                actionRow("thermometer.medium", "Today",
                          value: today.map { "\(Units.tempString($0.tempMax)) / \(Units.tempString($0.tempMin))" },
                          detail: today?.condition.rawValue.lowercased(),
                          hint: "Opens today's hourly detail") { showTodayOverlay = true }
                divider
                weekRow(days)                       // the five-day icon strip
                divider
                standardRow(.tides, "water.waves", "Next tide",
                            value: nextTide.map(\.heightDisplay),
                            detail: nextTide.map { "\($0.type.rawValue.lowercased()) at \($0.timeDisplay)" })
                divider
                uvRow(consensus.uvIndex)
                divider
                if let a = airQuality {
                    aqiRow(a)
                    divider
                }
                if let m = moonData {
                    moonRow(m)
                } else {
                    standardRow(.sky, "moon.stars", "Moon", value: nil, detail: nil)
                }
                divider
                sourcesRow
                divider
                accuracyRow
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

    /// Same row, but runs an action (e.g. presents an overlay) rather than opening a tab.
    private func actionRow(_ icon: String, _ title: String, value: String?, detail: String?,
                           hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
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
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value ?? "unavailable"). \(hint).")
    }

    /// Air quality folded into one at-a-glance row: a severity-coloured dot and
    /// number carry the meaning, so a full card isn't needed. Shows pollen instead
    /// of the category where CAMS has it (Europe).
    private func aqiRow(_ a: AirQuality) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "aqi.medium").font(.system(size: 13, weight: .medium))
                .foregroundColor(Sky.muted).frame(width: 18)
            Text("Air quality").font(.system(size: 13)).foregroundColor(Sky.text)
            Spacer(minLength: 8)
            Text(a.topPollen.map { "\($0.name.capitalized) pollen \($0.level)" } ?? a.category.lowercased())
                .font(.system(size: 10)).foregroundColor(Sky.muted).lineLimit(1).layoutPriority(-1)
            Circle().fill(Color(hex: a.colorHex)).frame(width: 7, height: 7)
            Text("\(Int(a.usAqi.rounded()))").font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: a.colorHex))
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var rowChevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            .foregroundColor(Sky.muted.opacity(0.6))
    }

    /// UV as a colour scale: the WHO index ramp (green→yellow→orange→red→purple)
    /// with a marker where today sits, and the number in that band's colour.
    private func uvRow(_ uv: Double) -> some View {
        Button { onOpenTab?(.uv) } label: {
            HStack(spacing: 11) {
                Image(systemName: "sun.max").font(.system(size: 13, weight: .medium))
                    .foregroundColor(Sky.muted).frame(width: 18)
                Text("UV index").font(.system(size: 13)).foregroundColor(Sky.text)
                Spacer(minLength: 8)
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(
                        colors: [Color(hex: "3DD68C"), Color(hex: "F5D23D"), Color(hex: "F5A623"),
                                 Color(hex: "E05555"), Color(hex: "A78BFA")],
                        startPoint: .leading, endPoint: .trailing)).frame(width: 44, height: 4)
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Sky.navy, lineWidth: 1))
                        .offset(x: min(37, max(0, 44 * min(1, uv / 11) - 3.5)))
                }
                Text(uv.isFinite ? "\(Int(uv.rounded()))" : "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(uvColor(uv)).frame(minWidth: 18, alignment: .trailing)
                rowChevron
            }
            .padding(.vertical, 10).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("UV index \(Int(uv.rounded())), \(ComfortMetric.uv.comfortLabel(uv)). Opens UV.")
    }

    private func uvColor(_ uv: Double) -> Color {
        switch uv {
        case ..<3:  Color(hex: "3DD68C")
        case ..<6:  Color(hex: "F5D23D")
        case ..<8:  Color(hex: "F5A623")
        case ..<11: Color(hex: "E05555")
        default:    Color(hex: "A78BFA")
        }
    }

    /// Moon as a fill: a ring that runs empty at new moon to full at full moon,
    /// with the illumination percentage beside it.
    private func moonRow(_ m: MoonData) -> some View {
        Button { onOpenTab?(.sky) } label: {
            HStack(spacing: 11) {
                Image(systemName: "moon.stars").font(.system(size: 13, weight: .medium))
                    .foregroundColor(Sky.muted).frame(width: 18)
                Text("Moon").font(.system(size: 13)).foregroundColor(Sky.text)
                Spacer(minLength: 8)
                Text(m.phase.rawValue.lowercased()).font(.system(size: 10)).foregroundColor(Sky.muted)
                    .lineLimit(1).layoutPriority(-1)
                ZStack {
                    Circle().stroke(Sky.surface, lineWidth: 3).frame(width: 15, height: 15)
                    Circle().trim(from: 0, to: m.illumination)
                        .stroke(Sky.text, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 15, height: 15).rotationEffect(.degrees(-90))
                }
                Text("\(m.illuminationPercent)%").font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Sky.white).frame(minWidth: 34, alignment: .trailing)
                rowChevron
            }
            .padding(.vertical, 10).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Moon, \(m.phase.rawValue), \(m.illuminationPercent) percent lit. Opens Sky.")
    }

    /// The accuracy ledger, folded into one line — which source has been sharpest
    /// here, or the learning progress — tapping through to the full scoreboard. It
    /// no longer needs a whole card on the home screen.
    private var accuracyRow: some View {
        let table = SkillLedger.shared.table(for: location)
        let forecast = consensus.sources.filter { $0.kind == .forecast }
        let weighted = table.weights(for: .temp, among: forecast) != nil
        let best = forecast.filter { table.samples($0, .temp) >= SkillTable.minSamples }
            .min { (table.mae($0, .temp) ?? .infinity) < (table.mae($1, .temp) ?? .infinity) }
        let minChecks = forecast.map { table.samples($0, .temp) }.min() ?? 0
        return Button { onOpenTab?(.sources) } label: {
            HStack(spacing: 11) {
                Image(systemName: "scope").font(.system(size: 13, weight: .medium))
                    .foregroundColor(Sky.muted).frame(width: 18)
                Text("Most accurate").font(.system(size: 13)).foregroundColor(Sky.text)
                Spacer(minLength: 8)
                if weighted, let b = best {
                    Text("here lately").font(.system(size: 10)).foregroundColor(Sky.muted)
                        .lineLimit(1).layoutPriority(-1)
                    Text(b.short).font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Comfort.good)
                } else {
                    Text("learning").font(.system(size: 10)).foregroundColor(Sky.muted)
                    Text("\(minChecks)/\(SkillTable.minSamples)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Sky.muted)
                }
                rowChevron
            }
            .padding(.vertical, 10).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weighted ? "Most accurate source here lately, \(best?.rawValue ?? "unknown"). Opens Sources."
                                     : "Learning the most accurate source, \(minChecks) of \(SkillTable.minSamples) checks. Opens Sources.")
    }

    /// Sources agreeing, tinted by agreement — green when they line up, amber when
    /// they don't, matching the confidence language everywhere else.
    private var sourcesRow: some View {
        let agree = flagCount == 0
        return Button { onOpenTab?(.sources) } label: {
            HStack(spacing: 11) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 13, weight: .medium))
                    .foregroundColor(Sky.muted).frame(width: 18)
                Text("Sources agreeing").font(.system(size: 13)).foregroundColor(Sky.text)
                Spacer(minLength: 8)
                Text(agree ? "no disagreements" : "\(flagCount) metric\(flagCount == 1 ? "" : "s") vary")
                    .font(.system(size: 10)).foregroundColor(Sky.muted).lineLimit(1).layoutPriority(-1)
                Circle().fill(agree ? Comfort.good : Sky.amber).frame(width: 7, height: 7)
                Text("\(consensus.sources.count)/\(consensus.sources.count + failedSources.count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(agree ? Comfort.good : Sky.amber).frame(minWidth: 30, alignment: .trailing)
                rowChevron
            }
            .padding(.vertical, 10).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sources agreeing, \(consensus.sources.count) of \(consensus.sources.count + failedSources.count). Opens Sources.")
    }

    /// The week at a glance: the next five days as icon cells, each with its day,
    /// weather glyph and high/low, opening the Week tab.
    private func weekRow(_ days: [ConsensusDaily]) -> some View {
        Button { showWeekSheet = true } label: {
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

// MARK: - Home signals

/// The "worth-knowing" things that don't have a number on the dial but change your
/// day: a calendar event the weather threatens, a rare sky event coming up, a
/// serious weather story. Tide and moon come straight from the aggregator; these
/// three are fetched here, best-effort and off the critical path.
@MainActor
final class HomeSignals: ObservableObject {
    @Published var astro: AstroEvent?
    @Published var news: WeatherNewsItem?
    @Published var calendarEvents: [WeatherEvent] = []

    private let calendar = CalendarWeatherManager()
    private var lastKey = ""

    func load(location: CLLocation, region: String?, country: String?,
              forecast: [ConsensusDaily]) async {
        // Refetch only when the ~5 km grid cell changes, not on every redraw.
        let key = "\(Int(location.coordinate.latitude * 20)),\(Int(location.coordinate.longitude * 20))"
        guard key != lastKey else { return }
        lastKey = key

        // Sky: the soonest notable event in the next month.
        let events = await AstroService().upcomingEvents(near: location, months: 2)
        astro = events.first { $0.daysUntil <= 30 }

        // News: the most serious weather story — only if it's actually serious.
        let stories = await WeatherNewsService().fetchLocalNews(
            location: location, region: region, countryCode: country)
        news = stories.first { $0.impact == .high } ?? stories.first { $0.impact == .medium }

        // Calendar: only when the user has already granted access — never prompt
        // from the home screen. Keep events the forecast genuinely threatens.
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            await calendar.analyse(forecast: forecast)
            calendarEvents = calendar.weatherEvents.filter { $0.impact >= .watch }
        }
    }
}

/// A horizontal run of signal chips, each shown only when it has something to say,
/// each a tap into the tab that owns it. Deliberately quiet — this is peripheral
/// awareness, not the main event.
struct SignalsStrip: View {
    let calendarEvents: [WeatherEvent]
    let tideDay: TideDay?
    let moonData: MoonData?
    let astro: AstroEvent?
    let news: WeatherNewsItem?
    let onOpenTab: ((ContentView.Tab) -> Void)?
    /// A pinned chip (e.g. the report action) shown before the scrolling signals,
    /// so two rows of chrome collapse into one.
    var leading: AnyView? = nil

    private struct Chip: Identifiable {
        let id = UUID()
        let emoji: String; let text: String; let color: Color; let tab: ContentView.Tab
    }

    var body: some View {
        let chips = buildChips()
        if leading != nil || !chips.isEmpty {
            HStack(spacing: 8) {
                if let leading { leading }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { c in
                            Button { onOpenTab?(c.tab) } label: {
                                HStack(spacing: 5) {
                                    Text(c.emoji).font(.system(size: 12))
                                    Text(c.text).font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Sky.white).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(c.color.opacity(0.16))
                                .overlay(Capsule().stroke(c.color.opacity(0.45), lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 16)
                }
            }
            .padding(.leading, 16)
        }
    }

    private func buildChips() -> [Chip] {
        var out: [Chip] = []

        // Calendar interruptions — worst first (analyse already sorts).
        if let worst = calendarEvents.first {
            let text = calendarEvents.count == 1
                ? short(worst.title, 20)
                : "\(calendarEvents.count) events at risk"
            out.append(Chip(emoji: "📅", text: text,
                            color: worst.impact == .major ? Sky.red : Sky.amber, tab: .plans))
        }

        // Next tide.
        if let next = tideDay?.events.first(where: { $0.time > Date() }) {
            out.append(Chip(emoji: "🌊", text: "\(next.type.rawValue) \(next.timeDisplay)",
                            color: Sky.tide, tab: .tides))
        }

        // Moon.
        if let m = moonData {
            let text = m.daysToFull <= 1 ? "Full moon" : "\(m.illuminationPercent)% lit"
            out.append(Chip(emoji: m.phase.emoji, text: text, color: Sky.muted, tab: .sky))
        }

        // Sky alert — a notable event coming up soon.
        if let a = astro {
            let when = a.daysUntil == 0 ? "tonight" : "\(a.daysUntil)d"
            out.append(Chip(emoji: a.type.emoji, text: "\(short(a.title, 16)) \(when)",
                            color: Sky.wind, tab: .sky))
        }

        // Serious weather news.
        if let n = news {
            out.append(Chip(emoji: "📰", text: short(n.headline, 24),
                            color: n.impact == .high ? Sky.red : Sky.amber, tab: .sky))
        }

        return out
    }

    private func short(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Today overlay

/// Tapping the temperature opens today hour-by-hour without leaving the screen —
/// a semi-transparent sheet with a VERTICAL timeline: time runs down, each hour's
/// temperature is a comfort-lit dot tracing across the day's low→high range, so the
/// shape of the day reads as a single glance down the column.
struct TodayOverlay: View {
    let hourly: [ConsensusHourly]
    @Binding var isPresented: Bool

    var body: some View {
        let hours = Array(hourly.prefix(24))
        let lo = hours.map(\.temperature).min() ?? 0
        let hi = hours.map(\.temperature).max() ?? 1

        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY").font(.system(size: 11, weight: .bold)).kerning(1.6).foregroundColor(Sky.muted)
                        Text("Hour by hour").font(.system(size: 19, weight: .semibold)).foregroundColor(Sky.white)
                    }
                    Spacer()
                    Text("\(Units.tempString(lo)) – \(Units.tempString(hi))")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Sky.muted)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 26))
                            .foregroundColor(Sky.muted).padding(.leading, 8)
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(hours.enumerated()), id: \.element.id) { i, h in
                            row(h, lo: lo, hi: hi, isFirst: i == 0)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 22)
                }
            }
            .background(Sky.navy.opacity(0.82))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Sky.surface.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 12).padding(.vertical, 44)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func dismiss() { withAnimation(.easeOut(duration: 0.2)) { isPresented = false } }

    private func row(_ h: ConsensusHourly, lo: Double, hi: Double, isFirst: Bool) -> some View {
        let span = max(hi - lo, 1)
        let t = CGFloat((h.temperature - lo) / span)
        let c = Comfort.comfortColor(ComfortMetric.temp.score(h.temperature))
        return HStack(spacing: 10) {
            Text(isFirst ? "Now" : h.hourLabel)
                .font(.system(size: 12, weight: isFirst ? .bold : .regular))
                .foregroundColor(isFirst ? Sky.white : Sky.muted)
                .frame(width: 42, alignment: .leading)
            Image(systemName: h.condition.icon).font(.system(size: 13))
                .foregroundColor(Sky.text).frame(width: 20)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Sky.surface.opacity(0.6)).frame(height: 3)
                    Circle().fill(c).frame(width: 11, height: 11)
                        .shadow(color: c.opacity(0.6), radius: 4)
                        .offset(x: max(0, min(w - 11, t * w - 5.5)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 26)
            if h.rainProbability >= 30 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill").font(.system(size: 8))
                    Text("\(Int(h.rainProbability.rounded()))%").font(.system(size: 10))
                }
                .foregroundColor(Sky.rain).frame(width: 38, alignment: .trailing)
            } else {
                Color.clear.frame(width: 38, height: 1)
            }
            Text(Units.tempString(h.temperature))
                .font(.system(size: 15, weight: .semibold)).foregroundColor(Sky.white)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 6.5)
    }
}

// MARK: - Feedback / correction overlay

/// "It says raining, it's dry." A semi-transparent overlay from the main screen
/// where you correct any dimension with a couple of taps. Stored as a UserReport;
/// on-device ground truth today, the People's Weather layer tomorrow.
struct FeedbackOverlay: View {
    let consensus: ConsensusWeather
    let existing: UserReport?
    @Binding var isPresented: Bool
    let onSubmit: (UserReport) -> Void
    let onClear: () -> Void

    @State private var rain: Double?
    @State private var temp: Double?
    @State private var wind: Double?
    @State private var condition: String?

    init(consensus: ConsensusWeather, existing: UserReport?, isPresented: Binding<Bool>,
         onSubmit: @escaping (UserReport) -> Void, onClear: @escaping () -> Void) {
        self.consensus = consensus
        self.existing = existing
        self._isPresented = isPresented
        self.onSubmit = onSubmit
        self.onClear = onClear
        _rain = State(initialValue: existing?.rainPercent)
        _temp = State(initialValue: existing?.temperature)
        _wind = State(initialValue: existing?.windSpeed)
        _condition = State(initialValue: existing?.condition)
    }

    private let rainOpts: [(String, String, Double)] =
        [("☀️", "Dry", 0), ("🌦", "Showers", 40), ("🌧", "Rain", 70), ("⛈", "Heavy", 100)]
    private let windOpts: [(String, String, Double)] =
        [("🍃", "Calm", 0), ("💨", "Breezy", 15), ("🌬", "Windy", 30), ("🌪", "Strong", 50)]
    private var skyOpts: [(String, String, String)] {
        [("☀️", "Clear", WeatherCondition.clearSky.rawValue), ("☁️", "Cloudy", WeatherCondition.overcast.rawValue),
         ("🌧", "Rain", WeatherCondition.rain.rawValue), ("⛈", "Storm", WeatherCondition.thunderstorm.rawValue)]
    }
    private var nothingSet: Bool { rain == nil && temp == nil && wind == nil && condition == nil }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { dismiss() }
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        rainRow; tempRow; windRow; skyRow
                    }
                    .padding(20)
                }
                footer
            }
            .background(Sky.navy.opacity(0.9))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Sky.surface.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 12).padding(.vertical, 40)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func dismiss() { withAnimation(.easeOut(duration: 0.2)) { isPresented = false } }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WHAT'S IT ACTUALLY DOING?")
                    .font(.system(size: 11, weight: .bold)).kerning(1).foregroundColor(Sky.muted)
                Text("Correct anything that's off").font(.system(size: 19, weight: .semibold)).foregroundColor(Sky.white)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundColor(Sky.muted)
            }.accessibilityLabel("Close")
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
    }

    private func dimHeader(_ label: String, _ forecast: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15, weight: .semibold)).foregroundColor(Sky.white)
            Spacer()
            Text("forecast \(forecast)").font(.system(size: 12)).foregroundColor(Sky.muted)
        }
    }

    private var rainRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            dimHeader("Rain", "\(Int(consensus.rainProbability.rounded()))%")
            chips(rainOpts, selected: rain) { v in rain = (rain == v ? nil : v) }
        }
    }
    private var windRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            dimHeader("Wind", Units.windString(consensus.windSpeed))
            chips(windOpts, selected: wind) { v in wind = (wind == v ? nil : v) }
        }
    }
    private var skyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            dimHeader("Sky", consensus.condition.rawValue.lowercased())
            chips(skyOpts, selected: condition) { v in condition = (condition == v ? nil : v) }
        }
    }
    private var tempRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            dimHeader("Temp", Units.tempString(consensus.temperature))
            HStack(spacing: 14) {
                stepBtn("minus") { temp = (temp ?? consensus.temperature) - 1 }
                Text(temp.map { Units.tempString($0) } ?? "tap to set")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(temp == nil ? Sky.muted : Sky.white).frame(minWidth: 92)
                stepBtn("plus") { temp = (temp ?? consensus.temperature) + 1 }
                Spacer()
                if temp != nil {
                    Button("clear") { temp = nil }.font(.system(size: 12)).foregroundColor(Sky.muted)
                }
            }
        }
    }

    private func stepBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(Sky.tide)
                .frame(width: 40, height: 40).background(Sky.surface).clipShape(Circle())
        }.buttonStyle(.plain)
    }

    private func chips<V: Equatable>(_ opts: [(String, String, V)], selected: V?,
                                     tap: @escaping (V) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(opts.enumerated()), id: \.offset) { _, opt in
                let isSel = selected == opt.2
                Button { tap(opt.2) } label: {
                    VStack(spacing: 3) {
                        Text(opt.0).font(.system(size: 20))
                        Text(opt.1).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(isSel ? Sky.tide.opacity(0.2) : Sky.surface.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSel ? Sky.tide : .clear, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(isSel ? Sky.white : Sky.text)
                }.buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if existing != nil {
                Button { onClear(); dismiss() } label: {
                    Text("Clear").font(.system(size: 14, weight: .medium)).foregroundColor(Sky.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Sky.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            Button {
                onSubmit(UserReport(reportedAt: Date(), rainPercent: rain, temperature: temp,
                                    windSpeed: wind, condition: condition))
                dismiss()
            } label: {
                Text("Save report").font(.system(size: 14, weight: .semibold)).foregroundColor(Sky.navy)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(nothingSet ? Sky.tide.opacity(0.4) : Sky.tide)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(nothingSet)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}

// MARK: - Most accurate here (the accuracy ledger, surfaced)

/// The moat made visible: which source has actually been closest to the
/// thermometer *here* lately, and whether we've earned the right to weight it. No
/// mainstream weather app tells you this — it's the single strongest answer to the
/// category's #1 complaint (accuracy), grounded in what you can verify out a window.
struct MostAccurateCard: View {
    let location: CLLocation
    let sources: [WeatherSource]
    let onOpen: () -> Void

    var body: some View {
        let table = SkillLedger.shared.table(for: location)
        let forecast = sources.filter { $0.kind == .forecast }
        let weighted = table.weights(for: .temp, among: forecast) != nil
        let ranked = forecast
            .filter { table.samples($0, .temp) >= SkillTable.minSamples }
            .sorted { (table.mae($0, .temp) ?? .infinity) < (table.mae($1, .temp) ?? .infinity) }
        let minChecks = forecast.map { table.samples($0, .temp) }.min() ?? 0

        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("🎯 MOST ACCURATE HERE").font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
                    Spacer()
                    Text(weighted ? "weighting consensus" : "learning")
                        .font(.system(size: 9)).foregroundColor(weighted ? Comfort.good : Sky.muted)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Sky.muted.opacity(0.6))
                }

                if weighted, let best = ranked.first, let bestMae = table.mae(best, .temp) {
                    Text("\(best.rawValue) leads temperature here")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Sky.white)
                    ForEach(ranked.prefix(3), id: \.self) { s in
                        bar(s, mae: table.mae(s, .temp) ?? bestMae, best: bestMae, checks: table.samples(s, .temp))
                    }
                    Text("Average miss vs the nearest thermometer over the last few weeks. Your consensus leans on whoever's been closest here.")
                        .font(.system(size: 10)).foregroundColor(Sky.muted).lineSpacing(2)
                } else {
                    Text("Learning which source is sharpest here")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Sky.white)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Sky.surface).frame(height: 6)
                            Capsule().fill(Comfort.good)
                                .frame(width: geo.size.width *
                                       min(1, Double(minChecks) / Double(SkillTable.minSamples)), height: 6)
                        }
                    }.frame(height: 6)
                    Text("\(minChecks)/\(SkillTable.minSamples) checks so far. Once every source has been scored against the nearby thermometer, the consensus starts favouring whichever has been closest to reality here.")
                        .font(.system(size: 10)).foregroundColor(Sky.muted).lineSpacing(2)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Comfort.good.opacity(weighted ? 0.3 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Source · accuracy bar (fuller = sharper, comfort-ramp coloured) · ±miss.
    private func bar(_ s: WeatherSource, mae: Double, best: Double, checks: Int) -> some View {
        let frac = max(0.12, min(1, best / max(mae, 0.01)))
        return HStack(spacing: 8) {
            Circle().fill(Color(hex: s.colorHex)).frame(width: 5, height: 5)
            Text(s.short).font(.system(size: 11)).foregroundColor(Sky.text).frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Sky.surface).frame(height: 5)
                    Capsule().fill(Comfort.comfortColor(frac * 2 - 1)).frame(width: geo.size.width * frac, height: 5)
                }.frame(maxHeight: .infinity, alignment: .center)
            }.frame(height: 16)
            Text("±\(String(format: "%.1f", Units.tempDelta(mae)))\(Units.temperature.label)")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(Sky.white)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - Precip nowcast notifier

/// Fires a quiet local notification when rain is about to start here — the
/// "rain in 15 min at your location" alert people have missed since Dark Sky.
/// Provisional authorisation delivers it to Notification Center with no intrusive
/// prompt; the user can promote it to a banner alert from Settings. De-duplicated
/// so one incoming shower produces one heads-up, not one per refresh.
final class PrecipNotifier {
    static let shared = PrecipNotifier()
    private var lastNotifiedStart: Date?

    func consider(_ nowcast: PrecipNowcast, place: String) {
        // Only for rain STARTING soon while it's currently dry.
        guard !nowcast.rainingNow, let change = nowcast.nextChange, change.starts,
              let mins = nowcast.minutesToChange, mins <= 45 else { return }
        if let last = lastNotifiedStart, abs(last.timeIntervalSince(change.at)) < 30 * 60 { return }
        lastNotifiedStart = change.at

        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .provisional])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rain soon in \(place)"
            content.body = mins <= 5 ? "Rain starting in a few minutes." : "Rain starting in about \(mins) minutes."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let req = UNNotificationRequest(identifier: "precip-\(Int(change.at.timeIntervalSince1970))",
                                            content: content, trigger: trigger)
            try? await center.add(req)
        }
    }
}

// MARK: - Air quality card

/// AQI + particulates (global) and pollen (where CAMS covers it). Baseline info
/// users now expect; kept quiet — one glanceable number, coloured by severity.
struct AirQualityCard: View {
    let air: AirQuality?

    var body: some View {
        Group {
            if let a = air {
                let c = Color(hex: a.colorHex)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("🌫 AIR QUALITY").font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
                        Spacer()
                        Text(a.category).font(.system(size: 10, weight: .semibold)).foregroundColor(c)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(a.usAqi.rounded()))")
                            .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(Sky.white)
                        Text("US AQI").font(.system(size: 11)).foregroundColor(Sky.muted)
                        Spacer()
                        if let pm = a.pm25 { pill("PM2.5", String(format: "%.0f", pm)) }
                        if let o = a.ozone { pill("O₃", String(format: "%.0f", o)) }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Sky.green, Sky.amber, Color(hex: "E05555")],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(height: 6).opacity(0.35)
                            Circle().fill(c).frame(width: 12, height: 12)
                                .shadow(color: c.opacity(0.6), radius: 4)
                                .offset(x: max(0, min(geo.size.width - 12, geo.size.width * a.dialFraction - 6)))
                        }.frame(maxHeight: .infinity, alignment: .center)
                    }.frame(height: 14)
                    if let p = a.topPollen {
                        Text("🌾 \(p.name.capitalized) pollen \(p.level)")
                            .font(.system(size: 11)).foregroundColor(Sky.text)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func pill(_ label: String, _ val: String) -> some View {
        VStack(spacing: 1) {
            Text(val).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Sky.white)
            Text(label).font(.system(size: 8)).foregroundColor(Sky.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Sky.surface).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
