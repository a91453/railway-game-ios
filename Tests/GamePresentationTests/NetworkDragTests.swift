import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 102: drawing track with a finger. A drag that
/// starts on the picked start, or on track, draws the next stretch to the
/// finger and leaves it previewed; one that starts anywhere else moves the
/// map; nothing is built or spent until the player builds the preview.
@MainActor
final class NetworkDragTests: XCTestCase {
    private static let reach: Int64 = 512
    private static let a = PlanPoint(x: 2_048, y: 2_048)
    private static let b = PlanPoint(x: 6_144, y: 2_048)
    private static let c = PlanPoint(x: 10_240, y: 4_096)

    private func makeSession() throws -> GameSession {
        let session = GameSession(world: try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .paused))
        session.selectTool(.network)
        return session
    }

    func testADragOnEmptyGroundMovesTheMap() throws {
        let session = try makeSession()
        XCTAssertFalse(session.networkDragDraws(from: Self.a, reach: Self.reach), "nothing to draw from")
        session.selectTool(.select)
        session.tapNetwork(at: Self.a, reach: Self.reach)
        XCTAssertFalse(session.networkDragDraws(from: Self.a, reach: Self.reach), "only the network tool draws")
    }

    func testADragFromTheStartDrawsAPreviewAndBuildsNothing() throws {
        let session = try makeSession()
        session.tapNetwork(at: Self.a, reach: Self.reach)
        let near = PlanPoint(x: Self.a.x + 300, y: Self.a.y)
        XCTAssertTrue(session.networkDragDraws(from: near, reach: Self.reach))
        XCTAssertFalse(session.networkDragDraws(from: Self.b, reach: Self.reach), "away from the start, with no track")

        let start = session.world
        session.dragNetwork(from: near, to: PlanPoint(x: 4_096, y: 2_048), reach: Self.reach)
        XCTAssertEqual(session.networkStart, .point(Self.a), "the start stays")
        XCTAssertEqual(session.networkEnd, .point(PlanPoint(x: 4_096, y: 2_048)))
        session.dragNetwork(from: near, to: Self.b, reach: Self.reach)
        session.endNetworkDrag(from: near, to: Self.b, reach: Self.reach)
        XCTAssertEqual(session.networkEnd, .point(Self.b), "the end follows the finger")
        // Decision 107: where the map puts its flags and build button.
        XCTAssertEqual(session.networkStartPlanPoint, Self.a)
        XCTAssertEqual(session.networkEndPlanPoint, Self.b)
        XCTAssertEqual(session.world, start, "nothing built or spent")
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNotNil(preview.cost, "the preview says what it costs")

        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1)
        XCTAssertLessThan(session.world.economy.balance, start.economy.balance)
    }

    func testADragFromTrackStartsThereAndContinuesIt() throws {
        let session = try makeSession()
        session.tapNetwork(at: Self.a, reach: Self.reach)
        session.tapNetwork(at: Self.b, reach: Self.reach)
        session.buildNetworkTrack()
        let built = try XCTUnwrap(session.world.network.edges.first)
        session.clearNetworkDraft()

        // From the far node of the built track.
        XCTAssertTrue(session.networkDragDraws(from: Self.b, reach: Self.reach))
        session.dragNetwork(from: Self.b, to: Self.c, reach: Self.reach)
        session.endNetworkDrag(from: Self.b, to: Self.c, reach: Self.reach)
        XCTAssertEqual(session.networkStart, .node(built.to))
        XCTAssertEqual(session.networkStartPlanPoint, Self.b, "a node stands where it was built")
        XCTAssertEqual(session.networkEnd, .point(Self.c))
        XCTAssertNotNil(session.networkPreview)

        // From the middle of the built track: a turnout there.
        session.clearNetworkDraft()
        let middle = PlanPoint(x: 4_096, y: 2_048)
        XCTAssertTrue(session.networkDragDraws(from: middle, reach: Self.reach))
        session.dragNetwork(from: middle, to: PlanPoint(x: 6_144, y: 5_120), reach: Self.reach)
        guard case .track(let point)? = session.networkStart else {
            return XCTFail("a turnout on the track: \(String(describing: session.networkStart))")
        }
        XCTAssertEqual(point.edge, built.id)
    }

    func testACancelledDragPutsTheEndBack() throws {
        let session = try makeSession()
        session.tapNetwork(at: Self.a, reach: Self.reach)
        session.tapNetwork(at: Self.b, reach: Self.reach)
        session.dragNetwork(from: Self.a, to: Self.c, reach: Self.reach)
        XCTAssertEqual(session.networkEnd, .point(Self.c))
        session.cancelNetworkDrag()
        XCTAssertEqual(session.networkEnd, .point(Self.b))
        XCTAssertEqual(session.networkStart, .point(Self.a))
    }

    /// A drag that began on other track picked a new start; cancelled, it
    /// keeps that start, as a tap there would, but not the end picked for
    /// the old one: the player never chose that stretch.
    func testACancelledDragFromOtherTrackLeavesNoStretchUnpicked() throws {
        let session = try makeSession()
        session.tapNetwork(at: Self.a, reach: Self.reach)
        session.tapNetwork(at: Self.b, reach: Self.reach)
        session.buildNetworkTrack()
        session.clearNetworkDraft()
        let d = PlanPoint(x: 2_048, y: 6_144), e = PlanPoint(x: 12_288, y: 6_144)
        session.tapNetwork(at: d, reach: Self.reach)
        session.tapNetwork(at: e, reach: Self.reach)
        let middle = PlanPoint(x: 4_096, y: 2_048)
        session.dragNetwork(from: middle, to: Self.c, reach: Self.reach)
        session.cancelNetworkDrag()
        guard case .track? = session.networkStart else { return XCTFail("the start the drag picked stays") }
        XCTAssertNil(session.networkEnd, "not D's end E from the track")
        XCTAssertNil(session.networkPreview)
    }

    func testDraggingBackOntoTheStartLeavesNoEnd() throws {
        let session = try makeSession()
        session.tapNetwork(at: Self.a, reach: Self.reach)
        session.dragNetwork(from: Self.a, to: Self.b, reach: Self.reach)
        session.endNetworkDrag(from: Self.a, to: PlanPoint(x: Self.a.x + 10, y: Self.a.y), reach: Self.reach)
        XCTAssertNotNil(session.networkStart)
        XCTAssertNil(session.networkEnd)
        XCTAssertNil(session.networkEndPlanPoint)
        XCTAssertNil(session.networkPreview)
    }
}
