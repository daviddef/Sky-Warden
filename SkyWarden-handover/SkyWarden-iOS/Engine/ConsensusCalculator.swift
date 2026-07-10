// SkyWarden — ConsensusCalculator
// Merges multiple WeatherReadings into a single ConsensusWeather

import Foundation

struct ConsensusCalculator {

    private let engine = DisagreementEngine()

    func calculate(from readings: [WeatherReading]) -> ConsensusWeather {
        precondition(!readings.isEmpty)

        let (disagreements, confidence, worst) = engine.analyse(readings)

        let temps     = readings.map(\.temperature)
        let rains     = readings.map(\.rainProbability)
        let winds     = readings.map(\.windSpeed)
        let humidity  = readings.map(\.humidity)
        // Only average sources that actually measure UV (BOM reports none).
        let uvValues  = readings.compactMap(\.uvIndex)

        let consensusTemp  = trimmedMean(temps)
        let consensusRain  = mean(rains)
        let consensusWind  = median(winds)
        let consensusHumid = mean(humidity)
        let consensusUV    = mean(uvValues)
        let consensusCond  = pluralityCondition(readings.map(\.condition))
        let consensusDir   = circularMeanDirection(readings.map(\.windDirection))
        let consensusFeels = trimmedMean(readings.map(\.feelsLike))

        // Ranges for UI when sources differ
        let tempRange = temps.count > 1 ? (temps.min()!...temps.max()!) : nil
        let rainRange = rains.count > 1 ? (rains.min()!...rains.max()!) : nil
        let windRange = winds.count > 1 ? (winds.min()!...winds.max()!) : nil

        // Merge hourly (use most detailed source, flag hours where sources diverge)
        let hourly = mergeHourly(readings)

        // Merge daily
        let daily = mergeDaily(readings)

        return ConsensusWeather(
            sources:          readings.map(\.source),
            fetchedAt:        Date(),
            confidence:       confidence,
            disagreements:    disagreements,
            worstSeverity:    worst,
            temperature:      consensusTemp,
            feelsLike:        consensusFeels,
            rainProbability:  consensusRain,
            rainAmount:       mean(readings.map(\.rainAmount)),
            windSpeed:        consensusWind,
            windDirection:    consensusDir,
            humidity:         consensusHumid,
            uvIndex:          consensusUV,
            condition:        consensusCond,
            temperatureRange: tempRange,
            rainRange:        rainRange,
            windRange:        windRange,
            hourlyForecast:   hourly,
            dailyForecast:    daily,
            rawReadings:      readings
        )
    }

    // MARK: - Statistical helpers

    /// Trimmed mean: drops single outlier if ≥3 values, otherwise plain mean
    private func trimmedMean(_ values: [Double]) -> Double {
        guard values.count >= 3 else { return mean(values) }
        let sorted = values.sorted()
        let trimmed = Array(sorted.dropFirst().dropLast())
        return mean(trimmed)
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// Circular mean for wind direction (handles 350°/10° = 0°, not 180°)
    private func circularMeanDirection(_ degrees: [Int]) -> Int {
        guard !degrees.isEmpty else { return 0 }
        let radians = degrees.map { Double($0) * .pi / 180 }
        let sinMean = radians.map { sin($0) }.reduce(0, +) / Double(radians.count)
        let cosMean = radians.map { cos($0) }.reduce(0, +) / Double(radians.count)
        let angle = atan2(sinMean, cosMean) * 180 / .pi
        return Int((angle + 360).truncatingRemainder(dividingBy: 360))
    }

    /// Plurality: returns the most common condition category
    private func pluralityCondition(_ conditions: [WeatherCondition]) -> WeatherCondition {
        let counts = conditions.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? conditions[0]
    }

    // MARK: - Forecast merging

    private func mergeHourly(_ readings: [WeatherReading]) -> [ConsensusHourly] {
        // Use Open-Meteo as primary (most detailed hourly), flag hours where sources differ
        guard let primary = readings.first(where: { $0.source == .openMeteo })
                         ?? readings.first else { return [] }

        return primary.hourlyForecast.map { hour in
            let otherReadings = readings.filter { $0.source != primary.source }
            let hasDisagreement = otherReadings.contains { other in
                // Compare with same-hour data from other sources
                if let match = other.hourlyForecast.min(by: {
                    abs($0.time.timeIntervalSince(hour.time)) <
                    abs($1.time.timeIntervalSince(hour.time))
                }) {
                    return abs(match.temperature - hour.temperature) > 2 ||
                           abs(match.rainProbability - hour.rainProbability) > 15
                }
                return false
            }
            return ConsensusHourly(
                time:             hour.time,
                temperature:      hour.temperature,
                rainProbability:  hour.rainProbability,
                condition:        hour.condition,
                windSpeed:        hour.windSpeed,
                hasDisagreement:  hasDisagreement
            )
        }
    }

    private func mergeDaily(_ readings: [WeatherReading]) -> [ConsensusDaily] {
        guard let primary = readings.first(where: { $0.source == .openMeteo })
                         ?? readings.first else { return [] }

        return primary.dailyForecast.enumerated().map { (index, day) in
            let otherTemps  = readings.compactMap { $0.dailyForecast[safe: index]?.tempMax }
            let otherRains  = readings.compactMap { $0.dailyForecast[safe: index]?.rainProbability }
            let hasDisagreement = {
                if otherTemps.count > 1, let spread = (otherTemps.max().map { $0 - (otherTemps.min() ?? $0) }) {
                    if spread > 3 { return true }
                }
                if otherRains.count > 1, let spread = (otherRains.max().map { $0 - (otherRains.min() ?? $0) }) {
                    if spread > 20 { return true }
                }
                return false
            }()

            return ConsensusDaily(
                date:             day.date,
                tempMax:          day.tempMax,
                tempMin:          day.tempMin,
                rainProbability:  day.rainProbability,
                windSpeed:        day.windSpeed,
                condition:        day.condition,
                hasDisagreement:  hasDisagreement
            )
        }
    }
}

// MARK: - Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
