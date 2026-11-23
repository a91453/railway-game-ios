import GameCore
@testable import GamePresentation
import XCTest

/// The AI testers' first round (2026-11-23): what is worked out off
/// Apple's platforms of the fixes it asked for.
@MainActor
final class AITesterRoundOneTests: XCTestCase {
    /// Lesson 1's map rings and numbers both towns while the player looks
    /// for them and lays the track, and no longer once the track is built.
    func testLessonOneRingsBothTownsUntilTheTrackIsBuilt() throws {
        let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .english)
        session.startTutorial()
        XCTAssertEqual(session.tutorialPlaceMarks, [], "Tap Build marks nothing")
        session.selectTool(.network)
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "map.move")
        let towns = Array(Lesson.towns(in: session.world.bounds).prefix(2))
        let marks = session.tutorialPlaceMarks
        XCTAssertEqual(marks.map(\.number), [1, 2])
        XCTAssertEqual(marks.map(\.location), towns)
        XCTAssertEqual(marks.map(\.radius), [Land.catchmentRadius, Land.catchmentRadius])

        session.mapDidMove()
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.step.id, "track.draw")
        XCTAssertEqual(session.tutorialPlaceMarks, marks, "the track step keeps the same marks")

        session.tapNetwork(at: towns[0], reach: 512)
        session.tapNetwork(at: towns[1], reach: 512)
        session.buildNetworkTrack()
        session.showNextTutorialStep()
        XCTAssertNotEqual(session.tutorial?.step.id, "track.draw")
        XCTAssertEqual(session.tutorialPlaceMarks, [])
    }

    /// Outside a lesson nothing is marked: the first tutorial lays its
    /// track across one town and has no places to link.
    func testNothingIsMarkedOutsideALesson() {
        let session = GameSession(world: .newGame(), language: .english)
        session.startTutorial()
        session.selectTool(.network)
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorialPlaceMarks, [])
    }
}
