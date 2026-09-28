import Foundation
import GameCore
import XCTest

/// Station stops (Stage N): a station's platforms are the track tiles
/// directly north, east, south and west of it; a route to a station ends at
/// the first platform reached; and a train is stopped at a station when it
/// stands at the centre of one of its platforms with no continuation left.
///
/// Hand-made cases write their answers out. Generated networks check the
/// station route against ``GameWorld/route(from:to:)`` for every platform
/// (itself checked against an independent reference in TrainRouteTests),
/// and the stop against its definition, written again here.
final class StationStopTests: XCTestCase {
    // A line along row 2 with dead ends at both ends, and stations beside it:
    //
    //            C       M
    //   a - b - c - d - e - f
    //                    H
    //
    // Central (2,1) is north of b; Market (4,1) and Hill (4,3) are north and
    // south of d, so d is a platform of both.
    private let a = GridPosition(x: 1, y: 2)
    private let b = GridPosition(x: 2, y: 2)
    private let c = GridPosition(x: 3, y: 2)
    private let d = GridPosition(x: 4, y: 2)
    private let e = GridPosition(x: 5, y: 2)
    private let f = GridPosition(x: 6, y: 2)
    private let central = StationID(rawValue: 1)
    private let market = StationID(rawValue: 2)
    private let hill = StationID(rawValue: 3)
    private let first = TrainID(rawValue: 1)

