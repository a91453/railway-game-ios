import XCTest
@testable import GamePresentation

final class Map3DSevenSectionLRTTests: XCTestCase {
    func testAllSevenUnitsReconstructTheFormationAtOneRailDatum() {
        let train=Map3DSevenSectionLRT.formation();var index=0
        for unit in Map3DSevenSectionLRT.Unit.allCases {
            let part=Map3DSevenSectionLRT.model(unit)
            for p in part.vertices {
                let q=train.vertices[index];index += 1
                XCTAssertEqual(q.x,p.x+unit.centre,accuracy:0.0001)
                XCTAssertEqual(q.y,p.y,accuracy:0.0001);XCTAssertEqual(q.z,p.z,accuracy:0.0001)
                XCTAssertEqual(q.color,p.color)
            }
            XCTAssertEqual(part.maximum.z,unit == .trailing ? 4.465 : 3.371,accuracy:0.003)
            XCTAssertEqual(part.minimum.z,unit.hasBogie ? 0 : 0.24,accuracy:0.001)
        }
        XCTAssertEqual(index,train.vertices.count)
        XCTAssertEqual(train.length,45.5,accuracy:0.001)
    }
    func testTheMeshHasEightActualAxlesWithNoWheelsOnSuspendedSections() {
        let wheels=Map3DSevenSectionLRT.formation().vertices.filter { $0.color == Map3DStreetModel.tyre }
        var clusters=0,last: Float = -.infinity
        for x in wheels.map(\.x).sorted() { if x-last>0.17 { clusters += 1 };last=x }
        XCTAssertEqual(clusters,8)
        XCTAssertEqual(wheels.map(\.z).min()!,0,accuracy:0.001)
        for unit in Map3DSevenSectionLRT.Unit.allCases where !unit.hasBogie {
            XCTAssertFalse(Map3DSevenSectionLRT.model(unit).vertices.contains { $0.color == Map3DStreetModel.tyre })
        }
    }
    func testFourDoorModulesThreeWindowModulesAndOnePantographAppearInActualGeometry() {
        var panto=0,leaves=0
        for unit in Map3DSevenSectionLRT.Unit.allCases {
            let model=Map3DSevenSectionLRT.model(unit)
            if model.maximum.z>4 { panto += 1;XCTAssertEqual(unit,.trailing) }
            for sign: Float in [-1,1] {
                let glassColors: [Float] = [0.86,0.80]
                let colors=glassColors.map { Map3DColor.shaded(Map3DSevenSectionLRT.glass,$0) }
                let glass=model.vertices.filter { colors.contains($0.color) && $0.y*sign>1.355 && abs($0.ny)>0.9 }
                let edges=Set(glass.map { Int(($0.x*1000).rounded()) })
                XCTAssertEqual(edges.count,unit.hasBogie ? 8 : 0)
                leaves += edges.count/2
            }
        }
        XCTAssertEqual(leaves,32) // eight double-door groups on each side
        XCTAssertEqual(panto,1)
    }
    func testEveryTriangleIsFiniteNondegenerateAndNoRedPaintWasIntroduced() {
        for unit in Map3DSevenSectionLRT.Unit.allCases {
            let model=Map3DSevenSectionLRT.model(unit)
            XCTAssertLessThan(model.triangleCount,3000)
            for i in stride(from:0,to:model.vertices.count,by:3) {
                let a=model.vertices[i],b=model.vertices[i+1],c=model.vertices[i+2]
                XCTAssertGreaterThan((b.position-a.position).cross(c.position-a.position).length,0.0000001)
                XCTAssertTrue([a.x,a.y,a.z,a.nx,a.ny,a.nz].allSatisfy(\.isFinite))
                let red=Int(a.color&255),green=Int((a.color>>8)&255),blue=Int((a.color>>16)&255)
                XCTAssertFalse(red>100 && red>green+30 && red>blue+30)
            }
            XCTAssertNotNil(Map3DModelPack.standard.index(of:model.name))
        }
        XCTAssertLessThan(Map3DSevenSectionLRT.formation().triangleCount,15000)
        XCTAssertNotNil(Map3DModelPack.standard.index(of:"lrt-five-formation"))
    }
}
