import XCTest
@testable import GamePresentation

final class Map3DStationExteriorBatch2Tests: XCTestCase {
    func testNineStudiesKeepBudgetsLightingAndIsolation() {
        XCTAssertEqual(Map3DStationExteriorBatch2.Station.allCases.count, 9)
        for station in Map3DStationExteriorBatch2.Station.allCases {
            let near = Map3DStationExteriorBatch2.model(for: station, detail: .near)
            let far = Map3DStationExteriorBatch2.model(for: station, detail: .far)
            XCTAssertGreaterThan(near.triangleCount, far.triangleCount, station.rawValue)
            XCTAssertGreaterThanOrEqual(near.triangleCount, 1_500, station.rawValue)
            XCTAssertLessThanOrEqual(near.triangleCount, 5_000, station.rawValue)
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
    func testEveryOSMOutlineRetainsAllOpenMetreVertices() {
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
            XCTAssertFalse(outline.first!.0 == outline.last!.0 && outline.first!.1 == outline.last!.1)
            XCTAssertTrue(outline.allSatisfy { $0.0.isFinite && $0.1.isFinite })
            // Clearance may remove triangles from the displayed outline; source vertices stay complete.
            XCTAssertTrue(outline.contains { east, north in models.contains { model in model.vertices.contains {
                abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - height) < 0.002
            } } })
        }
    }
    func testSurfaceRailAndPlatformEnvelopesRemainEmptyBelowFivePointFiveMetres() {
        for station in Map3DStationExteriorBatch2.Station.allCases {
            let paths = Map3DStationExteriorBatch2.clearancePaths(for: station)
            guard !paths.isEmpty else { continue }
            for detail: Map3DStationExteriorBatch2.LevelOfDetail in [.near, .far] {
                let model = Map3DStationExteriorBatch2.model(for: station, detail: detail)
                for i in stride(from: 0, to: model.vertices.count, by: 3) {
                    let triangle = Array(model.vertices[i..<(i + 3)])
                    guard triangle.map(\.z).min()! < 5.5 else { continue }
                    let plan = triangle.map { ($0.x, -$0.y) }
                    for path in paths {
                        for j in path.indices.dropLast() {
                            XCTAssertFalse(Map3DStationExteriorBatch2.triangleTouchesCorridor(plan, path[j], path[j + 1], radius: 2.2), "\(station.rawValue) \(detail) triangle \(i/3)")
                        }
                    }
                }
            }
        }
    }
    func testBroadCrossRailRoofsStartAboveTrainClearance() {
        // OSM tags the long Tainan underground section and Qiaotou station layer=1.
        // Only the outline and roof pieces may span the mapped rails; both start at 8 m.
        let qiaotou = Map3DStationExteriorBatch2.model(for: .qiaotou, detail: .near)
        // The estimated sugar-rail ticket office is at ground level outside the
        // mapped MRT platform. The full-size MRT envelope remains above 8 m.
        XCTAssertTrue(qiaotou.vertices.contains { $0.z >= 8 && $0.x < 15 })
        XCTAssertTrue(qiaotou.vertices.filter { $0.z < 5.5 }.allSatisfy { $0.x > 20 })
        let tainan = Map3DStationExteriorBatch2.model(for: .tainan, detail: .near)
        for (east, north) in Map3DStationExteriorBatch2.way1568933253 {
            XCTAssertTrue(tainan.vertices.contains { abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 8.32) < 0.002 })
        }
    }
}
