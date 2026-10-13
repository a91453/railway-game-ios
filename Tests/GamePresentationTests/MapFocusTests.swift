import GameCore
import GamePresentation
import XCTest

/// Decision 106, later: narrower panels beside the map on a phone on its
/// side, and the camera putting the selection in the map they leave.
final class MapFocusTests: XCTestCase {
    private let map = try! WorldBounds(width: 262_144, height: 262_144)
    /// An iPhone 14 Pro on its side, inside the safe area.
    private let phone = ScreenSize(width: 734, height: 372)

    func testAPhoneOnItsSideKeepsAboutTwoThirdsOfTheMap() {
        XCTAssertEqual(SidePanelWidth.panel(screenWidth: 734, compactHeight: true), 264)
        XCTAssertEqual(SidePanelWidth.card(screenWidth: 734, compactHeight: true), 257)
        XCTAssertEqual(SidePanelWidth.panel(screenWidth: 932, compactHeight: true), 300)
        XCTAssertEqual(SidePanelWidth.card(screenWidth: 932, compactHeight: true), 300)
        // Otherwise as before.
        XCTAssertEqual(SidePanelWidth.panel(screenWidth: 734, compactHeight: false), 367)
        XCTAssertEqual(SidePanelWidth.panel(screenWidth: 1_180, compactHeight: false), 420)
        XCTAssertEqual(SidePanelWidth.card(screenWidth: 734, compactHeight: false), 294)
        XCTAssertEqual(SidePanelWidth.card(screenWidth: 1_180, compactHeight: false), 340)
    }

    func testAStationUnderThePanelMovesToTheMiddleOfTheMapBesideIt() {
        let camera = PlanCamera(bounds: map, viewport: phone).centered(on: WorldCoordinate(x: 131_072, y: 131_072))
        let insets = ScreenInsets(top: 40, trailing: 274)
        // The view's middle (x 367) is left of the panel (from x 460); a
        // point 250 points east of it is under the panel.
        let covered = WorldCoordinate(x: 131_072 + camera.worldDistance(250), y: 131_072)
        XCTAssertFalse(camera.showsClear(covered, of: insets))
        XCTAssertTrue(camera.showsClear(WorldCoordinate(x: 131_072, y: 131_072), of: insets))

        let moved = camera.centered(on: covered, clearOf: insets)
        let middle = moved.clearMiddle(insets)
        XCTAssertEqual(middle.x, 230, accuracy: 0.001)
        XCTAssertEqual(middle.y, 206, accuracy: 0.001)
        let shown = moved.screenPoint(of: covered)
        XCTAssertEqual(shown.x, middle.x, accuracy: 1)
        XCTAssertEqual(shown.y, middle.y, accuracy: 1)
        XCTAssertTrue(moved.showsClear(covered, of: insets))
    }

    func testNoInsetsIsTheViewsMiddle() {
        let camera = PlanCamera(bounds: map, viewport: phone)
        XCTAssertEqual(camera.clearMiddle(ScreenInsets()), ScreenPoint(x: 367, y: 186))
        // Insets that leave nothing count as none.
        XCTAssertEqual(camera.clearMiddle(ScreenInsets(leading: 400, trailing: 400)).x, 367)
    }

    func testALineIsZoomedOutToFitBesideThePanelButNeverIn() {
        let camera = PlanCamera(bounds: map, viewport: phone).centered(on: WorldCoordinate(x: 131_072, y: 131_072))
        let insets = ScreenInsets(trailing: 274)
        let long = WorldRegion(minX: 100_000, minY: 120_000, maxX: 100_000 + camera.worldDistanceDouble(800), maxY: 121_000)
        let fitted = camera.showing(long, clearOf: insets)
        XCTAssertLessThan(fitted.pointsPerUnit, camera.pointsPerUnit)
        for corner in [WorldCoordinate(x: Int64(long.minX), y: Int64(long.minY)), WorldCoordinate(x: Int64(long.maxX), y: Int64(long.maxY))] {
            XCTAssertTrue(fitted.showsClear(corner, of: insets), "\(corner)")
        }
        let short = WorldRegion(minX: 130_000, minY: 130_000, maxX: 130_100, maxY: 130_100)
        XCTAssertEqual(camera.showing(short, clearOf: insets).pointsPerUnit, camera.pointsPerUnit)
    }
}

private extension PlanCamera {
    func worldDistanceDouble(_ points: Double) -> Double {
        points / pointsPerUnit
    }
}
