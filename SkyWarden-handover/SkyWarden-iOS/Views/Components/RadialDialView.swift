// Sky Warden — Radial Comfort Dial
//
// Reads as one picture: how good is today, and do the sources agree.
//
// What it encodes, and where each thing went:
//   position  the reading. 12 o'clock is borderline; anticlockwise is
//             comfortable, clockwise is not. Same mapping as the arc dial.
//   hue       comfort, and ONLY comfort (Comfort.comfortColor). Not the metric.
//   the orb   the verdict — the app icon's circle, tinted on the same ramp.
//   the rim   confidence. The gap in the dashes is the doubt.
//   ticks     where each source actually sits. A wide scatter IS disagreement.
//
// Decluttered deliberately:
//   · the metric's icon rides its own needle tip, so the five icons sit at five
//     different angles instead of stacking into a totem pole at 12 o'clock
//   · no value labels on the canvas — the pills below already carry all five,
//     and printing them twice was most of the noise. Tap a ring and the orb
//     bursts open with that metric's number.
//   · source ticks are neutral, not nine hues. Which source is which belongs in
//     the Sources tab; here only the spread matters.

import SwiftUI

struct RadialDialView: View {
    let data: ComfortData
    let temperature: Double        // consensus temp, shown in the orb
    let confidence: Double
    @Binding var selected: ComfortMetric?

    @AppStorage(DisplayKey.showRange)   private var showRange = true
    @AppStorage(DisplayKey.arcFillMode) private var fillModeRaw = ArcFillMode.comfort.rawValue
    private var fillMode: ArcFillMode { ArcFillMode(rawValue: fillModeRaw) ?? .comfort }

    private func shownRange(_ r: RingReading) -> (Double, Double)? {
        guard showRange, let mm = r.minMax,
              r.metric.format(mm.0) != r.metric.format(mm.1) else { return nil }
        return mm
    }

    // Both dials share the fill-mode toggle: comfort → position by comfort score,
    // value/both → position by the raw reading on its own 0→max scale.
    private func comfortFraction(_ score: Double) -> Double { (1 - max(-1, min(1, score))) / 2 }
    private func fraction(_ m: ComfortMetric, value: Double) -> Double {
        switch fillMode {
        case .comfort:      comfortFraction(m.score(value))
        case .value, .both: m.normalized(value)
        }
    }

    private let W: CGFloat = 320
    private let baseR: CGFloat = 140
    // Tip icons ride the rings, so the gap must exceed a tip's diameter —
    // otherwise metrics with equal scores (all the good ones sit at exactly +1)
    // land on the same bearing and their icons collide.
    private let gap: CGFloat = 20
    private var center: CGPoint { CGPoint(x: W / 2, y: W / 2) }
    private func radius(_ i: Int) -> CGFloat { baseR - CGFloat(i) * gap }

    private var orbR: CGFloat { radius(4) - 17 }

