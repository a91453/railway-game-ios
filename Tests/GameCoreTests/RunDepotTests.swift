import Foundation
@testable import GameCore
import XCTest

/// Depots of lines with runs, and lines with several depots (ARCHITECTURE
/// decision 221): a train goes into the depot it reaches soonest when no
/// run of its line leaves where it waits for a while, and out of the depot
/// nearest a stop in time for a run that would find no train there.
///
/// A straight track of eleven columns: the depot West beside column 1,
/// Alpha, Beta and Gamma beside columns 3, 5 and 7, the depot East beside
/// column 9; the line Main from Alpha to Gamma, planned with a crawl, so a
/// link (1024 units) takes about a minute. Its runs leave both ends at
/// 06:00 and at 22:00, ten minutes each.
final class RunDepotTests: XCTestCase {
    private let track = TestLine(tiles: 11)
    private let west = StationID(rawValue: 1)
    private let alpha = StationID(rawValue: 2)
    private let beta = StationID(rawValue: 3)
    private let gamma = StationID(rawValue: 4)
    private let east = StationID(rawValue: 5)
    private let main = LineID(rawValue: 1)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    private func run(_ from: Int, _ to: Int, at minute: Int64, taking minutes: Int64 = 10) -> LineRun {
        let start = minute * 60
        return LineRun(from: from, to: to, times: [
            LineRunTime(arrival: start, departure: start), LineRunTime(arrival: start + minutes * 60, departure: start + minutes * 60),
        ])
    }

    /// The runs of the day: each end at 06:00 and 22:00.
    private var day: [LineRun] {
        [run(0, 1, at: 360), run(1, 0, at: 360), run(0, 1, at: 1_320), run(1, 0, at: 1_320)]
    }

    /// The runs of a day on the single track under traffic control, where
    /// two runs cannot pass: out from Alpha at 06:00 and 22:00, back from
    /// Gamma half an hour later, which the same train runs.
    private var singleTrackDay: [LineRun] {
        [run(0, 1, at: 360), run(1, 0, at: 390), run(0, 1, at: 1_320), run(1, 0, at: 1_350)]
    }

