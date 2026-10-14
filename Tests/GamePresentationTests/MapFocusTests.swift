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

    /// #593: the zoom buttons in the bottom-trailing corner push in the
    /// side, which leaves more of a phone held sideways; the layer buttons
    /// along the bottom-leading edge push in the bottom.
    func testTheCornersPushInTheEdgeThatLeavesMoreOfTheView() {
        let zoom = ScreenFrame(x: 666, y: 248, width: 68, height: 112)
        let layers = ScreenFrame(x: 12, y: 304, width: 200, height: 56)
        let insets = ScreenInsets(top: 40).clearing([zoom, layers, ScreenFrame(x: 0, y: 0, width: 0, height: 0)], viewport: phone)
        XCTAssertEqual(insets, ScreenInsets(top: 40, leading: 0, bottom: 68, trailing: 68))
        // Never less than the insets already were.
        XCTAssertEqual(ScreenInsets(trailing: 300).clearing([zoom], viewport: phone).trailing, 300)
    }

    /// #593: a game opens with what it has built clear of the corners'
    /// controls, so no station is under the zoom buttons.
    func testTheOpeningCameraKeepsTheFocusClearOfTheControls() {
        let built = WorldRegion(minX: 100_000, minY: 100_000, maxX: 160_000, maxY: 130_000)
        let insets = ScreenInsets(top: 40, leading: 0, bottom: 68, trailing: 68)
        let camera = PlanCamera(bounds: map, viewport: phone, showing: built, clearOf: insets)
        for corner in [(built.minX, built.minY), (built.maxX, built.maxY), (built.minX, built.maxY), (built.maxX, built.minY)] {
            let point = WorldCoordinate(x: Int64(corner.0), y: Int64(corner.1))
            XCTAssertTrue(camera.showsClear(point, of: insets), "\(point)")
        }
        // Without insets it opens as it always did.
        let plain = PlanCamera(bounds: map, viewport: phone, showing: built)
        XCTAssertEqual(PlanCamera(bounds: map, viewport: phone, showing: built, clearOf: ScreenInsets()), plain)
        XCTAssertLessThanOrEqual(camera.pointsPerUnit, plain.pointsPerUnit)
        // Balanced, it opens on the same middle, only farther out.
        let balanced = PlanCamera(bounds: map, viewport: phone, showing: built, clearOf: insets.balanced)
        XCTAssertEqual(insets.balanced, ScreenInsets(top: 68, leading: 68, bottom: 68, trailing: 68))
        XCTAssertEqual(balanced.centerX, plain.centerX, accuracy: 0.001)
        XCTAssertEqual(balanced.centerY, plain.centerY, accuracy: 0.001)
        for corner in [(built.minX, built.minY), (built.maxX, built.maxY)] {
            XCTAssertTrue(balanced.showsClear(WorldCoordinate(x: Int64(corner.0), y: Int64(corner.1)), of: insets))
        }
    }
}

private extension PlanCamera {
    func worldDistanceDouble(_ points: Double) -> Double {
        points / pointsPerUnit
    }
}
