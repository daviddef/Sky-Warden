// SkyWarden — Comfort Dial
// Five concentric semicircular arcs (top half only) mapping each measurement to
// a left(good)…right(uncomfortable) comfort scale. Ported from the prototype's
// Dial/RingLayer. Drawn with Canvas (immediate mode) per the handover's note.
//
// CRITICAL LAYOUT: the ring box and the centre readout are two SEPARATE stacked
// blocks in normal flow — NOT an overlay with hand-tuned offsets — so the readout
// can never overlap the rings or the content below it.

import SwiftUI

struct ComfortDialView: View {
    let data: ComfortData
    @Binding var selected: ComfortMetric?

    // Geometry (from the prototype)
    private let W: CGFloat = 340
    private let ringH: CGFloat = 190
    private let readoutH: CGFloat = 80
    private let cx: CGFloat = 170
    private let cy: CGFloat = 176
    private let baseR: CGFloat = 150
    private let gap: CGFloat = 23

    private var center: CGPoint { CGPoint(x: cx, y: cy) }
    private func radius(_ i: Int) -> CGFloat { baseR - CGFloat(i) * gap }

    var body: some View {
        VStack(spacing: 0) {
            ringBox
            readout
                .frame(width: W, height: readoutH, alignment: .top)
                .padding(.top, -58)   // pull the readout up into the dial's open lower centre
        }
        .frame(width: W)
    }

