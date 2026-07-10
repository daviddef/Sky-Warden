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

    private func key(_ location: CLLocation) -> String {
        DiskCache.gridKey("skill", location, precision: Self.gridPrecision)
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
    @discardableResult
    func update(with readings: [WeatherReading], location: CLLocation, now: Date = Date()) -> Int {
        queue.sync {
            let k = key(location)
            var t = loaded[k] ?? DiskCache.loadDurable(SkillTable.self, key: k) ?? SkillTable()

            var scored = 0
            if let truth = SkillTable.observation(from: readings) {
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
    func allWeights(among sources: [WeatherSource], location: CLLocation) -> [SkillMetric: [WeatherSource: Double]] {
        let ranked = sources.filter { $0.kind == .forecast }
        let t = table(for: location)
        var out: [SkillMetric: [WeatherSource: Double]] = [:]
        for m in SkillMetric.allCases {
            if let w = t.weights(for: m, among: ranked) { out[m] = w }
        }
        return out
    }

    func reset() {
        queue.sync {
            loaded.removeAll()
            DiskCache.clearDurable()
        }
    }
}
