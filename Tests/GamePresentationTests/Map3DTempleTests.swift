import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 268: a temple faces its busiest street across a
/// stone forecourt, with a gateway at the pavement, lanterns that glow at
/// night, banyans and more worshippers; and the back yards between rows
/// of houses green.
final class Map3DTempleTests: XCTestCase {
    private func builder(_ target: Map3DScene.Builder.Target) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: GameWorld.newGame())
        builder.target = target
        return builder
    }

    func testATempleFacesItsBusiestStreetSouthFirst() {
        var b = builder(.near)
        XCTAssertNil(b.templeFront(column: 3, row: 5))
        // A lane on the south, a main road on the east: toward the road,
        // its pavement half the lot less the road's width and pavement.
        b.streetEdges[Map3DSeededStreets.Edge(horizontal: true, line: 6, along: 3)] = .minor
        b.streetEdges[Map3DSeededStreets.Edge(horizontal: false, line: 4, along: 5)] = .primary
        let front = b.templeFront(column: 3, row: 5)
        XCTAssertEqual(front?.forward, Map3DPoint(1, 0, 0))
        XCTAssertEqual(front?.distance ?? 0, 32 - Map3DSeededStreets.clearance(.primary) - 0.3, accuracy: 1e-4)
        // Two alike: south.
        b.streetEdges[Map3DSeededStreets.Edge(horizontal: true, line: 6, along: 3)] = .primary
        XCTAssertEqual(b.templeFront(column: 3, row: 5)?.forward, Map3DPoint(0, 0, 1))
    }

    func testTheForecourtGatewayLanternsAndBanyansStandBeforeTheTemple() throws {
        var near = builder(.near), far = builder(.far)
        let forward = Map3DPoint(1, 0, 0), front: Float = 26
        near.addTemple(base: .zero, lot: 62, forward: forward, front: front)
        far.addTemple(base: .zero, lot: 62, forward: forward, front: front)
        let nearVertices = near.nearMeshes.values.flatMap(\.vertices), farVertices = far.farMeshes.values.flatMap(\.vertices)
        // The forecourt's stone reaches the pavement, east of the terrace.
        let court = nearVertices.filter { $0.color == Map3DPalette.forecourt }
        XCTAssertEqual(court.map(\.x).max() ?? 0, front, accuracy: 1e-3)
        XCTAssertGreaterThan(court.map(\.x).min() ?? 0, 0)
        XCTAssertTrue(court.allSatisfy { $0.ny > 0.99 }, "the stone faces up")
        XCTAssertTrue(farVertices.contains { $0.color == Map3DPalette.forecourt })
        // The gateway's posts at the pavement, 6 m either side, 6 m tall.
        let posts = nearVertices.filter { $0.color == Map3DPalette.templeRidge && abs($0.x - (front - 1.2)) < 0.5 }
        XCTAssertEqual(posts.map(\.z).max() ?? 0, 6.45, accuracy: 0.01)
        XCTAssertEqual(posts.map(\.y).max() ?? 0, 6, accuracy: 0.01)
        // Four red lanterns, glowing, near only.
        let lanterns = nearVertices.filter { $0.color == Map3DPalette.lantern }
        XCTAssertFalse(lanterns.isEmpty)
        XCTAssertTrue(lanterns.allSatisfy(\.glows))
        XCTAssertFalse(farVertices.contains { $0.color == Map3DPalette.lantern })
        // Two banyans on the forecourt, near only.
        let trees = near.props.values.flatMap { $0 }
        XCTAssertEqual(trees.count, 2)
        XCTAssertTrue(trees.allSatisfy { $0.transform[12] > 0 && $0.transform[12] < front })
        XCTAssertTrue(far.props.isEmpty)
        // The worshippers fill the forecourt.
        let spot = try XCTUnwrap(near.streetLife.spots.first)
        XCTAssertEqual(spot.people, 36)
        XCTAssertGreaterThan(spot.width, 3)
        XCTAssertTrue(spot.path.points.allSatisfy { $0.x > 0 && $0.x < front })
        XCTAssertTrue(far.streetLife.spots.isEmpty)
    }

    func testWithoutAStreetATempleStillFacesSouthAndFitsItsLot() {
        var near = builder(.near)
        near.addTemple(base: Map3DPoint(200, 0, 0), lot: 62)
        let court = near.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.forecourt && $0.x > 100 }
        XCTAssertEqual(court.map(\.z).max() ?? 0, 31, accuracy: 1e-3)
        let all = near.nearMeshes.values.flatMap(\.vertices).filter { $0.x > 100 }
        XCTAssertLessThanOrEqual(all.map(\.z).max() ?? 0, 33)
        XCTAssertGreaterThanOrEqual(all.map(\.z).min() ?? 0, -33)
    }

    func testTheBackYardsBetweenTwoStreetsAreMostlyGreen() {
        var greens = 0, trees = 0
        for lot in 0..<20 {
            var near = builder(.near)
            let fronts = Map3DScene.Builder.RowFronts(north: 25, south: 25, west: -27, east: 27)
            near.addRowHouses(base: .zero, side: 64, density: 1, shops: false, seed: (Int32(lot), 3), fronts: fronts)
            let lawn = near.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.park }
            if !lawn.isEmpty {
                greens += 1
                // Behind both rows (each 16 m deep from its front at 25 m).
                XCTAssertGreaterThanOrEqual(lawn.map(\.z).min() ?? 0, -9 + 1.5 - 1e-3)
                XCTAssertLessThanOrEqual(lawn.map(\.z).max() ?? 0, 9 - 1.5 + 1e-3)
            }
            trees += near.props.values.flatMap { $0 }.count
        }
        XCTAssertGreaterThan(greens, 8)
        XCTAssertLessThan(greens, 20)
        XCTAssertGreaterThan(trees, greens)
        // Back to back, no yard.
        var near = builder(.near)
        near.addRowHouses(base: .zero, side: 64, density: 1, shops: false, seed: (1, 3), fronts: Map3DScene.Builder.RowFronts(north: 25, south: nil, west: -27, east: 27))
        XCTAssertFalse(near.nearMeshes.values.flatMap(\.vertices).contains { $0.color == Map3DPalette.park })
    }
}
