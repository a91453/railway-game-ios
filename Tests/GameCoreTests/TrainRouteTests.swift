import GameCore
import XCTest

/// Route finding: the fewest links from the node ahead of a train to a track
/// tile without turning straight back, ties broken by north, east, south,
/// west order of the exit directions.
///
/// Hand-made cases write their routes out. Random maps are checked against
/// an independent reference written from the rules (distances by repeated
/// relaxation, then a greedy walk; `ReferenceRoute` in PropertySupport.swift),
/// not against a copy of the breadth-first search in GameCore.
final class TrainRouteTests: XCTestCase {
    // A line with a loop at its east end:
    //
    //        f - e
    //        |   |
    //   a - b - c - d
    private let a = GridPosition(x: 1, y: 3)
    private let b = GridPosition(x: 2, y: 3)
    private let c = GridPosition(x: 3, y: 3)
    private let d = GridPosition(x: 4, y: 3)
    private let e = GridPosition(x: 4, y: 2)
    private let f = GridPosition(x: 3, y: 2)

    private func makeLoopWorld() throws -> GameWorld {
        var world = try makeWorld(balance: 100_000)
        try world.buildTrack(at: a, connections: .east)
        try world.buildTrack(at: b, connections: [.east, .west])
        try world.buildTrack(at: c, connections: [.north, .east, .west])
        try world.buildTrack(at: d, connections: [.north, .west])
        try world.buildTrack(at: e, connections: [.south, .west])
        try world.buildTrack(at: f, connections: [.east, .south])
        return world
    }

    // MARK: - Hand-made cases

    func testAStraightRouteListsEveryNodeAfterTheStart() throws {
        var world = try makeWorld(balance: 100_000)
        for x in 1...5 {
            try world.buildTrack(at: GridPosition(x: x, y: 1), connections: [.east, .west])
        }
        let start = TrainPosition.atNode(GridPosition(x: 1, y: 1), heading: .east)

        XCTAssertEqual(
            world.route(from: start, to: GridPosition(x: 4, y: 1)),
            [GridPosition(x: 2, y: 1), GridPosition(x: 3, y: 1), GridPosition(x: 4, y: 1)]
        )
        XCTAssertEqual(world.route(from: start, to: GridPosition(x: 1, y: 1)), [], "already there")
        XCTAssertNil(world.route(from: .atNode(GridPosition(x: 3, y: 1), heading: .east), to: GridPosition(x: 1, y: 1)), "behind, no loop")
    }

    func testARouteFromALinkStartsAtItsEnd() throws {
        let world = try makeLoopWorld()
        let start = TrainPosition.onLink(from: a, to: b, offset: 700)

        XCTAssertEqual(world.route(from: start, to: b), [])
        XCTAssertEqual(world.route(from: start, to: c), [c])
        XCTAssertEqual(world.route(from: start, to: d), [c, d])
        // a is behind the train: reachable only round the loop.
        XCTAssertEqual(world.route(from: start, to: a), [c, f, e, d, c, b, a])
    }

    func testALoopTurnsTheTrainAroundWithoutReversing() throws {
        let world = try makeLoopWorld()

        // a lies behind a train at b facing east: once round the loop. At c
        // both ways round are 7 links; north (f) comes before east (d).
        XCTAssertEqual(world.route(from: .atNode(b, heading: .east), to: a), [c, f, e, d, c, b, a])
        // Facing the dead end at a there is no way to d without reversing.
        XCTAssertNil(world.route(from: .atNode(b, heading: .west), to: d))
        XCTAssertEqual(world.route(from: .atNode(a, heading: .east), to: d), [b, c, d])
    }