    /// The arc dial spends 90° on a full-scale reading. A ring has the whole
    /// circle, so spread it wider — the same reading, more legible.
    private let spread: Double = 1.55
    /// Fraction 0 (good/low) → far anticlockwise; 0.5 → top; 1 (poor/high) → far
    /// clockwise. Mirrors the arc's left→right, just wrapped around more of the ring.
    private func ang(_ fraction: Double) -> Double { (fraction - 0.5) * 2 * 90 * spread }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                drawBorderlineMark(ctx)
                for (i, metric) in ComfortMetric.allCases.enumerated() {
                    guard let r = data.ring(metric) else { continue }
                    drawRing(ctx, reading: r, radius: radius(i), isSelected: selected == metric)
                }
                drawOrb(ctx)
                drawConfidenceRim(ctx)
            }
            .frame(width: W, height: W)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                withAnimation(.spring(response: 0.3)) { selected = hit(at: value.location) }
            })

            readout
                .frame(width: orbR * 1.75)
                .allowsHitTesting(false)
        }
        .frame(width: W, height: W)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverSummary)
    }

    // MARK: - Rings

    private func drawRing(_ ctx: GraphicsContext, reading r: RingReading,
                          radius rad: CGFloat, isSelected: Bool) {
        let metric = r.metric
        let startAngle = ang(0)                      // the good / low end
        let end = ang(fraction(metric, value: r.value))
        let color = Comfort.comfortColor(r.score)
        let lw: CGFloat = isSelected ? 9 : 6.5

        // Track. Recessive: it's a scale, not data.
        ctx.stroke(circle(rad), with: .color(Sky.surface.opacity(0.55)),
                   style: StrokeStyle(lineWidth: lw))

        // Today's forecast low→high: a faint band for the span, plus a bright
        // core and end ticks. Numbers appear in the centre when the ring is tapped.
        if let mm = shownRange(r) {
            let a = ang(fraction(metric, value: mm.0)), b = ang(fraction(metric, value: mm.1))
            ctx.stroke(arc(min(a, b), max(a, b), rad), with: .color(Sky.muted.opacity(0.13)),
                       style: StrokeStyle(lineWidth: lw + 4, lineCap: .round))
            ctx.stroke(arc(min(a, b), max(a, b), rad), with: .color(Sky.white.opacity(0.45)),
                       style: StrokeStyle(lineWidth: max(2, lw * 0.32), lineCap: .round))
            for e in [a, b] {
                ctx.stroke(tick(e, rad, lw + 3), with: .color(Sky.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5))
            }
        }

        // Where each source sits — neutral ticks; a wide scatter reads as spread.
        for s in r.perSource {
            ctx.stroke(tick(ang(fraction(metric, value: s.value)), rad, lw),
                       with: .color(Sky.muted.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
        }

        // .both: mark where comfort crosses, so magnitude and comfort read apart.
        if fillMode == .both {
            for t in comfortThresholds(metric) {
                ctx.stroke(tick(ang(metric.normalized(t)), rad, lw + 3),
                           with: .color(Sky.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5))
            }
        }

        // Disagreement: a dashed span across the sources' full width.
        if r.hasFlag {
            let fracs = r.perSource.map { fraction(metric, value: $0.value) }
            if let hi = fracs.max(), let lo = fracs.min() {
                ctx.stroke(arc(ang(lo), ang(hi), rad + lw / 2 + 4),
                           with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
        }

        // The reading: a sweep from the good/low end to the reading.
        if abs(end - startAngle) > 1.5 {
            ctx.stroke(arc(startAngle, end, rad), with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }

        // The needle tip IS the metric's icon. Five tips, five angles — no stack.
        let tip = polar(end, rad)
        let tipR: CGFloat = isSelected ? 11 : 9
        ctx.fill(dot(tip, tipR), with: .color(Sky.navy))
        ctx.stroke(Path(ellipseIn: rect(tip, tipR)), with: .color(color),
                   lineWidth: isSelected ? 2.5 : 1.8)
        ctx.draw(Text(metric.emoji).font(.system(size: isSelected ? 13 : 11)), at: tip)

        // A flagged ring gets a halo, so disagreement survives greyscale.
        if r.hasFlag {
            ctx.stroke(Path(ellipseIn: rect(tip, tipR + 3)),
                       with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.7)), lineWidth: 1.5)
        }
    }

    /// 12 o'clock is "borderline". Marking it makes every sweep's direction
    /// meaningful instead of decorative.
    private func drawBorderlineMark(_ ctx: GraphicsContext) {
        // In comfort mode, 12 o'clock is the borderline (score 0); mark it. In
        // value mode the top is just the mid-scale, so no mark there.
        if fillMode == .comfort {
            var line = Path()
            line.move(to: polar(0, orbR + 14))
            line.addLine(to: polar(0, baseR + 9))
            ctx.stroke(line, with: .color(Sky.white.opacity(0.13)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
        let (lo, hi) = fillMode == .comfort ? ("good", "poor") : ("low", "high")
        ctx.draw(Text(lo).font(.system(size: 8.5)).foregroundColor(Comfort.good.opacity(0.6)),
                 at: CGPoint(x: 2, y: center.y + baseR - 24), anchor: .leading)
        ctx.draw(Text(hi).font(.system(size: 8.5)).foregroundColor(Comfort.poor.opacity(0.6)),
                 at: CGPoint(x: W - 2, y: center.y + baseR - 24), anchor: .trailing)
    }

    /// Values in a metric's display range where its comfort score crosses zero.
    private func comfortThresholds(_ metric: ComfortMetric) -> [Double] {
        let r = metric.displayRange
        let steps = 180
        var out: [Double] = []
        var prev = metric.score(r.lowerBound)
        for i in 1...steps {
            let v = r.lowerBound + (r.upperBound - r.lowerBound) * Double(i) / Double(steps)
            let s = metric.score(v)
            if (prev < 0) != (s < 0) { out.append(v) }
            prev = s
        }
        return out
    }

    // MARK: - Verdict orb

    private func drawOrb(_ ctx: GraphicsContext) {
        let tint = Comfort.overallColor(Comfort.overallScore(data))
        ctx.fill(dot(center, orbR), with: .radialGradient(
            Gradient(colors: [tint.opacity(0.30), tint.opacity(0.07), Sky.navy]),
            center: center, startRadius: 0, endRadius: orbR))
        ctx.stroke(Path(ellipseIn: rect(center, orbR)), with: .color(tint.opacity(0.5)), lineWidth: 1.5)
    }

    /// A dashed rim whose filled fraction is the consensus confidence — the gap
    /// is literally the doubt. Dashes keep it from reading as another ring.
    private func drawConfidenceRim(_ ctx: GraphicsContext) {
        let rimR = orbR + 8
        let color = confidence >= 0.8 ? Comfort.good : confidence >= 0.5 ? Sky.amber : Comfort.poor
        ctx.stroke(circle(rimR), with: .color(Sky.surface.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 2.5, dash: [2, 4]))
        ctx.stroke(arc(0, 360 * max(0, min(1, confidence)), rimR),
                   with: .color(color.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 4]))
    }

    /// One line combining today's range and when it peaks — they usually share a
    /// number ("0–5" and "peaks 5 at 12pm"), so a single line reads far cleaner:
    /// "0–5 · peaks 12pm". Either half may be absent.
    static func detailLine(_ r: RingReading) -> String? {
        let range = r.minMax.map { "\(r.metric.format($0.0))–\(r.metric.format($0.1))" }
        let peak = r.peak.map { "peaks \(IntradayPeak.hourLabel($0.time))" }
        switch (range, peak) {
        case let (rr?, pp?): return "\(rr) · \(pp)"
        case let (rr?, nil): return rr
        case let (nil, pp?): return pp
        default:             return nil
        }
    }

    // MARK: - Centre readout ("burst open")

    @ViewBuilder
    private var readout: some View {
        if let metric = selected, let r = data.ring(metric) {
            let color = Comfort.comfortColor(r.score)
            VStack(spacing: 1) {
                Text(metric.label.uppercased())
                    .font(.system(size: 8)).foregroundColor(Sky.muted).kerning(0.6)
                Text(metric.format(r.value))
                    .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                    .foregroundColor(color)
                Text(metric.comfortLabel(r.value))
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                // Range and peak merged onto ONE legible line so the readout
                // stays inside the orb and clear of the dashed confidence rim.
                if let line = RadialDialView.detailLine(r) {
                    Text(line).font(.system(size: 9, weight: .medium)).foregroundColor(Sky.text.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                if r.hasFlag {
                    Text("\(r.isMajor ? "🚨" : "⚠️") \(metric.format(r.spread)) apart")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(r.isMajor ? Sky.red : Sky.amber)
                }
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            let s = Comfort.overallScore(data)
            VStack(spacing: 0) {
                Text(Units.tempString(temperature))
                    .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                    .foregroundColor(Sky.white)
                Text(Comfort.overallLabel(s))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Comfort.overallColor(s))
            }
        }
    }

    private var voiceOverSummary: String {
        let s = Comfort.overallScore(data)
        let flags = data.rings.filter(\.hasFlag).map(\.metric.label)
        let base = "Comfort \(Comfort.overallLabel(s)). \(Units.tempString(temperature)). "
            + "\(Int((confidence * 100).rounded())) percent confidence."
        return flags.isEmpty ? base : base + " Sources disagree on \(flags.joined(separator: ", "))."
    }

    // MARK: - Geometry

    /// 0° is 12 o'clock; positive is clockwise (the uncomfortable side).
    private func polar(_ deg: Double, _ r: CGFloat) -> CGPoint {
        let rad = (deg - 90) * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(cos(rad)), y: center.y + r * CGFloat(sin(rad)))
    }
    private func arc(_ a1: Double, _ a2: Double, _ r: CGFloat) -> Path {
        var p = Path()
        let steps = max(2, Int(abs(a2 - a1) / 1.5))
        for i in 0...steps {
            let pt = polar(a1 + (a2 - a1) * Double(i) / Double(steps), r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
    private func tick(_ a: Double, _ r: CGFloat, _ lw: CGFloat) -> Path {
        var p = Path()
        p.move(to: polar(a, r - lw / 2))
        p.addLine(to: polar(a, r + lw / 2))
        return p
    }
    private func circle(_ r: CGFloat) -> Path { Path(ellipseIn: rect(center, r)) }
    private func rect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }
    private func dot(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: rect(c, r)) }

    /// Nearest ring to a tap; a tap on the orb clears the selection. Icons ride
    /// the tips, so a tap near a tip should select that ring too.
    private func hit(at p: CGPoint) -> ComfortMetric? {
        for (i, metric) in ComfortMetric.allCases.enumerated() {
            guard let r = data.ring(metric) else { continue }
            let tip = polar(ang(fraction(metric, value: r.value)), radius(i))
            if hypot(p.x - tip.x, p.y - tip.y) <= 14 { return selected == metric ? nil : metric }
        }
        let dist = hypot(p.x - center.x, p.y - center.y)
        guard dist > orbR else { return nil }
        var best: (ComfortMetric, CGFloat)?
        for (i, metric) in ComfortMetric.allCases.enumerated() {
            let d = abs(dist - radius(i))
            if d < gap / 2 + 4, best == nil || d < best!.1 { best = (metric, d) }
        }
        guard let found = best?.0 else { return nil }
        return selected == found ? nil : found
    }
}
