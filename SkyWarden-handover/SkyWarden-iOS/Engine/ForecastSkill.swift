// Sky Warden — forecast skill tracking
//
// The moat. Every rival either picks one source or makes you switch manually;
// none of them tell you which source is actually right *where you are*. To do
// that we have to remember what each source predicted, wait, and then check.
//
// How it works:
//   1. On each refresh we file what every source predicts for a few hours ahead.
//   2. Later, when that hour arrives, the observation (BOM's thermometer) scores
//      the pending forecasts and we accumulate mean absolute error per source.
//   3. Once a source has enough scored samples, the consensus weights it by
//      1/(MAE + ε) instead of counting every source equally.
//
// Deliberate constraints, because a wrong accuracy claim is worse than none:
//   · Truth is an *observation*, never another forecast. Scoring forecasts
//     against the consensus would just reward agreeing with the crowd.
//   · A source is never scored against itself.
//   · Weighting only engages when EVERY candidate source has enough samples,
//     so a well-measured source can't quietly dominate a newly-added one.
//   · Weights are clamped, so one lucky source cannot swamp the rest.
//   · Skill is per location grid: being good in Brisbane says nothing about
//     being good in Perth.
//
// This file is pure and synchronous so it can be tested without a network,
// a clock, or a simulator.

import Foundation

// MARK: - What we can actually check

/// Only metrics an observation station reports. Rain *probability* can never be
/// scored — a 30% chance that didn't happen was not necessarily wrong.
/// Humidity is deliberately absent: the models don't publish it hourly, so a
/// humidity forecast could never be filed, and a metric that can never be scored
/// would just be a column of dashes.
enum SkillMetric: String, Codable, CaseIterable {
    case temp, wind

    /// Errors are averaged per metric, so they never need to share a unit.
    var unit: String {
        switch self {
        case .temp: "°"
        case .wind: " km/h"
        }
    }

    func value(of r: WeatherReading) -> Double {
        switch self {
        case .temp: r.temperature
        case .wind: r.windSpeed
        }
    }

    func value(of h: HourlyReading) -> Double {
        switch self {
        case .temp: h.temperature
        case .wind: h.windSpeed
        }
    }
}

/// A prediction, filed and waiting for the hour it describes to arrive.
struct PendingForecast: Codable, Equatable {
    let source: String          // WeatherSource.rawValue
    let metric: SkillMetric
    let targetTime: Date
    let predicted: Double
}

struct SkillStat: Codable, Equatable {
    var count: Int = 0
    var sumAbsError: Double = 0

    /// Mean absolute error, in the metric's own unit.
    var mae: Double { count == 0 ? .infinity : sumAbsError / Double(count) }
}

// MARK: - The table

struct SkillTable: Codable, Equatable {

    /// Enough samples before a source's error is allowed to move the consensus.
    /// Twenty hourly checks is roughly a day of use — small enough to be
    /// reachable, large enough that one freak afternoon doesn't set the weights.
    static let minSamples = 20

    /// How close a pending forecast's target hour must be to "now" to be scored.
    static let matchTolerance: TimeInterval = 30 * 60

    /// Keeps the file bounded: 9 sources × 3 metrics × a day of horizons.
    static let maxPending = 600

    private(set) var pending: [PendingForecast] = []
    private(set) var stats: [String: SkillStat] = [:]

    private static func key(_ source: String, _ metric: SkillMetric) -> String {
        "\(source)|\(metric.rawValue)"
    }

    // MARK: File a prediction

    /// Files predictions for later scoring. Anything already in the past is
    /// ignored — we can only score a forecast we made *before* the fact.
    mutating func record(_ forecasts: [PendingForecast], now: Date) {
        for f in forecasts where f.targetTime > now {
            // One prediction per (source, metric, hour): a later refresh
            // supersedes an earlier one for the same target.
            if let i = pending.firstIndex(where: {
                $0.source == f.source && $0.metric == f.metric
                    && abs($0.targetTime.timeIntervalSince(f.targetTime)) < 60
            }) {
                pending[i] = f
            } else {
                pending.append(f)
            }
        }
        if pending.count > Self.maxPending {
            pending.sort { $0.targetTime < $1.targetTime }
            pending.removeFirst(pending.count - Self.maxPending)
        }
    }

    /// Everything `readings` predicts for the coming hours, as filable rows.
    /// The observation source is skipped: BOM reports what happened, so it makes
    /// no forecast to score.
    static func forecasts(from readings: [WeatherReading], now: Date,
                          horizons: [TimeInterval] = [3600, 3 * 3600, 6 * 3600]) -> [PendingForecast] {
        var out: [PendingForecast] = []
        for r in readings where r.source.kind == .forecast {
            for h in horizons {
                let target = now.addingTimeInterval(h)
                guard let hour = r.hourlyForecast.min(by: {
                    abs($0.time.timeIntervalSince(target)) < abs($1.time.timeIntervalSince(target))
                }), abs(hour.time.timeIntervalSince(target)) <= matchTolerance else { continue }

                for metric in SkillMetric.allCases {
                    out.append(PendingForecast(source: r.source.rawValue, metric: metric,
                                               targetTime: hour.time, predicted: metric.value(of: hour)))
                }
            }
        }
        return out
    }

    // MARK: Score against truth

