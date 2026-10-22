import XCTest
@testable import GamePresentation

final class Map3DGreenTramTests: XCTestCase {
    func testDistinctUnitsAssembleWithoutExtraCabsOrWrongDatum() throws {
        let head = Map3DGreenTram.model(.head)
        let middle = Map3DGreenTram.model(.middle)
        let tail = Map3DGreenTram.model(.tail)
        let train = Map3DGreenTram.formation()
        XCTAssertEqual(train.triangleCount, head.triangleCount + middle.triangleCount + tail.triangleCount)
        XCTAssertGreaterThan(train.length, 32)
        XCTAssertLessThan(train.length, 34)
        XCTAssertLessThanOrEqual(train.maximum.y - train.minimum.y, 2.7)
        XCTAssertGreaterThan(tail.maximum.z, head.maximum.z + 0.7, "Pantograph belongs only on the rear section")
        XCTAssertLessThan(middle.maximum.z, 3.4, "Middle section has no cab or pantograph equipment")
        XCTAssertLessThan(abs(head.minimum.z), 0.015)
        XCTAssertLessThan(abs(middle.minimum.z), 0.015)
        XCTAssertLessThan(abs(tail.minimum.z), 0.015)
        let names = Map3DModelPack.standard.models.map(\.name)
        for name in [head.name, middle.name, tail.name, train.name] { XCTAssertTrue(names.contains(name)) }
    }

    func testGeneratedTrianglesHaveOutwardSupportAndNoDegeneracy() {
        for model in Map3DGreenTram.Section.allCases.map(Map3DGreenTram.model) + [Map3DGreenTram.formation()] {
            XCTAssertGreaterThan(model.triangleCount, 400)
            XCTAssertLessThan(model.triangleCount, 15_000)
            for start in stride(from: 0, to: model.vertices.count, by: 3) {
                let a = model.vertices[start], b = model.vertices[start + 1], c = model.vertices[start + 2]
                let u = b.position - a.position, v = c.position - a.position
                XCTAssertGreaterThan(u.cross(v).length, 0.000001, "Degenerate face in \(model.name) at \(start / 3)")
                XCTAssertGreaterThan(a.color >> 24, 0, "Transparent/unsupported livery face")
            }
        }
    }
}