    /// The world at `minutes`, with train 1 in West facing east and train 2
    /// in East facing west (or at `places`), both Main's, Main given
    /// `depots` and `runs`.
    private func makeWorld(
        minutes: Int64 = 0, depots: [StationID]? = nil, runs: [LineRun]? = nil, trafficControl: Bool = false,
        at places: [(x: Int, facingEast: Bool)] = [(1, true), (9, false)]
    ) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 12_288, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: .normal)
        )
        try track.build(in: &world)
        try track.buildStation(named: "West", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Alpha", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Beta", beside: 5, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 7, at: 0, in: &world)
        try track.buildStation(named: "East", beside: 9, at: 0, in: &world)
        try world.setStationDepot(west, to: true)
        try world.setStationDepot(east, to: true)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineRuns(main, to: runs ?? day)
        try world.setLineDepots(main, to: depots ?? [west, east])
        try world.setTrafficControl(trafficControl)
        for (index, (x, facingEast)) in places.enumerated() {
            let train = try world.purchaseTrain(named: "T\(index + 1)")
            try world.placeTrain(train.id, at: track.at(x, facingEast: facingEast))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        return world
    }

    private func id(_ number: Int) -> TrainID { TrainID(rawValue: number) }

    // MARK: - Commands

    /// A line with runs keeps depots, several of them, and a save writes
    /// several as `"depots"`, one as `"depot"`.
    func testALineWithRunsHasDepots() throws {
        var world = try makeWorld()
        XCTAssertEqual(world.line(id: main)?.depots, [west, east])
        XCTAssertEqual(world.line(id: main)?.depot, west)
        XCTAssertThrowsError(try world.setLineDepots(main, to: [west, west])) { XCTAssertEqual($0 as? GameError, .depotListedTwice(west)) }
        XCTAssertThrowsError(try world.setLineDepots(main, to: [west, beta])) { XCTAssertEqual($0 as? GameError, .notADepot(beta)) }
        XCTAssertThrowsError(try world.setStationDepot(east, to: false)) { XCTAssertEqual($0 as? GameError, .depotInUse(main)) }
        XCTAssertEqual(world.line(id: main)?.depots, [west, east], "a refused change changes nothing")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var text = String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertTrue(text.contains(#""depots":[1,5]"#))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: Data(text.utf8)).world, world)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(text.replacingOccurrences(of: #""depots":[1,5]"#, with: #""depots":[1,1]"#).utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(text.replacingOccurrences(of: #""depots":[1,5]"#, with: #""depot":1,"depots":[1,5]"#).utf8)))
        try world.setLineDepot(main, to: east)
        text = String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertTrue(text.contains(#""depot":5"#))
        XCTAssertFalse(text.contains("depots"))
        // Demolishing a depot takes it off the line's list, keeping the other.
        try world.setLineDepots(main, to: [west, east])
        try world.removeStation(east)
        XCTAssertEqual(world.line(id: main)?.depots, [west])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    // MARK: - Late under traffic control

    /// Main from Alpha by Beta to Gamma, runs from Alpha at 06:00 and from
    /// Gamma at 06:20, and an unassigned train standing between Beta and
    /// Gamma. Under traffic control train 1, out of West for the first run,
    /// cannot take its route past it and waits at Beta, later and later.
    /// Its timetable has it at Gamma at 06:10, in time for the second run;
    /// it counts from when it would arrive, its lateness added, so once
    /// that is past 06:20 train 2 comes out of East to Gamma for the run.
    /// With traffic control off train 1 runs on to Gamma and train 2 stays
    /// in East, as before.
    func testUnderTrafficControlALateTrainLeavesItsRunToOneFromTheDepot() throws {
        func world(trafficControl: Bool) throws -> GameWorld {
            var world = try GameWorld(
                bounds: WorldBounds(width: 12_288, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
                clock: GameClock(now: GameTime(minutes: 330), speed: .normal)
            )
            try track.build(in: &world)
            for (name, x) in [("West", 1), ("Alpha", 3), ("Beta", 5), ("Gamma", 7), ("East", 9)] {
                try track.buildStation(named: name, beside: x, at: 0, in: &world)
            }
            try world.setStationDepot(west, to: true)
            try world.setStationDepot(east, to: true)
            try world.createLine(named: "Main", stops: [alpha, beta, gamma])
            try world.setLinePerformance(main, to: crawl)
            func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
                LineRun(from: from, to: to, times: [0, 5, 10].map { LineRunTime(arrival: (minute + $0) * 60, departure: (minute + $0) * 60) })
            }
            try world.setLineRuns(main, to: [run(0, 2, at: 360), run(2, 0, at: 380)])
            try world.setLineDepots(main, to: [west, east])
            try world.setTrafficControl(trafficControl)
            for (x, facingEast) in [(1, true), (9, false)] {
                let train = try world.purchaseTrain(named: "T\(x)")
                try world.placeTrain(train.id, at: track.at(x, facingEast: facingEast))
                try world.setTrainMovementRate(train.id, to: 1024)
                try world.assignTrain(train.id, to: main)
            }
            let standing = try world.purchaseTrain(named: "Standing")
            try world.placeTrain(standing.id, at: track.at(6, facingEast: true))
            return world
        }
        func leftEast(_ world: inout GameWorld) throws -> Bool {
            while world.clock.now < GameTime(minutes: 390) {
                try world.advance(ticks: 1)
                if world.train(id: id(2))?.isDeadheading == true { return true }
            }
            return false
        }
        var controlled = try world(trafficControl: true)
        XCTAssertTrue(try leftEast(&controlled), "train 2 comes out of East for the run from Gamma")
        XCTAssertGreaterThan(controlled.lateness(of: id(1)) ?? 0, 10 * 60, "train 1 is more than ten minutes late at Beta")
        XCTAssertEqual(controlled.stationsStoppedAt(by: id(1)), [beta])
        XCTAssertEqual(WorldInvariants.violations(in: controlled), [])

        var free = try world(trafficControl: false)
        XCTAssertFalse(try leftEast(&free), "without traffic control train 2 stays in East")
        XCTAssertEqual(free.stationsStoppedAt(by: id(2)), [east])
    }

    // MARK: - Out and in

    /// Each train runs out of its depot a few minutes before 06:00 to the
    /// end nearer it, and its run leaves on the dot.
    func testTheTrainsLeaveTheirDepotsInTimeForTheFirstRuns() throws {
        var world = try makeWorld()
        var leftAt: [TrainID: GameTime] = [:]
        while world.line(id: main)?.runDays[0] == nil || world.line(id: main)?.runDays[1] == nil {
            try world.advance(ticks: 1)
            for train in world.trains where train.isDeadheading && leftAt[train.id] == nil { leftAt[train.id] = world.clock.now }
            XCTAssertLessThan(world.clock.now, GameTime(minutes: 400))
        }
        for train in [id(1), id(2)] {
            let left = try XCTUnwrap(leftAt[train])
            XCTAssertLessThan(left, GameTime(minutes: 355), "out of the depot before the run is due")
            XCTAssertGreaterThan(left, GameTime(minutes: 340), "not long before it")
            XCTAssertEqual(world.train(id: train)?.timetable.first?.departure, GameTime(minutes: 360), "the run leaves on time")
        }
        XCTAssertEqual(world.train(id: id(1))?.timetable.first?.station, alpha, "West's train runs from Alpha")
        XCTAssertEqual(world.train(id: id(2))?.timetable.first?.station, gamma, "East's from Gamma")
        XCTAssertGreaterThan(world.line(id: main)?.deadheadDistance ?? 0, 0, "the runs out are empty running")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// After the morning runs no run leaves either end before 22:00, so each
    /// train goes into the depot beside the end it reached (train 1, from
    /// Alpha, into East), comes out again for the evening run, and after it
    /// stands in the depot beside where it ended until the morning.
    func testBetweenRunsAndAtNightTheTrainsStandInTheNearestDepot() throws {
        var world = try makeWorld()
        try world.advance(ticks: 8 * 60)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [east], "train 1 ended at Gamma")
        XCTAssertEqual(world.stationsStoppedAt(by: id(2)), [west], "train 2 at Alpha")
        try world.advance(ticks: 22 * 60 + 30 - 8 * 60)
        XCTAssertEqual(world.line(id: main)?.runDays, [0, 0, 0, 0], "every run of the day left")
        try world.advance(ticks: 60)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [west], "back where it began")
        XCTAssertEqual(world.stationsStoppedAt(by: id(2)), [east])
        try world.advance(ticks: 4 * 60)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [west], "still there at 04:30")
        XCTAssertNil(world.train(id: id(1))?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// With line accounts the runs into and out of the depots are in the
    /// trip log as empty runs (decision 223), as on a line without runs.
    func testTheRunsIntoAndOutOfTheDepotsAreLogged() throws {
        var world = try makeWorld()
        world.setLineAccounts(true)
        try world.advance(ticks: 8 * 60)
        let trips = world.trips(of: id(1))
        XCTAssertTrue(trips.contains { $0.isDeadhead && $0.from == west }, "out of West: \(trips)")
        XCTAssertTrue(trips.contains { $0.isDeadhead && $0.to == east }, "into East: \(trips)")
        XCTAssertTrue(trips.contains { !$0.isDeadhead && $0.from == alpha && $0.to == gamma }, "the run")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A train whose next run leaves where it waits within two hours stays
    /// there: here it reaches Gamma at about 06:10 and leaves it at 07:00.
    func testATrainThatTurnsRoundSoonStays() throws {
        var world = try makeWorld(runs: [run(0, 1, at: 360), run(1, 0, at: 420)])
        try world.setTrainMovementRate(id(2), to: 0)
        try world.advance(ticks: 6 * 60 + 20)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [gamma])
        for _ in 0..<35 {
            try world.advance(ticks: 1)
            XCTAssertFalse(world.train(id: id(1))?.isDeadheading ?? true, "it does not run into East at \(world.clock.now.minute)")
        }
        try world.advance(ticks: 10)
        XCTAssertEqual(world.line(id: main)?.runDays[1], 0, "and takes its 07:00 run")
    }

    /// A train on its way to a stop counts for a run there only if it
    /// arrives by the run's departure, each train taking the earliest run
    /// it can; and in the world, Gamma's 06:00 run has East's train, not
    /// Alpha's that reaches Gamma at 06:10.
    func testATrainArrivingAfterTheRunDoesNotCount() throws {
        XCTAssertEqual(GameWorld.runsWithoutTrains([100, 200], ready: [150]), 1)
        XCTAssertEqual(GameWorld.runsWithoutTrains([100, 200], ready: [50, 150]), 0)
        XCTAssertEqual(GameWorld.runsWithoutTrains([100], ready: [150, 160]), 1)
        var world = try makeWorld()
        try world.advance(ticks: 6 * 60 + 1)
        XCTAssertEqual(world.line(id: main)?.runDays[1], 0)
        XCTAssertEqual(world.train(id: id(2))?.timetable.first?.departure, GameTime(minutes: 360), "Gamma's run leaves on time")
    }

    /// A train that waits where no run of its line leaves goes into a
    /// depot: Beta is between the line's ends.
    func testATrainWhereNoRunLeavesGoesIn() throws {
        var world = try makeWorld(minutes: 600, at: [(5, true), (9, false)])
        try world.advance(ticks: 30)
        XCTAssertFalse(world.stationsStoppedAt(by: id(1)).contains(beta))
        XCTAssertTrue([west, east].contains(world.stationsStoppedAt(by: id(1)).first ?? beta))
    }

    /// Two trains going into the same depot take a siding each, not the
    /// one where the first stands: West has its sidings either side of
    /// column 1.
    func testTrainsGoingIntoADepotTakeASidingEach() throws {
        var world = try makeWorld(minutes: 600, depots: [west], at: [(3, false), (5, false)])
        try world.advance(ticks: 30)
        let edges = world.trains.compactMap { train -> TrackEdgeID? in
            guard case .onEdge(let traversal, _)? = train.position else { return nil }
            return traversal.edge
        }
        XCTAssertEqual(world.trains.map { world.stationsStoppedAt(by: $0.id) }, [[west], [west]])
        XCTAssertEqual(Set(edges).count, 2, "a siding each")
    }

    /// Under traffic control the trains still go in and out: train 1 runs
    /// out of West for the 06:00 run, takes the 06:30 back from Gamma (it
    /// stands there, so East sends none), goes into West after it and runs
    /// the evening's two the same way; train 2 stays in East.
    func testUnderTrafficControl() throws {
        var world = try makeWorld(runs: singleTrackDay, trafficControl: true)
        try world.advance(ticks: 8 * 60)
        XCTAssertEqual(world.line(id: main)?.runDays, [0, 0, nil, nil])
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [west])
        XCTAssertEqual(world.stationsStoppedAt(by: id(2)), [east])
        try world.advance(ticks: 16 * 60)
        XCTAssertEqual(world.line(id: main)?.runDays, [0, 0, 0, 0])
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [west])
        XCTAssertEqual(world.stationsStoppedAt(by: id(2)), [east], "never sent out")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// The whole day in one call ends exactly where minute by minute does:
    /// the moves into and out of the depots wake the idle stretches at the
    /// right minutes.
    func testLongBatchesMatchSingleMinutes() throws {
        for trafficControl in [false, true] {
            var batched = try makeWorld(minutes: 300, runs: trafficControl ? singleTrackDay : day, trafficControl: trafficControl)
            var single = batched
            try batched.advance(ticks: 26 * 60)
            for _ in 0..<(26 * 60) { try single.advance(ticks: 1) }
            XCTAssertEqual(batched, single, "traffic control \(trafficControl)")
            XCTAssertEqual(batched.line(id: main)?.runDays, [1, 1, 0, 0])
        }
    }

    /// A line without depots, or a line without runs, is as before: the
    /// trains stay where their runs end.
    ///
    /// One train: two going opposite ways at once on the single track wait
    /// for each other (decision 248) rather than run through each other.
    func testWithoutDepotsTheTrainsStayWhereTheyEnd() throws {
        var world = try makeWorld(minutes: 340, depots: [], runs: [run(0, 1, at: 360)], at: [(3, true)])
        try world.advance(ticks: 3 * 60)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [gamma])
        XCTAssertEqual(world.line(id: main)?.deadheadDistance, 0)
    }

    // MARK: - Saves

    /// Save version 59: a line with runs and two depots, its trains on
    /// their way out of the depots just before 06:00. Written by the
    /// version 59 build (#611), merged as version 59; no build since writes
    /// it.
    func testVersionFiftyNineKeepsTheDepots() throws {
        try checkFixture("v59-run-depots.json", version: 59, writing: false)
    }

    /// Save version 61: the same world. The format came in under 59 while
    /// `main` was at 60 (the trip log), so a version 60 build would have
    /// read it as its own and dropped the depots after a line's first;
    /// since 61 a build before it says the save is newer instead.
    func testVersionSixtyOneKeepsTheDepots() throws {
        try checkFixture("v61-run-depots.json", version: 61, writing: ProcessInfo.processInfo.environment["RUN_DEPOT_SAVE_NEW"] != nil)
    }

    private func checkFixture(_ name: String, version: Int, writing: Bool) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/\(name)")
        var made = try makeWorld()
        made.setEconomyMode(.management)
        try made.advance(ticks: 353)
        XCTAssertTrue(made.trains.allSatisfy(\.isDeadheading), "both on their way out")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if writing {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, version)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertEqual(loaded.line(id: main)?.depots, [west, east])
        XCTAssertTrue(loaded.line(id: main)?.hasRuns ?? false)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : \#(version),"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        try loaded.advance(ticks: 30)
        XCTAssertEqual(loaded.line(id: main)?.runDays[0], 0, "and the runs leave")
    }
}
