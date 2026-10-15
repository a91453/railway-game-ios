import Foundation
@testable import GameCore
import XCTest

/// The trip log (ARCHITECTURE decision 223, point 5): each train's trips of
/// today and yesterday, the times of every call, and its line's share of
/// the fares.
final class TrainTripLogTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let first = LineID(rawValue: 1)
    private let second = LineID(rawValue: 2)
    private let one = TrainID(rawValue: 1)
    private let two = TrainID(rawValue: 2)

    /// `LineAccountsTests`' two lines, A–B and B–C, with the people of A and
    /// C going to each other: every trip changes at B.
    private func build(accounts: Bool = true, managed: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        try world.createLine(named: "First", stops: [a, b])
        try world.createLine(named: "Second", stops: [b, c])
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: track.at(1, facingEast: true))
        try world.placeTrain(two, at: track.at(3, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_500))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 1_500))
        world.setPassengerRoutingMode(.network)
        if managed { world.setEconomyMode(.management) }
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        return world
    }

    /// Every trip a line's train ran: from its line's first stop round to
    /// it again, every call timed, each left before the next, and the
    /// whole trip as its line counts it for punctuality.
    func testEachTripHasEveryCallTimed() throws {
        var world = try build()
        try world.advance(ticks: 600)
        let trips = world.trips(of: one)
        XCTAssertGreaterThan(trips.count, 3)
        let finished = trips.filter { !$0.isRunning }
        XCTAssertFalse(finished.isEmpty)
        for trip in finished {
            XCTAssertEqual(trip.line, first)
            XCTAssertEqual(trip.from, a)
            XCTAssertEqual(trip.to, a, "a round trip comes back")
            XCTAssertEqual(trip.calls.map(\.station), [a, b, a])
            XCTAssertFalse(trip.isInterrupted)
            XCTAssertFalse(trip.isDeadhead)
            XCTAssertEqual(trip.arrival, trip.calls.last?.arrival)
            XCTAssertNotNil(trip.departure)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(trip.departure), trip.sentOut)
            for (call, next) in zip(trip.calls, trip.calls.dropFirst()) {
                XCTAssertLessThanOrEqual(try XCTUnwrap(call.departure), next.arrival)
            }
            XCTAssertNotNil(trip.delay)
            XCTAssertLessThanOrEqual(trip.scheduledDeparture, trip.scheduledArrival)
        }
        // One after another: each trip sent out after the one before ended.
        for (earlier, later) in zip(trips, trips.dropFirst()) {
            XCTAssertLessThanOrEqual(try XCTUnwrap(earlier.arrival), later.sentOut)
        }
        // Only the last may still run.
        XCTAssertTrue(trips.dropLast().allSatisfy { !$0.isRunning })
        XCTAssertEqual(world.tripLog.map(\.train), world.tripLog.map(\.train).sorted())
    }

    /// The trips take the share of the fares their line was given, so
    /// they add up to at most the line's fares; on the second line, whose
    /// riders all paid at A, to less.
    func testTheTripsFaresAddUpToAtMostTheLines() throws {
        var world = try build()
        try world.advance(ticks: 1_440 + 600)
        func lineFares(_ line: LineID) -> Money {
            let book = world.lineAccounts!.records(of: line)!
            return book.days.reduce(book.pending.fareRevenue) { $0 + $1.tally.fareRevenue }
        }
        func tripFares(_ train: TrainID) -> Money {
            world.trips(of: train).reduce(.zero) { $0 + $1.fare }
        }
        // Nothing dropped yet: the log holds every trip since the start.
        XCTAssertEqual(world.trips(of: one).first?.sentOut, world.trips(of: one).map(\.sentOut).min())
        XCTAssertGreaterThan(tripFares(one), .zero)
        XCTAssertLessThanOrEqual(tripFares(one), lineFares(first))
        XCTAssertLessThan(tripFares(two), lineFares(second), "a rider who changes paid at A")
        XCTAssertGreaterThan(world.trips(of: one).reduce(0) { $0 + $1.boarded }, 0)
        XCTAssertGreaterThan(world.trips(of: two).reduce(0) { $0 + $1.boarded }, 0)
        XCTAssertTrue(world.tripLog.allSatisfy { $0.fare >= .zero && $0.boarded >= 0 })
    }

    /// The log keeps today and yesterday: at every midnight the day before
    /// yesterday goes.
    func testOnlyTodayAndYesterdayAreKept() throws {
        var world = try build()
        try world.advance(ticks: 3 * 1_440 + 120)
        let today = world.dayIndex(of: world.clock.now)
        let days = Set(world.tripLog.map { world.dayIndex(of: $0.sentOut) })
        XCTAssertEqual(days, [today - 1, today])
        // Without a managed company no midnight is settled; the log still
        // drops the old days as trains are sent out.
        var free = try build(managed: false)
        try free.advance(ticks: 3 * 1_440 + 120)
        XCTAssertFalse(free.tripLog.isEmpty)
        XCTAssertTrue(free.tripLog.allSatisfy { free.dayIndex(of: $0.sentOut) >= today - 1 })
        XCTAssertEqual(free.tripLog.reduce(.zero) { $0 + $1.fare }, .zero, "a free company takes no fares")
    }

    /// Kept with the line accounts: without them, nothing is logged.
    func testWithoutLineAccountsNothingIsLogged() throws {
        var world = try build(accounts: false)
        try world.advance(ticks: 600)
        XCTAssertEqual(world.tripLog, [])
        // Turning the accounts off drops the log with them.
        var on = try build()
        try on.advance(ticks: 600)
        XCTAssertFalse(on.tripLog.isEmpty)
        on.setLineAccounts(false)
        XCTAssertEqual(on.tripLog, [])
        try on.advance(ticks: 60)
        XCTAssertEqual(on.tripLog, [])
    }

    /// The log is a record only: batched and minute by minute give the
    /// same world, it saves and loads, and turning it off changes nothing
    /// else.
    func testTheLogChangesNothingElseAndSaves() throws {
        var batched = try build()
        var stepped = batched
        try batched.advance(ticks: 1_500)
        for _ in 0..<1_500 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        XCTAssertFalse(loaded.tripLog.isEmpty)
        // A world whose log is cleared runs on the same, but for the log.
        var cleared = batched
        cleared.tripLog = []
        var kept = batched
        try cleared.advance(ticks: 200)
        try kept.advance(ticks: 200)
        cleared.tripLog = []
        kept.tripLog = []
        XCTAssertEqual(cleared, kept)
    }

    /// A service stopped on the way ends its trip there, interrupted; a
    /// train taken off its line finishes its trip first.
    func testAStoppedServiceInterruptsItsTrip() throws {
        var world = try build()
        while !(world.trips(of: one).last?.isRunning ?? false) { try world.advance(ticks: 1) }
        let running = try XCTUnwrap(world.trips(of: one).last)
        XCTAssertTrue(running.isRunning)
        try world.unassignTrain(one)
        XCTAssertTrue(try XCTUnwrap(world.trips(of: one).last).isRunning, "still on its way")
        try world.stopTrainService(one)
        let stopped = try XCTUnwrap(world.trips(of: one).last)
        XCTAssertEqual(stopped.sentOut, running.sentOut)
        XCTAssertTrue(stopped.isInterrupted)
        XCTAssertEqual(stopped.arrival, world.clock.now)
        XCTAssertNil(stopped.delay)
        XCTAssertNil(stopped.isLate)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// A late arrival is late as a line's punctuality counts it.
    func testDelayIsCountedAsTheLinesPunctuality() {
        var trip = TrainTrip(train: one, line: first, from: a, to: b, scheduledDeparture: GameTime(seconds: 0),
                             scheduledArrival: GameTime(seconds: 600), isDeadhead: false,
                             calls: [TripCall(station: a, arrival: GameTime(seconds: 0), departure: GameTime(seconds: 60))])
        XCTAssertNil(trip.delay)
        trip.calls.append(TripCall(station: b, arrival: GameTime(seconds: 600 + GameWorld.punctualSeconds)))
        trip.arrival = trip.calls.last?.arrival
        XCTAssertEqual(trip.delay, GameWorld.punctualSeconds)
        XCTAssertEqual(trip.isLate, false, "five minutes is on time")
        trip.calls[1] = TripCall(station: b, arrival: GameTime(seconds: 601 + GameWorld.punctualSeconds))
        trip.arrival = trip.calls.last?.arrival
        XCTAssertEqual(trip.isLate, true)
        XCTAssertTrue(trip.isValid)
    }

    /// A log that breaks its rules is refused: out of order, two trips of
    /// a train running, calls out of time, or a train never bought.
    func testABrokenLogIsRefused() throws {
        var world = try build()
        try world.advance(ticks: 600)
        let data = try JSONEncoder().encode(world)
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: data))
        func refuses(_ change: (inout [[String: Any]]) -> Void, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
            var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var log = try XCTUnwrap(object["tripLog"] as? [[String: Any]])
            change(&log)
            object["tripLog"] = log
            let broken = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: broken), message, file: file, line: line)
        }
        try refuses({ $0.reverse() }, "out of order")
        try refuses({ log in
            let index = log.firstIndex { ($0["train"] as? Int) == 1 && $0["arrival"] != nil }!
            log[index]["arrival"] = nil
        }, "an earlier trip still running")
        try refuses({ log in
            var calls = log[0]["calls"] as! [[Int]]
            calls[0] = [calls[0][0], calls[0][1], calls[0][1] - 1]
            log[0]["calls"] = calls
        }, "a call left before it arrived")
        try refuses({ $0[0]["calls"] = [] as [Any] }, "no calls")
        try refuses({ $0[$0.count - 1]["train"] = 99 }, "a train never bought")
        try refuses({ $0[0]["fare"] = -100 }, "a negative fare")
        // Beyond the caps the line's takings keep: the next riders would
        // overflow the sum and stop the game.
        try refuses({ $0[0]["fare"] = Int64.max }, "a fare beyond the cap")
        try refuses({ $0[0]["boarded"] = Int64.max }, "riders beyond the cap")
    }

    /// A save of version 60: the two lines run past midnight, so the log
    /// holds yesterday's trips and today's, one of them still running. It saves byte for byte and is the world this build makes.
    func testVersionSixtyKeepsTheTripLog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v60-trip-log.json")
        // The accounts (and so the log) on from 23:40, so the fixture holds
        // an hour of trips across midnight rather than a day and a half of
        // them.
        var made = try build(accounts: false)
        try made.advance(ticks: 1_420)
        made.setLineAccounts(true)
        try made.advance(ticks: 50)
        while !made.tripLog.contains(where: \.isRunning) { try made.advance(ticks: 1) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TRIP_LOG_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 60)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        let today = world.dayIndex(of: world.clock.now)
        XCTAssertEqual(Set(world.tripLog.map { world.dayIndex(of: $0.sentOut) }), [today - 1, today])
        XCTAssertTrue(world.tripLog.contains(where: \.isRunning))
        XCTAssertTrue(world.tripLog.contains { $0.fare > .zero })
        var carried = world
        var straight = made
        try carried.advance(ticks: 40)
        try straight.advance(ticks: 40)
        XCTAssertEqual(carried, straight)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 60,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    /// A save from before the log has none, and logs from the next trip
    /// on: a trip already on its way is not logged halfway.
    func testAnOlderSaveStartsAnEmptyLog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v48-line-accounts.json")
        var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: url)).world
        XCTAssertEqual(world.tripLog, [])
        XCTAssertNotNil(world.lineAccounts)
        try world.advance(ticks: 300)
        XCTAssertFalse(world.tripLog.isEmpty)
        XCTAssertTrue(world.tripLog.allSatisfy { $0.calls.first?.station == $0.from })
    }
}
