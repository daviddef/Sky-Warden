// Sky Warden — Comfort Dial (arc)
//
// Five concentric top-half arcs. Position and colour always carry comfort; what
// the *filled length* means is a user setting (ArcFillMode):
//
//   .comfort  fill runs from the good (left) end to the needle — a comfortable
//             metric is a short arc, an uncomfortable one nearly full. Nothing
//             emanates from the top any more, which is what "start at 0" meant.
//   .value    fill is the raw reading on the metric's own 0→max scale. UV 0 is
//             empty, UV 11 nearly full.
//   .both     value fill, plus tick(s) where the comfort line crosses.
//
// Each needle tip carries a capsule with the metric's icon AND its value, so the
// numbers live on the dial. The verdict and a row of confidence dots sit in the
// open lower centre; the wordy readout that didn't fit is gone.

import SwiftUI

struct ComfortDialView: View {
    let data: ComfortData
    var temperature: Double = .nan
    var confidence: Double = 1
    @Binding var selected: ComfortMetric?

    @AppStorage(DisplayKey.arcFillMode) private var fillModeRaw = ArcFillMode.comfort.rawValue
    @AppStorage(DisplayKey.showRange)   private var showRange   = true
    private var fillMode: ArcFillMode { ArcFillMode(rawValue: fillModeRaw) ?? .comfort }

    private let W: CGFloat = 340
    private let ringH: CGFloat = 206
    private let readoutH: CGFloat = 84
    private let cx: CGFloat = 170
    private let cy: CGFloat = 178
    private let baseR: CGFloat = 150
    private let gap: CGFloat = 23

    private var center: CGPoint { CGPoint(x: cx, y: cy) }
    private func radius(_ i: Int) -> CGFloat { baseR - CGFloat(i) * gap }

    var body: some View {
        VStack(spacing: 0) {
            ringBox
            readout
                .frame(width: W, height: readoutH, alignment: .top)
                .padding(.top, -74)
        }
        .frame(width: W)
    }

    // MARK: - Fraction along the arc (0 = good/left, 1 = poor/right)

    /// Comfort score +1 (good) → 0, −1 (poor) → 1.
    private func comfortFraction(_ score: Double) -> Double { (1 - max(-1, min(1, score))) / 2 }

    /// Where a raw value sits on the arc, per the current fill mode. In value
    /// modes the arc is the metric's own scale; in comfort mode it's the score.
    private func fraction(_ metric: ComfortMetric, value: Double) -> Double {
        switch fillMode {
        case .comfort:     comfortFraction(metric.score(value))
        case .value, .both: metric.normalized(value)
        }
    }

    /// The reading's own fraction — what the fill runs to and the needle marks.
    private func readingFraction(_ r: RingReading) -> Double {
        fraction(r.metric, value: r.value)
    }

    private func angleAt(_ fraction: Double) -> Double { -90 + 180 * max(0, min(1, fraction)) }

    /// Today's low→high, but only when it's worth showing: the setting is on, a
    /// range exists, and the two ends don't format to the same string (a wind
    /// forecast of 0.6–1.4 km/h collapses to "1–1", which is just noise).
    private func shownRange(_ r: RingReading) -> (Double, Double)? {
        guard showRange, let mm = r.minMax,
              r.metric.format(mm.0) != r.metric.format(mm.1) else { return nil }
        return mm
    }

    private struct Badge {
        let metric: ComfortMetric, value: Double
        let range: (Double, Double)?
        let anchor: CGPoint          // the reading dot on the ring
        let radius: CGFloat          // this ring's radius
        let frac: Double             // reading fraction 0…1 along the arc
        let color: Color
        let flagged: Bool, major: Bool, selected: Bool
    }

