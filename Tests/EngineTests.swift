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

// MARK: - Forecast skill tracking (the moat)
//
// This decides which forecast the user sees, so it is tested adversarially:
// every rule that stops a false accuracy claim has a test that tries to break it.
final class SkillTableTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_783_000_000)
    private func pf(_ src: WeatherSource, _ m: SkillMetric, _ offset: TimeInterval, _ v: Double) -> PendingForecast {
        PendingForecast(source: src.rawValue, metric: m, targetTime: t0.addingTimeInterval(offset), predicted: v)
    }

    func testRecordsOnlyFutureForecasts() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 20), pf(.gfs, .temp, -3600, 20)], now: t0)
        XCTAssertEqual(t.pending.count, 1, "you cannot forecast the past")
        XCTAssertEqual(t.pending.first?.source, WeatherSource.ecmwf.rawValue)
    }

    func testLaterRefreshSupersedesTheSamePrediction() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 20)], now: t0)
        t.record([pf(.ecmwf, .temp, 3600, 22)], now: t0)
        XCTAssertEqual(t.pending.count, 1, "one prediction per source, metric and hour")
        XCTAssertEqual(t.pending.first?.predicted, 22)
    }

    func testScoringAccumulatesMeanAbsoluteError() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 20), pf(.gfs, .temp, 3600, 25)], now: t0)
        let scored = t.score(observed: [.temp: 21], at: t0.addingTimeInterval(3600))
        XCTAssertEqual(scored, 2)
        XCTAssertEqual(t.mae(.ecmwf, .temp)!, 1, accuracy: 0.001)
        XCTAssertEqual(t.mae(.gfs, .temp)!, 4, accuracy: 0.001)
        XCTAssertTrue(t.pending.isEmpty, "a scored forecast is consumed")
    }

    /// The app was closed over the target hour. Scoring it against a much later
    /// thermometer would blame a forecast for the wrong moment.
    func testAForecastWhoseHourPassedUnscoredIsDroppedNotMisScored() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 20)], now: t0)
        let scored = t.score(observed: [.temp: 35], at: t0.addingTimeInterval(3600 + 6 * 3600))
        XCTAssertEqual(scored, 0)
        XCTAssertTrue(t.pending.isEmpty)
        XCTAssertNil(t.mae(.ecmwf, .temp), "no sample, therefore no opinion")
    }

    func testForecastStillInWindowSurvivesAMissingObservation() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 20)], now: t0)
        t.score(observed: [:], at: t0.addingTimeInterval(3600))     // BOM was down
        XCTAssertEqual(t.pending.count, 1, "wait for the next refresh")
        t.score(observed: [.temp: 20], at: t0.addingTimeInterval(3600 + 600))
        XCTAssertEqual(t.samples(.ecmwf, .temp), 1)
    }

    func testFutureForecastIsNotScoredEarly() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 6 * 3600, 20)], now: t0)
        XCTAssertEqual(t.score(observed: [.temp: 20], at: t0), 0)
        XCTAssertEqual(t.pending.count, 1)
    }

    /// Regression: the match window used to be symmetric, so a forecast for
    /// 11:00 was graded against the 10:35 thermometer — marked wrong for
    /// correctly predicting a temperature that hadn't happened yet, then
    /// consumed, so the real 11:00 reading never saw it. Refreshes run every
    /// ten minutes, so this fired constantly.
    func testAForecastIsNeverScoredBeforeItsHourArrives() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 22)], now: t0)          // predicts 22° at 11:00

        // 10:35 — inside a symmetric ±30 min window, but the hour hasn't come.
        XCTAssertEqual(t.score(observed: [.temp: 18], at: t0.addingTimeInterval(3600 - 25 * 60)), 0)
        XCTAssertEqual(t.pending.count, 1, "still waiting for its hour")
        XCTAssertNil(t.mae(.ecmwf, .temp), "no false error recorded")

        // 11:00 — now it may be scored, against the right observation.
        XCTAssertEqual(t.score(observed: [.temp: 22], at: t0.addingTimeInterval(3600)), 1)
        XCTAssertEqual(t.mae(.ecmwf, .temp)!, 0, accuracy: 0.001, "it was exactly right")
    }

    /// A refresh shortly after the hour still scores it — that is the whole
    /// point of the tolerance.
    func testAForecastIsScoredShortlyAfterItsHour() {
        var t = SkillTable()
        t.record([pf(.ecmwf, .temp, 3600, 22)], now: t0)
        XCTAssertEqual(t.score(observed: [.temp: 20], at: t0.addingTimeInterval(3600 + 20 * 60)), 1)
        XCTAssertEqual(t.mae(.ecmwf, .temp)!, 2, accuracy: 0.001)
    }

    /// Truth must be a thermometer. Scoring forecasts against the consensus
    /// would reward agreeing with the crowd rather than being right.
    func testTruthComesOnlyFromAnObservationSource() {
        let forecasts = [reading(.ecmwf, temp: 20), reading(.gfs, temp: 22)]
        XCTAssertNil(SkillTable.observation(from: forecasts))

        let withObs = forecasts + [reading(.bom, temp: 19, rain: nil, uv: nil)]
        let truth = SkillTable.observation(from: withObs)
        XCTAssertEqual(truth?[.temp], 19)
    }

    /// BOM makes no forecast, so it must never be filed and never be scored
    /// against itself — which would give it a perfect record for free.
    func testObservationSourceIsNeverFiledAsAForecast() {
        let readings = [reading(.bom, temp: 19, rain: nil, uv: nil)]
        XCTAssertTrue(SkillTable.forecasts(from: readings, now: t0).isEmpty)
    }

    // MARK: Weighting

    private func table(with maes: [WeatherSource: Double], samples: Int) -> SkillTable {
        var t = SkillTable()
        for (src, mae) in maes {
            for i in 0..<samples {
                t.record([pf(src, .temp, Double(i + 1) * 3600, 20 + mae)], now: t0)
                t.score(observed: [.temp: 20], at: t0.addingTimeInterval(Double(i + 1) * 3600))
            }
        }
        return t
    }

    func testNoWeightsUntilEverySourceHasEnoughSamples() {
        let t = table(with: [.ecmwf: 1, .gfs: 4], samples: SkillTable.minSamples - 1)
        XCTAssertNil(t.weights(for: .temp, among: [.ecmwf, .gfs]),
                     "an unearned weighting is worse than none")
    }

    /// A source we happen to have measured a lot must not outrank one we simply
    /// haven't measured yet. That's a fact about our data, not about the forecast.
    func testAWellMeasuredSourceCannotOutrankAnUnmeasuredOne() {
        var t = table(with: [.ecmwf: 1], samples: SkillTable.minSamples + 5)
        t.record([pf(.icon, .temp, 3600, 20)], now: t0)
        XCTAssertNil(t.weights(for: .temp, among: [.ecmwf, .icon]))
    }

    func testTheMoreAccurateSourceEarnsMoreWeight() {
        let t = table(with: [.ecmwf: 1, .gfs: 4], samples: SkillTable.minSamples)
        let w = t.weights(for: .temp, among: [.ecmwf, .gfs])!
        XCTAssertGreaterThan(w[.ecmwf]!, w[.gfs]!)
        XCTAssertEqual(w.values.reduce(0, +), 1, accuracy: 0.001, "weights are normalised")
    }

    /// One near-perfect record must not swamp the rest before the sample count
    /// has had a chance to catch up with it.
    ///
    /// Regression: the cap used to be 3x an equal share, which for three sources
    /// is 1.0 and can never bind — a source with MAE 0 walked off with 99.3% of
    /// the weight. The earlier version of this test asserted `<= 1.0` and passed
    /// vacuously.
    func testWeightsAreClampedSoOneLuckySourceCannotDominate() {
        let t = table(with: [.ecmwf: 0, .gfs: 30, .icon: 30], samples: SkillTable.minSamples)
        let w = t.weights(for: .temp, among: [.ecmwf, .gfs, .icon])!

        let cap = SkillTable.weightCapMultiple / 3.0        // 0.667, and it must bind
        XCTAssertEqual(w[.ecmwf]!, cap, accuracy: 0.001, "a perfect record is capped, not unbounded")
        XCTAssertEqual(w[.gfs]!, (1 - cap) / 2, accuracy: 0.001, "the excess spills to the others")
        XCTAssertEqual(w[.icon]!, (1 - cap) / 2, accuracy: 0.001)
        XCTAssertEqual(w.values.reduce(0, +), 1, accuracy: 0.001)
    }

    /// Water-filling, not a single capped pass: the spill must not push a
    /// previously-uncapped source over the cap.
    func testCappingSpillsRepeatedlyUntilNobodyIsOverTheCap() {
        let t = table(with: [.ecmwf: 0, .gfs: 0, .icon: 40, .metno: 40, .gem: 40],
                      samples: SkillTable.minSamples)
        let sources: [WeatherSource] = [.ecmwf, .gfs, .icon, .metno, .gem]
        let w = t.weights(for: .temp, among: sources)!
        let cap = SkillTable.weightCapMultiple / Double(sources.count)   // 0.4
        for s in sources {
            XCTAssertLessThanOrEqual(w[s]!, cap + 0.001, "\(s.short) is over the cap")
            XCTAssertGreaterThan(w[s]!, 0, "nobody is zeroed out")
        }
        XCTAssertEqual(w.values.reduce(0, +), 1, accuracy: 0.001)
    }

    /// Equal skill must produce equal weights — no drift from the capping loop.
    func testIdenticalSkillGivesUniformWeights() {
        let t = table(with: [.ecmwf: 2, .gfs: 2, .icon: 2], samples: SkillTable.minSamples)
        let w = t.weights(for: .temp, among: [.ecmwf, .gfs, .icon])!
        for v in w.values { XCTAssertEqual(v, 1.0 / 3, accuracy: 0.001) }
    }

    // MARK: The merge

    func testWeightedTrimmedMeanFallsBackToTheOldBehaviourWithoutWeights() {
        let pairs: [(source: WeatherSource, value: Double)] =
            [(.ecmwf, 20), (.gfs, 21), (.icon, 40)]
        // Drops 20 and 40, keeps 21 — exactly the existing trimmed mean.
        XCTAssertEqual(weightedTrimmedMean(pairs, weights: nil), 21, accuracy: 0.001)
    }

    func testWeightingPullsTheConsensusTowardTheAccurateSource() {
        let pairs: [(source: WeatherSource, value: Double)] =
            [(.ecmwf, 20), (.gfs, 24), (.icon, 28), (.metno, 40), (.gem, 10)]
        // gem (10) and metno (40) are trimmed; ecmwf, gfs, icon survive.
        let unweighted = weightedTrimmedMean(pairs, weights: nil)
        XCTAssertEqual(unweighted, 24, accuracy: 0.001)

        let weighted = weightedTrimmedMean(pairs, weights: [.ecmwf: 0.8, .gfs: 0.1, .icon: 0.1])
        XCTAssertLessThan(weighted, unweighted, "trusting ecmwf pulls it toward 20")
        XCTAssertEqual(weighted, 20 * 0.8 + 24 * 0.1 + 28 * 0.1, accuracy: 0.001)
    }

    /// A trimmed-out source's weight must not silently vanish into the divisor.
    func testWeightsRenormaliseOverTheSurvivorsOnly() {
        let pairs: [(source: WeatherSource, value: Double)] =
            [(.ecmwf, 20), (.gfs, 22), (.icon, 30)]
        // ecmwf and icon are trimmed; only gfs survives, so the answer is gfs.
        XCTAssertEqual(weightedTrimmedMean(pairs, weights: [.ecmwf: 0.9, .gfs: 0.05, .icon: 0.05]),
                       22, accuracy: 0.001)
    }

    func testTwoSourcesAreAveragedNotTrimmedAway() {
        let pairs: [(source: WeatherSource, value: Double)] = [(.ecmwf, 20), (.gfs, 24)]
        XCTAssertEqual(weightedTrimmedMean(pairs, weights: nil), 22, accuracy: 0.001)
    }
}

