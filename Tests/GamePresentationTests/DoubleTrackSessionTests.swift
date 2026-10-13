import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 204: the network tool's double-track option lays a second
/// track 5 m beside each stretch, in one command, and carries it on from
/// the last parallel when the next stretch is drawn on.
@MainActor
final class DoubleTrackSessionTests: XCTestCase {
    private func session(side: PlatformTrackSide = .left) throws -> GameSession {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: 10_000_000, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.networkDoubleSide = side
        return session
    }

    func testAStraightStretchGetsATrackFiveMetresBeside() throws {
        let session = try session()
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 16)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem)
        XCTAssertEqual(draft.crossing.first, WorldCoordinate(x: 2_048, y: 10_240 - 320), "left of eastward is north")
        XCTAssertEqual(draft.crossing.last, WorldCoordinate(x: 18_432, y: 10_240 - 320))
        let cost = try XCTUnwrap(draft.preview.cost)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, Money(10_000_000) - cost)
        let world = session.world
        XCTAssertEqual(world.network.edges.count, 2)
        let positions = Set(world.network.nodes.map(\.position))
        XCTAssertEqual(positions, [
            WorldCoordinate(x: 2_048, y: 10_240), WorldCoordinate(x: 18_432, y: 10_240),
            WorldCoordinate(x: 2_048, y: 9_920), WorldCoordinate(x: 18_432, y: 9_920),
        ])
        XCTAssertEqual(session.commandLog.entries.count, 1, "one command")
    }

    func testDrawingOnCarriesTheParallelOnFromTheLastOne() throws {
        let session = try session(side: .right)
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 16)
        session.buildNetworkTrack()
        // On round a curve to the south-east.
        session.tapNetwork(at: PlanPoint(x: 30_720, y: 16_384), reach: 16)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        XCTAssertEqual(world.network.edges.count, 4)
        XCTAssertEqual(world.network.nodes.count, 6, "the parallels meet at a node of their own")
        // Each parallel joins the next as the track beside it does: two
        // lines, each running through.
        let through = world.network.nodes.filter { $0.ends.count == 2 }
        XCTAssertEqual(through.count, 2)
        for node in through { XCTAssertTrue(node.ends.allSatisfy { $0.exits.count == 1 }) }
        let south = try XCTUnwrap(world.network.nodes.first { $0.position == WorldCoordinate(x: 18_432, y: 10_560) })
        XCTAssertEqual(south.ends.count, 2, "the second parallel starts where the first ended")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// Decision 164 eases a grade only where it fits under the steepest; the
    /// track on the inside of a curve is shorter, so eased it can be too
    /// steep where the stretch is not. Then both keep a steady grade and
    /// the stretch is built, rather than refused as too steep.
    func testAParallelTooSteepEasedKeepsBothSteady() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 5_120, y: 8_192))
        try world.buildTrackEdge(from: west, to: east)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkStructure = .elevated
        session.networkHeight = 352
        session.networkEasesGrade = true
        session.networkBuildsDouble = true
        // Round a curve to the south-east: the right side is the inside.
        session.networkDoubleSide = .right
        session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 13_312, y: 16_384), reach: 16)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        XCTAssertEqual(draft.preview.profile, .uniform)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let built = session.world.network.edges.filter { $0.id != .edge(1) }
        XCTAssertEqual(built.count, 2)
        XCTAssertTrue(built.allSatisfy { $0.profile == .uniform })
    }

    func testWithoutRoomTheStretchIsNotBuilt() throws {
        var world = try makeWorld(width: 40_960, height: 20_480, balance: 10_000_000, speed: .paused)
        // A track 2 m north of where the parallel would go.
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 9_792))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 19_456, y: 9_792))
        try world.buildTrackEdge(from: a, to: b)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.networkSnapsToTrack = false
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 16)
        XCTAssertNotNil(session.networkPreview?.problem)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world.network.edges.count, 1, "nothing built")
    }
}
