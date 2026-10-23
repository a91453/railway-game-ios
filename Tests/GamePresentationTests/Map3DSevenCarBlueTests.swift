import XCTest
@testable import GamePresentation

final class Map3DSevenCarBlueTests: XCTestCase {
    func testAssemblyIsAnExactTranslationWithSharedRailDatumAndBudget() {
        let formation=Map3DSevenCarBlue.formation();var index=0
        for unit in Map3DSevenCarBlue.Unit.allCases {
            let part=Map3DSevenCarBlue.model(unit)
            XCTAssertEqual(part.minimum.z,0,accuracy:0.0001)
            XCTAssertNotNil(Map3DModelPack.standard.index(of:part.name))
            for v in part.vertices {
                let q=formation.vertices[index];index += 1
                XCTAssertEqual(q.x,v.x+unit.centre,accuracy:0.0001)
                XCTAssertEqual(q.y,v.y,accuracy:0.0001);XCTAssertEqual(q.z,v.z,accuracy:0.0001)
                XCTAssertEqual(q.color,v.color)
                XCTAssertGreaterThan(Map3DPoint(q.nx,q.ny,q.nz).dot(Map3DPoint(v.nx,v.ny,v.nz)),0.99999)
            }
        }
        XCTAssertEqual(index,formation.vertices.count)
        XCTAssertLessThan(formation.triangleCount,Map3DModelFile.maximumTriangles)
        for id in ["metro-four-leading","lrt-seven-formation","lrt-five-formation","urban-three-leading"] { XCTAssertNotNil(Map3DModelPack.standard.index(of:id)) }
    }
    func testActualDoorAndWindowPanesHaveTheReferenceRhythm() {
        let colors: [UInt32]=[0.86,0.80].map { Map3DColor.shaded(Map3DSevenCarBlue.glass,$0) }
        for unit in Map3DSevenCarBlue.Unit.allCases {
            let m=Map3DSevenCarBlue.model(unit)
            for side: Float in [-1,1] {
                let panes=m.vertices.filter { colors.contains($0.color) && $0.y*side>1.33 && $0.ny*side>0.9 }
                let doors=panes.filter { abs($0.y)>1.35 }
                let windows=panes.filter { abs($0.y)<1.35 }
                // Each independent rectangle has two distinct x coordinates.
                XCTAssertEqual(Set(doors.map { Int(($0.x*1000).rounded()) }).count,unit.cab == 0 ? 8:4)
                XCTAssertEqual(Set(windows.map { Int(($0.x*1000).rounded()) }).count,6)
                XCTAssertEqual(panes.map(\.z).max() ?? 0,2.705,accuracy:0.001)
            }
            let windscreens=m.vertices.filter { $0.color == Map3DSevenCarBlue.glass && abs($0.nx)>0.9 && abs($0.y)<1 && $0.z>1.3 }
            XCTAssertEqual(windscreens.isEmpty,unit.cab == 0)
            let raised=m.vertices.filter { $0.z>3.6 }
            XCTAssertEqual(raised.isEmpty,unit != .leading)
        }
    }
    func testActualWheelGroupsAndClearanceRatherThanDeclaredCounts() {
        for unit in Map3DSevenCarBlue.Unit.allCases {
            let m=Map3DSevenCarBlue.model(unit),wheels=m.vertices.filter { $0.color == Map3DStreetModel.tyre }
            var clusters=0,last: Float = -.infinity
            for x in wheels.map(\.x).sorted() { if x-last>0.14 { clusters += 1 };last=x }
            XCTAssertEqual(clusters,4) // Documented concealed display assumption.
            XCTAssertEqual(wheels.map(\.z).min()!,0,accuracy:0.0001)
            let top=wheels.map(\.z).max()!
            let floor=m.vertices.filter { $0.nz < -0.9 && abs($0.y)>1.18 && $0.z>0.51 && $0.z<0.60 }
            XCTAssertFalse(floor.isEmpty);XCTAssertGreaterThan((floor.map(\.z).min() ?? 0)-top,0.049)
        }
    }
    func testAllTrianglesAreFiniteNondegenerateAndNormalsMatchWinding() {
        for unit in Map3DSevenCarBlue.Unit.allCases {
            let m=Map3DSevenCarBlue.model(unit)
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let a=m.vertices[i],b=m.vertices[i+1],c=m.vertices[i+2]
                let cross=(b.position-a.position).cross(c.position-a.position)
                XCTAssertGreaterThan(cross.length,0.0000001)
                XCTAssertTrue([a.x,a.y,a.z,a.nx,a.ny,a.nz].allSatisfy(\.isFinite))
                XCTAssertEqual(Map3DPoint(a.nx,a.ny,a.nz).length,1,accuracy:0.0001)
                XCTAssertGreaterThan(cross.dot(Map3DPoint(a.nx,a.ny,a.nz)),0)
            }
        }
    }
}
