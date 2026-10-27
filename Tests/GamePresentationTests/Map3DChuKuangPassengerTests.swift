import XCTest
@testable import GamePresentation

final class Map3DChuKuangPassengerTests: XCTestCase {
    func testUnitsAreDistinctAndLegal() {
        for role in Map3DChuKuangPassenger.Role.allCases {
            let near=Map3DChuKuangPassenger.model(role), far=Map3DChuKuangPassenger.model(role,far:true)
            XCTAssertTrue(near.triangleCount < 15_000)
            XCTAssertTrue(far.triangleCount < near.triangleCount)
            XCTAssertTrue(far.triangleCount < 4_100)
            XCTAssertTrue(abs(near.minimum.z) < 0.0001)
            XCTAssertTrue(abs(near.length-20) < 0.001)
            XCTAssertTrue(near.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        XCTAssertTrue(Map3DChuKuangPassenger.windows(.standard,left:true).count == 9)
        XCTAssertTrue(Map3DChuKuangPassenger.windows(.standard,left:true).filter{$0.1>1}.count == 5)
        XCTAssertTrue(Map3DChuKuangPassenger.model(.standard).vertices.map(\.x) != Map3DChuKuangPassenger.model(.conductorStudy).vertices.map(\.x))
    }
    func testStudyDoesNotReplaceOperatingCars() {
        let names=Set(Map3DModelPack.standard.models.map(\.name))
        XCTAssertTrue(!names.contains("chukuang-standard"))
        XCTAssertTrue(names.contains("set-E500CK-car"))
        XCTAssertTrue(names.contains("pp-ppt1000"))
    }
}
