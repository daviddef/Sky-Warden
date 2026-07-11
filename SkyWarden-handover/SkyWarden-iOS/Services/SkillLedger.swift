// Sky Warden — the skill ledger
//
// Owns persistence and the per-location split for SkillTable. Being accurate in
// Brisbane says nothing about being accurate in Perth, so each ~50 km grid cell
// keeps its own scoreboard.
//
// Stored durably, not in Caches: this data takes days of real use to accumulate
// and no server can hand it back.

import Foundation
import CoreLocation

final class SkillLedger {
    static let shared = SkillLedger()

    /// Coarser than the response cache. A forecast model's skill varies over
    /// weather-system scales, not suburbs, and a fine grid would scatter samples
    /// across cells and never reach `minSamples`.
    private static let gridPrecision = 0.5      // ≈ 55 km

    private var loaded: [String: SkillTable] = [:]
    private let queue = DispatchQueue(label: "skywarden.skill-ledger")

    /// The fleet's pooled scoreboard for a grid, as last fetched from the server,
    /// keyed `source|metric`. Empty until `syncPooled` succeeds — and if it never
    /// does (proxy off, offline, endpoint absent), weighting silently falls back
    /// to this device's own samples, exactly as before pooling existed.
    private var pooled: [String: [String: SkillStat]] = [:]

    /// A snapshot of what this device has already sent to the pool, per grid, so
    /// the next contribution sends only the delta and never double-counts. Stored
    /// durably alongside the ledger — losing it would re-send old samples.
    private var contributed: [String: [String: SkillStat]] = [:]

    private func key(_ location: CLLocation) -> String {
        DiskCache.gridKey("skill", location, precision: Self.gridPrecision)
    }

    /// Durable key for the "already contributed" snapshot of a grid.
    private func sentKey(_ cell: String) -> String { cell + "|sent" }

    private func contributedSnapshot(_ cell: String) -> [String: SkillStat] {
        if let s = contributed[cell] { return s }
        let s = DiskCache.loadDurable([String: SkillStat].self, key: sentKey(cell)) ?? [:]
        contributed[cell] = s
        return s
    }

    func table(for location: CLLocation) -> SkillTable {
        queue.sync {
            let k = key(location)
            if let t = loaded[k] { return t }
            let t = DiskCache.loadDurable(SkillTable.self, key: k) ?? SkillTable()
            loaded[k] = t
            return t
        }
    }

    /// Score what has come true, then file what's newly predicted.
    ///
    /// What actually stops a source being scored against the *same* refresh's
    /// observation — which would hand it a free perfect record for "predicting"
    /// the present — is the one-hour minimum horizon in `SkillTable.forecasts`,
    /// not this ordering. A forecast for now+1h sits well outside the ±30 min
    /// scoring window. The order here is merely tidy.
    /// `truth` overrides the in-readings observation — used to pass a METAR
    /// reading outside Australia, where BOM (the only in-readings observation)
    /// isn't present.
    @discardableResult
    func update(with readings: [WeatherReading], truth explicitTruth: [SkillMetric: Double]? = nil,
                location: CLLocation, now: Date = Date()) -> Int {
        queue.sync {
            let k = key(location)
            var t = loaded[k] ?? DiskCache.loadDurable(SkillTable.self, key: k) ?? SkillTable()

            var scored = 0
            if let truth = SkillTable.observation(from: readings) ?? explicitTruth {
                scored = t.score(observed: truth, at: now)
            }
            t.record(SkillTable.forecasts(from: readings, now: now), now: now)

            loaded[k] = t
            DiskCache.saveDurable(t, key: k)
            return scored
        }
    }

    /// Weights for the merge, or nil when the ledger hasn't earned an opinion.
    func weights(for metric: SkillMetric, among sources: [WeatherSource],
                 location: CLLocation) -> [WeatherSource: Double]? {
        table(for: location).weights(for: metric, among: sources)
    }

