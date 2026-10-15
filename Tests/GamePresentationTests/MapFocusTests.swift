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

    /// The PR #627–#646 review: choosing a tile to buy shows the tiles
    /// for sale above the map expansion's pill, which grows along the
    /// bottom from the bottom-leading corner once choosing starts; a
    /// narrow row there would otherwise push in only the side, and the
    /// tile below the land lay under the pill's Done.
    func testTheTilesForSaleShowAboveTheExpansionsRow() {
        let row = ScreenFrame(x: 60, y: 260, width: 56, height: 100)
        let cover = MapCover(edges: ScreenInsets(top: 40, leading: 48), corners: [row])
        XCTAssertEqual(cover.framing(in: phone).bottom, 0, "the row pushes in the side")
        let framing = cover.framing(above: row, in: phone)
        XCTAssertEqual(framing.bottom, 112)
        XCTAssertEqual(framing.leading, cover.framing(in: phone).leading)
        let tiles = WorldRegion(minX: 120_000, minY: 120_000, maxX: 140_000, maxY: 140_000)
        let camera = PlanCamera(bounds: map, viewport: phone, showing: tiles, clearOf: framing)
        let bottom = camera.screenPoint(of: WorldCoordinate(x: 130_000, y: 140_000))
        XCTAssertLessThanOrEqual(bottom.y, row.y, "the bottom tiles end above the row")
        // A row not laid out yet pushes nothing more.
        XCTAssertEqual(cover.framing(above: ScreenFrame(x: 0, y: 0, width: 0, height: 0), in: phone), cover.framing(in: phone))
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

        // A game opens as it always did unless a station it shows would be
        // under the controls.
        let middle = WorldCoordinate(x: 130_000, y: 115_000)
        XCTAssertEqual(PlanCamera.opening(bounds: map, viewport: phone, showing: built, keeping: [middle], clearOf: insets), plain)
        let corner = WorldCoordinate(x: Int64(built.maxX), y: Int64(built.maxY))
        XCTAssertFalse(plain.showsClear(corner, of: insets))
        let modest = ScreenInsets(top: 20, leading: 0, bottom: 40, trailing: 40)
        XCTAssertFalse(plain.showsClear(corner, of: modest))
        let opened = PlanCamera.opening(bounds: map, viewport: phone, showing: built, keeping: [middle, corner], clearOf: modest)
        XCTAssertTrue(opened.showsClear(corner, of: modest))
        // About the same middle, only farther out.
        XCTAssertEqual(opened.centerX, plain.centerX, accuracy: 0.001)
        XCTAssertEqual(opened.centerY, plain.centerY, accuracy: 0.001)
        XCTAssertLessThan(opened.pointsPerUnit, plain.pointsPerUnit)
        // Insets that leave only a small box keep the usual opening, not a
        // network shrunk into a corner.
        let crowded = ScreenInsets(top: 40, leading: 0, bottom: 200, trailing: 400)
        XCTAssertEqual(PlanCamera.opening(bounds: map, viewport: phone, showing: built, keeping: [middle, corner], clearOf: crowded), plain)
    }

    /// A frame still moving in (partly outside the view) or past half of
    /// it pushes nothing.
    func testFramesStillSettlingPushNothing() {
        let outside = ScreenFrame(x: 700, y: 300, width: 120, height: 112)
        let huge = ScreenFrame(x: 300, y: 100, width: 434, height: 272)
        XCTAssertEqual(ScreenInsets(top: 40).clearing([outside, huge], viewport: phone), ScreenInsets(top: 40))
    }

    /// A phone on its side with a layer's legend open in the
    /// bottom-trailing corner. The framing gives the legend the whole band
    /// of the view beside it; a selected station in that band, beside the
    /// legend and not under it, stays where it is (it was moved every time
    /// the details card opened or closed).
    func testAStationBesideACornersControlStaysWhereItIs() throws {
        let camera = PlanCamera(bounds: map, viewport: phone).centered(on: WorldCoordinate(x: 131_072, y: 131_072))
        let legend = ScreenFrame(x: 500, y: 200, width: 222, height: 160)
        let cover = MapCover(edges: ScreenInsets(top: 40), corners: [legend])
        let framing = cover.framing(in: phone)
        XCTAssertEqual(framing, ScreenInsets(top: 40, leading: 0, bottom: 0, trailing: 234))

        let beside = camera.world(at: ScreenPoint(x: 600, y: 120))
        // What the map did: in the legend's band, so moved.
        XCTAssertFalse(camera.showsClear(beside, of: framing))
        XCTAssertFalse(camera.hides(beside, under: cover))
        XCTAssertNil(camera.keepingClear(beside, of: cover))

        // Under the legend itself it moves into the middle of the map the
        // framing leaves.
        let under = camera.world(at: ScreenPoint(x: 600, y: 300))
        XCTAssertTrue(camera.hides(under, under: cover))
        let moved = try XCTUnwrap(camera.keepingClear(under, of: cover))
        XCTAssertEqual(moved.screenPoint(of: under).x, 250, accuracy: 1)
        XCTAssertEqual(moved.screenPoint(of: under).y, 206, accuracy: 1)
        // Once there, opening or closing the card again leaves it.
        XCTAssertNil(moved.keepingClear(under, of: cover))
        XCTAssertNil(moved.keepingClear(under, of: MapCover(edges: ScreenInsets(top: 40, trailing: 257), corners: [legend])))
    }

    /// Where the framing leaves less than a fingertip down (the top
    /// column and the corners' controls on a short phone), a station keeps
    /// its height: one under a panel moves only across, one only under the
    /// top column does not move.
    func testATinyClearBoxKeepsTheStationAlongThatAxis() throws {
        let camera = PlanCamera(bounds: map, viewport: phone).centered(on: WorldCoordinate(x: 131_072, y: 131_072))
        let cover = MapCover(edges: ScreenInsets(top: 200, bottom: 140, trailing: 274))
        let framing = cover.framing(in: phone)

        let underPanel = camera.world(at: ScreenPoint(x: 600, y: 250))
        let moved = try XCTUnwrap(camera.keepingClear(underPanel, of: cover))
        XCTAssertEqual(moved.screenPoint(of: underPanel).x, 230, accuracy: 1)
        XCTAssertEqual(moved.screenPoint(of: underPanel).y, 250, accuracy: 1)
        // What the map did: down into the 32-point strip between them.
        XCTAssertEqual(camera.centered(on: underPanel, clearOf: framing).screenPoint(of: underPanel).y, 216, accuracy: 1)

        let underColumn = camera.world(at: ScreenPoint(x: 300, y: 100))
        XCTAssertFalse(camera.showsClear(underColumn, of: framing))
        XCTAssertNil(camera.keepingClear(underColumn, of: cover))

        // Insets that leave nothing down: the map moved it to the view's
        // middle, under the top column; it keeps its height.
        let crowded = MapCover(edges: ScreenInsets(top: 200, bottom: 200, trailing: 274))
        XCTAssertEqual(camera.centered(on: underPanel, clearOf: crowded.framing(in: phone)).screenPoint(of: underPanel).y, 186, accuracy: 1)
        let kept = try XCTUnwrap(camera.keepingClear(underPanel, of: crowded))
        XCTAssertEqual(kept.screenPoint(of: underPanel).y, 250, accuracy: 1)
        XCTAssertEqual(kept.centerY, camera.centerY, accuracy: 0.001)

        // A station out of the view comes into it: to the view's middle
        // along the axis with no room.
        let away = camera.world(at: ScreenPoint(x: 300, y: 900))
        XCTAssertTrue(camera.hides(away, under: cover))
        let brought = try XCTUnwrap(camera.keepingClear(away, of: cover))
        XCTAssertEqual(brought.screenPoint(of: away).x, 230, accuracy: 1)
        XCTAssertEqual(brought.screenPoint(of: away).y, 186, accuracy: 1)
    }
}

private extension PlanCamera {
    func world(at point: ScreenPoint) -> WorldCoordinate {
        let position = worldPosition(at: point)
        return WorldCoordinate(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
    }

    func worldDistanceDouble(_ points: Double) -> Double {
        points / pointsPerUnit
    }
}
