import XCTest
@testable import GamePresentation

final class Map3DAirportAircraftStudiesTests: XCTestCase {
    func testAircraftDimensionsBudgetsGroundAndDeterminism() {
        for kind in Map3DAircraftStudies.Kind.allCases {
            let near=Map3DAircraftStudies.model(kind)
            let far=Map3DAircraftStudies.model(kind,far:true)
            XCTAssertGreaterThan(near.triangleCount,0)
            XCTAssertLessThanOrEqual(near.triangleCount,15_000)
            XCTAssertLessThan(far.triangleCount,near.triangleCount)
            XCTAssertEqual(near.minimum.z,0,accuracy:0.001)
            let again=Map3DAircraftStudies.model(kind)
            XCTAssertEqual(near.vertices.count,again.vertices.count)
            for (a,b) in zip(near.vertices,again.vertices) {
                XCTAssertTrue(a.x.isFinite && a.y.isFinite && a.z.isFinite)
                XCTAssertEqual(a.x,b.x);XCTAssertEqual(a.y,b.y);XCTAssertEqual(a.z,b.z)
            }
            let metadata=Map3DAircraftStudies.metadata(kind)
            XCTAssertGreaterThan(metadata.dimensions.length,16)
            XCTAssertGreaterThan(metadata.dimensions.wingspan,16)
            XCTAssertEqual(metadata.joints.count,kind == .commuter19 || kind == .regional70 ? 4 : 2)
            XCTAssertEqual(metadata.glowParts.count,6)
        }
    }
    func testAirportPartsGroundBudgetAndRunwayConnections() {
        for kind in Map3DAirportStudies.Kind.allCases {
            let near=Map3DAirportStudies.model(kind)
            let far=Map3DAirportStudies.model(kind,far:true)
            XCTAssertGreaterThan(near.triangleCount,0)
            XCTAssertLessThanOrEqual(near.triangleCount,15_000)
            XCTAssertLessThanOrEqual(far.triangleCount,near.triangleCount)
            XCTAssertEqual(near.minimum.z,0,accuracy:0.001)
            for vertex in near.vertices { XCTAssertTrue(vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite) }
        }
        let runway=Map3DAirportStudies.connections(.runway)
        XCTAssertEqual(runway.runwayEnds.count,2)
        XCTAssertEqual(runway.runwayEnds[0].length,60)
        XCTAssertEqual(runway.runwayEnds[0].position.z,0)
        XCTAssertEqual(runway.runwayEnds[0].heading.x,1)
        XCTAssertEqual(runway.runwayEnds[1].heading.x,-1)
        XCTAssertEqual(runway.taxiwayLinks.count,1)
    }
    func testStandsAndBridges() {
        let stands=Map3DAirportStudies.connections(.apron).stands
        XCTAssertEqual(stands.count,3)
        XCTAssertEqual(stands.map(\.aircraftClass),["A","C","D"])
        for stand in stands {
            XCTAssertEqual(stand.noseStop.z,0)
            XCTAssertEqual(hypotf(stand.heading.x,stand.heading.y),1,accuracy:0.0001)
            XCTAssertGreaterThanOrEqual(stand.maxWingspan,17)
        }
        let bridges=Map3DAirportStudies.connections(.cityTerminal).jetbridges
        XCTAssertEqual(bridges.count,4)
        for bridge in bridges { XCTAssertGreaterThan(bridge.exit.x,bridge.pivot.x);XCTAssertEqual(bridge.translationAxis.x,1);XCTAssertEqual(bridge.extensionRange.upperBound,7) }
        XCTAssertTrue(Map3DAirportStudies.connections(.islandTerminal).jetbridges.isEmpty)
    }
}