    /// Everything the consensus needs, in one lookup.
    ///
    /// Only forecast sources are ranked. Passing the observation in would poison
    /// the guard — BOM files no forecasts, so it can never reach `minSamples`,
    /// and `weights` would return nil forever. The accuracy loop would run,
    /// accumulate, display a scoreboard, and never once move the consensus.
    ///
    /// Weighting runs over the *effective* scoreboard: the pooled fleet stats plus
    /// whatever this device has measured but not yet contributed. With an empty
    /// pool that reduces to this device's own table, so behaviour is unchanged
    /// until the pool has something to add; with a warm pool a new user inherits
    /// the fleet's proven weights on their first refresh.
    func allWeights(among sources: [WeatherSource], location: CLLocation) -> [SkillMetric: [WeatherSource: Double]] {
        let ranked = sources.filter { $0.kind == .forecast }
        return queue.sync {
            let cell = key(location)
            let local = (loaded[cell] ?? DiskCache.loadDurable(SkillTable.self, key: cell) ?? SkillTable()).scoreboard
            let unsent = SkillTable.delta(current: local, contributed: contributedSnapshot(cell))
            let effective = SkillTable.mergeScoreboards(pooled[cell] ?? [:], unsent)

            var out: [SkillMetric: [WeatherSource: Double]] = [:]
            for m in SkillMetric.allCases {
                if let w = SkillTable.weights(for: m, among: ranked, stats: effective) { out[m] = w }
            }
            return out
        }
    }

    // MARK: - Pooling across devices

    /// Pull the fleet's scoreboard for this grid into `pooled`. Best-effort: any
    /// failure (proxy off, offline, endpoint not yet deployed) leaves the pool
    /// untouched and weighting falls back to local samples. Cheap enough to run in
    /// parallel with the weather fetch, so it adds no latency to a refresh.
    func syncPooled(location: CLLocation) async {
        guard let base = WeatherProxy.ledgerURL else { return }
        let cell = key(location)
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "grid", value: cell)]
        guard let url = comps?.url else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        if !WeatherProxy.appToken.isEmpty {
            req.setValue(WeatherProxy.appToken, forHTTPHeaderField: "x-skywarden-app")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(PooledResponse.self, from: data) else { return }

        queue.sync { pooled[cell] = decoded.stats }
    }

    /// Send this device's newly-scored samples to the pool. Contributes only the
    /// delta since the last successful send, so the pool never hears the same
    /// sample twice. Best-effort; on success it records the new high-water mark and
    /// folds the delta into the local pooled view so this device sees its own
    /// contribution before the next sync.
    func contribute(location: CLLocation) async {
        guard let base = WeatherProxy.ledgerURL else { return }
        let cell = key(location)

        let (snapshot, delta): ([String: SkillStat], [String: SkillStat]) = queue.sync {
            let local = (loaded[cell] ?? DiskCache.loadDurable(SkillTable.self, key: cell) ?? SkillTable()).scoreboard
            return (local, SkillTable.delta(current: local, contributed: contributedSnapshot(cell)))
        }
        guard !delta.isEmpty else { return }

        let entries = delta.map { (k, s) -> PooledEntry in
            let parts = k.split(separator: "|", maxSplits: 1)
            return PooledEntry(source: String(parts.first ?? ""),
                               metric: String(parts.count > 1 ? parts[1] : ""),
                               count: s.count, sumAbsError: s.sumAbsError)
        }

        var req = URLRequest(url: base)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if !WeatherProxy.appToken.isEmpty {
            req.setValue(WeatherProxy.appToken, forHTTPHeaderField: "x-skywarden-app")
        }
        req.httpBody = try? JSONEncoder().encode(PooledContribution(grid: cell, entries: entries))
        guard req.httpBody != nil,
              let (_, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return }

        queue.sync {
            contributed[cell] = snapshot
            DiskCache.saveDurable(snapshot, key: sentKey(cell))
            pooled[cell] = SkillTable.mergeScoreboards(pooled[cell] ?? [:], delta)
        }
    }

    func reset() {
        queue.sync {
            loaded.removeAll()
            pooled.removeAll()
            contributed.removeAll()
            DiskCache.clearDurable()
        }
    }
}

// MARK: - Pool wire format

/// GET …/ledger?grid=… → { grid, stats: { "source|metric": {count, sumAbsError} } }
private struct PooledResponse: Decodable { let stats: [String: SkillStat] }
private struct PooledEntry: Encodable {
    let source: String; let metric: String; let count: Int; let sumAbsError: Double
}
private struct PooledContribution: Encodable { let grid: String; let entries: [PooledEntry] }