    func testTiesGoToNorthThenEastThenSouthThenWest() throws {
        // Two 2-link routes from s to t: north then east, or east then north.
        var world = try makeWorld(balance: 100_000)
        let s = GridPosition(x: 1, y: 5)
        let n = GridPosition(x: 1, y: 4)
        let east = GridPosition(x: 2, y: 5)
        let t = GridPosition(x: 2, y: 4)
        try world.buildTrack(at: s, connections: [.north, .east])
        try world.buildTrack(at: n, connections: [.south, .east])
        try world.buildTrack(at: east, connections: [.west, .north])
        try world.buildTrack(at: t, connections: [.west, .south])

        XCTAssertEqual(world.route(from: .atNode(s, heading: .east), to: t), [n, t])
        XCTAssertEqual(world.route(from: .atNode(s, heading: .north), to: t), [n, t])
        // Facing south, north would turn straight back.
        XCTAssertEqual(world.route(from: .atNode(s, heading: .south), to: t), [east, t])
        // Facing west, east would turn straight back.
        XCTAssertEqual(world.route(from: .atNode(s, heading: .west), to: t), [n, t])
    }

    func testFewerLinksWinOverDirectionOrder() throws {
        // From a junction j facing east: north leads round to t in 5 links,
        // south in 1. South wins although north comes first.
        var world = try makeWorld(balance: 100_000)
        let j = GridPosition(x: 5, y: 5)
        let t = GridPosition(x: 5, y: 6)
        try world.buildTrack(at: j, connections: [.north, .south, .west])
        try world.buildTrack(at: GridPosition(x: 5, y: 4), connections: [.south, .east])
        try world.buildTrack(at: GridPosition(x: 6, y: 4), connections: [.west, .south])
        try world.buildTrack(at: GridPosition(x: 6, y: 5), connections: [.north, .south])
        try world.buildTrack(at: GridPosition(x: 6, y: 6), connections: [.north, .west])
        try world.buildTrack(at: t, connections: [.north, .east])

        XCTAssertEqual(world.route(from: .atNode(j, heading: .east), to: t), [t])
    }

    func testAJunctionIsLeftByTheBranchThatLeadsThere() throws {
        var world = try makeWorld(balance: 100_000)
        let j = GridPosition(x: 3, y: 3)
        try world.buildTrack(at: GridPosition(x: 2, y: 3), connections: [.east, .west])
        try world.buildTrack(at: j, connections: [.east, .south, .west])
        try world.buildTrack(at: GridPosition(x: 4, y: 3), connections: [.east, .west])
        try world.buildTrack(at: GridPosition(x: 3, y: 4), connections: [.north, .south])
        let start = TrainPosition.atNode(GridPosition(x: 2, y: 3), heading: .east)

        XCTAssertEqual(world.route(from: start, to: GridPosition(x: 3, y: 4)), [j, GridPosition(x: 3, y: 4)])
        XCTAssertEqual(world.route(from: start, to: GridPosition(x: 4, y: 3)), [j, GridPosition(x: 4, y: 3)])
    }

    func testThereIsNoRouteToAnythingButReachableTrack() throws {
        var world = try makeLoopWorld()
        let station = GridPosition(x: 5, y: 3)
        try world.buildStation(named: "Yard", at: station)
        let isolated = GridPosition(x: 8, y: 8)
        try world.buildTrack(at: isolated, connections: [.north, .south])
        let start = TrainPosition.atNode(b, heading: .east)

        for destination in [station, isolated, GridPosition(x: 0, y: 0), GridPosition(x: 20, y: 3), GridPosition(x: -1, y: 3),
                            GridPosition(x: Int.max, y: Int.min), GridPosition(x: Int.min, y: Int.max)] {
            XCTAssertNil(world.route(from: start, to: destination), "\(destination)")
        }
    }

    func testInvalidStartsHaveNoRouteAndDoNotTrap() throws {
        let world = try makeLoopWorld()
        let starts: [TrainPosition] = [
            .atNode(GridPosition(x: 0, y: 0), heading: .east), // empty
            .atNode(GridPosition(x: -1, y: 3), heading: .east),
            .atNode(GridPosition(x: Int.max, y: Int.max), heading: .north),
            .onLink(from: a, to: b, offset: 0),
            .onLink(from: a, to: b, offset: 1024),
            .onLink(from: a, to: b, offset: .min),
            .onLink(from: a, to: c, offset: 512), // not neighbours
            .onLink(from: b, to: GridPosition(x: 2, y: 4), offset: 512), // not joined
            .onLink(from: GridPosition(x: Int.max, y: 0), to: GridPosition(x: Int.min, y: 0), offset: 512),
        ]
        for start in starts {
            XCTAssertNil(world.route(from: start, to: d), "\(start)")
        }
    }

