import XCTest
@testable import GamePresentation

final class Map3DGreenCommuterTests: XCTestCase {
    func testTwoHighFloorCabUnitsAssembleWithoutReversingEitherUnit() {
        let leading = Map3DGreenCommuter.model(.leading)
        let trailing = Map3DGreenCommuter.model(.trailing)
        let train = Map3DGreenCommuter.formation()
        XCTAssertEqual(train.triangleCount, leading.triangleCount + trailing.triangleCount)
        XCTAssertGreaterThan(train.length, 38)
        XCTAssertLessThan(train.length, 41)
        XCTAssertEqual(leading.maximum.y - leading.minimum.y, trailing.maximum.y - trailing.minimum.y, accuracy: 0.002)
        XCTAssertLessThan(abs(leading.minimum.z), 0.02)
        XCTAssertLessThan(abs(trailing.minimum.z), 0.02)
        for (unit, shift, offset) in [(leading, Map3DGreenCommuter.pitch / 2, 0),
                                      (trailing, -Map3DGreenCommuter.pitch / 2, leading.vertices.count)] {
            for i in unit.vertices.indices {
                let a = unit.vertices[i], b = train.vertices[offset + i]
                XCTAssertEqual(b.x - a.x, shift, accuracy: 0.0001)
                XCTAssertEqual(b.y, a.y, accuracy: 0.0001)
                XCTAssertEqual(b.z, a.z, accuracy: 0.0001)
                XCTAssertEqual(b.color, a.color)
            }
        }
        let names = Map3DModelPack.standard.models.map(\.name)
        for model in [leading, trailing, train] { XCTAssertTrue(names.contains(model.name)) }
    }

    func testCabGlassFacesOutAndFourWheelsetsPerUnitTouchDatum() {
        for (unit, drivingSign) in [(Map3DGreenCommuter.model(.leading), Float(1)),
                                    (Map3DGreenCommuter.model(.trailing), Float(-1))] {
            let glass = unit.vertices.filter { $0.color == Map3DGreenCommuter.glass }
            XCTAssertTrue(glass.contains { $0.x * drivingSign > 9.2 && $0.z > 1.8 && $0.z < 2.9 })
            XCTAssertFalse(glass.contains { $0.x * drivingSign < -9.2 && $0.z > 1.8 && $0.z < 2.9 }, "Inward end must not gain a cab window")
            let wheels = unit.vertices.filter { $0.color == Map3DStreetModel.tyre && $0.z < 0.8 }
            let axleCentres: [Float] = [-7.82,-5.78,5.78,7.82]
            for axle in axleCentres {
                XCTAssertGreaterThan(wheels.filter { abs($0.x - axle) < 0.4 && $0.y > 1.0 }.count, 10)
                XCTAssertGreaterThan(wheels.filter { abs($0.x - axle) < 0.4 && $0.y < -1.0 }.count, 10)
            }
            XCTAssertGreaterThan(wheels.filter { abs($0.z - 0.01) < 0.02 }.count, 4)
        }
    }

    func testAllTrianglesAreFiniteAndNonDegenerate() {
        for model in Map3DGreenCommuter.Unit.allCases.map(Map3DGreenCommuter.model) + [Map3DGreenCommuter.formation()] {
            XCTAssertGreaterThan(model.triangleCount, 600)
            XCTAssertLessThan(model.triangleCount, 15_000)
            for i in stride(from: 0, to: model.vertices.count, by: 3) {
                let a = model.vertices[i], b = model.vertices[i + 1], c = model.vertices[i + 2]
                XCTAssertGreaterThan((b.position - a.position).cross(c.position - a.position).length,
                                     0.000001, "Degenerate triangle in \(model.name) at \(i / 3)")
                XCTAssertTrue(a.x.isFinite && a.y.isFinite && a.z.isFinite)
                XCTAssertEqual(a.color >> 24, 0xff)
            }
        }
    }
}
