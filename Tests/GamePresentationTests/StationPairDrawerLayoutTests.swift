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

    /// On a phone on its side the drawer rides in the map's pill, beside
    /// its words and its ✕ ↶ ✓, open or folded; before, open, it stood
    /// over the ✓ (decision 384's first version, the planner's review).
    func testOnTheSmallestPhonesTheOpenDrawerKeepsOffTheCheck() {
        XCTAssertTrue(StationPairDrawerLayout.ridesInPill(compactHeight: true), "A phone on its side")
        XCTAssertFalse(StationPairDrawerLayout.ridesInPill(compactHeight: false), "An iPad keeps it over the dock")
        // The map's points (it runs under the safe area): an iPhone SE and
        // a 13 mini on their sides, the smallest the app runs on (iOS 17),
        // with a real-world map's credits band of 30. Above the pill, the
        // status bar and the layer strip (ContentView's `mapTop`); below
        // it, the station master standing at the column's foot and a
        // margin (`dockBottom`); beside it, the tools column.
        let phones: [(name: String, width: Double, height: Double, safe: ScreenInsets)] = [
            ("SE", 667, 375, ScreenInsets(top: 0, leading: 0, bottom: 0, trailing: 0)),
            ("13 mini", 812, 375, ScreenInsets(top: 0, leading: 50, bottom: 21, trailing: 50)),
        ]
        let margin = BuildConfirmLayout.margin, padding = StationPairDrawerLayout.pillPadding
        for phone in phones {
            let top = phone.safe.top + 10 + 44 + 10 + 36
            let bottom = phone.safe.bottom + 30 + 44 + 25 + 10
            let leading = phone.safe.leading + 10 + ToolColumn.width
            let available = phone.height - top - bottom - 2 * margin
            let pillWidth = BuildConfirmLayout.maximumWidth(viewportWidth: phone.width, leading: leading, trailing: phone.safe.trailing)
            guard let maximum = StationPairDrawerLayout.maximumHeightInPill(available: available, pillWidth: pillWidth) else {
                return XCTFail("\(phone.name): the drawer fits in the pill")
            }
            // Open: its top line and five figures' bars (15 tall, 6 apart),
            // scrolling in the room left.
            let bars = min(5 * 15 + 4 * 6.0, StationPairDrawerLayout.barsRoom(maximumHeight: maximum))
            XCTAssertGreaterThan(bars, 15, "\(phone.name): a figure's bars show at least")
            let drawerHeight = StationPairDrawerLayout.foldedHeight + (bars > 0 ? 6 + bars : 0)
            XCTAssertLessThanOrEqual(drawerHeight, maximum, phone.name)
            // The pill's words: the line's length, time and price on two
            // lines, its contents on one, and the buttons.
            let words = ScreenSize(width: pillWidth - 2 * padding - StationPairDrawerLayout.widthInPill - StationPairDrawerLayout.pillSpacing, height: 3 * 16 + 4 + 40)
            XCTAssertGreaterThanOrEqual(words.width, BuildConfirmLayout.minimumWidth, phone.name)
            let pillHeight = 2 * padding + max(drawerHeight, words.height)
            // Its last station picked low on the map: the pill is held to
            // the clear band, whole.
            let pillY = min(max(phone.height - 60, top + margin), phone.height - bottom - margin - pillHeight)
            XCTAssertGreaterThanOrEqual(pillY, top + margin, "\(phone.name): under the status bar")
            let pillX = leading + margin
            let drawer = ScreenFrame(x: pillX + padding, y: pillY + padding, width: StationPairDrawerLayout.widthInPill, height: drawerHeight)
            let check = ScreenFrame(
                x: drawer.x + drawer.width + StationPairDrawerLayout.pillSpacing, y: pillY + padding,
                width: words.width, height: words.height
            )
            XCTAssertFalse(overlaps(drawer, check), "\(phone.name): \(drawer) and \(check)")
            XCTAssertLessThanOrEqual(check.x + check.width + padding, phone.width - phone.safe.trailing - margin, "\(phone.name): within the map")
        }
    }

    func testTheDrawerStaysOutOfThePillWithoutRoom() {
        // Too short for its top line.
        XCTAssertNil(StationPairDrawerLayout.maximumHeightInPill(available: 60, pillWidth: 600))
        // Too narrow beside the narrowest words (a card open beside it).
        XCTAssertNil(StationPairDrawerLayout.maximumHeightInPill(available: 200, pillWidth: 400))
        XCTAssertEqual(StationPairDrawerLayout.maximumHeightInPill(available: 200, pillWidth: 600), 200 - 12)
        XCTAssertEqual(StationPairDrawerLayout.barsRoom(maximumHeight: StationPairDrawerLayout.foldedHeight), 0)
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
