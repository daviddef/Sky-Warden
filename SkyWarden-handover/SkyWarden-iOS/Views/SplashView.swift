// SkyWarden — Animated splash
// Continues seamlessly from the static launch screen (same mark on navy):
// the three confidence arcs sweep in, the sun blooms, the wordmark rises.

import SwiftUI

// MARK: - Root: splash over the app, auto-dismissing
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            withAnimation(.easeInOut(duration: 0.55)) { showSplash = false }
        }
    }
}

// MARK: - Splash
struct SplashView: View {
    @State private var reveal: CGFloat = 0
    @State private var sunOn = false
    @State private var textOn = false

    private let dialSize: CGFloat = 236

    var body: some View {
        ZStack {
            Sky.navy.ignoresSafeArea()

            VStack(spacing: 30) {
                ZStack {
                    // Warm glow behind the sun
                    Circle()
                        .fill(RadialGradient(
                            colors: [Sky.uv.opacity(0.55), Sky.uv.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 150))
                        .frame(width: 300, height: 300)
                        .opacity(sunOn ? 1 : 0)

                    // Sun disc
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(hex: "FFD27A"), Color(hex: "FF8C61")],
                            center: UnitPoint(x: 0.5, y: 0.4), startRadius: 4, endRadius: 62))
                        .frame(width: 112, height: 112)
                        .scaleEffect(sunOn ? 1 : 0.4)
                        .opacity(sunOn ? 1 : 0)

                    // Three confidence arcs, staggered
                    ring(diameter: 236, color: Sky.green, segs: 14, delay: 0.00)
                    ring(diameter: 194, color: Sky.tide,  segs: 12, delay: 0.12)
                    ring(diameter: 152, color: Sky.rain,  segs: 10, delay: 0.24)
                }
                .frame(width: dialSize, height: dialSize)

                VStack(spacing: 8) {
                    Text("Sky Warden")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(Sky.white)
                    Text("Weather, from more than one sky.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Sky.muted)
                }
                .opacity(textOn ? 1 : 0)
                .offset(y: textOn ? 0 : 12)
            }
        }
        .onAppear {
            reveal = 1  // per-ring .animation modifiers stagger the sweep
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) { sunOn = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.6)) { textOn = true }
        }
    }

    private func ring(diameter: CGFloat, color: Color, segs: Int, delay: Double) -> some View {
        SegmentedArc(startDeg: 150, sweepDeg: 240, segments: segs, gapDeg: 3.5)
            .trim(from: 0, to: reveal)
            .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .animation(.easeOut(duration: 0.9).delay(delay), value: reveal)
    }
}

// MARK: - Segmented arc (disconnected capsule ticks, trimmable)
struct SegmentedArc: Shape {
    var startDeg: Double
    var sweepDeg: Double
    var segments: Int
    var gapDeg: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let seg = (sweepDeg - gapDeg * Double(segments - 1)) / Double(segments)
        for i in 0..<segments {
            let a0 = startDeg + Double(i) * (seg + gapDeg)
            let a1 = a0 + seg
            let start = CGPoint(x: c.x + r * cos(a0 * .pi / 180),
                                y: c.y + r * sin(a0 * .pi / 180))
            p.move(to: start)
            p.addArc(center: c, radius: r,
                     startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
        }
        return p
    }
}

#Preview {
    SplashView()
}
