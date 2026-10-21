import Foundation
@testable import GamePresentation
import XCTest

final class Map3DMidiBusTests: XCTestCase {
    func testMidibusIsGroundedOpaqueDeterministicAndWithinBudget() {
        let m=Map3DMidiBus.model()
        XCTAssertEqual(m.name,Map3DStreetModel.midiBus.modelName)
        XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
        XCTAssertEqual(m.length,Map3DMidiBus.length,accuracy:0.02)
        XCTAssertEqual(m.maximum.z,Map3DMidiBus.height,accuracy:0.0001)
        XCTAssertEqual(m.maximum.y-m.minimum.y,2.91,accuracy:0.001)
        XCTAssertLessThanOrEqual(m.triangleCount,3000)
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DMidiBus.bodyColor })
        XCTAssertTrue(m.vertices.contains { $0.color==Map3DMidiBus.accentColor })
        XCTAssertTrue(m.vertices.contains { $0.glows && $0.x>4.4 })
        XCTAssertTrue(m.vertices.contains { $0.glows && $0.x < -4.57 })
        XCTAssertTrue(m.vertices.contains { $0.nz < -0.9 })
        for v in m.vertices {
            XCTAssertEqual(v.color>>24,255)
            XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite))
            XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
        }
        XCTAssertEqual(m.vertices,Map3DMidiBus.model().vertices)
    }
    func testTwoAxlesHaveOpenArchesAndActualTyres() {
        let m=Map3DMidiBus.model()
        for x: Float in [-2.12,2.86] {
            XCTAssertEqual(ray(from:Map3DPoint(x,1.7,0.94),direction:Map3DPoint(0,-1,0),vertices:m.vertices),.infinity)
            XCTAssertLessThan(ray(from:Map3DPoint(x,1.7,0.44),direction:Map3DPoint(0,-1,0),vertices:m.vertices),0.46)
        }
    }
    func testCurvedWindscreenAndSideWindowsHaveSolidBacking() {
        let m=Map3DMidiBus.model();var front=0,side=0
        var normals=Set<Int>()
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing }) else { continue }
            let n=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
            guard n.x>0.9 || abs(n.y)>0.9 else { continue }
            let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            XCTAssertLessThan(ray(from:c+n*0.001,direction:n * -1,vertices:m.vertices,skipGlass:true),0.03,"Floating pane at \(c)")
            if n.x>0.9 { front+=1;normals.insert(Int((n.y*1000).rounded()));XCTAssertGreaterThan(n.z,0.3) } else { side+=1 }
        }
        XCTAssertEqual(front,8,"Four real plan facets, two triangles each")
        XCTAssertEqual(normals.count,4,"A bowed windscreen must not collapse to one flat face")
        XCTAssertGreaterThan(side,50)
    }
    func testRightFrontPassengerDoorAndLeftRearEmergencyHatchStayAsymmetric() {
        let m=Map3DMidiBus.model()
        let lowGlass=m.vertices.filter { $0.color==Map3DPalette.glazing && $0.z<1.4 }
        XCTAssertTrue(lowGlass.contains { $0.x>1.2 && $0.x<2.3 && $0.y < -1.24 })
        XCTAssertFalse(lowGlass.contains { $0.y>1.24 },"The left-rear hatch is not a passenger boarding door")
        let emergency=m.vertices.filter { $0.x < -3.10 && $0.x > -4.0 && $0.y>1.21 && $0.z<1.4 }
        XCTAssertTrue(emergency.contains { $0.color==Map3DMidiBus.bodyColor && $0.ny>0.9 })
        XCTAssertFalse(emergency.contains { $0.color==Map3DPalette.tankStand },"No thick grey luggage cover")
        XCTAssertLessThanOrEqual(emergency.map(\.y).max() ?? 0,1.233)
        // The forehead is continuous with the body and both shallow roof
        // hatches touch a supporting roof rather than hovering above it.
        for x: Float in [-2.82,-0.95] {
            XCTAssertEqual(ray(from:Map3DPoint(x,0,3.10),direction:Map3DPoint(0,0,-1),vertices:m.vertices),0.055,accuracy:0.001)
        }
    }
    func testStandardAndBundledCityBusPacksKeepAllFiveVehicles() throws {
        let standard=Map3DModelPack.standard
        let id=try XCTUnwrap(Map3DStreetLife.models[.midiBus])
        XCTAssertEqual(standard.models[id].vertices,Map3DMidiBus.model().vertices)
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RailwayGameApp/Resources/Models/city-bus.m3dmodel")
        let fitted=Map3DCityBus.pack(file:url)
        for type in Map3DStreetModel.allCases.filter(\.isBus) where type != .bus {
            let index=try XCTUnwrap(Map3DStreetLife.models[type])
            XCTAssertEqual(fitted.models[index].vertices,standard.models[index].vertices)
        }
        XCTAssertEqual(Map3DStreetModel.allCases.filter(\.isBus).count,5)
        XCTAssertGreaterThan(Map3DStreetLife.busSpacing,Map3DMidiBus.length+3)
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
