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
    private let sourceOrder: [WeatherSource] = WeatherSource.allCases

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

        // Weight the merge by each source's proven skill so far. This reads the
        // ledger as it already stands — this refresh's scoring (below) applies to
        // the NEXT merge — so nothing here waits on the network.
        let weights = SkillLedger.shared.allWeights(among: readings.map(\.source), location: location)
        let consensus = calculator.calculate(from: readings, skillWeights: weights)

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

        // Update the ledger AFTER the screen is up, off the critical path: score
        // what came true, file what's newly predicted. BOM is the truth in
        // Australia; anywhere else a nearby airport METAR fills the gap (fetched
        // only when there's no BOM), so the accuracy moat isn't Australia-only.
        Task { [readings] in
            var truth: [SkillMetric: Double]?
            if !readings.contains(where: { $0.source.kind == .observation }) {
                truth = await METARService().observation(near: location)?.truth
            }
            SkillLedger.shared.update(with: readings, truth: truth, location: location)
        }
    }

    // MARK: - Parallel weather fetch with TaskGroup
    private func fetchAllWeather(location: CLLocation) async -> ([WeatherReading], [WeatherSource]) {
        var readings: [WeatherReading] = []
        var failed:   [WeatherSource]  = []

        await withTaskGroup(of: ([WeatherSource], Result<[WeatherReading], Error>).self) { group in
            // One request returns all six numerical models.
            group.addTask { [openMeteo, sourceTimeout] in
                await Self.tagged(WeatherSource.models, sourceTimeout) { try await openMeteo.fetch(location: location) }
            }
            group.addTask { [openWeather, sourceTimeout] in
                await Self.tagged([.openWeather], sourceTimeout) { [try await openWeather.fetch(location: location)] }
            }
            group.addTask { [weatherKit, sourceTimeout] in
                await Self.tagged([.weatherKit], sourceTimeout) { [try await weatherKit.fetch(location: location)] }
            }
            group.addTask { [bom, sourceTimeout] in
                await Self.tagged([.bom], sourceTimeout) { [try await bom.fetch(location: location)] }
            }

            for await (sources, result) in group {
                switch result {
                case .success(let newReadings):
                    readings.append(contentsOf: newReadings)
                case .failure(let error):
                    // A source that doesn't cover this location isn't "unavailable" —
                    // don't surface BOM as broken when the user is in Paris.
                    if case ServiceError.notApplicable = error { continue }
                    failed.append(contentsOf: sources)
                    print("⚠️ \(sources.map(\.short).joined(separator: ",")) fetch failed: \(error.localizedDescription)")
                }
            }
        }

        // Stable ordering for consistent UI
        readings.sort { rank($0.source) < rank($1.source) }
        failed.sort   { rank($0)        < rank($1) }
        return (readings, failed)
    }

    private func rank(_ s: WeatherSource) -> Int { sourceOrder.firstIndex(of: s) ?? .max }

    /// Runs a provider fetch with a timeout, tagged with the sources it supplies.
    /// A provider may yield several sources (Open-Meteo returns six models).
    private static func tagged(
        _ sources: [WeatherSource],
        _ timeout: TimeInterval,
        _ operation: @escaping () async throws -> [WeatherReading]
    ) async -> ([WeatherSource], Result<[WeatherReading], Error>) {
        do    { return (sources, .success(try await withTimeout(timeout, operation))) }
        catch { return (sources, .failure(error)) }
    }

    // MARK: - Tides fetch
    /// Called on every refresh — including forced ones and background wakes —
    /// but WorldTidesService caches on disk for 6 h, so this is nearly always
    /// free. `force` deliberately does not reach the tide cache: forcing a
    /// weather refresh should not spend a paid tide credit.
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
