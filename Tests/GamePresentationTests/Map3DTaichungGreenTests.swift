import XCTest
@testable import GamePresentation

final class Map3DTaichungGreenTests: XCTestCase {
    func testStaticStudiesDoNotChangeOperatingPack() throws {
        XCTAssertFalse(Map3DModelPack.standard.models.contains { $0.name.hasPrefix("taichung-green-") })
        for role in Map3DTaichungGreen.Role.allCases {
            let near=Map3DTaichungGreen.model(role), far=Map3DTaichungGreen.model(role,far:true)
            XCTAssertNotNil(Map3DModelPack.studies.index(of:near.name))
            XCTAssertLessThan(near.triangleCount,Map3DModelFile.maximumTriangles)
            XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
            for model in [near,far] {
                XCTAssertEqual(model.length,22.17,accuracy:0.0001)
                XCTAssertEqual(model.minimum.z,0,accuracy:0.0001)
                XCTAssertEqual(model.maximum.z,3.78,accuracy:0.0001)
                XCTAssertEqual(model.maximum.y-model.minimum.y,2.98,accuracy:0.0001)
            }
        }
    }
    func testDMEquipmentDifferenceAndRotation() {
        let a=Map3DTaichungGreen.model(.dm1),b=Map3DTaichungGreen.model(.dm2)
        XCTAssertEqual(a.triangleCount,b.triangleCount)
        XCTAssertNotEqual(a.vertices.map(\.position),b.vertices.map(\.position))
        var builder=StationKitBuilder()
        builder.add(a,at:Map3DPoint(11.085,0,0))
        builder.add(b,at:Map3DPoint(-11.085,0,0),angle:.pi)
        let whole=Map3DModelPack.Model.flat(named:"independent-tg-formation",from:builder.mesh)
        XCTAssertEqual(whole.length,44.34,accuracy:0.0001)
        XCTAssertEqual(whole.triangleCount,a.triangleCount+b.triangleCount)
        XCTAssertGreaterThan(whole.vertices.filter { $0.x>20 && $0.nx>0.7 }.count,20)
        XCTAssertGreaterThan(whole.vertices.filter { $0.x < -20 && $0.nx < -0.7 }.count,20)
    }
}