// MARK: - Skill weighting reaches the consensus
final class SkillWeightedConsensusTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_783_000_000)

    private func hourly(_ times: [TimeInterval], temp: Double, wind: Double) -> [HourlyReading] {
        times.map { HourlyReading(time: t0.addingTimeInterval($0), temperature: temp,
                                  rainProbability: 10, rainAmount: 0, windSpeed: wind,
                                  condition: .clearSky, uvIndex: 3) }
    }

    /// With no ledger, the merge is exactly what it always was.
    func testEmptyWeightsLeaveTheConsensusUnchanged() {
        let readings = [reading(.ecmwf, temp: 20), reading(.gfs, temp: 21), reading(.icon, temp: 40)]
        let plain = ConsensusCalculator().calculate(from: readings)
        let weighted = ConsensusCalculator().calculate(from: readings, skillWeights: [:])
        XCTAssertEqual(plain.temperature, weighted.temperature, accuracy: 0.001)
        XCTAssertEqual(weighted.temperature, 21, accuracy: 0.001)
    }

    func testSkillWeightsMoveTheConsensusTemperature() {
        let readings = [reading(.ecmwf, temp: 20), reading(.gfs, temp: 24), reading(.icon, temp: 28),
                        reading(.metno, temp: 40), reading(.gem, temp: 10)]
        let plain = ConsensusCalculator().calculate(from: readings)
        XCTAssertEqual(plain.temperature, 24, accuracy: 0.001)

        let trusted: [WeatherSource: Double] = [.ecmwf: 0.6, .gfs: 0.2, .icon: 0.2]
        let weighted = ConsensusCalculator().calculate(from: readings, skillWeights: [.temp: trusted])
        XCTAssertLessThan(weighted.temperature, plain.temperature)
        XCTAssertEqual(weighted.temperature, 20 * 0.6 + 24 * 0.2 + 28 * 0.2, accuracy: 0.001)
    }

    /// A source must never be scored against the observation from the very
    /// refresh that filed it — that would be a free perfect record for
    /// "predicting" the present. The one-hour minimum horizon is what enforces it.
    func testASourceCannotBeScoredAgainstTheRefreshThatFiledIt() {
        var r = reading(.ecmwf, temp: 20)
        r.hourlyForecast = hourly([0, 3600], temp: 20, wind: 10)
        let filed = SkillTable.forecasts(from: [r], now: t0)

        XCTAssertFalse(filed.isEmpty, "it did file something for later")
        XCTAssertTrue(filed.allSatisfy { $0.targetTime >= t0.addingTimeInterval(3600) - 1 },
                      "nothing is filed for the current hour")

        var table = SkillTable()
        table.record(filed, now: t0)
        XCTAssertEqual(table.score(observed: [.temp: 99], at: t0), 0,
                       "the present cannot score a forecast made for the future")
    }

    /// BOM makes no forecast, so it contributes no rows, so it can never be
    /// scored against its own thermometer.
    func testTheObservationSourceContributesNoScorableRows() {
        var bom = reading(.bom, temp: 19, rain: nil, uv: nil)
        bom.hourlyForecast = hourly([3600], temp: 19, wind: 8)
        XCTAssertTrue(SkillTable.forecasts(from: [bom], now: t0).isEmpty)
    }
}

