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
    /// on the smallest phones on their side, cut between two buttons where
    /// it does not fit; 100.1 (decision 509): five tools over Build, Done
    /// beside it.
    func testTheBuildingColumnIsCutBetweenButtonsWhereItDoesNotFit() {
        // The five tools and Build: 224 + 6 + 48.
        XCTAssertEqual(ToolColumn.buildingHeight(tools: 5), 278)
        // A 13 mini (354 inside the safe area) and an SE (375), the
        // board's foot at 59, and 30 more under the column, as the
        // real-world map's credits took before 98.1: Build stands whole
        // under a part cut between two buttons.
        for screenHeight in [354.0, 375] {
            let maxHeight = ToolColumn.maxHeight(screenHeight: screenHeight, top: 59, gap: 10, bottom: 30 + 10)
            XCTAssertLessThan(maxHeight, ToolColumn.buildingHeight(tools: 5))
            let shown = ToolColumn.buildingScrollHeight(maxHeight: maxHeight, tools: 5, toggle: false)
            XCTAssertLessThanOrEqual(shown + ToolColumn.tileGap + ToolColumn.tileHeight(buttons: 1), maxHeight)
            let buttons: [(top: Double, foot: Double)] = (0..<5).map { index in
                let top = ToolColumn.tilePadding + Double(index) * (40 + ToolColumn.buttonSpacing)
                return (top, top + 40)
            }
            // The cut falls in a gap, or shows most of the next button
            // (``ToolColumn/peek``): no button shows less than half.
            for button in buttons where button.top < shown && shown < button.foot {
                XCTAssertGreaterThanOrEqual(shown - button.top, ToolColumn.compactButtonHeight / 2, "\(screenHeight): cut at \(shown)")
            }
            XCTAssertGreaterThanOrEqual(buttons.filter { $0.foot <= shown }.count, 4, "\(screenHeight)")
        }
        // In a lesson's first steps: fewer tools; all of it fits.
        XCTAssertEqual(ToolColumn.buildingScrollHeight(maxHeight: 250, tools: 1, toggle: false), ToolColumn.tileHeight(buttons: 1))
    }

    /// 98.1 (the owner, the planner): with the bus tool, four building
    /// tools, and the card's toggle beside Build rather than over them;
    /// 100.1 (decision 509): with zoning, five, and Done beside Build too.
    /// With Done in their group the five took 322, more than any phone on
    /// its side has; without it they take the 278 the four and Done took,
    /// and fit a phone on its side without scrolling. The room each phone
    /// leaves, inside its safe area, under the board's foot (about 59 on a
    /// Pro in the screenshots of run 41081038317) with the gap of 10 below
    /// it and 10 above the screen's foot. The column runs down beside a
    /// real-world map's credits (the planner's (a)), which start past it,
    /// so they take none of its room: the same on either map.
    func testFiveBuildingToolsFitAPhoneOnItsSide() {
        XCTAssertEqual(ToolColumn.buildingHeight(tools: 5), 278)
        XCTAssertEqual(ToolColumn.buildingHeight(tools: 5) + ToolColumn.compactButtonHeight + ToolColumn.buttonSpacing, 322,
                       "Done in the tools' group")
        func room(_ screenHeight: Double) -> Double {
            ToolColumn.maxHeight(screenHeight: screenHeight, top: 59, gap: 10, bottom: 10)
        }
        XCTAssertLessThan(room(381), 322, "with Done in the group, not even a 17 Pro")
        // iPhone 16 Pro, 17 Pro (402 tall, 381 inside), iPhone SE (375,
        // no home indicator), iPhone 14 to 16 (390 and 393, 369 and 372):
        // they fit.
        for height in [381.0, 375, 372, 369] {
            XCTAssertGreaterThanOrEqual(room(height), ToolColumn.buildingHeight(tools: 5), "\(height)")
        }
        // The 12 and 13 mini (375 tall, 354 inside) does not, by 3 points.
        // There the column scrolls (below).
        XCTAssertEqual(room(354), ToolColumn.buildingHeight(tools: 5) - 3)
    }

    /// Where they do not fit, the part that scrolls, at the column's top,
    /// shows the first tools whole and most of the next, fading, so it
    /// shows more is below (run 41081038317 cut cleanly after the building
    /// tool, the bus tool not there at all); Build whole under it.
    func testFiveBuildingToolsScrollFromTheColumnsTopWhereTheyDoNotFit() {
        let tools = 5
        let lastTop = ToolColumn.tilePadding + 4 * (ToolColumn.compactButtonHeight + ToolColumn.buttonSpacing)
        // The mini: the part takes all the room, 3 short of the column,
        // the last tool whole and only the glass under it cut.
        let mini = ToolColumn.maxHeight(screenHeight: 354, top: 59, gap: 10, bottom: 10)
        let room = mini - (ToolColumn.tileGap + ToolColumn.tileHeight(buttons: 1))
        let shown = ToolColumn.buildingScrollHeight(maxHeight: mini, tools: tools, toggle: false)
        XCTAssertEqual(shown, room)
        XCTAssertGreaterThanOrEqual(shown - lastTop, ToolColumn.compactButtonHeight)
        XCTAssertLessThan(shown, ToolColumn.tileHeight(buttons: tools))
        // Shorter still (196, the room the mini's column had before 98.1
        // with a real-world map's credits under it, less Done): too little
        // of the fifth would show, so the part is cut after four whole,
        // the first at the top.
        let cut = ToolColumn.buildingScrollHeight(maxHeight: 196 + ToolColumn.tileGap + ToolColumn.tileHeight(buttons: 1), tools: tools, toggle: false)
        XCTAssertGreaterThanOrEqual(cut, ToolColumn.tileHeight(buttons: 4) - ToolColumn.tilePadding)
        XCTAssertLessThan(cut, ToolColumn.tileHeight(buttons: 5) - ToolColumn.tilePadding - ToolColumn.compactButtonHeight / 2)
    }
}
