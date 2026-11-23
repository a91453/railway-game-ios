import GameCore
import GamePresentation
import XCTest

/// The details card keeps its layout while its head takes a line more or
/// less (TestFlight 56.1): a switch put the options back at their top and
/// closed an open menu. Decision 588: where the head and foot leave the
/// options too little room, the foot (the action button, and a train's
/// cars and platform while it is placed) stays in view and the head
/// scrolls away.
final class DetailsCardLayoutTests: XCTestCase {
    private func layout(_ head: Double, _ foot: Double, _ maxHeight: Double, _ current: DetailsCardLayout?) -> DetailsCardLayout {
        DetailsCardLayout.layout(head: head, foot: foot, maxHeight: maxHeight, current: current)
    }

    func testAFirstLayoutPinsBothEndsOnlyWithThreeRowsOfRoom() {
        XCTAssertEqual(layout(100, 56, 288, nil), .pinned)
        XCTAssertEqual(layout(101, 56, 288, nil), .footPinned)
    }

    func testAFirstLayoutPinsTheFootWithARowOfRoom() {
        XCTAssertEqual(layout(400, 244, 288, nil), .footPinned)
        XCTAssertEqual(layout(400, 245, 288, nil), .whole)
    }

    /// A train's summary at the head, one line (about 20 pt) longer while
    /// it stops than while it runs, around each of the card's limits.
    func testATrainStoppingAndStartingKeepsTheLayout() {
        let maxHeight: Double = 300
        for foot in [56.0, 170] {
            for start in stride(from: 20.0, through: 280, by: 5) {
                var current = layout(start, foot, maxHeight, nil)
                let first = current
                for head in [start + 20, start, start + 20, start, start + 20] {
                    current = layout(head, foot, maxHeight, current)
                    XCTAssertEqual(current, first, "head \(start) to \(head) pt over a \(foot) pt foot in a \(maxHeight) pt card")
                }
            }
        }
    }

    /// A platform's warning under the platforms makes the foot a line
    /// taller, and goes again.
    func testAFootALineTallerKeepsItPinned() {
        let maxHeight: Double = 240
        for start in stride(from: 150.0, through: 220, by: 2) {
            var current = layout(300, start, maxHeight, nil)
            let first = current
            for foot in [start + 16, start, start + 16, start] {
                current = layout(300, foot, maxHeight, current)
                XCTAssertEqual(current, first, "foot \(start) to \(foot) pt")
            }
        }
    }

    func testAPinnedHeadScrollsAwayOnlyWhenTheOptionsWouldKeepLessThanTwoRows() {
        XCTAssertEqual(layout(156, 56, 300, .pinned), .pinned)
        XCTAssertEqual(layout(157, 56, 300, .pinned), .footPinned)
    }

    func testAScrollingHeadIsPinnedAgainOnceTheOptionsHaveThreeRows() {
        XCTAssertEqual(layout(113, 56, 300, .footPinned), .footPinned)
        XCTAssertEqual(layout(112, 56, 300, .footPinned), .pinned)
    }

    func testTheWholeCardScrollsOnlyWhenTheFootLeavesLessThanAFewLines() {
        XCTAssertEqual(layout(100, 276, 300, .footPinned), .footPinned)
        XCTAssertEqual(layout(100, 277, 300, .footPinned), .whole)
        XCTAssertEqual(layout(100, 257, 300, .whole), .whole)
        XCTAssertEqual(layout(100, 256, 300, .whole), .footPinned)
    }

    /// The card's greatest height on each device held on its side: the
    /// screen's height less the status pill, the room under the card and
    /// the margins, 135 pt in decision 584's screenshots (an iPhone Pro,
    /// 402 pt high on its side: a card of 267); an iPad's card, much
    /// taller.
    private static let cards: [(String, Double)] = [
        ("iPhone SE / mini", 375 - 135), ("iPhone Pro", 402 - 135), ("iPhone Pro Max", 440 - 135), ("iPad", 600),
    ]

    /// The foot of a train being placed at a station of two platforms:
    /// the cars over their price (about 36 pt), the platforms (two lines,
    /// about 44), a warning under them (a line, 4 + 16), the Place button
    /// (44, one line in either language: its words shrink a little rather
    /// than wrap), with the foot's gaps and margins (12 + 8 + 12 + 14).
    /// The heads: a station's nameboard (about 110 pt, Chinese) and a
    /// train's next step (about 190, English, decision 584's run
    /// 41906093384).
    func testPlacingATrainKeepsItsChoicesAndThePlaceButtonInViewOnEveryDevice() {
        let feet: [(String, Double)] = [("no warning", 36 + 44 + 44 + 46), ("a warning", 36 + 44 + 20 + 44 + 46)]
        for (device, maxHeight) in Self.cards {
            for (warning, foot) in feet {
                for head in [110.0, 190] {
                    let shown = layout(head, foot, maxHeight, nil)
                    XCTAssertNotEqual(shown, .whole, "\(device), \(warning), head \(head): the foot must stay in view")
                    // Some options still show above it.
                    let room = maxHeight - foot - (shown == .pinned ? head : 0)
                    XCTAssertGreaterThanOrEqual(room, DetailsCardLayout.leastKept, "\(device), \(warning)")
                }
            }
        }
    }

