import Foundation
@testable import GameCore
import XCTest

/// Keeping left on double track (ARCHITECTURE decision 202).
///
/// The network, worked by hand: West's platform on a single track (e1,
/// x 1,024 to 5,120 at y 5,120), which parts at node 2 into a north track
/// (e2 to y 4,096, e4 along it) and a south track (e3 to y 6,144, e5 along
/// it), which meet again at node 7 (e6, e7) for East's platform on a single
/// track (e8, x 34,816 to 38,912). The two tracks are mirror images, so
/// both ways round are equally long, and the turnouts start along the
/// straight (each curve's first control point is on it), so only the chord
/// tells which way on is left.
///
/// x grows east and y south: going east the north track is on the left,
/// going west the south track. Before the rule both ways took the north
/// track, the first of the equally short ways by edge number (e2 before e3,
/// e6 before e7): TestFlight 56.1's report of both directions on one line.
final class KeepLeftTests: XCTestCase {
    static let eastbound = [2, 4, 6, 8].map { TrackTraversal(edge: .edge($0), direction: .forward) }
    static let westboundLeft = [7, 5, 3, 1].map { TrackTraversal(edge: .edge($0), direction: .backward) }
    static let westboundNorth = [6, 4, 2, 1].map { TrackTraversal(edge: .edge($0), direction: .backward) }

