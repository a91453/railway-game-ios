import Foundation
import GameCore
import GamePresentation
import XCTest

/// The status banner's message: a success clears itself after a while, so
/// a panel's banner does not stay over the row just edited; a problem
/// stays longer the longer it is (decision 106); the banner's timer never
/// clears a newer message.
final class StatusMessageTests: XCTestCase {
    func testASuccessClearsItselfAndAProblemStaysLongerTheLongerItIs() {
        XCTAssertEqual(StatusMessage(kind: .success, text: "Built").autoDismissDelay, .seconds(4))
        XCTAssertEqual(StatusMessage(kind: .failure, text: "Too steep").autoDismissDelay, .seconds(6), "at least 6 s")
        let thirty = String(repeating: "x", count: 30)
        XCTAssertEqual(StatusMessage(kind: .failure, text: thirty).autoDismissDelay, .seconds(7))
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(StatusMessage(kind: .failure, text: long).autoDismissDelay, .seconds(10), "at most 10 s")
    }

    @MainActor
    func testTheTimerClearsOnlyTheMessageItWasStartedFor() throws {
        let session = GameSession(world: try makeWorld(width: 8_192, height: 4_096, balance: 1_000, speed: .paused))
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 1_024), reach: 512)
        session.tapNetwork(at: PlanPoint(x: 6_144, y: 1_024), reach: 512)
        session.buildNetworkTrack()
        let built = try XCTUnwrap(session.message)
        XCTAssertEqual(built.kind, .success)
        let serial = session.messageSerial
        session.dismissMessage(posted: serial - 1)
        XCTAssertEqual(session.message, built, "a newer message stays")
        session.dismissMessage(posted: serial)
        XCTAssertNil(session.message)
    }

    /// The same text again is a newer message: saving twice within 4 s,
    /// the first save's timer leaves the second "Saved the game.", which
    /// shows for its own 4 s.
    @MainActor
    func testTheTimerLeavesTheSameTextPostedAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StatusMessageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session)
        launcher.saveCurrentGame()
        let first = try XCTUnwrap(session.message)
        let firstSerial = session.messageSerial
        launcher.saveCurrentGame()
        XCTAssertEqual(session.message, first, "the same text")
        XCTAssertNotEqual(session.messageSerial, firstSerial, "a newer message")
        session.dismissMessage(posted: firstSerial)
        XCTAssertNotNil(session.message, "the first message's timer leaves the second")
        session.dismissMessage(posted: session.messageSerial)
        XCTAssertNil(session.message)
    }
}
