import Foundation
@testable import GamePresentation
import XCTest

final class Map3DCoastalKitTests: XCTestCase {
    func testCatalogIs24DistinctAssetsAndFourAssemblies() {
        let parts=Map3DCoastalKit.Part.allCases
        XCTAssertEqual(parts.count,24);XCTAssertEqual(Set(parts.map(\.id)).count,24)
        XCTAssertEqual(Map3DCoastalKit.Example.allCases.count,4)
        for c in Map3DCoastalKit.Category.allCases { XCTAssertEqual(parts.filter { $0.category==c }.count,8) }
        let models=parts.map(Map3DCoastalKit.model(for:))
        for i in models.indices { for j in 0..<i { XCTAssertNotEqual(models[i].vertices,models[j].vertices) } }
    }
    func testEveryMeshIsFiniteOpaqueNondegenerateAndWithinLoaderBudget() {
        let models=Map3DCoastalKit.Part.allCases.map(Map3DCoastalKit.model(for:))+Map3DCoastalKit.Example.allCases.map(Map3DCoastalKit.model(for:))
        for m in models {
            XCTAssertGreaterThan(m.triangleCount,0,m.name);XCTAssertLessThanOrEqual(m.triangleCount,Map3DModelFile.maximumTriangles,m.name)
            XCTAssertTrue(m.vertices.contains { $0.nz < -0.5 },m.name+" missing underside")
            for v in m.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),m.name)
                XCTAssertEqual(v.color>>24,255,m.name)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,m.name)
            }
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=m.vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) }
                XCTAssertGreaterThan((t[1]-t[0]).cross(t[2]-t[0]).dot((t[1]-t[0]).cross(t[2]-t[0])),1e-15,m.name)
            }
        }
    }
    func testGroundFeetAndNativeConnectorAxes() {
        for p in Map3DCoastalKit.Part.allCases {
            let m=Map3DCoastalKit.model(for:p)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.001,p.id+" floats or sinks")
            for c in p.connectors { XCTAssertEqual(c.normal.dot(c.normal),1,accuracy:0.0001) }
            XCTAssertEqual(p.connectors[0].normal,Map3DPoint(0,0,-1))
            if let c=p.connectors.first(where: { $0.name=="waterline" }) {
                XCTAssertGreaterThan(c.position.z,m.minimum.z);XCTAssertLessThan(c.position.z,m.maximum.z)
                XCTAssertEqual(c.normal,Map3DPoint(0,0,1))
            }
        }
    }
    func testWindowBackingAndShelterRoofSupports() {
        let m=Map3DCoastalKit.model(for:.beaconTower)
        var checked=0
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing && $0.nx>0.8 }) else { continue }
            let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            XCTAssertLessThan(ray(c+Map3DPoint(0.001,0,0),Map3DPoint(-1,0,0),m,excluding:Map3DPalette.glazing),0.12)
            checked+=1
        }
        XCTAssertGreaterThan(checked,0)
        let shelter=Map3DCoastalKit.model(for:.coastShelter)
        for x: Float in [-1.9,1.9] { for y: Float in [-1.4,1.4] {
            XCTAssertLessThan(ray(Map3DPoint(x,y,2.61),Map3DPoint(0,0,1),shelter),0.15,"Post must meet roof beam")
        } }
    }
    func testTentPorchRearEdgeMeetsTheActualEndWall() throws {
        let m=Map3DCoastalKit.model(for:.ridgeTent)
        let canopy=m.vertices.filter { abs($0.z-1.24)<0.001 && $0.y>1.3 }
        let edge=try XCTUnwrap(canopy.map { abs($0.x) }.max())
        for sign: Float in [-1,1] {
            XCTAssertLessThan(ray(Map3DPoint(sign*edge,1.30,1.21),Map3DPoint(0,-1,0),m,only:[Map3DPalette.tinRoofs[0]]),0.2,"Porch must attach to the backed tent end, not the air beside its sloping roof")
        }
    }
    func testHammockRopesMeetClothAndStand() {
        let m=Map3DCoastalKit.model(for:.hammockStand)
        for sign: Float in [-1,1] {
            for y: Float in [-0.42,0.42] {
                XCTAssertLessThan(ray(Map3DPoint(sign*1.3,y,1.055),Map3DPoint(0,0,-1),m,only:[Map3DPalette.gymGreen,Map3DPalette.tileWhite]),0.05,"Rope end must touch actual cloth")
            }
            XCTAssertLessThan(ray(Map3DPoint(sign*1.65,0,1.5),Map3DPoint(0,0,-1),m,only:[Map3DPalette.counters[1]]),0.10,"Hanger must meet A-frame")
        }
    }
    func testSkiffSeatBottomCornersStayInsideTheActualHull() {
        let m=Map3DCoastalKit.model(for:.rowingSkiff)
        let corners=m.vertices.filter { abs($0.z-0.43)<0.00001 }
        XCTAssertFalse(corners.isEmpty)
        for v in corners {
            XCTAssertLessThan(ray(Map3DPoint(v.x,v.y,v.z-0.0001),Map3DPoint(0,0,-1),m),0.5,"Seat corner pierces the hull underside")
        }
    }
    func testTablesAndPontoonMatchMountingSurfaces() throws {
        for (part,name) in [(Map3DCoastalKit.Part.campTable,"tabletop"),(.fishSortingTable,"worktop"),(.floatingPontoon,"deck")] {
            let c=try XCTUnwrap(part.connectors.first { $0.name==name }),m=Map3DCoastalKit.model(for:part)
            XCTAssertEqual(ray(c.position+Map3DPoint(0,0,0.01),Map3DPoint(0,0,-1),m),0.01,accuracy:0.0001,part.id)
        }
        let boat=Map3DCoastalKit.model(for:.rowingSkiff)
        XCTAssertLessThan(ray(Map3DPoint(0,0,0.3),Map3DPoint(0,0,-1),boat),0.20,"Hull has an actual inner floor")
        XCTAssertGreaterThan(ray(Map3DPoint(0,0,0.3),Map3DPoint(0,0,1),boat),0.2,"Cockpit stays hollow")
    }
    func testAssembliesReusePlacementsAndWaterlineHeights() throws {
        let p=Map3DCoastalKit.placements(for:.fishingHarbor)
        for a in p where a.part == .motorDinghy || a.part == .floatingPontoon {
            let c=try XCTUnwrap(a.part.connectors.first { $0.name=="waterline" })
            XCTAssertEqual(a.position.z+c.position.z,0.30,accuracy:0.0001)
        }
        let yard=Map3DCoastalKit.placements(for:.boatyard)
        let trailer=try XCTUnwrap(yard.first { $0.part == .boatTrailer }),skiff=try XCTUnwrap(yard.first { $0.part == .rowingSkiff })
        XCTAssertEqual(skiff.position.z-trailer.position.z,0.62,accuracy:0.0001)
        let table=try XCTUnwrap(yard.first { $0.part == .fishSortingTable }),box=try XCTUnwrap(yard.first { $0.part == .insulatedFishCrate })
        XCTAssertEqual(box.position.z-table.position.z,0.9,accuracy:0.0001)
    }
    func testOnDemandDeterminismAndNoStandardRegistration() {
        let a=Map3DCoastalKit.model(for:.motorDinghy)
        _=Map3DCoastalKit.model(for:.domeTent)
        XCTAssertEqual(a.vertices,Map3DCoastalKit.model(for:.motorDinghy).vertices)
        let pack=Map3DModelPack(coastalKit:[.motorDinghy,.campTable])
        XCTAssertEqual(pack.models.count,2);XCTAssertEqual(pack.index(of:"coastal-campTable"),1)
        XCTAssertNil(Map3DModelPack.standard.index(of:"coastal-motorDinghy"))
    }
    private func ray(_ origin: Map3DPoint,_ direction: Map3DPoint,_ model: Map3DModelPack.Model,excluding: UInt32? = nil,only: [UInt32]? = nil) -> Float {
        var result=Float.infinity
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let t=Array(model.vertices[i..<i+3])
            if let excluding,t[0].color==excluding { continue }
            if let only,!only.contains(t[0].color) { continue }
            let p=t.map { Map3DPoint($0.x,$0.y,$0.z) },e=p[1]-p[0],f=p[2]-p[0],h=direction.cross(f),det=e.dot(h)
            if abs(det)<0.0000001 { continue }
            let s=origin-p[0],u=s.dot(h)/det,q=s.cross(e),v=direction.dot(q)/det,d=f.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v<=1.00001 && d>0.00001 { result=min(result,d) }
        }
        return result
    }
}