    /// The network. With a `bow`, the south track between nodes 4 and 6
    /// leaves its line by an S-curve 4,096 long to `bow` units further
    /// south (node 9), runs straight to node 10 and comes back the same way
    /// (e5 to node 9, e9, e10 to node 6): longer, with each joint along the
    /// straight.
    static func world(keepLeft: Bool, bow: Int64 = 0) throws -> (world: GameWorld, west: StationID, east: StationID) {
        var world = try GameWorld(bounds: WorldBounds(width: 40_960, height: 20_480), economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0)), clock: GameClock(speed: .normal))
        for (x, y): (Int64, Int64) in [(1_024, 5_120), (5_120, 5_120), (9_216, 4_096), (9_216, 6_144), (30_720, 4_096), (30_720, 6_144), (34_816, 5_120), (38_912, 5_120)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        if bow > 0 {
            try world.buildTrackNode(at: WorldCoordinate(x: 13_312, y: 6_144 + bow)) // node 9
            try world.buildTrackNode(at: WorldCoordinate(x: 26_624, y: 6_144 + bow)) // node 10
        }
        try world.buildTrackEdge(from: .node(1), to: .node(2)) // e1
        try world.buildTrackEdge(from: .node(2), to: .node(3), curve: .cubic(PlanPoint(x: 7_168, y: 5_120), PlanPoint(x: 7_168, y: 4_096))) // e2
        try world.buildTrackEdge(from: .node(2), to: .node(4), curve: .cubic(PlanPoint(x: 7_168, y: 5_120), PlanPoint(x: 7_168, y: 6_144))) // e3
        try world.buildTrackEdge(from: .node(3), to: .node(5)) // e4
        if bow > 0 {
            try world.buildTrackEdge(from: .node(4), to: .node(9), curve: .cubic(PlanPoint(x: 11_264, y: 6_144), PlanPoint(x: 11_264, y: 6_144 + bow))) // e5
        } else {
            try world.buildTrackEdge(from: .node(4), to: .node(6)) // e5
        }
        try world.buildTrackEdge(from: .node(5), to: .node(7), curve: .cubic(PlanPoint(x: 32_768, y: 4_096), PlanPoint(x: 32_768, y: 5_120))) // e6
        try world.buildTrackEdge(from: .node(6), to: .node(7), curve: .cubic(PlanPoint(x: 32_768, y: 6_144), PlanPoint(x: 32_768, y: 5_120))) // e7
        try world.buildTrackEdge(from: .node(7), to: .node(8)) // e8
        if bow > 0 {
            try world.buildTrackEdge(from: .node(9), to: .node(10)) // e9
            try world.buildTrackEdge(from: .node(10), to: .node(6), curve: .cubic(PlanPoint(x: 28_672, y: 6_144 + bow), PlanPoint(x: 28_672, y: 6_144))) // e10
        }
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 7_168)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 36_864, y: 7_168)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: .edge(8), from: 1_024, to: 3_072)
        world.setKeepLeft(keepLeft)
        return (world, west, east)
    }

    /// West's berth facing east, and East's facing west.
    static let fromWest = TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 3_072)
    static let fromEast = TrainPosition.onEdge(TrackTraversal(edge: .edge(8), direction: .backward), offset: 3_072)

    func testTheTwoTracksAreEquallyLongAndTheTurnoutsStartAlongTheStraight() throws {
        let world = try Self.world(keepLeft: false).world
        let length = { (edge: Int) in world.network.edge(.edge(edge))!.length }
        XCTAssertEqual(length(2), length(3))
        XCTAssertEqual(length(4), length(5))
        XCTAssertEqual(length(6), length(7))
        let node = world.network.node(.node(2))!
        XCTAssertEqual(node.end(of: .edge(2))!.direction, node.end(of: .edge(3))!.direction, "the tangents tie; the chord decides")
    }

    func testOffBothDirectionsTakeTheNorthTrackAsBefore() throws {
        let (world, west, east) = try Self.world(keepLeft: false)
        XCTAssertEqual(world.path(from: Self.fromWest, toStation: east)?.traversals, Self.eastbound)
        XCTAssertEqual(world.path(from: Self.fromEast, toStation: west)?.traversals, Self.westboundNorth)
    }

    func testOnEachDirectionTakesTheTrackOnItsLeft() throws {
        let (world, west, east) = try Self.world(keepLeft: true)
        let out = try XCTUnwrap(world.path(from: Self.fromWest, toStation: east))
        let back = try XCTUnwrap(world.path(from: Self.fromEast, toStation: west))
        XCTAssertEqual(out.traversals, Self.eastbound, "north, on the left going east")
        XCTAssertEqual(back.traversals, Self.westboundLeft, "south, on the left going west")
        // Selection only: the distance is the path's exact length, the same
        // both ways round.
        let off = try Self.world(keepLeft: false).world
        XCTAssertEqual(out.distance, off.path(from: Self.fromWest, toStation: east)?.distance)
        XCTAssertEqual(back.distance, off.path(from: Self.fromEast, toStation: west)?.distance)
        XCTAssertEqual(out.distance, back.distance)
    }

    /// Into a depot's free siding (decision 221) a train keeps left too.
    func testTheWayIntoADepotKeepsLeft() throws {
        var (world, west, _) = try Self.world(keepLeft: true)
        try world.setStationDepot(west, to: true)
        let train = try world.purchaseTrain(named: "T1")
        var memo = GameWorld.PathMemo()
        let path = try XCTUnwrap(world.pathIntoDepot(west, from: Self.fromEast, for: train, memo: &memo))
        XCTAssertEqual(path.traversals, Self.westboundLeft, "south, on the left going west")
    }

    func testTheWaysOnRightOfTheLeftmost() throws {
        let world = try Self.world(keepLeft: true).world
        let forward = { (edge: Int) in TrackTraversal(edge: .edge(edge), direction: .forward) }
        let backward = { (edge: Int) in TrackTraversal(edge: .edge(edge), direction: .backward) }
        XCTAssertEqual(world.rightOfLeftmost(after: forward(1), among: world.transitions(after: forward(1))), [forward(3)])
        XCTAssertEqual(world.rightOfLeftmost(after: backward(8), among: world.transitions(after: backward(8))), [backward(6)])
        XCTAssertEqual(world.rightOfLeftmost(after: forward(4), among: world.transitions(after: forward(4))), [], "one way on")
    }

    /// The south track bowed further south is longer going west: by about
    /// 1,274 units bowed 2,048, about 4,057 bowed 4,096. Within the margin
    /// the train still keeps left; beyond it, the shorter north track wins.
    func testTheLeftWinsOnlyWithinTheMargin() throws {
        XCTAssertEqual(GameWorld.keepLeftMargin, 3_200, "50 m")
        let north = try Self.world(keepLeft: true).world.network.edge(.edge(4))!.length
        for (bow, keepsLeft) in [(Int64(2_048), true), (4_096, false)] {
            let (world, west, _) = try Self.world(keepLeft: true, bow: bow)
            let south = [5, 9, 10].map { world.network.edge(.edge($0))!.length }.reduce(0, +)
            XCTAssertEqual(south - north > 0 && south - north < GameWorld.keepLeftMargin, keepsLeft, "bow \(bow): \(south - north) longer")
            let path = try XCTUnwrap(world.path(from: Self.fromEast, toStation: west))
            XCTAssertEqual(path.traversals.contains(TrackTraversal(edge: .edge(5), direction: .backward)), keepsLeft, "bow \(bow)")
            XCTAssertEqual(path.traversals.contains(TrackTraversal(edge: .edge(4), direction: .backward)), !keepsLeft, "bow \(bow)")
        }
    }

    func testALinesJourneyKeepsLeftBothWays() throws {
        for keepLeft in [false, true] {
            var (world, west, east) = try Self.world(keepLeft: keepLeft)
            let line = try world.createLine(named: "Main", stops: [west, east]).id
            let legs = try XCTUnwrap(world.lineJourney(line)).legs
            XCTAssertEqual(legs.map(\.path.traversals).map { Array($0.dropLast()) }, [Array(Self.eastbound.dropLast()), Array((keepLeft ? Self.westboundLeft : Self.westboundNorth).dropLast())], "keepLeft \(keepLeft)")
        }
    }

    /// A line's chosen route is followed as it was: the rule does not turn
    /// a westbound route by the north track to the south.
    func testALinesChosenRouteIsKeptAsItWas() throws {
        var (world, west, east) = try Self.world(keepLeft: true)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        let platform = try XCTUnwrap(world.trackPlatforms(of: west).first)
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 1, to: 0, tracks: [TrackTraversal(edge: .edge(8), direction: .backward)] + Self.westboundNorth, platform: platform)])
        let legs = try XCTUnwrap(world.lineJourney(line)).legs
        XCTAssertEqual(legs.last?.path.traversals, Self.westboundNorth)
    }

    /// Double track with a platform on each track at both ends and a
    /// crossover just beyond each station, the way a train leaving it turns
    /// to its left: the north track (nodes 1 to 4, e1 to e3), the south
    /// track (nodes 5 to 8, e4 to e6), e7 from the south track to the north
    /// going east past West, e8 from the north track to the south going west
    /// past East.
    static func crossovers(keepLeft: Bool) throws -> (world: GameWorld, line: LineID) {
        var world = try GameWorld(bounds: WorldBounds(width: 40_960, height: 10_240), economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0)), clock: GameClock(speed: .normal))
        for (x, y): (Int64, Int64) in [(1_024, 4_096), (13_312, 4_096), (31_744, 4_096), (38_912, 4_096), (1_024, 6_144), (9_216, 6_144), (27_648, 6_144), (38_912, 6_144)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        for (from, to) in [(1, 2), (2, 3), (3, 4), (5, 6), (6, 7), (7, 8)] {
            try world.buildTrackEdge(from: .node(from), to: .node(to))
        }
        try world.buildTrackEdge(from: .node(6), to: .node(2), curve: .cubic(PlanPoint(x: 11_264, y: 6_144), PlanPoint(x: 11_264, y: 4_096))) // e7
        try world.buildTrackEdge(from: .node(3), to: .node(7), curve: .cubic(PlanPoint(x: 29_696, y: 4_096), PlanPoint(x: 29_696, y: 6_144))) // e8
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_192)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 36_864, y: 8_192)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(west, on: .edge(4), from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: .edge(3), from: 4_096, to: 6_144)
        try world.addTrackPlatform(east, on: .edge(6), from: 8_192, to: 10_240)
        world.setKeepLeft(keepLeft)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        return (world, line)
    }

    /// Two trains on the line under traffic control, one from each end:
    /// going east they keep to the north track, going west to the south,
    /// crossing over beyond each station. Without the rule both run the
    /// middle of the north track both ways.
    func testTwoTrainsRunningTheLineEachKeepToTheirLeft() throws {
        let northEast = TrackTraversal(edge: .edge(2), direction: .forward), northWest = TrackTraversal(edge: .edge(2), direction: .backward)
        let southEast = TrackTraversal(edge: .edge(5), direction: .forward), southWest = TrackTraversal(edge: .edge(5), direction: .backward)
        for keepLeft in [true, false] {
            var (world, line) = try Self.crossovers(keepLeft: keepLeft)
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
            world.setFlexDispatch(true)
            // West's north platform facing east; East's south platform facing west.
            for (position, name) in [(TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 3_072), "Out"),
                                     (.onEdge(TrackTraversal(edge: .edge(6), direction: .backward), offset: 3_072), "Back")] {
                let train = try world.purchaseTrain(named: name).id
                try world.setTrainCars(train, to: 2)
                try world.placeTrain(train, at: position)
                if case .onEdge(_, let offset) = position { try world.setTrainContinuation(train, along: [], stoppingAt: offset) }
                try world.setTrainMovementRate(train, to: 1_024)
                try world.assignTrain(train, to: line)
            }
            try world.setTrafficControl(true)
            world.setSpeed(.x1)
            var seen: Set<TrackTraversal> = []
            for _ in 0..<1_200 {
                try world.advance(ticks: 10)
                for train in world.trains {
                    if case .onEdge(let traversal, _)? = train.position { seen.insert(traversal) }
                }
            }
            if keepLeft {
                XCTAssertTrue(seen.isSuperset(of: [northEast, southWest]), "both ways ran: \(seen)")
                XCTAssertFalse(seen.contains(northWest), "none went west on the north track")
                XCTAssertFalse(seen.contains(southEast), "none went east on the south track")
            } else {
                XCTAssertTrue(seen.isSuperset(of: [northEast, northWest]), "both ways on the north track: \(seen)")
            }
        }
    }

    func testASaveWithoutItFindsItsRoutesAsBeforeAndOneWithItKeepsIt() throws {
        let plain = try Self.world(keepLeft: false).world
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("keepLeft"), "written only when on")
        let left = try Self.world(keepLeft: true).world
        let text = String(decoding: try JSONEncoder().encode(left), as: UTF8.self)
        XCTAssertTrue(text.contains(#""keepLeft":true"#))
        let decoded = try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8))
        XCTAssertEqual(decoded, left)
        XCTAssertTrue(decoded.keepLeft)
    }

    func testVersionFiftyTwoKeepsKeepingLeft() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v52-keep-left.json")
        var (made, west, east) = try Self.world(keepLeft: true)
        let line = try made.createLine(named: "Main", stops: [west, east]).id
        let train = try made.purchaseTrain(named: "Blue").id
        try made.setTrainCars(train, to: 2)
        try made.placeTrain(train, at: Self.fromEast)
        try made.assignTrain(train, to: line)
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["KEEP_LEFT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 52)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertTrue(loaded.keepLeft)
        XCTAssertEqual(loaded.path(from: Self.fromEast, toStation: west)?.traversals, Self.westboundLeft)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 52,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
