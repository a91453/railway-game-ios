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
        var normals=Set<Int>(),slopes=[Float]()
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DMidiBus.windowColor }) else { continue }
            let n=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
            guard n.x>0.25 || abs(n.y)>0.9 else { continue }
            let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            XCTAssertLessThan(ray(from:c+n*0.001,direction:n * -1,vertices:m.vertices,skipGlass:true),0.03,"Floating pane at \(c)")
            if n.x>0.25 { front+=1;normals.insert(Int((n.y*1000).rounded()));slopes.append(n.z) } else { side+=1 }
        }
        XCTAssertGreaterThanOrEqual(front,100,"Panoramic glass follows multiple plan and height sections")
        XCTAssertGreaterThanOrEqual(normals.count,6,"The windscreen wraps around both front corners")
        XCTAssertLessThan(slopes.min() ?? 1,0.15,"Lower screen stays upright")
        XCTAssertGreaterThan(slopes.max() ?? 0,0.4,"Upper screen curves progressively into the roof")
        XCTAssertGreaterThan(side,50)
    }
    func testRightFrontPassengerDoorAndLeftRearEmergencyHatchStayAsymmetric() {
        let m=Map3DMidiBus.model()
        let lowGlass=m.vertices.filter { $0.color==Map3DMidiBus.windowColor && $0.z<1.4 }
        XCTAssertTrue(lowGlass.contains { $0.x>1.2 && $0.x<2.3 && $0.y < -1.24 })
        XCTAssertFalse(lowGlass.contains { $0.y>1.24 },"The left-rear hatch is not a passenger boarding door")
        let emergency=m.vertices.filter { $0.x < -3.10 && $0.x > -4.0 && $0.y>1.21 && $0.z<1.4 }
        XCTAssertTrue(emergency.contains { $0.color==Map3DMidiBus.bodyColor && $0.ny>0.9 })
        XCTAssertFalse(emergency.contains { $0.color==Map3DPalette.tankStand },"No thick grey luggage cover")
        XCTAssertLessThanOrEqual(emergency.map(\.y).max() ?? 0,1.233)
    }
    func testRoofShouldersAreRoundedAndForeheadJoinsTheBody() {
        let m=Map3DMidiBus.model()
        func roofHeight(_ x: Float,_ y: Float) -> Float {
            3.50-ray(from:Map3DPoint(x,y,3.50),direction:Map3DPoint(0,0,-1),vertices:m.vertices)
        }
        let centre=roofHeight(-1,0)
        for y: Float in [-0.98,0.98] {
            let shoulder=roofHeight(-1,y)
            XCTAssertGreaterThan(centre-shoulder,0.16,"A full-width flat roof loses the reference's rounded shoulder")
            XCTAssertLessThan(centre-shoulder,0.30)
            XCTAssertGreaterThan(shoulder,2.72,"The crown stays above its supported body edge")
        }
        XCTAssertGreaterThan(roofHeight(2.70,0)-centre,0.08,"The raised forehead must flow above the rear roof")
        // Cross the crown/body join inwards from each side: the white
        // body's side remains behind the roof rather than leaving a hole.
        for y: Float in [-1,1] {
            XCTAssertLessThan(ray(from:Map3DPoint(0,y*1.24,2.70),direction:Map3DPoint(0,-y,0),vertices:m.vertices),0.051)
        }
    }
    func testWindowRibbonHasOutwardFacesBetweenPanes() {
        let m=Map3DMidiBus.model()
        for side: Float in [-1,1] {
            var ribbon=[Map3DVertex]()
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3])
                if t.allSatisfy({ $0.color==Map3DStreetModel.trim && $0.ny*side>0.9 }) { ribbon+=t }
            }
            XCTAssertEqual(ray(from:Map3DPoint(-2.89,side*1.25,2.10),direction:Map3DPoint(0,-side,0),vertices:ribbon),0.047,accuracy:0.001,"A reversed dark ribbon disappears and leaves white window frames")
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
            if skipGlass && vertices[i].color==Map3DMidiBus.windowColor { continue }
            let p=vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) },e=p[1]-p[0],f=p[2]-p[0],h=direction.cross(f),det=e.dot(h)
            if abs(det)<0.000001 { continue }
            let s=origin-p[0],u=s.dot(h)/det,q=s.cross(e),v=direction.dot(q)/det,d=f.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v<=1.00001 && d>0.00001 { result=min(result,d) }
        }
        return result
    }
}
