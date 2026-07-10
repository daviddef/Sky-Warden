// Sky Warden — engine tests
// Covers the comfort scoring curves, the consensus merge, and the source
// coverage/parsing rules that caused real bugs.

import XCTest
import CoreLocation
@testable import SkyWarden

// MARK: - Fixtures
private func reading(
    _ source: WeatherSource,
    temp: Double = 20,
    rain: Double = 10,
    wind: Double = 10,
    humidity: Double = 50,
    uv: Double? = 5,
    windDir: Int = 180
) -> WeatherReading {
    WeatherReading(
        source: source, fetchedAt: Date(),
        temperature: temp, feelsLike: temp,
        tempMin: nil, tempMax: nil,
        rainProbability: rain, rainAmount: 0,
        windSpeed: wind, windGust: nil, windDirection: windDir,
        humidity: humidity, uvIndex: uv, visibility: nil, pressure: nil,
        condition: .clearSky, hourlyForecast: [], dailyForecast: []
    )
}

// MARK: - Comfort scoring curves
final class ComfortModelTests: XCTestCase {

    func testTemperatureCurveIsIdealInTheComfortBand() {
        XCTAssertEqual(ComfortMetric.temp.score(25), 1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.temp.score(22), 1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.temp.score(28), 1.0, accuracy: 0.001)
    }

    func testTemperatureScoresNegativeWhenTooColdAndTooHot() {
        // Both extremes are uncomfortable — the curve is not linear.
        XCTAssertEqual(ComfortMetric.temp.score(15), -0.4, accuracy: 0.001)  // cool
        XCTAssertEqual(ComfortMetric.temp.score(36), -0.6, accuracy: 0.001)  // hot
        XCTAssertEqual(ComfortMetric.temp.score(5),  -1.0, accuracy: 0.001)  // clamped
        XCTAssertEqual(ComfortMetric.temp.score(45), -1.0, accuracy: 0.001)  // clamped
    }

    func testRainWindUVHumidityBoundaries() {
        XCTAssertEqual(ComfortMetric.rain.score(15), 1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.rain.score(100), -1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.wind.score(12), 1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.wind.score(60), -1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.uv.score(5), 0.0, accuracy: 0.001)     // borderline → needle straight up
        XCTAssertEqual(ComfortMetric.uv.score(2), 1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.humidity.score(50), 1.0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.humidity.score(95), -1.0, accuracy: 0.001)
    }

    func testScoreMapsToDialAngleLeftIsGood() {
        XCTAssertEqual(Comfort.angle(1.0), -90, accuracy: 0.001)   // comfortable → 9 o'clock
        XCTAssertEqual(Comfort.angle(0.0), 0, accuracy: 0.001)     // borderline  → 12 o'clock
        XCTAssertEqual(Comfort.angle(-1.0), 90, accuracy: 0.001)   // uncomfortable → 3 o'clock
    }

    func testOverallLabelThresholds() {
        XCTAssertEqual(Comfort.overallLabel(0.8), "Great")
        XCTAssertEqual(Comfort.overallLabel(0.3), "Good")
        XCTAssertEqual(Comfort.overallLabel(0.0), "OK")
        XCTAssertEqual(Comfort.overallLabel(-0.2), "Rough")
        XCTAssertEqual(Comfort.overallLabel(-0.9), "Poor")
    }

    func testSeasonIsHemisphereAware() {
        let july = DateComponents(calendar: .current, year: 2026, month: 7, day: 10).date!
        XCTAssertEqual(currentSeason(latitude: -27.5, date: july), "winter")  // Brisbane
        XCTAssertEqual(currentSeason(latitude: 51.5, date: july), "summer")   // London
        let january = DateComponents(calendar: .current, year: 2026, month: 1, day: 10).date!
        XCTAssertEqual(currentSeason(latitude: -27.5, date: january), "summer")
        XCTAssertEqual(currentSeason(latitude: 51.5, date: january), "winter")
    }
}

// MARK: - Consensus merging
final class ConsensusCalculatorTests: XCTestCase {

    func testTrimmedMeanDropsOutlierWhenThreeOrMoreSources() {
        // 20, 21, 40 → drop high and low, keep 21.
        let c = ConsensusCalculator().calculate(from: [
            reading(.openMeteo, temp: 20),
            reading(.openWeather, temp: 21),
            reading(.bom, temp: 40, uv: nil),
        ])
        XCTAssertEqual(c.temperature, 21, accuracy: 0.001)
    }