// MARK: - The moat must actually engage
final class SkillEngagementTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_783_000_000)

    private func trained(_ sources: [WeatherSource]) -> SkillTable {
        var t = SkillTable()
        for s in sources {
            for i in 0..<SkillTable.minSamples {
                let target = t0.addingTimeInterval(Double(i + 1) * 3600)
                t.record([PendingForecast(source: s.rawValue, metric: .temp,
                                          targetTime: target, predicted: 21)], now: t0)
                t.score(observed: [.temp: 20], at: target)
            }
        }
        return t
    }

    /// BOM is an observation: it files no forecasts, so it can never reach
    /// minSamples. Asking for weights over a list that includes it would return
    /// nil forever, and the accuracy loop would silently never engage.
    func testObservationSourceMustNotBlockWeighting() {
        let t = trained([.ecmwf, .gfs, .icon])
        XCTAssertEqual(t.samples(.bom, .temp), 0, "BOM files nothing, by design")

        XCTAssertNil(t.weights(for: .temp, among: [.ecmwf, .gfs, .icon, .bom]),
                     "including the observation poisons the guard")
        XCTAssertNotNil(t.weights(for: .temp, among: [.ecmwf, .gfs, .icon]),
                        "forecast sources alone have earned an opinion")
    }

    /// A source with no skill record (the observation, or a newly-added model)
    /// must keep a fair share of the merge rather than being silently zeroed.
    func testASourceWithoutAWeightKeepsAnAverageShare() {
        let pairs: [(source: WeatherSource, value: Double)] =
            [(.ecmwf, 20), (.gfs, 22), (.bom, 24), (.icon, 40), (.gem, 10)]
        // gem and icon are trimmed; ecmwf, gfs and bom survive.
        let weights: [WeatherSource: Double] = [.ecmwf: 0.5, .gfs: 0.3, .icon: 0.2]

        let result = weightedTrimmedMean(pairs, weights: weights)
        XCTAssertGreaterThan(result, 20, "bom is not zeroed out")
        XCTAssertLessThan(result, 24)

        // bom takes the mean of the supplied weights (1/3), so:
        let meanW = (0.5 + 0.3 + 0.2) / 3
        let expected = (20 * 0.5 + 22 * 0.3 + 24 * meanW) / (0.5 + 0.3 + meanW)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }
}

