import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 184: a refusal and a new worry in the news log
/// have their own sounds (and, in the app, taps of the phone).
@MainActor
final class FeedbackCueTests: XCTestCase {
    func testARefusalSoundsSo() throws {
        let session = GameSession(world: try makeWorld(), language: .english)
        var played: [SoundCue] = []
        session.playSound = { played.append($0) }
        session.undo()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(played, [.refused])
        session.togglePause()
        XCTAssertEqual(played, [.refused], "no message, no sound")
    }

    func testANewWorryRingsTheWarningButARestoredLogDoesNot() throws {
        let world = try NewsSessionTests.world(day: 3, balance: Money(40_000))
        let session = GameSession(world: world, language: .english)
        var played: [SoundCue] = []
        session.playSound = { played.append($0) }
        let tick = try XCTUnwrap(session.beginLoopTick())
        let step = try GameSession.advanced(tick.world, by: 1_440, listening: false)
        XCTAssertTrue(session.finish(tick, with: .success(step)))
        XCTAssertTrue(session.news.items.contains { $0.category == .debt })
        XCTAssertEqual(played.filter { $0 == .warning }.count, 1)

        let other = GameSession(world: world, language: .english)
        var restored: [SoundCue] = []
        other.playSound = { restored.append($0) }
        other.restoreNews(session.news)
        XCTAssertEqual(restored, [])
    }
}
