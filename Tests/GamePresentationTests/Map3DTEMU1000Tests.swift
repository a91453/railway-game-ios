import XCTest
@testable import GamePresentation

final class Map3DTEMU1000Tests: XCTestCase {
    func testIndependentUnitsAndAssembly() {
        let parts = Map3DTEMU1000.Unit.allCases.map(Map3DTEMU1000.model)
        let all = Map3DTEMU1000.formation()
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(all.triangleCount, Map3DTEMU1000.order.reduce(0) { $0 + Map3DTEMU1000.model($1).triangleCount })
        XCTAssertLessThan(all.triangleCount, Map3DModelFile.maximumTriangles)
        XCTAssertEqual(Map3DTEMU1000.order.first, .trailing)
        XCTAssertEqual(Map3DTEMU1000.order.last, .leading)
        XCTAssertEqual(Map3DTEMU1000.order.filter { $0 == .pantograph }.count, 2)
        XCTAssertGreaterThan(all.length, 185)
        XCTAssertLessThan(all.length, 195)
        XCTAssertEqual(all.minimum.z, 0, accuracy: 0.012)
        XCTAssertTrue(parts.allSatisfy { abs($0.minimum.z) < 0.012 })
        XCTAssertGreaterThan(Map3DTEMU1000.model(.pantograph).maximum.z, Map3DTEMU1000.model(.middle).maximum.z + 0.5)
    }

    func testOperatingTarokoUsesNewUnits() throws {
        let pack = Map3DModelPack.standard
        let layout = try XCTUnwrap(pack.layout(forType: "taroko", count: 8))
        XCTAssertEqual(layout.count, 8)
        let names = layout.map { pack.models[$0.model].name }
        XCTAssertEqual(names.first, "set-taroko-head")
        XCTAssertEqual(names.last, "set-taroko-tail")
        XCTAssertEqual(names.filter { $0 == "set-taroko-panto" }.count, 2)
        XCTAssertFalse(pack.isTurned(forType: "taroko", carIndex: 7, count: 8))
        XCTAssertEqual(pack.models[layout[0].model].triangleCount, Map3DTEMU1000.model(.leading).triangleCount + 24)
    }

    func testMiddleHasNoCabGlassAtEnd() {
        let middle = Map3DTEMU1000.model(.middle)
        let head = Map3DTEMU1000.model(.leading)
        let glass = Map3DTEMU1000.glass
        XCTAssertFalse(middle.vertices.contains { $0.color == glass && abs($0.x) > 10.5 && $0.z > 2.8 })
        XCTAssertTrue(head.vertices.contains { $0.color == glass && $0.x > 10.5 && $0.z > 2.8 })
    }
}
