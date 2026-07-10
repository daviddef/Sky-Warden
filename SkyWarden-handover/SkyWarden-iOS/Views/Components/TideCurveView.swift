// SkyWarden — TideCurveView
// Smooth tide curve for a single day using SwiftUI Charts (iOS 16+)

import SwiftUI
import Charts

struct TideCurveView: View {
    let curvePoints: [TideCurvePoint]
    let events: [TideEvent]
    let height: CGFloat

    @State private var nowTime = Date()

    private var minHeight: Double { (curvePoints.map(\.height).min() ?? 0) - 0.1 }
    private var maxHeight: Double { (curvePoints.map(\.height).max() ?? 2) + 0.1 }

    var body: some View {
        Chart {
            // Filled area under curve
            ForEach(curvePoints.indices, id: \.self) { i in
                let p = curvePoints[i]
                AreaMark(
                    x: .value("Time", p.time),
                    y: .value("Height", p.height)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Sky.tide.opacity(0.35), Sky.tide.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", p.time),
                    y: .value("Height", p.height)
                )
                .foregroundStyle(Sky.tide)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            // High/low event markers
            ForEach(events) { event in
                PointMark(
                    x: .value("Time", event.time),
                    y: .value("Height", event.height)
                )
                .foregroundStyle(event.type == .high ? Sky.tide : Sky.muted)
                .symbolSize(36)
                .annotation(position: event.type == .high ? .top : .bottom) {
                    VStack(spacing: 1) {
                        Text(event.heightDisplay)
                            .font(SkyType.micro)
                            .foregroundColor(event.type == .high ? Sky.tide : Sky.muted)
                        Text(event.timeDisplay)
                            .font(SkyType.micro)
                            .foregroundColor(Sky.muted)
                    }
                }
            }

            // "Now" vertical rule
            RuleMark(x: .value("Now", nowTime))
                .foregroundStyle(Sky.white.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .center) {
                    Text("NOW")
                        .font(SkyType.micro)
                        .foregroundColor(Sky.muted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Sky.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
        }
        .chartYScale(domain: minHeight...maxHeight)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Sky.surface)
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(Sky.muted)
                    .font(SkyType.micro)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Sky.surface)
                AxisValueLabel(format: Decimal.FormatStyle())
                    .foregroundStyle(Sky.muted)
                    .font(SkyType.micro)
            }
        }
        .frame(height: height)
        .onAppear { nowTime = Date() }
    }
}

// MARK: - Compact tide strip (for Now tab card)
struct TideStripView: View {
    let events: [TideEvent]

    var body: some View {
        HStack {
            ForEach(events.prefix(4)) { event in
                VStack(spacing: 3) {
                    Text(event.type.rawValue.uppercased())
                        .font(SkyType.micro)
                        .foregroundColor(event.type == .high ? Sky.tide : Sky.muted)
                        .kerning(0.5)
                    Text(event.heightDisplay)
                        .font(SkyType.body)
                        .fontWeight(.medium)
                        .foregroundColor(Sky.white)
                    Text(event.timeDisplay)
                        .font(SkyType.micro)
                        .foregroundColor(Sky.muted)
                }
                .frame(maxWidth: .infinity)
                if events.prefix(4).last?.id != event.id {
                    Divider()
                        .background(Sky.surface)
                        .frame(height: 36)
                }
            }
        }
    }
}
