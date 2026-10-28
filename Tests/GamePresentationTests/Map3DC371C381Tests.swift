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
        XCTAssertEqual(pack.models.last(where: { !$0.name.hasPrefix(Map3DTrainLights.prefix) })?.name, Map3DLowFloorBus.routeModel().name)
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

    func testC371FrontMaskRoundsIntoTheRoofShoulders() {
        let mask = Map3DColor.shaded(Map3DPalette.tankStand, 0.42)
        let front = Map3DC371.model(.dm).vertices.filter { $0.x > 11.60 && $0.color == mask }
        let upper = front.filter { $0.z > 3.39 && $0.z < 3.44 }
        let middle = front.filter { $0.z > 3.10 && $0.z < 3.20 }
        XCTAssertFalse(upper.isEmpty)
        XCTAssertFalse(middle.isEmpty)
        let upperHalfWidth = upper.map { abs($0.y) }.max() ?? 0
        let middleHalfWidth = middle.map { abs($0.y) }.max() ?? 0
        XCTAssertLessThan(upperHalfWidth, middleHalfWidth - 0.15)
    }
}
