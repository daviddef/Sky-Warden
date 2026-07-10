// SkyWarden — DisagreementPanelView

import SwiftUI

// MARK: - Expandable disagreement panel (triggered by ⚠️ badge tap)
struct DisagreementPanelView: View {
    let disagreements: [FieldDisagreement]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Sky.amber)
                    .font(.system(size: 13))
                Text("Sources disagree")
                    .font(SkyType.sectionHead)
                    .foregroundColor(Sky.amber)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text("TAP TO DISMISS")
                    .font(SkyType.micro)
                    .foregroundColor(Sky.muted)
            }

            ForEach(disagreements) { d in
                FieldDisagreementRow(disagreement: d)
            }
        }
        .padding(16)
        .background(Sky.amberBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Sky.amber.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct FieldDisagreementRow: View {
    let disagreement: FieldDisagreement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(disagreement.fieldLabel)
                .font(SkyType.micro)
                .foregroundColor(Sky.muted)
                .textCase(.uppercase)
                .kerning(0.5)

            HStack(spacing: 6) {
                ForEach(disagreement.sortedSources, id: \.0.rawValue) { (source, value) in
                    SourceValuePill(source: source, value: value)
                }
                Spacer()
            }
        }
    }
}

struct SourceValuePill: View {
    let source: WeatherSource
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: source.colorHex))
                .frame(width: 6, height: 6)
            Text(source.short)
                .font(SkyType.caption)
                .foregroundColor(Sky.muted)
            Text(value)
                .font(SkyType.caption)
                .fontWeight(.semibold)
                .foregroundColor(Sky.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Sky.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Warning badge tappable button
struct DisagreementBadgeButton: View {
    let disagreements: [FieldDisagreement]
    let severity: DisagreementSeverity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: severity == .major
                      ? "exclamationmark.triangle.fill"
                      : "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(disagreements.count) \(disagreements.count == 1 ? "field" : "fields") vary")
                    .font(SkyType.micro)
            }
            .foregroundColor(severity == .major ? Sky.red : Sky.amber)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (severity == .major ? Sky.red : Sky.amber).opacity(0.15)
            )
            .overlay(
                Capsule().stroke(
                    (severity == .major ? Sky.red : Sky.amber).opacity(0.4),
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
    }
}

// MARK: - Full sources tab row
struct SourceStatusRow: View {
    let reading: WeatherReading

    var body: some View {
        HStack(spacing: 12) {
            // Source dot
            Circle()
                .fill(Color(hex: reading.source.colorHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.source.rawValue)
                    .font(SkyType.body)
                    .foregroundColor(Sky.white)
                Text("Updated \(reading.fetchedAt.relativeLabel)")
                    .font(SkyType.micro)
                    .foregroundColor(Sky.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(reading.temperature.rounded()))°")
                    .font(SkyType.smallTemp)
                    .foregroundColor(Sky.white)
                Text(reading.condition.rawValue)
                    .font(SkyType.micro)
                    .foregroundColor(Sky.muted)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Date helper
extension Date {
    var relativeLabel: String {
        let secs = Int(Date().timeIntervalSince(self))
        if secs < 60   { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}

#Preview {
    ZStack {
        Sky.navy.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 16) {
                DisagreementPanelView(disagreements: [
                    FieldDisagreement(
                        fieldKey: "temperature", fieldLabel: "Temperature",
                        severity: .minor,
                        perSource: [.ecmwf: "24°C", .gfs: "26°C", .bom: "24°C"]
                    ),
                    FieldDisagreement(
                        fieldKey: "rain", fieldLabel: "Rain chance",
                        severity: .major,
                        perSource: [.ecmwf: "15%", .gfs: "55%", .ukmo: "10%"]
                    ),
                ])
                DisagreementBadgeButton(
                    disagreements: [],
                    severity: .minor,
                    action: {}
                )
            }
            .padding(16)
        }
    }
}
