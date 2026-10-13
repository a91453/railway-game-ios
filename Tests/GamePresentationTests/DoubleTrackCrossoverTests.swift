import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 204, later: a double track drawn from the track already there
/// gets a crossover from its second track over to the stretch at that end,
/// in the same command, so trains on the second track reach it too.
@MainActor
final class DoubleTrackCrossoverTests: XCTestCase {
    /// A single track from x 1,024 to 5,120 along y 8,192, and the session
    /// drawing a double track on from its east end, the second track on the
    /// north.
    private func sessionOnTheTrack(balance: Money = Money(10_000_000)) throws -> (GameSession, west: TrackNodeID) {
        var world = try makeWorld(width: 40_960, height: 16_384, balance: balance, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 5_120, y: 8_192))
        try world.buildTrackEdge(from: west, to: east)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.networkDoubleSide = .left
        session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 16)
        return (session, west)
    }

    /// Whether a train on the second track's far end, heading back, can
    /// reach `node`.
    private func secondTrackReaches(_ node: TrackNodeID, from far: WorldCoordinate, in world: GameWorld) throws -> Bool {
        let end = try XCTUnwrap(world.network.nodes.first { $0.position == far })
        let edgeID = try XCTUnwrap(end.ends.first?.edge)
        let edge = try XCTUnwrap(world.network.edge(edgeID))
        let traversal = TrackTraversal(edge: edgeID, direction: edge.to == end.id ? .backward : .forward)
        return world.route(from: .onEdge(traversal, offset: 0), to: node) != nil
    }

    func testAStretchFromTheTrackGetsACrossoverAtThatEnd() throws {
        let (session, west) = try sessionOnTheTrack()
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        XCTAssertEqual(draft.preview.crossovers.count, 1)
        XCTAssertEqual(draft.preview.crossoverNote, "A crossover joins the second track to the track it meets.")
        let cost = try XCTUnwrap(draft.preview.cost)
        let balance = session.world.economy.balance
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.hasSuffix(" A crossover joins the second track to the track it meets.") ?? false, session.message?.text ?? "")
        let world = session.world
        XCTAssertEqual(world.economy.balance, balance - cost, "what the preview said")
        // The track, the stretch and the parallel each split once, and the
        // crossover: 1 + 2 + 2 + 1.
        XCTAssertEqual(world.network.edges.count, 6)
        XCTAssertTrue(try secondTrackReaches(west, from: WorldCoordinate(x: 18_432, y: 7_872), in: world))
        XCTAssertEqual(session.commandLog.entries.count, 1, "one command")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testWithoutTheCrossoverTheSecondTrackReachesNothing() throws {
        // What the crossover is for: the same stretch built as before it.
        let (session, west) = try sessionOnTheTrack()
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        guard case .buildDoubleTrack(let stretch, let parallel, let crossovers)? = try lastCommand(afterBuilding: session) else {
            return XCTFail("not a double track")
        }
        XCTAssertEqual(crossovers.count, 1)
        let (bare, _) = try sessionOnTheTrack()
        _ = try bare.performCommand(.buildDoubleTrack(stretch, parallel: parallel))
        XCTAssertFalse(try secondTrackReaches(west, from: WorldCoordinate(x: 18_432, y: 7_872), in: bare.world))
    }

    func testAStretchBetweenTwoTracksGetsOneAtEachEnd() throws {
        var (session, west) = try sessionOnTheTrack()
        var world = session.world
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 22_528, y: 8_192))
        let beyond = try world.buildTrackNode(at: WorldCoordinate(x: 26_624, y: 8_192))
        try world.buildTrackEdge(from: far, to: beyond)
        session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 22_528, y: 8_192), reach: 16)
        XCTAssertEqual(session.networkDraftPreview?.preview.crossovers.count, 2)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.hasSuffix(" Crossovers join the second track to the track at both ends.") ?? false, session.message?.text ?? "")
        // 2 tracks + stretch + parallel, the stretch and parallel split
        // twice each, 2 crossovers.
        XCTAssertEqual(session.world.network.edges.count, 2 + 2 + 4 + 2)
        // From the far track onto the parallel and back off it: a train
        // from `beyond` heading west reaches `west`.
        let route = session.world.route(
            from: .onEdge(TrackTraversal(edge: try XCTUnwrap(session.world.network.node(beyond)?.ends.first?.edge), direction: .backward), offset: 0),
            to: west
        )
        XCTAssertNotNil(route)
    }

    func testTooShortForACrossoverBuildsTheDoubleTrackAndSaysSo() throws {
        let (session, _) = try sessionOnTheTrack()
        // 64 m: less than 22 m + 50 m + 22 m.
        session.tapNetwork(at: PlanPoint(x: 5_120 + 4_096, y: 8_192), reach: 16)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        XCTAssertTrue(draft.preview.crossovers.isEmpty)
        XCTAssertEqual(
            draft.preview.crossoverNote,
            "The second track is not joined to the track it meets: no room for a crossover (too short, or on a grade). Add one by hand."
        )
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 3)
    }

    func testAStretchFromNothingNeedsNoCrossover() throws {
        let world = try makeWorld(width: 40_960, height: 16_384, balance: 10_000_000, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertTrue(preview.crossovers.isEmpty)
        XCTAssertNil(preview.crossoverNote)
    }

    func testWithoutMoneyForTheCrossoverNothingIsBuilt() throws {
        // The stretch and the parallel alone are affordable; the crossover
        // too is not. All of it is one command: nothing is built.
        let (probe, _) = try sessionOnTheTrack()
        probe.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        let total = try XCTUnwrap(probe.networkPreview?.cost)
        guard case .buildDoubleTrack(let stretch, let parallel, _)? = try lastCommand(afterBuilding: probe) else {
            return XCTFail("not a double track")
        }
        let (bare, _) = try sessionOnTheTrack()
        let before = bare.world.economy.balance
        let setUp = 10_000_000 - before.amount
        _ = try bare.performCommand(.buildDoubleTrack(stretch, parallel: parallel))
        let pair = Money(before.amount - bare.world.economy.balance.amount)
        XCTAssertLessThan(pair, total)
        let (session, _) = try sessionOnTheTrack(balance: Money(setUp + pair.amount + (total.amount - pair.amount) / 2))
        let unchanged = session.world
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .failure, session.message?.text ?? "")
        XCTAssertEqual(session.world, unchanged)
    }

    private func lastCommand(afterBuilding session: GameSession) throws -> PlayerCommand? {
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        guard case .command(let command)? = session.commandLog.entries.last?.action else { return nil }
        return command
    }
}
