// SkyWarden — Scene tab
// An illustrated beach-house scene where every element is driven by real data:
// sky colour blends through the day, the water line tracks the tide, clouds/rain
// scale with rain probability, and the palm + dune grass bend with wind speed.
// Ported from the prototype's SceneTab (SVG → SwiftUI Canvas).

import SwiftUI

// MARK: - Sky keyframes
private struct SkyKeyframe {
    let h: Double
    let top: Color, mid: Color, bottom: Color
    let sun: String?      // "rise" | "low" | "high" | "set" | nil (night)
    let stars: Double
    let glow: Double
}

private let SKY_KEYFRAMES: [SkyKeyframe] = [
    .init(h: 0,    top: .hx("040A16"), mid: .hx("0A1830"), bottom: .hx("122544"), sun: nil,     stars: 1.0,  glow: 0),
    .init(h: 4.5,  top: .hx("0A1830"), mid: .hx("16264A"), bottom: .hx("2C3F63"), sun: nil,     stars: 0.7,  glow: 0),
    .init(h: 5.8,  top: .hx("2B3A63"), mid: .hx("8B5A6B"), bottom: .hx("FFA366"), sun: "rise",  stars: 0.15, glow: 0.6),
    .init(h: 7,    top: .hx("6FA8D0"), mid: .hx("9AC8DE"), bottom: .hx("FFD9A0"), sun: "low",   stars: 0,    glow: 0.35),
    .init(h: 9.5,  top: .hx("4A9AD4"), mid: .hx("7EC3E8"), bottom: .hx("D6EEF7"), sun: "high",  stars: 0,    glow: 0.15),
    .init(h: 14.5, top: .hx("4A9AD4"), mid: .hx("7EC3E8"), bottom: .hx("D6EEF7"), sun: "high",  stars: 0,    glow: 0.15),
    .init(h: 16.5, top: .hx("5B8DC7"), mid: .hx("8FB4D8"), bottom: .hx("FFDDA8"), sun: "low",   stars: 0,    glow: 0.3),
    .init(h: 18,   top: .hx("4A4C8C"), mid: .hx("B0587A"), bottom: .hx("FF9159"), sun: "set",   stars: 0.1,  glow: 0.7),
    .init(h: 19.2, top: .hx("241E4C"), mid: .hx("5C3A63"), bottom: .hx("B45C5A"), sun: nil,     stars: 0.45, glow: 0.25),
    .init(h: 20.5, top: .hx("0F1730"), mid: .hx("1B2748"), bottom: .hx("2E3A5E"), sun: nil,     stars: 0.8,  glow: 0),
    .init(h: 24,   top: .hx("040A16"), mid: .hx("0A1830"), bottom: .hx("122544"), sun: nil,     stars: 1.0,  glow: 0),
]

private struct SkyState {
    let top: Color, mid: Color, bottom: Color
    let sun: String?
    let stars: Double, glow: Double
}

private func skyAt(_ hour: Double) -> SkyState {
    let kf = SKY_KEYFRAMES
    for i in 0..<(kf.count - 1) where hour >= kf[i].h && hour <= kf[i + 1].h {
        let t = (hour - kf[i].h) / (kf[i + 1].h - kf[i].h)
        return SkyState(
            top: Comfort.mix(kf[i].top, kf[i + 1].top, t),
            mid: Comfort.mix(kf[i].mid, kf[i + 1].mid, t),
            bottom: Comfort.mix(kf[i].bottom, kf[i + 1].bottom, t),
            sun: t < 0.5 ? kf[i].sun : kf[i + 1].sun,
            stars: kf[i].stars + (kf[i + 1].stars - kf[i].stars) * t,
            glow: kf[i].glow + (kf[i + 1].glow - kf[i].glow) * t
        )
    }
    let last = kf[kf.count - 1]
    return SkyState(top: last.top, mid: last.mid, bottom: last.bottom, sun: last.sun, stars: last.stars, glow: last.glow)
}