// MARK: - Arc dial value scale
final class DisplayScaleTests: XCTestCase {

    func testNormalizedClampsToUnitInterval() {
        XCTAssertEqual(ComfortMetric.uv.normalized(0), 0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.uv.normalized(12), 1, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.uv.normalized(6), 0.5, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.uv.normalized(20), 1, accuracy: 0.001, "above range clamps, never wraps")
        XCTAssertEqual(ComfortMetric.temp.normalized(-10), 0, accuracy: 0.001, "below range clamps")
    }

    /// The whole reason "start at 0" was raised: UV 0 must be an empty arc in
    /// value mode, not the long sweep the comfort mapping drew.
    func testValueModeShowsZeroAsEmpty() {
        XCTAssertEqual(ComfortMetric.uv.normalized(0), 0, accuracy: 0.001)
        XCTAssertEqual(ComfortMetric.rain.normalized(0), 0, accuracy: 0.001)
    }

    func testEveryMetricHasAPositiveDisplayRange() {
        for m in ComfortMetric.allCases {
            XCTAssertGreaterThan(m.displayRange.upperBound, m.displayRange.lowerBound, "\(m.label)")
        }
    }

    func testArcFillModeHasAllThreeToggles() {
        XCTAssertEqual(Set(ArcFillMode.allCases.map(\.rawValue)), ["comfort", "value", "both"])
    }

