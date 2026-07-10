// SkyWarden — WeatherAggregator
// Orchestrates all source fetches in parallel via Swift Concurrency.
// Each source is bounded by a 6-second timeout; if a source fails or times out
// the aggregator degrades gracefully rather than failing the whole screen.

import Foundation
import CoreLocation

@MainActor
final class WeatherAggregator: ObservableObject {

    // MARK: - Published state
    @Published var fetchState: FetchState = .idle
    @Published var tideDay: TideDay?
    @Published var moonData: MoonData?
    @Published var failedSources: [WeatherSource] = []

    // MARK: - Dependencies
    private let openMeteo    = OpenMeteoService()
    private let openWeather  = OpenWeatherService()
    private let weatherKit   = WeatherKitService()
    private let bom          = BOMService()
    private let worldTides   = WorldTidesService()
    private let moonService  = MoonService()
    private let calculator   = ConsensusCalculator()

    // MARK: - Tunables
    private let sourceTimeout: TimeInterval = 6   // per-source deadline

    // MARK: - Cache
    private var lastLocation: CLLocation?
    private var lastFetch:    Date?
    private let cacheSeconds: TimeInterval = 600  // 10 minutes

    // Display order for readings and failed-source chips
    private let sourceOrder: [WeatherSource] = [.openMeteo, .openWeather, .weatherKit, .bom]

    // MARK: - Main fetch
    func refresh(location: CLLocation, force: Bool = false) async {
        // Debounce unless forced
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < cacheSeconds,
           let lastLoc = lastLocation, location.distance(from: lastLoc) < 1000 {
            return
        }

        fetchState = .loading

        // Parallel fetch all weather sources
        async let weatherReadings = fetchAllWeather(location: location)
        async let tides           = fetchTides(location: location)
        let moon                  = moonService.moonData()

        let (readings, failed) = await weatherReadings
        let tideResult = await tides

        // Store non-weather data
        self.moonData = moon
        self.tideDay  = tideResult
        self.failedSources = failed

        guard !readings.isEmpty else {
            fetchState = .failed(AggregatorError.noSourcesAvailable)
            return
        }

        let consensus = calculator.calculate(from: readings)

        lastFetch    = Date()
        lastLocation = location

        // Persist coordinate so the background task can refresh headlessly.
        UserDefaults.skyWardenShared?.storeLastCoordinate(
            latitude:  location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        // Share the latest snapshot with the Watch complication.
        publishToWatch(consensus)

        if failed.isEmpty {
            fetchState = .loaded(consensus)
        } else {
            fetchState = .partialLoad(consensus, failed)
        }
    }

    // MARK: - Parallel weather fetch with TaskGroup
    private func fetchAllWeather(location: CLLocation) async -> ([WeatherReading], [WeatherSource]) {
        var readings: [WeatherReading] = []
        var failed:   [WeatherSource]  = []

        await withTaskGroup(of: (WeatherSource, Result<WeatherReading, Error>).self) { group in
            group.addTask { [openMeteo, sourceTimeout] in
                await Self.tagged(.openMeteo, sourceTimeout) { try await openMeteo.fetch(location: location) }
            }
            group.addTask { [openWeather, sourceTimeout] in
                await Self.tagged(.openWeather, sourceTimeout) { try await openWeather.fetch(location: location) }
            }
            group.addTask { [weatherKit, sourceTimeout] in
                await Self.tagged(.weatherKit, sourceTimeout) { try await weatherKit.fetch(location: location) }
            }
            group.addTask { [bom, sourceTimeout] in
                await Self.tagged(.bom, sourceTimeout) { try await bom.fetch(location: location) }
            }

            for await (source, result) in group {
                switch result {
                case .success(let reading):
                    readings.append(reading)
                case .failure(let error):
                    failed.append(source)
                    print("⚠️ \(source.rawValue) fetch failed: \(error.localizedDescription)")
                }
            }
        }

        // Stable ordering for consistent UI
        readings.sort { rank($0.source) < rank($1.source) }
        failed.sort   { rank($0)        < rank($1) }
        return (readings, failed)
    }

    private func rank(_ s: WeatherSource) -> Int { sourceOrder.firstIndex(of: s) ?? .max }

    /// Runs a source fetch with a timeout and tags the result with its source.
    private static func tagged(
        _ source: WeatherSource,
        _ timeout: TimeInterval,
        _ operation: @escaping () async throws -> WeatherReading
    ) async -> (WeatherSource, Result<WeatherReading, Error>) {
        do    { return (source, .success(try await withTimeout(timeout, operation))) }
        catch { return (source, .failure(error)) }
    }

    // MARK: - Tides fetch
    private func fetchTides(location: CLLocation) async -> TideDay? {
        do {
            return try await Self.withTimeout(sourceTimeout) { try await self.worldTides.fetch(location: location) }
        } catch {
            print("⚠️ Tides fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Watch data sharing
    /// Encodes the current consensus into the App Group so the Watch complication
    /// can render real data. No-op if the App Group entitlement is unavailable.
    private func publishToWatch(_ consensus: ConsensusWeather) {
        guard let defaults = UserDefaults.skyWardenShared else { return }

        let nextTide: String? = tideDay?.events
            .first(where: { $0.time > Date() })
            .map { "\($0.type.rawValue) \($0.heightDisplay) @ \($0.timeDisplay)" }

        let snapshot = StoredWeatherData(
            fetchedAt:         consensus.fetchedAt,
            temperature:       Int(consensus.temperature.rounded()),
            conditionSFSymbol: consensus.condition.icon,
            conditionEmoji:    consensus.condition.emoji,
            rainPercent:       Int(consensus.rainProbability.rounded()),
            confidencePercent: Int((consensus.confidence * 100).rounded()),
            hasDisagreement:   consensus.hasDisagreements,
            nextTide:          nextTide,
            moonEmoji:         moonData?.phase.emoji ?? "🌙",
            moonPhase:         moonData?.phase.rawValue ?? ""
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: SkyWardenID.latestWeatherKey)
        }
    }

    // MARK: - Background refresh support
    /// Called by BGAppRefreshTask in AppDelegate
    func backgroundRefresh(location: CLLocation) async {
        await refresh(location: location, force: true)
    }
}

// MARK: - Timeout helper
struct TimeoutError: LocalizedError {
    var errorDescription: String? { "Source timed out" }
}

/// Races an async operation against a deadline. Whichever finishes first wins;
/// the loser is cancelled.
func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping () async throws -> T
) async throws -> T {
    try await WeatherAggregator.withTimeout(seconds, operation)
}

extension WeatherAggregator {
    static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Errors
enum AggregatorError: LocalizedError {
    case noSourcesAvailable
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .noSourcesAvailable: return "No weather sources responded. Check your connection."
        case .locationUnavailable: return "Location unavailable. Please enable Location Services."
        }
    }
}
