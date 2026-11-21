import Foundation
@testable import GameCore
import XCTest

/// HK-LATE-RUNS: the way to a line's chosen platform keeps left (decision
/// 202) when that takes fewer crossovers than the shortest way.
///
/// The network, worked by hand: double track west to east. The north
/// track runs from node 1 to node 7 (e1, e2, e3, e4, e5, e6, e7); between
/// nodes 3 and 4 it bows north by an S-curve 2,500 units up (e3), a
/// straight (e4) and an S-curve back down (e5), every joint along the
/// straight. The south track runs from node 9 to node 12 (e8, e9, e10). A
/// crossover leaves the north track at node 2 for the south track at node
/// 10 going east (e11), and one comes back up from node 11 to node 8 (e12). The way over the two crossovers
/// and the south track is 533 units (8 m) shorter than the north track's
/// bow, so the shortest way east runs on the south track, against the
/// trains coming west on it, as the South Island Line's northbound trains
/// did between Wong Chuk Hang and Ocean Park. West's platform is on e1,
/// East's on e7.
final class PreferredPlatformKeepLeftTests: XCTestCase {
    static let straight = [2, 3, 4, 5, 6, 7].map { TrackTraversal(edge: .edge($0), direction: .forward) }
    static let overTheCrossovers = [11, 9, 12, 7].map { TrackTraversal(edge: .edge($0), direction: .forward) }

    static func world(keepLeft: Bool) throws -> (world: GameWorld, line: LineID, preference: LineRoutePreference) {
        var world = try GameWorld(bounds: WorldBounds(width: 40_960, height: 20_480), economy: fixtureEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0)), clock: GameClock(speed: .normal))
        let north: Int64 = 12_288, south: Int64 = 14_336, bow: Int64 = north - 2_500
        for (x, y): (Int64, Int64) in [(1_024, north), (9_216, north), (13_312, north), (26_624, north), (17_408, bow), (22_528, bow), (38_912, north), (30_720, north),
                                       (1_024, south), (13_312, south), (26_624, south), (38_912, south)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        // Nodes: 1 West end, 2 the turnout down, 3 and 4 the bow's ends, 5 and
        // 6 its top, 7 East end, 8 the turnout up; 9 to 12 the south track.
        try world.buildTrackEdge(from: .node(1), to: .node(2)) // e1
        try world.buildTrackEdge(from: .node(2), to: .node(3)) // e2
        try world.buildTrackEdge(from: .node(3), to: .node(5), curve: .cubic(PlanPoint(x: 15_360, y: north), PlanPoint(x: 15_360, y: bow))) // e3
        try world.buildTrackEdge(from: .node(5), to: .node(6)) // e4
        try world.buildTrackEdge(from: .node(6), to: .node(4), curve: .cubic(PlanPoint(x: 24_576, y: bow), PlanPoint(x: 24_576, y: north))) // e5
        try world.buildTrackEdge(from: .node(4), to: .node(8)) // e6
        try world.buildTrackEdge(from: .node(8), to: .node(7)) // e7
        try world.buildTrackEdge(from: .node(9), to: .node(10)) // e8
        try world.buildTrackEdge(from: .node(10), to: .node(11)) // e9
        try world.buildTrackEdge(from: .node(11), to: .node(12)) // e10
        try world.buildTrackEdge(from: .node(2), to: .node(10), curve: .cubic(PlanPoint(x: 11_264, y: north), PlanPoint(x: 11_264, y: south))) // e11
        try world.buildTrackEdge(from: .node(11), to: .node(8), curve: .cubic(PlanPoint(x: 28_672, y: south), PlanPoint(x: 28_672, y: north))) // e12
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 16_384)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 36_864, y: 16_384)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: .edge(7), from: 2_048, to: 4_096)
        world.setKeepLeft(keepLeft)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        let platform = try XCTUnwrap(world.trackPlatforms(of: east).first)
        let preference = LineRoutePreference(from: 0, to: 1, platform: platform)
        try world.setLineRoutePreferences(line, to: [preference])
        return (world, line, preference)
    }

    static let fromWest = TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 3_072)

    func testTheNetworkIsAsWorkedByHand() throws {
        let (world, _, _) = try Self.world(keepLeft: true)
        let bowed = try [2, 3, 4, 5, 6].map { try XCTUnwrap(world.network.edge(.edge($0))).length }.reduce(0, +)
        let over = try [11, 9, 12].map { try XCTUnwrap(world.network.edge(.edge($0))).length }.reduce(0, +)
        XCTAssertGreaterThan(bowed, over, "the north track is the longer way")
        XCTAssertLessThan(bowed - over, GameWorld.keepLeftMargin, "but within the margin keeping left allows")
    }

    /// Only the two crossovers count as crossovers: the tracks' own edges
    /// at the turnouts lie alone on their side of a node at one end.
    func testCrossoversCountsTheEdgesBetweenTheTwoTracks() throws {
        let (world, _, _) = try Self.world(keepLeft: true)
        XCTAssertEqual(world.crossovers(on: TrainPath(traversals: Self.straight, end: nil, distance: 0)), 0)
        XCTAssertEqual(world.crossovers(on: TrainPath(traversals: Self.overTheCrossovers, end: nil, distance: 0)), 2)
    }

    /// Keeping left, the way to the chosen platform stays on the north
    /// track; with the rule off it is the shortest, over the crossovers,
    /// as before.
    func testTheWayToTheChosenPlatformKeepsToItsTrack() throws {
        for keepLeft in [true, false] {
            let (world, _, preference) = try Self.world(keepLeft: keepLeft)
            let path = try XCTUnwrap(world.preferredPath(from: Self.fromWest, preference: preference, length: 0))
            XCTAssertEqual(path.traversals, keepLeft ? Self.straight : Self.overTheCrossovers, "keepLeft \(keepLeft)")
        }
    }
}
