import XCTest
@testable import GamePresentation

/// Decision 780: the local studio's cars of Hong Kong's airport railway.
final class Map3DMTRAirportLineTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DMTRAirportLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DMTRAirportLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DMTRAirportLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001, "\(unit.rawValue) stands on the rail")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 3.096, accuracy: 0.02, "\(unit.rawValue) is 3.096 m wide")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(unit.rawValue): the far car under half the near")
            // The far car's colours are some of the near car's.
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The cab cars' lamps at their front: white headlamps and red tail
    /// lamps, so the game lights the right end.
    func testTheCabsHaveTheirLampsAtTheFront() throws {
        for unit in Map3DMTRAirportLine.Unit.allCases where unit.cab {
            let model = try XCTUnwrap(Map3DMTRAirportLine.model(unit))
            for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
                let xs = model.vertices.filter { $0.color == lens }.map(\.x)
                XCTAssertFalse(xs.isEmpty, unit.rawValue)
                XCTAssertGreaterThan(xs.min() ?? 0, unit.pitch / 2 - 2, "\(unit.rawValue): its lamps at the cab end")
            }
        }
    }

    /// The baggage car has no saloon windows: no glass along its body
    /// behind the cab.
    func testTheBaggageCarHasNoSaloonWindows() throws {
        let baggage = try XCTUnwrap(Map3DMTRAirportLine.model(.expressBaggage))
        let saloon = baggage.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x < 8 && abs($0.y) > 1.4 }
        XCTAssertTrue(saloon.isEmpty)
        let cab = try XCTUnwrap(Map3DMTRAirportLine.model(.expressCab))
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x < 8 && abs($0.y) > 1.4 }.isEmpty)
    }

    /// Eight cars as the real trains run: the Airport Express's baggage car
    /// turned round at the back, the pantograph car fourth.
    func testTheEightCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        func names(_ key: String) throws -> [String] {
            try (0..<8).map { car in
                let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: 8))
                return pack.models[index].name
            }
        }
        XCTAssertEqual(try names("mtrAirportExpress"), ["set-mtrAirportExpress-head", "set-mtrAirportExpress-car", "set-mtrAirportExpress-car",
                                                       "set-mtrAirportExpress-panto", "set-mtrAirportExpress-car", "set-mtrAirportExpress-car",
                                                       "set-mtrAirportExpress-car", "set-mtrAirportExpress-tail"])
        XCTAssertEqual(try names("mtrTungChung")[3], "set-mtrTungChung-panto")
    }
}
