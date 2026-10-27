import Foundation
@testable import GamePresentation
import XCTest

final class Map3DLowFloorBusTests: XCTestCase {
    func testDimensionsGroundOpaquePaintNormalsAndLampBudget() {
        let m=Map3DLowFloorBus.model()
        XCTAssertEqual(m.name,Map3DStreetModel.lowFloorBus.modelName)
        XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
        XCTAssertEqual(m.length,Map3DLowFloorBus.length,accuracy:0.02)
        XCTAssertEqual(m.maximum.z,Map3DLowFloorBus.height,accuracy:0.0001)
        XCTAssertEqual(m.maximum.y-m.minimum.y,3.05,accuracy:0.001)
        XCTAssertLessThanOrEqual(m.triangleCount,2500)
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DLowFloorBus.bodyColor })
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DLowFloorBus.accentColor })
        XCTAssertTrue(m.vertices.contains { $0.glows && $0.x>6 })
        XCTAssertTrue(m.vertices.contains { $0.glows && $0.x < -5.98 })
        XCTAssertTrue(m.vertices.contains { $0.nz < -0.9 })
        for v in m.vertices {
            XCTAssertEqual(v.color>>24,255)
            XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite))
            XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
        }
        XCTAssertEqual(m.vertices,Map3DLowFloorBus.model().vertices)
    }
    func testWheelArchesHaveEmptySpaceAboveTyresOnBothSides() {
        let m=Map3DLowFloorBus.model()
        for x: Float in [-3.55,3.45] {
            XCTAssertEqual(ray(from:Map3DPoint(x,1.6,1.0),direction:Map3DPoint(0,-1,0),vertices:m.vertices),.infinity)
        }
    }
    func testAllFrontAndSideGlassHasSolidBacking() {
        let m=Map3DLowFloorBus.model();var front=0,side=0
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing }) else { continue }
            let n=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
            guard n.x>0.9 || abs(n.y)>0.9 else { continue }
            let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            XCTAssertLessThan(ray(from:c+n*0.001,direction:n * -1,vertices:m.vertices,skipGlass:true),0.03,"Floating pane at \(c)")
            if n.x>0.9 { front+=1;XCTAssertGreaterThan(n.z,0.08) } else { side+=1 }
        }
        XCTAssertEqual(front,2);XCTAssertGreaterThan(side,50)
    }
    func testTwoDoubleDoorsAreOnTheRightAndEquipmentHasRoofContact() {
        let m=Map3DLowFloorBus.model()
        for x: Float in [0.05,4.86] {
            let panes=m.vertices.filter { $0.color==Map3DPalette.glazing && abs($0.x-x)<0.8 && $0.z<1.2 }
            XCTAssertTrue(panes.contains { $0.y < -1.31 })
            XCTAssertFalse(panes.contains { $0.y>1.31 })
            XCTAssertTrue(panes.contains { $0.x<x });XCTAssertTrue(panes.contains { $0.x>x })
        }
        // The HVAC feet touch the roof and the enclosure at both ends.
        for x: Float in [-3.52,-1.28] {
            for z: Float in [3.141,3.199] {
                XCTAssertEqual(ray(from:Map3DPoint(x,1.0,z),direction:Map3DPoint(0,-1,0),vertices:m.vertices),0.29,accuracy:0.001,"A foot must span the whole roof-to-enclosure gap")
            }
        }
    }
    func testAllBusTypesCoexistAndKeepTheSameTrafficPopulation() throws {
        let types=Map3DStreetModel.allCases.filter(\.isBus)
        let ids=try types.map { try XCTUnwrap(Map3DStreetLife.models[$0]) }
        XCTAssertEqual(Set(ids).count,types.count)
        XCTAssertEqual(Map3DModelPack.standard.models[ids[2]].vertices,Map3DLowFloorBus.model().vertices)
        let path=try XCTUnwrap(Map3DStreetLife.Path([.zero,Map3DPoint(2000,0,0)]))
        var counts=Array(repeating:0,count:ids.count),total=0
        for seed: Int32 in 0..<12 {
            let roadSeed=(seed &* 1009,seed &* 9176 &+ 4)
            var life=Map3DStreetLife()
            life.lanes=[.init(path:path,half:6,twoWay:true,speed:11,perHundred:5,scooters:true,seed:roadSeed,buses:true)]
            let a=life.frame(target:Map3DPoint(1000,0,0),distance:1200,time:60,detail:.full,activity:.init())
            for i in ids.indices { counts[i]+=a.instances.filter { $0.model==ids[i] }.count }
            total+=a.vehicles
            let allBusIDs=Set(Map3DStreetModel.allCases.filter(\.isBus).compactMap { Map3DStreetLife.models[$0] })
            XCTAssertEqual(a.buses,a.instances.filter { allBusIDs.contains($0.model) }.count)
            life.lanes=[.init(path:path,half:6,twoWay:true,speed:11,perHundred:5,scooters:true,seed:roadSeed)]
            let b=life.frame(target:Map3DPoint(1000,0,0),distance:1200,time:60,detail:.full,activity:.init())
            // A bus takes a vehicle's place, never adds one; decision 446:
            // the scooter that would have ridden beside it goes too.
            XCTAssertTrue((0...a.buses).contains(b.vehicles-a.vehicles),"\(a.vehicles) \(b.vehicles)");XCTAssertEqual(b.buses,0)
        }
        XCTAssertTrue(counts.allSatisfy { $0>0 },"Every bus type must be reachable: \(counts)")
        XCTAssertEqual(Double(counts.reduce(0,+))/Double(total),Double(Map3DStreetLife.busShare),accuracy:0.02)
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
