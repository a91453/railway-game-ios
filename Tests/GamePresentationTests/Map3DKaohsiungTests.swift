import XCTest
@testable import GamePresentation

final class Map3DKaohsiungTests: XCTestCase {
    func testLegalUnitsAndFarBudget() {
        for unit in Map3DKaohsiung.Unit.allCases {
            let a=Map3DKaohsiung.model(unit),b=Map3DKaohsiung.model(unit,far:true)
            XCTAssertLessThanOrEqual(a.triangleCount,Map3DModelFile.maximumTriangles)
            XCTAssertLessThan(b.triangleCount*2,a.triangleCount)
            XCTAssertEqual(a.minimum,b.minimum);XCTAssertEqual(a.maximum,b.maximum)
            XCTAssertEqual(a.minimum.z,0,accuracy:0.00001)
        }
    }
    func testTrailerHasNoCabGlassOrExternalCoupler() {
        let t=Map3DKaohsiung.model(.t)
        XCTAssertFalse(t.vertices.contains { abs($0.x)>10 && $0.z<1 })
        XCTAssertFalse(t.vertices.contains { abs($0.x)>10 && $0.z>2 && $0.color==Map3DTrainStyle.glass })
    }
    func testStudiesOnlyAndProtectedOperatingMapping() {
        let studies=Map3DModelPack.studies
        for unit in Map3DKaohsiung.Unit.allCases {
            XCTAssertNotNil(studies.index(of:"kaohsiung-"+unit.rawValue))
            XCTAssertNil(Map3DModelPack.standard.index(of:"kaohsiung-"+unit.rawValue))
        }
    }
}
