// Sky Warden — severe-weather warnings banner + detail sheet
//
// Warnings are urgent, so the banner sits at the very top of the Now tab,
// coloured by the worst active severity. Tapping it opens the full list.

import SwiftUI

struct WarningsBanner: View {
    let warnings: [WeatherWarning]
    @State private var showList = false

    private var worst: WeatherWarning? {
        warnings.max { $0.severity < $1.severity }
    }

    var body: some View {
        if let worst {
            Button { showList = true } label: {
                HStack(spacing: 10) {
                    Text(worst.severity.emoji).font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(warnings.count == 1 ? worst.severity.label
                                                 : "\(warnings.count) warnings · \(worst.severity.label)")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        Text(worst.title)
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(worst.color.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(warnings.count) weather \(warnings.count == 1 ? "warning" : "warnings"). Worst: \(worst.severity.label), \(worst.title).")
            .sheet(isPresented: $showList) { WarningsSheet(warnings: warnings) }
        }
    }
}

struct WarningsSheet: View {
    let warnings: [WeatherWarning]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Sky.navy.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(warnings) { w in card(w) }

                        Text(attribution)
                            .font(.system(size: 10)).foregroundColor(Sky.muted).lineSpacing(2)
                            .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(Sky.tide)
                }
            }
            .toolbarBackground(Sky.ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    /// Names the agencies actually shown, so the credit (CC-BY requires it) is
    /// always accurate rather than a fixed list that drifts as feeds are added.
    private var attribution: String {
        let names: [String: String] = [
            "QFD": "Queensland Fire Department", "NSW RFS": "NSW Rural Fire Service",
            "VicEmergency": "VicEmergency", "DFES": "DFES / Emergency WA",
        ]
        let orgs = warnings.map(\.sourceOrg)
        let credited = Array(NSOrderedSet(array: orgs.map { names[$0] ?? $0 })) as? [String] ?? []
        let list = ListFormatter.localizedString(byJoining: credited)
        return "Official warnings from \(list). Always follow the direction of local authorities."
    }

    private func card(_ w: WeatherWarning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(w.severity.emoji).font(.system(size: 15))
                Text(w.severity.label.uppercased())
                    .font(.system(size: 10, weight: .bold)).foregroundColor(w.color).kerning(0.5)
                Spacer()
                Text(w.sourceOrg).font(.system(size: 10)).foregroundColor(Sky.muted)
            }
            Text(w.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Sky.white)
                .fixedSize(horizontal: false, vertical: true)
            if let instruction = w.instruction, !instruction.isEmpty {
                Text(instruction).font(.system(size: 12)).foregroundColor(Sky.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Text(w.category).font(.system(size: 10)).foregroundColor(Sky.muted)
                if let updated = w.updated {
                    Text("· \(relative(updated))").font(.system(size: 10)).foregroundColor(Sky.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sky.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(w.color.opacity(0.4), lineWidth: 1))
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
