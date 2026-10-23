import GamePresentation
import XCTest

/// Decision 384 (TestFlight 85.1): the new line's station pair drawer
/// covered the map's ✓ and the small map and zoom buttons.
final class StationPairDrawerLayoutTests: XCTestCase {
    // An iPhone 17 Pro on its side, inside the safe area (62 each side,
    // 21 below) as ContentView lays out: 750 by 381, a real-world map's
    // credits band of 30 at the foot.
    private let width = 750.0, height = 381.0, margin = 10.0
    /// The tools column and its margin (decision 226).
    private var leading: Double { margin + ToolColumn.width }
    /// The drawer's foot: the credits' band, the station master standing
    /// at the column's foot and two margins.
    private let bottom = 30.0 + 52 + 10 + 2 * 10
    /// The map's bottom-trailing column as the screenshot had it: the
    /// small map (with its lock) over the coverage, 3D and zoom buttons.
    private var corner: ScreenFrame { ScreenFrame(x: width - 10 - 188, y: height - 30 - 10 - 174, width: 188, height: 174) }

    private func drawer(folded: Bool, trailing: Double) -> ScreenFrame {
        StationPairDrawerLayout.frame(
            size: ScreenSize(width: 460, height: folded ? 52 : 130), screenWidth: width, screenHeight: height,
            leading: leading, trailing: trailing, bottom: bottom, margin: margin
        )
    }

    private func overlaps(_ a: ScreenFrame, _ b: ScreenFrame) -> Bool {
        BuildConfirmLayout.overlaps(x: a.x, y: a.y, width: a.width, height: a.height, b)
    }

    func testTheDrawerLeavesTheSmallMapAndTheZoomButtons() {
        // Before: only a panel beside the map moved it.
        let before = drawer(folded: false, trailing: 0)
        XCTAssertTrue(overlaps(before, corner), "The screenshot: \(before) over \(corner)")
        let trailing = StationPairDrawerLayout.trailingInset(panel: 0, card: 0, corner: width - corner.x)
        let after = drawer(folded: false, trailing: trailing)
        XCTAssertFalse(overlaps(after, corner), "\(after) and \(corner)")
        XCTAssertGreaterThanOrEqual(after.x, leading + margin, "Clear of the tools column")
    }

    func testTheDrawerLeavesTheDetailsCard() {
        // The details card down the trailing side, 300 wide with its margin.
        let card = ScreenFrame(x: width - 10 - 290, y: 54 + 10, width: 290, height: height - 64 - 10)
        let trailing = StationPairDrawerLayout.trailingInset(panel: 0, card: 290 + margin, corner: width - corner.x)
        XCTAssertEqual(trailing, 300)
        XCTAssertFalse(overlaps(drawer(folded: true, trailing: trailing), card))
    }

    func testTheMapsCheckKeepsOffTheFoldedDrawer() {
        XCTAssertTrue(StationPairDrawerLayout.startsFolded(compactHeight: true), "A phone on its side")
        XCTAssertFalse(StationPairDrawerLayout.startsFolded(compactHeight: false), "An iPad keeps the bars open")
        let trailing = StationPairDrawerLayout.trailingInset(panel: 0, card: 0, corner: width - corner.x)
        let drawer = drawer(folded: true, trailing: trailing)
        // The ✕, ↶ and ✓ with the line's caption over them, under the last
        // station picked (小港 → 順苓), which stands just above the drawer.
        let pill = ScreenSize(width: 200, height: 76)
        let station = (x: drawer.x + drawer.width / 2, y: drawer.y - 10)
        let highest = 54 + 10 + 46 + 10.0 // under the board and the layer strip
        let placed = BuildConfirmLayout.keepingOff(
            [drawer, corner], x: station.x - pill.width / 2, y: station.y + 22, width: pill.width, height: pill.height,
            minX: leading + 8, maxX: width - trailing - pill.width - 8, highest: highest
        )
        let frame = ScreenFrame(x: placed.x, y: placed.y, width: pill.width, height: pill.height)
        XCTAssertFalse(overlaps(frame, drawer), "\(frame) and \(drawer)")
        XCTAssertFalse(overlaps(frame, corner), "\(frame) and \(corner)")
        XCTAssertGreaterThanOrEqual(frame.y, highest)
    }

    func testTheCheckKeepsOffBesideWhenThereIsNoRoomAbove() {
        // An obstacle reaching up to the top: the pill goes beside it.
        let wall = ScreenFrame(x: 300, y: 100, width: 100, height: 200)
        let placed = BuildConfirmLayout.keepingOff(
            [wall], x: 310, y: 150, width: 120, height: 50, minX: 20, maxX: 600, highest: 120
        )
        XCTAssertEqual(placed.x, 300 + 100 + BuildConfirmLayout.margin)
        XCTAssertEqual(placed.y, 150)
        XCTAssertFalse(BuildConfirmLayout.overlaps(x: placed.x, y: placed.y, width: 120, height: 50, wall))
    }
}