    private func makeLineWorld() throws -> GameWorld {
        var world = try makeWorld(balance: 1_000_000)
        try world.buildTrack(at: a, connections: .east)
        for tile in [b, c, d, e] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: f, connections: .west)
        try world.buildStation(named: "Central", at: GridPosition(x: 2, y: 1))
        try world.buildStation(named: "Market", at: GridPosition(x: 4, y: 1))
        try world.buildStation(named: "Hill", at: GridPosition(x: 4, y: 3))
        world.setSpeed(.normal)
        return world
    }

    /// The line world with Train 1 placed at `position`.
    private func makeLineWorld(trainAt position: TrainPosition, rate: Int64 = 0) throws -> GameWorld {
        var world = try makeLineWorld()
        try world.purchaseTrain(named: "Train 1")
        try world.placeTrain(first, at: position)
        try world.setTrainMovementRate(first, to: rate)
        return world
    }

    // MARK: - Platforms

    func testPlatformsAreTheTrackTilesBesideTheStationInNorthEastSouthWestOrder() throws {
        let station = GridPosition(x: 5, y: 5)
        let north = GridPosition(x: 5, y: 4)
        let east = GridPosition(x: 6, y: 5)
        let south = GridPosition(x: 5, y: 6)
        let west = GridPosition(x: 4, y: 5)
        // Straights running past the station: none has an exit toward it.
        let pieces: [(GridPosition, TrackConnections)] = [
            (west, [.north, .south]), (south, [.east, .west]), (east, [.north, .south]), (north, [.east, .west]),
            // Diagonal neighbours are not platforms.
            (GridPosition(x: 6, y: 6), [.north, .west]), (GridPosition(x: 4, y: 4), [.east, .south]),
        ]
        var forward = try makeWorld(balance: 1_000_000)
        let id = try forward.buildStation(named: "Hub", at: station).id
        for (tile, connections) in pieces {
            try forward.buildTrack(at: tile, connections: connections)
        }
        var backward = try makeWorld(balance: 1_000_000)
        for (tile, connections) in pieces.reversed() {
            try backward.buildTrack(at: tile, connections: connections)
        }
        try backward.buildStation(named: "Hub", at: station)

        XCTAssertEqual(forward.platforms(of: id), [north, east, south, west])
        XCTAssertEqual(backward.platforms(of: id), [north, east, south, west], "independent of build order")
    }

    func testPlatformsSkipEmptyTilesOtherStationsAndTheMapEdge() throws {
        var world = try makeWorld(width: 4, height: 3, balance: 1_000_000)
        // A corner station: north and west are off the map, east is another
        // station, south is empty.
        let corner = try world.buildStation(named: "Corner", at: GridPosition(x: 0, y: 0)).id
        let neighbour = try world.buildStation(named: "Neighbour", at: GridPosition(x: 1, y: 0)).id
        XCTAssertEqual(world.platforms(of: corner), [])
        XCTAssertEqual(world.platforms(of: neighbour), [])

        // Derived on every query: building and removing track shows at once.
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        try world.buildTrack(at: GridPosition(x: 2, y: 0), connections: .south)
        XCTAssertEqual(world.platforms(of: corner), [GridPosition(x: 0, y: 1)])
        XCTAssertEqual(world.platforms(of: neighbour), [GridPosition(x: 2, y: 0)])
        try world.removeTrack(at: GridPosition(x: 0, y: 1))
        XCTAssertEqual(world.platforms(of: corner), [])

        // The far corner, next to the map's east and south edges.
        let farCorner = try world.buildStation(named: "Far", at: GridPosition(x: 3, y: 2)).id
        XCTAssertEqual(world.platforms(of: farCorner), [])
        try world.buildTrack(at: GridPosition(x: 2, y: 2), connections: .north)
        XCTAssertEqual(world.platforms(of: farCorner), [GridPosition(x: 2, y: 2)])
    }

    func testAnUnknownStationHasNoPlatforms() throws {
        let world = try makeLineWorld()
        for raw in [0, -1, 4, 99, Int.min, Int.max] {
            XCTAssertEqual(world.platforms(of: StationID(rawValue: raw)), [], "station \(raw)")
        }
    }

    func testATrackTileBetweenTwoStationsIsAPlatformOfBoth() throws {
        let world = try makeLineWorld()

        XCTAssertEqual(world.platforms(of: central), [b])
        XCTAssertEqual(world.platforms(of: market), [d])
        XCTAssertEqual(world.platforms(of: hill), [d])
    }

    // MARK: - Routes to a station

    func testARouteToAStationEndsAtItsFirstPlatform() throws {
        let world = try makeLineWorld()
        let start = TrainPosition.atNode(a, heading: .east)

        XCTAssertEqual(world.route(from: start, toStation: central), [b])
        XCTAssertEqual(world.route(from: start, toStation: market), [b, c, d])
        XCTAssertEqual(world.route(from: start, toStation: hill), [b, c, d])
        XCTAssertEqual(world.route(from: .atNode(e, heading: .west), toStation: market), [d])
        // The same as routing to the platform itself.
        XCTAssertEqual(world.route(from: start, toStation: market), world.route(from: start, to: d))
        // Routing to the station's own tile is still no route (Stage L).
        XCTAssertNil(world.route(from: start, to: GridPosition(x: 4, y: 1)))
    }

    func testTiesBetweenPlatformsGoToNorthThenEastThenSouthThenWest() throws {
        // A ring of track round a station: every side's middle is a platform.
        //
        //   p - N - q
        //   |       |
        //   W   S   E
        //   |       |
        //   r - s - t      (S, the station, has platforms N, E, s and W)
        var world = try makeWorld(balance: 1_000_000)
        let p = GridPosition(x: 2, y: 2)
        let north = GridPosition(x: 3, y: 2)
        let q = GridPosition(x: 4, y: 2)
        let east = GridPosition(x: 4, y: 3)
        let t = GridPosition(x: 4, y: 4)
        let south = GridPosition(x: 3, y: 4)
        let r = GridPosition(x: 2, y: 4)
        let west = GridPosition(x: 2, y: 3)
        try world.buildTrack(at: p, connections: [.east, .south])
        try world.buildTrack(at: north, connections: [.east, .west])
        try world.buildTrack(at: q, connections: [.south, .west])
        try world.buildTrack(at: east, connections: [.north, .south])
        try world.buildTrack(at: t, connections: [.north, .west])
        try world.buildTrack(at: south, connections: [.east, .west])
        try world.buildTrack(at: r, connections: [.north, .east])
        try world.buildTrack(at: west, connections: [.north, .south])
        let station = try world.buildStation(named: "Loop", at: GridPosition(x: 3, y: 3)).id
        XCTAssertEqual(world.platforms(of: station), [north, east, south, west])

        // From p two platforms are one link away: east (N) comes before
        // south (W), unless it would turn straight back.
        XCTAssertEqual(world.route(from: .atNode(p, heading: .east), toStation: station), [north])
        XCTAssertEqual(world.route(from: .atNode(p, heading: .south), toStation: station), [north])
        XCTAssertEqual(world.route(from: .atNode(p, heading: .north), toStation: station), [north])
        XCTAssertEqual(world.route(from: .atNode(p, heading: .west), toStation: station), [west])
        // From t: north (E) before west (s), unless it would turn back.
        XCTAssertEqual(world.route(from: .atNode(t, heading: .north), toStation: station), [east])
        XCTAssertEqual(world.route(from: .atNode(t, heading: .west), toStation: station), [east])
        XCTAssertEqual(world.route(from: .atNode(t, heading: .east), toStation: station), [east])
        XCTAssertEqual(world.route(from: .atNode(t, heading: .south), toStation: station), [south])
        // Standing on a platform, or heading for one, the route is empty.
        for heading in TrackDirection.allCases {
            XCTAssertEqual(world.route(from: .atNode(north, heading: heading), toStation: station), [])
        }
        XCTAssertEqual(world.route(from: .onLink(from: p, to: west, offset: 1023), toStation: station), [])
        // Leaving a platform on a link, the next one is round the corner.
        XCTAssertEqual(world.route(from: .onLink(from: north, to: q, offset: 1), toStation: station), [east])
    }

    func testFewerLinksWinOverDirectionOrderBetweenPlatforms() throws {
        // From the junction j facing east, the north branch reaches the
        // station's east platform in six links, the south branch its west
        // platform in two. South wins although north comes first.
        //
        //        n1 - n2 - n3
        //        |          |
        //   w -  j          n4
        //        |          |
        //        s1         n5
        //        |          |
        //        s2    S    n6      (S at (6,7): platforms n6 east, s2 west)
        var world = try makeWorld(balance: 1_000_000)
        let w = GridPosition(x: 4, y: 5)
        let j = GridPosition(x: 5, y: 5)
        let s1 = GridPosition(x: 5, y: 6)
        let s2 = GridPosition(x: 5, y: 7)
        let n1 = GridPosition(x: 5, y: 4)
        let n2 = GridPosition(x: 6, y: 4)
        let n3 = GridPosition(x: 7, y: 4)
        let n4 = GridPosition(x: 7, y: 5)
        let n5 = GridPosition(x: 7, y: 6)
        let n6 = GridPosition(x: 7, y: 7)
        try world.buildTrack(at: w, connections: .east)
        try world.buildTrack(at: j, connections: [.north, .south, .west])
        try world.buildTrack(at: s1, connections: [.north, .south])
        try world.buildTrack(at: s2, connections: .north)
        try world.buildTrack(at: n1, connections: [.east, .south])
        try world.buildTrack(at: n2, connections: [.east, .west])
        try world.buildTrack(at: n3, connections: [.south, .west])
        try world.buildTrack(at: n4, connections: [.north, .south])
        try world.buildTrack(at: n5, connections: [.north, .south])
        try world.buildTrack(at: n6, connections: .north)
        let station = try world.buildStation(named: "Fork", at: GridPosition(x: 6, y: 7)).id
        XCTAssertEqual(world.platforms(of: station), [n6, s2])

        XCTAssertEqual(world.route(from: .atNode(j, heading: .east), toStation: station), [s1, s2])
        XCTAssertEqual(world.route(from: .atNode(j, heading: .west), toStation: station), [s1, s2])
        XCTAssertEqual(world.route(from: .atNode(j, heading: .south), toStation: station), [s1, s2])
        XCTAssertEqual(world.route(from: .onLink(from: w, to: j, offset: 10), toStation: station), [s1, s2])
        // Facing north, south would turn straight back: the long way round.
        XCTAssertEqual(world.route(from: .atNode(j, heading: .north), toStation: station), [n1, n2, n3, n4, n5, n6])
    }

    func testARouteToAStationStopsAtTheFirstPlatformItReaches() throws {
        // Two platforms of one station on one line: p1 north of the
        // station S, and p2 south of it, reached from x only round the bend.
        //
        //   a1 - p1 - x - y
        //        S        |
        //        p2 - v - u
        var world = try makeWorld(balance: 1_000_000)
        let a1 = GridPosition(x: 1, y: 1)
        let p1 = GridPosition(x: 2, y: 1)
        let x = GridPosition(x: 3, y: 1)
        let y = GridPosition(x: 4, y: 1)
        let y2 = GridPosition(x: 4, y: 2)
        let u = GridPosition(x: 4, y: 3)
        let v = GridPosition(x: 3, y: 3)
        let p2 = GridPosition(x: 2, y: 3)
        try world.buildTrack(at: a1, connections: .east)
        try world.buildTrack(at: p1, connections: [.east, .west])
        try world.buildTrack(at: x, connections: [.east, .west])
        try world.buildTrack(at: y, connections: [.south, .west])
        try world.buildTrack(at: y2, connections: [.north, .south])
        try world.buildTrack(at: u, connections: [.north, .west])
        try world.buildTrack(at: v, connections: [.east, .west])
        try world.buildTrack(at: p2, connections: .east)
        let station = try world.buildStation(named: "Twin", at: GridPosition(x: 2, y: 2)).id
        XCTAssertEqual(world.platforms(of: station), [p1, p2])

        XCTAssertEqual(world.route(from: .atNode(a1, heading: .east), toStation: station), [p1])
        // Beyond p1, p2 is the one ahead.
        XCTAssertEqual(world.route(from: .atNode(x, heading: .east), toStation: station), [y, y2, u, v, p2])
        // Facing back toward p1 from x.
        XCTAssertEqual(world.route(from: .atNode(x, heading: .west), toStation: station), [p1])
    }

    func testNoRouteToAStationWithoutAReachablePlatform() throws {
        var world = try makeLineWorld()
        let start = TrainPosition.atNode(a, heading: .east)

        // Unknown stations.
        for raw in [0, -1, 4, Int.min, Int.max] {
            XCTAssertNil(world.route(from: start, toStation: StationID(rawValue: raw)), "station \(raw)")
        }
        // A station with no track beside it.
        let field = try world.buildStation(named: "Field", at: GridPosition(x: 10, y: 10)).id
        XCTAssertNil(world.route(from: start, toStation: field))
        // A platform on isolated track.
        try world.buildTrack(at: GridPosition(x: 10, y: 11), connections: .north)
        XCTAssertEqual(world.platforms(of: field), [GridPosition(x: 10, y: 11)])
        XCTAssertNil(world.route(from: start, toStation: field))
        // Behind the train, past a dead end: only a reverse would do.
        XCTAssertNil(world.route(from: .atNode(c, heading: .east), toStation: central))
        XCTAssertNil(world.route(from: .onLink(from: b, to: c, offset: 512), toStation: central))
        XCTAssertNil(world.route(from: .atNode(a, heading: .west), toStation: central))
        XCTAssertEqual(world.route(from: .atNode(c, heading: .west), toStation: central), [b])

        // Invalid starts: the same check as placing a train.
        let invalidStarts: [TrainPosition] = [
            .atNode(GridPosition(x: 2, y: 1), heading: .south), // the station tile
            .atNode(GridPosition(x: 0, y: 0), heading: .east), // empty
            .atNode(GridPosition(x: -1, y: 2), heading: .east), // off the map
            .atNode(GridPosition(x: Int.max, y: Int.min), heading: .east),
            .onLink(from: a, to: b, offset: 0),
            .onLink(from: a, to: b, offset: TrainPosition.linkLength),
            .onLink(from: a, to: b, offset: -1),
            .onLink(from: a, to: c, offset: 1),
            .onLink(from: b, to: GridPosition(x: 2, y: 1), offset: 1),
            .onLink(from: GridPosition(x: Int.max, y: 0), to: GridPosition(x: Int.min, y: 0), offset: 1),
        ]
        for invalid in invalidStarts {
            XCTAssertNil(world.route(from: invalid, toStation: central), "\(invalid)")
            XCTAssertNil(world.route(from: invalid, toStation: market), "\(invalid)")
        }
    }

    func testStationRoutesAreAcceptedAndFollowedToAStop() throws {
        var world = try makeLineWorld(trainAt: .atNode(a, heading: .east), rate: 700)
        let route = try XCTUnwrap(world.route(from: .atNode(a, heading: .east), toStation: market))
        try world.setTrainContinuation(first, to: route)

        var ticks = 0
        while world.stationsStoppedAt(by: first).isEmpty {
            try world.advance(ticks: 1)
            ticks += 1
            XCTAssertLessThanOrEqual(ticks, 10, "the train never arrived")
            if ticks > 10 { return }
        }
        // 3 links of 1024 at 700 a minute: 5 minutes, 428 units dropped.
        XCTAssertEqual(ticks, 5)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(d, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill])
    }

    func testStationQueriesNeverChangeTheWorld() throws {
        var world = try makeLineWorld(trainAt: .onLink(from: a, to: b, offset: 300), rate: 50)
        try world.setTrainContinuation(first, to: [c, d])
        let before = world

        for raw in -1...5 {
            _ = world.platforms(of: StationID(rawValue: raw))
            _ = world.route(from: .atNode(a, heading: .east), toStation: StationID(rawValue: raw))
            _ = world.stationsStoppedAt(by: TrainID(rawValue: raw))
        }

        XCTAssertEqual(world, before)
    }

    // MARK: - Stopping

    func testATrainStandingOnAPlatformWithNoContinuationIsStopped() throws {
        var world = try makeLineWorld()
        try world.purchaseTrain(named: "Train 1")
        let second = try world.purchaseTrain(named: "Train 2").id
        let third = try world.purchaseTrain(named: "Train 3").id
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "unplaced")

        try world.placeTrain(first, at: .atNode(b, heading: .north))
        try world.placeTrain(second, at: .atNode(a, heading: .east))
        try world.placeTrain(third, at: .onLink(from: c, to: d, offset: 1023))

        XCTAssertEqual(world.stationsStoppedAt(by: first), [central], "placed on a platform, facing any way")
        XCTAssertEqual(world.stationsStoppedAt(by: second), [], "a is diagonal to Central, not beside it")
        XCTAssertEqual(world.stationsStoppedAt(by: third), [], "a train on a link is not at a platform")
        for raw in [0, -1, 4, 99, Int.min, Int.max] {
            XCTAssertEqual(world.stationsStoppedAt(by: TrainID(rawValue: raw)), [], "train \(raw)")
        }
    }

    func testPassingAPlatformIsNotAStop() throws {
        var world = try makeLineWorld(trainAt: .atNode(a, heading: .east), rate: TrainPosition.linkLength)
        try world.setTrainContinuation(first, to: [b, c, d, e])

        // Each minute ends exactly on the next node.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(b, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "passing Central")
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(d, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "passing Market and Hill")
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(e, heading: .east))
        XCTAssertEqual(world.train(id: first)?.movement.remainingContinuation.isEmpty, true)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "the journey ends at e, which is no platform")
    }

    func testArrivingExactlyOrWithDistanceToSpareStopsAtTheSamePlace() throws {
        for rate in [256, 1024, 1025, 3_072, 5_000, Int64.max] as [Int64] {
            var world = try makeLineWorld(trainAt: .atNode(a, heading: .east), rate: rate)
            try world.setTrainContinuation(first, to: [b, c, d])
            for _ in 0..<12 {
                try world.advance(ticks: 1)
            }

            XCTAssertEqual(world.train(id: first)?.position, .atNode(d, heading: .east), "rate \(rate)")
            XCTAssertEqual(world.train(id: first)?.movement.continuation, [], "rate \(rate)")
            XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill], "rate \(rate)")
        }
    }

    func testAStoppedTrainStaysStoppedAsTimePasses() throws {
        var world = try makeLineWorld(trainAt: .atNode(a, heading: .east), rate: 5_000)
        try world.setTrainContinuation(first, to: [b])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central])
        let stopped = world

        try world.advance(ticks: 1_000)
        world.setSpeed(.double)
        try world.advance(ticks: 7)

        XCTAssertEqual(world.trains, stopped.trains, "nothing moves a stopped train")
        XCTAssertEqual(world.clock.now.minutes, stopped.clock.now.minutes + 1_014)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central])
    }

    func testGivingAStoppedTrainSomewhereToGoEndsTheStopBeforeItMoves() throws {
        var world = try makeLineWorld(trainAt: .atNode(b, heading: .east), rate: 0)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central])

        try world.setTrainContinuation(first, to: [c, d])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "departing, although the rate is 0")
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(b, heading: .east), "held by rate 0")
        XCTAssertEqual(world.stationsStoppedAt(by: first), [])

        // Clearing the continuation again stops it where it stands.
        try world.setTrainContinuation(first, to: [])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central])

        try world.setTrainContinuation(first, to: [c])
        try world.setTrainMovementRate(first, to: 512)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .onLink(from: b, to: c, offset: 512))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "left the platform")
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(c, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "c is no platform")
    }

    func testReversingAtAPlatformKeepsOrMakesTheStop() throws {
        var world = try makeLineWorld(trainAt: .atNode(d, heading: .east), rate: 100)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill])

        try world.reverseTrain(first)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(d, heading: .west))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill], "turned round at the platform")

        // Reversing clears a continuation, so a departing train stops again.
        try world.setTrainContinuation(first, to: [c, b])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [])
        try world.reverseTrain(first)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill])
    }

    func testATrainOnALinkStopsWhenItReachesThePlatform() throws {
        var world = try makeLineWorld(trainAt: .onLink(from: a, to: b, offset: 100), rate: 400)
        XCTAssertEqual(world.route(from: .onLink(from: a, to: b, offset: 100), toStation: central), [])
        try world.setTrainContinuation(first, to: [])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "not yet at the platform")

        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: first)?.position, .onLink(from: a, to: b, offset: 900))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(b, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central])
    }

    func testWaitingAtAPlatformForRemovedTrackIsNotAStop() throws {
        var world = try makeLineWorld(trainAt: .atNode(a, heading: .east), rate: 1_024)
        try world.setTrainContinuation(first, to: [b, c, d])
        try world.removeTrack(at: c)

        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(b, heading: .east))
        XCTAssertEqual(Array(world.train(id: first)?.movement.remainingContinuation ?? []), [c, d])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [], "waiting to go on, not stopped")

        try world.buildTrack(at: c, connections: [.east, .west])
        try world.advance(ticks: 2)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill])
    }

    func testUnplacingEndsTheStopAndAStoppedTrainKeepsItsTrack() throws {
        var world = try makeLineWorld(trainAt: .atNode(b, heading: .west))
        XCTAssertThrowsGameError(try world.removeTrack(at: b), .trackInUse(b))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central])

        try world.unplaceTrain(first)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [])
        try world.removeTrack(at: b)
        XCTAssertEqual(world.platforms(of: central), [])
    }

    func testAStationBuiltBesideAStoppedTrainCountsAtOnce() throws {
        var world = try makeLineWorld(trainAt: .atNode(b, heading: .east))
        let annex = try world.buildStation(named: "Annex", at: GridPosition(x: 2, y: 3)).id

        XCTAssertEqual(world.platforms(of: annex), [b])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [central, annex])
    }

    func testStationsAreListedInAscendingIDOrder() throws {
        // Built south first, then north, east and west of a crossing: the
        // answer is by ID, not by direction.
        var world = try makeWorld(balance: 1_000_000)
        let x = GridPosition(x: 5, y: 5)
        try world.buildTrack(at: x, connections: [.north, .south])
        let south = try world.buildStation(named: "South", at: GridPosition(x: 5, y: 6)).id
        let north = try world.buildStation(named: "North", at: GridPosition(x: 5, y: 4)).id
        let east = try world.buildStation(named: "East", at: GridPosition(x: 6, y: 5)).id
        let west = try world.buildStation(named: "West", at: GridPosition(x: 4, y: 5)).id
        let train = try world.purchaseTrain(named: "Shuttle").id
        try world.placeTrain(train, at: .atNode(x, heading: .north))

        XCTAssertEqual(world.stationsStoppedAt(by: train), [south, north, east, west])
        XCTAssertEqual(world.stationsStoppedAt(by: train).map(\.rawValue), [1, 2, 3, 4])
    }

    func testStopsSurviveSaveAndLoadWithoutChangingTheSaveFormat() throws {
        var world = try makeLineWorld(trainAt: .atNode(a, heading: .east), rate: 1_024)
        try world.setTrainContinuation(first, to: [b, c, d])
        try world.advance(ticks: 3)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [market, hill])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        let decoded = try JSONDecoder().decode(GameWorld.self, from: data)

        XCTAssertEqual(decoded, world)
        XCTAssertEqual(decoded.stationsStoppedAt(by: first), [market, hill])
        XCTAssertEqual(decoded.platforms(of: market), [d])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        for word in ["platform", "stop", "Stop"] {
            XCTAssertFalse(json.contains(word), "nothing about stops is saved: \(word)")
        }
    }

    // MARK: - Generated networks

    /// On generated networks, for random starts and every station: the
    /// station route is the best of the routes to each platform (fewest
    /// links, then direction order), passes no platform before its end, is
    /// accepted as a continuation, and a train that follows it is stopped
    /// at the station, as the stop is defined.
    func testStationRoutesAreTheBestRouteToAnyPlatformAndEndInAStop() throws {
        var checked = 0
        var found = 0
        var driven = 0
        var digest = Digest()
        runCampaign("stationStop.routes", cases: 40) { testCase in
            let shape = testCase.random.element(of: NetworkShape.allCases)
            var generated = NetworkGenerator.specs(shape, using: &testCase.random)
            // Stations beside the network, on empty tiles of the map.
            let occupied = Set(generated.specs.map(\.position))
            for y in 0..<generated.height {
                for x in 0..<generated.width where !occupied.contains(GridPosition(x: x, y: y)) && testCase.random.chance(1, in: 3) {
                    generated.specs.append(TileSpec(position: GridPosition(x: x, y: y), kind: .station))
                }
            }
            testCase.note("shape \(shape), \(generated.width) x \(generated.height)")
            guard let world = try? NetworkGenerator.build(generated.specs, width: generated.width, height: generated.height) else {
                testCase.fail("the network did not build")
                return
            }
            for _ in 0..<6 {
                guard let start = PositionGenerator.validPosition(in: world, using: &testCase.random) else { return }
                for station in world.stations {
                    checked += 1
                    let platforms = world.platforms(of: station.id)
                    let route = world.route(from: start, toStation: station.id)
                    digest.add("\(start) \(station.id.rawValue) \(String(describing: route))")
                    let expected = Self.bestRoute(in: world, from: start, to: platforms)
                    testCase.expect(route == expected, "route from \(start) to \(station.name): \(String(describing: route)), expected \(String(describing: expected))")
                    guard let route else { continue }
                    found += 1
                    // Empty exactly when the node ahead is a platform; otherwise
                    // no platform before the last node.
                    let passed = [ahead(of: start).node] + route.dropLast()
                    if route.isEmpty {
                        testCase.expect(platforms.contains(ahead(of: start).node), "empty route from \(start) to \(station.name), not at a platform")
                    } else {
                        testCase.expect(!passed.contains(where: platforms.contains), "the route from \(start) to \(station.name) passes a platform: \(route)")
                    }

                    // Follow it with a fresh train until it is stopped.
                    var driving = world
                    guard let train = try? driving.purchaseTrain(named: "Probe").id else { continue }
                    do {
                        try driving.placeTrain(train, at: start)
                        try driving.setTrainContinuation(train, to: route)
                        try driving.setTrainMovementRate(train, to: 1 + Int64(testCase.random.below(2_048)))
                        driving.setSpeed(.normal)
                        try driving.advance(ticks: 2 * (route.count + 1) * Int(TrainPosition.linkLength))
                    } catch {
                        testCase.fail("following the route from \(start) to \(station.name) failed: \(error)")
                        continue
                    }
                    driven += 1
                    let stops = driving.stationsStoppedAt(by: train)
                    testCase.expect(stops.contains(station.id), "the train from \(start) is not stopped at \(station.name): \(stops)")
                    testCase.expect(stops == Self.stops(in: driving, of: train), "stops \(stops) disagree with the definition")
                }
            }
        }
        print("[digest] stationStop.routes \(digest.hex) (\(checked) checked, \(found) found, \(driven) driven)")
        assertVolume(checked > 1_000, "only \(checked) station routes checked")
        assertVolume(found > 200, "only \(found) station routes found")
        assertVolume(driven == found, "\(found - driven) found routes were not driven")
    }

    /// The best of `route(from:to:)` over `platforms`: fewest links, then
    /// the first sequence of exit directions in north, east, south, west
    /// order.
    private static func bestRoute(in world: GameWorld, from start: TrainPosition, to platforms: [GridPosition]) -> [GridPosition]? {
        let order = TrackDirection.allCases
        func key(_ route: [GridPosition]) -> [Int] {
            var node = ahead(of: start).node
            return route.map { next in
                defer { node = next }
                return order.firstIndex(of: stepDirection(from: node, to: next)!)!
            }
        }
        return platforms
            .compactMap { world.route(from: start, to: $0) }
            .min { lhs, rhs in
                lhs.count != rhs.count ? lhs.count < rhs.count : key(lhs).lexicographicallyPrecedes(key(rhs))
            }
    }

    /// The stop, written again from its definition: at a node with no
    /// continuation left, every station whose tile is next to that node, by
    /// ID.
    private static func stops(in world: GameWorld, of id: TrainID) -> [StationID] {
        guard let train = world.train(id: id), case .atNode(let tile, _)? = train.position,
              train.movement.cursor >= train.movement.continuation.count
        else { return [] }
        return world.stations
            .filter { stepDirection(from: tile, to: $0.position) != nil }
            .map(\.id)
    }
}
