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
}
