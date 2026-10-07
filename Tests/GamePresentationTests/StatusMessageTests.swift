import GameCore
import GamePresentation
import XCTest

/// The status banner's message: a success clears itself after a while, so
/// a panel's banner does not stay over the row just edited; a problem stays
/// until dismissed; the banner's timer never clears a newer message.
final class StatusMessageTests: XCTestCase {
    func testASuccessClearsItselfAndAProblemStays() {
        XCTAssertEqual(StatusMessage(kind: .success, text: "Built").autoDismissDelay, .seconds(4))
        XCTAssertNil(StatusMessage(kind: .failure, text: "Too steep").autoDismissDelay)
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
        session.dismissMessage(StatusMessage(kind: .failure, text: "an older one"))
        XCTAssertEqual(session.message, built, "a newer message stays")
        session.dismissMessage(built)
        XCTAssertNil(session.message)
    }
}
