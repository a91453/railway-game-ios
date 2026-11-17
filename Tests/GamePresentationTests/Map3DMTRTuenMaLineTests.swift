import XCTest
@testable import GamePresentation

/// Decision 839: the local studio's cars of Hong Kong's Tuen Ma line train.
final class Map3DMTRTuenMaLineTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DMTRTuenMaLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DMTRTuenMaLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DMTRTuenMaLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001, "\(unit.rawValue) stands on the rail")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 3.1, accuracy: 0.05, "\(unit.rawValue) is about 3.1 m wide")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount + 1_000, "\(unit.rawValue): the far car much lighter")
            XCTAssertLessThan(far.triangleCount, near.triangleCount, unit.rawValue)
            // The far car's colours are some of the near car's.
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The cab car's lamps at its front: white headlamps and red tail
    /// lamps, so the game lights the right end; its round nose narrows
    /// towards the front.
    func testTheCabHasItsLampsAndARoundNose() throws {
        let model = try XCTUnwrap(Map3DMTRTuenMaLine.model(.cab))
        let front = Map3DMTRTuenMaLine.Unit.cab.pitch / 2 - 2.5
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = model.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, front, "its lamps at the cab end")
        }
        func halfWidth(at x: Float) -> Float {
            model.vertices.filter { abs($0.x - x) < 0.15 && $0.z > 1.2 }.map { abs($0.y) }.max() ?? 0
        }
        XCTAssertLessThan(halfWidth(at: model.maximum.x - 0.3), halfWidth(at: 0) - 0.3, "the nose rounds in towards the front")
    }

    /// Every car has the navy band along its windows and red doors.
    func testEveryCarHasTheNavyBandAndRedDoors() throws {
        for unit in Map3DMTRTuenMaLine.Unit.allCases {
            let model = try XCTUnwrap(Map3DMTRTuenMaLine.model(unit))
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.playerRim && abs($0.x) < 5 }.isEmpty, unit.rawValue)
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrRed && $0.z > 1.2 && $0.z < 3 }.isEmpty, unit.rawValue)
        }
    }

    /// Eight cars as the real trains run, D P M T T M P D: the pantograph
    /// cars second from each end, the back half turned round.
    func testTheEightCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let names = try (0..<8).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: Map3DMTRTuenMaLine.key, carIndex: car, count: 8))
            return pack.models[index].name
        }
        XCTAssertEqual(names.first, "set-mtrTuenMaLine-head")
        XCTAssertEqual(names.last, "set-mtrTuenMaLine-tail")
        XCTAssertTrue(names[1].contains("panto") && names[6].contains("panto"), "\(names)")
        XCTAssertFalse(names[2...5].contains { $0.contains("panto") }, "\(names)")
        XCTAssertNotEqual(names[1], names[6], "the back pantograph car turned round")
    }
}
