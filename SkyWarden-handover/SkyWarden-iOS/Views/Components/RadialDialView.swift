// Sky Warden — Radial Comfort Dial
//
// The alternative to ComfortDialView's half-gauge. Same data, same comfort-angle
// mapping — good sweeps anticlockwise from 12 o'clock, uncomfortable sweeps
// clockwise — so the two dials can never disagree.
//
// Three ideas from the design brief land here:
//   · the verdict orb   the app icon's circle, tinted by how good today actually
//                       is (red bad → green good), stating the verdict in words
//   · the confidence rim a dashed ring around the orb; the gap is the doubt
//   · burst open        tapping a ring replaces the orb's verdict with that
//                       metric's real value, min/max and spread
//
// Drawn with Canvas (immediate mode), like the arc dial.

import SwiftUI

struct RadialDialView: View {
    let data: ComfortData
    let temperature: Double        // consensus temp, shown in the orb
    let confidence: Double
    @Binding var selected: ComfortMetric?

    private let W: CGFloat = 330
    private let baseR: CGFloat = 134
    private let gap: CGFloat = 17
    private var center: CGPoint { CGPoint(x: W / 2, y: W / 2) }
    private func radius(_ i: Int) -> CGFloat { baseR - CGFloat(i) * gap }

    private var orbR: CGFloat { radius(4) - 16 }

