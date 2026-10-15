import Foundation
@testable import GameCore
import XCTest

/// Decision 227: before cars could have their type's real length, every
/// train's cars stood 16 m (1,024 world units) apart. This file was written
/// against that code and is not to change when real lengths come in: every
/// train of every committed save still reads at 16 m a car, and writes no
/// car length of its own.
final class RealCarLengthPinTests: XCTestCase {
    func testEveryTrainOfEverySaveFixtureKeepsSixteenMetreCars() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: SavedGameTests.fixtures.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertGreaterThan(names.count, 60)
        var multiCar = 0
        for name in names {
            let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent(name))
            // The saves from before real car lengths (version 62 is theirs).
            let version = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["saveVersion"] as? Int ?? 0
            guard version < 62 else { continue }
            let world = try JSONDecoder().decode(SavedGame.self, from: data).world
            for train in world.trains {
                XCTAssertEqual(train.length, Int64(train.cars - 1) * 1_024, "\(name): train \(train.id.rawValue)")
                if train.cars > 1 { multiCar += 1 }
                let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(train)) as? [String: Any]
                XCTAssertNil(written?["carPitch"], "\(name): train \(train.id.rawValue)")
            }
        }
        XCTAssertGreaterThan(multiCar, 20, "the fixtures hold trains of several cars")
    }

    /// A train bought in a world as `GameWorld` makes it, of any type or
    /// none, has 16 m cars.
    func testATrainBoughtInAPlainWorldHasSixteenMetreCars() throws {
        var world = try makeWorld(balance: Money(100_000_000))
        var trains = [try world.purchaseTrain(named: "Standard")]
        for type in TrainType.allCases {
            trains.append(try world.purchaseTrain(named: type.rawValue, as: type))
        }
        for train in trains {
            var train = train
            train.cars = 12
            XCTAssertEqual(train.length, 11 * 1_024, train.name)
        }
    }
}