    /// Scores every pending forecast whose hour has arrived, using an
    /// observation as the truth. Returns how many were scored.
    @discardableResult
    mutating func score(observed: [SkillMetric: Double], at now: Date) -> Int {
        var scored = 0
        var survivors: [PendingForecast] = []

        for f in pending {
            let age = now.timeIntervalSince(f.targetTime)

            // Never score early. The window is one-sided: a forecast for 11:00
            // must not be graded against the 10:35 thermometer just because that
            // is within half an hour — it would be marked wrong for correctly
            // predicting a temperature that hadn't happened yet, and consumed,
            // so the real 11:00 reading would never see it.
            if age < 0 {                             // its hour hasn't come yet
                survivors.append(f)
            } else if age > Self.matchTolerance {    // its hour passed unscored — the app
                continue                             // was closed. Drop it; scoring it now
                                                     // would compare noon's forecast to
                                                     // this evening's thermometer.
            } else if let truth = observed[f.metric] {
                var stat = stats[Self.key(f.source, f.metric)] ?? SkillStat()
                stat.count += 1
                stat.sumAbsError += abs(f.predicted - truth)
                stats[Self.key(f.source, f.metric)] = stat
                scored += 1
            } else {
                survivors.append(f)                  // still in window; the observation
            }                                        // may arrive on the next refresh
        }
        pending = survivors
        return scored
    }

    /// The truth, from an observation reading. `nil` when the source is a forecast.
    static func observation(from readings: [WeatherReading]) -> [SkillMetric: Double]? {
        guard let obs = readings.first(where: { $0.source.kind == .observation }) else { return nil }
        return Dictionary(uniqueKeysWithValues: SkillMetric.allCases.map { ($0, $0.value(of: obs)) })
    }

    // MARK: Read the scoreboard

    func mae(_ source: WeatherSource, _ metric: SkillMetric) -> Double? {
        guard let s = stats[Self.key(source.rawValue, metric)], s.count > 0 else { return nil }
        return s.mae
    }

    func samples(_ source: WeatherSource, _ metric: SkillMetric) -> Int {
        stats[Self.key(source.rawValue, metric)]?.count ?? 0
    }

    /// No source may carry more than twice an equal share. Two, not three:
    /// with three candidates a 3× cap equals 1.0 and can never bind, which is
    /// how a source with a near-perfect record ended up holding 99.3% of the
    /// weight — the exact failure the cap exists to prevent.
    static let weightCapMultiple = 2.0

    /// Normalised weights, or `nil` when we haven't earned the right to weight.
    ///
    /// Every candidate must clear `minSamples`, otherwise a source we happen to
    /// have measured a lot would outrank one we simply haven't measured yet —
    /// which is a statement about our data, not about the forecast.
    func weights(for metric: SkillMetric, among sources: [WeatherSource],
                 minSamples: Int = SkillTable.minSamples) -> [WeatherSource: Double]? {
        guard sources.count >= 2 else { return nil }
        var raw: [WeatherSource: Double] = [:]
        for s in sources {
            guard samples(s, metric) >= minSamples, let e = mae(s, metric) else { return nil }
            raw[s] = 1 / (e + 0.1)     // ε keeps a perfect record from dividing by zero
        }
        let total = raw.values.reduce(0, +)
        guard total > 0 else { return nil }

        var w = raw.mapValues { $0 / total }
        let cap = Self.weightCapMultiple / Double(sources.count)

        // Water-filling. Capping once and renormalising doesn't work: the capped
        // source shrinks back below its cap and keeps almost all of its share.
        // Spill the excess into the uncapped sources, in proportion, and repeat
        // until nobody is over. Bounded: each pass caps at least one source.
        for _ in 0..<sources.count {
            let over = w.filter { $0.value > cap + 1e-9 }
            guard !over.isEmpty else { break }
            let excess = over.values.reduce(0) { $0 + ($1 - cap) }
            for k in over.keys { w[k] = cap }

            let under = w.filter { $0.value < cap - 1e-9 }
            let underTotal = under.values.reduce(0, +)
            guard underTotal > 0 else { break }   // everyone is at the cap: already uniform
            for (k, v) in under { w[k] = v + excess * (v / underTotal) }
        }
        return w
    }
}

// MARK: - Weighted merge

/// Trims the extremes by value (as before), then averages the survivors weighted
/// by proven skill. With no weights this is exactly the old trimmed mean, so the
/// consensus is unchanged until the ledger has actually earned an opinion.
func weightedTrimmedMean(_ pairs: [(source: WeatherSource, value: Double)],
                         weights: [WeatherSource: Double]?) -> Double {
    guard !pairs.isEmpty else { return 0 }
    guard pairs.count >= 3 else {
        return pairs.map(\.value).reduce(0, +) / Double(pairs.count)
    }
    let sorted = pairs.sorted { $0.value < $1.value }
    let survivors = Array(sorted.dropFirst().dropLast())

    guard let weights, !weights.isEmpty else {
        return survivors.map(\.value).reduce(0, +) / Double(survivors.count)
    }
    // A source absent from `weights` — the observation, which files no forecasts,
    // or a model added yesterday — carries the MEAN of the supplied weights, not
    // zero. Zeroing it would silently drop BOM's thermometer out of the current
    // temperature the moment the ledger warmed up.
    let meanWeight = weights.values.reduce(0, +) / Double(weights.count)
    func weight(_ s: WeatherSource) -> Double { weights[s] ?? meanWeight }

    let total = survivors.reduce(0.0) { $0 + weight($1.source) }
    guard total > 0 else {
        return survivors.map(\.value).reduce(0, +) / Double(survivors.count)
    }
    return survivors.reduce(0.0) { $0 + $1.value * weight($1.source) } / total
}
