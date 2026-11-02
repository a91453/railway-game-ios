import XCTest
@testable import GamePresentation

final class Map3DEMU700Tests: XCTestCase {
    func testAllRolesHaveIndependentLegalNearAndFarGeometry() {
        var hashes = Set<String>()
        for role in Map3DEMU700.Role.allCases {
            let near = Map3DEMU700.model(role), far = Map3DEMU700.model(role, far: true)
            XCTAssertLessThanOrEqual(near.triangleCount, 15_000)
            XCTAssertLessThanOrEqual(far.triangleCount, 15_000)
            XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.0001)
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.0001)
            XCTAssertEqual(near.minimum.x, far.minimum.x, accuracy: 0.001)
            XCTAssertEqual(near.maximum.x, far.maximum.x, accuracy: 0.001)
            XCTAssertEqual(near.maximum.z, far.maximum.z, accuracy: 0.001)
            XCTAssertTrue(hashes.insert(String(describing: near.vertices)).inserted)
        }
    }
    func testOnlyPowerTrailerCarriesRaisedPantograph() {
        for role in Map3DEMU700.Role.allCases {
            let model = Map3DEMU700.model(role)
            if role == .ep { XCTAssertGreaterThan(model.maximum.z, 4.8) }
            else { XCTAssertLessThan(model.maximum.z, 4.1) }
        }
    }
}
