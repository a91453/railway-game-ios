import XCTest
@testable import GamePresentation

final class Map3DBusTerminalStudiesTests: XCTestCase {
    func testBudgetsAndFiniteModels() {
        for kind in Map3DBusTerminalStudies.Kind.allCases {
            let near=Map3DBusTerminalStudies.model(kind),far=Map3DBusTerminalStudies.model(kind,far:true)
            XCTAssertGreaterThan(near.triangleCount,0)
            XCTAssertLessThanOrEqual(near.triangleCount,15_000)
            XCTAssertLessThan(far.triangleCount,near.triangleCount+1)
            for v in near.vertices { XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite) }
            let again=Map3DBusTerminalStudies.model(kind)
            XCTAssertEqual(near.vertices.count,again.vertices.count)
            for (a,b) in zip(near.vertices,again.vertices) { XCTAssertEqual(a.x,b.x);XCTAssertEqual(a.y,b.y);XCTAssertEqual(a.z,b.z);XCTAssertEqual(a.color,b.color) }
        }
    }
    func testParkingAndRoadConnections() {
        for (kind,count) in [(Map3DBusTerminalStudies.Kind.large,8),(.medium,5),(.expressStop,1)] {
            let c=Map3DBusTerminalStudies.connections(for:kind)
            XCTAssertEqual(c.parking.count,count)
            XCTAssertEqual(c.entry?.position.z,0)
            XCTAssertEqual(c.exit?.position.z,0)
            for bay in c.parking { XCTAssertGreaterThanOrEqual(bay.usableLength,13.2);XCTAssertGreaterThanOrEqual(bay.clearWidth,3.16);XCTAssertEqual(hypotf(bay.heading.x,bay.heading.y),1,accuracy:0.0001) }
        }
    }
    func testGroundMountsAndRoofSupports() {
        let seat=Map3DBusTerminalStudies.model(.seatGroup)
        let canopy=Map3DBusTerminalStudies.model(.canopy8)
        XCTAssertEqual(seat.minimum.z,0,accuracy:0.001)
        XCTAssertEqual(canopy.minimum.z,0,accuracy:0.001)
        XCTAssertGreaterThan(canopy.maximum.z,3.35)
    }
}
