import XCTest
@testable import GamePresentation

final class Map3DE1000Tests: XCTestCase {
    func testOfficialCouplerLengthRailDatumAndNativeNormals() {
        for far in [false,true] {
            let m=Map3DE1000.model(far:far)
            XCTAssertEqual(m.maximum.x-m.minimum.x,17.211,accuracy:0.00001)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertLessThanOrEqual(m.triangleCount,far ? 4_100:6_000)
            for v in m.vertices {
                XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.00001)
            }
        }
    }
    func testOneStreamlinedCabAndASeparateRearPassage() {
        for far in [false,true] {
            let m=Map3DE1000.model(far:far)
            let cab=m.vertices.filter{$0.color==Map3DE1000.glassColor && $0.x>6 && $0.z>2.6}
            let rear=m.vertices.filter{$0.color==Map3DE1000.glassColor && $0.x < -8.25}
            XCTAssertFalse(cab.isEmpty)
            XCTAssertFalse(rear.isEmpty)
            XCTAssertGreaterThan(m.vertices.filter{$0.x < -8.4 && $0.z>3}.count,0)
            XCTAssertLessThan(m.vertices.filter{$0.x > 8.4 && $0.z>3}.count,1)
        }
    }
    func testNearFarKeepMainSilhouetteBoundsAndBodyIsNotAnE500Clone() {
        let a=Map3DE1000.model(),b=Map3DE1000.model(far:true)
        XCTAssertEqual(a.minimum,b.minimum)
        XCTAssertEqual(a.maximum,b.maximum)
        XCTAssertNotEqual(a.vertices.count,Map3DE500.model().vertices.count)
        XCTAssertLessThan(a.length,Map3DE500.model().length)
    }
}
