import Foundation
@testable import GameCore
import XCTest

/// Realistic operation, first stage (ARCHITECTURE decision 206): with the
/// world's switch on, a line plans its legs at its performance's usual
/// rates with a recovery margin, dwells by its kind or as set, a late train
/// makes up its margin, and each line counts its trips' punctuality. Off,
/// as in every world before it, nothing changes.
final class RealisticOperationTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private static let track = TestLine(tiles: 40)

    /// A straight track of 40 tiles (624 m between the first and last
    /// stations' nodes) with A at column 1, B at 20 and C at 38, and the
    /// line Main A–B–C running all day; managed, with line accounts.
    private func build(realistic: Bool, performance: TrainPerformance = .standard) throws -> GameWorld {
        var world = try makeWorld(width: 40 * TestLine.tile, height: 4 * TestLine.tile, balance: 10_000_000)
        try Self.track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 20), ("C", 38)] {
            try Self.track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        try world.createLine(named: "Main", stops: [a, b, c])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.setLinePerformance(main, to: performance)
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        world.setRealisticOperation(realistic)
        return world
    }

    private func trainOnLine(_ world: inout GameWorld) throws -> TrainID {
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: Self.track.at(1, facingEast: true))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: main)
        world.setSpeed(.normal)
        return train
    }

    // MARK: Planning

    func testUsualRatesAreTheRatesWithoutTheFallbacks() {
        let usual = TrainPerformance.highSpeed.usualRates
        XCTAssertEqual(usual, TrainPerformance(acceleration: 1400, braking: 1500, topSpeed: 300, coast: TrainPerformance.highSpeed.coast))
        XCTAssertEqual(TrainPerformance.standard.usualRates, .standard, "no fallbacks to drop")
    }

    func testOffALinePlansItsLeastSecondsAndAMinutesDwell() throws {
        let world = try build(realistic: false, performance: .highSpeed)
        let journey = try XCTUnwrap(world.lineJourney(main))
        for leg in journey.legs {
            XCTAssertEqual(leg.seconds, RunningCurve.leastSeconds(length: leg.path.distance, performance: .highSpeed))
        }
        XCTAssertEqual(journey.dwellSeconds, 60)
        XCTAssertEqual(journey.terminalDwellSeconds, 120)
        let running: Int64 = journey.legs.map(\.seconds).reduce(0, +)
        XCTAssertEqual(journey.roundTripSeconds, running + 2 * 120 + 2 * 60)
    }

    func testOnALinePlansTheUsualRatesWithAMarginAndAHighSpeedDwell() throws {
        let world = try build(realistic: true, performance: .highSpeed)
        let journey = try XCTUnwrap(world.lineJourney(main))
        for leg in journey.legs {
            let usual = try XCTUnwrap(RunningCurve.leastSeconds(length: leg.path.distance, performance: TrainPerformance.highSpeed.usualRates))
            XCTAssertEqual(leg.seconds, usual + (usual * 4 + 99) / 100)
            let fastest = try XCTUnwrap(RunningCurve.leastSeconds(length: leg.path.distance, performance: .highSpeed))
            XCTAssertGreaterThan(usual, fastest, "the fallback rates are faster over a short leg")
        }
        XCTAssertEqual(journey.dwellSeconds, 110, "a high-speed line dwells as the real all-stops trains do")
        XCTAssertEqual(journey.terminalDwellSeconds, 120)
        let running: Int64 = journey.legs.map(\.seconds).reduce(0, +)
        XCTAssertEqual(journey.roundTripSeconds, running + 2 * 120 + 2 * 110)
        // The timetable a train is sent out on dwells as planned.
        let trip = LineTrip(turnsFirst: false, journey: journey)
        let timetable = try XCTUnwrap(trip.timetable(calling: [a, b, c], sentOutAt: GameTime(seconds: 0)))
        XCTAssertEqual(timetable[1].departure.seconds - timetable[1].arrival.seconds, 110)
        XCTAssertEqual(timetable[2].departure.seconds - timetable[2].arrival.seconds, 120)
    }

    func testAStandardLineDwellsAMinuteEitherWay() throws {
        let world = try build(realistic: true)
        let journey = try XCTUnwrap(world.lineJourney(main))
        XCTAssertEqual(journey.dwellSeconds, 60)
        for leg in journey.legs {
            let least = try XCTUnwrap(RunningCurve.leastSeconds(length: leg.path.distance, performance: .standard))
            XCTAssertEqual(leg.seconds, least + (least * 4 + 99) / 100, "no fallbacks: the margin alone")
        }
    }

    // MARK: A line's dwell

    func testALinesOwnDwell() throws {
        var world = try build(realistic: false)
        XCTAssertThrowsGameError(try world.setLineDwell(LineID(rawValue: 9), seconds: 90), .unknownLine(LineID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.setLineDwell(main, seconds: 35), .invalidLineDwell)
        XCTAssertThrowsGameError(try world.setLineDwell(main, seconds: 601), .invalidLineDwell)
        try world.setLineDwell(main, seconds: 36)
        XCTAssertEqual(world.lineJourney(main)?.dwellSeconds, 36)
        try world.setLineDwell(main, seconds: 200)
        let journey = try XCTUnwrap(world.lineJourney(main))
        XCTAssertEqual(journey.dwellSeconds, 200)
        XCTAssertEqual(journey.terminalDwellSeconds, 200, "a terminal dwells at least as long")
        try world.setLineDwell(main, seconds: nil)
        XCTAssertEqual(world.lineJourney(main)?.dwellSeconds, 60)
    }

    func testALinesDwellIsSavedOnlyWhenSetAndAnOutOfRangeOneIsRefused() throws {
        var world = try build(realistic: false)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains("dwellSeconds"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains("realisticOperation"))
        try world.setLineDwell(main, seconds: 90)
        world.setRealisticOperation(true)
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""dwellSeconds":90"#))
        XCTAssertTrue(text.contains(#""realisticOperation":true"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)
        for bad in ["35", "601"] {
            let broken = text.replacingOccurrences(of: #""dwellSeconds":90"#, with: #""dwellSeconds":\#(bad)"#)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
    }

    // MARK: Recovery

    /// The train Blue waiting at A on Main's timetable, which leaves at the
    /// clock's time: on time, and the same train as though its timetable
    /// had been 40 s earlier, so that it leaves 40 s late.
    private func departing(realistic: Bool) throws -> (world: GameWorld, onTime: Train, late: Train) {
        var world = try build(realistic: realistic, performance: .highSpeed)
        let id = try trainOnLine(&world)
        try world.setTrainPerformance(id, to: .highSpeed)
        var train = try XCTUnwrap(world.train(id: id))
        let journey = try XCTUnwrap(world.lineJourney(main))
        let now = world.clock.now.seconds
        func shifted(by seconds: Int64) throws -> Train {
            let timetable = try XCTUnwrap(LineTrip(turnsFirst: false, journey: journey).timetable(calling: [a, b, c], sentOutAt: GameTime(seconds: 0)))
            let lead = timetable[0].departure.seconds
            var moved = train
            moved.timetable = timetable.map {
                ScheduledStop(station: $0.station, arrival: GameTime(seconds: now + $0.arrival.seconds - lead - seconds),
                              departure: GameTime(seconds: now + $0.departure.seconds - lead - seconds), reverses: $0.reverses)
            }
            moved.execution = .waitingAtStop(0, cycle: 0)
            moved.times = ServiceTimes(arrival: GameTime(seconds: now))
            return moved
        }
        train = try shifted(by: 0)
        return (world, train, try shifted(by: 40))
    }

    private func runSeconds(_ leaving: GameWorld.Leaving) throws -> Int64 {
        guard case .setsOff(let train, _) = leaving else { throw XCTSkip("the train did not set off") }
        return try XCTUnwrap(train.times?.run?.seconds)
    }

    func testALateTrainMakesUpItsMargin() throws {
        let (world, onTime, late) = try departing(realistic: true)
        let planned = onTime.timetable[1].arrival.seconds - onTime.timetable[0].departure.seconds
        XCTAssertEqual(try runSeconds(world.leaving(onTime, stop: 0, cycle: 0)), planned, "on time, its planned leg")
        let lateRun = try runSeconds(world.leaving(late, stop: 0, cycle: 0))
        let leg = try XCTUnwrap(world.lineJourney(main)?.legs.first)
        let fastest = try XCTUnwrap(RunningCurve.leastSeconds(length: leg.path.distance, performance: .highSpeed))
        XCTAssertEqual(lateRun, max(fastest, planned - 40), "late, it runs faster, never below its least time")
        XCTAssertLessThan(lateRun, planned)
    }

    func testOffALateTrainArrivesAsLate() throws {
        let (world, onTime, late) = try departing(realistic: false)
        let planned = onTime.timetable[1].arrival.seconds - onTime.timetable[0].departure.seconds
        XCTAssertEqual(try runSeconds(world.leaving(late, stop: 0, cycle: 0)), planned, "the timetable's time, from departure to arrival")
    }

    // MARK: Punctuality

    func testALineCountsItsTripsOnlyWithRealisticOperation() throws {
        for realistic in [false, true] {
            var world = try build(realistic: realistic)
            _ = try trainOnLine(&world)
            try world.advance(ticks: 1_440 + 30)
            let tally = world.lineDays(main).reduce(LineTally()) { var sum = $0; sum.add($1.tally); return sum }
            XCTAssertGreaterThan(tally.departures, 0)
            if realistic {
                XCTAssertGreaterThan(tally.trips, 0, "every trip that reached its last call")
                XCTAssertEqual(tally.lateTrips, 0, "one train on its own line keeps time")
                XCTAssertEqual(tally.punctualityPermille, 1_000)
            } else {
                XCTAssertEqual(tally.trips, 0)
                XCTAssertNil(tally.punctualityPermille)
            }
        }
    }

    func testATallyWithoutTripsReadsAsBeforeAndOneWithThemKeepsThem() throws {
        var tally = LineTally()
        tally.departures = 3
        let plain = String(decoding: try JSONEncoder().encode(tally), as: UTF8.self)
        XCTAssertFalse(plain.contains("trips"), "written only with trips")
        XCTAssertEqual(try JSONDecoder().decode(LineTally.self, from: Data(plain.utf8)), tally)
        tally.trips = 10
        tally.lateTrips = 3
        XCTAssertEqual(tally.punctualityPermille, 700)
        let text = String(decoding: try JSONEncoder().encode(tally), as: UTF8.self)
        XCTAssertEqual(try JSONDecoder().decode(LineTally.self, from: Data(text.utf8)), tally)
        XCTAssertTrue(tally.isValid)
        tally.lateTrips = 11
        XCTAssertFalse(tally.isValid, "no more late trips than trips")
    }

    // MARK: Save version 53

    func testVersionFiftyThreeKeepsRealisticOperation() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v53-realistic-operation.json")
        var made = try build(realistic: true, performance: .highSpeed)
        try made.setLineDwell(main, seconds: 90)
        _ = try trainOnLine(&made)
        try made.advance(ticks: 3 * 60)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["REALISTIC_OPERATION_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 53)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertTrue(loaded.realisticOperation)
        XCTAssertEqual(loaded.line(id: main)?.dwellSeconds, 90)
        XCTAssertGreaterThan(loaded.lineDays(main).reduce(0) { $0 + $1.tally.trips }, 0, "it has counted trips")
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 53,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