    func testPlainMeanWithTwoSources() {
        let c = ConsensusCalculator().calculate(from: [
            reading(.openMeteo, temp: 20),
            reading(.openWeather, temp: 24),
        ])
        XCTAssertEqual(c.temperature, 22, accuracy: 0.001)
    }

    /// Regression: BOM reports no UV. It used to send 0, which halved the
    /// consensus UV and raised a false "sources disagree" flag on the UV ring.
    func testSourceWithoutUVIsExcludedFromUVConsensus() {
        let c = ConsensusCalculator().calculate(from: [
            reading(.openMeteo, uv: 6),
            reading(.bom, uv: nil),
        ])
        XCTAssertEqual(c.uvIndex, 6, accuracy: 0.001, "BOM's absent UV must not drag the average to 3")
    }

    func testSourceWithoutUVProducesNoUVDisagreement() {
        let data = ComfortData(consensus: ConsensusCalculator().calculate(from: [
            reading(.openMeteo, uv: 6),
            reading(.bom, uv: nil),
        ]))
        let uvRing = data.ring(.uv)!
        XCTAssertEqual(uvRing.perSource.count, 1, "only sources that measure UV appear on the ring")
        XCTAssertEqual(uvRing.spread, 0, accuracy: 0.001)
        XCTAssertFalse(uvRing.hasFlag, "must not flag a disagreement against a source that reports nothing")
    }

    func testDisagreementIsFlaggedWhenSourcesActuallyDiffer() {
        let data = ComfortData(consensus: ConsensusCalculator().calculate(from: [
            reading(.openMeteo, temp: 18),
            reading(.openWeather, temp: 24),   // 6° spread, threshold 2 → major (≥2×)
        ]))
        let temp = data.ring(.temp)!
        XCTAssertEqual(temp.spread, 6, accuracy: 0.001)
        XCTAssertTrue(temp.hasFlag)
        XCTAssertTrue(temp.isMajor)
    }

    func testCircularMeanHandlesWrapAround() {
        // 350° and 10° should average to 0°, not 180°.
        let c = ConsensusCalculator().calculate(from: [
            reading(.openMeteo, windDir: 350),
            reading(.openWeather, windDir: 10),
        ])
        XCTAssertTrue(c.windDirection == 0 || c.windDirection == 360,
                      "got \(c.windDirection)")
    }
}

// MARK: - Display units
final class UnitsTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UnitKey.temperature)
        UserDefaults.standard.removeObject(forKey: UnitKey.wind)
        super.tearDown()
    }
    private func set(temp: TemperatureUnit) {
        UserDefaults.standard.set(temp.rawValue, forKey: UnitKey.temperature)
    }
    private func set(wind: WindUnit) {
        UserDefaults.standard.set(wind.rawValue, forKey: UnitKey.wind)
    }

    func testDefaultsAreMetric() {
        XCTAssertEqual(Units.temperature, .celsius)
        XCTAssertEqual(Units.wind, .kmh)
        XCTAssertEqual(Units.temp(20), 20, accuracy: 0.001)
    }

    func testAbsoluteTemperatureTakesTheOffset() {
        set(temp: .fahrenheit)
        XCTAssertEqual(Units.temp(0), 32, accuracy: 0.001)
        XCTAssertEqual(Units.temp(100), 212, accuracy: 0.001)
        XCTAssertEqual(Units.tempString(20), "68°")
    }

    /// A temperature *difference* scales by 9/5 and must NOT take the +32 offset.
    /// Getting this wrong would render a 3°C swing as "+37°F".
    func testTemperatureDeltaScalesWithoutOffset() {
        set(temp: .fahrenheit)
        XCTAssertEqual(Units.tempDelta(0), 0, accuracy: 0.001, "a zero difference stays zero")
        XCTAssertEqual(Units.tempDelta(5), 9, accuracy: 0.001)
        XCTAssertEqual(Units.tempDelta(-3), -5.4, accuracy: 0.001)
        XCTAssertEqual(Units.tempDeltaString(5), "+9°")
    }

    /// The "on this day" delta must equal the difference of the two numbers the
    /// user can see. Computing it from unrounded values showed 60° vs 72° as -13°.
    func testDisplayDeltaAgreesWithTheRoundedNumbersOnScreen() {
        for unit in TemperatureUnit.allCases {
            UserDefaults.standard.set(unit.rawValue, forKey: UnitKey.temperature)
            for (a, b) in [(15.3, 22.3), (17.4, 21.6), (0.0, -3.7), (30.2, 30.4)] {
                let shownA = Int(Units.temp(a).rounded())
                let shownB = Int(Units.temp(b).rounded())
                XCTAssertEqual(Units.displayTempDelta(a, b), shownA - shownB,
                               "\(unit.label): \(shownA) - \(shownB) must match the delta")
            }
        }
    }

    func testWindConversions() {
        set(wind: .mph)
        XCTAssertEqual(Units.windValue(100), 62.1371, accuracy: 0.001)
        XCTAssertEqual(Units.windString(100, withUnit: true), "62 mph")
        set(wind: .knots)
        XCTAssertEqual(Units.windValue(100), 53.9957, accuracy: 0.001)
        XCTAssertEqual(Units.windString(100, withUnit: true), "54 kn")
    }

    /// Scoring must stay metric regardless of what the user chose to see.
    func testUnitPreferenceDoesNotAffectComfortScoring() {
        let celsiusScore = ComfortMetric.temp.score(25)
        set(temp: .fahrenheit)
        XCTAssertEqual(ComfortMetric.temp.score(25), celsiusScore, accuracy: 0.001,
                       "score() takes °C — display units must not leak into the curves")
        XCTAssertEqual(ComfortMetric.temp.format(25), "77°", "…but display converts")
    }
}

