import Foundation
@testable import GameCore
import XCTest

/// Splitting an edge of the track network (`GameWorld.splitTrackEdge`, the
/// owner's play-test of 2026-10-06): a turnout can then branch from the
/// middle of a line, and the parts join as the edge did.
final class TrackSplitTests: XCTestCase {
    private let west = WorldCoordinate(x: 2_048, y: 10_240)
    private let left = WorldCoordinate(x: 10_240, y: 10_240)
    private let right = WorldCoordinate(x: 18_432, y: 10_240)
    private let east = WorldCoordinate(x: 26_624, y: 10_240)

    /// Three straight edges west to east, 8192 units (128 m) each:
    /// `.edge(1)`, `.edge(2)` and `.edge(3)`.
    private func world() throws -> GameWorld {
        var world = try makeWorld(width: 40_960, height: 20_480, balance: 1_000_000)
        let nodes = try [west, left, right, east].map { try world.buildTrackNode(at: $0) }
        for index in 1..<nodes.count {
            try world.buildTrackEdge(from: nodes[index - 1], to: nodes[index])
        }
        return world
    }

    private func exits(of edge: TrackEdgeID, at node: TrackNodeID, in world: GameWorld) -> [TrackEdgeID] {
        world.network.node(node)?.end(of: edge)?.exits ?? []
    }

