import XCTest
@testable import GamePresentation

/// Decision 843: the local studio's cars of Hong Kong's East Rail line train.
final class Map3DMTREastRailLineTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DMTREastRailLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DMTREastRailLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DMTREastRailLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001, "\(unit.rawValue) stands on the rail")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 3.22, accuracy: 0.05, "\(unit.rawValue) is about 3.22 m wide")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount + 1_000, "\(unit.rawValue): the far car much lighter")
            XCTAssertLessThan(far.triangleCount, near.triangleCount, unit.rawValue)
            // The far car's colours are some of the near car's.
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The cab car's lamps at its front: white headlamps and red tail
    /// lamps, so the game lights the right end; its rounded nose narrows
    /// towards the front.
    func testTheCabHasItsLampsAndARoundedNose() throws {
        let model = try XCTUnwrap(Map3DMTREastRailLine.model(.cab))
        let front = Map3DMTREastRailLine.Unit.cab.pitch / 2 - 2.5
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = model.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, front, "its lamps at the cab end")
        }
        func halfWidth(at x: Float) -> Float {
            model.vertices.filter { abs($0.x - x) < 0.15 && $0.z > 1.2 }.map { abs($0.y) }.max() ?? 0
        }
        XCTAssertLessThan(halfWidth(at: model.maximum.x - 0.1), halfWidth(at: 0) - 0.2, "the nose rounds in towards the front")
    }

    /// Every car has the red line along its eaves and dark grey doors and
    /// window bays.
    func testEveryCarHasTheRedEavesLineAndDarkGreyBays() throws {
        for unit in Map3DMTREastRailLine.Unit.allCases {
            let model = try XCTUnwrap(Map3DMTREastRailLine.model(unit))
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrRed && abs($0.x) < 5 && $0.z > 3 }.isEmpty, unit.rawValue)
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrCharcoal && $0.z > 1.2 && $0.z < 3 }.isEmpty, unit.rawValue)
        }
    }

    /// Nine cars as the real trains run, D P M F P M M P D: the first class
    /// car fourth, the pantograph cars second, fifth and eighth, the last
    /// one turned round.
    func testTheNineCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let names = try (0..<9).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: Map3DMTREastRailLine.key, carIndex: car, count: 9))
            return pack.models[index].name
        }
        let key = Map3DMTREastRailLine.key
        XCTAssertEqual(names, ["head", "panto", "car", "centre", "panto", "car", "car", "fourth", "tail"].map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: 9))
        XCTAssertEqual(layout.count, 9)
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 25.0 * 2 + 24.136 * 7, accuracy: 0.1, "218.952 m")
    }
}
