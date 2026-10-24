import GamePresentation
import XCTest

/// Decision 226, later (TestFlight, 2026-10-16): the phone's tools column.
final class ToolColumnTests: XCTestCase {
    func testTheColumnIsAsWideAsOn66_1() {
        // TestFlight 67.1 beside 66.1: the phone's column back to 66.1's
        // width, a button of 48 points (the narrowest a named button was)
        // and the glass either side.
        XCTAssertEqual(ToolColumn.buttonWidth, 48)
        XCTAssertEqual(ToolColumn.width, 56)
        XCTAssertEqual(ToolColumn.buttonWidth + 2 * ToolColumn.tilePadding, ToolColumn.width)
    }

    func testTheBuildingToolsBesideTheMapKeep66_1sWidth() {
        // The rail beside the map (an iPad's) was 72
        // points on 66.1, and stays so: its buttons are 64.
        XCTAssertEqual(ToolColumn.railWidth, 72)
        XCTAssertEqual(ToolColumn.railButtonWidth + 2 * ToolColumn.tilePadding, ToolColumn.railWidth)
    }

    func testTheColumnStopsAGapBelowTheLayerStrip() {
        // An iPhone 17 Pro on its side, 382 points inside the safe area:
        // the board's foot at 54, the strip 36 high under it after a gap of
        // 10, so the strip's foot is at 100; the column 10 above the foot.
        let height = ToolColumn.maxHeight(screenHeight: 382, top: 100, gap: 10, bottom: 10)
        XCTAssertEqual(height, 262)
        // Its top is then the gap below the strip, as the strip is below
        // the board.
        XCTAssertEqual(382 - 10 - height - 100, 10)
    }

    func testAShortScreenStillLeavesTheColumnSomeRoom() {
        XCTAssertEqual(ToolColumn.maxHeight(screenHeight: 120, top: 100, gap: 10, bottom: 10), 60)
    }

    /// Decision 382, later (TestFlight 85.1): while building, the column
    /// on the smallest phones on their side.
    func testTheBuildingColumnFitsTheSmallestPhoneOrIsCutBetweenButtons() {
        // The card's toggle, the track, train and building tools with Done,
        // and Build: 48 + 6 + 180 + 6 + 48.
        XCTAssertEqual(ToolColumn.buildingHeight(tools: 3, toggle: true), 288)
        // An iPhone SE on its side (375, no safe area), the board's foot at
        // 54, no layer strip while building: all of it fits.
        let se = ToolColumn.maxHeight(screenHeight: 375, top: 54, gap: 10, bottom: 10)
        XCTAssertGreaterThanOrEqual(se, ToolColumn.buildingHeight(tools: 3, toggle: true))
        // Where it does not, Done and Build stand at the foot, apart: the
        // part over them, the three tools and the toggle, is 136 + 6 + 48.
        XCTAssertEqual(ToolColumn.buildingScrollHeight(maxHeight: se, tools: 3, toggle: true), 190)
        // A 13 mini (354 inside the safe area), and an SE, with a
        // real-world map's credits (30) under the column: it does not fit,
        // and Done and Build stand whole under a part cut between two
        // buttons.
        for screenHeight in [354.0, 375] {
            let maxHeight = ToolColumn.maxHeight(screenHeight: screenHeight, top: 54, gap: 10, bottom: 30 + 10)
            XCTAssertLessThan(maxHeight, ToolColumn.buildingHeight(tools: 3, toggle: true))
            let shown = ToolColumn.buildingScrollHeight(maxHeight: maxHeight, tools: 3, toggle: true)
            XCTAssertLessThanOrEqual(shown + 2 * (ToolColumn.tileGap + ToolColumn.tileHeight(buttons: 1)), maxHeight)
            // The cut falls in a gap: every button above it whole.
            var buttons: [(top: Double, foot: Double)] = (0..<3).map { index in
                let top = ToolColumn.tilePadding + Double(index) * (40 + ToolColumn.buttonSpacing)
                return (top, top + 40)
            }
            let toggle = ToolColumn.tileHeight(buttons: 3) + ToolColumn.tileGap + ToolColumn.tilePadding
            buttons.append((toggle, toggle + 40))
            XCTAssertFalse(buttons.contains { $0.top < shown && shown < $0.foot }, "\(screenHeight): cut at \(shown)")
            // The three tools whole, the toggle under them scrolling; Done
            // and Build below, never scrolled away.
            XCTAssertEqual(buttons.filter { $0.foot <= shown }.count, 3, "\(screenHeight)")
        }
        // In a lesson's first steps: fewer tools, no toggle; all of it fits.
        XCTAssertEqual(ToolColumn.buildingScrollHeight(maxHeight: 250, tools: 1, toggle: false), ToolColumn.tileHeight(buttons: 1))
    }
}
