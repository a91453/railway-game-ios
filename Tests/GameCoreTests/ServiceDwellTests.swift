import Foundation
@testable import GameCore
import XCTest

/// Stage W2b (ARCHITECTURE decision 39): a service's dwell at each call, on
/// the game's clock, and the lateness worked out from its actual times. The
/// reference pack's W2 contract (`Railway/railway_game_reference_clean/
/// 02_W2_IMPLEMENTATION_CONTRACT.md`) asks for these: an arrival is
/// recorded, the least dwell holds with no passengers, boarding lengthens
/// the dwell predictably, an early train holds for its timetable and a late
/// one does not, and a save during a dwell restores it exactly.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. The clock runs at x10, one second a
/// tick, unless a test says otherwise. Between calls a train runs on its
/// running curve in the time its timetable gives the run (Stage W2c,
/// decision 40), or as fast as it can when that is too short.
final class ServiceDwellTests: XCTestCase {
    // On the track network (Stage F3b): nodes a (512, 1536) to g (6656,
    // 1536) a tile apart, edges 1 to 6 between them, dead ends at both
    // ends; Alpha, Beta and Gamma at the centres of tiles (1, 0), (3, 0) and
    // (5, 0), each with a platform either side of node b, d or f.
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)

    private func makeWorld(speed: GameSpeed = .x10) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: speed)
        )
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        return world
    }

    /// A stop at `arrival` and `departure` seconds.
    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(seconds: arrival), departure: GameTime(seconds: departure))
    }

    /// `run` is the start, length and seconds of a run (Stage W2c).
    private func times(
        _ arrival: Int64, _ exchangeEnd: Int64? = nil, _ closing: Int64? = nil, departure: Int64? = nil,
        run: (Int64, Int64, Int64)? = nil
    ) -> ServiceTimes {
        ServiceTimes(
            arrival: GameTime(seconds: arrival), exchangeEnd: exchangeEnd.map(GameTime.init(seconds:)),
            closing: closing.map(GameTime.init(seconds:)), departure: departure.map(GameTime.init(seconds:)),
            run: run.map { ServiceRun(start: GameTime(seconds: $0.0), length: $0.1, seconds: $0.2) }
        )
    }

    /// Advances to second `second`; the step at that second has not run.
    private func advance(_ world: inout GameWorld, to second: Int64, file: StaticString = #filePath, line: UInt = #line) throws {
        try world.advance(ticks: Int(second - world.clock.now.seconds))
        XCTAssertEqual(world.clock.now.seconds, second, file: file, line: line)
    }

    // MARK: - The rules

    /// The metro game's dwell and door times, its boarding rate through four
    /// doors a car, and the exchange rounded up to whole seconds.
    func testTheDwellRulesComeFromTheReferences() {
        XCTAssertEqual(ServiceDwell.minimum, 36)
        XCTAssertEqual(ServiceDwell.terminalMinimum, 42)
        XCTAssertEqual(ServiceDwell.doorOpening, 8)
        XCTAssertEqual(ServiceDwell.doorClosing, 9, "8.3 s rounded up")
        XCTAssertEqual(ServiceDwell.minimumDwell(isTerminal: false), 36)
        XCTAssertEqual(ServiceDwell.minimumDwell(isTerminal: true), 42)
        XCTAssertEqual(ServiceDwell.passengersPerSecond(cars: 1), 8)
        XCTAssertEqual(ServiceDwell.passengersPerSecond(cars: 6), 48)
        XCTAssertEqual(ServiceDwell.exchangeSeconds(0, cars: 1), 0)
        XCTAssertEqual(ServiceDwell.exchangeSeconds(1, cars: 1), 1)
        XCTAssertEqual(ServiceDwell.exchangeSeconds(8, cars: 1), 1)
        XCTAssertEqual(ServiceDwell.exchangeSeconds(9, cars: 1), 2)
        XCTAssertEqual(ServiceDwell.exchangeSeconds(352, cars: 1), 44)
        XCTAssertEqual(ServiceDwell.exchangeSeconds(2_112, cars: 6), 44)
    }

    // MARK: - Holding and lateness

    /// Alpha 0–60, Beta 120–120, Gamma 240–240 and Gamma again 360–420:
    ///
    /// - Alpha: started (arrived) at 0, an end: least dwell 42 s, but early,
    ///   so its doors close at 51 and it leaves at 60, on time, on the
    ///   minute's run to Beta.
    /// - Beta at 120, on time; between the ends, 36 s: doors closing at
    ///   147, it leaves at 156, 36 s late, with no hold for the timetable,
    ///   on the 2 minutes' run to Gamma.
    /// - Gamma at 276, 36 s late; 36 s again: it leaves at 312, and is at
    ///   once at its next call, Gamma again (a call at the station it is
    ///   at), 48 s early for 360. The last stop: it holds for its departure
    ///   at 420, doors closing at 411; the service ends at 420.
    func testAnEarlyTrainHoldsForItsTimetableAndALateOneDoesNot() throws {
        var world = try makeWorld()
        try world.setTrainMovementRate(one, to: 2_048)
        try world.setTrainTimetable(one, to: [stop(alpha, 0, 60), stop(beta, 120, 120), stop(gamma, 240, 240), stop(gamma, 360, 420)])
        try world.startTrainService(one)
        XCTAssertEqual(world.train(id: one)?.times, times(0))
        XCTAssertEqual(world.lateness(of: one), 0)

        try advance(&world, to: 9)
        XCTAssertEqual(world.train(id: one)?.times, times(0, 8), "no passengers: the exchange ends as the doors open")
        try advance(&world, to: 52)
        XCTAssertEqual(world.train(id: one)?.times, times(0, 8, 51))
        try advance(&world, to: 60)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(0))
        try advance(&world, to: 61)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1))
        XCTAssertEqual(world.train(id: one)?.times, times(0, departure: 60, run: (60, 2048, 60)))
        XCTAssertEqual(world.lateness(of: one), 0)

        try advance(&world, to: 120)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(1))
        XCTAssertEqual(world.train(id: one)?.times, times(120, departure: 60))
        XCTAssertEqual(world.lateness(of: one), 0)
        try advance(&world, to: 156)
        XCTAssertEqual(world.train(id: one)?.times, times(120, 128, 147, departure: 60))
        XCTAssertEqual(world.lateness(of: one), 36)
        try advance(&world, to: 157)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(2))
        XCTAssertEqual(world.train(id: one)?.times, times(120, departure: 156, run: (156, 2048, 120)))
        XCTAssertEqual(world.lateness(of: one), 36, "left Beta 36 s late, and not yet due at Gamma")

        try advance(&world, to: 276)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(2))
        XCTAssertEqual(world.train(id: one)?.times, times(276, departure: 156))
        XCTAssertEqual(world.lateness(of: one), 36, "arrived as late as it left")
        try advance(&world, to: 312)
        XCTAssertEqual(world.train(id: one)?.times, times(276, 284, 303, departure: 156))

        try advance(&world, to: 313)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(3))
        XCTAssertEqual(world.train(id: one)?.times, times(312, departure: 312))
        XCTAssertEqual(world.lateness(of: one), -48, "early: arrived 48 s before its scheduled arrival")
        try advance(&world, to: 420)
        XCTAssertEqual(world.train(id: one)?.times, times(312, 320, 411, departure: 312))
        XCTAssertEqual(world.lateness(of: one), -48, "still early until its departure has passed")
        try advance(&world, to: 421)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertNil(world.train(id: one)?.times)
        XCTAssertNil(world.lateness(of: one))
        XCTAssertNil(world.lateness(of: TrainID(rawValue: 9)))
    }

    // MARK: - Passengers

    /// One car, Main Alpha–Gamma: four links, 23 s a leg with the line's
    /// standard performance (√(2 × 4096 × 0.06) = 22.17 s), so sent out at
    /// 0 its trip leaves Alpha at 42, reaches Gamma at 65 and leaves it at
    /// 185. The train's top speed is 3 km/h (53⅓ units a second), which
    /// cannot keep 23 s: each run takes 79 s (4096 ÷ 53⅓ = 76.8 s cruising,
    /// and 53⅓ × 0.06 ÷ 2 = 1.6 s lost speeding up and slowing down).
    ///
    /// - 300 for Gamma board at 8: 38 s (300 / 8 a second, rounded up), so
    ///   the exchange ends at 46, past the least dwell's 33: the doors close
    ///   at 46 and the train leaves at 55, 13 s late.
    /// - Gamma at 134 (2:14): the 300 get off from 142 to 180.
    /// - At 3:00, with its doors still open (they would start closing at
    ///   180, the latest of the exchange, 134 + 42 − 9 and 185 − 9), 300
    ///   more come and board for Alpha: from 180, 38 s more, to 218: the
    ///   doors close at 218 and it leaves at 227, 42 s late.
    func testPassengersMakeTheDwellLongerAndBoardWhileTheDoorsAreOpen() throws {
        var world = try makeWorld()
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainPerformance(one, to: TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 3))
        try world.assignTrain(one, to: main)
        for station in [alpha, gamma] {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 0))
        }
        release(&world, 300, at: alpha, for: gamma, .outbound)

        try advance(&world, to: 9)
        XCTAssertEqual(world.riderCount(of: one), 300)
        XCTAssertEqual(world.train(id: one)?.times, times(0, 46))
        try advance(&world, to: 55)
        XCTAssertEqual(world.train(id: one)?.times, times(0, 46, 46))
        XCTAssertEqual(world.lateness(of: one), 13)
        try advance(&world, to: 56)
        XCTAssertEqual(world.train(id: one)?.times, times(0, departure: 55, run: (55, 4096, 79)))

        try advance(&world, to: 143)
        XCTAssertEqual(world.train(id: one)?.times, times(134, 180, departure: 55))
        XCTAssertEqual(world.riderCount(of: one), 0)
        XCTAssertEqual(world.passengerLedger(of: alpha).arrived, 300)

        try advance(&world, to: 180)
        release(&world, 300, at: gamma, for: alpha, .inbound, since: 3)
        try advance(&world, to: 181)
        XCTAssertEqual(world.riderCount(of: one), 300)
        XCTAssertEqual(world.train(id: one)?.times, times(134, 218, departure: 55))
        try advance(&world, to: 227)
        XCTAssertEqual(world.train(id: one)?.times, times(134, 218, 218, departure: 55))
        XCTAssertEqual(world.lateness(of: one), 42)
        try advance(&world, to: 228)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(2))
        XCTAssertEqual(world.train(id: one)?.times, times(134, departure: 227, run: (227, 4096, 79)))
    }

    /// Puts `count` passengers for `destination` in `station`'s queue, as
    /// released at minute `since` along Main.
    private func release(
        _ world: inout GameWorld, _ count: Int64, at station: StationID, for destination: StationID, _ direction: LineDirection, since: Int64 = 0
    ) {
        let index = world.passengers.firstIndex { $0.station == station }!
        world.passengers[index].release(count, to: destination, along: PassengerTrip(line: main, direction: direction), at: GameTime(minutes: since))
    }

    // MARK: - Batches and saves

    /// An idle minute that ends exactly when a dwell moves on skips nothing:
    /// the doors start closing at 120, on the minute, and the train leaves
    /// at 129 within one batch, as single ticks have it, on its 111 s run to
    /// Beta: 51 s along it by 3.
    func testAnIdleMinuteNeverSkipsAServiceEventOnTheMinute() throws {
        var start = try makeWorld(speed: .normal)
        try start.setTrainMovementRate(one, to: 1_024)
        try start.setTrainTimetable(one, to: [stop(alpha, 0, 129), stop(beta, 240, 240)])
        try start.startTrainService(one)

        var batch = start
        try batch.advance(ticks: 3)
        var single = start
        for _ in 0..<3 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(batch, single)
        XCTAssertEqual(batch.train(id: one)?.execution, .travellingToStop(1))
        XCTAssertEqual(batch.train(id: one)?.times, times(0, departure: 129, run: (129, 2048, 111)))
        XCTAssertEqual(batch.train(id: one)?.position, line.between(1, 2, offset: runDistance(2048, in: 111, after: 51)))
    }

    /// A save in the middle of a dwell, of the exchange or with the doors
    /// closing, loads back equal and carries on exactly as the world it was
    /// saved from.
    func testASaveDuringADwellRestoresItExactly() throws {
        var world = try makeWorld()
        try world.setTrainMovementRate(one, to: 2_048)
        try world.setTrainTimetable(one, to: [stop(alpha, 0, 60), stop(beta, 120, 120), stop(gamma, 240, 300)])
        try world.startTrainService(one)
        for second: Int64 in [4, 9, 52, 58, 61, 125, 150, 220, 295] {
            try advance(&world, to: second)
            var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
            XCTAssertEqual(loaded, world, "at \(second)")
            var carried = world
            try loaded.advance(ticks: 40)
            try carried.advance(ticks: 40)
            XCTAssertEqual(loaded, carried, "after \(second)")
        }
    }

    // MARK: - Saving the times

    /// `{"arrival": s}` plus the others only when set; an explicit `null`,
    /// or no arrival, is refused.
    func testServiceTimesAreSavedOnlyWhenSet() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(times(5)), as: UTF8.self), #"{"arrival":5}"#)
        XCTAssertEqual(
            String(decoding: try encoder.encode(times(5, 13, 40, departure: 2)), as: UTF8.self),
            #"{"arrival":5,"closing":40,"departure":2,"exchangeEnd":13}"#
        )
        for value in [times(5), times(5, 13), times(5, 13, 40, departure: 2), times(-7, departure: -9)] {
            XCTAssertEqual(try JSONDecoder().decode(ServiceTimes.self, from: encoder.encode(value)), value)
        }
        for text in [#"{}"#, #"{"arrival": null}"#, #"{"arrival": 5, "closing": null}"#, #"{"arrival": 5, "exchangeEnd": "13"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ServiceTimes.self, from: Data(text.utf8)), text)
        }
    }
}
