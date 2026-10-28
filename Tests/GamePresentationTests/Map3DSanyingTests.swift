import XCTest
@testable import GamePresentation

final class Map3DSanyingTests: XCTestCase {
    func testTwoIndependentCarsFitPublishedEnvelopeAndFarBudget() {
        for unit in Map3DSanying.Unit.allCases {
            let near = Map3DSanying.model(unit)
            let far = Map3DSanying.model(unit, far: true)
            XCTAssertLessThan(near.triangleCount, 15_000)
            XCTAssertLessThan(far.triangleCount, near.triangleCount / 2)
            XCTAssertEqual(near.maximum.x - near.minimum.x, 17.7, accuracy: 0.25)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 2.6, accuracy: 0.15)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.001)
            XCTAssertLessThanOrEqual(near.maximum.z, 3.81) // no pantograph on third-rail train
            XCTAssertTrue(near.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertEqual(near.minimum.x, far.minimum.x, accuracy: 0.001)
            XCTAssertEqual(near.maximum.x, far.maximum.x, accuracy: 0.001)
        }
    }
}
