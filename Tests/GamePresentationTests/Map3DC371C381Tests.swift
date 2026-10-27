import XCTest
@testable import GamePresentation

final class Map3DC371C381Tests: XCTestCase {
    func testSeparateRegisteredUnitsAndBudget() {
        let pack = Map3DModelPack.standard
        for model in Map3DC371.Unit.allCases.map(Map3DC371.model) + Map3DC381.Unit.allCases.map(Map3DC381.model) {
            XCTAssertNotNil(pack.index(of: model.name))
            XCTAssertGreaterThan(model.triangleCount, 0)
            XCTAssertLessThanOrEqual(model.triangleCount, Map3DModelFile.maximumTriangles)
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.0001)
        }
        XCTAssertEqual(pack.models.last?.name, Map3DLowFloorBus.routeModel().name)
    }

    func testDistinctFrontGeometryAndSixFinalUnits() {
        let a = Map3DC371.model(.dm), b = Map3DC381.model(.dm)
        XCTAssertNotEqual(a.vertices.map(\.position), b.vertices.map(\.position))
        for (formation, sections) in [
            (Map3DC371.formation(), Map3DC371.arrangement.map(Map3DC371.model)),
            (Map3DC381.formation(), Map3DC381.arrangement.map(Map3DC381.model))
        ] {
            XCTAssertEqual(formation.vertices.count, sections.reduce(0) { $0 + $1.vertices.count })
            XCTAssertLessThanOrEqual(formation.triangleCount, Map3DModelFile.maximumTriangles)
        }
    }
}
