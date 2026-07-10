// Sky Warden — engine tests
// Covers the comfort scoring curves, the consensus merge, and the source
// coverage/parsing rules that caused real bugs.

import XCTest
import CoreLocation
import MapKit
@testable import SkyWarden

/// MKMapRect has no region initialiser; corners it is.
private func mapRect(_ r: MKCoordinateRegion) -> MKMapRect {
    let nw = MKMapPoint(CLLocationCoordinate2D(latitude: r.center.latitude + r.span.latitudeDelta / 2,
                                               longitude: r.center.longitude - r.span.longitudeDelta / 2))
    let se = MKMapPoint(CLLocationCoordinate2D(latitude: r.center.latitude - r.span.latitudeDelta / 2,
                                               longitude: r.center.longitude + r.span.longitudeDelta / 2))
    return MKMapRect(x: min(nw.x, se.x), y: min(nw.y, se.y),
                     width: abs(se.x - nw.x), height: abs(se.y - nw.y))
}

// MARK: - Fixtures
private func reading(
    _ source: WeatherSource,
    temp: Double = 20,
    rain: Double? = 10,
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

    /// Hue now means comfort and nothing else, so the ramp's endpoints and
    /// midpoint are load-bearing: a metric at its best must not render red.
    func testComfortRampAnchorsAtItsPoles() {
        XCTAssertEqual(Comfort.comfortColor(1).rgba.r, Comfort.good.rgba.r, accuracy: 0.001)
        XCTAssertEqual(Comfort.comfortColor(-1).rgba.r, Comfort.poor.rgba.r, accuracy: 0.001)
        XCTAssertEqual(Comfort.comfortColor(0).rgba.g, Comfort.neutral.rgba.g, accuracy: 0.001)
        // Clamped, not wrapped: an out-of-range score must not fold back to green.
        XCTAssertEqual(Comfort.comfortColor(-4).rgba.r, Comfort.poor.rgba.r, accuracy: 0.001)
    }

    /// Red channel rises monotonically as comfort falls — the ramp reads the
    /// same way in greyscale, and to a colour-blind user.
    func testComfortRampIsMonotonicFromGoodToPoor() {
        let scores = stride(from: 1.0, through: -1.0, by: -0.25)
        let reds = scores.map { Comfort.comfortColor($0).rgba.r }
        XCTAssertEqual(reds, reds.sorted(), "red must increase as the score worsens")
        let greens = scores.map { Comfort.comfortColor($0).rgba.g }
        XCTAssertEqual(greens.first!, greens.max()!, accuracy: 0.001, "the good pole is the greenest")
    }

    /// The verdict orb is the icon's circle doing its job: it must sit on the
    /// same ramp as the rings, or the middle of the dial contradicts its edge.
    func testOverallColourUsesTheSameRamp() {
        for s in [-1.0, -0.4, 0.0, 0.5, 1.0] {
            XCTAssertEqual(Comfort.overallColor(s).rgba.r, Comfort.comfortColor(s).rgba.r, accuracy: 0.001)
        }
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
            reading(.ecmwf, temp: 20),
            reading(.gfs, temp: 21),
            reading(.bom, temp: 40, uv: nil),
        ])
        XCTAssertEqual(c.temperature, 21, accuracy: 0.001)
    }

    func testPlainMeanWithTwoSources() {
        let c = ConsensusCalculator().calculate(from: [
            reading(.ecmwf, temp: 20),
            reading(.gfs, temp: 24),
        ])
        XCTAssertEqual(c.temperature, 22, accuracy: 0.001)
    }

    /// Regression: BOM reports no UV. It used to send 0, which halved the
    /// consensus UV and raised a false "sources disagree" flag on the UV ring.
    func testSourceWithoutUVIsExcludedFromUVConsensus() {
        let c = ConsensusCalculator().calculate(from: [
            reading(.ecmwf, uv: 6),
            reading(.bom, uv: nil),
        ])
        XCTAssertEqual(c.uvIndex, 6, accuracy: 0.001, "BOM's absent UV must not drag the average to 3")
    }

    func testSourceWithoutUVProducesNoUVDisagreement() {
        let data = ComfortData(consensus: ConsensusCalculator().calculate(from: [
            reading(.ecmwf, uv: 6),
            reading(.bom, uv: nil),
        ]))
        let uvRing = data.ring(.uv)!
        XCTAssertEqual(uvRing.perSource.count, 1, "only sources that measure UV appear on the ring")
        XCTAssertEqual(uvRing.spread, 0, accuracy: 0.001)
        XCTAssertFalse(uvRing.hasFlag, "must not flag a disagreement against a source that reports nothing")
    }

    func testDisagreementIsFlaggedWhenSourcesActuallyDiffer() {
        let data = ComfortData(consensus: ConsensusCalculator().calculate(from: [
            reading(.ecmwf, temp: 18),
            reading(.gfs, temp: 24),   // 6° spread, threshold 2 → major (≥2×)
        ]))
        let temp = data.ring(.temp)!
        XCTAssertEqual(temp.spread, 6, accuracy: 0.001)
        XCTAssertTrue(temp.hasFlag)
        XCTAssertTrue(temp.isMajor)
    }

    /// UKMO publishes no precipitation probability and BOM reports observations,
    /// not a forecast. Neither may drag the rain consensus or manufacture a flag.
    func testSourceWithoutRainProbabilityIsExcluded() {
        let c = ConsensusCalculator().calculate(from: [
            reading(.ecmwf, rain: 80),
            reading(.ukmo, rain: nil),
            reading(.bom, rain: nil, uv: nil),
        ])
        XCTAssertEqual(c.rainProbability, 80, accuracy: 0.001,
                       "absent probabilities must not be averaged in as zero")

        let ring = ComfortData(consensus: c).ring(.rain)!
        XCTAssertEqual(ring.perSource.count, 1)
        XCTAssertFalse(ring.hasFlag, "no disagreement against sources that published nothing")
    }

    func testRainDisagreementStillFlaggedBetweenSourcesThatDoPublish() {
        // Real spread seen in the wild: GEM 5% vs GFS 100% for the same day.
        let data = ComfortData(consensus: ConsensusCalculator().calculate(from: [
            reading(.gem, rain: 5), reading(.gfs, rain: 100), reading(.ukmo, rain: nil),
        ]))
        let ring = data.ring(.rain)!
        XCTAssertEqual(ring.perSource.count, 2)
        XCTAssertTrue(ring.isMajor)
    }

    /// The six model sources must be exactly the ones with an Open-Meteo model id.
    func testModelSourcesAreIndependentAndDistinct() {
        XCTAssertEqual(WeatherSource.models.count, 6)
        XCTAssertEqual(Set(WeatherSource.models.compactMap(\.openMeteoModel)).count, 6)
        XCTAssertNil(WeatherSource.bom.openMeteoModel)
        XCTAssertNil(WeatherSource.weatherKit.openMeteoModel)
        // Identity comes from the label, which must be unique.
        XCTAssertEqual(Set(WeatherSource.allCases.map(\.short)).count, WeatherSource.allCases.count)
    }

    /// Colour no longer identifies the source — nine hues cannot be told apart
    /// under protanopia (best achievable ΔE 4.8, floor 8). It encodes the only
    /// thing that changes how a number is read: forecast, or measurement.
    func testSourceColourEncodesForecastVersusObservation() {
        XCTAssertEqual(WeatherSource.bom.kind, .observation, "BOM reports what happened")
        for s in WeatherSource.allCases where s != .bom {
            XCTAssertEqual(s.kind, .forecast, "\(s.short) is a forecast")
        }
        // Exactly two colours, and they are not the nine-hue rainbow.
        XCTAssertEqual(Set(WeatherSource.allCases.map(\.colorHex)).count, 2)
        XCTAssertNotEqual(WeatherSource.bom.colorHex, WeatherSource.ecmwf.colorHex)
        XCTAssertEqual(WeatherSource.gfs.colorHex, WeatherSource.ecmwf.colorHex,
                       "two models are both just models")
    }

    /// Range grows with sample count, so it can't be the disagreement measure
    /// once we fetch six models — otherwise more information looks like less
    /// confidence. With 4+ sources we trim the extremes first.
    func testRobustSpreadTrimsExtremesOnceThereAreFourSources() {
        XCTAssertEqual(robustSpread([10, 12])!, 2, accuracy: 0.001, "2 sources: plain range")
        XCTAssertEqual(robustSpread([10, 11, 12])!, 2, accuracy: 0.001, "3 sources: plain range")
        // One wild model must not define the disagreement.
        XCTAssertEqual(robustSpread([10, 11, 12, 13, 14, 100])!, 3, accuracy: 0.001)
        XCTAssertNil(robustSpread([5]))
    }

    func testOneOutlierModelDoesNotManufactureAMajorDisagreement() {
        // Five models agree within 1°; one is wildly off. Trimming keeps it sane.
        let readings = [
            reading(.ecmwf, temp: 20), reading(.gfs, temp: 20.5), reading(.icon, temp: 20.2),
            reading(.metno, temp: 20.4), reading(.gem, temp: 20.1), reading(.ukmo, temp: 34, rain: nil),
        ]
        let ring = ComfortData(consensus: ConsensusCalculator().calculate(from: readings)).ring(.temp)!
        XCTAssertLessThan(ring.spread, 2.0, "trimmed spread ignores the single outlier")
        XCTAssertFalse(ring.hasFlag)
    }

    func testCircularMeanHandlesWrapAround() {
        // 350° and 10° should average to 0°, not 180°.
        let c = ConsensusCalculator().calculate(from: [
            reading(.ecmwf, windDir: 350),
            reading(.gfs, windDir: 10),
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

// MARK: - Weather map tiles
final class WeatherMapServiceTests: XCTestCase {

    /// Each geostationary satellite only sees one face of the Earth.
    func testSatelliteChosenByLongitude() {
        XCTAssertEqual(WeatherMapLayer.geostationaryLayer(forLongitude: 153.35),
                       "Himawari_AHI_Band13_Clean_Infrared")           // Hope Island
        XCTAssertEqual(WeatherMapLayer.geostationaryLayer(forLongitude: -74.0),
                       "GOES-East_ABI_Band13_Clean_Infrared")          // New York
        XCTAssertEqual(WeatherMapLayer.geostationaryLayer(forLongitude: -122.4),
                       "GOES-West_ABI_Band13_Clean_Infrared")          // San Francisco
        XCTAssertNil(WeatherMapLayer.geostationaryLayer(forLongitude: -0.12),
                     "London sits between the discs — no live cloud layer")
    }

    /// Rainfall is global; the cloud layer isn't.
    func testRainfallHasASpecEverywhereCloudDoesNot() {
        XCTAssertNotNil(WeatherMapLayer.rainfall.spec(forLongitude: -0.12))
        XCTAssertNil(WeatherMapLayer.cloud.spec(forLongitude: -0.12))
        XCTAssertNotNil(WeatherMapLayer.cloud.spec(forLongitude: 153.35))
    }

    func testFrameFlooringMatchesLayerCadence() {
        let d = Date(timeIntervalSince1970: 1_783_000_000)  // arbitrary
        let f10 = WeatherMapService.floor(d, toStep: 10)
        let f30 = WeatherMapService.floor(d, toStep: 30)
        XCTAssertEqual(Int(f10.timeIntervalSince1970) % 600, 0)
        XCTAssertEqual(Int(f30.timeIntervalSince1970) % 1800, 0)
        XCTAssertLessThanOrEqual(f10, d)
    }

    func testFramesRunOldestToNewestAtTheLayerStep() {
        let spec = WeatherMapLayer.cloud.spec(forLongitude: 153.35)!
        let latest = WeatherMapService.floor(Date(), toStep: spec.stepMinutes)
        let frames = WeatherMapService.frameDates(endingAt: latest, spec: spec, count: 4)
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames.last, latest, "the newest frame is last")
        XCTAssertEqual(frames[1].timeIntervalSince(frames[0]), Double(spec.stepMinutes * 60), accuracy: 1)
    }

    /// GIBS is WMTS: the path is {z}/{row}/{col} — row (y) BEFORE col (x).
    /// Swapping them silently renders the wrong hemisphere.
    func testGIBSTileURLPutsRowBeforeColumn() {
        let spec = WeatherMapLayer.cloud.spec(forLongitude: 153.35)!
        let frame = MapFrame(date: Date(timeIntervalSince1970: 1_783_000_800), token: "2026-07-06T04:40:00Z")
        let url = WeatherMapService.tileURL(spec, frame: frame, z: 5, x: 29, y: 18)!
        XCTAssertTrue(url.absoluteString.hasSuffix("/5/18/29.png"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("Himawari_AHI_Band13_Clean_Infrared"))
    }

    /// RainViewer is a plain slippy map: {z}/{x}/{y}, column BEFORE row — the
    /// opposite of GIBS. Getting these two confused transposes the map.
    func testRainViewerTileURLPutsColumnBeforeRow() {
        let spec = WeatherMapLayer.radar.spec(forLongitude: 153.35)!
        let frame = MapFrame(date: Date(timeIntervalSince1970: 1_783_000_800),
                             token: "https://tilecache.rainviewer.com/v2/radar/abc123")
        let url = WeatherMapService.tileURL(spec, frame: frame, z: 8, x: 237, y: 148)!
        XCTAssertEqual(url.absoluteString,
                       "https://tilecache.rainviewer.com/v2/radar/abc123/512/8/237/148/4/1_1.png")
    }

    /// Regression: RainViewer's free tilecache answers z8+ with a tile reading
    /// "Zoom Level Not Supported". Anything past z7 must resolve to a z7 ancestor
    /// rather than be requested, or that text gets painted onto the map.
    func testRadarNeverRequestsPastItsSupportedZoom() {
        let spec = WeatherMapLayer.radar.spec(forLongitude: 153.35)!
        XCTAssertEqual(spec.maxZ, 7)
        for z in 8...14 {
            let a = WeatherMapService.ancestor(z: z, x: 1 << (z - 1), y: 1 << (z - 1), maxZ: spec.maxZ)
            XCTAssertEqual(a.z, 7, "z\(z) must fall back to the deepest served level")
        }
    }

    /// Radar is available everywhere the catalogue reaches, unlike the
    /// geostationary cloud layer, which is blind to half the planet.
    func testRadarHasASpecAtEveryLongitude() {
        for lon in stride(from: -180.0, through: 180.0, by: 30) {
            XCTAssertNotNil(WeatherMapLayer.radar.spec(forLongitude: lon), "no radar spec at \(lon)")
        }
        XCTAssertNil(WeatherMapLayer.cloud.spec(forLongitude: 10), "no geostationary cover over Europe")
    }

    /// The warm-up must cache exactly the tiles MapKit is about to request. This
    /// is the calibration point: a 1400 km camera on a ~393pt-wide phone made
    /// MapKit ask for z6, which is what broke the layer when maximumZ was 5.
    func testZoomLevelMatchesWhatMapKitRequests() {
        let region = MKCoordinateRegion(center: .init(latitude: -27.87, longitude: 153.35),
                                        latitudinalMeters: 1_400_000, longitudinalMeters: 1_400_000)
        let rect = mapRect(region)
        XCTAssertEqual(WeatherMapService.zoomLevel(visibleMapRect: rect, widthPoints: 393), 6)
    }

    func testTileBoundsCoverTheVisibleRectAndStayInRange() {
        let region = MKCoordinateRegion(center: .init(latitude: -27.87, longitude: 153.35),
                                        latitudinalMeters: 500_000, longitudinalMeters: 500_000)
        let b = WeatherMapService.tileBounds(mapRect(region), z: 8)
        XCTAssertLessThanOrEqual(b.x0, b.x1)
        XCTAssertLessThanOrEqual(b.y0, b.y1)
        XCTAssertGreaterThanOrEqual(b.x0, 0)
        XCTAssertLessThan(b.x1, 1 << 8)
        // The Hope Island z8 tile must fall inside the bounds we're about to warm.
        let (x, y) = WeatherMapService.tileIndex(.init(latitude: -27.87, longitude: 153.35), z: 8)
        XCTAssertTrue((b.x0...b.x1).contains(x) && (b.y0...b.y1).contains(y))
    }

    func testTileIndexForHopeIsland() {
        let (x, y) = WeatherMapService.tileIndex(.init(latitude: -27.87, longitude: 153.35), z: 5)
        XCTAssertEqual(x, 29)
        XCTAssertEqual(y, 18)
    }

    /// MapKit asks for z6 at phone zoom but GIBS stops at z5, so every request
    /// has to resolve to an ancestor tile plus a quadrant within it.
    func testAncestorResolvesUnservedZoomToItsParentQuadrant() {
        // The four z6 children of the Hope Island z5 tile (29, 18).
        for (x, y, ox, oy) in [(58, 36, 0, 0), (59, 36, 1, 0), (58, 37, 0, 1), (59, 37, 1, 1)] {
            let a = WeatherMapService.ancestor(z: 6, x: x, y: y, maxZ: 5)
            XCTAssertEqual(a.z, 5)
            XCTAssertEqual(a.x, 29)
            XCTAssertEqual(a.y, 18)
            XCTAssertEqual(a.dz, 1)
            XCTAssertEqual(a.ox, ox)
            XCTAssertEqual(a.oy, oy)
        }
    }

    func testAncestorIsIdentityAtOrBelowTheServedZoom() {
        let a = WeatherMapService.ancestor(z: 4, x: 14, y: 9, maxZ: 5)
        XCTAssertEqual(a.z, 4)
        XCTAssertEqual(a.x, 14)
        XCTAssertEqual(a.y, 9)
        XCTAssertEqual(a.dz, 0, "no upsampling when the server has the level")
    }

    /// Radar is fetched at 512px so a 256pt tile gets Retina density; the other
    /// layers have no such render and must stay at 256.
    func testRadarRequestsHighDensityTiles() {
        let radar = WeatherMapLayer.radar.spec(forLongitude: 153.35)!
        XCTAssertEqual(radar.tilePixels, 512)
        let frame = MapFrame(date: Date(), token: "https://t/v2/radar/abc")
        XCTAssertTrue(WeatherMapService.tileURL(radar, frame: frame, z: 7, x: 1, y: 2)!
            .absoluteString.contains("/512/7/1/2/"))

        XCTAssertEqual(WeatherMapLayer.cloud.spec(forLongitude: 153.35)!.tilePixels, 256)
    }
}

// MARK: - Response cache
//
// WorldTides bills per call. These tests exist because the app shipped for weeks
// re-fetching paid tide data on every launch, every pull-to-refresh and every
// 10-minute background wake, and nothing caught it.
final class DiskCacheTests: XCTestCase {

    private struct Payload: Codable, Equatable { let value: Int }

    override func setUp() { super.setUp(); DiskCache.clear() }
    override func tearDown() { DiskCache.clear(); super.tearDown() }

    func testRoundTripsWithinTTL() {
        DiskCache.save(Payload(value: 42), key: "k")
        XCTAssertEqual(DiskCache.load(Payload.self, key: "k", ttl: 60), Payload(value: 42))
    }

    func testExpiredEntryIsAMiss() {
        DiskCache.save(Payload(value: 42), key: "k")
        XCTAssertNil(DiskCache.load(Payload.self, key: "k", ttl: -1), "a stale entry must not be served")
    }

    func testMissingKeyIsAMiss() {
        XCTAssertNil(DiskCache.load(Payload.self, key: "absent", ttl: 60))
    }

    /// The whole point: a second call inside the TTL must not hit the network.
    func testThroughFetchesOnceThenServesFromCache() async throws {
        var calls = 0
        let fetch: () async throws -> Payload = { calls += 1; return Payload(value: calls) }

        let first  = try await DiskCache.through(key: "t", ttl: 60, fetch: fetch)
        let second = try await DiskCache.through(key: "t", ttl: 60, fetch: fetch)

        XCTAssertEqual(calls, 1, "the provider must be billed exactly once")
        XCTAssertEqual(first, second)
    }

    /// A provider outage must not pin an empty answer for six hours.
    func testFailuresAreNotCached() async {
        struct Boom: Error {}
        var calls = 0
        for _ in 0..<2 {
            calls += 1
            _ = try? await DiskCache.through(key: "f", ttl: 60) { () -> Payload in throw Boom() }
        }
        XCTAssertEqual(calls, 2)
        XCTAssertNil(DiskCache.load(Payload.self, key: "f", ttl: 60))
    }

    /// The key quantises to a ~5.5 km grid, so most movement reuses one entry and
    /// distant places never collide.
    func testGridKeyQuantisesLocation() {
        let a = CLLocation(latitude: -27.861, longitude: 153.351)
        let b = CLLocation(latitude: -27.859, longitude: 153.349)   // same cell
        let brisbane = CLLocation(latitude: -27.470, longitude: 153.020)

        XCTAssertEqual(DiskCache.gridKey("tides", a), DiskCache.gridKey("tides", b))
        XCTAssertNotEqual(DiskCache.gridKey("tides", a), DiskCache.gridKey("tides", brisbane))
    }

    /// Honest about the limit: a grid has edges, so two points a few hundred
    /// metres apart CAN land in different cells and cost a second call. Bounded
    /// waste, not eliminated waste — worth knowing before trusting the grid.
    func testGridKeyStillSplitsAcrossACellBoundary() {
        let justBelow = CLLocation(latitude: -27.874, longitude: 153.35)
        let justAbove = CLLocation(latitude: -27.876, longitude: 153.35)   // ~220 m, across -27.875
        XCTAssertNotEqual(DiskCache.gridKey("tides", justBelow), DiskCache.gridKey("tides", justAbove))
    }

    func testTidesTTLIsLongEnoughToMatter() {
        // Tides are astronomical and we fetch two days at a time. Anything under
        // an hour and we're back to paying per weather refresh.
        XCTAssertGreaterThanOrEqual(CacheTTL.tides, 3600)
        XCTAssertGreaterThanOrEqual(CacheTTL.archive, 12 * 3600)
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
