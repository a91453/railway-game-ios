import Foundation
@testable import GameCore
import XCTest

/// Decision 227: each type's real car length, taken by trains bought or
/// changed to a type in a world with real car lengths.
final class RealCarLengthTests: XCTestCase {
    private func makeWorld(real: Bool) throws -> GameWorld {
        var world = try GameCoreTests.makeWorld(width: 204_800, height: 20_480, balance: Money(1_000_000_000))
        world.setRealCarLengths(real)
        return world
    }

    func testEachTypesCarLength() {
        let metres: [String: Int64] = [
            "A": 1_408, "B": 1_248, "C": 1_216, "L": 1_056, "D": 1_280, "APM": 800,
            "MAGLEV": 960, "SKYRAIL": 768, "MONORAIL": 960, "STEAM": 512, "HSR": 1_600, "EMU3000": 1_299,
            // Decision 252: 20.1, 20.0 (the Chu-Kuang coaches) and 20.3 m.
            "EMU100": 1_286, "E200CK": 1_280, "E500CK": 1_280, "R100CK": 1_280, "R200CK": 1_280, "HAIFENG": 1_299,
            // Decision 286: 20.0 m (the old blue coaches, estimated).
            "BLUE": 1_280,
        ]
        XCTAssertEqual(Set(metres.keys), Set(TrainType.allCases.map(\.rawValue)))
        for type in TrainType.allCases {
            XCTAssertEqual(type.carLength, metres[type.rawValue], type.rawValue)
        }
        XCTAssertEqual(Train.realStandardCarLength, 20 * WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(TrainTypeSpec.worldUnits(metres: 20, tenths: 3), 1_299, "20.3 m to the nearest unit")
    }

    func testATrainTakesItsTypesLengthOnlyInAWorldWithRealLengths() throws {
        var world = try makeWorld(real: true)
        let standard = try world.purchaseTrain(named: "Standard")
        XCTAssertEqual(standard.carPitch, 1_280)
        for type in TrainType.allCases {
            let train = try world.purchaseTrain(named: type.rawValue, as: type)
            XCTAssertEqual(train.carPitch, type.carLength, type.rawValue)
        }
        // Cars added keep the pitch; a change of type takes the new one's.
        try world.setTrainCars(standard.id, to: 12)
        XCTAssertEqual(world.train(id: standard.id)?.length, 11 * 1_280)
        try world.setTrainType(standard.id, to: .highSpeed)
        XCTAssertEqual(world.train(id: standard.id)?.carPitch, 1_600)
        XCTAssertEqual(world.train(id: standard.id)?.length, 11 * 1_600)
        try world.setTrainType(standard.id, to: nil)
        XCTAssertEqual(world.train(id: standard.id)?.carPitch, 1_280)
        // Turned off, the trains already bought keep theirs; the next one
        // and a change of type are 16 m.
        world.setRealCarLengths(false)
        XCTAssertEqual(world.train(id: standard.id)?.carPitch, 1_280)
        XCTAssertEqual(try world.purchaseTrain(named: "Later", as: .highSpeed).carPitch, 1_024)
        try world.setTrainType(standard.id, to: .b)
        XCTAssertEqual(world.train(id: standard.id)?.carPitch, 1_024)
    }

    /// A platform for twelve 16 m cars no longer takes a high-speed set of
    /// twelve real ones (300 m against 176 m); one for its 275 m does.
    func testALongTrainNeedsAPlatformAsLongAsItIs() throws {
        var world = try makeWorld(real: true)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 10_240))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 101_024, y: 10_240))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let short = try world.buildStation(named: "Short", at: PlanPoint(x: 21_024, y: 10_240)).id
        let long = try world.buildStation(named: "Long", at: PlanPoint(x: 71_024, y: 10_240)).id
        try world.addTrackPlatform(short, on: edge, from: 15_000, to: 15_000 + 12 * 1_024)
        try world.addTrackPlatform(long, on: edge, from: 60_000, to: 60_000 + 12 * 1_600)
        let set = try world.purchaseTrain(named: "THSR", as: .highSpeed)
        try world.setTrainCars(set.id, to: 12)
        let length = try XCTUnwrap(world.train(id: set.id)).length
        XCTAssertTrue(world.berths(of: short, length: length).isEmpty)
        XCTAssertFalse(world.berths(of: long, length: length).isEmpty)
        // The same set of 16 m cars, in a world without, takes either.
        world.setRealCarLengths(false)
        try world.setTrainType(set.id, to: .highSpeed)
        let old = try XCTUnwrap(world.train(id: set.id)).length
        XCTAssertEqual(old, 11 * 1_024)
        XCTAssertFalse(world.berths(of: short, length: old).isEmpty)
    }

    /// Written only when set: the world's `"realCarLengths": true` and a
    /// train's `"carPitch"` when not 16 m; a pitch no car has does not read.
    func testTheSaveKeepsBothAndOnlyWhenSet() throws {
        var world = try makeWorld(real: true)
        let set = try world.purchaseTrain(named: "THSR", as: .highSpeed)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertEqual(object["realCarLengths"] as? Bool, true)
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
        XCTAssertEqual(trains.first?["carPitch"] as? Int, 1_600)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)

        var plain = try makeWorld(real: false)
        _ = try plain.purchaseTrain(named: "Plain", as: .highSpeed)
        let plainObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        XCTAssertNil(plainObject["realCarLengths"])
        XCTAssertNil((plainObject["trains"] as? [[String: Any]])?.first?["carPitch"])

        var train = try XCTUnwrap(world.train(id: set.id))
        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(train)) as! [String: Any]
        for pitch in [0, 1_000, 1_281, -1_600] {
            var bad = good
            bad["carPitch"] = pitch
            XCTAssertThrowsError(try JSONDecoder().decode(Train.self, from: JSONSerialization.data(withJSONObject: bad)), "\(pitch)")
        }
        train.carPitch = Train.carLength
        XCTAssertEqual(try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(train)).carPitch, 1_024)
    }

    /// `SaveFixtures/v62-real-car-length.json`: a world with real car
    /// lengths, a twelve-car high-speed set, a four-car medium metro and a
    /// standard train of one car.
    func testVersionSixtyTwoKeepsTheCarLengths() throws {
        var world = try makeWorld(real: true)
        let set = try world.purchaseTrain(named: "THSR 101", as: .highSpeed)
        try world.setTrainCars(set.id, to: 12)
        let metro = try world.purchaseTrain(named: "Metro 1", as: .b)
        try world.setTrainCars(metro.id, to: 4)
        _ = try world.purchaseTrain(named: "Standard")

        let url = SavedGameTests.fixtures.appendingPathComponent("v62-real-car-length.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["REAL_CAR_LENGTH_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 62)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertTrue(loaded.realCarLengths)
        XCTAssertEqual(loaded.trains.map(\.length), [11 * 1_600, 3 * 1_248, 0])
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 62,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
