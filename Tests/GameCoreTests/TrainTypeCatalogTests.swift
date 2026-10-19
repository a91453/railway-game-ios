import Foundation
@testable import GameCore
import XCTest

/// Decision 225: every train type's numbers, written out as they were before
/// they moved from `switch`es to the built-in table. This file was written
/// against the `enum` and is not to change when the table changes how the
/// numbers are kept: a value moved here is a behaviour change.
final class TrainTypeCatalogTests: XCTestCase {
    /// One type as it was: its code, a car's rating and doors, whether it
    /// overloads, its own performance, and its prices in dollars.
    private struct Pinned {
        let code: String
        let capacity: Int64
        let doors: Int64
        let overloads: Bool
        let performance: TrainPerformance?
        let first: Int64
        let car: Int64
        let permille: Int64
    }

    private static let pinned: [Pinned] = [
        .init(code: "A", capacity: 310, doors: 5, overloads: true, performance: nil, first: 150_000, car: 40_000, permille: 1_000),
        .init(code: "B", capacity: 260, doors: 4, overloads: true, performance: nil, first: 150_000, car: 40_000, permille: 1_000),
        .init(code: "C", capacity: 200, doors: 4, overloads: true, performance: nil, first: 150_000, car: 40_000, permille: 1_000),
        .init(code: "L", capacity: 243, doors: 3, overloads: true, performance: nil, first: 90_000, car: 25_000, permille: 700),
        .init(code: "D", capacity: 230, doors: 5, overloads: true, performance: nil, first: 120_000, car: 35_000, permille: 1_300),
        .init(code: "APM", capacity: 138, doors: 2, overloads: true, performance: nil, first: 110_000, car: 30_000, permille: 800),
        .init(code: "MAGLEV", capacity: 240, doors: 3, overloads: true, performance: nil, first: 600_000, car: 150_000, permille: 1_800),
        .init(code: "SKYRAIL", capacity: 140, doors: 2, overloads: true, performance: nil, first: 170_000, car: 50_000, permille: 1_000),
        .init(code: "MONORAIL", capacity: 224, doors: 2, overloads: true, performance: nil, first: 160_000, car: 45_000, permille: 1_000),
        .init(code: "STEAM", capacity: 50, doors: 2, overloads: true, performance: .steam, first: 80_000, car: 20_000, permille: 1_400),
        .init(code: "HSR", capacity: 80, doors: 2, overloads: false, performance: .highSpeed, first: 900_000, car: 120_000, permille: 2_000),
        .init(code: "EMU3000", capacity: 45, doors: 2, overloads: true, performance: .emu3000, first: 260_000, car: 55_000, permille: 1_200),
        // Decision 252: rows added after; the ones above did not move.
        .init(code: "EMU100", capacity: 45, doors: 1, overloads: true, performance: .emu100, first: 200_000, car: 45_000, permille: 1_100),
        .init(code: "E200CK", capacity: 50, doors: 2, overloads: true, performance: .e200ChuKuang, first: 220_000, car: 35_000, permille: 1_300),
        .init(code: "E500CK", capacity: 50, doors: 2, overloads: true, performance: .e500ChuKuang, first: 300_000, car: 35_000, permille: 1_200),
        .init(code: "R100CK", capacity: 50, doors: 2, overloads: true, performance: .r100ChuKuang, first: 160_000, car: 35_000, permille: 1_500),
        .init(code: "R200CK", capacity: 50, doors: 2, overloads: true, performance: .r200ChuKuang, first: 280_000, car: 35_000, permille: 1_400),
        .init(code: "HAIFENG", capacity: 44, doors: 3, overloads: true, performance: .haiFeng, first: 240_000, car: 50_000, permille: 1_300),
        // Decision 286.
        .init(code: "BLUE", capacity: 50, doors: 2, overloads: true, performance: .r100ChuKuang, first: 260_000, car: 45_000, permille: 1_500),
        .init(code: "SHANLAN", capacity: 44, doors: 3, overloads: true, performance: .haiFeng, first: 240_000, car: 50_000, permille: 1_300),
    ]

