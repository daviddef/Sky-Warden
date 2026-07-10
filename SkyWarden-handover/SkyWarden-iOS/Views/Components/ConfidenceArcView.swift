// SkyWarden — ConfidenceArcView
// Segmented arc ring surrounding the main temperature.
// Fills based on consensus confidence score.

import SwiftUI

struct ConfidenceArcView: View {
    let confidence: Double   // 0.0 – 1.0
    let diameter: CGFloat

    private let segments = 20
    private let totalArcDegrees: Double = 240
    private let gapDegrees: Double = 4
    private let lineWidth: CGFloat = 6

    private var startAngle: Double { 150 }   // degrees from 12 o'clock, clockwise
    private var segDeg: Double {
        (totalArcDegrees - gapDegrees * Double(segments - 1)) / Double(segments)
    }
    private var filledSegments: Int { Int((confidence * Double(segments)).rounded()) }

    var body: some View {
        ZStack {
            ForEach(0..<segments, id: \.self) { i in
                ArcSegment(
                    index:       i,
                    total:       segments,
                    startAngle:  startAngle,
                    segDegrees:  segDeg,
                    gapDegrees:  gapDegrees,
                    radius:      (diameter / 2) - lineWidth,
                    lineWidth:   lineWidth,
                    filled:      i < filledSegments,
                    fillColor:   Sky.confidenceColor(confidence),
                    emptyColor:  Sky.surface
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.6).delay(Double.random(in: 0...0.1)), value: confidence)
    }
}

private struct ArcSegment: View {
    let index: Int
    let total: Int
    let startAngle: Double
    let segDegrees: Double
    let gapDegrees: Double
    let radius: CGFloat
    let lineWidth: CGFloat
    let filled: Bool
    let fillColor: Color
    let emptyColor: Color

    private var segStart: Double {
        startAngle + Double(index) * (segDegrees + gapDegrees)
    }
    private var segEnd: Double { segStart + segDegrees }

    var body: some View {
        Path { path in
            path.addArc(
                center:     CGPoint(x: radius + lineWidth, y: radius + lineWidth),
                radius:     radius,
                startAngle: .degrees(segStart),
                endAngle:   .degrees(segEnd),
                clockwise:  false
            )
        }
        .stroke(
            filled ? fillColor : emptyColor,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .frame(width: (radius + lineWidth) * 2, height: (radius + lineWidth) * 2)
    }
}

// MARK: - Confidence badge (compact, for Watch / list rows)
struct ConfidenceBadge: View {
    let confidence: Double
    let severity: DisagreementSeverity

    var body: some View {
        HStack(spacing: 4) {
            if severity != .none {
                Text(severity.emoji)
                    .font(.system(size: 11))
            }
            Text("\(Int((confidence * 100).rounded()))%")
                .font(SkyType.micro)
                .foregroundColor(Sky.confidenceColor(confidence))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Sky.confidenceColor(confidence).opacity(0.12))
        .clipShape(Capsule())
    }
}

#Preview {
    ZStack {
        Sky.navy.ignoresSafeArea()
        VStack(spacing: 40) {
            ConfidenceArcView(confidence: 0.85, diameter: 200)
            ConfidenceArcView(confidence: 0.60, diameter: 200)
            ConfidenceArcView(confidence: 0.30, diameter: 200)
            HStack(spacing: 12) {
                ConfidenceBadge(confidence: 0.85, severity: .none)
                ConfidenceBadge(confidence: 0.60, severity: .minor)
                ConfidenceBadge(confidence: 0.30, severity: .major)
            }
        }
    }
}
