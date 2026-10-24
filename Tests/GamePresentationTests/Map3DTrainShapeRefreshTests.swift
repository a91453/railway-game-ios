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
    func testColouredShoulderWrapsTheNoseWithoutExtendingItsLength() {
        let cab=Map3DTrainShapeRefresh.model("refresh-700t-cab")
        let teal=Map3DPalette.shopAwnings[0]
        let band=cab.vertices.filter { $0.color==teal && $0.x>5.7 && $0.x<9.2 }
        XCTAssertGreaterThan(band.map(\.z).max()!,1.9,"Coloured shoulder remains a narrow lower stripe")
        let front=cab.vertices.filter { $0.color==teal && $0.x>11.8 }
        XCTAssertGreaterThan(front.map(\.z).max()!,1.25,"Band fails to wrap over the low front lip")
        XCTAssertLessThan(cab.maximum.x,12.6,"Unrequested long paddle returned")
        XCTAssertGreaterThan(cab.vertices.filter { abs($0.x-9.1)<0.002 && $0.color==teal }.map { abs($0.y) }.max()!,1.6)
    }
    func testShoulderKeepsWidthWhileCentralNoseNarrowsInsideIt() {
        let m=Map3DTrainShapeRefresh.model("refresh-700t-cab")
        let section=m.vertices.filter { abs($0.x-10.5)<0.0001 }
        let width=section.map(\.y).max()!-section.map(\.y).min()!
        XCTAssertGreaterThan(width,3.20,"Lower shoulder still collapses with the upper nose")
        let central=section.filter { $0.color==Map3DTrainShapeRefresh.highSpeedBodyColor }
        let centralWidth=central.map(\.y).max()!-central.map(\.y).min()!
        XCTAssertLessThan(centralWidth/width,0.85,"Central nose covers the broad coloured shoulder")
        let front=m.vertices.filter { abs($0.x-11.9)<0.0001 && $0.color==Map3DTrainShapeRefresh.highSpeedBodyColor }
        XCTAssertFalse(front.isEmpty)
        XCTAssertLessThan(front.map(\.y).max()!-front.map(\.y).min()!,1.2,"Central inset fails to taper inside the front lip")
        // Check the body join on both sides from actual coloured vertices.
        let band=m.vertices.filter { $0.color==Map3DPalette.shopAwnings[0] }
        let h0=band.filter { abs($0.x)<0.0001 }.map(\.z).max()!
        let h1=band.filter { abs($0.x-3.7)<0.0001 }.map(\.z).max()!
        XCTAssertLessThan(abs(h1-h0),0.015,"Body paint join has a step")
    }
    func testWindscreenHasWhiteRoofMarginAndLowMaskProportions() {
        let cab=Map3DTrainShapeRefresh.model("refresh-700t-cab")
        let mask=cab.vertices.filter { $0.x>7 && $0.color==Map3DTrainShapeRefresh.highSpeedGlassColor }
        XCTAssertFalse(mask.isEmpty)
        let high=mask.map(\.z).max()!,low=mask.map(\.z).min()!
        let width=mask.map(\.y).max()!-mask.map(\.y).min()!
        XCTAssertGreaterThan(cab.maximum.z-high,0.23,"Windscreen touches the roof with no white margin")
        XCTAssertLessThan(high-low,1.0,"Black mask is too tall")
        XCTAssertGreaterThan(width/(high-low),2.2,"Mask reads as a tall rectangular box")
        XCTAssertGreaterThan(mask.map(\.x).min()!,8.0,"Mask extends too far up the roof")
    }
    func testFrontMaskNarrowsAndFairingCoversFrontRunningGear() {
        let cab=Map3DTrainShapeRefresh.model("refresh-700t-cab")
        let mask=cab.vertices.filter { $0.x>7 && $0.color==Map3DTrainShapeRefresh.highSpeedGlassColor }
        let width=mask.map(\.y).max()!-mask.map(\.y).min()!
        XCTAssertLessThan(width,2.25,"Front mask still spreads too far across the white nose")
        let fairing=cab.vertices.filter { $0.x>7 }
        XCTAssertLessThan(fairing.map(\.z).min()!,0.45,"Lower front fairing leaves the running gear exposed")
    }
    func testPassengerGlassHasRoundedCornersInsteadOfRectangle() {
        let m=Map3DTrainShapeRefresh.model("refresh-700t-middle")
        let glass=Map3DTrainShapeRefresh.highSpeedGlassColor
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
