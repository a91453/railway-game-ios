import XCTest
@testable import GamePresentation

final class Map3DEMU800Tests: XCTestCase {
    func testFormationUsesFourEquipmentRolesAndOppositeHalf() {
        XCTAssertEqual(Map3DEMU800.sequence,[.ed,.ema,.ep,.emb,.emb,.ep,.ema,.ed])
        let p=Map3DEMU800.placements
        XCTAssertEqual(p.filter {$0.role == .ep}.map {$0.reversed},[false,true])
        for i in 1..<p.count {
            let pitch:Float=(p[i-1].role == .ed ? 21.6:20.3)/2+(p[i].role == .ed ? 21.6:20.3)/2
            XCTAssertEqual(p[i-1].x-p[i].x,pitch,accuracy:0.0001)
        }
        for far in [false,true] {
            let assembled=Map3DEMU800.formation(far:far)
            XCTAssertEqual(assembled.triangleCount,p.reduce(0){$0+Map3DEMU800.model($1.role,reversed:$1.reversed,far:far).triangleCount})
            XCTAssertEqual(assembled.minimum.z,0,accuracy:0.00001)
        }
    }
    func testActualReversePayloadIsExactlyOneHalfTurn() {
        for role in Map3DEMU800.Role.allCases {for far in [false,true] {
            let a=Map3DEMU800.model(role,far:far),b=Map3DEMU800.model(role,reversed:true,far:far)
            XCTAssertLessThanOrEqual(a.triangleCount,15000)
            XCTAssertEqual(a.vertices.count,b.vertices.count)
            for (u,v) in zip(a.vertices,b.vertices) {
                XCTAssertEqual(v.x,-u.x);XCTAssertEqual(v.y,-u.y);XCTAssertEqual(v.z,u.z)
                XCTAssertEqual(v.nx,-u.nx);XCTAssertEqual(v.ny,-u.ny);XCTAssertEqual(v.nz,u.nz)
                XCTAssertEqual(v.color,u.color);XCTAssertEqual(v.layer,u.layer)
            }
        }}
    }
    func testPantographBelongsOnlyToEPAndRetainsTwoACs() {
        for far in [false,true] {
            for role in Map3DEMU800.Role.allCases {
                let m=Map3DEMU800.model(role,far:far)
                XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
                if role == .ep {XCTAssertGreaterThan(m.maximum.z,5)}else{XCTAssertLessThan(m.maximum.z,4)}
                let top=m.vertices.filter {$0.z>3.93&&$0.z<4.0}
                XCTAssertTrue(top.contains {$0.x<0});XCTAssertTrue(top.contains {$0.x>0})
            }
        }
    }
    func testStaticRegistrationKeepsTheOperatingMappingAndLastBus() {
        let pack=Map3DModelPack.standard
        XCTAssertNotNil(pack.models.first {$0.name=="emu800-ed"})
        XCTAssertEqual(pack.models.last(where: { !$0.name.hasPrefix(Map3DTrainLights.prefix) })?.name,Map3DLowFloorBus.routeModel().name)
        // Decision 432: the operating key now runs these units (Map3DEMU800IntegrationTests).
        XCTAssertEqual(Map3DTrainSet.byKey["emu800"]?.ownLengths,true)
        XCTAssertEqual(Map3DTrainSet.byKey["emu800"]?.far,"emu800Far")
        XCTAssertFalse(TrainPack.sets.contains("emu800"))
    }
}
