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
    func testDuckbillHasBroadLowForwardProjection() {
        let cab=Map3DTrainShapeRefresh.model("refresh-700t-cab")
        let bill=cab.vertices.filter { abs($0.x-12.2)<0.002 }
        XCTAssertFalse(bill.isEmpty)
        let width=bill.map(\.y).max()!-bill.map(\.y).min()!
        let thickness=bill.map(\.z).max()!-bill.map(\.z).min()!
        XCTAssertGreaterThan(width,2.5,"Bill narrows to a pointed cone")
        XCTAssertGreaterThan(width/thickness,5.5,"Bill lacks a flattened cross-section")
        XCTAssertGreaterThan(cab.maximum.x,13.4,"Low bill does not project forward")
    }
    func testPassengerGlassHasRoundedCornersInsteadOfRectangle() {
        let m=Map3DTrainShapeRefresh.model("refresh-700t-middle")
        let glass=Map3DColor.shaded(Map3DPalette.glazing,0.5)
        let pane=m.vertices.filter { $0.color==glass && $0.x > -9.56 && $0.x < -9.04 && $0.y>1.0 }
        XCTAssertFalse(pane.isEmpty)
        let xs=Set(pane.map { Int(($0.x*10000).rounded()) })
        let heights=Set(pane.map { Int(($0.z*10000).rounded()) })
        XCTAssertGreaterThan(xs.count,4)
        XCTAssertGreaterThan(heights.count,4)
        let low=pane.map(\.z).min()!,left=pane.map(\.x).min()!
        XCTAssertFalse(pane.contains { abs($0.z-low)<0.001 && abs($0.x-left)<0.001 },"Square lower glass corner returned")
    }
    func testAssemblyUsesExactFinalUnitsWithStableVertexColors() {
        let train=Map3DTrainShapeRefresh.formation()
        XCTAssertGreaterThan(train.triangleCount,15000) // Rebuilt from legal independent native units, not one native file.
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
