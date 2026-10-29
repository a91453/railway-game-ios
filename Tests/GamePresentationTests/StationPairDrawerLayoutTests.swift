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

    // Decision 491 (TestFlight 95.1): iPads held upright, a new line's
    // stations picked with the line panel open beside the map. The panel
    // takes half the width (``SidePanelWidth``), the map's coverage, 3D and
    // zoom buttons stand beside it at the foot of the map, and the
    // building tools run down the leading edge.
    private struct Upright {
        let name: String
        let width: Double, height: Double
        /// The map's corner column, measured from the screen's trailing
        /// and bottom edges: the three buttons in a row and their margins,
        /// or with a layer's key over them.
        let corner: Double, cornerHeight: Double
    }

    private let uprights = [
        Upright(name: "iPad Air 11-inch", width: 820, height: 1180, corner: 3 * 44 + 2 * 10, cornerHeight: 90 + 44 + 2 * 10),
        Upright(name: "iPad Air 11-inch, a layer's key", width: 820, height: 1180, corner: 260 + 2 * 10, cornerHeight: 90 + 44 + 160 + 2 * 10),
        Upright(name: "iPad Pro 13-inch", width: 1032, height: 1376, corner: 3 * 44 + 2 * 10, cornerHeight: 90 + 44 + 2 * 10),
    ]
    /// The dock along the bottom (not a tools column), 80 tall, and the
    /// drawer's foot above it as ContentView lays it out.
    private let dockHeight = 80.0
    private var uprightBottom: Double { dockHeight + 2 * margin }
    private var railEnd: Double { margin + ToolColumn.railWidth }

    private func uprightInsets(_ ipad: Upright) -> (panel: Double, insets: StationPairDrawerLayout.Insets?) {
        let panel = SidePanelWidth.panel(screenWidth: ipad.width, compactHeight: false) + margin
        let insets = StationPairDrawerLayout.insets(
            screenWidth: ipad.width, margin: margin, leading: 0, rail: ToolColumn.railWidth + margin,
            panel: panel, card: 0, corner: panel + ipad.corner, cornerHeight: ipad.cornerHeight, bottom: uprightBottom
        )
        return (panel, insets)
    }

    func testOnAnUprightIPadTheBandBesideTheCornerButtonsIsTooNarrow() {
        // Before: the drawer's band ended at the corner buttons beside the
        // panel, narrower than its top line and bars, or none at all.
        for ipad in uprights where ipad.width < 1000 {
            let panel = SidePanelWidth.panel(screenWidth: ipad.width, compactHeight: false) + margin
            let trailing = StationPairDrawerLayout.trailingInset(panel: panel, card: 0, corner: panel + ipad.corner)
            let before = StationPairDrawerLayout.frame(
                size: ScreenSize(width: 460, height: 130), screenWidth: ipad.width, screenHeight: ipad.height,
                leading: 0, trailing: trailing, bottom: uprightBottom, margin: margin
            )
            XCTAssertLessThan(before.width, StationPairDrawerLayout.minimumWidth, "\(ipad.name): \(before)")
            XCTAssertLessThan(before.x, railEnd, "\(ipad.name): over the building tools")
        }
    }

    func testOnAnUprightIPadTheDrawerStandsAboveTheCornerButtons() {
        for ipad in uprights {
            let (panel, found) = uprightInsets(ipad)
            guard let insets = found else { return XCTFail("\(ipad.name): the drawer shows") }
            let size = ScreenSize(width: 460, height: 130)
            let drawer = StationPairDrawerLayout.frame(
                size: size, screenWidth: ipad.width, screenHeight: ipad.height,
                leading: insets.leading, trailing: insets.trailing, bottom: insets.bottom, margin: margin
            )
            XCTAssertGreaterThanOrEqual(drawer.width, StationPairDrawerLayout.minimumWidth, ipad.name)
            XCTAssertGreaterThanOrEqual(drawer.x, 0, "\(ipad.name): on the screen")
            XCTAssertLessThanOrEqual(drawer.x + drawer.width, ipad.width - panel, "\(ipad.name): clear of the panel")
            let cornerButtons = ScreenFrame(
                x: ipad.width - panel - ipad.corner, y: ipad.height - ipad.cornerHeight, width: ipad.corner, height: ipad.cornerHeight
            )
            XCTAssertFalse(overlaps(drawer, cornerButtons), "\(ipad.name): \(drawer) and \(cornerButtons)")
            let dock = ScreenFrame(x: 0, y: ipad.height - dockHeight, width: ipad.width, height: dockHeight)
            XCTAssertFalse(overlaps(drawer, dock), "\(ipad.name): over the dock")
            if insets.bottom > uprightBottom {
                // Raised along the leading edge, past the building tools.
                XCTAssertGreaterThanOrEqual(drawer.x, railEnd + margin, "\(ipad.name): clear of the building tools")
            }
        }
    }

    func testOnAnIPadOnItsSideTheDrawerStaysWhereItWas() {
        // Landscape keeps decision 384's band beside the corner buttons.
        let width = 1180.0
        let panel = SidePanelWidth.panel(screenWidth: width, compactHeight: false) + margin
        for corner in [0, panel + 152] {
            let insets = StationPairDrawerLayout.insets(
                screenWidth: width, margin: margin, leading: 0, rail: ToolColumn.railWidth + margin,
                panel: panel, card: 0, corner: corner, cornerHeight: 154, bottom: uprightBottom
            )
            XCTAssertEqual(insets, StationPairDrawerLayout.Insets(
                leading: 0, trailing: StationPairDrawerLayout.trailingInset(panel: panel, card: 0, corner: corner), bottom: uprightBottom
            ))
        }
        // And with nothing beside the map, upright too.
        XCTAssertEqual(
            StationPairDrawerLayout.insets(
                screenWidth: 820, margin: margin, leading: 0, rail: 0, panel: 0, card: 0, corner: 162, cornerHeight: 300, bottom: uprightBottom
            ),
            StationPairDrawerLayout.Insets(leading: 0, trailing: 162, bottom: uprightBottom)
        )
    }

    func testWithNoRoomEvenBesideThePanelTheDrawerStaysAway() {
        // An iPad mini held upright: beside its panel and the building
        // tools, less than the drawer needs; the ✓ pill's words still give
        // the line's length and time.
        let width = 744.0
        let panel = SidePanelWidth.panel(screenWidth: width, compactHeight: false) + margin
        XCTAssertNil(StationPairDrawerLayout.insets(
            screenWidth: width, margin: margin, leading: 0, rail: ToolColumn.railWidth + margin,
            panel: panel, card: 0, corner: panel + 152, cornerHeight: 154, bottom: uprightBottom
        ))
    }
}