// MARK: - BOM source rules
final class BOMServiceTests: XCTestCase {

    func testCoversAustraliaOnly() {
        XCTAssertTrue(BOMService.covers(CLLocation(latitude: -27.87, longitude: 153.35)))  // Hope Island
        XCTAssertTrue(BOMService.covers(CLLocation(latitude: -42.9, longitude: 147.3)))    // Hobart
        XCTAssertFalse(BOMService.covers(CLLocation(latitude: 48.85, longitude: 2.35)))    // Paris
        XCTAssertFalse(BOMService.covers(CLLocation(latitude: -36.8, longitude: 174.7)))   // Auckland
    }

    func testNearestStationForHopeIslandIsCoolangatta() {
        let s = BOMService.nearestStation(to: CLLocation(latitude: -27.87, longitude: 153.35))
        XCTAssertEqual(s.name, "Coolangatta")
        XCTAssertEqual(s.product, "IDQ60801")
    }

    /// BOM reports wind direction as a compass string, not degrees.
    func testCompassStringToDegrees() {
        XCTAssertEqual(BOMService.degrees(fromCompass: "N"), 0)
        XCTAssertEqual(BOMService.degrees(fromCompass: "E"), 90)
        XCTAssertEqual(BOMService.degrees(fromCompass: "S"), 180)
        XCTAssertEqual(BOMService.degrees(fromCompass: "SSE"), 158)
        XCTAssertNil(BOMService.degrees(fromCompass: "CALM"))
        XCTAssertNil(BOMService.degrees(fromCompass: "-"))
        XCTAssertNil(BOMService.degrees(fromCompass: nil))
    }

    /// `weather` is usually "-"; the useful signal lives in `cloud`.
    func testConditionPrefersCloudFieldWhenWeatherIsBlank() {
        XCTAssertEqual(BOMService.condition(cloud: "Clear", weather: "-", rain: 0, humidity: 50), .clearSky)
        XCTAssertEqual(BOMService.condition(cloud: "Partly cloudy", weather: "-", rain: 0, humidity: 50), .partlyCloudy)
        XCTAssertEqual(BOMService.condition(cloud: "Overcast", weather: "-", rain: 0, humidity: 50), .overcast)
        // weather wins when it carries real information
        XCTAssertEqual(BOMService.condition(cloud: "Clear", weather: "Thunderstorm", rain: 0, humidity: 50), .thunderstorm)
        // nothing reported → infer
        XCTAssertEqual(BOMService.condition(cloud: "-", weather: "-", rain: 5, humidity: 50), .rain)
    }
}
