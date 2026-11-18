import XCTest
@testable import GamePresentation

/// Decision 852: the local studio's cars of Hong Kong's Disneyland Resort line train.
final class Map3DMTRDisneylandLineTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DMTRDisneylandLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DMTRDisneylandLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DMTRDisneylandLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001, "\(unit.rawValue) stands on the rail")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 3.11, accuracy: 0.05, "\(unit.rawValue) is about 3.11 m wide")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(unit.rawValue): the far car under half the near one")
            // The far car's colours are some of the near car's.
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The cab car's lamps at its front: white headlamps and red tail
    /// lamps, so the game lights the right end; the gold U and the red
    /// band on its front.
    func testTheCabHasItsLampsAndItsGoldUAndRedBand() throws {
        let model = try XCTUnwrap(Map3DMTRDisneylandLine.model(.cab))
        let front = Map3DMTRDisneylandLine.Unit.cab.pitch / 2 - 2.5
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = model.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, front, "its lamps at the cab end")
        }
        for colour in [Map3DPalette.platformEdge, Map3DPalette.mtrRed] {
            XCTAssertFalse(model.vertices.filter { $0.color == colour && $0.x > front }.isEmpty)
        }
    }

    /// Both cars are white above a dark blue band with the gold line in
    /// it, under a dark blue roof.
    func testEveryCarIsWhiteOverABlueBandWithAGoldLineUnderABlueRoof() throws {
        for unit in Map3DMTRDisneylandLine.Unit.allCases {
            let model = try XCTUnwrap(Map3DMTRDisneylandLine.model(unit))
            let middle = model.vertices.filter { abs($0.x) < 5 }
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.mtrPearl && $0.z > 2 && $0.z < 3 }.isEmpty, unit.rawValue)
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.playerRim && $0.z > 1 && $0.z < 1.85 }.isEmpty, unit.rawValue)
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.playerRim && $0.z > 3.5 }.isEmpty, unit.rawValue)
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.platformEdge && $0.z > 1.6 && $0.z < 1.75 }.isEmpty, unit.rawValue)
        }
    }

    /// Four cars as the real trains run, A C C A: the two pantograph cars
    /// between the two cab cars, the back one turned round.
    func testTheFourCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DMTRDisneylandLine.key
        let names = try (0..<4).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: 4))
            return pack.models[index].name
        }
        XCTAssertEqual(names, ["head", "panto", "panto", "tail"].map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: 4))
        XCTAssertEqual(layout.count, 4)
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 22.85 * 2 + 22.0 * 2, accuracy: 0.1, "89.7 m")
    }
}
