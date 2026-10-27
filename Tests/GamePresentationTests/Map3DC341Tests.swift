import XCTest
@testable import GamePresentation

final class Map3DC341Tests: XCTestCase {
    func testBudgetDatumAndRegistration() {
        let pack = Map3DModelPack.standard
        for u in Map3DC341.Unit.allCases {
            let m=Map3DC341.model(u)
            XCTAssertLessThanOrEqual(m.triangleCount,15000)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertGreaterThan(m.length,23)
            XCTAssertNotNil(pack.index(of:m.name))
        }
        XCTAssertEqual(Map3DC341.arrangement.count,6)
        XCTAssertEqual(pack.models.last?.name,Map3DLowFloorBus.routeModel().name)
    }
    func testMiddleHasNoFrontGlazingAndRearFacesOutward() {
        for u in [Map3DC341.Unit.t,.m] {
            let panes=Map3DC341.model(u).vertices.filter { $0.color == Map3DC341.glass }
            XCTAssertFalse(panes.isEmpty)
            XCTAssertTrue(panes.allSatisfy { abs($0.nx)<0.5 || abs($0.y)>1.58 })
        }
        let a=Map3DC341.model(.dm), b=Map3DC341.model(.rear)
        for (p,q) in zip(a.vertices,b.vertices) {
            XCTAssertEqual(p.x,-q.x,accuracy:0.00001)
            XCTAssertEqual(p.y,-q.y,accuracy:0.00001)
            XCTAssertEqual(p.z,q.z,accuracy:0.00001)
            XCTAssertEqual(p.color,q.color)
        }
    }
}
