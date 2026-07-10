// SkyWarden — Today Detail + Tides Detail Views

import SwiftUI

// MARK: - Today (full hourly breakdown)
struct TodayDetailView: View {
    let hourly: [ConsensusHourly]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(hourly.enumerated()), id: \.element.id) { (i, h) in
                        HourDetailRow(reading: h, isCurrent: i == 0)
                        if i < hourly.count - 1 {
                            Divider().background(Sky.surface).padding(.horizontal, 16)
                        }
                    }
                }
                .background(Sky.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct HourDetailRow: View {
    let reading: ConsensusHourly
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Time
            Text(isCurrent ? "Now" : reading.hourLabel)
                .font(SkyType.caption)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundColor(isCurrent ? Sky.white : Sky.muted)
                .frame(width: 38, alignment: .leading)

            // Condition icon
            Image(systemName: reading.condition.icon)
                .font(.system(size: 20))
                .foregroundColor(Sky.text)
                .frame(width: 24)

            // Condition label
            Text(reading.condition.rawValue)
                .font(SkyType.caption)
                .foregroundColor(Sky.muted)

            Spacer()

            // Disagreement indicator
            if reading.hasDisagreement {
                Text("⚠️")
                    .font(.system(size: 11))
            }

            // Rain bar + percent
            HStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Sky.surface)
                        .frame(width: 4, height: 24)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Sky.rain)
                        .frame(width: 4, height: max(1, CGFloat(reading.rainProbability / 100) * 24))
                }
                Text("\(Int(reading.rainProbability.rounded()))%")
                    .font(SkyType.caption)
                    .foregroundColor(reading.rainProbability > 40 ? Sky.rain : Sky.muted)
                    .frame(width: 32, alignment: .trailing)
            }

            // Temperature
            Text("\(Int(reading.temperature.rounded()))°")
                .font(SkyType.body)
                .fontWeight(.medium)
                .foregroundColor(isCurrent ? Sky.white : Sky.text)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isCurrent ? Sky.rain.opacity(0.07) : Color.clear)
    }
}

// MARK: - Tides Detail View
struct TidesDetailView: View {
    let tideDay: TideDay?
    let moonData: MoonData?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                if let tideDay {
                    // Full tide curve card
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "TODAY'S TIDES", icon: "water.waves")

                        TideStripView(events: tideDay.events)

                        if !tideDay.curvePoints.isEmpty {
                            TideCurveView(
                                curvePoints: tideDay.curvePoints,
                                events: tideDay.events,
                                height: 130
                            )
                        }

                        Divider().background(Sky.surface)

                        // Station info
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(Sky.muted)
                                Text("Tide Station")
                                    .font(SkyType.sectionHead)
                                    .foregroundColor(Sky.muted)
                            }
                            Text(tideDay.station.name)
                                .font(SkyType.body)
                                .foregroundColor(Sky.white)
                            if let dist = tideDay.station.distanceKm {
                                Text(String(format: "%.1f km from your location", dist))
                                    .font(SkyType.micro)
                                    .foregroundColor(Sky.muted)
                            }
                        }

                        Text("Tide predictions use harmonic analysis from official gauge stations. Tide times are deterministic — no disagreement comparison is applied.")
                            .font(SkyType.micro)
                            .foregroundColor(Sky.muted)
                    }
                    .padding(16)
                    .background(Sky.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)

                } else {
                    TidesUnavailableCard()
                        .padding(.horizontal, 16)
                }

                // Moon card (full)
                if let moon = moonData {
                    MoonDetailCard(moon: moon)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical, 12)
        }
    }
}

private struct MoonDetailCard: View {
    let moon: MoonData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "MOON", icon: "moonphase.waxing.gibbous")

            HStack(alignment: .top, spacing: 20) {
                // Big moon emoji
                Text(moon.phase.emoji)
                    .font(.system(size: 56))

                VStack(alignment: .leading, spacing: 6) {
                    Text(moon.phase.rawValue)
                        .font(SkyType.smallTemp)
                        .foregroundColor(Sky.moon)
                    Text("\(moon.illuminationPercent)% illuminated")
                        .font(SkyType.caption)
                        .foregroundColor(Sky.text)
                    Text("Age: \(String(format: "%.1f", moon.age)) days")
                        .font(SkyType.caption)
                        .foregroundColor(Sky.muted)
                }
            }

            // Illumination bar
            VStack(alignment: .leading, spacing: 6) {
                Text("ILLUMINATION")
                    .font(SkyType.sectionHead)
                    .foregroundColor(Sky.muted)
                    .kerning(0.6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Sky.surface)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Sky.moon.opacity(0.5), Sky.moon],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(moon.illumination), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("New")
                    Spacer()
                    Text("Full")
                }
                .font(SkyType.micro)
                .foregroundColor(Sky.muted)
            }

            Divider().background(Sky.surface)

            // Next events
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT FULL")
                        .font(SkyType.micro)
                        .foregroundColor(Sky.muted)
                        .kerning(0.5)
                    Text("In \(moon.daysToFull) day\(moon.daysToFull == 1 ? "" : "s")")
                        .font(SkyType.body)
                        .foregroundColor(Sky.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("NEXT NEW")
                        .font(SkyType.micro)
                        .foregroundColor(Sky.muted)
                        .kerning(0.5)
                    Text(moon.nextNewMoon.shortDateLabel)
                        .font(SkyType.body)
                        .foregroundColor(Sky.white)
                }
            }
        }
        .padding(16)
        .background(Sky.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct TidesUnavailableCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "water.waves.slash")
                .font(.system(size: 32))
                .foregroundColor(Sky.muted)
            Text("Tide data unavailable")
                .font(SkyType.body)
                .foregroundColor(Sky.text)
            Text("Add a WorldTides API key in settings to enable tide predictions.")
                .font(SkyType.caption)
                .foregroundColor(Sky.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Sky.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Date helper
extension Date {
    var shortDateLabel: String {
        if Calendar.current.isDateInTomorrow(self) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: self)
    }
}
