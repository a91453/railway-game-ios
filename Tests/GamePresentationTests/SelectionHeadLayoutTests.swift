import GamePresentation
import XCTest

/// The selection card's head on a narrow card: a player's report from an
/// iPhone held sideways, where "Station · Zuoying · 8 platforms, 1664…" and
/// "Station…" were both cut short.
final class SelectionHeadLayoutTests: XCTestCase {
    func testTheButtonsGoUnderTheWordsOnlyOnANarrowCard() {
        // A phone's side panel held sideways.
        XCTAssertTrue(SelectionHeadLayout.buttonsBelow(width: 214))
        XCTAssertTrue(SelectionHeadLayout.buttonsBelow(width: SelectionHeadLayout.leastBeside - 1))
        // An iPad's panel, and a phone's card across the bottom.
        XCTAssertFalse(SelectionHeadLayout.buttonsBelow(width: SelectionHeadLayout.leastBeside))
        XCTAssertFalse(SelectionHeadLayout.buttonsBelow(width: 380))
        // Not measured yet: beside, as before.
        XCTAssertFalse(SelectionHeadLayout.buttonsBelow(width: 0))
    }
}