    func testEveryTypeKeepsItsNumbers() throws {
        XCTAssertEqual(TrainType.allCases.map(\.rawValue), Self.pinned.map(\.code), "the types, in their order")
        for pin in Self.pinned {
            let type = try XCTUnwrap(TrainType(rawValue: pin.code), pin.code)
            XCTAssertEqual(type.rawValue, pin.code)
            XCTAssertEqual(type.ratedCapacityPerCar, pin.capacity, pin.code)
            XCTAssertEqual(type.doorsPerCar, pin.doors, pin.code)
            XCTAssertEqual(type.overloads, pin.overloads, pin.code)
            XCTAssertEqual(type.performance, pin.performance, pin.code)
            XCTAssertEqual(type.pricing.firstCar, Money(pin.first * 100), pin.code)
            XCTAssertEqual(type.pricing.eachCar, Money(pin.car * 100), pin.code)
            XCTAssertEqual(type.pricing.operatingPermille, pin.permille, pin.code)
            XCTAssertEqual(RollingStock.pricing(of: type), type.pricing, pin.code)
        }
    }

    func testTheListsKeepTheirTypesAndOrder() {
        XCTAssertEqual(TrainType.main.map(\.rawValue), ["A", "B", "C"])
        XCTAssertEqual(TrainType.reference.map(\.rawValue), ["A", "B", "C", "L", "D", "APM", "MAGLEV", "SKYRAIL", "MONORAIL"])
        XCTAssertEqual(TrainType.offered.map(\.rawValue), ["A", "B", "C", "L", "D", "APM", "MAGLEV", "SKYRAIL", "MONORAIL", "HSR", "EMU3000", "EMU100", "E200CK", "E500CK", "R100CK", "R200CK", "HAIFENG", "BLUE", "SHANLAN"])
        XCTAssertEqual(TrainType.referenceDefault.rawValue, "B")
        XCTAssertEqual([TrainType.a, .b, .c, .l, .d, .apm, .maglev, .skyRail, .monorail, .steam, .highSpeed, .emu3000,
                        .emu100, .e200ChuKuang, .e500ChuKuang, .r100ChuKuang, .r200ChuKuang, .haiFeng, .blueTrain, .shanLan], TrainType.allCases)
    }

    func testTheStandardCarKeepsItsNumbers() {
        XCTAssertEqual(RollingStock.standard.firstCar, Money(150_000 * 100))
        XCTAssertEqual(RollingStock.standard.eachCar, Money(40_000 * 100))
        XCTAssertEqual(RollingStock.standard.operatingPermille, 1_000)
        XCTAssertEqual(RollingStock.pricing(of: nil), RollingStock.standard)
        var train = Train(id: TrainID(rawValue: 1), name: "T")
        for cars in [1, 16] {
            train.cars = cars
            XCTAssertEqual(train.ratedCapacity, 320 * Int64(cars))
            XCTAssertEqual(train.capacity, 352 * Int64(cars))
            XCTAssertEqual(train.doorsPerCar, 4)
        }
    }

    /// What a train of each type and one or sixteen cars carries, takes,
    /// lets through its doors and costs, from the pinned numbers by the
    /// rules of decisions 66, 168 and 180.
    func testATrainOfEveryTypeCarriesAndCostsWhatItDid() throws {
        var train = Train(id: TrainID(rawValue: 1), name: "T")
        for pin in Self.pinned {
            let type = try XCTUnwrap(TrainType(rawValue: pin.code))
            train.type = type
            for cars in [1, 2, 16] {
                train.cars = cars
                let rated = pin.capacity * Int64(cars)
                XCTAssertEqual(train.ratedCapacity, rated, "\(pin.code) × \(cars)")
                XCTAssertEqual(train.capacity, pin.overloads ? (rated * 11 + 5) / 10 : rated, "\(pin.code) × \(cars)")
                XCTAssertEqual(train.passengersPerSecond, ServiceDwell.passengersPerDoorPerSecond * pin.doors * Int64(cars), "\(pin.code) × \(cars)")
                XCTAssertEqual(RollingStock.price(of: type, cars: cars), Money((pin.first + pin.car * Int64(cars - 1)) * 100), "\(pin.code) × \(cars)")
                XCTAssertEqual(RollingStock.weight(of: type, cars: cars), pin.permille * Int64(cars), "\(pin.code) × \(cars)")
            }
        }
    }

    /// A save stores a type by its code, and a code no type has does not
    /// read.
    func testTheCodesReadAndAnUnknownOneDoesNot() throws {
        for pin in Self.pinned {
            let data = try JSONEncoder().encode([TrainType(rawValue: pin.code)])
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"\(pin.code)\"]")
        }
        XCTAssertNil(TrainType(rawValue: "XYZ"))
        XCTAssertNil(TrainType(rawValue: "hsr"))
        XCTAssertThrowsError(try JSONDecoder().decode([TrainType].self, from: Data("[\"XYZ\"]".utf8)))
    }
}
