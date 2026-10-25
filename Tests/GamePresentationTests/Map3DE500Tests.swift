import XCTest
@testable import GamePresentation

final class Map3DE500Tests: XCTestCase {
    func testActualE500DispatchAndFarKeepDedicatedGeometry() throws {
        for key in ["E500CK", "MINGRI", "STAR"] {
            let near=try XCTUnwrap(Map3DTrainSet.named(key)), far=try XCTUnwrap(Map3DTrainSet.named(key+"Far"))
            XCTAssertEqual(near.far,key+"Far")
            XCTAssertTrue(near.ownLengths)
            XCTAssertEqual(near.build().head.vertices,Map3DE500.model().vertices)
            XCTAssertEqual(far.build().head.vertices,Map3DE500.model(far:true).vertices)
            XCTAssertEqual(Map3DTrainSet.reach(of:key),500)
            XCTAssertEqual(near.build().middle?.vertices,far.build().middle?.vertices)
        }
    }
    func testPackActuallySelectsNearFarAndExistingBoxFallback() throws {
        let pack=Map3DModelPack.standard
        for key in ["E500CK", "MINGRI", "STAR"] {
            let near=try XCTUnwrap(pack.index(of:"set-"+key+"-head"))
            let far=try XCTUnwrap(pack.index(of:"set-"+key+"Far-head"))
            XCTAssertEqual(pack.model(near,forType:key,count:7,at:499),near)
            XCTAssertEqual(pack.model(near,forType:key,count:7,at:500),far)
            XCTAssertNil(pack.model(near,forType:key,count:7,at:900))
            let layout=try XCTUnwrap(pack.layout(forType:key,count:7))
            XCTAssertEqual(layout.count,7)
            XCTAssertEqual(layout[0].length,20.77,accuracy:0.0001)
            XCTAssertEqual(pack.models[near].vertices,Map3DE500.model().vertices)
        }
    }
    func testNativeGeometryAtRailDatumAndMeasuredBudget() {
        for far in [false,true] {
            let m=Map3DE500.model(far:far)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertEqual(m.length,20.77,accuracy:0.0001)
            XCTAssertTrue(m.triangleCount<(far ? 3100:6000))
            XCTAssertTrue(m.maximum.z>5.2 && m.maximum.z<5.5) // raised collector; not stowed height
            for v in m.vertices {
                XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
            }
        }
    }
}
