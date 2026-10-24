import XCTest
@testable import GamePresentation

final class Map3DTrainShapeRefreshTests: XCTestCase {
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
    func testNoseDropsAndMiddleKeepsFullRoofWithoutCabGlass() {
        let cab=Map3DTrainShapeRefresh.model("refresh-700t-cab")
        let mid=Map3DTrainShapeRefresh.model("refresh-700t-middle")
        XCTAssertLessThan(cab.vertices.filter { $0.x>12 }.map(\.z).max()!,2)
        XCTAssertGreaterThan(mid.vertices.filter { $0.x>12 }.map(\.z).max()!,3.6)
        XCTAssertGreaterThan(cab.vertices.filter { $0.x>6 && $0.z>2 }.count,100)
        let tail=Map3DTrainShapeRefresh.model("refresh-700t-tail")
        XCTAssertEqual(tail.vertices.count,cab.vertices.count)
        for (a,b) in zip(cab.vertices,tail.vertices) {
            XCTAssertEqual(a.x,-b.x,accuracy:0.00001)
            XCTAssertEqual(a.y,-b.y,accuracy:0.00001)
            XCTAssertEqual(a.z,b.z,accuracy:0.00001)
        }
    }
    func testAssemblyUsesExactFinalUnitsWithStableVertexColors() {
        let train=Map3DTrainShapeRefresh.formation()
        XCTAssertLessThanOrEqual(train.triangleCount,15000)
        var offset=0
        for i in 0..<12 {
            let id=i == 0 ? "refresh-700t-cab" : i == 11 ? "refresh-700t-tail" : [3,8].contains(i) ? "refresh-700t-panto" : "refresh-700t-middle"
            let unit=Map3DTrainShapeRefresh.model(id)
            let centre=Float(11-2*i)*12.7
            for (j,v) in unit.vertices.enumerated() {
                let q=train.vertices[offset+j]
                XCTAssertEqual(q.x,v.x+centre,accuracy:0.00001)
                XCTAssertEqual(q.y,v.y,accuracy:0.00001)
                XCTAssertEqual(q.z,v.z,accuracy:0.00001)
                XCTAssertEqual(q.color,v.color)
            }
            offset += unit.vertices.count
        }
        XCTAssertEqual(offset,train.vertices.count)
    }
}
