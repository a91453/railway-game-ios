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
                for x: Float in [-4.65,4.65] {
                    for y: Float in [-0.94,0.94] {
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
}
