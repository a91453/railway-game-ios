import XCTest
@testable import GamePresentation

final class Map3DEMU900Tests: XCTestCase {
    func testPublishedTenCarPitchAndAsymmetricEquipmentOrder() {
        let ps=Map3DEMU900.placements
        XCTAssertEqual(ps.count,10)
        XCTAssertEqual(ps.filter { $0.role == .epCompressor || $0.role == .epAccessible }.count,3)
        XCTAssertEqual(ps[5].role,.epAccessible)
        XCTAssertEqual(ps[4].role,.emCrew)
        XCTAssertEqual(ps.first!.x-ps.last!.x+21.58,205.56,accuracy:0.001)
        XCTAssertFalse(ps[2].reversed)
        XCTAssertTrue(ps[5].reversed)
        XCTAssertTrue(ps[7].reversed)
        for i in 1..<ps.count {
            let a:Float=ps[i-1].role == .ed ? 21.58:20.30
            let b:Float=ps[i].role == .ed ? 21.58:20.30
            XCTAssertEqual(ps[i-1].x-ps[i].x,(a+b)/2,accuracy:0.0001)
        }
    }
    func testEveryDeliveredRoleHasLegalNearFarAndExactReverse() {
        for role in Map3DEMU900.Role.allCases {for far in [false,true] {
            let m=Map3DEMU900.model(role,far:far),r=Map3DEMU900.model(role,reversed:true,far:far)
            XCTAssertLessThanOrEqual(m.triangleCount,Map3DModelFile.maximumTriangles)
            XCTAssertGreaterThan(m.triangleCount,100)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertEqual(m.vertices.count,r.vertices.count)
            for (a,b) in zip(m.vertices,r.vertices) {
                XCTAssertEqual(a.x,-b.x);XCTAssertEqual(a.y,-b.y);XCTAssertEqual(a.z,b.z)
                XCTAssertEqual(a.nx,-b.nx);XCTAssertEqual(a.ny,-b.ny);XCTAssertEqual(a.nz,b.nz)
                XCTAssertEqual(a.color,b.color);XCTAssertEqual(a.layer,b.layer)
            }
            XCTAssertFalse(m.vertices.contains {$0.color == Map3DColor.rgb(0xFFC86B)})
        }}
    }
    func testFormationUsesTheFinalUnitsWithoutScaleOrSecondRotation() {
        for far in [false,true] {
            let full=Map3DEMU900.formation(far:far)
            XCTAssertEqual(full.triangleCount,Map3DEMU900.placements.reduce(0){$0+Map3DEMU900.model($1.role,far:far).triangleCount})
            var cursor=0
            for p in Map3DEMU900.placements {
                let unit=Map3DEMU900.model(p.role,reversed:p.reversed,far:far)
                for v in unit.vertices {
                    let actual=full.vertices[cursor];cursor+=1
                    XCTAssertEqual(actual.x,v.x+p.x,accuracy:0.0001)
                    XCTAssertEqual(actual.y,v.y,accuracy:0.00001)
                    XCTAssertEqual(actual.z,v.z,accuracy:0.00001)
                    XCTAssertEqual(actual.color,v.color)
                }
            }
        }
    }
}