    // MARK: - Rings
    private var ringBox: some View {
        Canvas { ctx, _ in
            for (i, metric) in ComfortMetric.allCases.enumerated() {
                guard let r = data.ring(metric) else { continue }
                drawRing(ctx, reading: r, radius: radius(i),
                         isSelected: selected == metric)
            }
            drawGuides(ctx)
        }
        .frame(width: W, height: ringH)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let hit = ringHit(at: value.location) {
                    withAnimation(.spring(response: 0.3)) {
                        selected = (selected == hit) ? nil : hit
                    }
                }
            }
        )
    }

    private func drawRing(_ ctx: GraphicsContext, reading r: RingReading,
                          radius rad: CGFloat, isSelected: Bool) {
        let metric = r.metric
        let score = r.score
        let angle = Comfort.angle(score)
        let color = Comfort.comfortColor(score)   // same ramp as the radial dial
        let lw: CGFloat = isSelected ? 12 : 9

        // Track + faint "good" half
        ctx.stroke(arc(-90, 90, rad), with: .color(Sky.surface),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round))
        ctx.stroke(arc(-90, 0, rad), with: .color(Comfort.good.opacity(0.06)),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // Today's forecast min/max: faint band + two ticks
        if let mm = r.minMax {
            let minA = Comfort.angle(metric.score(mm.0))
            let maxA = Comfort.angle(metric.score(mm.1))
            ctx.stroke(arc(min(minA, maxA), max(minA, maxA), rad),
                       with: .color(Sky.muted.opacity(0.09)),
                       style: StrokeStyle(lineWidth: lw + 2, lineCap: .round))
            for a in [minA, maxA] {
                ctx.stroke(tick(a, rad, lw), with: .color(Sky.muted.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.5))
            }
        }

        // Disagreement bracket (dashed) between furthest-apart source readings
        if r.hasFlag {
            let scores = r.perSource.map { metric.score($0.value) }
            if let hi = scores.max(), let lo = scores.min() {
                let d = arc(Comfort.angle(hi), Comfort.angle(lo), rad)
                ctx.stroke(d, with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.55)),
                           style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
            }
        }

        // Filled needle sweep from centre (12 o'clock) to the score angle
        if abs(angle) > 1 {
            ctx.stroke(arc(0, angle, rad), with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }

        // Per-source ticks. Neutral, not nine hues: here only the spread matters,
        // and nine source colours failed colour-blind separation anyway.
        for s in r.perSource {
            ctx.stroke(tick(Comfort.angle(metric.score(s.value)), rad, lw),
                       with: .color(Sky.muted.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
        }

        // Needle tip (+ flag halo)
        let tip = polar(angle, rad)
        let tipR: CGFloat = isSelected ? 8 : 6
        ctx.stroke(Path(ellipseIn: rect(tip, tipR)), with: .color(Sky.navy), lineWidth: 1.5)
        ctx.fill(dot(tip, tipR), with: .color(color))
        ctx.stroke(Path(ellipseIn: rect(tip, tipR)), with: .color(Sky.navy), lineWidth: 1.5)
        if r.hasFlag {
            ctx.stroke(Path(ellipseIn: rect(tip, isSelected ? 11 : 9)),
                       with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.5)), lineWidth: 1.5)
        }

        // Icon badge on the ring track at 12 o'clock
        let ip = polar(0, rad)
        let badgeR: CGFloat = isSelected ? 13 : 11
        ctx.fill(dot(ip, badgeR), with: .color(Sky.navy))
        ctx.stroke(Path(ellipseIn: rect(ip, badgeR)),
                   with: .color(isSelected ? color : Sky.surface),
                   lineWidth: isSelected ? 2 : 1.5)
        ctx.draw(Text(metric.emoji).font(.system(size: isSelected ? 15 : 13)), at: ip)
    }

    private func drawGuides(_ ctx: GraphicsContext) {
        var line = Path()
        line.move(to: CGPoint(x: cx, y: cy - baseR - 14))
        line.addLine(to: CGPoint(x: cx, y: cy + 8))
        ctx.stroke(line, with: .color(Sky.white.opacity(0.2)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

        // Anchored to the canvas edges, not outward from the rings — the latter
        // pushed both labels off the sides and truncated their arrows.
        ctx.draw(Text("◀ good").font(.system(size: 9)).foregroundColor(Comfort.good.opacity(0.6)),
                 at: CGPoint(x: 2, y: cy + 4), anchor: .leading)
        ctx.draw(Text("poor ▶").font(.system(size: 9)).foregroundColor(Comfort.poor.opacity(0.6)),
                 at: CGPoint(x: W - 2, y: cy + 4), anchor: .trailing)
    }

    // MARK: - Centre readout (separate flow block)
    @ViewBuilder
    private var readout: some View {
        if let metric = selected, let r = data.ring(metric) {
            let color = Comfort.comfortColor(r.score)
            VStack(spacing: 1) {
                Text(metric.emoji).font(.system(size: 24))
                Text(metric.format(r.value))
                    .font(.system(size: 36, weight: .ultraLight, design: .rounded))
                    .foregroundColor(color)
                Text(metric.comfortLabel(r.value))
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(color)
                if let mm = r.minMax {
                    Text("\(metric.format(mm.0))–\(metric.format(mm.1))")
                        .font(.system(size: 10)).foregroundColor(Sky.muted)
                }
            }
        } else {
            let s = Comfort.overallScore(data)
            VStack(spacing: 2) {
                Text("COMFORT")
                    .font(.system(size: 10)).foregroundColor(Sky.muted)
                    .kerning(0.7)
                Text(Comfort.overallLabel(s))
                    .font(.system(size: 40, weight: .ultraLight, design: .rounded))
                    .foregroundColor(Comfort.overallColor(s))
            }
        }
    }

    // MARK: - Geometry helpers
    private func polar(_ deg: Double, _ r: CGFloat) -> CGPoint {
        let rad = (deg - 90) * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(cos(rad)),
                       y: center.y + r * CGFloat(sin(rad)))
    }
    /// Sampled arc between two dial angles (avoids addArc winding pitfalls).
    private func arc(_ a1: Double, _ a2: Double, _ r: CGFloat) -> Path {
        var p = Path()
        let steps = max(2, Int(abs(a2 - a1) / 1.5))
        for i in 0...steps {
            let a = a1 + (a2 - a1) * Double(i) / Double(steps)
            let pt = polar(a, r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
    private func tick(_ a: Double, _ r: CGFloat, _ lw: CGFloat) -> Path {
        var p = Path()
        p.move(to: polar(a, r - lw / 2 - 2))
        p.addLine(to: polar(a, r + lw / 2 + 2))
        return p
    }
    private func rect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }
    private func dot(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: rect(c, r)) }

    /// Nearest ring to a tap in the upper half of the dial.
    private func ringHit(at p: CGPoint) -> ComfortMetric? {
        guard p.y <= cy + 12 else { return nil }
        let dist = hypot(p.x - cx, p.y - cy)
        var best: (ComfortMetric, CGFloat)?
        for (i, metric) in ComfortMetric.allCases.enumerated() {
            let d = abs(dist - radius(i))
            if d < (gap / 2 + 6), best == nil || d < best!.1 { best = (metric, d) }
        }
        return best?.0
    }
}
