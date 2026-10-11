import Foundation
@testable import GameCore
import XCTest

/// Door crowding (ARCHITECTURE decision 169): the crowd at a train's doors
/// slows the passengers going through them, `ceil(count ÷ rate × (1 + 1.5 ×
/// crowd⁴))`, where the crowd is the larger of the riders over what the train
/// is rated for and the passengers waiting over what a station holds, taken
/// when the doors have opened.
///
/// Expected values are worked out by hand from the rule and written out,
/// never taken from a previous run. The clock runs at x10, one second a tick.
final class DoorCrowdingTests: XCTestCase {
    // As ServiceDwellTests: nodes a to g a tile apart, edges 1 to 6 between
    // them; Alpha, Beta and Gamma at tiles (1, 0), (3, 0) and (5, 0).
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)

    // MARK: - The rule

    /// 1 + 1.5 × crowd⁴ in thousandths, each power rounded down to a
    /// thousandth: at 0.3 the square is 90 and the fourth power 8, so 1,012;
    /// at 0.5 they are 250 and 62, 1,093; at 0.8 they are 640 and 409, 1,613;
    /// at 1.0 they are 1,000 and 1,000, 2,500; at the limit 1.1 they are
    /// 1,210 and 1,464, 1,000 + 1,500 × 1,464 ÷ 1,000 = 3,196.
    func testTheMultiplierIsOnePlusOneAndAHalfTimesTheFourthPower() {
        XCTAssertEqual(DoorCrowding.limit, 1_100)
        XCTAssertEqual(DoorCrowding.coefficient, 1_500)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 0), 1_000)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 75), 1_000, "a light crowd changes nothing")
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 300), 1_012)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 500), 1_093)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 800), 1_613)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 1_000), 2_500)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 1_100), 3_196)
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 5_000), 3_196, "the crowd counts up to the limit")
        XCTAssertEqual(DoorCrowding.multiplier(crowd: -40), 1_000)
        // 937 is 300 riders of a 320-rated car: 877 and 769, so 2,153.
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 937), 2_153)
        // 750 is 3,000 waiting of a station's 4,000: 562 and 315, so 1,472.
        XCTAssertEqual(DoorCrowding.multiplier(crowd: 750), 1_472)
    }

    /// 300 at 8 a second take 37.5 s, 38 whole; in each crowd the time is
    /// 300 × multiplier ÷ 8,000 rounded up.
    func testAnExchangeTakesTheMultipliersShareLongerRoundedUp() {
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 0), 38)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 75), 38)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 500), 41, "327,900 ÷ 8,000 = 40.99")
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 800), 61, "483,900 ÷ 8,000 = 60.49")
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 937), 81, "645,900 ÷ 8,000 = 80.74")
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 1_000), 94, "750,000 ÷ 8,000 = 93.75")
        XCTAssertEqual(DoorCrowding.exchangeSeconds(300, rate: 8, crowd: 1_100), 120, "958,800 ÷ 8,000 = 119.85")
        XCTAssertEqual(DoorCrowding.exchangeSeconds(352, rate: 8, crowd: 750), 65, "518,144 ÷ 8,000 = 64.77")
        // Nobody to pass takes no time; one passenger takes a second.
        XCTAssertEqual(DoorCrowding.exchangeSeconds(0, rate: 8, crowd: 1_100), 0)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(1, rate: 8, crowd: 1_000), 1)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(3, rate: 1, crowd: 1_000), 8, "7,500 ÷ 1,000 = 7.5")
        // With no crowd it is the rate's alone, as before decision 169.
        for cars in 1...16 {
            let rate = ServiceDwell.passengersPerSecond(cars: cars)
            for count in Int64(0)...600 {
                XCTAssertEqual(DoorCrowding.exchangeSeconds(count, rate: rate, crowd: 0), ServiceDwell.exchangeSeconds(count, cars: cars), "\(count) in \(cars) cars")
            }
        }
    }

    /// The crowd never shortens an exchange, grows with the crowd and with
    /// the count, and at the limit is at most 3.2 times the uncrowded time
    /// and a second.
    func testACrowdOnlyLengthensAnExchange() {
        var previous = Int64(1_000)
        for crowd in Int64(0)...1_100 {
            let now = DoorCrowding.multiplier(crowd: crowd)
            XCTAssertGreaterThanOrEqual(now, previous, "at \(crowd)")
            previous = now
        }
        for rate in [1, 8, 24, 48, 160] as [Int64] {
            for count in [1, 7, 100, 352, 1_716, 5_632] as [Int64] {
                let uncrowded = DoorCrowding.exchangeSeconds(count, rate: rate, crowd: 0)
                var last = uncrowded
                for crowd in stride(from: Int64(0), through: 1_100, by: 25) {
                    let seconds = DoorCrowding.exchangeSeconds(count, rate: rate, crowd: crowd)
                    XCTAssertGreaterThanOrEqual(seconds, last, "rate \(rate), \(count) at \(crowd)")
                    last = seconds
                }
                XCTAssertLessThanOrEqual(last, uncrowded * 32 / 10 + 1, "rate \(rate), \(count)")
            }
        }
    }

    /// The crowd is the larger of the train's riders over what it is rated
    /// for (not what it takes, 1.1 of that) and the station's waiting over
    /// 4,000, at most 1,100.
    func testTheCrowdIsTheLargerOfTheTrainsAndTheStations() {
        XCTAssertEqual(StationPassengers.capacity, 4_000)
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 320, waiting: 0), 0)
        XCTAssertEqual(DoorCrowding.crowd(riders: 160, rated: 320, waiting: 0), 500)
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 320, waiting: 2_000), 500)
        XCTAssertEqual(DoorCrowding.crowd(riders: 160, rated: 320, waiting: 3_000), 750, "the platform's is the larger")
        XCTAssertEqual(DoorCrowding.crowd(riders: 300, rated: 320, waiting: 400), 937, "the train's is the larger")
        XCTAssertEqual(DoorCrowding.crowd(riders: 352, rated: 320, waiting: 0), 1_100, "full to what it takes")
        XCTAssertEqual(DoorCrowding.crowd(riders: 640, rated: 640, waiting: 0), 1_000, "a high-speed set takes no more than it is rated")
        XCTAssertEqual(DoorCrowding.crowd(riders: 9_999, rated: 320, waiting: 0), 1_100)
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 320, waiting: 4_000), 1_000, "a full station")
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 320, waiting: 9_000), 1_100)
        XCTAssertEqual(DoorCrowding.crowd(riders: -5, rated: 320, waiting: -5), 0)
        XCTAssertEqual(DoorCrowding.crowd(riders: 10, rated: 0, waiting: 0), 0, "a train rated for no one has no crowd")
    }

    /// Where the doors are few for the people the dwell grows past the
    /// metro game's 36 s: a full six-car monorail (224 a car, 2 doors, so
    /// 24 a second) at 1,344, of whom 700 get off and 700 get on, takes 30 s
    /// uncrowded (700 ÷ 24 = 29.17) and 1,000 crowd's 2,500 makes it 73 s
    /// (1,750,000 ÷ 24,000 = 72.9), with the doors' 8 s and 9 s 90 s;
    /// a six-car A train (310 a car, 5 doors, 60 a second) with the same
    /// exchange takes 12 s and 30 s, and so 47 s.
    func testFewDoorsForTheRidersLengthenTheDwellMost() {
        XCTAssertEqual(DoorCrowding.exchangeSeconds(700, rate: 2 * 2 * 6, crowd: 0), 30)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(700, rate: 2 * 2 * 6, crowd: 1_000), 73)
        XCTAssertEqual(ServiceDwell.doorOpening + 73 + ServiceDwell.doorClosing, 90)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(700, rate: 2 * 5 * 6, crowd: 0), 12)
        XCTAssertEqual(DoorCrowding.exchangeSeconds(700, rate: 2 * 5 * 6, crowd: 1_000), 30)
        XCTAssertEqual(ServiceDwell.doorOpening + 30 + ServiceDwell.doorClosing, 47)
        var train = Train(id: TrainID(rawValue: 1), name: "T")
        train.cars = 6
        train.type = .monorail
        XCTAssertEqual(train.ratedCapacity, 1_344)
        XCTAssertEqual(train.exchangeSeconds(700, crowd: 1_000), 73)
        train.type = .a
        XCTAssertEqual(train.exchangeSeconds(700, crowd: 1_000), 30)
        XCTAssertEqual(train.exchangeSeconds(700), 12, "no crowd given: as before")
    }

    // MARK: - The world

    func testItIsOffInANewWorldAndSavedOnlyWhenOn() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000, costs: testCosts))
        XCTAssertFalse(world.doorCrowding)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let off = String(decoding: try encoder.encode(world), as: UTF8.self)
        XCTAssertFalse(off.contains("doorCrowding"), "a world without it writes none, as saves from before it")
        let before = world
        world.setDoorCrowding(false)
        XCTAssertEqual(world, before, "turning it off when it is off changes nothing")
        world.setDoorCrowding(true)
        XCTAssertTrue(world.doorCrowding)
        let on = String(decoding: try encoder.encode(world), as: UTF8.self)
        XCTAssertTrue(on.contains(#""doorCrowding":true"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(on.utf8)), world)
        // A save without it reads as off; a wrong kind is refused.
        XCTAssertFalse(try JSONDecoder().decode(GameWorld.self, from: Data(off.utf8)).doorCrowding)
        let wrong = on.replacingOccurrences(of: #""doorCrowding":true"#, with: #""doorCrowding":"yes""#)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(wrong.utf8)))
        world.setDoorCrowding(false)
        XCTAssertEqual(world, before)
    }

    /// One one-car train between Alpha and Gamma on the line Main, as
    /// ServiceDwellTests runs it, its rate 1,024 and its performance a quick
    /// 1,500 / 2,500 / 3, with no demand of the stations' own.
    private func makeWorld(crowding: Bool) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .x10)
        )
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        world.setDoorCrowding(crowding)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainPerformance(one, to: TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 3))
        try world.assignTrain(one, to: main)
        for station in [alpha, gamma] {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 0))
        }
        return world
    }

    private func release(
        _ world: inout GameWorld, _ count: Int64, at station: StationID, for destination: StationID, _ direction: LineDirection, since: Int64 = 0
    ) {
        let index = world.passengers.firstIndex { $0.station == station }!
        world.passengers[index].release(count, to: destination, along: PassengerTrip(line: main, direction: direction), at: GameTime(minutes: since))
    }

    private func times(
        _ arrival: Int64, _ exchangeEnd: Int64? = nil, _ closing: Int64? = nil, departure: Int64? = nil
    ) -> ServiceTimes {
        ServiceTimes(
            arrival: GameTime(seconds: arrival), exchangeEnd: exchangeEnd.map(GameTime.init(seconds:)),
            closing: closing.map(GameTime.init(seconds:)), departure: departure.map(GameTime.init(seconds:))
        )
    }

    private func advance(_ world: inout GameWorld, to second: Int64, file: StaticString = #filePath, line: UInt = #line) throws {
        try world.advance(ticks: Int(second - world.clock.now.seconds))
        XCTAssertEqual(world.clock.now.seconds, second, file: file, line: line)
    }

    /// ServiceDwellTests' second test, the same run: 300 board at Alpha, the
    /// train arrives at Gamma at 134 and its doors have opened at 142.
    ///
    /// - Off, the 300 get off in 38 s, to 180 (the original's `times(134,
    ///   180)`); on, they are 300 of a 320-rated car, a crowd of 937, a
    ///   multiplier of 2,153, and take 81 s, to 223.
    /// - At Alpha the train is empty and 300 wait of 4,000, a crowd of 75: a
    ///   multiplier of 1,000, 38 s as ever, so the first exchange is the same
    ///   on or off: 8 + 38 = 46.
    /// - The doors close once the exchange is over, the latest of it, 134 + 42
    ///   − 9 = 167 and 185 − 9 = 176: at 180 off, at 223 on.
    func testAFullTrainTakesLongerToGetOff() throws {
        for crowding in [false, true] {
            var world = try makeWorld(crowding: crowding)
            release(&world, 300, at: alpha, for: gamma, .outbound)
            let label = crowding ? "on" : "off"
            try advance(&world, to: 9)
            XCTAssertEqual(world.riderCount(of: one), 300, label)
            XCTAssertEqual(world.train(id: one)?.times, times(0, 46), label)
            try advance(&world, to: 143)
            XCTAssertEqual(world.riderCount(of: one), 0, label)
            XCTAssertEqual(world.passengerLedger(of: alpha).arrived, 300, label)
            XCTAssertEqual(world.train(id: one)?.times, times(134, crowding ? 223 : 180, departure: 55), label)
            try advance(&world, to: crowding ? 224 : 181)
            XCTAssertEqual(world.train(id: one)?.times, times(134, crowding ? 223 : 180, crowding ? 223 : 180, departure: 55), label)
        }
    }

    /// Those who come while the doors are open get on in the crowd as it is
    /// then, before they board: at the whole minute 180 the train is empty and
    /// 300 wait at Gamma, a crowd of 75, so they take 38 s as ever, on from
    /// where the exchange is (223 on, 180 off): 261 and 218.
    func testThoseWhoComeWhileTheDoorsAreOpenBoardInTheCrowdOfTheMoment() throws {
        for crowding in [false, true] {
            var world = try makeWorld(crowding: crowding)
            release(&world, 300, at: alpha, for: gamma, .outbound)
            try advance(&world, to: 180)
            release(&world, 300, at: gamma, for: alpha, .inbound, since: 3)
            try advance(&world, to: 181)
            XCTAssertEqual(world.riderCount(of: one), 300, "on or off")
            XCTAssertEqual(world.train(id: one)?.times, times(134, crowding ? 261 : 218, departure: 55), crowding ? "on" : "off")
        }
    }

    /// 3,000 wait at Alpha of a station's 4,000 for an empty train: the
    /// platform's crowd is 750, a multiplier of 1,472, and the 352 a car takes
    /// get on in 65 s, not 44: the doors open at 8, so the exchange ends at
    /// 73, not 52.
    func testACrowdedPlatformSlowsBoardingOntoAnEmptyTrain() throws {
        for crowding in [false, true] {
            var world = try makeWorld(crowding: crowding)
            release(&world, 3_000, at: alpha, for: gamma, .outbound)
            XCTAssertEqual(world.doorCrowd(of: one, at: alpha), crowding ? 750 : 0)
            try advance(&world, to: 9)
            XCTAssertEqual(world.riderCount(of: one), 352, "a car takes 1.1 × 320")
            XCTAssertEqual(world.train(id: one)?.times, times(0, crowding ? 73 : 52), crowding ? "on" : "off")
        }
    }

    func testTheCrowdAtTheDoorsIsAskedOfTheWorld() throws {
        var world = try makeWorld(crowding: false)
        release(&world, 2_000, at: alpha, for: gamma, .outbound)
        XCTAssertEqual(world.doorCrowd(of: one, at: alpha), 0, "off: no crowd")
        world.setDoorCrowding(true)
        XCTAssertEqual(world.doorCrowd(of: one, at: alpha), 500, "2,000 of 4,000 wait")
        XCTAssertEqual(world.doorCrowd(of: one, at: gamma), 0)
        XCTAssertEqual(world.doorCrowd(of: TrainID(rawValue: 99), at: alpha), 0, "no such train")
    }

    /// The same station and a train just like it, but on a line of freight:
    /// its doors are not the passengers' (decision 155), so the people
    /// waiting do not slow the cargo.
    func testACrowdOnAPlatformDoesNotSlowFreight() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .x10)
        )
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        world.setDoorCrowding(true)
        world.enableFreight()
        try world.buildFreightFacility(at: alpha)
        try world.buildFreightFacility(at: gamma)
        try world.createLine(named: "Goods", stops: [alpha, gamma])
        try world.setLineFreight(main, to: true)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.assignTrain(train.id, to: main)
        try world.setStationDemand(alpha, to: StationDemand(kind: .office, dailyTrips: 0))
        release(&world, 2_000, at: alpha, for: gamma, .outbound)
        XCTAssertEqual(world.passengerLedger(of: alpha).waiting, 2_000)
        XCTAssertEqual(world.doorCrowd(of: train.id, at: alpha), 0, "cargo is not slowed by the people waiting")
    }

    /// A save in the middle of a crowded exchange loads back equal and
    /// carries on exactly as the world it was saved from.
    func testASaveDuringACrowdedDwellRestoresItExactly() throws {
        var world = try makeWorld(crowding: true)
        release(&world, 300, at: alpha, for: gamma, .outbound)
        for second: Int64 in [20, 100, 150, 200, 223, 224, 240] {
            try advance(&world, to: second)
            var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
            XCTAssertEqual(loaded, world, "at \(second)")
            var carried = world
            try loaded.advance(ticks: 60)
            try carried.advance(ticks: 60)
            XCTAssertEqual(loaded, carried, "after \(second)")
        }
        // One batch is the same as single ticks.
        var batch = try makeWorld(crowding: true)
        release(&batch, 300, at: alpha, for: gamma, .outbound)
        var single = batch
        try batch.advance(ticks: 260)
        for _ in 0..<260 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(batch, single)
    }

    // MARK: - The EMU3000 and the save

    /// Version 44 (decision 169): the crowded exchange at Gamma half way (150),
    /// door crowding on, and a second train, an unplaced EMU3000 of 12 cars.
    /// It saves byte for byte and is the world this build makes.
    func testVersionFortyFourKeepsDoorCrowdingAndTheEMU3000() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v44-door-crowding.json")
        var made = try makeWorld(crowding: true)
        let express = try made.purchaseTrain(named: "Express")
        try made.setTrainCars(express.id, to: 12)
        try made.setTrainType(express.id, to: .emu3000)
        release(&made, 300, at: alpha, for: gamma, .outbound)
        try advance(&made, to: 150)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DOOR_CROWDING_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 44)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertTrue(world.doorCrowding)
        XCTAssertEqual(world.train(id: express.id)?.type, .emu3000)
        XCTAssertEqual(world.train(id: express.id)?.ratedCapacity, 540)
        XCTAssertEqual(world.train(id: express.id)?.capacity, 594)
        // Half way through the 81 s exchange at Gamma, which began at 142.
        XCTAssertEqual(world.train(id: one)?.times, times(134, 223, departure: 55))
        // The doors close when it ends, at 223, and it leaves 9 s later.
        var carried = world
        try carried.advance(ticks: 80)
        XCTAssertEqual(carried.train(id: one)?.times, times(134, 223, 223, departure: 55))
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 44,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    /// A world from before decision 169 has no flag and no EMU3000: the
    /// committed saves before version 44 still load, with it off (the other
    /// fixtures' own tests run them on).
    func testAnEarlierSaveReadsWithDoorCrowdingOff() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v36-steam-era.json")
        let world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: url)).world
        XCTAssertFalse(world.doorCrowding)
    }
}
