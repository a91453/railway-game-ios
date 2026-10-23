import XCTest
@testable import GamePresentation

final class Map3DSteamTenderTests: XCTestCase {
    func testIndependentUnitsAssembleByTranslationAndCoexistWithExistingFleet() {
        let formation=Map3DSteamTender.formation(); var i=0
        for unit in Map3DSteamTender.Unit.allCases {
            let model=Map3DSteamTender.model(unit)
            XCTAssertEqual(model.minimum.z,0,accuracy:0.0001)
            XCTAssertNotNil(Map3DModelPack.standard.index(of:model.name))
            for v in model.vertices {
                let q=formation.vertices[i]; i += 1
                XCTAssertEqual(q.x,v.x+unit.centre,accuracy:0.00001)
                XCTAssertEqual(q.y,v.y,accuracy:0.00001); XCTAssertEqual(q.z,v.z,accuracy:0.00001)
                XCTAssertEqual(q.color,v.color)
                XCTAssertGreaterThan(Map3DPoint(q.nx,q.ny,q.nz).dot(Map3DPoint(v.nx,v.ny,v.nz)),0.9999)
            }
        }
        XCTAssertEqual(i,formation.vertices.count)
        XCTAssertLessThanOrEqual(formation.triangleCount,Map3DModelFile.maximumTriangles)
        for id in ["metro-four-leading","blue-seven-formation","lrt-five-formation","urban-three-leading"] {
            XCTAssertNotNil(Map3DModelPack.standard.index(of:id))
        }
    }
    func testActualWheelSolidsHaveThreeLargeDriverPairsAndNoBoardIntersections() {
        for unit in Map3DSteamTender.Unit.allCases {
            let parts=Map3DSteamTender.components(unit),wheels=parts.filter { $0.role == "wheel" }
            XCTAssertEqual(wheels.count,unit == .locomotive ? 12:8)
            let large=wheels.filter { $0.model.maximum.z>1.7 }
            XCTAssertEqual(large.count,unit == .locomotive ? 6:0)
            XCTAssertEqual(Set(large.map { Int((($0.model.maximum.x+$0.model.minimum.x)*500).rounded()) }).count,unit == .locomotive ? 3:0)
            for wheel in wheels {
                XCTAssertEqual(wheel.model.minimum.z,0,accuracy:0.0001)
                if unit == .locomotive && wheel.model.maximum.z>1.7 {
                    for board in parts.filter({ $0.name.hasPrefix("running-board") }) {
                        XCTAssertGreaterThan(board.model.minimum.z-wheel.model.maximum.z,0.05)
                    }
                }
            }
        }
    }
    func testEveryClosedComponentHasPositiveVolumeFiniteNormalsAndBalancedEdges() {
        func key(_ p: Map3DPoint)->String { [p.x,p.y,p.z].map { String(Int(($0*100_000).rounded())) }.joined(separator:",") }
        for unit in Map3DSteamTender.Unit.allCases { for part in Map3DSteamTender.components(unit) {
            let vs=part.model.vertices; var edges: [String:Int]=[:],volume: Float=0
            for i in stride(from:0,to:vs.count,by:3) {
                let a=vs[i],b=vs[i+1],c=vs[i+2],n=(b.position-a.position).cross(c.position-a.position)
                XCTAssertGreaterThan(n.length,0.00000001,part.name)
                XCTAssertTrue([a.x,a.y,a.z,a.nx,a.ny,a.nz].allSatisfy(\.isFinite),part.name)
                XCTAssertGreaterThan(n.dot(Map3DPoint(a.nx,a.ny,a.nz)),0,part.name)
                volume += a.position.dot(b.position.cross(c.position))/6
                let points=[a.position,b.position,c.position]
                for j in 0..<3 { let u=key(points[j]),v=key(points[(j+1)%3]); let k=[u,v].sorted().joined(separator:"|")
                    edges[k,default:0] += u<v ? 1:-1
                }
            }
            XCTAssertTrue(edges.values.allSatisfy { $0 == 0 },part.name+" open or reversed surface")
            XCTAssertGreaterThan(volume,0,part.name+" inward or zero volume")
        } }
    }
    func testTenderHasNoCabGlazingOrHeadlightsAndLocomotiveHasAsymmetricPipework() {
        let engine=Map3DSteamTender.components(.locomotive),tender=Map3DSteamTender.components(.tender)
        XCTAssertTrue(tender.filter { $0.role == "glass" || $0.name.contains("headlamp") }.isEmpty)
        XCTAssertEqual(engine.filter { $0.role == "glass" }.count,4)
        let pipes=engine.filter { $0.role == "pipe" }
        let left=pipes.filter { $0.model.minimum.y>0 }.count,right=pipes.filter { $0.model.maximum.y<0 }.count
        XCTAssertNotEqual(left,right)
        XCTAssertFalse(engine.contains { $0.name.contains("pantograph") })
    }
}