    // MARK: - Using a route

    func testARouteIsAContinuationTheTrainFollowsToTheDestination() throws {
        var world = try makeLoopWorld()
        try world.purchaseTrain(named: "Local")
        let id = TrainID(rawValue: 1)
        try world.placeTrain(id, at: .onLink(from: a, to: b, offset: 300))
        world.setSpeed(.normal)

        let route = try XCTUnwrap(world.route(from: XCTUnwrap(world.train(id: id)?.position), to: a))
        XCTAssertEqual(route, [c, f, e, d, c, b, a])
        try world.setTrainContinuation(id, to: route)
        try world.setTrainMovementRate(id, to: 1024)
        try world.advance(ticks: 20)

        XCTAssertEqual(world.train(id: id)?.position, .atNode(a, heading: .west))
        XCTAssertEqual(world.train(id: id)?.movement.continuation, [])
    }

    func testFindingARouteChangesNothing() throws {
        let world = try makeLoopWorld()
        let copy = world

        _ = world.route(from: .atNode(b, heading: .east), to: a)
        _ = world.route(from: .atNode(b, heading: .west), to: d)

        XCTAssertEqual(world, copy)
    }

    func testTheRouteDependsOnTheMapNotOnBuildOrder() throws {
        var forward = try makeWorld(balance: 100_000)
        var backward = try makeWorld(balance: 100_000)
        var tiles: [(GridPosition, TrackConnections)] = []
        for x in 0..<6 {
            for y in 0..<6 {
                tiles.append((GridPosition(x: x, y: y), [.north, .east, .south, .west]))
            }
        }
        for (position, connections) in tiles {
            try forward.buildTrack(at: position, connections: connections)
        }
        for (position, connections) in tiles.reversed() {
            try backward.buildTrack(at: position, connections: connections)
        }
        let start = TrainPosition.atNode(GridPosition(x: 0, y: 0), heading: .south)

        let route = forward.route(from: start, to: GridPosition(x: 3, y: 2))
        XCTAssertEqual(route, backward.route(from: start, to: GridPosition(x: 3, y: 2)))
        // East before south at every step while both are still shortest.
        XCTAssertEqual(route, [
            GridPosition(x: 1, y: 0), GridPosition(x: 2, y: 0), GridPosition(x: 3, y: 0),
            GridPosition(x: 3, y: 1), GridPosition(x: 3, y: 2),
        ])
    }

    func testALargeGridIsSearchedWithoutTrouble() throws {
        var world = try makeWorld(width: 100, height: 100, balance: 1_000_000_000)
        for x in 0..<96 {
            for y in 0..<95 {
                try world.buildTrack(at: GridPosition(x: x, y: y), connections: [.north, .east, .south, .west])
            }
        }
        let island = GridPosition(x: 50, y: 99)
        try world.buildTrack(at: island, connections: [.east, .west])
        let start = TrainPosition.atNode(GridPosition(x: 0, y: 0), heading: .east)

        let expected = (1...95).map { GridPosition(x: $0, y: 0) } + (1...94).map { GridPosition(x: 95, y: $0) }
        XCTAssertEqual(world.route(from: start, to: GridPosition(x: 95, y: 94)), expected)
        // Every reachable state is visited before giving up.
        XCTAssertNil(world.route(from: start, to: island))
    }

    // MARK: - Against an independent reference

