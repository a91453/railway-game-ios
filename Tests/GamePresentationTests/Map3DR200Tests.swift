import XCTest
@testable import GamePresentation

final class Map3DR200Tests: XCTestCase {
    func testIndependentCompleteLocomotivesShareRailAndEnvelope() {
        let near=Map3DR200.model(), far=Map3DR200.model(far:true)
        XCTAssertEqual(near.name,Map3DR200.ids[0])
        XCTAssertEqual(far.name,Map3DR200.ids[1])
        for m in [near,far] {
            XCTAssertLessThanOrEqual(m.triangleCount,15000)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
            XCTAssertEqual(m.maximum.z,4.08,accuracy:0.001)
            XCTAssertEqual(m.minimum.x,-10.005,accuracy:0.001)
            XCTAssertEqual(m.maximum.x,10.005,accuracy:0.001)
            XCTAssertTrue(m.vertices.allSatisfy { [$0.x,$0.y,$0.z,$0.nx,$0.ny,$0.nz].allSatisfy(\.isFinite) })
        }
        XCTAssertEqual(near.minimum,far.minimum)
        XCTAssertEqual(near.maximum,far.maximum)
        XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
    }
    func testBothCabEndsAndTwelveWheelPositionsActuallyExist() {
        for far in [false,true] {
            let m=Map3DR200.model(far:far)
            for end:Float in [-1,1] {
                XCTAssertTrue(m.vertices.contains { end*$0.x>8.7 && $0.z>3.0 && $0.z<3.5 })
            }
            for centre:Float in [-5.9,5.9] {
                for dx:Float in [-1.5,0,1.5] {
                    for side:Float in [-1,1] {
                        XCTAssertTrue(m.vertices.contains { abs($0.x-centre-dx)<0.001 && abs($0.z)<0.001 && side*$0.y>0.47 && side*$0.y<0.69 })
                    }
                }
            }
        }
    }
}
