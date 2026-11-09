import Foundation
@testable import GamePresentation
import XCTest

final class Map3DCivicKitTests: XCTestCase {
    func testCatalogContainsDistinctModelsInThreeCategories() {
        let parts=Map3DCivicKit.Part.allCases
        XCTAssertEqual(parts.count,48);XCTAssertEqual(Set(parts.map(\.id)).count,48)
        for c in Map3DCivicKit.Category.allCases { XCTAssertEqual(parts.filter { $0.category==c }.count,c == .furniture ? 24 : 12) }
        let models=parts.map(Map3DCivicKit.model(for:))
        for i in models.indices { for j in 0..<i { XCTAssertNotEqual(models[i].vertices,models[j].vertices,parts[i].id) } }
    }
    func testFiniteOpaqueClosedUndersidesWithinNativeBudget() {
        let models=Map3DCivicKit.Part.allCases.map(Map3DCivicKit.model(for:))+Map3DCivicKit.Example.allCases.map(Map3DCivicKit.model(for:))
        for m in models {
            XCTAssertGreaterThan(m.triangleCount,0,m.name);XCTAssertLessThanOrEqual(m.triangleCount,15000,m.name)
            XCTAssertTrue(m.vertices.contains { $0.nz < -0.5 },m.name)
            for v in m.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),m.name)
                XCTAssertEqual(v.color>>24,255,m.name)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,m.name)
            }
        }
    }
    func testInstallationPlanesAndConnectorNormals() {
        for p in Map3DCivicKit.Part.allCases {
            let m=Map3DCivicKit.model(for:p)
            switch p.mount {
            case .ground: XCTAssertEqual(m.minimum.z,0,accuracy:0.04,p.id+" floats or sinks")
            case .wall: XCTAssertEqual(m.minimum.x,0,accuracy:0.0001,p.id+" wall offset")
            case .ceiling: XCTAssertEqual(m.maximum.z,0,accuracy:0.0001,p.id+" ceiling offset")
            }
            for c in p.connectors { XCTAssertEqual(c.normal.dot(c.normal),1,accuracy:0.0001) }
        }
    }
    func testDeskTopConnectorMatchesActualHighestSurface() throws {
        let p=Map3DCivicKit.Part.writingDesk,m=Map3DCivicKit.model(for:p)
        let top=try XCTUnwrap(p.connectors.first { $0.name=="desktop" })
        XCTAssertEqual(m.maximum.z,top.position.z,accuracy:0.0001)
    }
    func testBuildingWindowsHaveBackingWithinFrameDepth() {
        for p in Map3DCivicKit.Part.allCases where p.category == .building {
            let m=Map3DCivicKit.model(for:p)
            var checked=0
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing && $0.nx>0.8 }) else { continue }
                let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                XCTAssertLessThan(ray(from:c+Map3DPoint(0.001,0,0),vertices:m.vertices),0.12,p.id);checked+=1
            }
            XCTAssertGreaterThan(checked,0,p.id)
        }
    }
    func testOnDemandPackDeterminismWallConnectionsAndRoofRidgeContact() {
        let a=Map3DCivicKit.model(for:.templeHall)
        _=Map3DCivicKit.model(for:.clinic)
        XCTAssertEqual(a.vertices,Map3DCivicKit.model(for:.templeHall).vertices)
        let pack=Map3DModelPack(civicKit:[.templeHall,.writingDesk])
        XCTAssertEqual(pack.models.count,2);XCTAssertEqual(pack.index(of:"civic-writingDesk"),1)
        var roof=StationKitBuilder();roof.civicTempleRoof(0,4,0,length:3,width:9,rise:1.5,traditional:false)
        let r=Map3DModelPack.Model.flat(named:"roof-contact",from:roof.mesh)
        for y: Float in [-3,3] {
            XCTAssertTrue(r.vertices.contains { abs($0.x)<0.001 && abs($0.y-y)<0.001 && abs($0.z-5.5)<0.001 },"Ridge ornament endpoint must meet the real hip-roof ridge")
        }
        let ends=Map3DCivicKit.Part.templeWall.connectors.filter { $0.name != "mount" }
        XCTAssertEqual(abs(ends[0].position.y-ends[1].position.y),4)
    }
    func testTraditionalRoofsRetainOriginalFarFallbackAndPortableLayers() {
        for p: Map3DCivicKit.Part in [.templeGate,.templeHall,.templeSideHall,.templeWall] {
            let near=Map3DCivicKit.model(for:p),far=Map3DCivicKit.model(for:p,far:true)
            XCTAssertEqual(far.vertices,Map3DCivicKit.model(for:p,far:false,traditional:false).vertices)
            XCTAssertGreaterThan(near.triangleCount,far.triangleCount,p.id)
            XCTAssertTrue(near.vertices.allSatisfy { $0.layer == Map3DVertex.plain })
            XCTAssertEqual(near.vertices,Map3DCivicKit.model(for:p).vertices)
            print("ROOF-COST \(p.id) near=\(near.triangleCount) far=\(far.triangleCount) delta=\(near.triangleCount-far.triangleCount)")
        }
        var roof=StationKitBuilder()
        roof.kitChineseRoof(2,4,3,length:3,width:9,rise:1.5,sweep:0.4,swallowtail:true)
        let m=Map3DModelPack.Model.flat(named:"roof",from:roof.mesh)
        XCTAssertEqual(m.minimum.z,4,accuracy:0.001)
        XCTAssertGreaterThan(m.maximum.z,6)
        XCTAssertTrue(m.vertices.contains { $0.nz < -0.8 && abs($0.z-4)<0.001 })
        XCTAssertEqual((m.minimum.x+m.maximum.x)/2,2,accuracy:0.001)
        XCTAssertEqual((m.minimum.y+m.maximum.y)/2,-3,accuracy:0.001)
    }

    func testRoofComponentCosts() {
        for (l,w,r,s) in [(Float(3),Float(9),Float(1.5),Float(0.4)),(10,12,2,0.4),(7,7,1.45,0.4),(0.5,4,0.3,0.08),(5.7,14.5,1.35,0.16),(5.5,2.5,0.8,0.12),(5.5,5.3,1.25,0.12)] {
            var roof=StationKitBuilder()
            roof.kitChineseRoof(0,0,0,length:l,width:w,rise:r,sweep:s)
            let base=roof.mesh.triangleCount
            var tail=StationKitBuilder()
            tail.kitChineseRoof(0,0,0,length:l,width:w,rise:r,sweep:s,swallowtail:true)
            XCTAssertEqual(tail.mesh.triangleCount-base,48)
            print("ROOF-PIECE \(l)x\(w) curved=\(base) swallowtail=\(tail.mesh.triangleCount-base) far-addition=0")
        }
    }

    private func ray(from origin: Map3DPoint,vertices: [Map3DVertex]) -> Float {
        let direction=Map3DPoint(-1,0,0);var result=Float.infinity
        for i in stride(from:0,to:vertices.count,by:3) {
            if vertices[i].color==Map3DPalette.glazing { continue }
            let p=vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) },e=p[1]-p[0],f=p[2]-p[0],h=direction.cross(f),det=e.dot(h)
            if abs(det)<0.000001 { continue }
            let s=origin-p[0],u=s.dot(h)/det,q=s.cross(e),v=direction.dot(q)/det,d=f.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v<=1.00001 && d>0.00001 { result=min(result,d) }
        }
        return result
    }
}
