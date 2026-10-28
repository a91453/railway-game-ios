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

    // An iPhone is only held on its side (decision 106): an iPhone 17 Pro
    // is 750 points wide inside its safe area, an iPhone SE 667.

    func testALargePhoneKeepsTheStripBesideTheCard() {
        // The card takes 35 % (263): 457 points are left, room for the
        // strip and the next step's flag (373).
        let card = SidePanelWidth.card(screenWidth: 750, compactHeight: true)
        let width = room(screen: 750, card: card)
        XCTAssertEqual(width, 457)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 0, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .strip, showsNextStep: true, nightSkip: .full))
    }

    func testTheStripFoldsAtNightBesideTheCard() {
        // At night the skip (190), the strip and the next step are 573
        // points, and ran under the card; folded they are 326.
        let card = SidePanelWidth.card(screenWidth: 750, compactHeight: true)
        let width = room(screen: 750, card: card)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: true, nightSkip: .full))
        XCTAssertLessThanOrEqual(
            MapTopRow.width(of: row, showsLayers: true, nightSkipWidth: 190, follows: false), width
        )
        // With the card closed the strip stays.
        let open = MapTopRow.arrange(width: room(screen: 750), showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(open.layers, .strip)
    }

    func testTheNightSkipKeepsItsNameBeforeTheStripOnASmallPhone() {
        // An iPhone SE with the card open (233): 404 points, short of the
        // skip and the strip (499).
        let card = SidePanelWidth.card(screenWidth: 667, compactHeight: true)
        let width = room(screen: 667, card: card)
        XCTAssertEqual(width, 404)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 190, nextStep: false, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .full))
    }

    func testTheNextStepGoesBeforeTheNightSkipLosesItsName() {
        // 190 + 52 + 64 and two gaps is 326; 300 points are short of it.
        let row = MapTopRow.arrange(width: 300, showsLayers: true, nightSkipWidth: 190, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .full))
    }

    func testTheNightSkipKeepsItsIconWhereNothingElseFits() {
        // At the largest text the skip is about 360 points: beside the
        // card on an iPhone SE (404) not even it and the button fit (422).
        let card = SidePanelWidth.card(screenWidth: 667, compactHeight: true)
        let width = room(screen: 667, card: card)
        let row = MapTopRow.arrange(width: width, showsLayers: true, nightSkipWidth: 360, nextStep: true, follows: false)
        XCTAssertEqual(row, .init(layers: .button, showsNextStep: false, nightSkip: .icon))
        XCTAssertLessThanOrEqual(
            MapTopRow.width(of: row, showsLayers: true, nightSkipWidth: 360, follows: false), width
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