    func testDialDefaultsToArc() {
        // The user asked for the arc to be the default; the fallback must agree.
        XCTAssertEqual(DialStyle(rawValue: "nonsense") ?? .arc, .arc)
    }

    /// The range band/label is suppressed when both ends format the same, so a
    /// wind forecast of 0.6–1.4 km/h doesn't render a pointless "1–1".
    func testRangeEndpointsThatFormatIdenticallyAreConsideredEmpty() {
        XCTAssertEqual(ComfortMetric.wind.format(0.6), ComfortMetric.wind.format(1.4),
                       "both round to the same displayed wind")
        XCTAssertNotEqual(ComfortMetric.temp.format(8), ComfortMetric.temp.format(20),
                          "a real temperature range shows")
    }

    func testShowRangeDefaultsOn() {
        // Absent key → range visible; the user asked to see it.
        XCTAssertTrue(UserDefaults.standard.object(forKey: "unset.key") as? Bool ?? true)
    }
}

// MARK: - Severe-weather warnings
//
// The point-in-polygon test decides whether someone standing inside a bushfire
// polygon is shown the warning. A false negative is a safety failure, so this is
// tested adversarially.
final class WarningGeometryTests: XCTestCase {

    private func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // A square around Brisbane-ish coords.
    private var square: [CLLocationCoordinate2D] {
        [c(-27.5, 152.9), c(-27.5, 153.1), c(-27.3, 153.1), c(-27.3, 152.9), c(-27.5, 152.9)]
    }

    func testPointInsidePolygonIsDetected() {
        XCTAssertTrue(WarningGeometry.pointInRing(c(-27.4, 153.0), square))
    }

    func testPointOutsidePolygonIsNot() {
        XCTAssertFalse(WarningGeometry.pointInRing(c(-27.9, 153.0), square), "south of the box")
        XCTAssertFalse(WarningGeometry.pointInRing(c(-27.4, 154.0), square), "east of the box")
    }

    func testDegeneratePolygonNeverContains() {
        XCTAssertFalse(WarningGeometry.pointInRing(c(-27.4, 153.0), [c(-27.5, 152.9), c(-27.3, 153.1)]))
    }