    // MARK: - Rings
    private var ringBox: some View {
        Canvas { ctx, _ in
            var badges: [Badge] = []
            for (i, metric) in ComfortMetric.allCases.enumerated() {
                guard let r = data.ring(metric) else { continue }
                drawRing(ctx, reading: r, radius: radius(i), isSelected: selected == metric, badges: &badges)
            }
            layoutBadges(ctx, badges)
            drawEndLabels(ctx)
        }
        .frame(width: W, height: ringH)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            if let hit = ringHit(at: value.location) {
                withAnimation(.spring(response: 0.3)) { selected = (selected == hit) ? nil : hit }
            }
        })
    }

    private func drawRing(_ ctx: GraphicsContext, reading r: RingReading,
                          radius rad: CGFloat, isSelected: Bool, badges: inout [Badge]) {
        let metric = r.metric
        let color = Comfort.comfortColor(r.score)
        let lw: CGFloat = isSelected ? 12 : 9
        let needleF = readingFraction(r)
        let needleA = angleAt(needleF)

        // Track.
        ctx.stroke(arc(-90, 90, rad), with: .color(Sky.surface),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // The fill: always from the left (good/low) end to the reading.
        ctx.stroke(arc(-90, needleA, rad), with: .color(color),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // Today's forecast low→high: a bright core over the span it covers, drawn
        // ON TOP of the fill so it reads whether the span sits inside the filled
        // part or beyond the needle. The numbers ride in the badge below.
        if let mm = shownRange(r) {
            let a = angleAt(fraction(metric, value: mm.0))
            let b = angleAt(fraction(metric, value: mm.1))
            ctx.stroke(arc(min(a, b), max(a, b), rad), with: .color(Sky.white.opacity(0.5)),
                       style: StrokeStyle(lineWidth: max(2, lw * 0.32), lineCap: .round))
            for e in [a, b] {
                ctx.stroke(tick(e, rad, lw + 3), with: .color(Sky.white.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5))
            }
        }

        // .both: mark where comfort crosses, so magnitude (length) and comfort
        // (tick) can be read separately.
        if fillMode == .both {
            for t in comfortThresholds(metric) {
                ctx.stroke(tick(angleAt(metric.normalized(t)), rad, lw + 3),
                           with: .color(Sky.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5))
            }
        }

        // Where each source sits — neutral ticks; a wide scatter reads as spread.
        for s in r.perSource {
            ctx.stroke(tick(angleAt(fraction(metric, value: s.value)), rad, lw),
                       with: .color(Sky.muted.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
        }

        // Disagreement span (dashed) across the sources' full width.
        if r.hasFlag {
            let fracs = r.perSource.map { fraction(metric, value: $0.value) }
            if let lo = fracs.min(), let hi = fracs.max() {
                ctx.stroke(arc(angleAt(lo), angleAt(hi), rad),
                           with: .color((r.isMajor ? Sky.red : Sky.amber).opacity(0.6)),
                           style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
            }
        }

        // The needle position is marked with a small dot; its icon+value capsule
        // is laid out afterwards, once all five are known, so they can be nudged
        // apart when several metrics cluster at the same end of the arc.
        let tip = polar(needleA, rad)
        ctx.fill(Path(ellipseIn: rect(tip, 3)), with: .color(color))
        // Range numbers ride in the badge only for temperature: a two-line badge
        // on all five would stack too tall where the good metrics cluster. Every
        // ring still shows the range as the band above; tap any ring for its
        // numbers in the centre.
        let badgeRange = metric == .temp ? shownRange(r) : nil
        badges.append(Badge(metric: metric, value: r.value, range: badgeRange,
                            anchor: tip, radius: rad, frac: needleF, color: color,
                            flagged: r.hasFlag, major: r.isMajor, selected: isSelected))
    }

    /// Lays out the icon+value capsules and draws them.
    ///
    /// The badges do NOT sit at the reading — the ring fill and the needle dot
    /// already show that. Anchoring them to the reading crowded every good metric
    /// at the left "starting point". Instead they're spread evenly across the arc,
    /// each on its own ring's radius, ordered so a left-to-right read still
    /// matches the readings, with a thin leader from each capsule back to its dot.
    private func layoutBadges(_ ctx: GraphicsContext, _ badges: [Badge]) {
        guard !badges.isEmpty else { return }
        let ordered = badges.sorted { $0.frac < $1.frac }
        let n = ordered.count

        for (k, b) in ordered.enumerated() {
            let size: CGFloat = b.selected ? 12 : 10.5
            let value = ctx.resolve(Text("\(b.metric.emoji) \(b.metric.format(b.value))")
                .font(.system(size: size, weight: .semibold)).foregroundColor(Sky.white))
            let vm = value.measure(in: CGSize(width: 160, height: 40))

            var range: GraphicsContext.ResolvedText?
            var rm = CGSize.zero
            if let mm = b.range {
                let t = ctx.resolve(Text("\(b.metric.format(mm.0))–\(b.metric.format(mm.1))")
                    .font(.system(size: size - 2, weight: .medium)).foregroundColor(Sky.muted))
                rm = t.measure(in: CGSize(width: 160, height: 40))
                range = t
            }
            let box = CGSize(width: max(vm.width, rm.width) + 16,
                             height: vm.height + (range != nil ? rm.height + 1 : 0) + 6)

            // Evenly-spaced slot across the arc, then park the capsule just inside
            // its ring at that angle. Even radii → different rings sit at different
            // heights, so the row never collides.
            let slotFrac = n == 1 ? 0.5 : 0.10 + 0.80 * Double(k) / Double(n - 1)
            let slotAngle = angleAt(slotFrac)
            // Seat just OUTSIDE the ring (away from the centre readout) and keep
            // every capsule in the upper half, so none can land on the "15 / Good"
            // text or the confidence dots that sit in the open lower centre.
            let seat = polar(slotAngle, b.radius + box.height / 2 + 4)
            let c = CGPoint(x: max(box.width / 2 + 1, min(W - box.width / 2 - 1, seat.x)),
                            y: max(box.height / 2 + 1, min(cy - box.height / 2 - 2, seat.y)))

            // Leader that HUGS the ring — an arc from the reading dot round to the
            // capsule's slot — rather than a chord across the open centre.
            if abs(slotFrac - b.frac) > 0.03 {
                ctx.stroke(arc(angleAt(b.frac), slotAngle, b.radius),
                           with: .color(Sky.muted.opacity(0.28)), lineWidth: 1)
            }

            let boxRect = CGRect(x: c.x - box.width / 2, y: c.y - box.height / 2,
                                 width: box.width, height: box.height)
            let corner = min(box.height / 2, 9)
            ctx.fill(Path(roundedRect: boxRect, cornerRadius: corner), with: .color(Sky.navy))
            ctx.stroke(Path(roundedRect: boxRect, cornerRadius: corner),
                       with: .color(b.flagged ? (b.major ? Sky.red : Sky.amber) : b.color),
                       lineWidth: b.selected ? 2 : 1.4)

            if let range {
                let vh = vm.height, rh = rm.height
                ctx.draw(value, at: CGPoint(x: c.x, y: boxRect.minY + 3 + vh / 2))
                ctx.draw(range, at: CGPoint(x: c.x, y: boxRect.maxY - 3 - rh / 2))
            } else {
                ctx.draw(value, at: c)
            }
        }
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

    private func drawEndLabels(_ ctx: GraphicsContext) {
        let (lo, hi) = fillMode == .comfort ? ("◀ good", "poor ▶") : ("◀ low", "high ▶")
        ctx.draw(Text(lo).font(.system(size: 8.5)).foregroundColor(Comfort.good.opacity(0.6)),
                 at: CGPoint(x: 2, y: cy + 15), anchor: .leading)
        ctx.draw(Text(hi).font(.system(size: 8.5)).foregroundColor(Comfort.poor.opacity(0.6)),
                 at: CGPoint(x: W - 2, y: cy + 15), anchor: .trailing)
    }

    // MARK: - Centre readout: verdict + confidence dots
    @ViewBuilder
    private var readout: some View {
        if let metric = selected, let r = data.ring(metric) {
            let color = Comfort.comfortColor(r.score)
            VStack(spacing: 1) {
                Text(metric.label.uppercased()).font(.system(size: 8)).foregroundColor(Sky.muted).kerning(0.6)
                Text(metric.format(r.value))
                    .font(.system(size: 30, weight: .ultraLight, design: .rounded)).foregroundColor(color)
                Text(metric.comfortLabel(r.value)).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                if let mm = r.minMax {
                    Text("\(metric.format(mm.0))–\(metric.format(mm.1))")
                        .font(.system(size: 9)).foregroundColor(Sky.muted)
                }
                if let peak = r.peak {
                    Text(peak.phrase).font(.system(size: 9, weight: .medium)).foregroundColor(color.opacity(0.9))
                }
            }
        } else {
            let s = Comfort.overallScore(data)
            VStack(spacing: 3) {
                // Temperature is the bright anchor; the verdict word carries the
                // comfort colour beneath it, matching the radial dial's orb.
                if temperature.isFinite {
                    Text(Units.tempString(temperature))
                        .font(.system(size: 30, weight: .ultraLight, design: .rounded))
                        .foregroundColor(Sky.white)
                }
                Text(Comfort.overallLabel(s))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Comfort.overallColor(s))
                confidenceDots.padding(.top, 2)
            }
        }
    }

    /// Confidence as a row of dots — the arc dial's echo of the radial rim. The
    /// number and bar that lived in a separate widget move here.
    private var confidenceDots: some View {
        let filled = Int((confidence * 10).rounded())
        let color = confidence >= 0.8 ? Comfort.good : confidence >= 0.5 ? Sky.amber : Comfort.poor
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    Circle().fill(i < filled ? color : Sky.surface).frame(width: 5, height: 5)
                }
            }
            Text("\(Int((confidence * 100).rounded()))% confidence")
                .font(.system(size: 8)).foregroundColor(Sky.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((confidence * 100).rounded())) percent confidence")
    }

    // MARK: - Geometry
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
        p.move(to: polar(a, r - lw / 2 - 2))
        p.addLine(to: polar(a, r + lw / 2 + 2))
        return p
    }
    private func rect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    /// Nearest ring to a tap in the upper half.
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
