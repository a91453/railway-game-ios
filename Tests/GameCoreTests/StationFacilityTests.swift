import Foundation
import GameCore
import XCTest

/// Station facilities and train length (Phase 4.5 Stage S2, ARCHITECTURE
/// decision 27): stations that grow onto more tiles, their platforms and
/// platform tracks, trains of several cars with a body behind the head,
/// how the body follows the head and turns round with it, routes that pull
/// a long train along the platforms, and saves.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class StationFacilityTests: XCTestCase {
    //   row 0:  .  West .   .  A   A   A   .   .   .      A = Central, grown east
    //   row 1:  o - o - o - o - o - o - o - o - o - o     dead ends at (0,1), (9,1)
    //
    // Central (4,0) grows onto (5,0) and (6,0); its platforms are (4,1),
    // (5,1), (6,1). West (1,0) has platform (1,1).
    private func p(_ x: Int, _ y: Int) -> GridPosition {
        GridPosition(x: x, y: y)
    }

    private func makeLineWorld(balance: Money = 1_000_000) throws -> (world: GameWorld, central: StationID, west: StationID) {
        var world = try GameWorld(width: 10, height: 3, economy: GameEconomy(balance: balance, costs: testCosts), clock: GameClock(speed: .normal))
        try world.buildTrack(at: p(0, 1), connections: .east)
        for x in 1...8 {
            try world.buildTrack(at: p(x, 1), connections: [.east, .west])
        }
        try world.buildTrack(at: p(9, 1), connections: .west)
        let central = try world.buildStation(named: "Central", at: p(4, 0)).id
        let west = try world.buildStation(named: "West", at: p(1, 0)).id
        return (world, central, west)
    }

    private func train(_ world: GameWorld, _ id: TrainID) throws -> Train {
        try XCTUnwrap(world.train(id: id))
    }

    // MARK: - Stations

    /// A station grows onto an empty tile beside one of its tiles, checked
    /// in the order station, tile, beside, money; it costs a station, and
    /// the track beside the new tile becomes its platforms too.
    func testAStationGrowsOntoAnEmptyTileBesideIt() throws {
        var (world, central, _) = try makeLineWorld()
        let before = world

        XCTAssertThrowsGameError(try world.extendStation(StationID(rawValue: 9), to: p(5, 0)), .unknownStation(StationID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.extendStation(central, to: p(10, 0)), .outOfBounds(p(10, 0)))
        XCTAssertThrowsGameError(try world.extendStation(central, to: p(4, 1)), .tileOccupied(p(4, 1)))
        XCTAssertThrowsGameError(try world.extendStation(central, to: p(6, 0)), .invalidStationTile(p(6, 0)))
        XCTAssertEqual(world, before)

        try world.extendStation(central, to: p(5, 0))
        try world.extendStation(central, to: p(6, 0))

        let station = try XCTUnwrap(world.station(id: central))
        XCTAssertEqual(station.annexes, [p(5, 0), p(6, 0)])
        XCTAssertEqual(station.tiles, [p(4, 0), p(5, 0), p(6, 0)])
        XCTAssertEqual(world.map.tile(at: p(6, 0))?.type, .station(id: central))
        XCTAssertEqual(world.economy.balance, before.economy.balance - testCosts.station - testCosts.station)
        XCTAssertEqual(world.platforms(of: central), [p(4, 1), p(5, 1), p(6, 1)])
        XCTAssertEqual(world.platformTracks(of: central), [[p(4, 1), p(5, 1), p(6, 1)]])
    }

    /// Money is checked last.
    func testGrowingAStationNeedsTheMoney() throws {
        // Ten tracks and two stations leave 999.
        var (world, central, _) = try makeLineWorld(balance: 3_999)
        let before = world

        XCTAssertThrowsGameError(try world.extendStation(central, to: p(5, 0)), .insufficientFunds(required: 1_000, available: 999))
        XCTAssertEqual(world, before)
    }

    /// Track on two sides of a station makes two platform tracks: groups of
    /// platforms joined by track, each in platform order.
    func testPlatformTracksAreThePlatformsJoinedByTrack() throws {
        var world = try GameWorld(width: 7, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        for x in 2...5 {
            try world.buildTrack(at: p(x, 1), connections: [.east, .west])
        }
        try world.buildTrack(at: p(3, 3), connections: .east)
        try world.buildTrack(at: p(4, 3), connections: .west)
        let station = try world.buildStation(named: "Twin", at: p(3, 2)).id
        try world.extendStation(station, to: p(4, 2))

        // (3,2): north (3,1), south (3,3); (4,2): north (4,1), south (4,3).
        XCTAssertEqual(world.platforms(of: station), [p(3, 1), p(3, 3), p(4, 1), p(4, 3)])
        XCTAssertEqual(world.platformTracks(of: station), [[p(3, 1), p(4, 1)], [p(3, 3), p(4, 3)]])
        XCTAssertEqual(world.platformTracks(of: StationID(rawValue: 9)), [])
    }

    // MARK: - Cars

    /// A new train has one car; cars are set off the track, 1 to 16, one
    /// to a tile, checked in the order train, count, off the track.
    func testCarsAreSetOffTheTrack() throws {
        var (world, _, _) = try makeLineWorld()
        let id = try world.purchaseTrain(named: "T").id
        XCTAssertEqual(try train(world, id).cars, 1)
        XCTAssertEqual(try train(world, id).length, 0)
        XCTAssertEqual(try train(world, id).tileCount, 1)

        XCTAssertThrowsGameError(try world.setTrainCars(TrainID(rawValue: 9), to: 17), .unknownTrain(TrainID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 0), .invalidTrainLength)
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 17), .invalidTrainLength)

        try world.setTrainCars(id, to: 16)
        XCTAssertEqual(try train(world, id).length, 15 * 1_024)
        XCTAssertEqual(try train(world, id).tileCount, 16)
        try world.setTrainCars(id, to: 3)
        XCTAssertEqual(try train(world, id).length, 2_048)
        XCTAssertEqual(try train(world, id).tileCount, 3)

        try world.placeTrain(id, at: .atNode(p(5, 1), heading: .east))
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 17), .invalidTrainLength)
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 2), .trainAlreadyPlaced(id))
        XCTAssertEqual(try train(world, id).cars, 3)

        // Taken off the track, it keeps its cars and loses its body.
        try world.unplaceTrain(id)
        XCTAssertEqual(try train(world, id).cars, 3)
        XCTAssertEqual(try train(world, id).trail, [])
    }

    /// A train of several cars is placed with its body behind its head:
    /// at a node from the tile behind it, on a link from the link's far
    /// end, then back along the track; not where the track behind ends
    /// first. Track under the body cannot be removed.
    func testALongTrainIsPlacedWithItsBodyBehindIt() throws {
        var (world, _, _) = try makeLineWorld()
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 3)

        XCTAssertThrowsGameError(try world.placeTrain(id, at: .atNode(p(1, 1), heading: .east)), .invalidTrainPosition)
        XCTAssertThrowsGameError(try world.placeTrain(id, at: .atNode(p(5, 1), heading: .north)), .invalidTrainPosition)

        try world.placeTrain(id, at: .atNode(p(2, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(1, 1), p(0, 1)])
        XCTAssertEqual(world.occupiedResources(of: id), [
            .tile(p(0, 1)), .tile(p(1, 1)), .tile(p(2, 1)), .wholeLink(.link(p(0, 1), p(1, 1))), .wholeLink(.link(p(1, 1), p(2, 1))),
        ])
        XCTAssertThrowsGameError(try world.removeTrack(at: p(0, 1)), .trackInUse(p(0, 1)))

        // On a link, 256 from (3,1): (3,1) at 256, (2,1) at 1280, (1,1)
        // at 2304, the first at or beyond the tail at 2048.
        try world.unplaceTrain(id)
        try world.placeTrain(id, at: .onLink(from: p(3, 1), to: p(4, 1), offset: 256))
        XCTAssertEqual(try train(world, id).trail, [p(3, 1), p(2, 1), p(1, 1)])
        XCTAssertEqual(world.occupiedResources(of: id), [
            .tile(p(2, 1)), .tile(p(3, 1)), .wholeLink(.link(p(1, 1), p(2, 1))), .wholeLink(.link(p(2, 1), p(3, 1))), .wholeLink(.link(p(3, 1), p(4, 1))),
        ])
        // (0,1) is free again; (1,1) is under the tail's link.
        try world.removeTrack(at: p(0, 1))
        XCTAssertThrowsGameError(try world.removeTrack(at: p(1, 1)), .trackInUse(p(1, 1)))
    }

    /// The body follows the head over the nodes it passed.
    func testTheBodyFollowsTheHead() throws {
        var (world, _, _) = try makeLineWorld()
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .atNode(p(2, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(1, 1)])
        try world.setTrainContinuation(id, to: [p(3, 1), p(4, 1)])
        try world.setTrainMovementRate(id, to: 512)

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).position, .onLink(from: p(2, 1), to: p(3, 1), offset: 512))
        XCTAssertEqual(try train(world, id).trail, [p(2, 1), p(1, 1)])

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(world, id).position, .atNode(p(3, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(2, 1)])

        try world.advance(ticks: 2)
        XCTAssertEqual(try train(world, id).position, .atNode(p(4, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(3, 1)])
    }

    /// Turning round puts the head where the tail was, facing away from
    /// where the head was, the body lying back toward it; turning round
    /// again undoes it. From a node the train is at a node again.
    func testTurningRoundPutsTheHeadWhereTheTailWas() throws {
        var (world, _, _) = try makeLineWorld()
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 3)
        try world.placeTrain(id, at: .atNode(p(5, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(4, 1), p(3, 1)])

        try world.reverseTrain(id)
        XCTAssertEqual(try train(world, id).position, .atNode(p(3, 1), heading: .west))
        XCTAssertEqual(try train(world, id).trail, [p(4, 1), p(5, 1)])

        try world.reverseTrain(id)
        XCTAssertEqual(try train(world, id).position, .atNode(p(5, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(4, 1), p(3, 1)])

        // On a link, 256 from (5,1) toward (6,1): the tail is 2048 back,
        // 256 short of (3,1) coming from (4,1); turned, the head is there.
        try world.unplaceTrain(id)
        try world.placeTrain(id, at: .onLink(from: p(5, 1), to: p(6, 1), offset: 256))
        XCTAssertEqual(try train(world, id).trail, [p(5, 1), p(4, 1), p(3, 1)])
        try world.reverseTrain(id)
        XCTAssertEqual(try train(world, id).position, .onLink(from: p(4, 1), to: p(3, 1), offset: 768))
        XCTAssertEqual(try train(world, id).trail, [p(4, 1), p(5, 1), p(6, 1)])
        try world.reverseTrain(id)
        XCTAssertEqual(try train(world, id).position, .onLink(from: p(5, 1), to: p(6, 1), offset: 256))
        XCTAssertEqual(try train(world, id).trail, [p(5, 1), p(4, 1), p(3, 1)])
    }

    // MARK: - Stops

    /// A long train's route to a station runs on along its platforms, a
    /// tile per car after the first, as far as they go; stopped there with
    /// its whole length, it turns round with its head at a platform.
    func testALongTrainIsPulledAlongThePlatforms() throws {
        var (world, central, west) = try makeLineWorld()
        try world.extendStation(central, to: p(5, 0))
        try world.extendStation(central, to: p(6, 0))
        let start = TrainPosition.atNode(p(2, 1), heading: .east)

        XCTAssertEqual(world.route(from: start, toStation: central), [p(3, 1), p(4, 1)])
        XCTAssertEqual(world.route(from: start, toStation: central, length: 1_024), [p(3, 1), p(4, 1), p(5, 1)])
        XCTAssertEqual(world.route(from: start, toStation: central, length: 2_048), [p(3, 1), p(4, 1), p(5, 1), p(6, 1)])
        // The platforms end at (6,1).
        XCTAssertEqual(world.route(from: start, toStation: central, length: 15 * 1_024), [p(3, 1), p(4, 1), p(5, 1), p(6, 1)])
        // Already at West's only platform: nothing to pull along.
        XCTAssertEqual(world.route(from: .atNode(p(1, 1), heading: .west), toStation: west, length: 2_048), [])

        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 3)
        try world.placeTrain(id, at: start)
        try world.setTrainContinuation(id, to: [p(3, 1), p(4, 1)])
        try world.setTrainMovementRate(id, to: 1_024)
        try world.advance(ticks: 2)
        // Head at the first platform, body on plain track.
        XCTAssertEqual(world.stationsStoppedAt(by: id), [central])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [])

        try world.setTrainContinuation(id, to: [p(5, 1), p(6, 1)])
        try world.advance(ticks: 2)
        XCTAssertEqual(try train(world, id).trail, [p(5, 1), p(4, 1)])
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [central])

        try world.reverseTrain(id)
        XCTAssertEqual(try train(world, id).position, .atNode(p(4, 1), heading: .west))
        XCTAssertEqual(world.stationsBesideWholeTrain(id), [central])
    }

    /// A line sends a long train out pulled along each station's platforms
    /// and brings it back; its trip's times count every link it runs.
    func testALineRunsALongTrain() throws {
        var (world, central, west) = try makeLineWorld()
        try world.extendStation(central, to: p(5, 0))
        let line = try world.createLine(named: "L", stops: [west, central]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 2)
        // At West's platform facing east, its body at (0,1).
        try world.placeTrain(id, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainMovementRate(id, to: 1_024)
        try world.assignTrain(id, to: line)

        try world.advance(ticks: 1)
        // Out: (2,1), (3,1), (4,1) to the first platform, one more for the
        // second car: 4 minutes. Turned at Central's (5,1), its head goes
        // to (4,1): back to West's (1,1) is 3. Two minutes at each end. In
        // seconds from leaving West, 42 s after it is sent out (Stage W2b).
        let departure = try train(world, id).timetable[0].departure.seconds
        XCTAssertEqual(
            try train(world, id).timetable.map { [$0.arrival.seconds - departure, $0.departure.seconds - departure] },
            [[-42, 0], [240, 360], [540, 540]]
        )
        XCTAssertEqual(try train(world, id).timetable.map(\.reverses), [false, true, true])

        try world.advance(ticks: 10)
        // Back at West at 9:42 and, its dwell over at 10:24, turned round
        // there: its head where its tail was,
        // at (2,1), off West's platform, too short for two cars; the line
        // cannot send it out again.
        XCTAssertNil(try train(world, id).execution)
        XCTAssertEqual(try train(world, id).position, .atNode(p(2, 1), heading: .east))
        XCTAssertEqual(try train(world, id).trail, [p(1, 1)])
        XCTAssertEqual(world.stationsStoppedAt(by: id), [])
        try world.advance(ticks: 30)
        XCTAssertNil(try train(world, id).execution)
    }

    // MARK: - Saves

    /// Grown stations and long trains load back equal; a station of one
    /// tile and a train of one car write no new keys; explicit nulls,
    /// counts out of range, and bodies that do not fit or are not on the
    /// track are refused.
    func testSavesKeepStationsAndBodies() throws {
        var (world, central, _) = try makeLineWorld()
        try world.extendStation(central, to: p(5, 0))
        let long = try world.purchaseTrain(named: "Long").id
        let short = try world.purchaseTrain(named: "Short").id
        try world.setTrainCars(long, to: 3)
        try world.placeTrain(long, at: .atNode(p(3, 1), heading: .east))
        try world.placeTrain(short, at: .atNode(p(7, 1), heading: .east))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stations = try XCTUnwrap(json["stations"] as? [[String: Any]])
        XCTAssertNotNil(stations[0]["annexes"])
        XCTAssertNil(stations[1]["annexes"])
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        XCTAssertEqual(trains[0]["cars"] as? Int, 3)
        XCTAssertNotNil(trains[0]["trail"])
        XCTAssertNil(trains[1]["cars"])
        XCTAssertNil(trains[1]["trail"])

        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var copy = json
            change(&copy)
            return try JSONSerialization.data(withJSONObject: copy)
        }
        func setTrain(_ key: String, _ value: Any) throws -> Data {
            try mutated { json in
                var trains = json["trains"] as! [[String: Any]]
                trains[0][key] = value
                json["trains"] = trains
            }
        }
        let refused: [(String, Data)] = try [
            ("null cars", setTrain("cars", NSNull())),
            ("no cars", setTrain("cars", 0)),
            ("too many cars", setTrain("cars", 17)),
            ("null trail", setTrain("trail", NSNull())),
            ("short trail", setTrain("trail", [["x": 2, "y": 1]])),
            ("trail not behind", setTrain("trail", [["x": 4, "y": 1], ["x": 5, "y": 1]])),
            ("trail off the track", setTrain("trail", [["x": 2, "y": 1], ["x": 2, "y": 0]])),
            ("null annexes", mutated { json in
                var stations = json["stations"] as! [[String: Any]]
                stations[0]["annexes"] = NSNull()
                json["stations"] = stations
            }),
            ("annex not beside", mutated { json in
                var stations = json["stations"] as! [[String: Any]]
                stations[0]["annexes"] = [["x": 6, "y": 0]]
                json["stations"] = stations
            }),
        ]
        for (name, bytes) in refused {
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: bytes), name)
        }
    }
}
