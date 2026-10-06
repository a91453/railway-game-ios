import GameCore
@testable import GamePresentation
import XCTest

/// A platform track in one step (the owner's play-test, 2026-10-06): beside
/// a station's platform, a parallel track with its own platform, joined by
/// a turnout at each end, island or side.
final class PlatformTrackSessionTests: XCTestCase {
    /// A straight track 480 m long west to east, with station Middle's
    /// 96 m platform halfway.
    private func world() throws -> (GameWorld, TrackPlatform) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 16_384, y: 8_704)).id
        try world.addTrackPlatform(station, on: edge, from: 12_288, to: 18_432)
        return (world, try XCTUnwrap(world.trackPlatforms(of: station).first))
    }

    @MainActor
    func testASidePlatformTrackRunsBesideAndJoinsAtBothEnds() throws {
        let (world, platform) = try world()
        let session = GameSession(world: world)
        XCTAssertEqual(session.platformTrackSideText(.left, of: platform), "north side")
        XCTAssertEqual(session.platformTrackSideText(.right, of: platform), "south side")
        let preview = session.platformTrackPreview(beside: platform, layout: .side, side: .left)
        XCTAssertNil(preview.problem)
        let cost = try XCTUnwrap(preview.cost)
        session.addPlatformTrack(beside: platform, layout: .side, side: .left)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.message?.text, "Middle: side platform track on the north side, for \(cost.moneyText).")
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - cost)

        let after = session.world
        let platforms = after.trackPlatforms(of: platform.station)
        XCTAssertEqual(platforms.count, 2)
        // The old platform now starts 50 m along the part between the
        // turnouts; the new one covers its whole edge.
        XCTAssertTrue(platforms.contains { $0.start == 3_200 && $0.end == 9_344 })
        let new = try XCTUnwrap(platforms.first { $0.start == 0 })
        let middle = try XCTUnwrap(after.network.edge(new.edge))
        let from = try XCTUnwrap(after.network.node(middle.from)), to = try XCTUnwrap(after.network.node(middle.to))
        XCTAssertEqual(from.position, WorldCoordinate(x: 13_312, y: 8_192 - 320), "5 m north of the platform's start")
        XCTAssertEqual(to.position, WorldCoordinate(x: 19_456, y: 8_192 - 320))
        XCTAssertEqual(new.end, middle.length)
        // Each turnout: from the main track a train may go on or onto the
        // platform track.
        let turnouts = after.network.nodes.filter { $0.ends.count == 3 }
        XCTAssertEqual(turnouts.count, 2)
        for turnout in turnouts {
            XCTAssertTrue(turnout.ends.contains { $0.exits.count == 2 }, "a turnout")
        }
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(after)), after)
    }

    @MainActor
    func testAnIslandPlatformTrackStandsFartherOut() throws {
        let (world, platform) = try world()
        let session = GameSession(world: world)
        session.addPlatformTrack(beside: platform, layout: .island, side: .right)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let platforms = session.world.trackPlatforms(of: platform.station)
        XCTAssertEqual(platforms.count, 2)
        let new = try XCTUnwrap(platforms.first { $0.start == 0 })
        let edge = try XCTUnwrap(session.world.network.edge(new.edge))
        XCTAssertEqual(session.world.network.node(edge.from)?.position.y, 8_192 + 704, "11 m south")
    }

    /// No room for the turnouts, or a refusal from GameCore: nothing
    /// changes.
    @MainActor
    func testAPlatformTrackThatDoesNotFitChangesNothing() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let station = try world.buildStation(named: "Short", at: PlanPoint(x: 12_288, y: 8_704)).id
        try world.addTrackPlatform(station, on: edge, from: 1_024, to: 7_168)
        let platform = try XCTUnwrap(world.trackPlatforms(of: station).first)
        let session = GameSession(world: world)
        XCTAssertEqual(session.platformTrackPreview(beside: platform, layout: .side, side: .left).problem,
                       "There is not enough track either side of the platform for the turnouts: the platform's track must run on past each end.")
        session.addPlatformTrack(beside: platform, layout: .side, side: .left)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)
    }
}
