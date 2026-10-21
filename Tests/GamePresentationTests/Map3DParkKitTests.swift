import Foundation
@testable import GamePresentation
import XCTest

final class Map3DParkKitTests: XCTestCase {
    func testCatalogHasThreeCategoriesOfTwelveDistinctModels() {
        let parts=Map3DParkKit.Part.allCases
        XCTAssertEqual(parts.count,36);XCTAssertEqual(Set(parts.map(\.id)).count,36)
        for c in Map3DParkKit.Category.allCases { XCTAssertEqual(parts.filter { $0.category==c }.count,12) }
        let models=parts.map(Map3DParkKit.model(for:))
        for i in models.indices { for j in 0..<i { XCTAssertNotEqual(models[i].vertices,models[j].vertices,parts[i].id) } }
    }
    func testPartsAndAssembliesAreFiniteOpaqueWithUndersidesWithinBudget() {
        let models=Map3DParkKit.Part.allCases.map(Map3DParkKit.model(for:))+Map3DParkKit.Example.allCases.map(Map3DParkKit.model(for:))
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
    func testGroundPlanesAndConnectorNormals() {
        for p in Map3DParkKit.Part.allCases {
            let m=Map3DParkKit.model(for:p)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.001,p.id+" floats or sinks")
            for c in p.connectors { XCTAssertEqual(c.normal.dot(c.normal),1,accuracy:0.0001) }
        }
    }
    func testBridgeDeckEndsMeetConnectorHeightAndCentreIsArched() throws {
        let p=Map3DParkKit.Part.archedFootbridge,m=Map3DParkKit.model(for:p)
        for c in p.connectors where c.name != "mount" {
            XCTAssertTrue(m.vertices.contains { abs($0.x-c.position.x)<0.0001 && abs($0.z-c.position.z)<0.0001 && $0.color==StationKitBuilder.parkWood })
        }
        XCTAssertTrue(m.vertices.contains { abs($0.x)<0.0001 && abs($0.z-0.87)<0.0001 && $0.color==StationKitBuilder.parkWood })
        let a=try XCTUnwrap(p.connectors.first { $0.name=="start" }),b=try XCTUnwrap(p.connectors.first { $0.name=="end" })
        XCTAssertEqual(b.position.x-a.position.x,5,accuracy:0.0001)
    }
    func testSuspensionMeetsSeatsDeckAndCrossbar() throws {
        let m=Map3DParkKit.model(for:.swingSet),ropes=m.vertices.filter { $0.color==StationKitBuilder.steel },seats=m.vertices.filter { $0.color==StationKitBuilder.parkWood },bar=m.vertices.filter { $0.color==StationKitBuilder.parkRed }
        let bottom=try XCTUnwrap(ropes.map(\.z).min()),top=try XCTUnwrap(ropes.map(\.z).max()),seat=try XCTUnwrap(seats.map(\.z).max())
        XCTAssertEqual(bottom,seat,accuracy:0.0001)
        XCTAssertGreaterThan(top,try XCTUnwrap(bar.map(\.z).min()))
        XCTAssertLessThan(top,try XCTUnwrap(bar.map(\.z).max()))
        let bridge=Map3DParkKit.model(for:.ropeBridge)
        let lower=bridge.vertices.filter { $0.color==StationKitBuilder.steel && $0.z<1 }
        XCTAssertGreaterThan(lower.count,0)
        XCTAssertTrue(lower.allSatisfy { abs($0.y)<=0.565 },"Lower suspension must reach the 1.1 m-wide deck edge")
        XCTAssertEqual(ropes.filter { abs($0.z-bottom)<0.0001 }.map(\.y).min()!,-1.098,accuracy:0.02)
    }
    func testOnDemandPackAndRebuildAreDeterministic() {
        let a=Map3DParkKit.model(for:.gazebo);_=Map3DParkKit.model(for:.slide)
        XCTAssertEqual(a.vertices,Map3DParkKit.model(for:.gazebo).vertices)
        let pack=Map3DModelPack(parkKit:[.gazebo,.slide]);XCTAssertEqual(pack.models.count,2);XCTAssertEqual(pack.index(of:"park-slide"),1)
    }
}
