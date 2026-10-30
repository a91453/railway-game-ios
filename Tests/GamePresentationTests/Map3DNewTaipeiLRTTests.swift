import XCTest
@testable import GamePresentation

final class Map3DNewTaipeiLRTTests: XCTestCase {
    func testIndependentFleetIdentityAndLegalUnits() throws {
        let pack=Map3DModelPack.studies
        for fleet in ["ankeng","danhai"] { for role in ["m1","m2","m3","m4","m5"] {
            let id="\(fleet)-lrt-\(role)"
            let near=try XCTUnwrap(pack.index(of:id)).mapModel(pack)
            let far=try XCTUnwrap(pack.index(of:id+"-far")).mapModel(pack)
            XCTAssertLessThan(near.triangleCount,15001)
            XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
            for axis in 0..<3 {
                let a=[near.minimum.x,near.minimum.y,near.minimum.z][axis]
                let b=[far.minimum.x,far.minimum.y,far.minimum.z][axis]
                XCTAssertEqual(a,b,accuracy:0.001)
            }
            if role == "m2" || role == "m4" { XCTAssertGreaterThan(near.minimum.z,0.24) }
            else { XCTAssertEqual(near.minimum.z,0,accuracy:0.00001) }
            XCTAssertNil(Map3DModelPack.standard.index(of:id))
        }}
    }
    func testFleetPaintIsIndependent() {
        let a=Map3DAnkengLRT.model(.m1),d=Map3DDanhaiLRT.model(.m1)
        XCTAssertNotEqual(a.vertices.map(\.color),d.vertices.map(\.color))
        XCTAssertEqual(a.minimum.x,d.minimum.x,accuracy:0.00001)
        XCTAssertEqual(a.maximum.x,d.maximum.x,accuracy:0.00001)
    }
}
private extension Int {
    func mapModel(_ pack: Map3DModelPack) -> Map3DModelPack.Model { pack.models[self] }
}
