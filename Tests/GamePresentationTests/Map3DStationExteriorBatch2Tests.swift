import XCTest
@testable import GamePresentation

final class Map3DStationExteriorBatch2Tests: XCTestCase {
    func testNineStudiesKeepBudgetsLightingAndIsolation() {
        XCTAssertEqual(Map3DStationExteriorBatch2.Station.allCases.count, 9)
        for station in Map3DStationExteriorBatch2.Station.allCases {
            let near = Map3DStationExteriorBatch2.model(for: station, detail: .near)
            let far = Map3DStationExteriorBatch2.model(for: station, detail: .far)
            XCTAssertGreaterThan(near.triangleCount, far.triangleCount, station.rawValue)
            XCTAssertLessThanOrEqual(near.triangleCount, 6_000, station.rawValue)
            XCTAssertLessThanOrEqual(far.triangleCount, 2_500, station.rawValue)
            XCTAssertGreaterThan(near.vertices.filter { $0.layer == Map3DVertex.glowing }.count, 12, station.rawValue)
            XCTAssertGreaterThan(far.vertices.filter { $0.layer == Map3DVertex.glowing }.count, 0, station.rawValue)
            XCTAssertNil(Map3DStationKit.model(id: near.name))
            XCTAssertNil(Map3DStationKit.model(id: far.name))
            for i in stride(from: 0, to: near.vertices.count, by: 3) {
                let t = near.vertices[i..<(i + 3)]
                XCTAssertFalse(t.allSatisfy { $0.color == Map3DPalette.ground && abs($0.z - 0.32) < 0.002 }, station.rawValue)
            }
        }
    }
    func testEveryOSMOutlineVertexSurvivesMetreConversion() {
        let outlines: [([(Float, Float)], Float)] = [
            (Map3DStationExteriorBatch2.way929730121, 0.32),
            (Map3DStationExteriorBatch2.way1069178919, 0.32),
            (Map3DStationExteriorBatch2.way367861777, 0.32),
            (Map3DStationExteriorBatch2.way286891391, 0.32),
            (Map3DStationExteriorBatch2.way204493488, 0.32),
            (Map3DStationExteriorBatch2.way204493489, 0.32),
            (Map3DStationExteriorBatch2.way1568887226, 0.32),
            (Map3DStationExteriorBatch2.way1568933253, 8.32),
            (Map3DStationExteriorBatch2.way353120128, 0.32),
            (Map3DStationExteriorBatch2.way444296747, 0.32),
            (Map3DStationExteriorBatch2.way344586161, 0.32),
            (Map3DStationExteriorBatch2.way112644875, 8.32),
        ]
        let models = Map3DStationExteriorBatch2.Station.allCases.map { Map3DStationExteriorBatch2.model(for: $0, detail: .near) }
        for (outline, height) in outlines {
            XCTAssertGreaterThanOrEqual(outline.count, 4)
            for (east, north) in outline {
                XCTAssertTrue(models.contains { model in model.vertices.contains {
                    abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - height) < 0.002
                } }, "OSM vertex at \(east), \(north)")
            }
        }
    }
    func testBroadCrossRailRoofsStartAboveTrainClearance() {
        // OSM tags the long Tainan underground section and Qiaotou station layer=1.
        // Only the outline and roof pieces may span the mapped rails; both start at 8 m.
        for station: Map3DStationExteriorBatch2.Station in [.qiaotou] {
            let model = Map3DStationExteriorBatch2.model(for: station, detail: .near)
            XCTAssertGreaterThanOrEqual(model.minimum.z, 8, station.rawValue)
        }
        let tainan = Map3DStationExteriorBatch2.model(for: .tainan, detail: .near)
        for (east, north) in Map3DStationExteriorBatch2.way1568933253 {
            XCTAssertTrue(tainan.vertices.contains { abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 8.32) < 0.002 })
        }
    }
}
