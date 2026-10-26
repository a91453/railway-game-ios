import XCTest
@testable import GamePresentation

final class Map3DTEMU2000Tests: XCTestCase {
    func testFiveIndependentUnitsAndSourcedEightCarAssembly() {
        let units = Map3DTEMU2000.Unit.allCases
        XCTAssertEqual(units.count, 5)
        XCTAssertEqual(Map3DTEMU2000.order, [
            .trailing, .tema, .tep, .temb, .temb, .tep, .tema, .leading
        ])
        XCTAssertEqual(Map3DTEMU2000.centres.count, 8)
        XCTAssertEqual(Map3DTEMU2000.rotations.count, 8)
        XCTAssertEqual(Map3DTEMU2000.rotations[5], .pi, accuracy: 0.0001,
                       "Second TEP pantograph must face toward the far TED")
        XCTAssertTrue(Map3DTEMU2000.rotations.enumerated().allSatisfy { $0.offset == 5 || $0.element == 0 })
        XCTAssertEqual(Map3DTEMU2000.formationLength, 168.390, accuracy: 0.001)
        XCTAssertEqual(Map3DTEMU2000.leadingOverallLength, 22.095, accuracy: 0.001)
        XCTAssertEqual(Map3DTEMU2000.intermediateOverallLength, 20.700, accuracy: 0.001)

        let parts = units.map(Map3DTEMU2000.model)
        let formation = Map3DTEMU2000.formation()
        XCTAssertEqual(formation.triangleCount,
                       Map3DTEMU2000.order.reduce(0) { $0 + Map3DTEMU2000.model($1).triangleCount })
        XCTAssertLessThanOrEqual(formation.triangleCount, Map3DModelFile.maximumTriangles)
        XCTAssertEqual(formation.minimum.z, 0, accuracy: 0.012)
        // 168.39 m is the coupled train envelope; visible carbody ends can
        // stop at the 21.745 m TED body length inside the coupler envelope.
        XCTAssertGreaterThan(formation.length, 167.9)
        XCTAssertLessThanOrEqual(formation.length, Map3DTEMU2000.formationLength + 0.05)
        XCTAssertTrue(parts.allSatisfy { abs($0.minimum.z) < 0.012 })
        XCTAssertGreaterThan(Map3DTEMU2000.model(.tep).maximum.z,
                             Map3DTEMU2000.model(.tema).maximum.z + 0.2)
        XCTAssertNotEqual(Map3DTEMU2000.model(.leading).vertices,
                          Map3DTEMU1000.model(.leading).vertices,
                          "TEMU2000 must have its own native shape")
    }

    func testStaticModelsAreAvailableWithoutChangingOperatingPuyumaSet() throws {
        let pack = Map3DModelPack.standard
        for unit in Map3DTEMU2000.Unit.allCases {
            XCTAssertNotNil(pack.index(of: "temu2000-\(unit.rawValue)"))
        }
        XCTAssertNotNil(pack.index(of: "temu2000-formation"))
        let operating = try XCTUnwrap(pack.modelIndex(forType: "puyuma", carIndex: 0, count: 8))
        XCTAssertFalse(pack.models[operating].name.hasPrefix("temu2000-"),
                       "Static asset registration does not imply game integration")
    }
}
