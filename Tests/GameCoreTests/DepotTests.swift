import Foundation
@testable import GameCore
import XCTest

/// Depots, level 1 (ARCHITECTURE decision 209): a station flagged as a
/// depot, a line that keeps its trains there out of service, sending them
/// out in time for their trips and back once it no longer needs them.
///
/// A straight track of nine columns: the depot beside column 1, Alpha,
/// Beta and Gamma beside columns 3, 5 and 7, the line Main from Alpha to
/// Gamma. The line plans with a crawl, so a link (1024 units) takes about
/// a minute; the depot is two links west of Alpha.
final class DepotTests: XCTestCase {
    private let track = TestLine(tiles: 9)
    private let depot = StationID(rawValue: 1)
    private let alpha = StationID(rawValue: 2)
    private let beta = StationID(rawValue: 3)
    private let gamma = StationID(rawValue: 4)
    private let main = LineID(rawValue: 1)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    /// The world at `minutes`, with `count` trains of the line standing in
    /// the depot facing east; the depot is one and the line's unless
    /// `withDepot` is false, when the trains stand at Alpha instead.
    private func makeWorld(trains count: Int = 1, inService: Int = 1, minutes: Int64 = 300, withDepot: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 10_240, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: .normal)
        )
        try track.build(in: &world)
        try track.buildStation(named: "Depot", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Alpha", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Beta", beside: 5, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 7, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .standard)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: inService, offPeak: inService, low: inService))
        if withDepot {
            try world.setStationDepot(depot, to: true)
            try world.setLineDepot(main, to: depot)
        }
        for index in 1...count {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: track.at(withDepot ? 1 : 3, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        return world
    }

    private func id(_ number: Int) -> TrainID { TrainID(rawValue: number) }

    // MARK: - Commands

    func testADepotIsAStationNoLineCallsAt() throws {
        var world = try makeWorld(withDepot: false)
        XCTAssertThrowsError(try world.setStationDepot(alpha, to: true)) { XCTAssertEqual($0 as? GameError, .depotIsLineStop(alpha)) }
        XCTAssertThrowsError(try world.setLineDepot(main, to: depot)) { XCTAssertEqual($0 as? GameError, .notADepot(depot)) }
        XCTAssertThrowsError(try world.setLineDepot(main, to: StationID(rawValue: 9))) { XCTAssertEqual($0 as? GameError, .unknownStation(StationID(rawValue: 9))) }
        try world.setStationDepot(depot, to: true)
        XCTAssertTrue(world.station(id: depot)?.isDepot ?? false)
        XCTAssertThrowsError(try world.createLine(named: "Into", stops: [depot, alpha])) { XCTAssertEqual($0 as? GameError, .depotIsLineStop(depot)) }
        XCTAssertThrowsError(try world.setLineStops(main, to: [depot, gamma])) { XCTAssertEqual($0 as? GameError, .depotIsLineStop(depot)) }
        try world.setLineDepot(main, to: depot)
        XCTAssertEqual(world.line(id: main)?.depot, depot)
        XCTAssertThrowsError(try world.setStationDepot(depot, to: false)) { XCTAssertEqual($0 as? GameError, .depotInUse(main)) }
        let run = LineRun(from: 0, to: 1, times: [
            LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 900, departure: 900),
        ])
        // Decision 221: a line with runs may keep its depot.
        try world.setLineRuns(main, to: [run])
        XCTAssertEqual(world.line(id: main)?.depots, [depot])
        try world.setLineRuns(main, to: [])
        try world.setLineDepot(main, to: nil)
        try world.setStationDepot(depot, to: false)
        XCTAssertFalse(world.station(id: depot)?.isDepot ?? true)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// No line's way runs over a depot's sidings, so a station on the
    /// line's only way between its stops cannot become one.
    func testAStationOnALinesOnlyWayCannotBecomeADepot() throws {
        var world = try makeWorld(withDepot: false)
        let before = world
        XCTAssertThrowsError(try world.setStationDepot(beta, to: true)) { XCTAssertEqual($0 as? GameError, .depotBlocksLine(main)) }
        XCTAssertEqual(world, before)
    }

    /// The depot's sidings are kept off the way to any other station
    /// (`topology.js`'s `allowYard=false`): on the single track W–M–E with
    /// a passing loop at M, a depot on the main track past M's platform
    /// sends the way from W to E round the loop, while the way into the
    /// depot, and out of it, still runs over them.
    func testAWayToAnotherStationKeepsOffTheSidings() throws {
        var world = try SingleTrackMeet.world()
        try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east])
        let yard = try world.buildStation(named: "Y", at: PlanPoint(x: 13_312, y: 8_192)).id
        try world.addTrackPlatform(yard, on: .edge(2), from: 1_024, to: 3_072)
        let start = TrainPosition.onEdge(SingleTrackMeet.forward(1), offset: 3_072)
        let before = try XCTUnwrap(world.path(from: start, toStation: SingleTrackMeet.east))
        XCTAssertTrue(before.traversals.contains(SingleTrackMeet.forward(2)), "the main track is the shorter way")
        try world.setStationDepot(yard, to: true)
        let after = try XCTUnwrap(world.path(from: start, toStation: SingleTrackMeet.east))
        XCTAssertFalse(after.traversals.contains { $0.edge == .edge(2) }, "not over the depot's siding")
        XCTAssertTrue(after.traversals.contains(SingleTrackMeet.forward(5)), "round the loop")
        XCTAssertNotNil(world.path(from: start, toStation: yard), "into the depot")
        XCTAssertNotNil(world.path(from: .onEdge(SingleTrackMeet.forward(2), offset: 3_072), toStation: SingleTrackMeet.east), "out of it")
    }

    // MARK: - Out and in

    /// The first train leaves the depot a few minutes before the line's
    /// window opens at 06:00, runs empty to Alpha and is sent out on the
    /// line's first trip at 06:00 on the dot; with flexible dispatch off,
    /// as here, it goes to the first stop.
    func testTheFirstTrainLeavesTheDepotInTimeForTheFirstTrip() throws {
        var world = try makeWorld()
        XCTAssertFalse(world.flexDispatch)
        var leftAt: GameTime?
        while world.line(id: main)?.lastDispatch == nil {
            try world.advance(ticks: 1)
            if leftAt == nil, world.train(id: id(1))?.isDeadheading == true { leftAt = world.clock.now }
            XCTAssertLessThan(world.clock.now, GameTime(minutes: 420))
        }
        let left = try XCTUnwrap(leftAt)
        XCTAssertLessThan(left, GameTime(minutes: 360), "out of the depot before the window opens")
        XCTAssertGreaterThan(left, GameTime(minutes: 350), "not long before it")
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 360))
        XCTAssertEqual(world.train(id: id(1))?.timetable.first?.station, alpha)
        XCTAssertFalse(world.train(id: id(1))?.isDeadheading ?? true)
        XCTAssertGreaterThan(world.line(id: main)?.deadheadDistance ?? 0, 0, "the run out is empty running")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// Once the window has closed at midnight the train finishes its trip
    /// and runs empty into the depot, where it stands until the morning.
    func testAfterTheWindowClosesTheTrainGoesIntoTheDepot() throws {
        var world = try makeWorld(minutes: 1_380)
        try world.advance(ticks: 1_440 + 60 - 1_380)
        XCTAssertNil(world.train(id: id(1))?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [depot], "in the depot after midnight")
        // It stays there until the morning.
        try world.advance(ticks: 4 * 60)
        XCTAssertEqual(world.stationsStoppedAt(by: id(1)), [depot])
        XCTAssertNil(world.train(id: id(1))?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A line that runs fewer trains than it has sends out only those it
    /// runs; the others stay in the depot, and a train more than it runs
    /// that stands at a stop goes into the depot.
    func testOnlyTheTrainsTheLineRunsLeaveTheDepot() throws {
        var world = try makeWorld(trains: 2)
        try world.advance(ticks: 120)
        XCTAssertNotNil(world.train(id: id(1))?.execution ?? world.train(id: id(1))?.timetable.first, "the first runs")
        XCTAssertEqual(world.stationsStoppedAt(by: id(2)), [depot], "the second stays in the depot")
        XCTAssertNil(world.train(id: id(2))?.execution)

        var surplus = try makeWorld(trains: 2, minutes: 420, withDepot: false)
        try surplus.setStationDepot(depot, to: true)
        try surplus.setLineDepot(main, to: depot)
        try surplus.advance(ticks: 30)
        XCTAssertEqual(surplus.stationsStoppedAt(by: id(2)), [depot], "the train the line does not run goes into the depot")
        XCTAssertNotNil(surplus.line(id: main)?.lastDispatch, "the other runs the line")
        XCTAssertEqual(WorldInvariants.violations(in: surplus), [])
    }

    /// Without flexible dispatch a train left in a depot that is not its
    /// line's (the line was given none) runs empty to the line's first
    /// stop and is sent out from there.
    func testATrainLeftInADepotGoesBackToTheLine() throws {
        var world = try makeWorld(minutes: 420)
        try world.setLineDepot(main, to: nil)
        try world.advance(ticks: 30)
        XCTAssertNotNil(world.line(id: main)?.lastDispatch)
        XCTAssertNotEqual(world.stationsStoppedAt(by: id(1)), [depot])
    }

    /// With flexible dispatch the train goes out to whichever end is
    /// nearer: here Alpha, two links away rather than six.
    func testWithFlexibleDispatchItGoesToTheNearerEnd() throws {
        var world = try makeWorld(minutes: 350)
        world.setFlexDispatch(true)
        while world.train(id: id(1))?.isDeadheading != true {
            try world.advance(ticks: 1)
            XCTAssertLessThan(world.clock.now, GameTime(minutes: 360))
        }
        XCTAssertEqual(world.train(id: id(1))?.timetable.last?.station, alpha)
    }

    /// The whole night and morning in one call ends exactly where minute
    /// by minute does: the moves into and out of the depot wake the idle
    /// stretches at the right minutes.
    func testLongBatchesMatchSingleMinutes() throws {
        var batched = try makeWorld(trains: 2, minutes: 1_380)
        var single = batched
        try batched.advance(ticks: 9 * 60)
        for _ in 0..<(9 * 60) { try single.advance(ticks: 1) }
        XCTAssertEqual(batched, single)
        XCTAssertNotNil(batched.line(id: main)?.lastDispatch)
        XCTAssertEqual(batched.stationsStoppedAt(by: id(2)), [depot])
    }

    // MARK: - Costs

    /// A day in the depot pays the train's upkeep but not its energy and
    /// crew, and the depot's two sidings cost $400 each.
    func testATrainInTheDepotPaysOnlyItsUpkeep() throws {
        func day(withDepot: Bool) throws -> GameWorld {
            var world = try makeWorld(minutes: 0, withDepot: withDepot)
            try world.setTrainMovementRate(id(1), to: 0)
            world.setEconomyMode(.management)
            try world.advance(ticks: 1_441)
            return world
        }
        func row(_ kind: LedgerEntry.Kind, _ item: LedgerItem, in world: GameWorld) -> Money? {
            world.accounts.entries.last { $0.kind == kind }?.breakdown.first { $0.item == item }?.amount
        }
        let plain = try day(withDepot: false)
        let resting = try day(withDepot: true)
        XCTAssertEqual(row(.dailyEnergy, .trainEnergy, in: plain), Money(-36_000))
        XCTAssertEqual(row(.dailyStaff, .trainStaff, in: plain), Money(-48_000))
        XCTAssertEqual(row(.dailyEnergy, .trainEnergy, in: resting), .zero)
        XCTAssertEqual(row(.dailyStaff, .trainStaff, in: resting), .zero)
        XCTAssertEqual(row(.dailyDepot, .depotUpkeep, in: resting), Money(-80_000))
        XCTAssertNil(row(.dailyDepot, .depotUpkeep, in: plain))
        XCTAssertEqual(
            plain.accounts.entries.filter { $0.kind == .hourlyNet }.map(\.amount),
            resting.accounts.entries.filter { $0.kind == .hourlyNet }.map(\.amount),
            "the hourly upkeep is the same"
        )
        XCTAssertEqual(resting.accounts.depotHours, [], "cleared as the day is settled")
    }

    // MARK: - Saves

    func testADepotIsSavedAndReadBack() throws {
        var world = try makeWorld(minutes: 355)
        world.setEconomyMode(.management)
        try world.advance(ticks: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""depot":true,"#))
        XCTAssertTrue(text.contains(#""depot":1,"#))
        // A line's depot that is not a depot is refused.
        let broken = text.replacingOccurrences(of: #""depot":true,"#, with: "")
        XCTAssertNotEqual(broken, text)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(broken.utf8)))
    }

    /// Save version 54: a train on its way out of the depot just before
    /// 06:00, with the hours the accounts have counted.
    func testVersionFiftyFourKeepsTheDepot() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v54-depot.json")
        var made = try makeWorld(minutes: 0)
        made.setEconomyMode(.management)
        try made.advance(ticks: 358)
        XCTAssertTrue(made.train(id: id(1))?.isDeadheading ?? false, "on its way out")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DEPOT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 54)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertEqual(loaded.line(id: main)?.depot, depot)
        XCTAssertTrue(loaded.station(id: depot)?.isDepot ?? false)
        XCTAssertFalse(loaded.accounts.depotHours.isEmpty)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 54,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    /// A day's depot hours beyond what a day can count are refused: the
    /// next hour in the depot would overflow the sum and stop the game.
    func testDepotHoursBeyondTheCapAreRefused() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v54-depot.json")
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var world = try XCTUnwrap(object["world"] as? [String: Any])
        var accounts = try XCTUnwrap(world["accounts"] as? [String: Any])
        XCTAssertNotNil(accounts["depotHours"])
        accounts["depotHours"] = [["line": 1, "weightHours": Int64.max]]
        world["accounts"] = accounts
        object["world"] = world
        let broken = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: broken))
    }
}
