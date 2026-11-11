import XCTest
@testable import GamePresentation

final class Map3DAirportAircraftStudiesTests: XCTestCase {
    private struct Edge: Hashable {
        let a: Map3DPoint
        let b: Map3DPoint
    }
    private func assertClosed(_ model: Map3DModelPack.Model, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.vertices.count % 3,0,file:file,line:line)
        var edges: [Edge:Int] = [:]
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let points=(i..<(i+3)).map { n in
                let v=model.vertices[n]
                return Map3DPoint(v.x,v.y,v.z)
            }
            for j in 0..<3 { edges[Edge(a:points[j],b:points[(j+1)%3]),default:0]+=1 }
        }
        for (edge,count) in edges { XCTAssertEqual(edges[Edge(a:edge.b,b:edge.a),default:0],count,file:file,line:line) }
    }
    func testAircraftDimensionsBudgetsGroundAndDeterminism() {
        for kind in Map3DAircraftStudies.Kind.allCases {
            let near=Map3DAircraftStudies.model(kind)
            let far=Map3DAircraftStudies.model(kind,far:true)
            XCTAssertGreaterThan(near.triangleCount,0)
            XCTAssertLessThanOrEqual(near.triangleCount,15_000)
            XCTAssertLessThan(far.triangleCount,near.triangleCount)
            XCTAssertEqual(near.minimum.z,0,accuracy:0.001)
            assertClosed(near);assertClosed(far)
            let again=Map3DAircraftStudies.model(kind)
            XCTAssertEqual(near.vertices.count,again.vertices.count)
            for (a,b) in zip(near.vertices,again.vertices) {
                XCTAssertTrue(a.x.isFinite && a.y.isFinite && a.z.isFinite)
                XCTAssertEqual(a.x,b.x);XCTAssertEqual(a.y,b.y);XCTAssertEqual(a.z,b.z)
            }
            let metadata=Map3DAircraftStudies.metadata(kind)
            XCTAssertGreaterThan(metadata.dimensions.length,16)
            XCTAssertGreaterThan(metadata.dimensions.wingspan,16)
            XCTAssertEqual(near.length,metadata.dimensions.length,accuracy:0.05)
            XCTAssertEqual(near.maximum.y-near.minimum.y,metadata.dimensions.wingspan,accuracy:0.05)
            XCTAssertEqual(near.maximum.z,metadata.dimensions.height,accuracy:0.05)
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
            assertClosed(near);assertClosed(far)
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
    // Decision 698: what the first pass got wrong, so it cannot come back.
    private func points(_ model: Map3DModelPack.Model, colored color: UInt32) -> [Map3DPoint] {
        model.vertices.filter { $0.color == color }.map { Map3DPoint($0.x,$0.y,$0.z) }
    }
    func testAircraftHaveANoseATailPropellersAndRoundWheels() {
        for kind in Map3DAircraftStudies.Kind.allCases {
            let model=Map3DAircraftStudies.model(kind), shape=Map3DAircraftStudies.shape(kind)
            let all=model.vertices.map { Map3DPoint($0.x,$0.y,$0.z) }
            // The nose closes to a point: the fuselage is not a tube with a flat end.
            let nose=all.filter { $0.x > model.maximum.x-0.3 }
            XCTAssertLessThan(nose.map { abs($0.y) }.max() ?? .infinity,shape.halfWidth*0.45,kind.rawValue)
            let tyres=points(model,colored:Map3DStudyColor.tyre)
            if Map3DAircraftStudies.isJet(kind) {
                // The intake stands ahead of the wing's leading edge.
                let lip=points(model,colored:Map3DStudyColor.hub).map(\.x).max() ?? -.infinity
                XCTAssertGreaterThan(lip,Map3DAircraftStudies.dimensions(kind).length/2-shape.wing[2].s+2,kind.rawValue)
            } else {
                // Propeller blades reach their full radius round each engine and clear the ground.
                let reach=tyres.filter { $0.x > model.maximum.x-shape.engine.from }.map { hypotf(abs($0.y)-shape.engine.y,$0.z-shape.engine.z) }.max() ?? 0
                XCTAssertGreaterThan(reach,shape.engine.propeller*0.95,kind.rawValue)
                XCTAssertEqual(Map3DAircraftStudies.metadata(kind).joints.first?.pivot.z,shape.engine.z)
            }
            // Wheels are round: the tyres' rims are not the four corners of a box.
            XCTAssertGreaterThanOrEqual(Set(tyres.filter { $0.z < 2*shape.mainGear.r+0.01 }.map { $0.z }).count,7,kind.rawValue)
        }
    }
    func testPavementIsGreyAndLampsLightItAtNight() {
        for kind in [Map3DAirportStudies.Kind.runway,.runwayEnd,.taxiway,.apron] {
            let model=Map3DAirportStudies.model(kind)
            // The pavement is the model's largest face and it is grey, not the navy of the first pass.
            let ground=model.vertices.filter { $0.z == 0 }
            XCTAssertFalse(ground.isEmpty)
            for color in Set(ground.map(\.color)) {
                let r=Int(color & 255),g=Int((color >> 8) & 255),b=Int((color >> 16) & 255)
                XCTAssertLessThan(max(r,g,b)-min(r,g,b),20,kind.rawValue)
            }
            XCTAssertFalse(model.vertices.contains { $0.color == Map3DPalette.playerRim })
            // Lamps glow, and so does the pavement under them, in the pavement's own colour.
            let glowing=Set(model.vertices.filter(\.glows).map(\.color))
            let pool=kind == .apron ? Map3DStudyColor.litDeck : kind == .taxiway ? Map3DStudyColor.litTaxi : Map3DStudyColor.litAsphalt
            XCTAssertTrue(glowing.contains(pool),kind.rawValue)
            XCTAssertTrue(glowing.contains(kind == .taxiway ? Map3DStudyColor.lampBlue : Map3DStudyColor.lamp),kind.rawValue)
        }
    }
    func testTerminalsStandOnOneGroundAndVehiclesOnRoundWheels() {
        for kind in [Map3DAirportStudies.Kind.cityTerminal,.islandTerminal] {
            let model=Map3DAirportStudies.model(kind)
            // One plate under the hall, the tower and the hangar: nothing floats apart.
            let plate=model.vertices.filter { $0.z == 0 && $0.color == Map3DStudyColor.deck }
            XCTAssertEqual(plate.map(\.x).min(),model.minimum.x);XCTAssertEqual(plate.map(\.y).min(),model.minimum.y)
            XCTAssertEqual(plate.map(\.y).max(),model.maximum.y)
            XCTAssertTrue(model.vertices.contains { $0.glows && $0.color == Map3DStudyColor.pane })
        }
        for kind in [Map3DAirportStudies.Kind.tug,.baggageCart,.boardingStairs,.fuelTruck] {
            let tyres=points(Map3DAirportStudies.model(kind),colored:Map3DStudyColor.tyre).filter { $0.z < 1.01 }
            XCTAssertGreaterThanOrEqual(Set(tyres.map { $0.z }).count,7,kind.rawValue)
        }
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
