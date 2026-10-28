@testable import GamePresentation
import XCTest

/// Decision 469: the row under the status pill gives way on a narrow screen.
final class MapTopRowTests: XCTestCase {
    /// The room the row has: the screen less its two edge gaps, and less
    /// the details card and its gap where the card is open.
    private func room(screen: Double, card: Double = 0) -> Double {
        screen - 2 * HUDMargins.edge - (card > 0 ? card + HUDMargins.edge : 0)
    }

    func testTheStripIsAsWideAsItsButtons() {
        // Five layers and More, 46 each; seven pieces 2 apart (the line
        // before More among them), the line 1 and 2 either side, the glass
        // 3 each side.
        XCTAssertEqual(MapTopRow.stripWidth, 6 * 46 + 6 * 2 + 5 + 6)
        XCTAssertEqual(MapTopRow.stripWidth, 299)
        XCTAssertEqual(MapTopRow.layersButtonWidth, 52)
    }

    func testAnIPadKeepsEverything() {
        // An 11-inch iPad upright with the card open (334 points) in a free
        // game: the strip and the next step, as before.
        let width = room(screen: 834, card: SidePanelWidth.card(screenWidth: 834, compactHeight: false))
        XCTAssertEqual(width, 470)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 0, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .strip, showsNextStep: true, nightSkip: .full))
        // With the card closed, at night too.
        let night = MapTopRow.arrange(width: room(screen: 834), showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(night, .init(layers: .strip, showsNextStep: true, nightSkip: .full))
        // At night beside the card the row was 573 points in 470 and ran
        // under the card; there the strip folds on an iPad too.
        let crowded = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(crowded.layers, .button)
    }

    func testALargePhoneUprightKeepsTheStripWithTheCardClosed() {
        // An iPhone 17 Pro, 402 points: the strip and the next step's flag.
        let row = MapTopRow.arrange(width: room(screen: 402), showsLayers: true, nightSkipWidth: 0, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .strip, showsNextStep: true, nightSkip: .full))
    }

    func testTheStripFoldsBesideTheCardOnAPhoneUpright() {
        // The card takes 40 % of a 402-point phone: 211 points are left,
        // where the 299-point strip ran under the card.
        let card = SidePanelWidth.card(screenWidth: 402, compactHeight: false)
        let width = room(screen: 402, card: card)
        XCTAssertLessThan(width, MapTopRow.stripWidth)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 0, nextStep: true, follows: false)
        XCTAssertEqual(row.layers, .button)
        XCTAssertTrue(row.showsNextStep)
        XCTAssertLessThanOrEqual(
            MapTopRow.width(of: row, showsLayers: true, nightSkipWidth: 0, follows: false), width
        )
    }

    func testTheNightSkipKeepsItsNameBeforeTheStripOnASmallPhone() {
        // An iPhone SE upright, 375 points, at night: the skip's name and
        // time (190) and the strip (299) do not both fit in 355.
        let row = MapTopRow.arrange(width: room(screen: 375), showsLayers: true, nightSkipWidth: 190, nextStep: false, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .full))
    }

    func testTheNextStepGoesBeforeTheNightSkipLosesItsName() {
        // 190 + 52 + 64 and two gaps is 326; 300 points are short of it.
        let row = MapTopRow.arrange(width: 300, showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .full))
    }

    func testTheNightSkipKeepsItsIconWhereNothingElseFits() {
        // Beside the card on a small phone upright: 375 less the card's
        // 150 leaves 195, short of the skip's 190, a gap and the button.
        let card = SidePanelWidth.card(screenWidth: 375, compactHeight: false)
        let width = room(screen: 375, card: card)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .icon))
        XCTAssertLessThanOrEqual(
            MapTopRow.width(of: row, showsLayers: true, nightSkipWidth: 190, follows: false), width
        )
    }

    func testTheStripFoldsBesideTheFollowBarOnAPhoneOnItsSide() {
        // An iPhone SE on its side, 667 points, with the card open (233):
        // the strip (299), a gap and the follow bar's least (110) are 419,
        // and 404 are left.
        let card = SidePanelWidth.card(screenWidth: 667, compactHeight: true)
        let width = room(screen: 667, card: card)
        XCTAssertEqual(width, 404)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 0, nextStep: false, follows: true)
        XCTAssertEqual(row.layers, .button)
        // With the card closed the strip stays beside the bar.
        let open = MapTopRow.arrange(width: room(screen: 667), showsLayers: true, nightSkipWidth: 0, nextStep: false, follows: true)
        XCTAssertEqual(open.layers, .strip)
    }

    func testWhileBuildingOnlyTheFollowBarCounts() {
        // The strip, the skip and the next step are not in the row while
        // building (decision 224): nothing of theirs is counted.
        let row = MapTopRow.arrange(width: 120, showsLayers: false, nightSkipWidth: 190, nextStep: true, follows: true)
        XCTAssertEqual(MapTopRow.width(of: row, showsLayers: false, nightSkipWidth: 190, follows: true), MapTopRow.followBarLeast)
    }

    func testTheNarrowestRowIsTheLastResort() {
        // Narrower than anything: the narrowest arrangement, not nothing.
        let row = MapTopRow.arrange(width: 40, showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: true)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .icon))
    }
}
