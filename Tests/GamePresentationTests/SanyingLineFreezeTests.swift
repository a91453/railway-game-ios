@testable import GameCore
@testable import GamePresentation
import XCTest

/// The author on 94, on an iPhone: "the game sticks after buying the
/// Sanying Line". Its 12 trains on 14 km of double track and the four that
/// stand overnight at stations between the ends wait for each other each
/// morning, and the search for trains in a deadlock behind the map's stuck
/// train bubbles asks a route of every waiting train: some 70–100 ms in
/// Linux release on the bought line, ten times the Blue Coast Line's, at
/// every tick at 6000×, on the main actor. The tick works the bubbles out
/// off the main actor with the world it made.
@MainActor
final class SanyingLineFreezeTests: XCTestCase {
    func testTheBoughtSanyingLinesStuckTrainsAreWorkedOutOffTheMainActor() async throws {
        let session = try RealLineAcquisitionTests.game(round: "sanying:LB", side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "sanying:LB" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        session.setSpeed(.fast)
        let before = session.situationAlertsWorkedOut
        var stuck = 0
        while session.world.clock.now.seconds < 7 * GameTime.secondsPerHour {
            _ = try await FiftyStationFreezeTests.tick(session)
            let bubbles = session.situationAlerts.filter { if case .trainStuck = $0.kind { true } else { false } }
            stuck = max(stuck, bubbles.count)
        }
        XCTAssertGreaterThan(stuck, 0, "the morning's trains waiting for each other still show")
        XCTAssertEqual(session.situationAlertsWorkedOut, before, "no deadlock search on the main actor at 6000x")
    }
}
