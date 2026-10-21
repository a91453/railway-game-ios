import Foundation
@testable import GamePresentation
import XCTest

final class Map3DShuttleBusTests: XCTestCase {
    func testShuttleIsGroundedOpaqueAndWithinStreetBudget() {
        let m=Map3DShuttleBus.model()
        XCTAssertEqual(m.name,Map3DStreetModel.shuttleBus.modelName)
        XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
        XCTAssertEqual(m.length,Map3DShuttleBus.length,accuracy:0.02)
        XCTAssertEqual(m.maximum.z,Map3DShuttleBus.height,accuracy:0.0001)
        XCTAssertLessThan(m.maximum.y-m.minimum.y,2.8,"including mirrors, fits a street lane")
        XCTAssertLessThanOrEqual(m.triangleCount,2000)
        XCTAssertTrue(m.vertices.contains( where: \.glows))
        XCTAssertTrue(m.vertices.contains { $0.nz < -0.9 })
        for v in m.vertices {
            XCTAssertEqual(v.color>>24,255)
            XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite))
            XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
        }
    }
    func testBothWheelArchesAreActuallyOpenAboveTyres() {
        let m=Map3DShuttleBus.model()
        for x: Float in [-1.90,2.10] {
            XCTAssertEqual(ray(from:Map3DPoint(x,1.22,0.77),direction:Map3DPoint(0,-1,0),vertices:m.vertices),.infinity,"A fan-triangulated concave side would incorrectly fill the wheel arch")
        }
    }
    func testRakedWindscreenHasSolidBackingOnItsActualPlane() {
        let m=Map3DShuttleBus.model();var checked=0
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing && $0.nx>0.5 && $0.nz>0.2 }) else { continue }
            let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) },n=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
            XCTAssertLessThan(ray(from:c+n*0.001,direction:n * -1,vertices:m.vertices,skipGlass:true),0.025);checked+=1
        }
        XCTAssertEqual(checked,2)
    }
    func testTallPassengerDoorIsOnTheRightAndFixedLiveryIsReproducible() {
        let m=Map3DShuttleBus.model(),glass=m.vertices.filter { $0.color==Map3DPalette.glazing && $0.x>0.1 && $0.x<1.1 && $0.z<1.2 }
        XCTAssertTrue(glass.contains { $0.y < -1.09 })
        XCTAssertFalse(glass.contains { $0.y > 1.09 })
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DShuttleBus.bodyColor })
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DShuttleBus.roofColor })
        XCTAssertEqual(m.vertices,Map3DShuttleBus.model().vertices)
    }
    func testBothBusTypesCoexistWithoutAddingTraffic() throws {
        let old=try XCTUnwrap(Map3DStreetLife.models[.bus]),shuttle=try XCTUnwrap(Map3DStreetLife.models[.shuttleBus])
        XCTAssertNotEqual(old,shuttle)
        XCTAssertEqual(Map3DModelPack.standard.models[shuttle].vertices,Map3DShuttleBus.model().vertices)
        let path=try XCTUnwrap(Map3DStreetLife.Path([.zero,Map3DPoint(2000,0,0)]))
        var life=Map3DStreetLife()
        life.lanes=[.init(path:path,half:6,twoWay:true,speed:11,perHundred:5,scooters:true,seed:(3,4),buses:true)]
        let a=life.frame(target:Map3DPoint(1000,0,0),distance:1200,time:60,detail:.full,activity:.init())
        XCTAssertGreaterThan(a.instances.filter { $0.model==old }.count,0)
        XCTAssertGreaterThan(a.instances.filter { $0.model==shuttle }.count,0)
        XCTAssertEqual(a.buses,a.instances.filter { $0.model==old || $0.model==shuttle }.count)
        life.lanes=[.init(path:path,half:6,twoWay:true,speed:11,perHundred:5,scooters:true,seed:(3,4))]
        let b=life.frame(target:Map3DPoint(1000,0,0),distance:1200,time:60,detail:.full,activity:.init())
        XCTAssertEqual(a.vehicles,b.vehicles);XCTAssertEqual(b.buses,0)
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
