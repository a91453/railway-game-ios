import XCTest
@testable import GamePresentation

/// Decision 848: the local studio's cars of Hong Kong's South Island line train.
final class Map3DMTRSouthIslandLineTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DMTRSouthIslandLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DMTRSouthIslandLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DMTRSouthIslandLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001, "\(unit.rawValue) stands on the rail")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 3.12, accuracy: 0.05, "\(unit.rawValue) is about 3.12 m wide")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(unit.rawValue): the far car under half the near one")
            // The far car's colours are some of the near car's.
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The cab car's lamps at its front: white headlamps and red tail
    /// lamps, so the game lights the right end; the black mask and red U
    /// on its front.
    func testTheCabHasItsLampsAndItsMaskAndRedU() throws {
        let model = try XCTUnwrap(Map3DMTRSouthIslandLine.model(.cab))
        let front = Map3DMTRSouthIslandLine.Unit.cab.pitch / 2 - 2.5
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = model.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, front, "its lamps at the cab end")
        }
        for colour in [Map3DColor.rgb(0x1D2125), Map3DPalette.mtrRed] {
            XCTAssertFalse(model.vertices.filter { $0.color == colour && $0.x > front && $0.z > 1.5 && $0.z < 3.3 }.isEmpty)
        }
    }

    /// Both cars have the red line along their eaves, dark grey doors and
    /// window bays and a steel roof (no roofSilver).
    func testEveryCarHasTheRedEavesLineDarkGreyBaysAndASteelRoof() throws {
        for unit in Map3DMTRSouthIslandLine.Unit.allCases {
            let model = try XCTUnwrap(Map3DMTRSouthIslandLine.model(unit))
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrRed && abs($0.x) < 5 && $0.z > 3 }.isEmpty, unit.rawValue)
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrCharcoal && $0.z > 1.2 && $0.z < 3 }.isEmpty, unit.rawValue)
            XCTAssertFalse(model.vertices.contains { $0.color == Map3DPalette.mtrRoofSilver }, unit.rawValue)
        }
    }

    /// Three cars as the real trains run, A B A: the pantograph car between
    /// the two cab cars, the back one turned round.
    func testTheThreeCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DMTRSouthIslandLine.key
        let names = try (0..<3).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: 3))
            return pack.models[index].name
        }
        XCTAssertEqual(names, ["head", "panto", "tail"].map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: 3))
        XCTAssertEqual(layout.count, 3)
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 23.0 * 2 + 22.0, accuracy: 0.1, "68 m")
    }
}
