import Foundation
@testable import GamePresentation
import XCTest

final class Map3DResidentialKitTests: XCTestCase {
    func testDistinctCatalogAndOnDemandPack() {
        let parts = Map3DResidentialKit.Part.allCases
        XCTAssertEqual(parts.count,26)
        XCTAssertEqual(Set(parts.map(\.id)).count,26)
        for category in Map3DResidentialKit.Category.allCases {
            XCTAssertEqual(parts.filter { $0.category == category }.count,category == .home ? 10 : 8)
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

    func testRevisedRoofTypesAndLODColours() {
        for p: Map3DResidentialKit.Part in [.courtyardHouse,.oldNarrowTownhouse,.oldShophouse] {
            let near=Map3DResidentialKit.model(for:p,far:false),far=Map3DResidentialKit.model(for:p,far:true)
            XCTAssertGreaterThan(near.triangleCount,far.triangleCount)
            XCTAssertEqual(near.minimum,far.minimum)
            XCTAssertEqual(near.maximum.z,far.maximum.z,accuracy:0.001)
            let brick=Map3DColor.shaded(Map3DPalette.templeRidge,0.92)
            XCTAssertTrue(near.vertices.contains { $0.color==brick })
            XCTAssertTrue(far.vertices.contains { $0.color==brick })
            print("ROOF-COST \(p.id) near=\(near.triangleCount) far=\(far.triangleCount)")
        }
        let modern=Map3DResidentialKit.model(for:.narrowTownhouse,far:false)
        XCTAssertEqual(modern.vertices,Map3DResidentialKit.model(for:.narrowTownhouse,far:true).vertices)
        XCTAssertEqual(modern.vertices,Map3DResidentialKit.model(for:.narrowTownhouse,far:false,traditional:false).vertices)
        XCTAssertEqual(modern.maximum.z,10.13,accuracy:0.01)
        let horse=Map3DResidentialKit.horsebackGable(),coarse=Map3DResidentialKit.horsebackGable(far:true)
        XCTAssertEqual(horse.minimum,coarse.minimum);XCTAssertEqual(horse.maximum,coarse.maximum)
        XCTAssertGreaterThan(horse.triangleCount,coarse.triangleCount)
        print("HORSE-COST near=\(horse.triangleCount) far=\(coarse.triangleCount)")
        let shop=Map3DResidentialKit.model(for:.oldShophouse,far:false)
        XCTAssertGreaterThan(shop.maximum.z,7.8)
        let units=shop.vertices.filter { $0.color==Map3DPalette.acUnit }
        XCTAssertEqual(units.map(\.x).min()!,4.49,accuracy:0.001,"AC back must meet the real facade")
        let tiles=shop.vertices.filter { $0.color==Map3DPalette.templeRoof }
        XCTAssertLessThan(tiles.map(\.x).max()!,4.27,"The pitched roof must stay behind the street parapet")
        var facade=StationKitBuilder();facade.oldHouseFacade(0,0,0,width:5.3,floors:1)
        XCTAssertEqual(facade.mesh.triangleCount,44)
        var distant=StationKitBuilder();distant.oldHouseFacade(0,0,0,width:5.3,floors:1,far:true)
        XCTAssertEqual(distant.mesh.triangleCount,24)
    }

    func testHardRoofHasStraightTileRidgeAndRoundPlasterGables() {
        var b=StationKitBuilder()
        b.residentialHardRoof(0,0.08,0,length:8,width:4,rise:1,far:false)
        let m=Map3DModelPack.Model.flat(named:"hard-roof",from:b.mesh)
        let tile=m.vertices.filter { $0.color==Map3DPalette.templeRoof }
        XCTAssertEqual(tile.map(\.z).max()!,1.08,accuracy:0.001)
        XCTAssertTrue(tile.filter { abs($0.z-1.08)<0.001 }.allSatisfy { abs($0.y)<0.001 })
        let plaster=m.vertices.filter { $0.color==Map3DPalette.tileWhite }
        XCTAssertGreaterThan(plaster.map(\.z).max()!,1.4)
        XCTAssertTrue(plaster.contains { $0.z>1.1 && $0.z<1.4 })
        for v in m.vertices { XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite)) }
    }

    func testSteppedParapetCapsDoNotFillTheRecesses() {
        var b=StationKitBuilder()
        b.residentialProfile([(0,0),(4,0),(4,4),(3,4),(3,1),(1,1),(1,4),(0,4)],
            at:.zero,along:StationKitBuilder.forward,depth:0.2,color:Map3DPalette.tileWhite)
        let m=Map3DModelPack.Model.flat(named:"stepped-crown",from:b.mesh)
        var area: Float=0
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=m.vertices[i..<i+3];guard t.allSatisfy({abs($0.nx)>0.99}) else { continue }
            let p=t.map { Map3DPoint($0.x,$0.y,$0.z) }
            let n=(p[1]-p[0]).cross(p[2]-p[0]);area+=sqrt(n.dot(n))/2
        }
        // Two caps, each 4*4 minus a 2*3 recess.
        XCTAssertEqual(area,20,accuracy:0.001)
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
