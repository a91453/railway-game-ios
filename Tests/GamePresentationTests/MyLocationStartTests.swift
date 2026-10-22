import GameCore
@testable import GamePresentation
import XCTest

/// Decision 335: where "Use my location" moves the real-world picker's
/// frame, and what it says when it cannot or when the place cannot grow.
///
/// Expected values are worked out from the rules, never taken from a
/// previous run.
final class MyLocationStartTests: XCTestCase {
    /// In Taiwan the frame goes where the device is, to the nearest
    /// hundredth of a degree (about 1 km), as a tap there would put it
    /// (decision 312), and nothing is said.
    func testALocationInTaiwanMovesTheFrameThere() throws {
        let fix = MyLocationStart.located(latitude: 22.6394, longitude: 120.3024)
        let area = try XCTUnwrap(fix.area)
        XCTAssertEqual(area, RealWorldStartArea(latitude: 22.64, longitude: 120.30))
        XCTAssertEqual(area.middle.latitudeDegrees, 22.64, accuracy: 1e-7)
        XCTAssertEqual(area.middle.longitudeDegrees, 120.30, accuracy: 1e-7)
        XCTAssertTrue(area.buysMoreLand)
        XCTAssertFalse(fix.isKeptOnMap)
        XCTAssertNil(fix.message(in: .english))
        XCTAssertNil(fix.message(in: .traditionalChinese))
    }

    /// Outside the island and Penghu the frame still goes there, but that
    /// map stays 16 km (decision 167), and the line says so; Kinmen too,
    /// which is outside the island's box.
    func testOutsideTaiwanTheFrameMovesAndTheLineSaysItCannotGrow() throws {
        for (latitude, longitude, rounded) in [(35.681, 139.767, 35.68), (24.4329, 118.3171, 24.43)] {
            let fix = MyLocationStart.located(latitude: latitude, longitude: longitude)
            let area = try XCTUnwrap(fix.area)
            XCTAssertFalse(area.buysMoreLand)
            XCTAssertEqual(area.middle.latitudeDegrees, rounded, accuracy: 1e-7)
            XCTAssertFalse(fix.isKeptOnMap)
            XCTAssertEqual(
                fix.message(in: .english),
                "You're outside Taiwan's main island and Penghu. The square is on your location, but a map here stays this size. Pick a place there to buy more land later."
            )
            XCTAssertEqual(
                fix.message(in: .traditionalChinese),
                "你在台灣本島與澎湖以外。方框已移到你的位置，但這裡的地圖之後不會再擴大；選本島或澎湖的地點，之後才能買地擴大。"
            )
        }
    }

    /// Beyond about 85° the map ends: the frame stops at its edge, at the
    /// same longitude, and the line says why.
    func testNearAPoleTheFrameStopsAtTheMapsEdge() throws {
        let fix = MyLocationStart.located(latitude: -89.5, longitude: 0)
        let area = try XCTUnwrap(fix.area)
        XCTAssertEqual(area.middle.latitudeDegrees, -RealWorldStartArea.maximumLatitude, accuracy: 1e-7)
        XCTAssertTrue(fix.isKeptOnMap)
        XCTAssertEqual(
            fix.message(in: .english),
            "The map doesn't reach that far north or south, so the square is as close to you as it goes. A map here stays this size."
        )
        XCTAssertFalse(MyLocationStart.located(latitude: RealWorldStartArea.maximumLatitude, longitude: 0).isKeptOnMap)
    }

    /// Turned off or not found: the frame stays and the line says how to
    /// go on without it.
    func testDeniedAndFailedLeaveTheFrameAndSaySo() {
        XCTAssertNil(MyLocationStart.denied.area)
        XCTAssertNil(MyLocationStart.failed.area)
        XCTAssertEqual(
            MyLocationStart.denied.message(in: .english),
            "Location is off for this app. Search for a place or move the map instead, or turn location on in Settings."
        )
        XCTAssertEqual(
            MyLocationStart.denied.message(in: .traditionalChinese),
            "這個 App 的定位已關閉。請改用搜尋或移動地圖，或到「設定」開啟定位。"
        )
        XCTAssertEqual(
            MyLocationStart.failed.message(in: .english),
            "Couldn't find your location. Search for a place or move the map instead."
        )
        XCTAssertEqual(MyLocationStart.failed.message(in: .traditionalChinese), "找不到你的位置。請改用搜尋或移動地圖。")
    }

    /// A fix that is not a number moves nothing and reads as not found.
    func testAFixThatIsNotANumberIsAFailure() {
        let fix = MyLocationStart.located(latitude: .nan, longitude: 121)
        XCTAssertNil(fix.area)
        XCTAssertFalse(fix.isKeptOnMap)
        XCTAssertEqual(fix.message(in: .english), MyLocationStart.failed.message(in: .english))
    }
}
