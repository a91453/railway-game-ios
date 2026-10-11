import Foundation
@testable import GameCore
import XCTest

/// Train types (the reference's `TRAIN_TYPES`): what each car carries and
/// how many doors it has.
final class TrainTypeTests: XCTestCase {
    func testTheReferenceTableAndItsCapacities() {
        XCTAssertEqual(TrainType.allCases.map(\.rawValue), ["A", "B", "C", "L", "D", "APM", "MAGLEV", "SKYRAIL", "MONORAIL", "STEAM", "HSR", "EMU3000"])
        XCTAssertEqual(TrainType.allCases.map(\.ratedCapacityPerCar), [310, 260, 200, 243, 230, 138, 240, 140, 224, 50, 80, 45])
        // Decision 153: the reference's nine, and this project's steam train;
        // decision 168: and the high-speed set, which a world without an
        // era offers as well; decision 169: and the EMU3000.
        XCTAssertEqual(TrainType.reference, Array(TrainType.allCases.dropLast(3)))
        XCTAssertEqual(TrainType.offered, TrainType.reference + [.highSpeed, .emu3000])
        XCTAssertEqual(TrainType.main, [.a, .b, .c])
        XCTAssertEqual(TrainType.referenceDefault, .b)

        var train = Train(id: TrainID(rawValue: 1), name: "T")
        // The standard car, as before types: 320 rated, 352 taken.
        XCTAssertNil(train.type)
        XCTAssertEqual(train.ratedCapacity, 320)
        XCTAssertEqual(train.capacity, 352)
        train.cars = 16
        XCTAssertEqual(train.capacity, 16 * Train.capacityPerCar)
        // The reference's B × 6: 1,560 rated, round(1,560 × 1.1) = 1,716.
        train.cars = 6
        train.type = .b
        XCTAssertEqual(train.ratedCapacity, 1_560)
        XCTAssertEqual(train.capacity, 1_716)
        // A × 8: 2,480 and 2,728; L × 3: 729 and round(801.9) = 802;
        // APM × 1: 138 and round(151.8) = 152; L × 5: 1,215 and
        // round(1,336.5) = 1,337 (half up).
        train.cars = 8
        train.type = .a
        XCTAssertEqual([train.ratedCapacity, train.capacity], [2_480, 2_728])
        train.cars = 3
        train.type = .l
        XCTAssertEqual([train.ratedCapacity, train.capacity], [729, 802])
        train.cars = 1
        train.type = .apm
        XCTAssertEqual([train.ratedCapacity, train.capacity], [138, 152])
        train.cars = 5
        train.type = .l
        XCTAssertEqual([train.ratedCapacity, train.capacity], [1_215, 1_337])
        // No type carries more than the standard car, which bounds a riding
        // group in a save.
        XCTAssertTrue(TrainType.allCases.allSatisfy { $0.ratedCapacityPerCar <= Train.ratedCapacityPerCar })
    }

    /// Decision 168: a high-speed set never takes more than it is rated
    /// for (the reference's `metroTrainUsesOperationalOverload` is false on
    /// a high-speed line), 80 persons a car: 640 for the reference's
    /// 8 cars (its 650), 960 for the 12 of a real Taiwan High Speed Rail
    /// set (989 seats) and 1,280 for 16 (its 1,200 and 1,283).
    func testAHighSpeedSetNeverOverloads() {
        var train = Train(id: TrainID(rawValue: 1), name: "T")
        train.type = .highSpeed
        XCTAssertFalse(TrainType.highSpeed.overloads)
        XCTAssertTrue(TrainType.allCases.filter { $0 != .highSpeed }.allSatisfy(\.overloads))
        for (cars, rated) in [(1, 80), (8, 640), (12, 960), (16, 1_280)] {
            train.cars = cars
            XCTAssertEqual(train.ratedCapacity, Int64(rated))
            XCTAssertEqual(train.capacity, Int64(rated), "\(cars) cars take what they are rated for")
        }
        // The others keep the 1.1.
        train.type = .a
        XCTAssertEqual(train.capacity, (train.ratedCapacity * 11 + 5) / 10)
        // It runs as the reference's `PERF_HSR`.
        XCTAssertEqual(TrainType.highSpeed.performance, .highSpeed)
        XCTAssertNil(TrainType.a.performance)
        // Two doors a car, as the other long-distance types have.
        XCTAssertEqual(TrainType.highSpeed.doorsPerCar, 2)
        train.type = .highSpeed
        train.cars = 8
        XCTAssertEqual(train.passengersPerSecond, 32)
    }

