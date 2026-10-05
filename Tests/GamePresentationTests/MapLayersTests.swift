import GameCore
import GamePresentation
import XCTest

final class MapLayersTests: XCTestCase {
    func testDefaultPreferencesHaveAllLayersEnabled() {
        let prefs = MapLayerPreferences.default
        XCTAssertTrue(prefs.showsStationNames)
        XCTAssertTrue(prefs.showsWaitingCounts)
        XCTAssertTrue(prefs.showsCatchmentRings)
    }

    func testPreferencesEqualityAndMutation() {
        var a = MapLayerPreferences()
        var b = MapLayerPreferences()
        XCTAssertEqual(a, b)

        a.showsCatchmentRings = false
        XCTAssertNotEqual(a, b)

        b.showsCatchmentRings = false
        XCTAssertEqual(a, b)

        a.showsStationNames = false
        XCTAssertNotEqual(a, b)

        a.showsWaitingCounts = false
        XCTAssertFalse(a.showsWaitingCounts)
    }

    func testStationCatchmentRadiusIs800Metres() {
        XCTAssertEqual(StationDemand.catchmentRadius, 800.0, "Station catchment radius must be exactly 800 metres (ten minutes walk)")
    }
}
