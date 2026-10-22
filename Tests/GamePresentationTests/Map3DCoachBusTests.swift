import Foundation
@testable import GamePresentation
import XCTest

final class Map3DCoachBusTests: XCTestCase {
    func testCoachIsGroundedOpaqueDeterministicAndWithinBudget() {
        let m=Map3DCoachBus.model()
        XCTAssertEqual(m.name,Map3DStreetModel.coachBus.modelName)
        XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
        XCTAssertEqual(m.length,Map3DCoachBus.length,accuracy:0.02)
        XCTAssertEqual(m.maximum.z,Map3DCoachBus.height,accuracy:0.0001)
        XCTAssertEqual(m.maximum.y-m.minimum.y,3.16,accuracy:0.001)
        XCTAssertLessThanOrEqual(m.triangleCount,3500)
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DCoachBus.bodyColor })
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DCoachBus.accentColor })
        XCTAssertTrue(m.vertices.contains { $0.glows && $0.x>6.57 })
        XCTAssertTrue(m.vertices.contains { $0.glows && $0.x < -6.59 })
        XCTAssertTrue(m.vertices.contains { $0.nz < -0.9 })
        for v in m.vertices {
            XCTAssertEqual(v.color>>24,255)
            XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite))
            XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
        }
        XCTAssertEqual(m.vertices,Map3DCoachBus.model().vertices)
    }
    func testLuggageDoorsUseBodyPaintAndFineFlushSeams() {
        let m=Map3DCoachBus.model()
        for x: Float in [-1.15,0.42,1.99] { for side: Float in [-1,1] {
            let surface=m.vertices.filter { abs($0.x-x)<0.73 && $0.z>0.70 && $0.z<1.48 && $0.y*side>1.251 }
            XCTAssertFalse(surface.isEmpty)
            XCTAssertFalse(surface.contains { $0.color==Map3DPalette.tankStand },"No thick steel-coloured luggage boxes")
            XCTAssertTrue(surface.contains { $0.color==Map3DCoachBus.bodyColor && $0.ny*side>0.9 },"The door face must match the body's unshaded paint")
            XCTAssertLessThanOrEqual(surface.map { abs($0.y) }.max() ?? 0,1.262,"Door and handle stay within12mm of the body")
            let paint=surface.filter { $0.color==Map3DCoachBus.bodyColor && $0.ny*side>0.9 }.map { abs($0.y) }.min() ?? 0
            let seam=surface.filter { $0.color==Map3DColor.shaded(Map3DCoachBus.bodyColor,0.87) }.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThanOrEqual(paint-seam,0.002,"Paint must clear the seam backing enough to prevent depth flicker")
            XCTAssertLessThan(ray(from:Map3DPoint(x,side*1.28,1.0),direction:Map3DPoint(0,-side,0),vertices:m.vertices),0.031,"Door remains backed by the body")
        } }
    }
    func testThreeSeparateAxlesHaveRealWheelOpenings() {
        let m=Map3DCoachBus.model()
        for x: Float in [-3.90,-2.60,3.80] {
            XCTAssertEqual(ray(from:Map3DPoint(x,1.7,1.035),direction:Map3DPoint(0,-1,0),vertices:m.vertices),.infinity)
            XCTAssertLessThan(ray(from:Map3DPoint(x,1.7,0.50),direction:Map3DPoint(0,-1,0),vertices:m.vertices),0.45,"Each axle needs a real tyre on the outside")
        }
    }
    func testBothWindscreenPlanesAndSideWindowsHaveSolidBacking() {
        let m=Map3DCoachBus.model();var front=0,side=0
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing }) else { continue }
            let n=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
            guard n.x>0.9 || abs(n.y)>0.9 else { continue }
            let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            XCTAssertLessThan(ray(from:c+n*0.001,direction:n * -1,vertices:m.vertices,skipGlass:true),0.03,"Floating pane at \(c)")
            if n.x>0.9 { front+=1;XCTAssertGreaterThan(n.z,0.1) } else { side+=1 }
        }
        XCTAssertEqual(front,4,"The windscreen must follow both distinct body slopes")
        XCTAssertGreaterThan(side,50)
    }
    func testRightFrontDoorAndRoofEquipmentAreSupported() {
        let m=Map3DCoachBus.model()
        let panes=m.vertices.filter { $0.color==Map3DPalette.glazing && $0.x>4.7 && $0.z<1.8 }
        XCTAssertTrue(panes.contains { $0.y < -1.33 })
        XCTAssertFalse(panes.contains { $0.y>1.33 })
        for x: Float in [-1.55,0.95] { for z: Float in [3.521,3.579] {
            XCTAssertEqual(ray(from:Map3DPoint(x,1.0,z),direction:Map3DPoint(0,-1,0),vertices:m.vertices),0.27,accuracy:0.001,"Feet fill the whole roof-to-HVAC gap")
        } }
    }
    func testFourBusTypesKeepTheTrafficPopulationAndSafeLengthSpacing() throws {
        let types=Map3DStreetModel.allCases.filter(\.isBus)
        let ids=try types.map { try XCTUnwrap(Map3DStreetLife.models[$0]) }
        XCTAssertEqual(Set(ids).count,4)
        let coachID=try XCTUnwrap(Map3DStreetLife.models[.coachBus])
        XCTAssertEqual(Map3DModelPack.standard.models[coachID].vertices,Map3DCoachBus.model().vertices)
        let path=try XCTUnwrap(Map3DStreetLife.Path([.zero,Map3DPoint(2000,0,0)]))
        var counts=Dictionary(uniqueKeysWithValues:ids.map { ($0,0) }),total=0
        for seed: Int32 in 0..<12 {
            // Consecutive seed.x + vehicleIndex repeats almost the same
            // vehicle keys. Sample independent roads in both coordinates.
            let roadSeed=(seed &* 1009,seed &* 9176 &+ 4)
            var life=Map3DStreetLife()
            life.lanes=[.init(path:path,half:6,twoWay:true,speed:11,perHundred:5,scooters:true,seed:roadSeed,buses:true)]
            let a=life.frame(target:Map3DPoint(1000,0,0),distance:1200,time:60,detail:.full,activity:.init())
            for id in ids { counts[id,default:0]+=a.instances.filter { $0.model==id }.count }
            total+=a.vehicles
            XCTAssertEqual(a.buses,a.instances.filter { ids.contains($0.model) }.count)
            for direction: Float in [-1,1] {
                let cars=a.instances.filter { $0.transform[0]*direction>0.5 }.sorted { $0.transform[12]<$1.transform[12] }
                for (left,right) in zip(cars,cars.dropFirst()) where left.model==coachID || right.model==coachID {
                    let l=Map3DModelPack.standard.models[left.model].length,r=Map3DModelPack.standard.models[right.model].length
                    XCTAssertGreaterThan(right.transform[12]-left.transform[12],(l+r)/2,"Coach must not overlap its neighbour")
                }
            }
            life.lanes=[.init(path:path,half:6,twoWay:true,speed:11,perHundred:5,scooters:true,seed:roadSeed)]
            let b=life.frame(target:Map3DPoint(1000,0,0),distance:1200,time:60,detail:.full,activity:.init())
            XCTAssertEqual(a.vehicles,b.vehicles);XCTAssertEqual(b.buses,0)
        }
        XCTAssertTrue(counts.values.allSatisfy { $0>0 },"All four types remain reachable: \(counts)")
        XCTAssertEqual(Double(counts.values.reduce(0,+))/Double(total),Double(Map3DStreetLife.busShare),accuracy:0.02)
        XCTAssertGreaterThan(Map3DStreetLife.busSpacing,Map3DCoachBus.length+3)
    }
    private func ray(from origin: Map3DPoint,direction: Map3DPoint,vertices: [Map3DVertex],skipGlass: Bool = false) -> Float {
        var result=Float.infinity
        for i in stride(from:0,to:vertices.count,by:3) {
            if skipGlass && vertices[i].color==Map3DPalette.glazing { continue }
            let p=vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) },e=p[1]-p[0],f=p[2]-p[0],h=direction.cross(f),det=e.dot(h)
            if abs(det)<0.000001 { continue }
            let s=origin-p[0],u=s.dot(h)/det,q=s.cross(e),v=direction.dot(q)/det,d=f.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v<=1.00001 && d>0.00001 { result=min(result,d) }
        }
        return result
    }
}
