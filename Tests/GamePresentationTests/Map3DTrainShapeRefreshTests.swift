import XCTest
@testable import GamePresentation

final class Map3DTrainShapeRefreshTests: XCTestCase {
    /// The E200 (the 700T's four recipe cars, tested here until they
    /// were deleted on 2026-11-27, have ``Map3DTHSR700TTests``).
    func testEveryUnitHasFiniteOutwardNormalsAndRailContact() {
        for id in Map3DTrainShapeRefresh.ids {
            let m=Map3DTrainShapeRefresh.model(id)
            XCTAssertLessThanOrEqual(m.triangleCount,15000)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            for v in m.vertices {
                XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
            }
        }
    }
}
