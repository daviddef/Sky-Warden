// Sky Warden — Apple Watch modules (WidgetKit)
//
// The modern (watchOS 9+) complications, alongside the legacy ClockKit set in
// ComplicationViews/SkyWardenComplications.swift. WidgetKit is what the current
// watch face editor surfaces, and it gives us the accessory families:
//
//   .accessoryCircular     a ring around the temp — the CONFIDENCE ring is the
//                          hero: it fills with how much the sources agree, and
//                          turns amber the moment they don't. Sky Warden's moat,
//                          on the smallest possible surface.
//   .accessoryCorner       temp with a curved confidence gauge hugging the corner.
//   .accessoryRectangular  temp + condition + the agree/disagree verdict + next tide.
//   .accessoryInline       one line: "24° · sources vary" — the flag in the
//                          watch-face inline slot.
//
// Data: the iOS app already writes a snapshot to the App Group after every fetch
// (WeatherAggregator.publishToWatch → StoredWeatherData in the shared defaults);
// this reads that snapshot. No network on the watch.
//
// NOT YET BUILT: there is no watchOS target in project.yml. See docs/WATCH.md for
// the exact wiring (targets, bundle IDs, App Group) — deliberately not added here
// because a mis-wired embedded target can break the iOS App Store archive, and the
// archive can't be verified with the screen locked. Add the target, drop this file
// into it, and it compiles against the shared SkyWardenEntry / StoredWeatherData.

#if canImport(WidgetKit) && os(watchOS)
import WidgetKit
import SwiftUI

// MARK: - Timeline provider (reads the App Group snapshot)

struct SkyWardenTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkyWardenEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SkyWardenEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyWardenEntry>) -> Void) {
        let entry = Self.currentEntry()
        // The iOS app refreshes the snapshot on its own cadence; ask WidgetKit to
        // re-read in ~15 min so a stale face doesn't linger.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static func currentEntry() -> SkyWardenEntry {
        guard let defaults = UserDefaults.skyWardenShared,
              let data = defaults.data(forKey: SkyWardenID.latestWeatherKey),
              let s = try? JSONDecoder().decode(StoredWeatherData.self, from: data)
        else { return .placeholder }
        return SkyWardenEntry(
            date: s.fetchedAt, temperature: s.temperature, condition: s.conditionSFSymbol,
            conditionEmoji: s.conditionEmoji, rainPercent: s.rainPercent,
            confidencePercent: s.confidencePercent, comfortPercent: s.comfortPercent,
            hasDisagreement: s.hasDisagreement,
            nextTide: s.nextTide, moonEmoji: s.moonEmoji, moonPhase: s.moonPhase)
    }
}

// MARK: - The widget

@main
struct SkyWardenWatchWidgets: WidgetBundle {
    var body: some Widget { SkyWardenComplication() }
}

struct SkyWardenComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkyWardenComplication", provider: SkyWardenTimelineProvider()) { entry in
            SkyWardenComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Sky Warden")
        .description("Temperature with the source-agreement confidence ring.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Family router

struct SkyWardenComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SkyWardenEntry

    var body: some View {
        switch family {
        case .accessoryCircular:    CircularView(entry: entry)
        case .accessoryCorner:      CornerView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        case .accessoryInline:      InlineView(entry: entry)
        default:                    CircularView(entry: entry)
        }
    }

    /// Confidence is the fill; disagreement recolours it. The one idea that makes
    /// Sky Warden Sky Warden, on a watch face.
    private static func tint(_ e: SkyWardenEntry) -> Color { e.hasDisagreement ? .orange : .green }
}

// MARK: - Circular: temp + rain inside a COMFORT gauge

private struct CircularView: View {
    let entry: SkyWardenEntry
    var body: some View {
        // The ring is the overall comfort aggregate — how nice it is out — and its
        // red→amber→green fill colour reflects that too. The centre carries the
        // temperature with the rain chance under it.
        Gauge(value: Double(entry.comfortPercent), in: 0...100) {
            EmptyView()
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text("\(entry.temperature)°").font(.system(size: 16, weight: .semibold, design: .rounded))
                HStack(spacing: 1) {
                    Image(systemName: "drop.fill").font(.system(size: 6))
                    Text("\(entry.rainPercent)%").font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.red, .yellow, .green]))
        .widgetAccentable()
    }
}

// MARK: - Corner: temp with a curved confidence gauge

private struct CornerView: View {
    let entry: SkyWardenEntry
    var body: some View {
        Text("\(entry.temperature)°")
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: Double(entry.confidencePercent), in: 0...100) { EmptyView() }
                    .tint(entry.hasDisagreement ? .orange : .green)
            }
    }
}

// MARK: - Rectangular: the full glance

private struct RectangularView: View {
    let entry: SkyWardenEntry
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: entry.condition)
                    Text("\(entry.temperature)°").font(.system(size: 22, weight: .medium, design: .rounded))
                }
                Text(entry.hasDisagreement ? "⚠︎ sources vary · \(entry.confidencePercent)%"
                                           : "\(entry.confidencePercent)% agree")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.hasDisagreement ? .orange : .secondary)
                if let tide = entry.nextTide {
                    Text("🌊 \(tide)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Inline: one line on the face

private struct InlineView: View {
    let entry: SkyWardenEntry
    var body: some View {
        if entry.hasDisagreement {
            Text("\(entry.temperature)° · sources vary")
        } else {
            Text("\(entry.temperature)° · \(entry.rainPercent)% rain")
        }
    }
}
#endif