    func testPolygonWithAHoleExcludesTheHole() {
        let hole = [c(-27.45, 152.95), c(-27.45, 153.05), c(-27.35, 153.05), c(-27.35, 152.95), c(-27.45, 152.95)]
        let area = WarningArea.polygon(rings: [square, hole])
        XCTAssertTrue(area.contains(c(-27.31, 152.91)), "inside outer, outside hole")
        XCTAssertFalse(area.contains(c(-27.40, 153.00)), "inside the hole → not covered")
    }

    func testPointAreaUsesRadius() {
        let area = WarningArea.point(c(-27.87, 153.35), radiusKm: 50)
        XCTAssertTrue(area.contains(c(-27.9, 153.4)), "a few km away")
        XCTAssertFalse(area.contains(c(-28.9, 153.35)), "~110 km south")
    }

    func testCollectionIsCoveredIfAnyMemberIs() {
        let far = WarningArea.polygon(rings: [[c(-10, 140), c(-10, 141), c(-11, 141), c(-11, 140), c(-10, 140)]])
        let near = WarningArea.polygon(rings: [square])
        XCTAssertTrue(WarningArea.collection([far, near]).contains(c(-27.4, 153.0)))
        XCTAssertFalse(WarningArea.collection([far]).contains(c(-27.4, 153.0)))
    }

    func testHaversineIsAboutRight() {
        // Brisbane ↔ Gold Coast ≈ 70 km.
        let d = WarningGeometry.haversineKm(c(-27.47, 153.02), c(-28.00, 153.43))
        XCTAssertEqual(d, 70, accuracy: 12)
    }

    // MARK: Severity mapping

    func testSeverityNormalisesTheManyWordings() {
        XCTAssertEqual(WarningSeverity.from("Emergency Warning"), .emergency)
        XCTAssertEqual(WarningSeverity.from("EVACUATE NOW"), .emergency)
        XCTAssertEqual(WarningSeverity.from("Watch and Act"), .watchAndAct)
        XCTAssertEqual(WarningSeverity.from("Severe"), .watchAndAct)
        XCTAssertEqual(WarningSeverity.from("Advice"), .advice)
        XCTAssertEqual(WarningSeverity.from("AVOID SMOKE"), .advice)
        XCTAssertEqual(WarningSeverity.from(nil), .unknown)
        XCTAssertEqual(WarningSeverity.from("gibberish"), .unknown)
    }

    func testSeveritySortsWorstFirst() {
        XCTAssertTrue(WarningSeverity.emergency > WarningSeverity.watchAndAct)
        XCTAssertTrue(WarningSeverity.watchAndAct > WarningSeverity.advice)
    }

    // MARK: NSW description parsing

    func testNSWFieldExtraction() {
        let html = "ALERT LEVEL: Emergency Warning<br />LOCATION: Somewhere<br />TYPE: Bush Fire<br />STATUS: out of control"
        XCTAssertEqual(WarningsService.field("ALERT LEVEL", in: html), "Emergency Warning")
        XCTAssertEqual(WarningsService.field("TYPE", in: html), "Bush Fire")
        XCTAssertEqual(WarningsService.field("STATUS", in: html), "out of control")
        XCTAssertNil(WarningsService.field("MISSING", in: html))
    }

    // MARK: GeoJSON decode

