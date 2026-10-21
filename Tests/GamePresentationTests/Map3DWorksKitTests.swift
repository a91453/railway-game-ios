import Foundation
@testable import GamePresentation
import XCTest

final class Map3DWorksKitTests: XCTestCase {
    func testFourCategoriesHaveTwelveDistinctModelsEach() {
        let parts=Map3DWorksKit.Part.allCases
        XCTAssertEqual(parts.count,48);XCTAssertEqual(Set(parts.map(\.id)).count,48)
        for c in Map3DWorksKit.Category.allCases { XCTAssertEqual(parts.filter { $0.category==c }.count,12) }
        let models=parts.map(Map3DWorksKit.model(for:))
        for i in models.indices { for j in 0..<i { XCTAssertNotEqual(models[i].vertices,models[j].vertices,parts[i].id+" / "+parts[j].id) } }
    }
    func testModelsAndAssembliesAreFiniteOpaqueAndHaveUndersidesWithinBudget() {
        let models=Map3DWorksKit.Part.allCases.map(Map3DWorksKit.model(for:))+Map3DWorksKit.Example.allCases.map(Map3DWorksKit.model(for:))
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
    func testGroundAssetsTouchGroundAndConnectorsUseNativeAxes() {
        for p in Map3DWorksKit.Part.allCases {
            let m=Map3DWorksKit.model(for:p)
            if p.mount == .ground {
                XCTAssertLessThanOrEqual(m.minimum.z,0.001,p.id+" floats")
                XCTAssertGreaterThanOrEqual(m.minimum.z,-0.04,p.id+" sinks")
            }
            for c in p.connectors { XCTAssertEqual(c.normal.dot(c.normal),1,accuracy:0.0001) }
        }
        XCTAssertEqual(Map3DWorksKit.Part.koi.connectors[0].position.z,0.13)
        XCTAssertEqual(Map3DWorksKit.Part.railCrane.mount,.rail)
    }
    func testStackingContainerConnectorMeetsTheHighestCornerCastings() throws {
        for p in [Map3DWorksKit.Part.container20,.container40] {
            let m=Map3DWorksKit.model(for:p),top=try XCTUnwrap(p.connectors.first { $0.name=="stack" })
            XCTAssertEqual(m.maximum.z,top.position.z,accuracy:0.0001)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
            XCTAssertEqual(m.maximum.y-m.minimum.y,2.485,accuracy:0.02)
        }
    }
    func testVehicleWindshieldsHaveSolidCabGeometryImmediatelyBehind() {
        for p in [Map3DWorksKit.Part.excavator,.forklift,.roadRoller,.dumpTruck,.serviceTruck] {
            let m=Map3DWorksKit.model(for:p)
            var checked=0
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3]);guard t.allSatisfy({ $0.color==Map3DPalette.glazing && $0.nx>0.8 }) else { continue }
                let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                XCTAssertLessThan(ray(from:c+Map3DPoint(0.001,0,0),direction:Map3DPoint(-1,0,0),vertices:m.vertices),0.12,p.id);checked+=1
            }
            if p != .forklift { XCTAssertGreaterThan(checked,0,p.id) }
        }
    }
    func testOnDemandPackIsSmallAndDeterministic() {
        let a=Map3DWorksKit.model(for:.stationCat)
        _=Map3DWorksKit.model(for:.excavator)
        XCTAssertEqual(a.vertices,Map3DWorksKit.model(for:.stationCat).vertices)
        let pack=Map3DModelPack(worksKit:[.stationCat,.forklift])
        XCTAssertEqual(pack.models.count,2);XCTAssertEqual(pack.index(of:"works-forklift"),1)
    }
    private func ray(from origin: Map3DPoint,direction: Map3DPoint,vertices: [Map3DVertex]) -> Float {
        var result=Float.infinity
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
