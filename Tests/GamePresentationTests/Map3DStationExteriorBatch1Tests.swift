import XCTest
@testable import GamePresentation

final class Map3DStationExteriorBatch1Tests: XCTestCase {
    func testHsinchuStudyKeepsOSMWayAndHistoricRoofSeparateFromChineseRoofs() {
        let near = Map3DStationExteriorBatch1.model(for: .hsinchuTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .hsinchuTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        for (east, north) in Map3DStationExteriorBatch1.hsinchuFootprint {
            XCTAssertTrue(near.vertices.contains {
                abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 0.32) < 0.002
            })
        }
        let angle: Float = 32.2 * .pi / 180
        let along = Map3DStationExteriorBatch1.hsinchuFootprint.map { $0.0 * cos(angle) + $0.1 * sin(angle) }
        let across = Map3DStationExteriorBatch1.hsinchuFootprint.map { -$0.0 * sin(angle) + $0.1 * cos(angle) }
        XCTAssertEqual((along.max() ?? 0) - (along.min() ?? 0), 143.68, accuracy: 0.1)
        XCTAssertEqual((across.max() ?? 0) - (across.min() ?? 0), 16.87, accuracy: 0.1)
        let colours = Set(near.vertices.map(\.color))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0x899780)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xC79C89)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xE5D8C3)))
        let ordered = [0xF1EADD, 0xE5D8C3, 0xC79C89, 0x899780].map(Map3DColor.rgb)
        func brightness(_ color: UInt32) -> Float {
            Float(color & 255) * 0.2126 + Float((color >> 8) & 255) * 0.7152
                + Float((color >> 16) & 255) * 0.0722
        }
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(brightness(lighter), brightness(darker))
        }
    }

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
