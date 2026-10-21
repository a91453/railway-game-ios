import Foundation
@testable import GamePresentation
import XCTest

final class Map3DResidentialKitTests: XCTestCase {
    func testDistinctCatalogAndOnDemandPack() {
        let parts = Map3DResidentialKit.Part.allCases
        XCTAssertEqual(parts.count,24)
        XCTAssertEqual(Set(parts.map(\.id)).count,24)
        for category in Map3DResidentialKit.Category.allCases {
            XCTAssertEqual(parts.filter { $0.category == category }.count,8)
        }
        let models=parts.map(Map3DResidentialKit.model(for:))
        for i in models.indices { for j in 0..<i {
            XCTAssertNotEqual(models[i].vertices,models[j].vertices,parts[i].id)
        } }
        let pack=Map3DModelPack(residentialKit:[.ironGate,.roofSolar])
        XCTAssertEqual(pack.models.count,2)
        XCTAssertEqual(pack.index(of:"residential-roofSolar"),1)
    }

    func testClosedOpaqueGeometryAndSceneTriangleBudget() {
        let models=Map3DResidentialKit.Part.allCases.map(Map3DResidentialKit.model(for:))
            + Map3DResidentialKit.Example.allCases.map(Map3DResidentialKit.model(for:))
        for model in models {
            XCTAssertGreaterThan(model.triangleCount,0,model.name)
            XCTAssertLessThanOrEqual(model.triangleCount,15_000,model.name)
            XCTAssertTrue(model.vertices.contains { $0.nz < -0.5 },model.name)
            for vertex in model.vertices {
                XCTAssertTrue([vertex.x,vertex.y,vertex.z,vertex.nx,vertex.ny,vertex.nz].allSatisfy(\.isFinite),model.name)
                XCTAssertEqual(vertex.color >> 24,255,model.name)
            }
        }
    }

    func testMountPlanesAndConnectorNormals() {
        for part in Map3DResidentialKit.Part.allCases {
            let model=Map3DResidentialKit.model(for:part)
            if part.mount == .ground { XCTAssertEqual(model.minimum.z,0,accuracy:0.04,part.id) }
            else { XCTAssertEqual(model.minimum.x,0,accuracy:0.0001,part.id) }
            for port in part.connectors {
                XCTAssertEqual(port.normal.dot(port.normal),1,accuracy:0.0001,part.id)
            }
        }
    }

    func testHomeWindowsHaveSolidBacking() {
        let frontGlass=Map3DColor.shaded(Map3DPalette.glazing,0.92)
        for part in Map3DResidentialKit.Part.allCases where part.category == .home {
            let vertices=Map3DResidentialKit.model(for:part).vertices
            var count=0
            for i in stride(from:0,to:vertices.count,by:3) {
                let face=Array(vertices[i..<i+3])
                guard face.allSatisfy({ $0.color == frontGlass && $0.nx > 0.8 }) else { continue }
                let center=face.reduce(Map3DPoint.zero) { $0 + Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                XCTAssertLessThan(backingDistance(from:center+Map3DPoint(0.001,0,0),vertices:vertices),0.20,part.id)
                count += 1
            }
            XCTAssertGreaterThan(count,0,part.id)
        }
    }

    func testArcadePostsAndBalconyBracketsActuallyMeet() {
        let arcade=Map3DResidentialKit.model(for:.arcadeTownhouse)
        for side: Float in [-1,1] {
            for height: Float in [0.18,3.23] {
                XCTAssertTrue(arcade.vertices.contains {
                    $0.x > 2.4 && $0.x < 3.1 && abs($0.y-side*3.25)<0.36 && abs($0.z-height)<0.01
                })
            }
        }
        let balcony=Map3DResidentialKit.model(for:.balconyModule)
        XCTAssertEqual(balcony.minimum.x,0,accuracy:0.0001)
        XCTAssertTrue(balcony.vertices.contains { abs($0.x-0.09)<0.06 && abs($0.z-0.42)<0.06 })
        XCTAssertTrue(balcony.vertices.contains { abs($0.x-1.43)<0.06 && abs($0.z-0.10)<0.06 })
    }

    func testApartmentBalconiesHaveBackedDoorsOnEveryUpperFloor() {
        let vertices=Map3DResidentialKit.model(for:.walkupApartment).vertices
        let frontGlass=Map3DColor.shaded(Map3DPalette.glazing,0.92)
        for floor in 1...3 {
            let low=Float(floor)*3+0.45,high=low+1.96
            XCTAssertTrue(vertices.contains {
                $0.color == frontGlass && $0.nx > 0.8 && $0.x > 3.84 && $0.x < 3.91
                    && abs($0.y)<0.7 && $0.z >= low && $0.z <= high
            },"Missing balcony door on floor \(floor)")
        }
    }

    func testSolarPanelHasARealUnderside() {
        let vertices=Map3DResidentialKit.model(for:.roofSolar).vertices
        XCTAssertTrue(stride(from:0,to:vertices.count,by:3).contains { i in
            let face=vertices[i..<i+3]
            let center=face.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            return face.allSatisfy { $0.color == Map3DPalette.tankStand && $0.nz < -0.8 }
                && center.z > 0.4 && center.z < 0.9 && abs(center.y) < 1.0
        })
    }

    func testDeterministicAssembly() {
        let first=Map3DResidentialKit.model(for:.roofGarden)
        _=Map3DResidentialKit.model(for:.ruralCourtyard)
        XCTAssertEqual(first.vertices,Map3DResidentialKit.model(for:.roofGarden).vertices)
    }

    private func backingDistance(from origin: Map3DPoint,vertices: [Map3DVertex]) -> Float {
        let direction=Map3DPoint(-1,0,0)
        var result=Float.infinity
        for i in stride(from:0,to:vertices.count,by:3) {
            if vertices[i].color == Map3DPalette.glazing { continue }
            let points=vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) }
            let edge=points[1]-points[0],other=points[2]-points[0],h=direction.cross(other),det=edge.dot(h)
            if abs(det)<0.000001 { continue }
            let s=origin-points[0],u=s.dot(h)/det,q=s.cross(edge),v=direction.dot(q)/det,d=other.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v <= 1.00001 && d>0.00001 { result=min(result,d) }
        }
        return result
    }
}
