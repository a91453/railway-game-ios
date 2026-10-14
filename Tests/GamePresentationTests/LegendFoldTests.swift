@testable import GamePresentation
import XCTest

/// TestFlight 59.1: the legend folds on a short screen until the player
/// chooses, and then as they left it.
final class LegendFoldTests: XCTestCase {
    func testTheLegendFoldsOnAShortScreenUntilThePlayerChooses() {
        XCTAssertTrue(LegendFold.isFolded(stored: 0, compactHeight: true))
        XCTAssertFalse(LegendFold.isFolded(stored: 0, compactHeight: false))
        for compact in [true, false] {
            XCTAssertTrue(LegendFold.isFolded(stored: LegendFold.stored(folded: true), compactHeight: compact))
            XCTAssertFalse(LegendFold.isFolded(stored: LegendFold.stored(folded: false), compactHeight: compact))
        }
        XCTAssertNotEqual(LegendFold.stored(folded: true), 0)
        XCTAssertNotEqual(LegendFold.stored(folded: false), 0)
    }

    func testBesideAWideCardTheLegendFoldsUntilOpenedThere() {
        for stored in [0, LegendFold.stored(folded: true), LegendFold.stored(folded: false)] {
            for compact in [true, false] {
                XCTAssertTrue(LegendFold.isFolded(stored: stored, compactHeight: compact, besideCard: true))
                XCTAssertFalse(LegendFold.isFolded(stored: stored, compactHeight: compact, besideCard: true, openedBesideCard: true))
            }
        }
        // Away from the card, the stored choice again.
        XCTAssertFalse(LegendFold.isFolded(stored: LegendFold.stored(folded: false), compactHeight: true, besideCard: false, openedBesideCard: false))
    }
}