    func testRandomMapsMatchTheReferenceAndTheRoutesCanBeFollowed() throws {
        var random = SplitMix64(seed: 0x5EED_0001)
        var compared = 0
        var found = 0
        for _ in 0..<150 {
            let width = 5
            let height = 5
            var world = try makeWorld(width: width, height: height, balance: 10_000_000)
            // Mostly track, a few stations; neighbouring track is joined both
            // ways with some probability, and some exits are left one-sided.
            var kinds: [GridPosition: Int] = [:]
            var exits: [GridPosition: TrackConnections] = [:]
            for x in 0..<width {
                for y in 0..<height {
                    let roll = random.next() % 20
                    kinds[GridPosition(x: x, y: y)] = roll < 16 ? 0 : (roll < 17 ? 1 : 2)
                }
            }
            for x in 0..<width {
                for y in 0..<height {
                    let tile = GridPosition(x: x, y: y)
                    guard kinds[tile] == 0 else { continue }
                    for (way, neighbor) in [(TrackDirection.east, GridPosition(x: x + 1, y: y)), (.south, GridPosition(x: x, y: y + 1))] {
                        if kinds[neighbor] == 0, random.next() % 10 < 6 {
                            exits[tile, default: []].insert(TrackConnections(way))
                            exits[neighbor, default: []].insert(TrackConnections(way.opposite))
                        }
                    }
                    if random.next() % 5 == 0 {
                        exits[tile, default: []].insert(TrackConnections(TrackDirection.allCases[Int(random.next() % 4)]))
                    }
                }
            }
            for x in 0..<width {
                for y in 0..<height {
                    let tile = GridPosition(x: x, y: y)
                    if kinds[tile] == 0 {
                        let connections = exits[tile] ?? TrackConnections(TrackDirection.allCases[Int(random.next() % 4)])
                        try world.buildTrack(at: tile, connections: connections.isEmpty ? .north : connections)
                    } else if kinds[tile] == 1 {
                        try world.buildStation(named: "S", at: tile)
                    }
                }
            }
            try world.purchaseTrain(named: "Probe")
            world.setSpeed(.normal)

            for _ in 0..<25 {
                let start = randomStart(in: world, using: &random)
                let destination = GridPosition(x: Int(random.next() % 7) - 1, y: Int(random.next() % 7) - 1)
                let route = world.route(from: start, to: destination)
                compared += 1
                XCTAssertEqual(route, ReferenceRoute.route(in: world, from: start, to: destination), "\(start) to \(destination)")

                guard let route else { continue }
                found += 1
                var follower = world
                let id = TrainID(rawValue: 1)
                try follower.placeTrain(id, at: start)
                try follower.setTrainContinuation(id, to: route)
                try follower.setTrainMovementRate(id, to: .max)
                try follower.advance(ticks: 1)
                guard case .atNode(let end, _)? = follower.train(id: id)?.position else {
                    return XCTFail("\(start) to \(destination) did not end at a node")
                }
                XCTAssertEqual(end, destination, "\(start) via \(route)")
            }
        }
        XCTAssertEqual(compared, 150 * 25)
        XCTAssertGreaterThan(found, 500, "the random maps should give many routes")
    }

    /// A start that is usually valid (a node or a link on the map's track)
    /// and sometimes not.
    private func randomStart(in world: GameWorld, using random: inout SplitMix64) -> TrainPosition {
        let headings = TrackDirection.allCases
        let heading = headings[Int(random.next() % 4)]
        let tracks = world.tracks
        guard !tracks.isEmpty, random.next() % 10 != 0 else {
            return .atNode(GridPosition(x: Int(random.next() % 5), y: Int(random.next() % 5)), heading: heading)
        }
        let tile = tracks[Int(random.next() % UInt64(tracks.count))].position
        let neighbors = world.connectedNeighbors(of: tile)
        if random.next() % 2 == 0, !neighbors.isEmpty {
            let to = neighbors[Int(random.next() % UInt64(neighbors.count))]
            return .onLink(from: tile, to: to, offset: Int64(random.next() % 1023) + 1)
        }
        return .atNode(tile, heading: heading)
    }
}
