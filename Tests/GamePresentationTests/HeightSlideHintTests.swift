import GameCore
@testable import GamePresentation
import XCTest

/// The one-time line about the construction HUD's height cell
/// (``HeightSlideHint``): when it shows and when it is done with.
@MainActor
final class HeightSlideHintTests: XCTestCase {
    private func card(label: String = "End 6 m above the ground", up: Int = 10, down: Int = 10, fixes: [NetworkHeightFix] = []) -> NetworkHeightCard {
        NetworkHeightCard(
            adjusts: .end, label: label, canRaise: up > 0, canLower: down > 0, fixes: fixes, note: nil,
            aboveGround: 0, stepsUp: up, stepsDown: down
        )
    }

    func testItShowsBesideAHeightCellThatSlides() {
        XCTAssertTrue(HeightSlideHint.shows(seen: false, card: card(), tutorialRuns: false))
        XCTAssertTrue(HeightSlideHint.shows(seen: false, card: card(up: 0), tutorialRuns: false), "one way is enough")
    }

    func testItDoesNotShowWithoutACellToSlide() {
        XCTAssertFalse(HeightSlideHint.shows(seen: false, card: nil, tutorialRuns: false), "no height card: a finger still draws, or a traced line")
        XCTAssertFalse(HeightSlideHint.shows(seen: false, card: card(label: ""), tutorialRuns: false), "both ends on track: the plain figure")
        XCTAssertFalse(HeightSlideHint.shows(seen: false, card: card(up: 0, down: 0), tutorialRuns: false), "nowhere to go")
    }

    func testItWaitsWhileTheBuildCardOffersABridge() {
        let bridge = NetworkHeightFix(ends: .end, change: 4, raises: NetworkRaises(end: 4), structure: .elevated, kind: .bridge, cost: Money(3_361))
        XCTAssertFalse(HeightSlideHint.shows(seen: false, card: card(fixes: [bridge]), tutorialRuns: false), "the card says how to get through")
        XCTAssertTrue(HeightSlideHint.shows(seen: false, card: card(), tutorialRuns: false), "and shows once the stretch gets through")
    }

    func testItNeverComesBackOnceDoneWith() {
        XCTAssertFalse(HeightSlideHint.shows(seen: true, card: card(), tutorialRuns: false))
    }

    func testItKeepsOutOfTheTutorialsWay() {
        XCTAssertFalse(HeightSlideHint.shows(seen: false, card: card(), tutorialRuns: true))
        XCTAssertTrue(HeightSlideHint.shows(seen: false, card: card(), tutorialRuns: false), "and waits for the first stretch after it")
    }

    func testOnlyAChangedHeightIsUsingTheCell() {
        XCTAssertFalse(HeightSlideHint.isUse(raisingBy: 0), "held and let go where it began")
        XCTAssertTrue(HeightSlideHint.isUse(raisingBy: 1))
        XCTAssertTrue(HeightSlideHint.isUse(raisingBy: -3))
        // What a slide applies when the finger lets go (decision 646).
        let card = card()
        XCTAssertFalse(HeightSlideHint.isUse(raisingBy: TrackHeightDrag.stepsApplied(endingAt: nil, card: card)))
        XCTAssertFalse(HeightSlideHint.isUse(raisingBy: TrackHeightDrag.stepsApplied(endingAt: -13, card: card)), "under a metre")
        XCTAssertTrue(HeightSlideHint.isUse(raisingBy: TrackHeightDrag.stepsApplied(endingAt: -29, card: card)))
    }

    func testItsWordsAndItsKey() {
        XCTAssertNotEqual(HeightSlideHint.text(in: .english), HeightSlideHint.text(in: .traditionalChinese))
        XCTAssertNotEqual(HeightSlideHint.dismissLabel(in: .english), HeightSlideHint.dismissLabel(in: .traditionalChinese))
        XCTAssertEqual(HeightSlideHint.seenKey, "hints.trackHeightSlide.seen", "the device's key: changing it shows the line again to everyone")
    }
}