    /// Decision 169: the Taiwan Railway's EMU3000, twelve cars rated 538
    /// seats in all (the type's Wikipedia page, repeated by Taiwan News):
    /// 538 ÷ 12 = 44.8, so 45 a car and 540 for a set, and the 1.1 every
    /// type but the high-speed set takes: round(540 × 1.1) = 594. Two doors
    /// a car side, as the owner's fleet catalogue counts and the 3D city
    /// view draws them: 2 × 2 × 12 = 48 a second.
    func testTheEMU3000IsTheTaiwanRailwaysExpress() {
        XCTAssertEqual(TrainType.emu3000.rawValue, "EMU3000")
        XCTAssertEqual(TrainType.emu3000.ratedCapacityPerCar, 45)
        XCTAssertEqual(TrainType.emu3000.doorsPerCar, 2)
        XCTAssertTrue(TrainType.emu3000.overloads)
        XCTAssertEqual(TrainType.emu3000.performance, .emu3000, "It runs as the reference's EMU3000 expresses: 135 km/h")
        XCTAssertEqual(TrainPerformance.emu3000.topSpeed, 135)
        XCTAssertFalse(TrainType.reference.contains(.emu3000))
        XCTAssertTrue(TrainType.offered.contains(.emu3000))
        var train = Train(id: TrainID(rawValue: 1), name: "T")
        train.type = .emu3000
        train.cars = 12
        XCTAssertEqual(train.ratedCapacity, 540)
        XCTAssertEqual(train.capacity, 594)
        XCTAssertEqual(train.passengersPerSecond, 48)
        XCTAssertEqual(train.exchangeSeconds(100), 3)
        XCTAssertLessThanOrEqual(train.capacity, Int64(train.cars) * Train.capacityPerCar, "A riding group in a save still fits")
    }

    func testDoorsSetHowFastPassengersGetOffAndOn() {
        XCTAssertEqual(TrainType.allCases.map(\.doorsPerCar), [5, 4, 4, 3, 5, 2, 3, 2, 2, 2, 2, 2])
        var train = Train(id: TrainID(rawValue: 1), name: "T")
        train.cars = 4
        // Standard: 4 doors × 2 a second × 4 cars, as before types.
        XCTAssertEqual(train.passengersPerSecond, 32)
        XCTAssertEqual(train.exchangeSeconds(100), ServiceDwell.exchangeSeconds(100, cars: 4))
        train.type = .a
        XCTAssertEqual(train.passengersPerSecond, 40)
        XCTAssertEqual(train.exchangeSeconds(100), 3)
        train.type = .monorail
        XCTAssertEqual(train.passengersPerSecond, 16)
        XCTAssertEqual(train.exchangeSeconds(100), 7)
        XCTAssertEqual(train.exchangeSeconds(0), 0)
    }

    func testTheTypeIsSetOffTheTrackAndSaved() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        let id = try world.purchaseTrain(named: "One").id
        let balance = world.economy.balance
        try world.setTrainType(id, to: .c)
        XCTAssertEqual(world.train(id: id)?.type, .c)
        XCTAssertEqual(world.economy.balance, balance, "Free")
        XCTAssertThrowsError(try world.setTrainType(TrainID(rawValue: 99), to: .a)) { error in
            XCTAssertEqual(error as? GameError, .unknownTrain(TrainID(rawValue: 99)))
        }

        let data = try JSONEncoder().encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""type":"C""#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        try world.placeTrain(id, at: track.at(1, facingEast: true))
        let placed = world
        XCTAssertThrowsError(try world.setTrainType(id, to: .a)) { error in
            XCTAssertEqual(error as? GameError, .trainAlreadyPlaced(id))
        }
        XCTAssertEqual(world, placed, "A refused change changes nothing")

        // A train of standard cars writes no type, as saves before types.
        try world.unplaceTrain(id)
        try world.setTrainType(id, to: nil)
        let standard = try JSONEncoder().encode(world)
        XCTAssertFalse(String(decoding: standard, as: UTF8.self).contains(#""type""#))
        XCTAssertNil(try JSONDecoder().decode(GameWorld.self, from: standard).train(id: id)?.type)
        let unknown = String(decoding: data, as: UTF8.self).replacingOccurrences(of: #""type":"C""#, with: #""type":"Z""#)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(unknown.utf8)))
    }

    func testATypedTrainTakesOnlyItsCapacity() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        let a = try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        let b = try track.buildStation(named: "B", beside: 5, at: 1, in: &world)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let id = try world.purchaseTrain(named: "One").id
        try world.setTrainType(id, to: .apm)
        try world.placeTrain(id, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(id, to: 1024)
        try world.assignTrain(id, to: line)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 0))
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[index].release(500, to: b, along: PassengerTrip(line: line, direction: .outbound), at: GameTime(minutes: -1))
        world.setSpeed(.normal)
        try world.advance(ticks: 1)
        // An APM car takes round(138 × 1.1) = 152.
        XCTAssertEqual(world.riderCount(of: id), 152)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }
}
