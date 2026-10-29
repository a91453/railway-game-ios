import XCTest
@testable import GamePresentation

final class Map3DE200MingriStyleTests: XCTestCase {
    func testPaintOnlyAndProtectedHardware() {
        for far in [false,true] { for role in Map3DE200MingriStyle.Role.allCases {
            let old = Map3DE200MingriStyle.original(role,far:far)
            let new = Map3DE200MingriStyle.model(role,far:far)
            XCTAssertEqual(old.vertices.count,new.vertices.count)
            XCTAssertEqual(old.minimum,new.minimum); XCTAssertEqual(old.maximum,new.maximum)
            var changed = 0
            for i in old.vertices.indices {
                let a = old.vertices[i], b = new.vertices[i]
                XCTAssertEqual(a.position,b.position); XCTAssertEqual(a.nx,b.nx)
                XCTAssertEqual(a.ny,b.ny); XCTAssertEqual(a.nz,b.nz)
                XCTAssertEqual(a.u,b.u); XCTAssertEqual(a.v,b.v); XCTAssertEqual(a.layer,b.layer)
                if a.color != b.color {
                    changed += 1
                    XCTAssertFalse(a.glows)
                    XCTAssertFalse(Map3DTrainMaterial.isGlassColour(a.color))
                    XCTAssertNotNil(Map3DE200MingriStyle.paint(old.vertices[(i/3*3)..<(i/3*3+3)],role:role,index:i/3,far:far))
                }
            }
            XCTAssertGreaterThan(changed,100)
        }}
    }
    func testOriginalSetAndSelectionStayOriginal() {
        XCTAssertEqual(Map3DTrainSet.variant(of:"E200CK",number:1),"E200CK")
        XCTAssertNil(Map3DTrainSet.named("e200-mingri-style"))
        XCTAssertFalse(Map3DModelPack.standard.models.contains { $0.name.hasPrefix("e200mingri-style-") })
    }
}
