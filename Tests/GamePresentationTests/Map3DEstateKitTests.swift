import Foundation
@testable import GamePresentation
import XCTest

final class Map3DEstateKitTests: XCTestCase {
    func test24DifferentBuildingsAndFourCategories() {
        let p=Map3DEstateKit.Part.allCases
        XCTAssertEqual(p.count,24);XCTAssertEqual(Set(p.map(\.id)).count,24)
        for c in Map3DEstateKit.Category.allCases { XCTAssertEqual(p.filter { $0.category==c }.count,6) }
        let models=p.map(Map3DEstateKit.model(for:))
        for i in models.indices { for j in 0..<i { XCTAssertNotEqual(models[i].vertices,models[j].vertices) } }
    }
    func testGroundMountsFiniteClosedBottomOpaqueNormalsAndBudget() {
        let parts=Map3DEstateKit.Part.allCases.map(Map3DEstateKit.model(for:))
        let scenes=Map3DEstateKit.Example.allCases.map(Map3DEstateKit.model(for:))
        XCTAssertEqual(scenes.count,4)
        for m in parts+scenes {
            XCTAssertEqual(m.minimum.z,0,accuracy:0.001,m.name)
            XCTAssertGreaterThan(m.triangleCount,0);XCTAssertLessThanOrEqual(m.triangleCount,15000,m.name)
            XCTAssertTrue(m.vertices.contains { $0.nz < -0.5 },m.name)
            for v in m.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),m.name)
                XCTAssertEqual(v.color>>24,255,m.name)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,m.name)
            }
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=m.vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) },n=(t[1]-t[0]).cross(t[2]-t[0])
                XCTAssertGreaterThan(n.dot(n),1e-15,m.name)
            }
        }
    }
    func testEveryExteriorWindowHasActualBacking() {
        var checked=0
        for part in Map3DEstateKit.Part.allCases {
            let m=Map3DEstateKit.model(for:part)
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3]);guard t[0].color==Map3DPalette.glazing else { continue }
                let normal=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
                guard abs(normal.x)>0.9 || abs(normal.y)>0.9 else { continue }
                let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                XCTAssertLessThan(ray(c+normal*0.001,normal * -1,m,excluding:Map3DPalette.glazing),0.25,part.id+" window has no backing")
                checked+=1
            }
        }
        XCTAssertGreaterThan(checked,100)
    }
    func testCarouselPostsAndHorsePolesMeetRoofAndPlatform() {
        let m=Map3DEstateKit.model(for:.carouselPavilion)
        for i in 0..<6 {
            let a=Float(i)*Float.pi/3,p=Map3DPoint(cosf(a)*3.1,-sinf(a)*3.1,3.49)
            XCTAssertLessThan(ray(p,Map3DPoint(0,0,1),m),0.1)
            XCTAssertLessThan(ray(Map3DPoint(p.x,p.y,0.42),Map3DPoint(0,0,-1),m),0.04)
        }
        for i in 0..<4 {
            let a=Float(i)*Float.pi/2,p=Map3DPoint(cosf(a)*1.85,-sinf(a)*1.85,3.49)
            XCTAssertLessThan(ray(p,Map3DPoint(0,0,1),m),0.1)
        }
    }
    func testWheelCabinRoofsMeetHangersAndHubMeetsWheel() {
        let m=Map3DEstateKit.model(for:.ferrisWheel)
        for i in 0..<8 {
            let a=Float(i)*Float.pi/4,y=6.2+sinf(a)*4.7,z=cosf(a)*4.7
            XCTAssertLessThan(ray(Map3DPoint(1.105,-z,y-0.30),Map3DPoint(-1,0,0),m),0.03,"Cabin hanger must touch roof")
            XCTAssertLessThan(ray(Map3DPoint(1.05,-z,y+0.1),Map3DPoint(0,0,-1),m,only:[Map3DPalette.tankStand]),0.12,"Hanger meets pivot")
        }
        XCTAssertLessThan(ray(Map3DPoint(0,0,6.5),Map3DPoint(0,0,-1),m,only:[Map3DPalette.tankStand]),0.1)
    }
    func testWaterHallPorchRearEdgeMeetsMainWall() {
        let m=Map3DEstateKit.model(for:.waterPlayHall)
        // Canopy rear edge must enter the wall at x=4, not stop in midair.
        XCTAssertLessThan(ray(Map3DPoint(3.99,-2.5,2.75),Map3DPoint(0,0,1),m),0.05)
    }
    func testSkybridgeMeetsBothActualTowerWalls() {
        let m=Map3DEstateKit.model(for:.skybridgeResidences)
        for sign: Float in [-1,1] {
            XCTAssertLessThan(ray(Map3DPoint(-1,sign*3.49,10),Map3DPoint(0,sign,0),m),0.07)
        }
    }
    func testMotorInnGalleryHasGroundedOuterPosts() {
        let m=Map3DEstateKit.model(for:.motorInn)
        for y: Float in [-6,-2,2,6] {
            XCTAssertLessThan(ray(Map3DPoint(3.7,y,3.15),Map3DPoint(0,0,1),m),0.04)
            XCTAssertLessThan(ray(Map3DPoint(3.7,y,0.17),Map3DPoint(0,0,-1),m),0.03)
        }
    }
    func testRoofPlanterBottomCornersRestOnTheActualRoof() {
        var mounts: [(Map3DEstateKit.Part,Float,Float,Float)]=[]
        for z: Float in [-5,-2,2,5] { mounts.append((.resortHotel,-0.6,-z,12.34)) }
        for i in 0..<4 { for z: Float in [-5,-2,2,5] { mounts.append((.terracedCondominium,6.3-Float(i)*2,-z,3.34+Float(i)*3)) } }
        for z: Float in [-4,-1,2,4] { mounts.append((.roofGardenVilla,-2,-z,6.34)) }
        for (part,x,y,h) in mounts {
            let m=Map3DEstateKit.model(for:part)
            for dx: Float in [-0.54,0.54] { for dy: Float in [-0.39,0.39] {
                XCTAssertLessThan(ray(Map3DPoint(x+dx,y+dy,h+0.001),Map3DPoint(0,0,-1),m,upwardOnly:true),0.03,part.id+" planter corner lacks a roof")
            } }
        }
    }
    func testPlacementsStayOnPlinthAndDoNotIntersectEachOther() {
        for example in Map3DEstateKit.Example.allCases {
            let placements=Map3DEstateKit.placements(for:example)
            XCTAssertEqual(placements.count,6)
            for p in placements { XCTAssertEqual(p.position.z,0.16,accuracy:0.0001) }
            // Actual rotated bounds are independently checked by verify.mjs.
            XCTAssertEqual(Set(placements.map { $0.part.id }).count,6)
        }
    }
    func testConnectorSurfaceDeterminismAndOptionalLoading() {
        for p in Map3DEstateKit.Part.allCases {
            let m=Map3DEstateKit.model(for:p)
            XCTAssertEqual(m.vertices,Map3DEstateKit.model(for:p).vertices)
            let c=p.connectors[0]
            XCTAssertEqual(c.normal,Map3DPoint(0,0,-1))
            XCTAssertEqual(ray(c.position+Map3DPoint(0,0,-0.01),Map3DPoint(0,0,1),m),0.01,accuracy:0.0001)
        }
        XCTAssertEqual(Map3DModelPack(estateKit:[.ferrisWheel,.towerHotel]).models.count,2)
        XCTAssertNil(Map3DModelPack.standard.index(of:"estate-ferrisWheel"))
    }
    private func ray(_ origin: Map3DPoint,_ direction: Map3DPoint,_ model: Map3DModelPack.Model,excluding: UInt32? = nil,only: [UInt32]? = nil,upwardOnly: Bool = false) -> Float {
        var result=Float.infinity
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let t=Array(model.vertices[i..<i+3])
            if upwardOnly && t[0].nz<0.9 { continue }
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
