import XCTest
@testable import GamePresentation

/// Decision 906: the local studio's TEMU1000 (the Taroko).
final class Map3DTEMU1000Tests: XCTestCase {
    func testIndependentUnitsAndAssembly() {
        let parts = Map3DTEMU1000.Unit.allCases.map(Map3DTEMU1000.model)
        let all = Map3DTEMU1000.formation()
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(all.triangleCount, Map3DTEMU1000.order.reduce(0) { $0 + Map3DTEMU1000.model($1).triangleCount })
        // The studio's eight cars pass one model file's limit, as the
        // TEMU2000's do.
        XCTAssertGreaterThan(all.triangleCount, Map3DModelFile.maximumTriangles)
        XCTAssertEqual(Map3DTEMU1000.order.first, .trailing)
        XCTAssertEqual(Map3DTEMU1000.order.last, .leading)
        XCTAssertEqual(Map3DTEMU1000.order.filter { $0 == .pantograph }.count, 2)
        // Each car its real length: 2 × 21.995 + 6 × 20.5.
        XCTAssertEqual(all.length, 166.99, accuracy: 0.05)
        XCTAssertEqual(Map3DTEMU1000.model(.leading).length, Map3DTEMU1000.cabLength, accuracy: 0.01)
        XCTAssertEqual(Map3DTEMU1000.model(.middle).length, Map3DTEMU1000.carLength, accuracy: 0.01)
        // The studio's wheel flanges 25 mm under the rail's top.
        XCTAssertTrue(parts.allSatisfy { abs($0.minimum.z + 0.025) < 0.012 })
        XCTAssertGreaterThan(Map3DTEMU1000.model(.pantograph).vertices.filter { $0.color == Map3DPalette.dark && $0.z > 3.8 }.count, 0)
    }

    /// The trailing cab is the leading one turned round: its nose at −x.
    func testTheTrailingCabIsTheLeadingOneTurned() {
        let lead = Map3DTEMU1000.model(.leading), trail = Map3DTEMU1000.model(.trailing)
        XCTAssertEqual(lead.triangleCount, trail.triangleCount)
        XCTAssertEqual(trail.minimum.x, -lead.maximum.x, accuracy: 0.001)
        XCTAssertEqual(trail.maximum.x, -lead.minimum.x, accuracy: 0.001)
        let lamps = Map3DTEMU1000.model(.trailing, far: false, lamps: true).vertices.filter(\.glows)
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertTrue(lamps.allSatisfy { $0.x < 0 }, "its lamps at −x")
    }

    /// The orange band is the band's only colour, on every car near and
    /// far, so a later livery can change that one colour.
    func testTheBandIsTheRealOrange() {
        XCTAssertEqual(Map3DTEMU1000.band, Map3DColor.rgb(0xEE8A22))
        for unit in Map3DTEMU1000.Unit.allCases {
            for far in [false, true] {
                XCTAssertTrue(Map3DTEMU1000.model(unit, far: far).vertices.contains { $0.color == Map3DTEMU1000.band }, "\(unit) far \(far)")
            }
        }
    }

    func testOperatingTarokoUsesTheStudiosCars() throws {
        let pack = Map3DModelPack.standard
        let layout = try XCTUnwrap(pack.layout(forType: "taroko", count: 8))
        XCTAssertEqual(layout.count, 8)
        let names = layout.map { pack.models[$0.model].name }
        XCTAssertEqual(names.first, "set-taroko-head")
        XCTAssertEqual(names.last, "set-taroko-tail")
        XCTAssertEqual(names.filter { $0 == "set-taroko-panto" }.count, 2)
        XCTAssertFalse(pack.isTurned(forType: "taroko", carIndex: 7, count: 8))
        XCTAssertEqual(pack.models[layout[0].model].triangleCount, Map3DTEMU1000.model(.leading).triangleCount)
        XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(layout.reduce(0) { $0 + $1.length }, 166.99, accuracy: 0.05)
    }

    /// The cab cars' own lamps lit, at the nose: the head lamps white and
    /// the tail lamps red; none on the cars between.
    func testTheCabCarsLightTheirOwnLamps() {
        for far in [false, true] {
            for (unit, nose) in [(Map3DTEMU1000.Unit.leading, Float(1)), (.trailing, -1)] {
                let lit = Map3DTEMU1000.model(unit, far: far, lamps: true).vertices.filter(\.glows)
                XCTAssertEqual(Set(lit.map(\.color)), [Map3DTrainStyle.headlamp, Map3DPalette.lantern], "\(unit) far \(far)")
                XCTAssertTrue(lit.allSatisfy { $0.x * nose > 8 }, "\(unit) far \(far): at its nose")
                XCTAssertFalse(Map3DTEMU1000.model(unit, far: far).vertices.contains(where: \.glows), "\(unit): the studies' unlit")
            }
            XCTAssertFalse(Map3DTEMU1000.model(.middle, far: far).vertices.contains(where: \.glows))
        }
    }
}
