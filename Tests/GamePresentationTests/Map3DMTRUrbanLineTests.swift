import XCTest
@testable import GamePresentation

/// Decision 786: the local studio's cars of Hong Kong's urban line train.
final class Map3DMTRUrbanLineTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DMTRUrbanLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DMTRUrbanLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DMTRUrbanLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001, "\(unit.rawValue) stands on the rail")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 3.1, accuracy: 0.05, "\(unit.rawValue) is about 3.1 m wide")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(unit.rawValue): the far car under half the near")
            // The far car's colours are some of the near car's.
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The cab car's lamps at its front: white headlamps and red tail
    /// lamps, so the game lights the right end; its front is black and
    /// edged in red.
    func testTheCabHasItsLampsAndRedEdgedBlackFront() throws {
        let model = try XCTUnwrap(Map3DMTRUrbanLine.model(.cab))
        let front = Map3DMTRUrbanLine.Unit.cab.pitch / 2 - 2
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = model.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, front, "its lamps at the cab end")
        }
        for colour in [Map3DColor.rgb(0x1D2125), Map3DPalette.mtrRed] {
            XCTAssertFalse(model.vertices.filter { $0.color == colour && $0.x > front }.isEmpty)
        }
    }

    /// Every car has the red line along its eaves and dark grey doors.
    func testEveryCarHasTheRedEavesAndDarkDoors() throws {
        for unit in Map3DMTRUrbanLine.Unit.allCases {
            let model = try XCTUnwrap(Map3DMTRUrbanLine.model(unit))
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrRed && $0.x < 5 && $0.z > 3 }.isEmpty, unit.rawValue)
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.mtrCharcoal }.isEmpty, unit.rawValue)
        }
    }

    /// Eight cars as the real trains run, A C B C B C B A: the pantograph
    /// on the C cars, the second cab car turned round at the back.
    func testTheEightCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let names = try (0..<8).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: Map3DMTRUrbanLine.key, carIndex: car, count: 8))
            return pack.models[index].name
        }
        XCTAssertEqual(names, ["set-mtrUrbanLine-head", "set-mtrUrbanLine-panto", "set-mtrUrbanLine-car", "set-mtrUrbanLine-panto",
                               "set-mtrUrbanLine-car", "set-mtrUrbanLine-panto", "set-mtrUrbanLine-car", "set-mtrUrbanLine-tail"])
    }
}