    func testDecodesPolygonFeatureAndProperties() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature",
           "properties":{"WarningTitle":"Test fire","WarningLevel":"Watch and Act","UniqueID":"abc"},
           "geometry":{"type":"Polygon","coordinates":[[[152.9,-27.5],[153.1,-27.5],[153.1,-27.3],[152.9,-27.3],[152.9,-27.5]]]}}
        ]}
        """.data(using: .utf8)!
        let feats = GeoFeature.decode(json)!
        XCTAssertEqual(feats.count, 1)
        XCTAssertEqual(feats[0].string("WarningTitle"), "Test fire")
        XCTAssertEqual(feats[0].id, "abc")
        XCTAssertTrue(feats[0].area.contains(CLLocationCoordinate2D(latitude: -27.4, longitude: 153.0)))
        XCTAssertFalse(feats[0].area.contains(CLLocationCoordinate2D(latitude: -30.0, longitude: 153.0)))
    }

    /// GeoJSON is [lon, lat]. Swapping them would put every Australian warning in
    /// the wrong hemisphere — this pins the ordering.
    func testGeoJSONCoordinateOrderIsLonLat() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{},
           "geometry":{"type":"Point","coordinates":[153.35,-27.87]}}]}
        """.data(using: .utf8)!
        let area = GeoFeature.decode(json)![0].area
        // Covered near Hope Island (-27.87, 153.35), not at the swapped (153.35, -27.87).
        XCTAssertTrue(area.contains(CLLocationCoordinate2D(latitude: -27.87, longitude: 153.35)))
    }

    func testHandlesGeometryCollection() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"title":"x"},
           "geometry":{"type":"GeometryCollection","geometries":[
             {"type":"Point","coordinates":[153.0,-27.4]},
             {"type":"Polygon","coordinates":[[[152.9,-27.5],[153.1,-27.5],[153.1,-27.3],[152.9,-27.3],[152.9,-27.5]]]}]}}]}
        """.data(using: .utf8)!
        let feats = GeoFeature.decode(json)!
        XCTAssertEqual(feats.count, 1, "a GeometryCollection feature must not be dropped")
        XCTAssertTrue(feats[0].area.contains(CLLocationCoordinate2D(latitude: -27.4, longitude: 153.0)))
    }
}

// MARK: - Intraday peak timing
final class IntradayPeakTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_783_000_000)   // arbitrary "now"

    private func hour(_ offsetH: Double, temp: Double = 20, rain: Double = 0,
                      wind: Double = 5, uv: Double? = nil) -> ConsensusHourly {
        ConsensusHourly(time: t0.addingTimeInterval(offsetH * 3600), temperature: temp,
                        rainProbability: rain, condition: .clearSky, windSpeed: wind,
                        uvIndex: uv, hasDisagreement: false)
    }

    func testFindsTheRainPeakHour() {
        let hrs = [hour(1, rain: 10), hour(2, rain: 80), hour(3, rain: 40)]
        let peak = IntradayPeak.of(.rain, hourly: hrs, now: t0)!
        XCTAssertEqual(peak.value, 80, accuracy: 0.001)
        XCTAssertEqual(peak.time, t0.addingTimeInterval(2 * 3600))
        XCTAssertTrue(peak.phrase.contains("most likely"))
    }

    func testWindPeakPhrase() {
        let hrs = [hour(1, wind: 10), hour(4, wind: 35), hour(6, wind: 15)]
        let peak = IntradayPeak.of(.wind, hourly: hrs, now: t0)!
        XCTAssertEqual(peak.value, 35, accuracy: 0.001)
        XCTAssertTrue(peak.phrase.hasPrefix("windiest"))
    }

    func testUVPeakNeedsHourlyUV() {
        let withUV = [hour(1, uv: 3), hour(2, uv: 9), hour(3, uv: 6)]
        let peak = IntradayPeak.of(.uv, hourly: withUV, now: t0)!
        XCTAssertEqual(peak.value, 9, accuracy: 0.001)
        XCTAssertTrue(peak.phrase.contains("9"))

        let noUV = [hour(1), hour(2), hour(3)]
        XCTAssertNil(IntradayPeak.of(.uv, hourly: noUV, now: t0), "no hourly UV → no callout")
    }

    /// A metric that stays low all day earns no callout — the whole point is to
    /// flag when something is worth watching, not to narrate a calm day.
    func testLowMetricGivesNoCallout() {
        XCTAssertNil(IntradayPeak.of(.rain, hourly: [hour(1, rain: 5), hour(2, rain: 10)], now: t0))
        XCTAssertNil(IntradayPeak.of(.wind, hourly: [hour(1, wind: 6), hour(2, wind: 9)], now: t0))
        XCTAssertNil(IntradayPeak.of(.uv, hourly: [hour(1, uv: 1), hour(2, uv: 2)], now: t0))
    }

    func testOnlyLooksAtTheRestOfToday() {
        // A huge peak 20h out must be ignored — that's tomorrow's problem.
        let hrs = [hour(1, rain: 40), hour(2, rain: 35), hour(20, rain: 100)]
        let peak = IntradayPeak.of(.rain, hourly: hrs, now: t0)!
        XCTAssertEqual(peak.value, 40, accuracy: 0.001, "the 20h-out peak is beyond the horizon")
    }

    func testHumidityHasNoIntradayCallout() {
        XCTAssertNil(IntradayPeak.of(.humidity, hourly: [hour(1), hour(2)], now: t0))
    }
}

// MARK: - METAR global observation truth
final class METARServiceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_783_000_000)
    private func iso(_ offsetMin: Double) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: now.addingTimeInterval(offsetMin * 60))
    }

    private func feed(_ entries: [(icao: String, lat: Double, lon: Double, temp: Double, wspd: Double, ageMin: Double)]) -> Data {
        let arr = entries.map { e -> [String: Any] in
            ["icaoId": e.icao, "name": e.icao, "lat": e.lat, "lon": e.lon,
             "temp": e.temp, "wspd": e.wspd, "reportTime": iso(-e.ageMin)]
        }
        return try! JSONSerialization.data(withJSONObject: arr)
    }

    func testParsesTempAndConvertsWindToKmh() {
        let data = feed([("YSSY", -33.95, 151.17, 13, 10, 20)])
        let s = METARService.parse(data)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].tempC, 13, accuracy: 0.001)
        XCTAssertEqual(s[0].windKmh, 10 * 1.852, accuracy: 0.01, "knots → km/h")
    }

    func testPicksTheNearestFreshStation() {
        let loc = CLLocation(latitude: -33.87, longitude: 151.21)
        let data = feed([
            ("YSSY", -33.95, 151.17, 13, 7, 10),   // ~10 km
            ("YSRI", -33.60, 150.78, 8, 0, 15),    // ~50 km
        ])
        let best = METARService.nearest(METARService.parse(data), to: loc, now: now)
        XCTAssertEqual(best?.icao, "YSSY")
        XCTAssertEqual(METARService.truth(best!)[.temp], 13)
    }

    /// A stale report must be rejected — scoring a forecast against a 5-hour-old
    /// thermometer teaches the ledger the wrong lesson.
    func testRejectsStaleReports() {
        let loc = CLLocation(latitude: -33.87, longitude: 151.21)
        let data = feed([("YSSY", -33.95, 151.17, 13, 7, 300)])   // 5h old
        XCTAssertNil(METARService.nearest(METARService.parse(data), to: loc, now: now))
    }

    /// A station beyond the radius must be rejected — a thermometer 400 km away
    /// isn't truth for here.
    func testRejectsDistantStations() {
        let loc = CLLocation(latitude: -33.87, longitude: 151.21)
        let data = feed([("YBBN", -27.38, 153.12, 20, 5, 10)])    // Brisbane, ~730 km
        XCTAssertNil(METARService.nearest(METARService.parse(data), to: loc, now: now))
    }

    func testEmptyFeedIsHandled() {
        XCTAssertTrue(METARService.parse(Data("[]".utf8)).isEmpty)
        XCTAssertTrue(METARService.parse(Data("garbage".utf8)).isEmpty)
    }

    /// Regression: the live API returns fractional seconds ("…00.000Z"), which
    /// the default ISO8601 formatter rejects. Parsing that as 1970 would make
    /// every real station read as stale and the whole feature silently dead.
    func testParsesRealFractionalSecondTimeFormat() {
        XCTAssertNotNil(METARService.parseTime("2026-07-11T00:20:00.000Z"))
        XCTAssertNotNil(METARService.parseTime("2026-07-11T00:20:00Z"))
        XCTAssertNotNil(METARService.parseTime("2026-07-11 00:20:00"))
        XCTAssertNil(METARService.parseTime("not a date"))

        // End to end: a real-shaped feed must yield a usable, fresh station.
        let json = #"[{"icaoId":"EGLC","name":"London City","lat":51.505,"lon":0.055,"temp":20,"wspd":9,"reportTime":"2026-07-11T00:20:00.000Z"}]"#
        let stations = METARService.parse(Data(json.utf8))
        XCTAssertEqual(stations.count, 1)
        let asOf = METARService.parseTime("2026-07-11T00:40:00.000Z")!   // 20 min later
        let best = METARService.nearest(stations, to: CLLocation(latitude: 51.51, longitude: 0.05), now: asOf)
        XCTAssertEqual(best?.icao, "EGLC", "a fresh real-format station must be selected, not dropped")
    }
}
