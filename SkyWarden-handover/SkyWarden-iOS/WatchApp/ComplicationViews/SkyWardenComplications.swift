// SkyWarden — Apple Watch Complications
// Supports: .circularSmall, .modularSmall, .graphicCircular, .graphicRectangular
// Requires watchOS 7+ (WidgetKit-based complications use watchOS 9+)

import ClockKit
import SwiftUI

// MARK: - Complication data entry
struct SkyWardenEntry: TimelineEntry {
    let date: Date
    let temperature: Int
    let condition: String         // SF Symbol name
    let conditionEmoji: String
    let rainPercent: Int
    let confidencePercent: Int
    let hasDisagreement: Bool
    let nextTide: String?         // e.g. "High 1.8m @ 6:14"
    let moonEmoji: String
    let moonPhase: String

    // Placeholder for previews
    static var placeholder: SkyWardenEntry {
        SkyWardenEntry(
            date:               Date(),
            temperature:        24,
            condition:          "cloud.sun.fill",
            conditionEmoji:     "⛅",
            rainPercent:        15,
            confidencePercent:  72,
            hasDisagreement:    true,
            nextTide:           "High 1.8m @ 6:14",
            moonEmoji:          "🌔",
            moonPhase:          "Waxing Gibbous"
        )
    }
}

// MARK: - Complication Provider
class SkyWardenComplicationProvider: NSObject, CLKComplicationDataSource {

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier:    "SkyWardenMain",
                displayName:   "Sky Warden",
                supportedFamilies: [
                    .circularSmall,
                    .modularSmall,
                    .modularLarge,
                    .graphicCircular,
                    .graphicCorner,
                    .graphicRectangular,
                ]
            )
        ]
        handler(descriptors)
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        let entry = loadStoredEntry() ?? SkyWardenEntry.placeholder
        let template = makeTemplate(for: complication.family, entry: entry)
        if let t = template {
            handler(CLKComplicationTimelineEntry(date: entry.date, complicationTemplate: t))
        } else {
            handler(nil)
        }
    }

    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Provide next 4 entries at 15-min intervals (refresh via background task)
        let entry = loadStoredEntry() ?? SkyWardenEntry.placeholder
        var entries: [CLKComplicationTimelineEntry] = []
        for i in 0..<min(limit, 4) {
            let futureDate = date.addingTimeInterval(TimeInterval(i * 900))
            if let template = makeTemplate(for: complication.family, entry: entry) {
                entries.append(CLKComplicationTimelineEntry(date: futureDate, complicationTemplate: template))
            }
        }
        handler(entries)
    }

    // MARK: - Template factory
    private func makeTemplate(for family: CLKComplicationFamily, entry: SkyWardenEntry) -> CLKComplicationTemplate? {
        switch family {

        // ── Graphic Circular (large round complication) ──────────────
        case .graphicCircular:
            let view = CircularComplicationView(entry: entry)
            return CLKComplicationTemplateGraphicCircularView(view)

        // ── Graphic Rectangular (banner style) ───────────────────────
        case .graphicRectangular:
            let view = RectangularComplicationView(entry: entry)
            return CLKComplicationTemplateGraphicRectangularFullView(view)

        // ── Graphic Corner ───────────────────────────────────────────
        case .graphicCorner:
            let view = CornerComplicationView(entry: entry)
            return CLKComplicationTemplateGraphicCornerCircularView(view)

        // ── Modular Small (legacy) ───────────────────────────────────
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "\(entry.temperature)°")
            template.line2TextProvider = CLKSimpleTextProvider(
                text: entry.hasDisagreement ? "⚠️\(entry.confidencePercent)%" : "\(entry.rainPercent)%💧"
            )
            return template

        // ── Circular Small ───────────────────────────────────────────
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "\(entry.temperature)°")
            template.line2TextProvider = CLKSimpleTextProvider(text: entry.conditionEmoji)
            return template

        default:
            return nil
        }
    }

    // MARK: - Data persistence
    private func loadStoredEntry() -> SkyWardenEntry? {
        // Load from App Group shared UserDefaults.
        // The main app writes after each fetch (see WeatherAggregator.publishToWatch);
        // the Watch reads that snapshot here.
        guard let defaults = UserDefaults.skyWardenShared,
              let data = defaults.data(forKey: SkyWardenID.latestWeatherKey),
              let stored = try? JSONDecoder().decode(StoredWeatherData.self, from: data)
        else { return nil }

        return SkyWardenEntry(
            date:               stored.fetchedAt,
            temperature:        stored.temperature,
            condition:          stored.conditionSFSymbol,
            conditionEmoji:     stored.conditionEmoji,
            rainPercent:        stored.rainPercent,
            confidencePercent:  stored.confidencePercent,
            hasDisagreement:    stored.hasDisagreement,
            nextTide:           stored.nextTide,
            moonEmoji:          stored.moonEmoji,
            moonPhase:          stored.moonPhase
        )
    }
}

// NOTE: `StoredWeatherData` now lives in Shared/SkyWardenShared.swift so both
// the iOS app (writer) and the Watch (reader) compile against one definition.

// MARK: - Circular complication SwiftUI view
struct CircularComplicationView: View {
    let entry: SkyWardenEntry

    var body: some View {
        ZStack {
            // Confidence ring
            Circle()
                .trim(from: 0, to: CGFloat(entry.confidencePercent) / 100)
                .stroke(
                    entry.hasDisagreement ? Color.yellow : Color.green,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(2)

            VStack(spacing: 0) {
                Text("\(entry.temperature)°")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                if entry.hasDisagreement {
                    Text("⚠️")
                        .font(.system(size: 9))
                } else {
                    Text("\(entry.rainPercent)%")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Rectangular complication SwiftUI view
struct RectangularComplicationView: View {
    let entry: SkyWardenEntry

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.temperature)°")
                    .font(.system(size: 26, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                Text(entry.conditionEmoji + " \(entry.rainPercent)% rain")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Divider().frame(height: 28).background(Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 2) {
                if entry.hasDisagreement {
                    Text("⚠️ Sources vary")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.yellow)
                }
                if let tide = entry.nextTide {
                    Text("🌊 " + tide)
                        .font(.system(size: 9))
                        .foregroundColor(.cyan)
                }
                Text(entry.moonEmoji + " " + entry.moonPhase)
                    .font(.system(size: 9))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Corner complication
struct CornerComplicationView: View {
    let entry: SkyWardenEntry

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(entry.confidencePercent) / 100)
                .stroke(entry.hasDisagreement ? Color.yellow : Color.green, lineWidth: 2)
                .rotationEffect(.degrees(-90))

            Text("\(entry.temperature)°")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.white)
        }
    }
}
