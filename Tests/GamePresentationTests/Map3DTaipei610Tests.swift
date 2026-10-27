import XCTest
@testable import GamePresentation

final class Map3DTaipei610Tests: XCTestCase {
    func testDedicatedRolesAndThirdRailEnvelope() {
        XCTAssertEqual(Map3DTaipei610.sequence, [.a,.c,.d,.b])
        for r in Map3DTaipei610.Role.allCases {
            let near=Map3DTaipei610.model(r), far=Map3DTaipei610.model(r,far:true), light=Map3DTaipei610.model(r,light:true)
            for m in [near,far,light] {
                XCTAssertLessThanOrEqual(m.triangleCount,15000)
                XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
                XCTAssertLessThan(m.maximum.z,3.65,"No invented overhead collection gear")
                XCTAssertTrue(m.vertices.allSatisfy {$0.x.isFinite && $0.y.isFinite && $0.z.isFinite})
            }
            XCTAssertLessThan(far.triangleCount,near.triangleCount)
            XCTAssertLessThan(light.triangleCount,far.triangleCount)
        }
    }
    func testRearIsReversedOnceAndFormationUsesFinalUnits() {
        let head=Map3DTaipei610.model(.a),tail=Map3DTaipei610.model(.b)
        XCTAssertEqual(head.vertices.count,tail.vertices.count)
        for (a,b) in zip(head.vertices,tail.vertices) {
            XCTAssertEqual(a.x,-b.x);XCTAssertEqual(a.y,-b.y);XCTAssertEqual(a.z,b.z)
            XCTAssertEqual(a.nx,-b.nx);XCTAssertEqual(a.ny,-b.ny);XCTAssertEqual(a.nz,b.nz)
            XCTAssertEqual(a.color,b.color)
        }
        for level in 0..<3 {
            let formation=Map3DTaipei610.formation(far:level==1,light:level==2)
            XCTAssertEqual(formation.triangleCount,Map3DTaipei610.sequence.reduce(0){$0+Map3DTaipei610.model($1,far:level==1,light:level==2).triangleCount})
            XCTAssertEqual(formation.minimum.z,0,accuracy:0.0001)
        }
    }
}
