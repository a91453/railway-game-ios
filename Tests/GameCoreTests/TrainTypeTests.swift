import Foundation
@testable import GameCore
import XCTest

/// Train types (the reference's `TRAIN_TYPES`): what each car carries and
/// how many doors it has.
final class TrainTypeTests: XCTestCase {
    func testTheReferenceTableAndItsCapacities() {
        XCTAssertEqual(TrainType.allCases.map(\.rawValue), ["A", "B", "C", "L", "D", "APM", "MAGLEV", "SKYRAIL", "MONORAIL", "STEAM"])
        XCTAssertEqual(TrainType.allCases.map(\.ratedCapacityPerCar), [310, 260, 200, 243, 230, 138, 240, 140, 224, 50])
        // Decision 153: the reference's nine, and this project's steam train.
        XCTAssertEqual(TrainType.reference, Array(TrainType.allCases.dropLast()))
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

    func testDoorsSetHowFastPassengersGetOffAndOn() {
        XCTAssertEqual(TrainType.allCases.map(\.doorsPerCar), [5, 4, 4, 3, 5, 2, 3, 2, 2, 2])
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
