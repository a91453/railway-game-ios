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
        func brightness(_ color: UInt32) -> Float {
            Float(color & 255) * 0.2126 + Float((color >> 8) & 255) * 0.7152
                + Float((color >> 16) & 255) * 0.0722
        }
        let ordered = [StationKitBuilder.white, Map3DColor.rgb(0xEEE7DA),
                       Map3DColor.rgb(0xE5E7E2), Map3DColor.rgb(0xC79C89),
                       Map3DColor.rgb(0x90979E)]
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(brightness(lighter), brightness(darker))
        }
    }
}
