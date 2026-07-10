// Sky Warden — Settings
// Units are a display preference; the engines always compute in °C and km/h.

import SwiftUI

struct SettingsView: View {
    @AppStorage(UnitKey.temperature)  private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(UnitKey.wind)         private var windUnit        = WindUnit.kmh.rawValue
    @AppStorage(DisplayKey.dialStyle)   private var dialStyle       = DialStyle.arc.rawValue
    @AppStorage(DisplayKey.arcFillMode) private var arcFillMode     = ArcFillMode.comfort.rawValue
    @AppStorage(DisplayKey.showRange)   private var showRange       = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Sky.navy.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        card("UNITS") {
                            picker("Temperature", selection: $temperatureUnit,
                                   options: TemperatureUnit.allCases.map { ($0.rawValue, $0.label) })
                            Divider().background(Sky.surface)
                            picker("Wind speed", selection: $windUnit,
                                   options: WindUnit.allCases.map { ($0.rawValue, $0.label) })
                        }

                        card("DISPLAY") {
                            picker("Comfort dial", selection: $dialStyle,
                                   options: DialStyle.allCases.map { ($0.rawValue, $0.title) })
                            Text(DialStyle(rawValue: dialStyle)?.blurb ?? "")
                                .font(.system(size: 10)).foregroundColor(Sky.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)

                            if dialStyle == DialStyle.arc.rawValue {
                                Divider().background(Sky.surface).padding(.vertical, 4)
                                picker("Arc fill", selection: $arcFillMode,
                                       options: ArcFillMode.allCases.map { ($0.rawValue, $0.title) })
                                Text(ArcFillMode(rawValue: arcFillMode)?.blurb ?? "")
                                    .font(.system(size: 10)).foregroundColor(Sky.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 2)
                            }

                            Divider().background(Sky.surface).padding(.vertical, 4)
                            toggle("Show today's range", $showRange)
                            Text("Marks today's forecast low→high on each ring and in its badge.")
                                .font(.system(size: 10)).foregroundColor(Sky.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }

                        card("SOURCES") {
                            ForEach(WeatherSource.allCases) { source in
                                HStack(spacing: 10) {
                                    Circle().fill(Color(hex: source.colorHex)).frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(source.rawValue)
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(Sky.white)
                                        Text(source.setupNote)
                                            .font(.system(size: 10)).foregroundColor(Sky.muted)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 3)
                            }
                        }

                        Text("Sky Warden reconciles several forecasts and shows you where they disagree, rather than pretending to a precision no forecast has.")
                            .font(.system(size: 11)).foregroundColor(Sky.muted).lineSpacing(3)
                            .padding(.horizontal, 4)

                        Text("Version \(appVersion)")
                            .font(.system(size: 10)).foregroundColor(Sky.muted)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Settings")
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

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Building blocks
    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10)).foregroundColor(Sky.muted).kerning(0.7)
            VStack(alignment: .leading, spacing: 8) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Sky.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func picker(_ label: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundColor(Sky.text)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190)
        }
    }

    private func toggle(_ label: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label).font(.system(size: 14)).foregroundColor(Sky.text)
        }
        .tint(Sky.tide)
    }
}

#Preview { SettingsView() }
