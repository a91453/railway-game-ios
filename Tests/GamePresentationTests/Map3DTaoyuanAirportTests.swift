import XCTest
@testable import GamePresentation

final class Map3DTaoyuanAirportTests: XCTestCase {
    func testRolesHaveLegalDistinctNearFarUnits() {
        var ids = Set<String>()
        for role in Map3DTaoyuanAirport.Role.allCases {
            let near = Map3DTaoyuanAirport.model(role)
            let far = Map3DTaoyuanAirport.model(role, far: true)
            XCTAssertTrue(ids.insert(near.name).inserted)
            XCTAssertLessThan(near.triangleCount, 15000)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.00001)
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.00001)
            XCTAssertEqual(near.maximum.x, far.maximum.x, accuracy: 0.0001)
            XCTAssertEqual(near.maximum.y, far.maximum.y, accuracy: 0.0001)
            XCTAssertEqual(near.maximum.z, far.maximum.z, accuracy: 0.02)
        }
    }
    func testBaggageIsNotAPassengerCabWithDifferentPaint() {
        let baggage = Map3DTaoyuanAirport.model(.dmb)
        let passenger = Map3DTaoyuanAirport.model(.dme1)
        XCTAssertNotEqual(baggage.triangleCount, passenger.triangleCount)
        // Actual side glass surfaces, not role constants: the baggage cab
        // has cab access glazing only and no saloon panes along the body.
        let sideGlass = baggage.vertices.filter {
            abs($0.y) > 1.52 && $0.x < 7.0 && $0.z > 2.1 && $0.color == Map3DTrainStyle.glass
        }
        XCTAssertTrue(sideGlass.isEmpty)
    }
}