    /// The ferry or cable car mode in English: its instruction at the head,
    /// five lines (about 125 pt), over a one-line button. On a phone the
    /// instruction scrolls with the options rather than leaving them a
    /// band some 70 pt high under it.
    func testALongInstructionOnAPhoneScrollsWithTheOptions() {
        XCTAssertEqual(layout(125, 56, 402 - 135, nil), .footPinned)
        XCTAssertEqual(layout(125, 56, 600, nil), .pinned)
    }

    func testOnlyATrainOffTheTrackUnderTheTrainToolPutsItsChoicesInTheFoot() {
        XCTAssertTrue(DetailsCardLayout.placesTrain(tool: .train, trainIsSelected: true, trainIsOnTrack: false))
        XCTAssertFalse(DetailsCardLayout.placesTrain(tool: .train, trainIsSelected: true, trainIsOnTrack: true))
        XCTAssertFalse(DetailsCardLayout.placesTrain(tool: .train, trainIsSelected: false, trainIsOnTrack: false))
        XCTAssertFalse(DetailsCardLayout.placesTrain(tool: .select, trainIsSelected: true, trainIsOnTrack: false))
    }

    /// DEPOT-SIDINGS-HIT (full lane `fcaa3f0`): #2614 pinned the network
    /// tool's mode row above the card. Counted against the options' room,
    /// a phone on its side lost the pinned head, and the inspector,
    /// scrolling above the options, pushed the Depot mode's sidings out of
    /// reach. The row was the options' first row: a card that pinned both
    /// ends with the row among the options pins them with the row on top.
    func testThePinnedModeRowCountsAsTheOptionsRoom() {
        for top in [40.0, 50, 60] {
            XCTAssertEqual(DetailsCardLayout.layout(top: top, head: 100, foot: 56, maxHeight: 288, current: nil), .pinned, "a \(top) pt row")
            XCTAssertEqual(DetailsCardLayout.layout(top: top, head: 101, foot: 56, maxHeight: 288, current: nil), .footPinned, "a \(top) pt row")
        }
    }

    /// The options under the row keep at least a row of their own when
    /// both ends are pinned, however tall the row (a large text size), and
    /// the foot is pinned only with a row of room under the mode row.
    func testTheOptionsUnderTheModeRowKeepARow() {
        for top in stride(from: 0.0, through: 200, by: 10) {
            for head in stride(from: 0.0, through: 300, by: 10) {
                for current in [nil, DetailsCardLayout.pinned, .footPinned, .whole] {
                    let maxHeight = 320.0, foot = 56.0
                    switch DetailsCardLayout.layout(top: top, head: head, foot: foot, maxHeight: maxHeight, current: current) {
                    case .pinned:
                        XCTAssertGreaterThanOrEqual(maxHeight - top - head - foot, DetailsCardLayout.leastKept, "row \(top), head \(head)")
                    case .footPinned:
                        XCTAssertGreaterThanOrEqual(maxHeight - top - foot, DetailsCardLayout.leastFootKept, "row \(top), head \(head)")
                    case .whole:
                        break
                    }
                }
            }
        }
    }

    /// With the row on top, a head a line longer or shorter still keeps
    /// the layout (TestFlight 56.1).
    func testAHeadALineLongerKeepsTheLayoutUnderTheModeRow() {
        for top in [44.0, 60, 100] {
            for start in stride(from: 20.0, through: 280, by: 5) {
                var current = DetailsCardLayout.layout(top: top, head: start, foot: 56, maxHeight: 320, current: nil)
                let first = current
                for head in [start + 20, start, start + 20, start] {
                    current = DetailsCardLayout.layout(top: top, head: head, foot: 56, maxHeight: 320, current: current)
                    XCTAssertEqual(current, first, "row \(top), head \(start) to \(head)")
                }
            }
        }
    }

    /// The card is as tall with the row pinned on top as it was with the
    /// row among the options: they take the rest of their steady height.
    func testTheOptionsTakeTheRestOfTheirHeightUnderTheRow() {
        XCTAssertEqual(DetailsCardLayout.optionsMinimum(under: 0), DetailsCardLayout.optionsHeight)
        XCTAssertEqual(DetailsCardLayout.optionsMinimum(under: 50) + 50, DetailsCardLayout.optionsHeight)
        XCTAssertEqual(DetailsCardLayout.optionsMinimum(under: 200), 0)
    }
}