    func testAStraightEdgeSplitsIntoTwoThatJoinAsItDid() throws {
        var world = try world()
        let balance = world.economy.balance
        let node = try world.splitTrackEdge(.edge(2), at: 4_096)
        XCTAssertEqual(node, .node(5))
        XCTAssertEqual(world.network.node(node)?.position, WorldCoordinate(x: 14_336, y: 10_240))
        XCTAssertNil(world.network.edge(.edge(2)), "the old edge is gone; IDs are never reused")
        XCTAssertEqual(world.network.edge(.edge(4))?.length, 4_096)
        XCTAssertEqual(world.network.edge(.edge(5))?.length, 4_096)
        XCTAssertEqual(exits(of: .edge(4), at: node, in: world), [.edge(5)])
        XCTAssertEqual(exits(of: .edge(5), at: node, in: world), [.edge(4)])
        XCTAssertEqual(exits(of: .edge(1), at: .node(2), in: world), [.edge(4)])
        XCTAssertEqual(exits(of: .edge(3), at: .node(3), in: world), [.edge(5)])
        XCTAssertEqual(world.economy.balance, balance, "free: the track is paid for")

        // A train runs straight through.
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 0))
        try world.setTrainContinuation(train, along: [.edge(4), .edge(5), .edge(3)].map { TrackTraversal(edge: $0, direction: .forward) })
        try world.setTrainMovementRate(train, to: 30_000)
        world.setSpeed(.normal)
        try world.advance(ticks: 2)
        guard case .onEdge(let traversal, _)? = world.train(id: train)?.position else { return XCTFail("placed") }
        XCTAssertEqual(traversal.edge, .edge(3))

        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testACurveSplitsAtItsNearestSampleAndStillJoins() throws {
        var world = try makeWorld(width: 40_960, height: 20_480, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 4_096))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 4_096))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 18_432, y: 8_192))
        try world.buildTrackEdge(from: a, to: b)
        let curve = TrackCurve.cubic(PlanPoint(x: 8_192, y: 4_096), PlanPoint(x: 12_288, y: 8_192))
        let edge = try world.buildTrackEdge(from: b, to: c, curve: curve)
        let length = try XCTUnwrap(world.network.edge(edge)?.length)
        let node = try world.splitTrackEdge(edge, at: length / 2)
        let first = try XCTUnwrap(world.network.edge(.edge(3))), second = try XCTUnwrap(world.network.edge(.edge(4)))
        XCTAssertEqual(first.to, node)
        XCTAssertEqual(second.from, node)
        XCTAssertLessThanOrEqual(abs(first.length + second.length - length), 8, "the parts follow the curve")
        XCTAssertLessThanOrEqual(abs(first.length - length / 2), 64, "cut at the sample nearest the middle")
        XCTAssertEqual(exits(of: .edge(1), at: b, in: world), [.edge(3)])
        XCTAssertEqual(exits(of: .edge(3), at: node, in: world), [.edge(4)])
        XCTAssertEqual(exits(of: .edge(4), at: node, in: world), [.edge(3)])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testATurnoutBranchesFromTheNewNode() throws {
        var world = try world()
        let node = try world.splitTrackEdge(.edge(2), at: 4_096)
        let middle = try XCTUnwrap(world.network.node(node)).position
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 26_624, y: 12_288))
        let branch = try world.buildTrackEdge(
            from: node, to: end,
            curve: .cubic(PlanPoint(x: middle.x + 4_096, y: middle.y), PlanPoint(x: 26_624 - 4_096, y: 12_288))
        )
        XCTAssertEqual(exits(of: .edge(4), at: node, in: world), [.edge(5), branch], "a turnout: straight on or the branch")
        XCTAssertEqual(exits(of: branch, at: node, in: world), [.edge(4)])
    }

    func testPlatformsMoveToTheirPartAndOneAcrossTheCutIsRefused() throws {
        var world = try world()
        let near = try world.buildStation(named: "Near", at: PlanPoint(x: 11_264, y: 10_752)).id
        let far = try world.buildStation(named: "Far", at: PlanPoint(x: 16_896, y: 10_752)).id
        try world.addTrackPlatform(near, on: .edge(2), from: 0, to: 2_048)
        try world.addTrackPlatform(far, on: .edge(2), from: 6_144, to: 7_168)
        var across = world
        let both = try across.buildStation(named: "Both", at: PlanPoint(x: 14_336, y: 10_752)).id
        try across.addTrackPlatform(both, on: .edge(2), from: 3_072, to: 5_120)
        XCTAssertThrowsGameError(try across.splitTrackEdge(.edge(2), at: 4_096), .trackEdgeHasPlatform(.edge(2)))

        try world.splitTrackEdge(.edge(2), at: 4_096)
        XCTAssertEqual(world.trackPlatforms(of: near), [TrackPlatform(station: near, edge: .edge(4), start: 0, end: 2_048)])
        XCTAssertEqual(world.trackPlatforms(of: far), [TrackPlatform(station: far, edge: .edge(5), start: 2_048, end: 3_072)])
    }

    /// A diagonal edge's parts are rounded to whole units and can end one
    /// short of where the edge did: a platform at its far end moves back
    /// with its length kept, so a train exactly as long still has a berth.
    func testAPlatformAtTheFarEndKeepsItsLength() throws {
        var world = try makeWorld(width: 40_960, height: 20_480, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_000, y: 1_000))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 31_000, y: 18_000))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let length = try XCTUnwrap(world.network.edge(edge)?.length)
        let station = try world.buildStation(named: "S", at: PlanPoint(x: 30_000, y: 17_000)).id
        try world.addTrackPlatform(station, on: edge, from: length - 4_096, to: length)
        XCTAssertEqual(world.berths(of: station, length: 4_096).count, 2)
        try world.splitTrackEdge(edge, at: 1_026)
        let second = try XCTUnwrap(world.network.edges.last)
        XCTAssertLessThan(1_026 + second.length, length, "the parts are a unit short")
        XCTAssertEqual(world.trackPlatforms(of: station),
                       [TrackPlatform(station: station, edge: second.id, start: second.length - 4_096, end: second.length)])
        XCTAssertEqual(world.berths(of: station, length: 4_096).count, 2)
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)))
    }

    func testRefusalsChangeNothing() throws {
        let world = try world()
        func refuses(_ expected: GameError, _ change: (inout GameWorld) throws -> Void = { _ in }, edge: TrackEdgeID = .edge(2),
                     at distance: Int64 = 4_096, file: StaticString = #filePath, line: UInt = #line) throws {
            var copy = world
            try change(&copy)
            let before = copy
            XCTAssertThrowsGameError(try copy.splitTrackEdge(edge, at: distance), expected, file: file, line: line)
            XCTAssertEqual(copy, before, "nothing changed", file: file, line: line)
        }
        try refuses(.unknownTrackEdge(.edge(9)), edge: .edge(9))
        try refuses(.invalidTrackGeometry, at: 512)
        try refuses(.invalidTrackGeometry, at: 8_192 - 512)
        // A train on it, or one whose path enters it.
        try refuses(.trackReserved(TrainID(rawValue: 1))) { world in
            let train = try world.purchaseTrain(named: "On").id
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(2), direction: .forward), offset: 100))
        }
        try refuses(.trackReserved(TrainID(rawValue: 1))) { world in
            let train = try world.purchaseTrain(named: "Coming").id
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 100))
            try world.setTrainContinuation(train, along: [TrackTraversal(edge: .edge(2), direction: .forward)])
        }
        // A sloping edge is not yet split.
        var sloped = try makeWorld(width: 40_960, height: 20_480, balance: 1_000_000)
        let low = try sloped.buildTrackNode(at: west)
        let high = try sloped.buildTrackNode(at: WorldCoordinate(x: right.x, y: right.y, z: 64))
        try sloped.buildTrackEdge(from: low, to: high)
        let before = sloped
        XCTAssertThrowsGameError(try sloped.splitTrackEdge(.edge(1), at: 4_096), .invalidTrackGeometry)
        XCTAssertEqual(sloped, before)
    }

    func testALinesChosenPathKeepsItsTrack() throws {
        var world = try world()
        let first = try world.buildStation(named: "First", at: PlanPoint(x: 4_096, y: 10_752)).id
        let second = try world.buildStation(named: "Second", at: PlanPoint(x: 11_264, y: 10_752)).id
        try world.addTrackPlatform(first, on: .edge(1), from: 4_096, to: 6_144)
        try world.addTrackPlatform(second, on: .edge(2), from: 0, to: 2_048)
        let line = try world.createLine(named: "L", stops: [first, second]).id
        let platform = try XCTUnwrap(world.trackPlatforms(of: second).first)
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: platform)])
        let before = world
        XCTAssertThrowsGameError(try world.splitTrackEdge(.edge(2), at: 4_096), .trackEdgeInLineRoute(line))
        XCTAssertEqual(world, before)
        XCTAssertNoThrow(try world.splitTrackEdge(.edge(3), at: 4_096), "other track splits")
    }
}
