import XCTest
@testable import GamePresentation

final class Map3DStationExteriorBatch2Tests: XCTestCase {
    func testAlishanEveryUpperDeckCornerHasConcreteBelow() {
        let model = Map3DStationExteriorBatch2.model(for: .alishan, detail: .near)
        let concrete = Map3DColor.rgb(0xD2D4CF)
        // Sample just inside the four corners of the 34 x 52 m deck. A lower
        // volume must cover each point at its 8.5 m top, not merely a railing.
        for east: Float in [-18.7,14.7] {
            for north: Float in [-16.7,34.7] {
                let point = (east,-north)
                let supported = stride(from: 0,to: model.vertices.count,by: 3).contains { i in
                    let triangle = Array(model.vertices[i..<(i+3)])
                    guard triangle.allSatisfy({ $0.color == concrete && abs($0.z-8.5) < 0.02 }) else { return false }
                    let a=(triangle[0].x,triangle[0].y),b=(triangle[1].x,triangle[1].y),c=(triangle[2].x,triangle[2].y)
                    func cross(_ p:(Float,Float),_ q:(Float,Float),_ r:(Float,Float)) -> Float {
                        (q.0-p.0)*(r.1-p.1)-(q.1-p.1)*(r.0-p.0)
                    }
                    let signs=[cross(a,b,point),cross(b,c,point),cross(c,a,point)]
                    return signs.allSatisfy { $0 >= -0.001 } || signs.allSatisfy { $0 <= 0.001 }
                }
                XCTAssertTrue(supported,"Upper deck corner (\(east),\(north)) has no lower volume")
            }
        }
    }
    func testFenqihuRoofProjectionFitsWallAndEaves() {
        let model = Map3DStationExteriorBatch2.model(for: .fenqihu, detail: .near)
        let wood = Map3DColor.rgb(0x858784)
        let wallCaps = stride(from:0,to:model.vertices.count,by:3).compactMap { i -> [Map3DVertex]? in
            let triangle = Array(model.vertices[i..<(i+3)])
            return triangle.allSatisfy { $0.color == wood && abs($0.z-4.0) < 0.002 } ? triangle : nil
        }
        let wall = wallCaps.flatMap { $0 }
        // The old test used a bounding box of a few surviving wall fragments;
        // the actual wall under the left roof had been removed by clearance.
        XCTAssertEqual(wallCaps.count,2,"The complete low wall cap must survive clearance")
        let wallSideColours = Set([0.92,0.80,0.70,0.86].map { Map3DColor.shaded(wood,$0) })
        let wallSides = stride(from:0,to:model.vertices.count,by:3).filter { i in
            let triangle = model.vertices[i..<(i+3)]
            return triangle.allSatisfy { wallSideColours.contains($0.color) } &&
                triangle.map(\.z).min()! < 0.01 && triangle.map(\.z).max()! > 3.99
        }
        XCTAssertGreaterThanOrEqual(wallSides.count,4,"The wall must reach the ground")
        let roof = model.vertices.filter { $0.color == Map3DColor.rgb(0x697973) && $0.z >= 3.87 }
        XCTAssertFalse(roof.isEmpty)
        guard !wall.isEmpty,!roof.isEmpty else { return }
        let wallX=wall.map(\.x),wallY=wall.map(\.y),roofX=roof.map(\.x),roofY=roof.map(\.y)
        let wallArea=(wallX.max()!-wallX.min()!)*(wallY.max()!-wallY.min()!)
        let roofArea=(roofX.max()!-roofX.min()!)*(roofY.max()!-roofY.min()!)
        XCTAssertLessThanOrEqual(roofArea/wallArea,1.4)
        for eave in [wallX.min()!-roofX.min()!,roofX.max()!-wallX.max()!,wallY.min()!-roofY.min()!,roofY.max()!-wallY.max()!] {
            XCTAssertGreaterThanOrEqual(eave,0.79)
            XCTAssertLessThanOrEqual(eave,1.21)
        }
        func coveredByWall(_ point:(Float,Float)) -> Bool {
            func cross(_ a:Map3DVertex,_ b:Map3DVertex,_ p:(Float,Float)) -> Float {
                (b.x-a.x)*(p.1-a.y)-(b.y-a.y)*(p.0-a.x)
            }
            return wallCaps.contains { t in
                let signed=[cross(t[0],t[1],point),cross(t[1],t[2],point),cross(t[2],t[0],point)]
                return signed.allSatisfy { $0 >= -0.001 } || signed.allSatisfy { $0 <= 0.001 }
            }
        }
        for east in [roofX.min()!+1.5,roofX.max()!-1.5] {
            for south in [roofY.min()!+1.5,roofY.max()!-1.5] {
                XCTAssertTrue(coveredByWall((east,south)),"No wall under roof corner inset 1.5 m at (\(east),\(south))")
            }
        }
    }
    func testFenqihuHasNoDetachedRearSidingRods() {
        let model = Map3DStationExteriorBatch2.model(for: .fenqihu, detail: .near)
        let oldRod = Map3DColor.rgb(0x70553E)
        // The old rear wall was cut by the platform clearance, leaving 4.1 m
        // high, 0.055 m wide cladding boxes without a supporting wall.
        XCTAssertFalse(model.vertices.contains {
            $0.color == oldRod && abs($0.x - 12) < 0.12 &&
            $0.z > 3.9 && abs($0.y - 7) < 9
        })
        XCTAssertFalse(model.vertices.contains {
            $0.color == Map3DColor.rgb(0xEDEDE8) && $0.x < 20 && $0.z > 1.0
        }, "Rear white window frames were clipped into detached rods")
    }
    func testFenqihuShelterIsBelowAndSeparateFromMainRoof() {
        let model = Map3DStationExteriorBatch2.model(for: .fenqihu, detail: .near)
        let shelter = model.vertices.filter { $0.color == Map3DColor.rgb(0x77746D) }
        XCTAssertFalse(shelter.isEmpty)
        // The shelter starts past the front wall and remains below the roof
        // eave, leaving no triangle intersection despite a shallow eave overlap.
        guard let shelterFront = shelter.map(\.x).min(),let shelterTop=shelter.map(\.z).max() else { return }
        XCTAssertGreaterThan(shelterFront, 30.5)
        XCTAssertLessThan(shelterTop + 0.3, 5.48)
    }
    func testKeelungSouthInternalSteelStaysBelowCanopyAndOldRoofCannotFragment() {
        let model = Map3DStationExteriorBatch2.model(for: .keelung, detail: .near)
        let steel = model.vertices.filter { $0.color == Map3DColor.rgb(0x42525A) && $0.x < -60 }
        XCTAssertFalse(steel.isEmpty)
        XCTAssertLessThan(steel.map(\.z).max()!, 8.0)
        XCTAssertFalse(model.vertices.contains { $0.color == Map3DColor.rgb(0x55585B) })
    }
    func testKeelungSouthCanopyHasSupportedFacetedFrontEdge() {
        let near = Map3DStationExteriorBatch2.model(for: .keelung, detail: .near)
        let far = Map3DStationExteriorBatch2.model(for: .keelung, detail: .far)
        let rib = Map3DColor.rgb(0x64777D)
        let frontRibs = near.vertices.filter { $0.color == rib && $0.x > -63 && $0.x < -62 }
        XCTAssertGreaterThan(frontRibs.count, 60)
        XCTAssertGreaterThan(frontRibs.map(\.z).max() ?? 0, 10)
        let columnColors = Set([1.0,0.92,0.80,0.70,0.86].map { Map3DColor.shaded(Map3DColor.rgb(0xB8C5C9),$0) })
        let columns = near.vertices.filter { columnColors.contains($0.color) && $0.x > -64 && $0.x < -62 && $0.z < 1 }
        XCTAssertFalse(columns.isEmpty)
        let roofSeam = Map3DColor.rgb(0x9BAEB3)
        let nearRoofSeams = near.vertices.filter { $0.color == roofSeam && $0.x < -60 && $0.z > 8.0 }
        let farRoofSeams = far.vertices.filter { $0.color == roofSeam && $0.x < -60 && $0.z > 8.0 }
        XCTAssertGreaterThan(nearRoofSeams.count, farRoofSeams.count)
        XCTAssertGreaterThan(nearRoofSeams.count, 400)
        let skylight = Map3DColor.rgb(0xBFE3E5)
        XCTAssertTrue(near.vertices.contains { $0.color == skylight && $0.x < -60 && $0.z > 10.9 })
        XCTAssertTrue(far.vertices.contains { $0.color == skylight && $0.x < -60 && $0.z > 10.9 })
        XCTAssertLessThan(near.triangleCount, 8_000)
        XCTAssertLessThan(far.triangleCount, 3_000)
    }
    func testQiaotouShelterRoofIsBelowTicketBoothRoof() {
        let model = Map3DStationExteriorBatch2.model(for: .qiaotou, detail: .near)
        let shelter = model.vertices.filter { $0.color == Map3DColor.rgb(0xBEC6C1) && $0.x > 30 }
        XCTAssertFalse(shelter.isEmpty)
        XCTAssertLessThan(shelter.map(\.z).max()!, 4.05)
        XCTAssertGreaterThan(shelter.map(\.x).min()!, 37.1)
    }
    func testWushulinGableUsesTheDarkTimberWallColor() {
        let model = Map3DStationExteriorBatch2.model(for: .wushulin, detail: .near)
        let timber = Map3DColor.rgb(0x604637)
        XCTAssertTrue(model.vertices.contains { $0.color == timber && $0.z > 3 && $0.x > 5 })
        XCTAssertFalse(model.vertices.contains { $0.color == Map3DColor.rgb(0xD2D1C5) && $0.z > 4.8 })
    }
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
    func testOptionalContextRemainsSeparateAndWithinClearance() {
        for station: Map3DStationExteriorBatch2.Station in [.alishan,.wushulin,.qiaotou] {
            let body = Map3DStationExteriorBatch2.model(for: station, detail: .near)
            let context = Map3DStationExteriorBatch2.contextModel(for: station, detail: .near)
            let scene = Map3DStationExteriorBatch2.model(for: station, detail: .near, includeContext: true)
            XCTAssertNotNil(context)
            XCTAssertNotEqual(body.name, scene.name)
            XCTAssertLessThanOrEqual(scene.triangleCount, 6_000)
            XCTAssertNil(Map3DStationKit.model(id: scene.name))
            for model in [context,scene].compactMap({ $0 }) {
                for i in stride(from: 0, to: model.vertices.count, by: 3) {
                    let triangle = Array(model.vertices[i..<(i+3)])
                    guard triangle.map(\.z).min()! < 5.5 else { continue }
                    let plan = triangle.map { ($0.x,-$0.y) }
                    for path in Map3DStationExteriorBatch2.clearancePaths(for: station) {
                        for j in path.indices.dropLast() {
                            XCTAssertFalse(Map3DStationExteriorBatch2.triangleTouchesCorridor(plan,path[j],path[j+1],radius:2.2),"\(station.rawValue) optional context triangle \(i/3)")
                        }
                    }
                }
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
        XCTAssertTrue(qiaotou.vertices.filter { $0.z < 5.5 && $0.x < 20 }.allSatisfy { $0.color != Map3DColor.rgb(0xA95D4B) })
        let tainan = Map3DStationExteriorBatch2.model(for: .tainan, detail: .near)
        for (east, north) in Map3DStationExteriorBatch2.way1568933253 {
            XCTAssertTrue(tainan.vertices.contains { abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 8.32) < 0.002 })
        }
    }
}
