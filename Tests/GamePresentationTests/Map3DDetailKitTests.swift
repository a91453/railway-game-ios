import Foundation
@testable import GamePresentation
import XCTest

final class Map3DDetailKitTests: XCTestCase {
    func testEveryCategoryHasSixteenDistinctUsableParts() {
        let parts=Map3DDetailKit.Part.allCases
        XCTAssertEqual(parts.count,96);XCTAssertEqual(Set(parts.map(\.id)).count,96)
        for c in Map3DDetailKit.Category.allCases { XCTAssertEqual(parts.filter { $0.category==c }.count,16) }
        // Same colours do not make unrelated objects the same mesh.
        let meshes=parts.map { Map3DDetailKit.model(for:$0).vertices }
        for i in meshes.indices { for j in 0..<i { XCTAssertNotEqual(meshes[i],meshes[j],parts[i].id+" / "+parts[j].id) } }
    }
    func testAllPartsPosesComponentsAndScenesAreFiniteClosedAndInBudget() {
        var models=Map3DDetailKit.Part.allCases.map { Map3DDetailKit.model(for:$0) }
        for p in Map3DDetailKit.Part.allCases where p.joint != nil {
            let c=Map3DDetailKit.components(for:p)
            models += [c.fixed,c.moving!,Map3DDetailKit.model(for:p,pose:p.joint!.limit.upperBound*0.63)]
        }
        models += Map3DDetailKit.Example.allCases.map { Map3DDetailKit.model(for:$0) }
        for m in models {
            XCTAssertGreaterThan(m.triangleCount,0,m.name)
            XCTAssertLessThanOrEqual(m.triangleCount,Map3DModelFile.maximumTriangles,m.name)
            XCTAssertTrue(m.vertices.contains { $0.nz < -0.5 },m.name+" has no underside")
            for v in m.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),m.name)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,m.name)
                XCTAssertEqual(v.color>>24,255,m.name)
            }
        }
    }
    func testMountingSurfacesReachTheWallCeilingOrGround() {
        for p in Map3DDetailKit.Part.allCases {
            let m=Map3DDetailKit.model(for:p)
            switch p.mount {
            case .wall: XCTAssertEqual(m.minimum.x,0,accuracy:0.001,p.id+" needs a wall mounting plate")
            case .ceiling: XCTAssertEqual(m.maximum.z,0,accuracy:0.001,p.id+" needs a ceiling fixing")
            case .ground,.roof: XCTAssertGreaterThanOrEqual(m.minimum.z,-0.04,p.id+" sinks")
                XCTAssertLessThanOrEqual(m.minimum.z,0.001,p.id+" floats")
            case .rail: break
            }
            for c in p.connectors {
                XCTAssertTrue([c.position.x,c.position.y,c.position.z].allSatisfy(\.isFinite))
                XCTAssertEqual(c.normal.dot(c.normal),1,accuracy:0.0001)
            }
        }
    }
    func testPipeAndTwoMetreSegmentsMeetWithoutGaps() throws {
        let straight=Map3DDetailKit.Part.wallPipeStraight,elbow=Map3DDetailKit.Part.wallPipeElbow
        let out=try XCTUnwrap(straight.connectors.first { $0.name=="pipe-out" })
        let input=try XCTUnwrap(elbow.connectors.first { $0.name=="pipe-in" })
        XCTAssertEqual(out.position-input.position,Map3DPoint(0,0,2))
        XCTAssertEqual(out.normal.dot(input.normal),-1)
        for p in [Map3DDetailKit.Part.cableTrough,.trackDrain,.guardRail,.maintenanceWalkway,.curbStraight] {
            let start=try XCTUnwrap(p.connectors.first { $0.name=="start" }),end=try XCTUnwrap(p.connectors.first { $0.name=="end" })
            XCTAssertEqual(end.position.x-start.position.x,2,accuracy:0.001)
            let m=Map3DDetailKit.model(for:p)
            XCTAssertEqual(m.minimum.x,start.position.x,accuracy:0.001,p.id)
            XCTAssertEqual(m.maximum.x,end.position.x,accuracy:0.001,p.id)
        }
    }
    func testJointMovesOnlyMovingBodyAndPreservesRigidDistances() throws {
        for p in Map3DDetailKit.Part.allCases where p.joint != nil {
            let j=try XCTUnwrap(p.joint),parts=Map3DDetailKit.components(for:p),moving=try XCTUnwrap(parts.moving)
            XCTAssertEqual(j.axis.dot(j.axis),1,accuracy:0.0001)
            let rest=Map3DDetailKit.model(for:p),value=j.limit.upperBound*0.63,posed=Map3DDetailKit.model(for:p,pose:value)
            XCTAssertEqual(Array(posed.vertices.prefix(parts.fixed.vertices.count)),parts.fixed.vertices,p.id)
            XCTAssertNotEqual(rest.vertices,posed.vertices,p.id)
            let posedBody=Array(posed.vertices.dropFirst(parts.fixed.vertices.count))
            XCTAssertEqual(posedBody.count,moving.vertices.count)
            for i in stride(from:0,to:moving.vertices.count,by:17) {
                let v=moving.vertices[i],a=Map3DPoint(v.x,v.y,v.z),b=Map3DPoint(posedBody[i].x,posedBody[i].y,posedBody[i].z)
                if j.kind == .rotation { XCTAssertEqual((a-j.pivot).dot(a-j.pivot),(b-j.pivot).dot(b-j.pivot),accuracy:0.0001,p.id) }
                else { let delta=b-a;XCTAssertEqual(delta.x,j.axis.x*value,accuracy:0.0001);XCTAssertEqual(delta.y,j.axis.y*value,accuracy:0.0001);XCTAssertEqual(delta.z,j.axis.z*value,accuracy:0.0001) }
            }
            XCTAssertEqual(Map3DDetailKit.model(for:p,pose:.nan).vertices,rest.vertices)
            XCTAssertEqual(Map3DDetailKit.model(for:p,pose:-999).vertices,rest.vertices)
            XCTAssertEqual(Map3DDetailKit.model(for:p,pose:999).vertices,Map3DDetailKit.model(for:p,pose:j.limit.upperBound).vertices)
        }
    }
    func testSelectedPackDoesNotIncludeTheEntireCatalogAndIsDeterministic() {
        let pack=Map3DModelPack(detailKit:[.windowGrille,.trafficCone])
        XCTAssertEqual(pack.models.count,2)
        XCTAssertEqual(pack.models.map(\.name),["detail-windowGrille","detail-trafficCone"])
        let a=Map3DDetailKit.model(for:.shopShelf)
        _=Map3DDetailKit.model(for:.gasCage)
        XCTAssertEqual(a.vertices,Map3DDetailKit.model(for:.shopShelf).vertices)
    }
}
