import XCTest
@testable import GamePresentation

final class Map3DEMU500Tests: XCTestCase {
    func testActualGeometryAndAssembly() {
        let all = Map3DEMU500.formation()
        XCTAssertLessThanOrEqual(all.triangleCount, Map3DModelFile.maximumTriangles)
        var cursor = 0
        for i in Map3DEMU500.order.indices {
            let part = Map3DEMU500.model(Map3DEMU500.order[i])
            XCTAssertEqual(part.minimum.z, 0, accuracy: 0.001)
            let c = cos(Map3DEMU500.rotations[i]), s = sin(Map3DEMU500.rotations[i])
            for v in part.vertices {
                let q = all.vertices[cursor]; cursor += 1
                XCTAssertEqual(q.x, c*v.x+s*v.y+Map3DEMU500.centres[i], accuracy: 0.0001)
                XCTAssertEqual(q.y, -s*v.x+c*v.y, accuracy: 0.0001)
                XCTAssertEqual(q.z, v.z, accuracy: 0.0001)
                XCTAssertEqual(q.color, v.color)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz, 1, accuracy: 0.001)
            }
        }
        XCTAssertEqual(cursor, all.vertices.count)
    }
    func testIntermediateEndsHaveNoDrivingGlassOrHeadlamps() {
        for unit in [Map3DEMU500.Unit.ep, .et] {
            let part = Map3DEMU500.model(unit)
            let endGlass = part.vertices.filter { abs($0.x)>9.7 && $0.z>2.1 && $0.color == Map3DEMU500.glass }
            XCTAssertTrue(endGlass.isEmpty)
            XCTAssertFalse(part.vertices.contains { $0.glows })
        }
    }
    func testRegistrationPreservesExistingVehiclePayload() {
        let pack = Map3DModelPack.unbaked
        for unit in Map3DEMU500.Unit.allCases {
            // K1-1: the static units are the tools' pack's.
            XCTAssertNotNil(Map3DModelPack.unbakedStudies.index(of: "emu500-"+unit.rawValue))
            XCTAssertNil(pack.index(of: "emu500-"+unit.rawValue))
        }
        for unit in Map3DTEMU1000.Unit.allCases {
            let expected=Map3DTEMU1000.model(unit)
            guard let index=pack.index(of: expected.name) else { return XCTFail("Existing unit missing") }
            let actual=pack.models[index]
            XCTAssertEqual(actual.vertices.count,expected.vertices.count)
            for (a,b) in zip(actual.vertices,expected.vertices) {
                XCTAssertEqual(a.position,b.position); XCTAssertEqual(a.color,b.color)
            }
        }
    }
}
