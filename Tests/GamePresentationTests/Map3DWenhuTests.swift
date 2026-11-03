import XCTest
@testable import GamePresentation

final class Map3DWenhuTests: XCTestCase {
    func testIndependentShellsAndRunningContact() {
        for far in [false,true] {
            let val=Map3DWenhuVAL256.model(.a,far:far)
            let apm=Map3DWenhuAPM256.model(.a,far:far)
            XCTAssertNotEqual(val.vertices,apm.vertices)
            for model in [val,apm,Map3DWenhuVAL256.model(.b,far:far),Map3DWenhuAPM256.model(.b,far:far)] {
                XCTAssertLessThanOrEqual(model.triangleCount,15_000)
                XCTAssertEqual(model.minimum.z,0,accuracy:0.001)
                XCTAssertLessThan(model.maximum.z,3.6)
                let axle: Float = model.name.contains("apm256") ? 5.0 : 4.65
                let lateral: Float = model.name.contains("apm256") ? 0.99 : 0.94
                for x in [-axle,axle] {
                    for y in [-lateral,lateral] {
                        XCTAssertTrue(model.vertices.contains { abs($0.x-x)<0.001 && abs($0.y-y)<0.14 && abs($0.z)<0.001 }, "Each of four load tyres must reach the running surface")
                    }
                }
            }
        }
    }
    func testRoleSpecificOuterCouplers() {
        for far in [false,true] {
            let a=Map3DWenhuAPM256.model(.a,far:far),b=Map3DWenhuAPM256.model(.b,far:far)
            let outerA=a.vertices.filter { $0.x>6.6 && abs($0.y)>0.20 }
            let outerB=b.vertices.filter { $0.x < -6.6 && abs($0.y)>0.20 }
            XCTAssertFalse(outerA.isEmpty)
            XCTAssertFalse(outerB.isEmpty)
            XCTAssertFalse(a.vertices.contains { $0.x < -6.6 && abs($0.y)>0.20 })
            XCTAssertFalse(b.vertices.contains { $0.x>6.6 && abs($0.y)>0.20 })
        }
    }
    func testLODsPreserveMetricEnvelopeWithinBudget() {
        let pairs = Map3DWenhuVAL256.Role.allCases.map { (Map3DWenhuVAL256.model($0),Map3DWenhuVAL256.model($0,far:true)) }
            + Map3DWenhuAPM256.Role.allCases.map { (Map3DWenhuAPM256.model($0),Map3DWenhuAPM256.model($0,far:true)) }
        for (near,far) in pairs {
            XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
            for (a,b) in [(near.minimum.x,far.minimum.x),(near.maximum.x,far.maximum.x),
                          (near.minimum.y,far.minimum.y),(near.maximum.y,far.maximum.y),
                          (near.minimum.z,far.minimum.z),(near.maximum.z,far.maximum.z)] {
                XCTAssertEqual(a,b,accuracy:0.0001)
            }
        }
    }

}
