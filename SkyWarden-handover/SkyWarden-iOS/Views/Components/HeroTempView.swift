// SkyWarden — HeroTempView
// The main temperature display with confidence arc and quick stats

import SwiftUI

struct HeroTempView: View {
    let consensus: ConsensusWeather
    @Binding var showDisagreement: Bool

    private let arcDiameter: CGFloat = 210

    var body: some View {
        VStack(spacing: 0) {

            // ── Confidence arc + temperature ─────────────────────────
            ZStack {
                ConfidenceArcView(confidence: consensus.confidence, diameter: arcDiameter)

                VStack(spacing: 4) {
                    // Condition icon
                    Image(systemName: consensus.condition.icon)
                        .font(.system(size: 28))
                        .foregroundColor(conditionColor)
                        .shadow(color: conditionColor.opacity(0.5), radius: 8)

                    // Main temperature
                    Text(consensus.temperatureDisplay)
                        .font(SkyType.largeTemp)
                        .foregroundColor(Sky.white)

                    // Condition label
                    Text(consensus.condition.rawValue)
                        .font(SkyType.caption)
                        .foregroundColor(Sky.muted)

                    // Confidence label
                    Text(consensus.confidenceLabel)
                        .font(SkyType.micro)
                        .foregroundColor(Sky.confidenceColor(consensus.confidence))
                        .textCase(.uppercase)
                        .kerning(0.7)
                        .padding(.top, 2)
                }
            }
            .frame(width: arcDiameter, height: arcDiameter)

            // ── Quick stats row ──────────────────────────────────────
            HStack(spacing: 24) {
                StatPill(icon: "thermometer", label: "Feels", value: "\(Int(consensus.feelsLike.rounded()))°")
                StatPill(icon: "drop.fill",   label: "Rain",  value: consensus.rainDisplay, color: Sky.rain)
                StatPill(icon: "wind",         label: "Wind",  value: consensus.windDisplay)
                StatPill(icon: "sun.max.fill", label: "UV",    value: "\(Int(consensus.uvIndex.rounded()))", color: Sky.uv)
            }
            .padding(.top, 8)

            // ── Source pills + disagreement badge ────────────────────
            HStack(spacing: 8) {
                ForEach(consensus.sources, id: \.rawValue) { source in
                    SourcePill(source: source)
                }

                if consensus.hasDisagreements {
                    DisagreementBadgeButton(
                        disagreements: consensus.disagreements,
                        severity: consensus.worstSeverity
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showDisagreement.toggle()
                        }
                    }
                } else {
                    // All sources agree — green signal
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("All sources agree")
                            .font(SkyType.micro)
                    }
                    .foregroundColor(Sky.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Sky.green.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Colour from condition
    private var conditionColor: Color {
        switch consensus.condition {
        case .clearSky, .mostlyClear:           return Sky.uv
        case .partlyCloudy, .mostlyCloudy:      return Sky.text
        case .overcast:                          return Sky.muted
        case .drizzle, .rain:                   return Sky.rain
        case .heavyRain, .thunderstorm:         return Sky.rain
        case .fog:                              return Sky.muted
        case .snow:                             return Sky.horizon
        }
    }
}

// MARK: - Sub-components
private struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = Sky.text

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SkyType.body)
                .fontWeight(.medium)
                .foregroundColor(color == Sky.text ? Sky.white : color)
            Text(label)
                .font(SkyType.micro)
                .foregroundColor(Sky.muted)
        }
    }
}

private struct SourcePill: View {
    let source: WeatherSource

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: source.colorHex))
                .frame(width: 5, height: 5)
            Text(source.short)
                .font(SkyType.micro)
                .foregroundColor(Sky.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Sky.surface)
        .clipShape(Capsule())
    }
}
