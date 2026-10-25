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

    func testRevisedCabHasBroadScreenAndRoundedLowNose() {
        let head = Map3DTEMU1000.model(.leading)
        let screen = head.vertices.filter { $0.color == Map3DTEMU1000.glass && $0.x > 9.8 && $0.z > 2.6 }
        XCTAssertFalse(screen.isEmpty)
        XCTAssertGreaterThan((screen.map(\.y).max() ?? 0) - (screen.map(\.y).min() ?? 0), 2.0,
                             "front windscreen must span the broad shoulders")
        XCTAssertGreaterThan((screen.map(\.z).max() ?? 0) - (screen.map(\.z).min() ?? 0), 0.75,
                             "front windscreen must extend down the cab")
        let front = head.vertices.filter { $0.x > 12.15 && $0.color == Map3DTEMU1000.shell }
        let low = front.filter { $0.z < 0.95 }.map { abs($0.y) }.max() ?? 0
        let shoulder = front.filter { $0.z > 1.3 && $0.z < 2.2 }.map { abs($0.y) }.max() ?? 0
        XCTAssertGreaterThan(low, 0.7)
        XCTAssertLessThan(low, shoulder * 0.87, "lower nose must round inward")
    }

    func testMiddleHasNoCabGlassAtEnd() {
        let middle = Map3DTEMU1000.model(.middle)
        let head = Map3DTEMU1000.model(.leading)
        let glass = Map3DTEMU1000.glass
        XCTAssertFalse(middle.vertices.contains { $0.color == glass && abs($0.x) > 9.8 && $0.z > 3.2 })
        XCTAssertTrue(head.vertices.contains { $0.color == glass && $0.x > 9.8 && $0.z > 3.2 })
    }
}
