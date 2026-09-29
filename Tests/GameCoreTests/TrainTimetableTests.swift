import Foundation
import GameCore
import XCTest

/// Train timetables (Phase 4 Stage O, ARCHITECTURE decision 19): an ordered
/// list of scheduled stops, each a station with an arrival and a departure
/// in game minutes, replaced whole by `setTrainTimetable` and saved with the
/// train. A timetable is plan data only: nothing in the simulation reads it.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class TrainTimetableTests: XCTestCase {
    // A line along y = 1 with dead ends at both ends, and three stations:
    //
    //   Alpha(1,0)  Beta(3,0)
    //       |           |
    //   a - b - c - d - e         Gamma(5,2): no platform
    //
    // Alpha's platform is b, Beta's is d.
    private let a = GridPosition(x: 0, y: 1)
    private let b = GridPosition(x: 1, y: 1)
    private let c = GridPosition(x: 2, y: 1)
    private let d = GridPosition(x: 3, y: 1)
    private let e = GridPosition(x: 4, y: 1)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)
    private let third = TrainID(rawValue: 3)

    private func makeLineWorld(trainCount: Int = 1) throws -> GameWorld {
        var world = try makeWorld(width: 6, height: 3, balance: 100_000)
        try world.buildTrack(at: a, connections: .east)
        for tile in [b, c, d] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: e, connections: .west)
        try world.buildStation(named: "Alpha", at: GridPosition(x: 1, y: 0))
        try world.buildStation(named: "Beta", at: GridPosition(x: 3, y: 0))
        try world.buildStation(named: "Gamma", at: GridPosition(x: 5, y: 2))
        for number in 0..<trainCount {
            try world.purchaseTrain(named: "Local \(number + 1)")
        }
        world.setSpeed(.normal)
        return world
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure))
    }

    private func timetable(of id: TrainID, in world: GameWorld) throws -> [ScheduledStop] {
        try XCTUnwrap(world.train(id: id)).timetable
    }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    /// Five stops: zero dwell, equal boundaries, repeated stations and a
    /// station without a platform, all allowed.
    private var fiveStops: [ScheduledStop] {
        [stop(alpha, 10, 12), stop(beta, 20, 20), stop(gamma, 20, 25), stop(beta, 30, 31), stop(alpha, 40, 40)]
    }

    // MARK: - Creation

    func testNewTrainsHaveNoTimetable() throws {
        var world = try makeLineWorld(trainCount: 2)
        XCTAssertEqual(try timetable(of: first, in: world), [])
        XCTAssertEqual(Train(id: first, name: "A").timetable, [])

        // A train bought after another got a timetable does not inherit it.
        try world.setTrainTimetable(second, to: fiveStops)
        let bought = try world.purchaseTrain(named: "Local 3")

        XCTAssertEqual(bought.timetable, [])
        XCTAssertEqual(try timetable(of: third, in: world), [])
        XCTAssertEqual(try timetable(of: second, in: world), fiveStops)
    }

    // MARK: - Valid timetables

    func testAOneStopTimetableIsSetAsGiven() throws {
        var world = try makeLineWorld()

        try world.setTrainTimetable(first, to: [stop(alpha, 10, 12)])

        XCTAssertEqual(try timetable(of: first, in: world), [stop(alpha, 10, 12)])
    }

    func testStopsKeepTheOrderTheyWereGivenIn() throws {
        var world = try makeLineWorld()
        let stops = [stop(beta, 0, 5), stop(gamma, 6, 6), stop(alpha, 7, 100)]

        try world.setTrainTimetable(first, to: stops)

        XCTAssertEqual(try timetable(of: first, in: world), stops)
        XCTAssertEqual(try timetable(of: first, in: world).map(\.station), [beta, gamma, alpha])
    }

    func testZeroDwellEqualBoundariesAndRepeatedStationsAreAllowed() throws {
        var world = try makeLineWorld()
        let allowed: [[ScheduledStop]] = [
            fiveStops,
            [stop(alpha, 0, 0)],
            [stop(alpha, 5, 5), stop(alpha, 5, 5), stop(alpha, 5, 5)],
            [stop(alpha, 0, 10), stop(beta, 10, 20), stop(alpha, 20, 30)],
            [stop(gamma, .max, .max)],
            [stop(alpha, 0, .max)],
        ]
        for stops in allowed {
            try world.setTrainTimetable(first, to: stops)
            XCTAssertEqual(try timetable(of: first, in: world), stops)
        }
    }

    /// Whether the train could keep to the timetable is not checked: times
    /// already passed, a station without a platform, and an unplaced train.
    func testFeasibilityIsNotChecked() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainMovementRate(first, to: 1)
        try world.advance(ticks: 100)
        XCTAssertEqual(world.clock.now.minutes, 100)
        XCTAssertEqual(world.platforms(of: gamma), [])

        // Minute 0 has passed, and Gamma has no platform to stop at.
        try world.setTrainTimetable(first, to: [stop(gamma, 0, 0), stop(beta, 1, 2)])
        // The second train has never been placed.
        try world.setTrainTimetable(second, to: [stop(alpha, 0, 1)])

        XCTAssertEqual(try timetable(of: first, in: world), [stop(gamma, 0, 0), stop(beta, 1, 2)])
        XCTAssertEqual(try timetable(of: second, in: world), [stop(alpha, 0, 1)])
    }

    func testReplacingATimetableReplacesItWhole() throws {
        var world = try makeLineWorld()
        try world.setTrainTimetable(first, to: fiveStops)

        try world.setTrainTimetable(first, to: [stop(beta, 100, 105)])

        XCTAssertEqual(try timetable(of: first, in: world), [stop(beta, 100, 105)])
    }

    func testAnEmptyListClearsTheTimetable() throws {
        var world = try makeLineWorld()
        try world.setTrainTimetable(first, to: fiveStops)

        try world.setTrainTimetable(first, to: [])
        XCTAssertEqual(try timetable(of: first, in: world), [])

        // Clearing an empty timetable is not an error.
        let before = world
        try world.setTrainTimetable(first, to: [])
        XCTAssertEqual(world, before)
    }

    // MARK: - Invalid timetables

    func testAnUnknownTrainIsRejected() throws {
        var world = try makeLineWorld()
        for raw in [0, -1, 2, Int.max, Int.min] {
            XCTAssertThrowsGameError(try world.setTrainTimetable(TrainID(rawValue: raw), to: []), .unknownTrain(TrainID(rawValue: raw)))
            XCTAssertThrowsGameError(
                try world.setTrainTimetable(TrainID(rawValue: raw), to: [stop(alpha, 1, 2)]),
                .unknownTrain(TrainID(rawValue: raw))
            )
        }
    }

    func testStopsAtUnknownStationsAreRejected() throws {
        var world = try makeLineWorld()
        for raw in [0, -1, 4, 99, Int.max, Int.min] {
            let unknown = StationID(rawValue: raw)
            XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(unknown, 0, 0)]), .unknownStation(unknown))
            XCTAssertThrowsGameError(
                try world.setTrainTimetable(first, to: [stop(alpha, 0, 1), stop(beta, 2, 3), stop(unknown, 4, 5)]),
                .unknownStation(unknown)
            )
        }
    }

    func testNegativeTimesAreRejected() throws {
        var world = try makeLineWorld()
        let rejected: [[ScheduledStop]] = [
            [stop(alpha, -1, 5)],
            [stop(alpha, -1, -1)],
            [stop(alpha, 0, -1)],
            [stop(alpha, .min, 0)],
            [stop(alpha, .min, .min)],
            [stop(alpha, 0, 1), stop(beta, -5, 2)],
            [stop(alpha, 0, 1), stop(beta, 2, -3)],
        ]
        for stops in rejected {
            XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: stops), .invalidTimetable)
        }
    }

    func testADepartureBeforeItsArrivalIsRejected() throws {
        var world = try makeLineWorld()
        for stops in [[stop(alpha, 15, 14)], [stop(alpha, 1, 0)], [stop(alpha, .max, 0)], [stop(alpha, 0, 5), stop(beta, 9, 8)]] {
            XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: stops), .invalidTimetable)
        }
    }

    func testAnArrivalBeforeThePreviousDepartureIsRejected() throws {
        var world = try makeLineWorld()
        let rejected: [[ScheduledStop]] = [
            [stop(alpha, 10, 20), stop(beta, 19, 30)],
            // Stops out of order are not sorted into order.
            [stop(beta, 20, 25), stop(alpha, 10, 12)],
            // Each stop is fine alone and after the one before; the third
            // goes back past the second.
            [stop(alpha, 0, 10), stop(beta, 10, 20), stop(gamma, 15, 40)],
            [stop(alpha, .max, .max), stop(beta, 0, 0)],
        ]
        for stops in rejected {
            XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: stops), .invalidTimetable)
        }
    }

    /// Checked in this order: the train, then the times, then the stations,
    /// the first missing one in timetable order.
    func testChecksRunInTheDocumentedOrder() throws {
        var world = try makeLineWorld()
        let nowhere = StationID(rawValue: 9)
        let elsewhere = StationID(rawValue: 5)

        XCTAssertThrowsGameError(
            try world.setTrainTimetable(TrainID(rawValue: 9), to: [stop(nowhere, -1, -2)]),
            .unknownTrain(TrainID(rawValue: 9))
        )
        // An unknown station listed before the stop whose times go back.
        XCTAssertThrowsGameError(
            try world.setTrainTimetable(first, to: [stop(nowhere, 0, 1), stop(alpha, 5, 4)]),
            .invalidTimetable
        )
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(nowhere, 5, 1)]), .invalidTimetable)
        // The first missing station in timetable order, not the lowest ID.
        XCTAssertThrowsGameError(
            try world.setTrainTimetable(first, to: [stop(alpha, 0, 0), stop(nowhere, 1, 1), stop(elsewhere, 2, 2)]),
            .unknownStation(nowhere)
        )
        XCTAssertThrowsGameError(
            try world.setTrainTimetable(first, to: [stop(elsewhere, 0, 0), stop(nowhere, 1, 1)]),
            .unknownStation(elsewhere)
        )
    }

    /// A refused command changes nothing: the old timetable stays, whole.
    func testRejectedTimetablesChangeNothing() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 300)
        try world.setTrainContinuation(first, to: [c, d])
        try world.setTrainTimetable(first, to: fiveStops)
        try world.advance(ticks: 2)
        let before = world

        let attempts: [(TrainID, [ScheduledStop])] = [
            (TrainID(rawValue: 7), [stop(alpha, 1, 2)]),
            (first, [stop(alpha, 1, 2), stop(beta, 1, 0)]),
            (first, [stop(alpha, -1, 2)]),
            (first, [stop(alpha, 1, 2), stop(StationID(rawValue: 4), 3, 4)]),
            (second, [stop(alpha, 3, 4), stop(beta, 2, 5)]),
            (second, [stop(StationID(rawValue: 0), 3, 4)]),
        ]
        for (id, stops) in attempts {
            XCTAssertThrowsError(try world.setTrainTimetable(id, to: stops))
            XCTAssertEqual(world, before, "\(id) \(stops)")
        }
        XCTAssertEqual(try timetable(of: first, in: world), fiveStops)
    }

    // MARK: - Isolation

    /// Setting a timetable changes that train's timetable and nothing else:
    /// not its position or movement, other trains, the map, stations, money,
    /// time or the IDs handed out next.
    func testATimetableChangesOnlyThatTrainsTimetable() throws {
        var world = try makeLineWorld(trainCount: 3)
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 300))
        try world.setTrainMovementRate(first, to: 200)
        try world.setTrainContinuation(first, to: [c])
        try world.placeTrain(second, at: .atNode(d, heading: .west))
        try world.setTrainTimetable(third, to: [stop(gamma, 1, 2)])
        try world.advance(ticks: 1)
        let before = world

        try world.setTrainTimetable(second, to: fiveStops)

        XCTAssertEqual(try timetable(of: second, in: world), fiveStops)
        XCTAssertEqual(world.map, before.map)
        XCTAssertEqual(world.stations, before.stations)
        XCTAssertEqual(world.clock, before.clock)
        XCTAssertEqual(world.economy, before.economy)
        XCTAssertEqual(world.trains.map(\.id), before.trains.map(\.id))
        for (train, old) in zip(world.trains, before.trains) {
            XCTAssertEqual(train.name, old.name)
            XCTAssertEqual(train.position, old.position)
            XCTAssertEqual(train.movement, old.movement)
            if train.id != second {
                XCTAssertEqual(train.timetable, old.timetable)
            }
        }
        // Putting the old timetable back gives back the same world, private
        // ID counters included.
        var restored = world
        try restored.setTrainTimetable(second, to: [])
        XCTAssertEqual(restored, before)
        // The next IDs are the ones that were due.
        XCTAssertEqual(try world.purchaseTrain(named: "Local 4").id, TrainID(rawValue: 4))
        XCTAssertEqual(try world.buildStation(named: "Delta", at: GridPosition(x: 0, y: 0)).id, StationID(rawValue: 4))
    }

    // MARK: - Lifecycle

    /// Placing, the movement commands, time, reversing, unplacing and
    /// placing again keep the timetable; each still does exactly what it did
    /// before timetables existed.
    func testTheTimetableSurvivesEveryTrainCommandAndTime() throws {
        var world = try makeLineWorld()
        try world.setTrainTimetable(first, to: fiveStops)
        func check(_ step: String, line: UInt = #line) throws {
            XCTAssertEqual(try timetable(of: first, in: world), fiveStops, step, line: line)
        }

        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try check("place")
        try world.setTrainMovementRate(first, to: 1024)
        try check("rate")
        try world.setTrainContinuation(first, to: [b, c])
        try check("continuation")
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(b, heading: .east))
        try check("advance")
        try world.setTrainContinuation(first, to: [])
        try check("clearing the continuation")

        try world.reverseTrain(first)
        XCTAssertEqual(world.train(id: first)?.position, .atNode(b, heading: .west))
        XCTAssertEqual(world.train(id: first)?.movement.rate, 1024)
        try check("reverse")

        try world.unplaceTrain(first)
        XCTAssertNil(world.train(id: first)?.position)
        XCTAssertEqual(world.train(id: first)?.movement, .idle)
        try check("unplace")

        try world.placeTrain(first, at: .atNode(d, heading: .west))
        XCTAssertEqual(world.train(id: first)?.movement, .idle)
        try check("placing again")
        try world.advance(ticks: 30)
        try check("time")
    }

    // MARK: - Inert

    /// A timetable never drives a train. A train stopped at a scheduled
    /// station stays there after its departure time; a train with a rate
    /// and nowhere to go is not given a continuation; a held train (rate 0)
    /// is not started; an unplaced train is not placed. Time passing past
    /// every arrival and departure changes no timetable.
    func testATimetableNeverDrivesATrain() throws {
        var world = try makeLineWorld(trainCount: 3)
        // Stopped at Alpha, scheduled to leave at minute 12 for Beta.
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 12), stop(beta, 14, 20)])
        // Held at rate 0 with a continuation, scheduled to leave at once.
        try world.placeTrain(second, at: .atNode(c, heading: .east))
        try world.setTrainContinuation(second, to: [d, e])
        try world.setTrainTimetable(second, to: [stop(beta, 0, 0)])
        // Never placed, scheduled at minute 5.
        try world.setTrainTimetable(third, to: [stop(beta, 5, 6)])
        let scheduled = world.trains.map(\.timetable)
        let trainsBefore = world.trains
        XCTAssertEqual(world.stationsStoppedAt(by: first), [alpha])

        for (ticks, minute) in [(5, 5), (7, 12), (1, 13), (1, 14), (100, 114)] as [(Int, Int64)] {
            try world.advance(ticks: ticks)
            XCTAssertEqual(world.clock.now.minutes, minute)
            XCTAssertEqual(world.trains, trainsBefore, "minute \(minute)")
            XCTAssertEqual(world.trains.map(\.timetable), scheduled)
            XCTAssertEqual(world.stationsStoppedAt(by: first), [alpha], "minute \(minute)")
        }
    }

    /// The same commands on a world with timetables and on one without give
    /// the same world apart from the timetables, step by step.
    func testTimetablesChangeNoOutcomeOfAScriptedRun() throws {
        var plain = try makeLineWorld(trainCount: 2)
        var scheduled = plain
        try scheduled.setTrainTimetable(first, to: fiveStops)
        try scheduled.setTrainTimetable(second, to: [stop(beta, 0, 0), stop(beta, 1, 1)])

        let script: [(inout GameWorld) throws -> Void] = [
            { try $0.placeTrain(self.first, at: .atNode(self.a, heading: .east)) },
            { try $0.setTrainMovementRate(self.first, to: 700) },
            { world in
                let route = try XCTUnwrap(world.route(from: .atNode(self.a, heading: .east), toStation: self.beta))
                try world.setTrainContinuation(self.first, to: route)
            },
            { try $0.advance(ticks: 3) },
            { try $0.placeTrain(self.second, at: .onLink(from: self.e, to: self.d, offset: 1000)) },
            { try $0.setTrainMovementRate(self.second, to: 50) },
            { try $0.advance(ticks: 20) },
            { try $0.reverseTrain(self.first) },
            { try $0.removeTrack(at: self.a) },
            { try $0.advance(ticks: 60) },
            { try $0.unplaceTrain(self.second) },
            { try $0.advance(ticks: 5) },
        ]
        for (index, step) in script.enumerated() {
            try step(&plain)
            try step(&scheduled)
            var cleared = scheduled
            try cleared.setTrainTimetable(first, to: [])
            try cleared.setTrainTimetable(second, to: [])
            XCTAssertEqual(cleared, plain, "step \(index)")
            XCTAssertEqual(try timetable(of: first, in: scheduled), fiveStops, "step \(index)")
            for id in [first, second] {
                XCTAssertEqual(scheduled.stationsStoppedAt(by: id), plain.stationsStoppedAt(by: id), "step \(index)")
            }
        }
        XCTAssertEqual(scheduled.train(id: first)?.position, .atNode(d, heading: .west))
        XCTAssertEqual(scheduled.stationsStoppedAt(by: first), [beta])
    }

    // MARK: - Saving

    func testEmptyTimetablesAreNotSavedAndOldSavesReadAsEmpty() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.setTrainTimetable(second, to: [stop(alpha, 10, 12)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]])

        XCTAssertNil(trains[0]["timetable"])
        XCTAssertNotNil(trains[1]["timetable"])

        // Trains saved before timetables existed: no "timetable" key.
        let old = try JSONDecoder().decode(Train.self, from: Data(#"{"id": 1, "name": "A"}"#.utf8))
        XCTAssertEqual(old.timetable, [])
        let placed = try JSONDecoder().decode(
            Train.self,
            from: Data(#"{"id": 1, "name": "A", "position": {"atNode": {"tile": {"x": 1, "y": 1}, "heading": {"east": {}}}}, "movement": {"rate": 5, "continuation": [], "cursor": 0}}"#.utf8)
        )
        XCTAssertEqual(placed.timetable, [])
        XCTAssertEqual(placed.movement.rate, 5)
        // An explicit empty list is the same as none.
        let explicit = try JSONDecoder().decode(Train.self, from: Data(#"{"id": 1, "name": "A", "timetable": []}"#.utf8))
        XCTAssertEqual(explicit, old)
    }

    /// A world without timetables saves exactly as it did before Stage O,
    /// and a save in that form loads with every timetable empty.
    func testASaveWithoutTimetablesKeepsItsFormat() throws {
        var world = try GameWorld(width: 2, height: 1, economy: GameEconomy(balance: 10_000, costs: testCosts))
        try world.buildTrack(at: GridPosition(x: 0, y: 0), connections: .east)
        try world.buildStation(named: "S", at: GridPosition(x: 1, y: 0))
        try world.purchaseTrain(named: "T")
        try world.placeTrain(first, at: .atNode(GridPosition(x: 0, y: 0), heading: .east))
        try world.setTrainMovementRate(first, to: 5)
        let saved = #"{"clock":{"now":0,"resumeSpeed":"normal","speed":"paused"},"economy":{"balance":3900,"costs":{"station":1000,"track":100,"train":5000}},"map":{"height":1,"tiles":[{"track":{"connections":2}},{"station":{"id":1}}],"width":2},"nextStationID":2,"nextTrainID":2,"stations":[{"id":1,"name":"S","position":{"x":1,"y":0}}],"trains":[{"id":1,"movement":{"continuation":[],"cursor":0,"rate":5},"name":"T","position":{"atNode":{"heading":{"east":{}},"tile":{"x":0,"y":0}}}}]}"#

        XCTAssertEqual(String(decoding: try encode(world), as: UTF8.self), saved)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: Data(saved.utf8))
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.trains.map(\.timetable), [[]])
    }

    /// Stops are saved in their order as `{"arrival", "departure",
    /// "station"}` with plain integers, and load back exactly; the same
    /// world always gives the same bytes.
    func testTimetablesAreSavedInOrderAndLoadExactly() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.setTrainTimetable(first, to: [stop(beta, 20, 20), stop(alpha, 20, 25), stop(beta, 30, .max)])
        try world.setTrainTimetable(second, to: [stop(gamma, 0, 0)])
        let data = try encode(world)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(
            text.contains(#""timetable":[{"arrival":20,"departure":20,"station":2},{"arrival":20,"departure":25,"station":1},{"arrival":30,"departure":9223372036854775807,"station":2}]"#),
            text
        )
        let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try timetable(of: first, in: loaded), [stop(beta, 20, 20), stop(alpha, 20, 25), stop(beta, 30, .max)])
        XCTAssertEqual(try encode(loaded), data)
        XCTAssertEqual(try encode(world), data)
    }

    private func savedTrain(timetable: String) -> Data {
        Data(#"{"id": 1, "name": "A", "timetable": \#(timetable)}"#.utf8)
    }

    /// Malformed timetables are refused, never cleared, sorted, clamped or
    /// trimmed into something loadable.
    func testMalformedTimetablesAreRejectedNotRepaired() {
        let malformed = [
            "null",
            "{}",
            #""10:00""#,
            "[null]",
            "[{}]",
            "[[1, 10, 12]]",
            #"[{"station": 1, "arrival": 10}]"#,
            #"[{"station": 1, "departure": 10}]"#,
            #"[{"arrival": 10, "departure": 12}]"#,
            #"[{"station": null, "arrival": 10, "departure": 12}]"#,
            #"[{"station": "1", "arrival": 10, "departure": 12}]"#,
            #"[{"station": 1.5, "arrival": 10, "departure": 12}]"#,
            #"[{"station": 1, "arrival": "10", "departure": 12}]"#,
            #"[{"station": 1, "arrival": 10.5, "departure": 12}]"#,
            #"[{"station": 1, "arrival": 10, "departure": 9223372036854775808}]"#,
            #"[{"station": 1, "arrival": true, "departure": 12}]"#,
            // Negative times.
            #"[{"station": 1, "arrival": -1, "departure": 12}]"#,
            #"[{"station": 1, "arrival": 0, "departure": -1}]"#,
            #"[{"station": 1, "arrival": -9223372036854775808, "departure": 0}]"#,
            // A departure before its arrival.
            #"[{"station": 1, "arrival": 12, "departure": 10}]"#,
            // Stops out of order: not sorted.
            #"[{"station": 2, "arrival": 20, "departure": 25}, {"station": 1, "arrival": 10, "departure": 12}]"#,
            #"[{"station": 1, "arrival": 10, "departure": 20}, {"station": 2, "arrival": 19, "departure": 30}]"#,
            #"[{"station": 1, "arrival": 0, "departure": 1}, {"station": 2, "arrival": 1, "departure": 1}, {"station": 1, "arrival": 0, "departure": 5}]"#,
        ]
        for timetable in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(Train.self, from: savedTrain(timetable: timetable)), timetable)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ScheduledStop.self, from: Data(#"{"station": 1, "arrival": 12, "departure": 10}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ScheduledStop.self, from: Data(#"{"station": 1, "arrival": -2, "departure": -1}"#.utf8)))

        // The same shapes, in order: accepted as they are.
        let valid: [(String, [ScheduledStop])] = [
            ("[]", []),
            (#"[{"station": 1, "arrival": 0, "departure": 0}]"#, [stop(alpha, 0, 0)]),
            (#"[{"station": 1, "arrival": 10, "departure": 20}, {"station": 2, "arrival": 20, "departure": 30}, {"station": 1, "arrival": 30, "departure": 30}]"#,
             [stop(alpha, 10, 20), stop(beta, 20, 30), stop(alpha, 30, 30)]),
            // Train decoding does not look up stations: the world does.
            (#"[{"station": 99, "arrival": 1, "departure": 2}]"#, [stop(StationID(rawValue: 99), 1, 2)]),
        ]
        for (timetable, stops) in valid {
            XCTAssertEqual(try JSONDecoder().decode(Train.self, from: savedTrain(timetable: timetable)).timetable, stops, timetable)
        }
    }

    /// The world refuses a timetable that names a station it does not have.
    func testWorldDecodingRejectsTimetablesNamingUnknownStations() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.setTrainTimetable(second, to: [stop(alpha, 1, 2), stop(gamma, 3, 4)])
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])

        func decode(_ change: (inout [[String: Any]]) -> Void) throws -> GameWorld {
            var object = saved
            var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
            change(&trains)
            object["trains"] = trains
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }

        XCTAssertEqual(try decode { _ in }, world)
        for station in [0, 4, -1, Int.max] {
            XCTAssertThrowsError(try decode { trains in
                trains[1]["timetable"] = [["station": 1, "arrival": 1, "departure": 2], ["station": station, "arrival": 3, "departure": 4]]
            }, "station \(station)")
            XCTAssertThrowsError(try decode { trains in
                trains[0]["timetable"] = [["station": station, "arrival": 0, "departure": 0]]
            }, "station \(station)")
        }
        // Every station the world has is fine, on either train.
        let loaded = try decode { trains in
            trains[0]["timetable"] = [["station": 3, "arrival": 0, "departure": 0], ["station": 2, "arrival": 0, "departure": 9]]
        }
        XCTAssertEqual(try timetable(of: first, in: loaded), [stop(gamma, 0, 0), stop(beta, 0, 9)])
    }

    /// Saving and loading mid-journey keeps every timetable and changes
    /// nothing about how the trains carry on or where they stop.
    func testSavingAndLoadingKeepsTimetablesAndChangesNoOutcome() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainMovementRate(first, to: 700)
        try world.setTrainContinuation(first, to: [b, c, d])
        try world.setTrainTimetable(first, to: fiveStops)
        try world.setTrainTimetable(second, to: [stop(gamma, 5, 5)])
        try world.advance(ticks: 2)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: encode(world))
        XCTAssertEqual(loaded, world)

        for ticks in [1, 1, 3, 50] {
            try world.advance(ticks: ticks)
            try loaded.advance(ticks: ticks)
            XCTAssertEqual(loaded, world)
            XCTAssertEqual(loaded.stationsStoppedAt(by: first), world.stationsStoppedAt(by: first))
        }
        XCTAssertEqual(world.train(id: first)?.position, .atNode(d, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [beta])
        XCTAssertEqual(try timetable(of: first, in: loaded), fiveStops)
        XCTAssertEqual(try timetable(of: second, in: loaded), [stop(gamma, 5, 5)])
    }
}
