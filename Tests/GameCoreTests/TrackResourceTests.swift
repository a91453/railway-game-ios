import Foundation
import GameCore
import XCTest

/// Turnouts, crossings and track resources (Phase 4.5 Stage S1,
/// ARCHITECTURE decision 26): which way a train may go on through each
/// piece, what trains occupy, the sections between branch points, and how
/// many separate tracks join two stations.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class TrackResourceTests: XCTestCase {
    //             (4,0)
    //               |
    //             (4,1)
    //               |
    //   o - o - T - o - X - o - o      row 2: T turnout at (2,2), stem west,
    //           |       |                     X crossing at (4,2)
    //         (2,3)   (4,3)
    //           |       |
    //         (2,4)   (4,4)
    //
    // Every end is a dead end. West(0,1) has platform (0,2); East(6,1) has
    // platform (6,2).
    private let turnout = GridPosition(x: 2, y: 2)
    private let crossing = GridPosition(x: 4, y: 2)

    private func p(_ x: Int, _ y: Int) -> GridPosition {
        GridPosition(x: x, y: y)
    }

    private func makeJunctionWorld() throws -> GameWorld {
        var world = try GameWorld(width: 7, height: 5, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildTrack(at: p(0, 2), connections: .east)
        try world.buildTrack(at: p(1, 2), connections: [.east, .west])
        try world.buildTurnout(at: turnout, connections: [.east, .south, .west], stem: .west)
        try world.buildTrack(at: p(3, 2), connections: [.east, .west])
        try world.buildCrossing(at: crossing)
        try world.buildTrack(at: p(5, 2), connections: [.east, .west])
        try world.buildTrack(at: p(6, 2), connections: .west)
        try world.buildTrack(at: p(4, 0), connections: .south)
        try world.buildTrack(at: p(4, 1), connections: [.north, .south])
        try world.buildTrack(at: p(4, 3), connections: [.north, .south])
        try world.buildTrack(at: p(4, 4), connections: .north)
        try world.buildTrack(at: p(2, 3), connections: [.north, .south])
        try world.buildTrack(at: p(2, 4), connections: .north)
        try world.buildStation(named: "West", at: p(0, 1))
        try world.buildStation(named: "East", at: p(6, 1))
        return world
    }

    // MARK: - Building

    /// A turnout needs three exits or more, only the four directions, and
    /// its stem among them, checked before the tile and the money; a
    /// crossing always has all four. Both cost what track costs, and both
    /// are removed like track.
    func testBuildingTurnoutsAndCrossings() throws {
        var world = try GameWorld(width: 4, height: 4, economy: GameEconomy(balance: 350, costs: testCosts))
        try world.buildTrack(at: p(0, 0), connections: .east)
        let before = world
        XCTAssertThrowsGameError(try world.buildTurnout(at: p(9, 9), connections: [.east, .west], stem: .west), .invalidTrackConnections)
        XCTAssertThrowsGameError(try world.buildTurnout(at: p(1, 1), connections: [.east, .south, .west], stem: .north), .invalidTrackConnections)
        XCTAssertThrowsGameError(
            try world.buildTurnout(at: p(1, 1), connections: TrackConnections(rawValue: 0b1_0111), stem: .north), .invalidTrackConnections
        )
        XCTAssertThrowsGameError(try world.buildTurnout(at: p(9, 9), connections: [.east, .south, .west], stem: .west), .outOfBounds(p(9, 9)))
        XCTAssertThrowsGameError(try world.buildTurnout(at: p(0, 0), connections: [.east, .south, .west], stem: .west), .tileOccupied(p(0, 0)))
        XCTAssertThrowsGameError(try world.buildCrossing(at: p(0, 0)), .tileOccupied(p(0, 0)))
        XCTAssertThrowsGameError(try world.buildCrossing(at: p(-1, 0)), .outOfBounds(p(-1, 0)))
        XCTAssertEqual(world, before)

        let built = try world.buildTurnout(at: p(1, 1), connections: [.north, .east, .south, .west], stem: .north)
        XCTAssertEqual(built, Track(position: p(1, 1), connections: [.north, .east, .south, .west], layout: .turnout(stem: .north)))
        XCTAssertEqual(world.track(at: p(1, 1)), built, "a three-way turnout")
        XCTAssertEqual(world.map.tile(at: p(1, 1))?.type, .turnout(connections: [.north, .east, .south, .west], stem: .north))
        let cross = try world.buildCrossing(at: p(2, 2))
        XCTAssertEqual(cross, Track(position: p(2, 2), connections: [.north, .east, .south, .west], layout: .crossing))
        XCTAssertEqual(world.economy.balance, 350 - 300, "each costs what track costs")
        XCTAssertEqual(world.tracks.map(\.layout), [.open, .turnout(stem: .north), .crossing])

        XCTAssertThrowsGameError(try world.buildCrossing(at: p(3, 3)), .insufficientFunds(required: 100, available: 50))

        try world.removeTrack(at: p(1, 1))
        try world.removeTrack(at: p(2, 2))
        XCTAssertNil(world.track(at: p(1, 1)))
        XCTAssertEqual(world.map.tile(at: p(2, 2))?.type, .empty)
    }

    // MARK: - Turning

    /// Through a turnout a train goes from the stem to any branch and from
    /// a branch only to the stem; through a crossing only straight on. A
    /// train that did not come in by an exit may leave by any but the one
    /// behind it.
    func testTrainsPassTurnoutsAndCrossingsOnlyTheWaysTheyJoin() throws {
        let world = try makeJunctionWorld()
        XCTAssertEqual(world.exits(from: turnout, facing: .east), [p(3, 2), p(2, 3)], "from the stem to both branches")
        XCTAssertEqual(world.exits(from: turnout, facing: .west), [p(1, 2)], "from the east branch to the stem only")
        XCTAssertEqual(world.exits(from: turnout, facing: .north), [p(1, 2)], "from the south branch to the stem only")
        XCTAssertEqual(world.exits(from: turnout, facing: .south), [p(3, 2), p(2, 3), p(1, 2)], "not come in by an exit")
        XCTAssertEqual(world.exits(from: crossing, facing: .east), [p(5, 2)])
        XCTAssertEqual(world.exits(from: crossing, facing: .south), [p(4, 3)])
        XCTAssertEqual(world.exits(from: p(3, 2), facing: .east), [p(4, 2)], "a plain piece: all but back")
        XCTAssertEqual(world.exits(from: p(9, 9), facing: .east), [])

        // Routes follow the same rules.
        XCTAssertEqual(world.route(from: .atNode(p(1, 2), heading: .east), to: p(2, 4)), [turnout, p(2, 3), p(2, 4)])
        XCTAssertNil(world.route(from: .atNode(p(3, 2), heading: .west), to: p(2, 4)), "branch to branch")
        XCTAssertNil(world.route(from: .atNode(p(3, 2), heading: .east), to: p(4, 4)), "no turning at a crossing")
        XCTAssertEqual(world.route(from: .atNode(p(4, 1), heading: .south), to: p(4, 4)), [crossing, p(4, 3), p(4, 4)])
        XCTAssertEqual(world.route(from: .atNode(p(1, 2), heading: .east), to: p(6, 2)), [turnout, p(3, 2), crossing, p(5, 2), p(6, 2)])

        // So do continuations.
        var moving = world
        let train = try moving.purchaseTrain(named: "T").id
        try moving.placeTrain(train, at: .atNode(p(3, 2), heading: .west))
        XCTAssertThrowsGameError(try moving.setTrainContinuation(train, to: [turnout, p(2, 3)]), .invalidContinuation)
        try moving.setTrainContinuation(train, to: [turnout, p(1, 2)])
    }

    /// A path set through a plain junction that becomes a turnout: the
    /// train goes as far as the turnout and waits there, as it would for
    /// missing track.
    func testATrainWaitsAtATurnoutItCannotPass() throws {
        var world = try GameWorld(
            width: 5, height: 3, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal)
        )
        try world.buildTrack(at: p(0, 1), connections: .east)
        try world.buildTrack(at: p(1, 1), connections: [.east, .south, .west])
        try world.buildTrack(at: p(2, 1), connections: [.east, .west])
        try world.buildTrack(at: p(3, 1), connections: .west)
        try world.buildTrack(at: p(1, 2), connections: .north)
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: .atNode(p(3, 1), heading: .west))
        try world.setTrainMovementRate(train, to: 1024)
        try world.setTrainContinuation(train, to: [p(2, 1), p(1, 1), p(1, 2)])
        try world.removeTrack(at: p(1, 1))
        try world.buildTurnout(at: p(1, 1), connections: [.east, .south, .west], stem: .west)
        try world.advance(ticks: 5)
        XCTAssertEqual(world.train(id: train)?.position, .atNode(p(1, 1), heading: .west))
        XCTAssertEqual(world.train(id: train)?.movement.cursor, 2, "the branch is not entered")
    }

    // MARK: - Resources

    /// A train occupies the tile it stands on or the link it is on; two
    /// trains on one resource conflict, however they face.
    func testTrainsOccupyTheirTileOrLink() throws {
        var world = try makeJunctionWorld()
        for name in ["A", "B", "C", "D"] {
            try world.purchaseTrain(named: name)
        }
        let (a, b, c, d) = (TrainID(rawValue: 1), TrainID(rawValue: 2), TrainID(rawValue: 3), TrainID(rawValue: 4))
        try world.placeTrain(a, at: .atNode(crossing, heading: .east))
        try world.placeTrain(b, at: .atNode(crossing, heading: .north))
        try world.placeTrain(c, at: .onLink(from: p(3, 2), to: crossing, offset: 512))
        try world.placeTrain(d, at: .onLink(from: crossing, to: p(3, 2), offset: 100))

        XCTAssertEqual(world.occupiedResources(of: a), [.tile(crossing)])
        XCTAssertEqual(world.occupiedResources(of: c), [.edge(.link(p(3, 2), crossing))])
        XCTAssertEqual(world.occupiedResources(of: d), [.edge(.link(p(3, 2), crossing))], "a link is the same either way")
        XCTAssertEqual(world.occupiedResources(of: TrainID(rawValue: 9)), [])
        XCTAssertEqual(world.occupancyConflicts(), [
            TrackConflict(resource: .tile(crossing), trains: [a, b]),
            TrackConflict(resource: .edge(.link(p(3, 2), crossing)), trains: [c, d]),
        ])
        XCTAssertEqual(TrackResource.link(between: crossing, and: p(3, 2)), .edge(.link(p(3, 2), crossing)))
        XCTAssertLessThan(TrackResource.tile(p(6, 0)), .tile(p(0, 1)), "row-major")
        XCTAssertLessThan(TrackResource.tile(p(6, 6)), .edge(.link(p(0, 0), p(1, 0))), "nodes before links")

        try world.unplaceTrain(b)
        try world.unplaceTrain(d)
        XCTAssertEqual(world.occupancyConflicts(), [])
    }

    /// Sections run between branch points (dead ends, the turnout and the
    /// crossing here), each once, from the end first in row-major order.
    func testSectionsRunBetweenBranchPoints() throws {
        let world = try makeJunctionWorld()
        XCTAssertEqual(world.trackSections(), [
            TrackSection(nodes: [p(4, 0), p(4, 1), crossing], isLoop: false),
            TrackSection(nodes: [p(0, 2), p(1, 2), turnout], isLoop: false),
            TrackSection(nodes: [turnout, p(3, 2), crossing], isLoop: false),
            TrackSection(nodes: [turnout, p(2, 3), p(2, 4)], isLoop: false),
            TrackSection(nodes: [crossing, p(5, 2), p(6, 2)], isLoop: false),
            TrackSection(nodes: [crossing, p(4, 3), p(4, 4)], isLoop: false),
        ])
        XCTAssertEqual(world.trackSections()[2].links, [.edge(.link(turnout, p(3, 2))), .edge(.link(p(3, 2), crossing))])

        var lone = try GameWorld(width: 2, height: 1, economy: GameEconomy(balance: 1_000, costs: testCosts))
        try lone.buildTrack(at: p(0, 0), connections: .north)
        XCTAssertEqual(lone.trackSections(), [TrackSection(nodes: [p(0, 0)], isLoop: false)])
    }

    //   A(1,0)          B(5,0)
    //     |               |
    //   (1,1) - o - o - o - (5,1)
    //     |                   |
    //   (1,2) - o - o - o - (5,2)
    private func makeLoopWorld() throws -> GameWorld {
        var world = try GameWorld(width: 7, height: 3, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildTrack(at: p(1, 1), connections: [.east, .south])
        try world.buildTrack(at: p(5, 1), connections: [.south, .west])
        try world.buildTrack(at: p(1, 2), connections: [.north, .east])
        try world.buildTrack(at: p(5, 2), connections: [.north, .west])
        for x in 2...4 {
            try world.buildTrack(at: p(x, 1), connections: [.east, .west])
            try world.buildTrack(at: p(x, 2), connections: [.east, .west])
        }
        try world.buildStation(named: "A", at: p(1, 0))
        try world.buildStation(named: "B", at: p(5, 0))
        return world
    }

    /// A ring of plain pieces is one section, from its first tile in
    /// row-major order, the first way north, east, south, west.
    func testARingIsOneSection() throws {
        let world = try makeLoopWorld()
        XCTAssertEqual(world.trackSections(), [
            TrackSection(nodes: [p(1, 1), p(2, 1), p(3, 1), p(4, 1), p(5, 1), p(5, 2), p(4, 2), p(3, 2), p(2, 2), p(1, 2)], isLoop: true),
        ])
        XCTAssertEqual(world.trackSections()[0].links.count, 10)
    }

    /// Two tracks that share no link between the stations are double
    /// track; cutting one leaves single track.
    func testParallelTracksCountTracksThatShareNoLink() throws {
        var world = try makeLoopWorld()
        let (a, b) = (StationID(rawValue: 1), StationID(rawValue: 2))
        XCTAssertEqual(world.parallelTracks(between: a, and: b), 2)
        XCTAssertEqual(world.parallelTracks(between: b, and: a), 2)
        XCTAssertEqual(world.parallelTracks(between: a, and: a), 0, "a shared platform is not track between them")
        XCTAssertEqual(world.parallelTracks(between: a, and: StationID(rawValue: 9)), 0)
        try world.createLine(named: "Shuttle", stops: [a, b])
        XCTAssertEqual(world.lineTrackCounts(LineID(rawValue: 1)), [2])
        XCTAssertNil(world.lineTrackCounts(LineID(rawValue: 9)))

        try world.removeTrack(at: p(3, 2))
        XCTAssertEqual(world.parallelTracks(between: a, and: b), 1)
        XCTAssertEqual(try makeJunctionWorld().parallelTracks(between: StationID(rawValue: 1), and: StationID(rawValue: 2)), 1)
    }

    // MARK: - Saving

    /// Turnouts and crossings save in the map and load back equal; a
    /// turnout that breaks the rules is refused.
    func testTurnoutsAndCrossingsSaveAndBadOnesAreRefused() throws {
        let world = try makeJunctionWorld()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let text = String(decoding: data, as: UTF8.self)
        let turnoutJSON = #"{"turnout":{"connections":14,"stem":{"west":{}}}}"#
        XCTAssertTrue(text.contains(turnoutJSON), text)
        XCTAssertTrue(text.contains(#"{"crossing":{}}"#))
        for bad in [#"{"turnout":{"connections":10,"stem":{"west":{}}}}"#, #"{"turnout":{"connections":14,"stem":{"north":{}}}}"#] {
            let mutated = Data(text.replacingOccurrences(of: turnoutJSON, with: bad).utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: mutated), bad)
        }
    }
}