// Deterministic star field
private struct Star { let x: Double; let y: Double; let r: Double; let bright: Double }
private let STARS: [Star] = (0..<45).map { i in
    let x = Double((i * 41 + 7) % 330 + 5)
    let y = Double((i * 59 + 3) % 140 + 8)
    let r = 0.5 + Double((i * 13) % 10) / 12.0
    let bright = 0.4 + Double((i * 23) % 10) / 14.0
    return Star(x: x, y: y, r: r, bright: bright)
}

extension Color { static func hx(_ h: String) -> Color { Color(hex: h) } }

// MARK: - Scene view
struct SceneView: View {
    let consensus: ConsensusWeather
    let tideDay: TideDay?

    private let W: CGFloat = 340
    private let H: CGFloat = 460

    // Fractional hour of day (device timezone)
    private var hour: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }

    /// `nil` when there is no tide data. It used to fall back to (1.0m, mid) and
    /// the scene printed "1.0m" in the same pill it uses for a real reading —
    /// a fabricated measurement, presented as measured. Now the water sits at a
    /// neutral level and the pill says so.
    private var tide: (now: Double, frac: Double)? {
        guard let events = tideDay?.events, events.count >= 2 else { return nil }
        let pts = events.map { (h: fracHour($0.time), v: $0.height) }.sorted { $0.h < $1.h }
        let heights = pts.map(\.v)
        let lo = heights.min() ?? 0, hi = heights.max() ?? 1
        var now = pts.first!.v
        for i in 0..<(pts.count - 1) where hour >= pts[i].h && hour <= pts[i + 1].h {
            let t = (hour - pts[i].h) / (pts[i + 1].h - pts[i].h)
            let eased = (1 - cos(t * .pi)) / 2
            now = pts[i].v + (pts[i + 1].v - pts[i].v) * eased
        }
        if hour < pts.first!.h { now = pts.first!.v }
        if hour > pts.last!.h { now = pts.last!.v }
        let frac = hi > lo ? (now - lo) / (hi - lo) : 0.5
        return (now, frac)
    }
    private func fracHour(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                illustration
                legend.padding(.horizontal, 16).padding(.top, 14)
                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Illustration (Canvas + glass overlays)
    private var illustration: some View {
        let sky = skyAt(hour)
        let rain = consensus.rainProbability
        let wind = consensus.windSpeed
        let t = tide
        return ZStack {
            Canvas { ctx, _ in
                drawScene(ctx, sky: sky, rain: rain, wind: wind, tideFrac: t?.frac ?? 0.5)
            }
            .frame(width: W, height: H)

            VStack(spacing: 8) {
                HStack {
                    glassPill(alignment: .leading,
                              title: clockLabel(hour),
                              subtitle: phaseLabel(sky))
                    Spacer()
                    glassPill(alignment: .trailing,
                              title: t.map { String(format: "%.1fm", $0.now) } ?? "—",
                              subtitle: t.map { "tide \($0.frac > 0.6 ? "rising" : $0.frac < 0.4 ? "low" : "turning")" }
                                        ?? "no tide data")
                }
                metricCards
                Spacer()
            }
            .padding(12)
            .frame(width: W, height: H)
        }
        .frame(width: W, height: H)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    // MARK: - The drawing
    private func drawScene(_ ctx: GraphicsContext, sky: SkyState, rain: Double, wind: Double, tideFrac: Double) {
        let isNight = sky.sun == nil
        let isDawnDusk = sky.sun == "rise" || sky.sun == "set" || sky.sun == "low"
        let cloudCover = rain > 15 ? min(1, rain / 65) : 0.12
        let isRaining = rain > 25
        let rainHeavy = rain > 55
        let windy = wind > 22

        let waterBaseY: CGFloat = 318, waterRange: CGFloat = 34
        let waterY = waterBaseY - CGFloat((tideFrac - 0.5) * 2) * waterRange

        // Sky
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: sky.top, location: 0),
                    .init(color: sky.mid, location: 0.55),
                    .init(color: sky.bottom, location: 1)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: H)))

        // Stars
        if sky.stars > 0.05 {
            for s in STARS {
                ctx.fill(circle(CGPoint(x: s.x, y: s.y), s.r),
                         with: .color(.white.opacity(sky.stars * s.bright)))
            }
        }

        // Sun / moon
        if let sun = sky.sun {
            let sunY: CGFloat = sun == "rise" ? 276 : sun == "low" ? 150 : sun == "set" ? 276 : 66
            let sunX: CGFloat = sun == "rise" ? 54 : sun == "set" ? 286 : 170
            let sunColor: Color = sun == "high" ? .hx("FFEFB0") : .hx("FFB876")
            let glowR: CGFloat = sun == "high" ? 70 : 95
            ctx.fill(circle(CGPoint(x: sunX, y: sunY), glowR),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: sunColor.opacity(0.9), location: 0),
                        .init(color: sunColor.opacity(0.35), location: 0.45),
                        .init(color: sunColor.opacity(0), location: 1)]),
                        center: CGPoint(x: sunX, y: sunY), startRadius: 0, endRadius: glowR))
            // A bright core fading to the sun's own colour reads rounder and hotter
            // than a flat disk.
            let sunR: CGFloat = sun == "high" ? 24 : 30
            ctx.fill(circle(CGPoint(x: sunX, y: sunY), sunR),
                     with: .radialGradient(Gradient(colors: [.white, sunColor, sunColor]),
                        center: CGPoint(x: sunX - sunR * 0.25, y: sunY - sunR * 0.25),
                        startRadius: 0, endRadius: sunR * 1.15))
        }
        if isNight {
            ctx.fill(circle(CGPoint(x: 278, y: 54), 22),
                     with: .radialGradient(Gradient(colors: [.hx("FFB876").opacity(0.5), .clear]),
                        center: CGPoint(x: 278, y: 54), startRadius: 0, endRadius: 22))
            ctx.fill(circle(CGPoint(x: 278, y: 54), 16), with: .color(.hx("EDEFF4")))
            for (cx, cy, r) in [(273.0, 49.0, 2.6), (282.0, 58.0, 1.8), (280.0, 48.0, 1.3)] {
                ctx.fill(circle(CGPoint(x: cx, y: cy), r), with: .color(.hx("D7DAE2").opacity(0.55)))
            }
        }

        // Clouds — drawn into a softly blurred layer so their edges read as
        // volumetric vapour rather than stacked hard ellipses. Tinted by the sky so
        // dawn/dusk clouds catch warm light and night clouds go slate.
        let cloudLight: Color = isNight ? .hx("39465F") : isDawnDusk ? .hx("F3D2C0") : .white
        let cloudCount = Int((2 + cloudCover * 4).rounded())
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.2))
            for i in 0..<max(0, cloudCount) {
                let cx = 36 + Double(i) * 74 + Double(i % 3) * 14
                let cy = 42 + Double((i * 31) % 36)
                let sc = 0.75 + Double((i * 17) % 6) / 10
                let op = 0.5 + cloudCover * 0.45
                func lobe(_ ex: Double, _ ey: Double, _ rx: Double, _ ry: Double, _ color: Color, _ o: Double) {
                    layer.fill(ellipse(CGPoint(x: cx + ex * sc, y: cy + ey * sc), rx * sc, ry * sc),
                               with: .color(color.opacity(o)))
                }
                lobe(2, 6, 32, 14, .hx(isNight ? "060E1C" : "5A6B85"), op * 0.22) // underside shadow
                lobe(0, 0, 28, 13, cloudLight, op)
                lobe(20, -5, 19, 11, cloudLight, op)
                lobe(-18, 1, 17, 10, cloudLight, op)
                lobe(6, -9, 14, 9, cloudLight, op)
            }
        }

        // Seagulls
        if !isRaining && !isNight {
            for (gx, gy) in [(60.0, 90.0), (95.0, 78.0), (250.0, 100.0)] {
                var p = Path()
                p.move(to: CGPoint(x: gx - 7, y: gy))
                p.addQuadCurve(to: CGPoint(x: gx, y: gy), control: CGPoint(x: gx - 3, y: gy - 5))
                p.addQuadCurve(to: CGPoint(x: gx + 7, y: gy), control: CGPoint(x: gx + 3, y: gy - 5))
                ctx.stroke(p, with: .color(.hx(isDawnDusk ? "3A2A38" : "3A3A44").opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }

        // Rain
        if isRaining {
            let n = rainHeavy ? 34 : 16
            for i in 0..<n {
                let rx = Double((i * 23 + 11) % Int(W))
                let ry = Double((i * 37) % 210 + 70)
                let len = rainHeavy ? 18.0 : 11.0
                let slant = windy ? 11.0 : 4.0
                let near = i % 2 == 0
                var p = Path()
                p.move(to: CGPoint(x: rx, y: ry))
                p.addLine(to: CGPoint(x: rx - slant, y: ry + len))
                ctx.stroke(p, with: .color(.hx("BFE0F5").opacity(near ? 0.6 : 0.35)),
                           style: StrokeStyle(lineWidth: near ? 1.6 : 1, lineCap: .round))
            }
        }

        // Atmospheric haze band at the horizon — the biggest single cue that
        // there's depth and air between here and the sea.
        let hazeColor: Color = isNight ? .hx("1A2C44") : isDawnDusk ? .hx("F0B889") : .hx("CFE6F0")
        ctx.fill(Path(CGRect(x: 0, y: waterY - 46, width: W, height: 52)),
                 with: .linearGradient(Gradient(colors: [hazeColor.opacity(0), hazeColor.opacity(0.28)]),
                                       startPoint: CGPoint(x: 0, y: waterY - 46), endPoint: CGPoint(x: 0, y: waterY + 6)))

        // A distant headland silhouette on the right, behind the sea, for depth.
        let landColor: Color = isNight ? .hx("0A1526") : isDawnDusk ? .hx("2C2030") : .hx("6E8A6A")
        var head = Path()
        head.move(to: CGPoint(x: W * 0.62, y: waterY + 1))
        head.addQuadCurve(to: CGPoint(x: W + 8, y: waterY - 14), control: CGPoint(x: W * 0.85, y: waterY - 22))
        head.addLine(to: CGPoint(x: W + 8, y: waterY + 6)); head.addLine(to: CGPoint(x: W * 0.62, y: waterY + 6)); head.closeSubpath()
        ctx.fill(head, with: .color(landColor.opacity(0.5)))

        // Water — two parallax bands
        let farTopColor: Color = isNight ? .hx("0E2036") : Comfort.mix(sky.bottom, .hx("0B3A55"), 0.55)
        let farBotColor: Color = isNight ? .hx("0A1826") : Comfort.mix(sky.bottom, .hx("08283D"), 0.7)
        var far = Path()
        far.move(to: CGPoint(x: 0, y: waterY))
        far.addCurve(to: CGPoint(x: W * 0.5, y: waterY), control1: CGPoint(x: W * 0.2, y: waterY - 4), control2: CGPoint(x: W * 0.35, y: waterY + 3))
        far.addCurve(to: CGPoint(x: W, y: waterY), control1: CGPoint(x: W * 0.65, y: waterY - 3), control2: CGPoint(x: W * 0.8, y: waterY + 4))
        far.addLine(to: CGPoint(x: W, y: waterY + 40)); far.addLine(to: CGPoint(x: 0, y: waterY + 40)); far.closeSubpath()
        ctx.fill(far, with: .linearGradient(Gradient(colors: [farTopColor, farBotColor]),
                                            startPoint: CGPoint(x: 0, y: waterY), endPoint: CGPoint(x: 0, y: waterY + 40)))

        let nearTop = waterY + 34
        var near = Path()
        near.move(to: CGPoint(x: 0, y: nearTop))
        near.addCurve(to: CGPoint(x: W * 0.5, y: nearTop), control1: CGPoint(x: W * 0.22, y: nearTop - 4), control2: CGPoint(x: W * 0.4, y: nearTop + 4))
        near.addCurve(to: CGPoint(x: W, y: nearTop), control1: CGPoint(x: W * 0.7, y: nearTop - 5), control2: CGPoint(x: W * 0.85, y: nearTop + 4))
        near.addLine(to: CGPoint(x: W, y: H)); near.addLine(to: CGPoint(x: 0, y: H)); near.closeSubpath()
        ctx.fill(near, with: .color(isNight ? .hx("0B1C2E") : Comfort.mix(sky.bottom, .hx("0A3049"), 0.5)))

        // Sun / moon reflection: a shimmering light column on the water beneath
        // whatever's in the sky. Broken into staggered slivers so it reads as
        // rippling light, not a solid bar.
        let lightX: CGFloat = sky.sun == "rise" ? 54 : sky.sun == "set" ? 286 : isNight ? 278 : 170
        let lightColor: Color = isNight ? .hx("D7DAE2") : sky.sun == "high" ? .hx("FFF3CF") : .hx("FFCE9A")
        if !isRaining {
            for i in 0..<7 {
                let ry = waterY + 4 + CGFloat(i) * 7
                let halfW = 10.0 + Double(i) * 5.5
                let jitter = Double((i * 13) % 5) - 2
                ctx.fill(ellipse(CGPoint(x: lightX + jitter, y: ry), halfW, 1.6),
                         with: .color(lightColor.opacity((isNight ? 0.28 : 0.5) * (1 - Double(i) / 8))))
            }
        }

        // Wave crest highlights
        for i in 0..<3 {
            let y = waterY + 8 + CGFloat(i) * 14
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addQuadCurve(to: CGPoint(x: W * 0.5, y: y), control: CGPoint(x: W * 0.25, y: y - 4))
            p.addQuadCurve(to: CGPoint(x: W, y: y), control: CGPoint(x: W * 0.75, y: y + 4))
            ctx.stroke(p, with: .color(.hx(isNight ? "3A5A78" : "EAF6FB").opacity(0.3 - Double(i) * 0.08)),
                       style: StrokeStyle(lineWidth: 1.1))
        }
        if windy {
            for i in 0..<8 {
                let cx = Double((i * 41 + 20) % Int(W))
                let cy = Double(waterY) + 10 + Double((i * 17) % 50)
                ctx.fill(ellipse(CGPoint(x: cx, y: cy), 4, 1.4), with: .color(.white.opacity(0.35)))
            }
        }

        // Beach
        let sandTop: Color = isNight ? .hx("2A2216") : isDawnDusk ? .hx("6B4A3E") : .hx("E8CE9C")
        let sandLow: Color = isNight ? .hx("1A1610") : isDawnDusk ? .hx("4A3128") : .hx("D4AF77")
        // Beach crescent sits a little lower so a strip of sea shows at the
        // horizon behind the house; the centre still rises to give it ground.
        var sand = Path()
        sand.move(to: CGPoint(x: 0, y: waterY + 26))
        sand.addQuadCurve(to: CGPoint(x: W, y: waterY + 26), control: CGPoint(x: W * 0.5, y: waterY - 4))
        sand.addLine(to: CGPoint(x: W, y: H)); sand.addLine(to: CGPoint(x: 0, y: H)); sand.closeSubpath()
        ctx.fill(sand, with: .linearGradient(Gradient(colors: [sandTop, sandLow]),
                                             startPoint: CGPoint(x: 0, y: waterY), endPoint: CGPoint(x: 0, y: H)))

        // Wet-sand sheen where the water meets the beach — a thin reflective band
        // that sells the waterline far more than a hard edge does.
        var sheen = Path()
        sheen.move(to: CGPoint(x: 0, y: waterY + 26))
        sheen.addQuadCurve(to: CGPoint(x: W, y: waterY + 26), control: CGPoint(x: W * 0.5, y: waterY - 4))
        ctx.stroke(sheen, with: .color((isNight ? Color.hx("5A7488") : .white).opacity(0.22)),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round))

        drawPalm(ctx, oy: waterY - 64, isNight: isNight, isDawnDusk: isDawnDusk, windy: windy)
        drawHouse(ctx, waterY: waterY, sky: sky, isNight: isNight, isDawnDusk: isDawnDusk)
        drawDuneGrass(ctx, isNight: isNight, isDawnDusk: isDawnDusk, windy: windy)

        // Vignette
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(.black.opacity(0.06)))
    }

    // MARK: - Palm
    private func drawPalm(_ ctx: GraphicsContext, oy: CGFloat, isNight: Bool, isDawnDusk: Bool, windy: Bool) {
        let ox: CGFloat = 48
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x, y: oy + y) }
        var trunk = Path()
        trunk.move(to: P(6, 86))
        trunk.addQuadCurve(to: P(windy ? 2 : 4, 0), control: P(windy ? -6 : -2, 50))
        ctx.stroke(trunk, with: .color(.hx(isNight ? "1A130E" : isDawnDusk ? "2E1D16" : "5C4230")),
                   style: StrokeStyle(lineWidth: 7, lineCap: .round))
        let frondColor = Color.hx(isNight ? "141C10" : isDawnDusk ? "2A2418" : "3E6B3E")
        for dir in [-1.0, -0.5, 0.0, 0.6, 1.1] {
            let bend = windy ? 26.0 : 14.0
            let baseX = windy ? 2.0 : 4.0
            let tipX = baseX + dir * 30 + (windy ? dir * 14 : 0)
            let tipY = -14 - abs(dir) * 6
            let midX = baseX + dir * bend * 0.6
            let midY = -10 - abs(dir) * 10
            var f = Path()
            f.move(to: P(baseX, 0))
            f.addQuadCurve(to: P(tipX, tipY), control: P(midX, midY))
            ctx.stroke(f, with: .color(frondColor.opacity(0.92)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }

    // MARK: - House
    private func drawHouse(_ ctx: GraphicsContext, waterY: CGFloat, sky: SkyState, isNight: Bool, isDawnDusk: Bool) {
        let ox = W / 2 - 62, oy = waterY - 134
        func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: ox + x, y: oy + y, width: w, height: h) }
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x, y: oy + y) }

        let wall: Color = isNight ? .hx("151E30") : isDawnDusk ? .hx("3B2A38") : .hx("EDE3D3")
        let wallSh: Color = isNight ? .hx("0D1420") : isDawnDusk ? .hx("2A1D28") : .hx("D8C9AE")
        let roof: Color = isNight ? .hx("0A0F1A") : isDawnDusk ? .hx("2E1E2A") : .hx("9B4B3F")
        let roofSh: Color = isNight ? .hx("050810") : isDawnDusk ? .hx("20141C") : .hx("7A362D")
        let trim: Color = isNight ? .hx("0A0F1A") : isDawnDusk ? .hx("241620") : .hx("FDFBF5")
        let windowLit = isNight || sky.sun == "set" || sky.sun == "rise"
        let windowColor: Color = windowLit ? .hx("FFC96B") : (isNight ? .hx("1A2438") : .hx("6FA8C9"))
        let doorColor: Color = isNight ? .hx("080C14") : isDawnDusk ? .hx("1C1220") : .hx("7A4A2E")

        // Ground shadow
        ctx.fill(ellipse(P(62, 132), 76, 8), with: .color(.black.opacity(0.18)))
        // Stilts
        for x in [14.0, 104.0, 58.0] { ctx.fill(Path(R(x, 94, 6, 34)), with: .color(wallSh)) }
        // Body
        ctx.fill(Path(R(4, 46, 120, 52)), with: .color(wall))
        ctx.fill(Path(R(94, 46, 30, 52)), with: .color(wallSh.opacity(0.55)))
        // Roof
        var roofP = Path(); roofP.move(to: P(-10, 46)); roofP.addLine(to: P(64, 6)); roofP.addLine(to: P(138, 46)); roofP.closeSubpath()
        ctx.fill(roofP, with: .linearGradient(Gradient(colors: [roof, roofSh]),
                                              startPoint: P(-10, 6), endPoint: P(138, 46)))
        var roofShade = Path(); roofShade.move(to: P(64, 6)); roofShade.addLine(to: P(138, 46)); roofShade.addLine(to: P(128, 46)); roofShade.closeSubpath()
        ctx.fill(roofShade, with: .color(roofSh.opacity(0.5)))
        var ridge = Path(); ridge.move(to: P(-10, 46)); ridge.addLine(to: P(64, 6)); ridge.addLine(to: P(138, 46))
        ctx.stroke(ridge, with: .color(trim.opacity(0.7)), lineWidth: 2)
        // Chimney
        ctx.fill(Path(R(96, 14, 10, 24)), with: .color(wallSh))
        ctx.fill(Path(R(94, 12, 14, 5)), with: .color(trim.opacity(0.8)))
        // Porch
        var porch = Path(); porch.move(to: P(-8, 74)); porch.addLine(to: P(18, 58)); porch.addLine(to: P(18, 74)); porch.closeSubpath()
        ctx.fill(porch, with: .color(roofSh.opacity(0.85)))
        ctx.fill(Path(R(-6, 74, 4, 24)), with: .color(trim.opacity(0.7)))
        ctx.fill(Path(R(12, 74, 4, 24)), with: .color(trim.opacity(0.7)))
        // Windows
        for wx in [20.0, 82.0] {
            ctx.fill(Path(roundedRect: R(wx, 58, 20, 20), cornerSize: CGSize(width: 1, height: 1)),
                     with: .color(windowColor.opacity(windowLit ? 0.95 : 0.85)))
            var m1 = Path(); m1.move(to: P(wx + 10, 58)); m1.addLine(to: P(wx + 10, 78))
            var m2 = Path(); m2.move(to: P(wx, 68)); m2.addLine(to: P(wx + 20, 68))
            ctx.stroke(m1, with: .color(trim.opacity(0.8)), lineWidth: 1.4)
            ctx.stroke(m2, with: .color(trim.opacity(0.8)), lineWidth: 1.4)
            ctx.stroke(Path(roundedRect: R(wx, 58, 20, 20), cornerSize: CGSize(width: 1, height: 1)),
                       with: .color(trim.opacity(0.9)), lineWidth: 1.6)
            if windowLit {
                var glow = ctx; glow.addFilter(.blur(radius: 3))
                glow.fill(circle(P(wx + 10, 68), 16), with: .color(windowColor.opacity(0.25)))
            }
        }
        // Door
        ctx.fill(Path(R(54, 64, 18, 34)), with: .color(doorColor))
        ctx.fill(Path(R(58, 68, 10, 10)), with: .color(windowColor.opacity(windowLit ? 0.7 : 0.4)))
        ctx.fill(circle(P(68, 82), 1.4), with: .color(trim.opacity(0.9)))
        // Steps
        ctx.fill(Path(R(50, 98, 26, 5)), with: .color(wallSh.opacity(0.8)))
        ctx.fill(Path(R(52, 103, 22, 5)), with: .color(wallSh.opacity(0.7)))
        // Deck rail
        for i in 0..<9 {
            var p = Path(); p.move(to: P(8 + Double(i) * 13, 98)); p.addLine(to: P(8 + Double(i) * 13, 108))
            ctx.stroke(p, with: .color(trim.opacity(0.55)), lineWidth: 2)
        }
        var rail = Path(); rail.move(to: P(4, 98)); rail.addLine(to: P(124, 98))
        ctx.stroke(rail, with: .color(trim.opacity(0.6)), lineWidth: 2)
    }

    // MARK: - Dune grass
    private func drawDuneGrass(_ ctx: GraphicsContext, isNight: Bool, isDawnDusk: Bool, windy: Bool) {
        for i in 0..<11 {
            let gx = 14 + Double(i) * 32
            let bend = windy ? 22.0 : 7.0
            let dir = i % 2 == 0 ? 1.0 : -1.0
            var p = Path()
            p.move(to: CGPoint(x: gx, y: Double(H) - 8))
            p.addQuadCurve(to: CGPoint(x: gx + bend * dir, y: Double(H) - 62),
                           control: CGPoint(x: gx + bend * dir * 0.6, y: Double(H) - 38))
            ctx.stroke(p, with: .color(.hx(isNight ? "0E1A10" : isDawnDusk ? "2A2418" : "3F6B3F").opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }

    // MARK: - Metric cards (the live data, on the image)
    //
    // Every comfort metric as a small glass card floating over the scene, tinted
    // by the same comfort ramp as the dial. This is what "reflect the metrics on
    // the image" means: the numbers live on the picture, not only in a legend.
    private var metricCards: some View {
        let comfort = ComfortData(consensus: consensus)
        return HStack(spacing: 6) {
            ForEach(comfort.rings) { r in
                let color = Comfort.comfortColor(r.score)
                VStack(spacing: 1) {
                    Text(r.metric.emoji).font(.system(size: 15))
                    Text(r.metric.format(r.value))
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.55), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if r.hasFlag {
                        Circle().fill(r.isMajor ? Sky.red : Sky.amber)
                            .frame(width: 5, height: 5).padding(4)
                    }
                }
            }
        }
    }

    // MARK: - Overlays / legend
    private func glassPill(alignment: HorizontalAlignment, title: String, subtitle: String) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Text(subtitle).font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var legend: some View {
        let sky = skyAt(hour)
        let rain = consensus.rainProbability
        let cloudCover = rain > 15 ? min(1, rain / 65) : 0.12
        let items: [(String, String, String)] = [
            ("🌅", "Sky colour", "Time of day, live"),
            ("🌊", "Water line", tide.map { String(format: "%.1fm tide height", $0.now) }
                                 ?? "No tide data — drawn at mid level"),
            ("☁️", "Cloud cover", "\(Int((cloudCover * 100).rounded()))% from rain chance"),
            ("🌧", "Rain", rain > 25 ? "Falling · \(Int(rain.rounded()))% chance" : "Dry right now"),
            ("🌴", "Palm sway", "\(Units.windString(consensus.windSpeed, withUnit: true)) wind"),
            ("✨", "Stars", sky.sun == nil ? "Visible now" : "Daytime — hidden"),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("🏖 WHAT THE SCENE SHOWS")
                .font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(items, id: \.1) { item in
                    HStack(spacing: 8) {
                        Text(item.0).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.1).font(.system(size: 11, weight: .semibold)).foregroundColor(Sky.text)
                            Text(item.2).font(.system(size: 10)).foregroundColor(Sky.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Redraws through the day. Sky blends smoothly between dawn, day, dusk and night. Water rises and falls with real tide predictions when they are available, and sits at mid level when they are not; rain and cloud density map to forecast probability.")
                .font(.system(size: 10)).foregroundColor(Sky.muted).lineSpacing(3)
        }
    }

    // MARK: - Small helpers
    private func circle(_ c: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    private func ellipse(_ c: CGPoint, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }
    private func clockLabel(_ h: Double) -> String {
        let hh = Int(h), mm = Int((h - Double(hh)) * 60)
        let am = hh < 12
        let disp = hh == 0 ? 12 : hh <= 12 ? hh : hh - 12
        return String(format: "%d:%02d %@", disp, mm, am ? "AM" : "PM")
    }
    private func phaseLabel(_ s: SkyState) -> String {
        if s.sun == nil { return "Night" }
        switch s.sun {
        case "rise": return "Sunrise"
        case "set": return "Sunset"
        case "low": return "Golden hour"
        default: return "Daytime"
        }
    }
}
