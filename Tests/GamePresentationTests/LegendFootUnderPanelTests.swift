import GamePresentation
import XCTest

/// TestFlight 98.1: a layer's legend under a phone's open panel goes down
/// to the credits, clear of what stands at the bottom under it.
final class LegendFootUnderPanelTests: XCTestCase {
    // An iPhone on its side, 402 points tall: 21 of safe area and 30 of
    // credits under the map, the dock's foot 82 above that.
    private let mapHeight = 402.0
    private let screenBottom = 51.0
    private let standard = 133.0

    func testGoesDownToTheCreditsWithNothingUnderIt() {
        let foot = HUDMargins.legendFootUnderPanel(
            standard: standard, screenBottom: screenBottom, mapHeight: mapHeight,
            legendStart: 300, legendEnd: 480, beside: []
        )
        XCTAssertEqual(foot, screenBottom)
    }

    func testKeepsAboveTheStationMasterUnderIt() {
        // The avatar and its title, 69 tall, standing on the dock's foot.
        let master = ScreenFrame(x: 250, y: 402 - 51 - 10 - 69, width: 60, height: 69)
        let foot = HUDMargins.legendFootUnderPanel(
            standard: standard, screenBottom: screenBottom, mapHeight: mapHeight,
            legendStart: 300, legendEnd: 480, beside: [master]
        )
        XCTAssertEqual(foot, mapHeight - master.y)
        XCTAssertLessThanOrEqual(foot, standard)
    }

    func testIgnoresWhatStandsBesideIt() {
        let undo = ScreenFrame(x: 120, y: 300, width: 100, height: 44)
        let row = ScreenFrame(x: 600, y: 370, width: 150, height: 28)
        let foot = HUDMargins.legendFootUnderPanel(
            standard: standard, screenBottom: screenBottom, mapHeight: mapHeight,
            legendStart: 300, legendEnd: 480, beside: [undo, row, ScreenFrame(x: 0, y: 0, width: 0, height: 0)]
        )
        XCTAssertEqual(foot, screenBottom)
    }

    func testNeverHigherThanBefore() {
        let tall = ScreenFrame(x: 350, y: 100, width: 50, height: 300)
        let foot = HUDMargins.legendFootUnderPanel(
            standard: standard, screenBottom: screenBottom, mapHeight: mapHeight,
            legendStart: 300, legendEnd: 480, beside: [tall]
        )
        XCTAssertEqual(foot, standard)
    }
}
