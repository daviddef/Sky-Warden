// SkyWarden — Plans · UV · Sky · News tabs
// Each owns one concept and wires the app's real services.

import SwiftUI
import CoreLocation
import EventKit
import UserNotifications

// MARK: - Shared uppercase section label
private func tabHeader(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Plans (Apple Calendar × forecast)
// ────────────────────────────────────────────────────────────────────────────
struct PlansView: View {
    let dailyForecast: [ConsensusDaily]
    @StateObject private var manager = CalendarWeatherManager()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                tabHeader("📆 UPCOMING OUTDOOR EVENTS")

                if manager.authorizationStatus == .fullAccess {
                    if manager.weatherEvents.isEmpty {
                        infoCard("No outdoor events found in your calendar for the next 7 days. Events with keywords like beach, hike, soccer or BBQ get flagged here against the forecast.")
                    } else {
                        ForEach(manager.weatherEvents) { EventCard(event: $0) }
                    }
                } else {
                    permissionCard
                }

                infoCard("Reads your Apple Calendar · Flags events with outdoor keywords · Updates as the forecast changes")
            }
            .padding(16)
        }
        .task {
            await manager.requestAccess()
            await manager.analyse(forecast: dailyForecast)
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 30)).foregroundColor(Sky.tide)
            Text("Allow calendar access to check the weather against your outdoor plans.")
                .font(.system(size: 13)).foregroundColor(Sky.text).multilineTextAlignment(.center)
            Button("Enable Calendar") { Task { await manager.requestAccess(); await manager.analyse(forecast: dailyForecast) } }
                .font(.system(size: 13, weight: .semibold)).foregroundColor(Sky.navy)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Sky.tide).clipShape(Capsule())
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func infoCard(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundColor(Sky.muted).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct EventCard: View {
    let event: WeatherEvent

    private var style: (bg: Color, border: Color, color: Color) {
        switch event.impact {
        case .major: (Sky.red.opacity(0.07), Sky.red.opacity(0.25), Sky.red)
        case .watch: (Sky.amber.opacity(0.07), Sky.amber.opacity(0.25), Sky.amber)
        case .minor: (Sky.green.opacity(0.05), Sky.green.opacity(0.2), Sky.green)
        case .clear: (Sky.card, .clear, Sky.green)
        }
    }
    /// An event past the forecast horizon has no forecast. `?? 0` used to turn
    /// that absence into 0% rain, which rendered a confident ☀️ for a day nobody
    /// has predicted yet.
    private var condEmoji: String {
        guard let r = event.forecast?.rainProbability else { return "❔" }
        return r > 50 ? "🌧" : r > 20 ? "⛅" : "☀️"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.impact.emoji).font(.system(size: 14))
                    Text(event.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Sky.white)
                }
                Text("\(event.dateLabel) · \(event.timeLabel)")
                    .font(.system(size: 11)).foregroundColor(Sky.muted)
                if let warning = event.warningText {
                    Text(warning).font(.system(size: 11)).foregroundColor(style.color).lineSpacing(2)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 1) {
                Text(condEmoji).font(.system(size: 20))
                if let f = event.forecast {
                    Text(Units.tempString(f.tempMax)).font(.system(size: 13, weight: .semibold)).foregroundColor(Sky.white)
                    Text("\(Int(f.rainProbability.rounded()))%💧").font(.system(size: 11)).foregroundColor(Sky.rain)
                } else {
                    Text("no forecast\nyet")
                        .font(.system(size: 9)).foregroundColor(Sky.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(style.bg)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(style.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - UV guardian
// ────────────────────────────────────────────────────────────────────────────
private struct UVLevel { let max: Double; let label: String; let color: Color }
private let UV_LEVELS: [UVLevel] = [
    .init(max: 2, label: "Low", color: .hx("3DD68C")),
    .init(max: 5, label: "Moderate", color: .hx("F5A623")),
    .init(max: 7, label: "High", color: .hx("F87171")),
    .init(max: 10, label: "Very High", color: .hx("E05555")),
    .init(max: 20, label: "Extreme", color: .hx("C084FC")),
]

struct UVView: View {
    let consensus: ConsensusWeather
    @State private var showKids = true

    private var uv: Double { consensus.uvIndex }
    private var level: UVLevel { UV_LEVELS.first { uv <= $0.max } ?? UV_LEVELS[0] }
    private var pct: Double { min(1, uv / 14) }

    /// Most numerical models publish no UV — use the first source that does.
    private var hourlyUV: [(uv: Double, time: Date)] {
        for reading in consensus.rawReadings {
            let points = reading.hourlyForecast.compactMap { h in h.uvIndex.map { (uv: $0, time: h.time) } }
            if !points.isEmpty { return points }
        }
        return []
    }
    private var peak: (value: Double, time: Date)? {
        hourlyUV.max { $0.uv < $1.uv }.map { ($0.uv, $0.time) }
    }
    private var protectionWindow: (Date, Date)? {
        let over = hourlyUV.filter { $0.uv >= 3 }
        guard let first = over.first?.time, let last = over.last?.time else { return nil }
        return (first, last)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                gauge
                if let w = protectionWindow {
                    VStack(spacing: 1) {
                        Text("PROTECTION REQUIRED").font(.system(size: 9)).foregroundColor(Sky.muted).kerning(0.5)
                        Text("\(time(w.0)) – \(time(w.1))").font(.system(size: 15, weight: .semibold)).foregroundColor(level.color)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(level.color.opacity(0.12))
                    .overlay(Capsule().stroke(level.color.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())
                }
                slipSlop
                kidsToggle
            }
            .padding(16)
        }
    }

    private var gauge: some View {
        ZStack {
            Canvas { ctx, _ in
                let c = CGPoint(x: 100, y: 100), r: CGFloat = 78
                ctx.stroke(uvArc(-210, 30, r, c), with: .color(Sky.surface),
                           style: StrokeStyle(lineWidth: 12, lineCap: .round))
                if pct > 0.01 {
                    ctx.stroke(uvArc(-210, -210 + 240 * pct, r, c),
                               with: .linearGradient(Gradient(colors: UV_LEVELS.map(\.color)),
                                                     startPoint: CGPoint(x: 20, y: 180), endPoint: CGPoint(x: 180, y: 20)),
                               style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
            }
            .frame(width: 200, height: 200)
            VStack(spacing: 1) {
                Text("UV INDEX").font(.system(size: 9)).foregroundColor(Sky.muted).kerning(0.7)
                Text("\(Int(uv.rounded()))").font(.system(size: 52, weight: .ultraLight, design: .rounded)).foregroundColor(level.color)
                Text(level.label).font(.system(size: 14, weight: .semibold)).foregroundColor(level.color)
                if let p = peak {
                    Text("Peak \(Int(p.value.rounded())) · \(time(p.time))").font(.system(size: 9)).foregroundColor(Sky.muted)
                }
            }
        }
    }

    private var slipSlop: some View {
        HStack {
            ForEach([("👕", "Slip", "Cover up"), ("🧴", "Slop", "SPF 50+"), ("🧢", "Slap", "Hat"),
                     ("🌳", "Seek", "Shade"), ("🕶", "Slide", "Sunnies")], id: \.1) { e, l, d in
                VStack(spacing: 2) {
                    Text(e).font(.system(size: 22))
                    Text(l).font(.system(size: 10, weight: .bold)).foregroundColor(level.color)
                    Text(d).font(.system(size: 8)).foregroundColor(Sky.muted)
                }
                .frame(maxWidth: .infinity)
                .opacity(uv >= 3 ? 1 : 0.4)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 8)
        .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var kidsText: String {
        if uv <= 2 { return "Fine for outdoor play." }
        if uv <= 5 { return "SPF 50+ sunscreen 20 min before going out. Wide-brim hat and UV sunglasses." }
        if uv <= 7 { return "Rashie + SPF 50+ essential. Reapply after swimming. Hat and sunglasses required." }
        return "Keep babies under 12 months out of direct sun. Full protection required for all children."
    }

    private var kidsToggle: some View {
        VStack(spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showKids.toggle() } } label: {
                Text("👶 \(showKids ? "Hide" : "Show") children & babies advice")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(showKids ? level.color : Sky.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(showKids ? level.color.opacity(0.1) : Sky.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(showKids ? level.color.opacity(0.3) : .clear, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            if showKids {
                Text(kidsText).font(.system(size: 12)).foregroundColor(Sky.text).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Sky.card)
                    .overlay(alignment: .leading) { Rectangle().fill(level.color).frame(width: 3) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func uvArc(_ a1: Double, _ a2: Double, _ r: CGFloat, _ c: CGPoint) -> Path {
        var p = Path()
        let steps = max(2, Int(abs(a2 - a1) / 2))
        for i in 0...steps {
            let a = (a1 + (a2 - a1) * Double(i) / Double(steps) - 90) * .pi / 180
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - Sky (astronomical events)
// ────────────────────────────────────────────────────────────────────────────
struct SkyView: View {
    let location: CLLocation
    @State private var events: [AstroEvent] = []
    @State private var loaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                tabHeader("🔭 ASTRONOMICAL EVENTS")
                if events.isEmpty && loaded {
                    Text("No notable events in the months ahead.")
                        .font(.system(size: 12)).foregroundColor(Sky.muted).padding(.top, 20)
                }
                ForEach(events) { AstroCard(event: $0) }
            }
            .padding(16)
        }
        .task {
            events = await AstroService().upcomingEvents(near: location)
            loaded = true
            // Schedule reminders for rare/notable events (3 days & 1 day before).
            // Provisional authorization delivers quietly with no intrusive prompt;
            // the user can promote these to prominent alerts from Notification Center.
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
            AstroNotificationScheduler().schedule(events: events)
        }
    }
}

private struct AstroCard: View {
    let event: AstroEvent

    private var accent: Color {
        switch event.rarity {
        case .rare: Sky.astro
        case .notable: Sky.moon
        default: Sky.muted
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(event.type.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Sky.white)
                    Spacer()
                    Text(event.dateLabel).font(.system(size: 11)).foregroundColor(Sky.muted)
                }
                Text(event.description).font(.system(size: 11)).foregroundColor(Sky.muted).lineSpacing(2)
                if event.rarity == .rare {
                    Text("RARE · PUSH NOTIFICATION SET")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(Sky.astro).kerning(0.5)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Sky.astro.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Sky.card)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ────────────────────────────────────────────────────────────────────────────
// MARK: - News
// ────────────────────────────────────────────────────────────────────────────
struct NewsView: View {
    let location: CLLocation
    let region: String?
    let countryCode: String?
    @State private var items: [WeatherNewsItem] = []
    @State private var loaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                tabHeader("📰 LOCAL WEATHER NEWS")
                if items.isEmpty && loaded {
                    Text("No current warnings or weather news for your area.")
                        .font(.system(size: 12)).foregroundColor(Sky.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
                ForEach(items) { NewsCard(item: $0) }
                sourcesFootnote
            }
            .padding(16)
        }
        .task {
            items = await WeatherNewsService().fetchLocalNews(
                location: location, region: region, countryCode: countryCode)
            loaded = true
        }
    }

    private var sourcesFootnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OFFICIAL WARNING SOURCES").font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
            Text("BOM Warnings Summary — free RSS per state (severe storm, cyclone, flood, fire, marine). BOM Anonymous FTP — the same products as machine-readable XML. BOM Space Weather API — geomagnetic storms and aurora alerts. High-impact warnings surface at the top of this list and on the Now screen ahead of general coverage.")
                .font(.system(size: 11)).foregroundColor(Sky.muted).lineSpacing(3)
        }
        .padding(14).background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct NewsCard: View {
    let item: WeatherNewsItem
    private var isHigh: Bool { item.impact == .high }
    private var isWarning: Bool { item.source.localizedCaseInsensitiveContains("warning") }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 6) {
                    if isWarning {
                        Text("⚠ OFFICIAL").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Sky.red).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(item.source.uppercased())
                        .font(.system(size: 9, weight: .bold)).foregroundColor(isHigh ? Sky.red : Sky.muted).kerning(0.5)
                }
                Spacer()
                Text(item.timeLabel).font(.system(size: 9)).foregroundColor(Sky.muted)
            }
            Text(item.headline).font(.system(size: 13, weight: .semibold)).foregroundColor(Sky.white).lineSpacing(2)
            Text(item.excerpt).font(.system(size: 11)).foregroundColor(Sky.muted).lineSpacing(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(isHigh ? Sky.red.opacity(0.06) : Sky.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isHigh ? Sky.red.opacity(0.3) : .clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
