import GamePresentation
import XCTest

/// The details card keeps its layout while its head takes a line more or
/// less (TestFlight 56.1): a switch put the options back at their top and
/// closed an open menu.
final class DetailsCardLayoutTests: XCTestCase {
    func testAFirstLayoutPinsOnlyWithTwoRowsOfRoom() {
        XCTAssertTrue(DetailsCardLayout.pinsEnds(ends: 200, maxHeight: 288, pinned: nil))
        XCTAssertFalse(DetailsCardLayout.pinsEnds(ends: 201, maxHeight: 288, pinned: nil))
    }

    /// A train's summary at the head, one line (about 20 pt) longer while
    /// it stops than while it runs, around the card's limit.
    func testATrainStoppingAndStartingKeepsTheLayout() {
        let maxHeight: Double = 300
        for start in stride(from: 150.0, through: 280, by: 5) {
            var pinned = DetailsCardLayout.pinsEnds(ends: start, maxHeight: maxHeight, pinned: nil)
            let first = pinned
            for ends in [start + 20, start, start + 20, start, start + 20] {
                pinned = DetailsCardLayout.pinsEnds(ends: ends, maxHeight: maxHeight, pinned: pinned)
                XCTAssertEqual(pinned, first, "head \(start) to \(ends) pt in a \(maxHeight) pt card")
            }
        }
    }

    func testThePinnedCardScrollsWholeOnlyWhenTheOptionsWouldKeepLessThanARow() {
        XCTAssertTrue(DetailsCardLayout.pinsEnds(ends: 256, maxHeight: 300, pinned: true))
        XCTAssertFalse(DetailsCardLayout.pinsEnds(ends: 257, maxHeight: 300, pinned: true))
    }

    func testTheWholeCardPinsAgainOnceTheOptionsHaveTwoRows() {
        XCTAssertFalse(DetailsCardLayout.pinsEnds(ends: 213, maxHeight: 300, pinned: false))
        XCTAssertTrue(DetailsCardLayout.pinsEnds(ends: 212, maxHeight: 300, pinned: false))
    }
}