    /// The arc dial spends 90° on a full-scale reading. A ring has the whole
    /// circle, so spread it wider — the same score, more legible.
    private let spread: Double = 1.6
    private func angle(_ score: Double) -> Double { Comfort.angle(score) * spread }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
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
                .frame(width: orbR * 1.7)
                .allowsHitTesting(false)
        }
        .frame(width: W, height: W)
    }

    // MARK: - Rings

    private func drawRing(_ ctx: GraphicsContext, reading r: RingReading,
                          radius rad: CGFloat, isSelected: Bool) {
        let metric = r.metric
        let score = r.score
        let end = angle(score)
        let color = Comfort.needleColor(metric, score)
        let lw: CGFloat = isSelected ? 11 : 8

        // Full track, with the "good" (anticlockwise) side hinted.
        ctx.stroke(circle(rad), with: .color(Sky.surface.opacity(0.7)),
                   style: StrokeStyle(lineWidth: lw))
        ctx.stroke(arc(0, -angle(1), rad), with: .color(Sky.green.opacity(0.05)),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // Today's forecast min/max as a faint band.
        if let mm = r.minMax {
            let a = angle(metric.score(mm.0)), b = angle(metric.score(mm.1))
            ctx.stroke(arc(min(a, b), max(a, b), rad), with: .color(Sky.muted.opacity(0.10)),
                       style: StrokeStyle(lineWidth: lw + 3, lineCap: .round))
        }

        // The reading itself: a sweep out of 12 o'clock.
        if abs(end) > 1 {
            ctx.stroke(arc(0, end, rad), with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }

        // Where the sources actually sit. A wide scatter IS the disagreement.
        for s in r.perSource {
            let p = polar(angle(metric.score(s.value)), rad)
            ctx.fill(dot(p, 2.4), with: .color(Color(hex: s.source.colorHex).opacity(0.75)))
        }

        // Fracture: dashed span between the furthest-apart sources.
        if r.hasFlag {
            let scores = r.perSource.map { metric.score($0.value) }
            if let hi = scores.max(), let lo = scores.min() {
                ctx.stroke(arc(angle(hi), angle(lo), rad),
                           with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.7)),
                           style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
            }
        }

        // Needle tip + the value, parked just outside the ring.
        let tip = polar(end, rad)
        ctx.fill(dot(tip, isSelected ? 7 : 5.5), with: .color(color))
        ctx.stroke(Path(ellipseIn: rect(tip, isSelected ? 7 : 5.5)),
                   with: .color(Sky.navy), lineWidth: 1.5)
        if r.hasFlag {
            ctx.stroke(Path(ellipseIn: rect(tip, isSelected ? 10 : 8.5)),
                       with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.55)), lineWidth: 1.5)
        }

        // Parked outside the ring, but clamped into the canvas — a needle near
        // 3 o'clock used to push its value off the edge, silently truncating it.
        let raw = polar(end, rad + (isSelected ? 19 : 16))
        let label = CGPoint(x: min(max(raw.x, 26), W - 26), y: min(max(raw.y, 12), W - 12))
        chip(ctx, metric.format(r.value), at: label, color: color, size: isSelected ? 12 : 10)

        // Emoji badge at 12 o'clock, on the ring it belongs to.
        let ip = polar(0, rad)
        ctx.fill(dot(ip, isSelected ? 12 : 10), with: .color(Sky.navy))
        ctx.stroke(Path(ellipseIn: rect(ip, isSelected ? 12 : 10)),
                   with: .color(isSelected ? color : Sky.surface), lineWidth: isSelected ? 2 : 1.5)
        ctx.draw(Text(metric.emoji).font(.system(size: isSelected ? 14 : 12)), at: ip)
    }

    /// Rings sit only `gap` apart, so a value label offset outward lands squarely
    /// on top of the next ring — coloured text on a coloured arc, invisible. The
    /// backing chip is what makes all five readable at once.
    private func chip(_ ctx: GraphicsContext, _ text: String, at p: CGPoint,
                      color: Color, size: CGFloat) {
        let resolved = ctx.resolve(Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color))
        let m = resolved.measure(in: CGSize(width: 120, height: 40))
        let box = CGRect(x: p.x - m.width / 2 - 4, y: p.y - m.height / 2 - 1.5,
                         width: m.width + 8, height: m.height + 3)
        ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Sky.navy.opacity(0.82)))
        ctx.draw(resolved, at: p)
    }

    // MARK: - Verdict orb

    private func drawOrb(_ ctx: GraphicsContext) {
        let s = Comfort.overallScore(data)
        let tint = Comfort.overallColor(s)
        ctx.fill(dot(center, orbR), with: .radialGradient(
            Gradient(colors: [tint.opacity(0.34), tint.opacity(0.08), Sky.navy]),
            center: center, startRadius: 0, endRadius: orbR))
        ctx.stroke(Path(ellipseIn: rect(center, orbR)),
                   with: .color(tint.opacity(0.55)), lineWidth: 1.5)
    }

    /// A dashed rim whose filled fraction is the consensus confidence — the gap
    /// is literally the doubt. Dashes keep it from reading as another metric ring.
    private func drawConfidenceRim(_ ctx: GraphicsContext) {
        let rimR = orbR + 9
        let color = confidence >= 0.8 ? Sky.green : confidence >= 0.5 ? Sky.amber : Sky.red
        ctx.stroke(circle(rimR), with: .color(Sky.surface.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 2.5, dash: [2, 4]))
        ctx.stroke(arc(0, 360 * max(0, min(1, confidence)), rimR),
                   with: .color(color.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 4]))
    }

    // MARK: - Centre readout ("burst open")

    @ViewBuilder
    private var readout: some View {
        if let metric = selected, let r = data.ring(metric) {
            let color = Comfort.needleColor(metric, r.score)
            VStack(spacing: 1) {
                Text(metric.emoji).font(.system(size: 19))
                Text(metric.format(r.value))
                    .font(.system(size: 31, weight: .ultraLight, design: .rounded))
                    .foregroundColor(color)
                Text(metric.comfortLabel(r.value))
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                if let mm = r.minMax {
                    Text("\(metric.format(mm.0))–\(metric.format(mm.1))")
                        .font(.system(size: 9)).foregroundColor(Sky.muted)
                }
                if r.hasFlag {
                    Text("\(r.isMajor ? "🚨" : "⚠️") \(metric.format(r.spread)) apart")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(r.isMajor ? Sky.red : Sky.amber)
                }
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            let s = Comfort.overallScore(data)
            VStack(spacing: 1) {
                Text(Units.tempString(temperature))
                    .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                    .foregroundColor(Sky.white)
                Text(Comfort.overallLabel(s))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Comfort.overallColor(s))
                Text("\(Int((confidence * 100).rounded()))% confident")
                    .font(.system(size: 8.5)).foregroundColor(Sky.muted)
            }
        }
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
    private func circle(_ r: CGFloat) -> Path { Path(ellipseIn: rect(center, r)) }
    private func rect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }
    private func dot(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: rect(c, r)) }

    /// Nearest ring to a tap; a tap on the orb clears the selection.
    private func hit(at p: CGPoint) -> ComfortMetric? {
        let dist = hypot(p.x - center.x, p.y - center.y)
        guard dist > orbR else { return nil }
        var best: (ComfortMetric, CGFloat)?
        for (i, metric) in ComfortMetric.allCases.enumerated() {
            let d = abs(dist - radius(i))
            if d < gap / 2 + 5, best == nil || d < best!.1 { best = (metric, d) }
        }
        guard let found = best?.0 else { return nil }
        return selected == found ? nil : found
    }
}
