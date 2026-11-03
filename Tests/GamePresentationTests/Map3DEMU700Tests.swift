import XCTest
@testable import GamePresentation

final class Map3DEMU700Tests: XCTestCase {
    func testAllRolesHaveIndependentLegalNearAndFarGeometry() {
        var hashes = Set<String>()
        for role in Map3DEMU700.Role.allCases {
            let near = Map3DEMU700.model(role), far = Map3DEMU700.model(role, far: true)
            XCTAssertLessThanOrEqual(near.triangleCount, 15_000)
            XCTAssertLessThanOrEqual(far.triangleCount, 15_000)
            XCTAssertLessThan(far.triangleCount, near.triangleCount / 2)
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

    func testCabNoseBandIsALowerBowlWithSpaceBelowTheLamps() throws {
        // Photo-fitted acceptance bounds, not surveyed engineering dimensions.
        // The rejected producer's central band started at 1.80m and reached
        // 2.15m, crowding the lamps and leaving a thin stepped moustache.
        let paint = Map3DColor.rgb(0xE9AD59)
        for far in [false, true] {
            let vertices = Map3DEMU700.model(.emc, far: far).vertices.filter {
                $0.x > 9 && abs($0.y) < 1.35 && $0.z < 2.1 && $0.color == paint
            }
            let low = try XCTUnwrap(vertices.map(\.z).min())
            let high = try XCTUnwrap(vertices.map(\.z).max())
            XCTAssertLessThan(low, 1.5)
            XCTAssertLessThanOrEqual(high, 1.9)
            XCTAssertGreaterThan(high - low, 0.4)
        }
    }

    func testActualCabModelsDoNotReceiveFictitiousMiddleCarEndShade() {
        for far in [false, true] {
            let cab = Map3DEMU700.model(.emc, far: far)
            XCTAssertFalse(Map3DTrainOcclusion.isMiddle(cab.name))
        }
    }
}
