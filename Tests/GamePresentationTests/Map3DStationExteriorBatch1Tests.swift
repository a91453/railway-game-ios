import XCTest
@testable import GamePresentation

final class Map3DStationExteriorBatch1Tests: XCTestCase {
    func testTaichungStudyUsesSurveyedFootprintsAndStaysOutsideOperationalCatalog() {
        let near = Map3DStationExteriorBatch1.model(for: .taichungTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .taichungTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))

        // Every OSM way vertex appears on the exported plinth boundary.
        for (x, north) in Map3DStationExteriorBatch1.mainFootprint + Map3DStationExteriorBatch1.oldFootprint {
            XCTAssertTrue(near.vertices.contains { abs($0.x - x) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 0.32) < 0.002 })
        }
        let colours = Set(near.vertices.map(\.color))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xE5E7E2)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xC79C89)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0x90979E)))
    }
}
