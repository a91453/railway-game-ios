import GameCore
@testable import GamePresentation
import XCTest

/// Decision 336, later (NEXT_PRIORITIES §22.2 rank 26): the sights from
/// the status bar, what Advanced holds, and the hint about holding a
/// line's track.
@MainActor
final class LessObviousEntriesTests: XCTestCase {
    func testTheSightsButtonIsForGamesWithSights() {
        let sights = GameSession(world: GameWorld.newGame(eventSeed: 9), language: .english)
        XCTAssertTrue(sights.world.hasTourism, "a new game has its sights")
        XCTAssertTrue(sights.showsSightsButton)
        var world = GameWorld.newGame(eventSeed: 9)
        world.setTourism(nil)
        XCTAssertFalse(GameSession(world: world, language: .english).showsSightsButton)
        sights.startTutorial()
        XCTAssertFalse(sights.showsSightsButton, "not in the tutorial")
    }

    func testAdvancedSaysWhatItHolds() {
        XCTAssertEqual(
            AdvancedDetails.contentsText(in: .traditionalChinese),
            "時段、各段股道與目標班距。"
        )
        XCTAssertNotEqual(AdvancedDetails.contentsText(in: .english), AdvancedDetails.contentsText(in: .traditionalChinese))
    }

    func testTheTrackHintShowsOnceOnALinesTrack() {
        let line = LineID(rawValue: 1)
        XCTAssertTrue(TrackHoldHint.shows(lines: [line], seen: false, tutorialRuns: false))
        XCTAssertFalse(TrackHoldHint.shows(lines: [line], seen: true, tutorialRuns: false), "once")
        XCTAssertFalse(TrackHoldHint.shows(lines: [], seen: false, tutorialRuns: false), "a track no line runs over opens nothing")
        XCTAssertFalse(TrackHoldHint.shows(lines: [line], seen: false, tutorialRuns: true))
        XCTAssertTrue(TrackHoldHint.text(in: .traditionalChinese).contains("長按"))
    }
}
