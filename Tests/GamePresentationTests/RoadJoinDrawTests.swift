import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ROAD-JOIN-DRAW (docs/research/ROAD_EDITING_2026-11-17.md §2.2): where the
/// player's road ends within a cell of a real street (a T), the buses take a
/// short piece from the end to the street (decision 476's sequel), and the
/// 2D and 3D maps draw that piece too, so the road is seen to meet the
/// street. Before, both drew the road only to its end cell's middle, up to
/// 45 m short of the street.
final class RoadJoinDrawTests: XCTestCase {
    private typealias Point = BusRoadNetwork.Point
    private typealias Road = BusRoadNetwork.Road

    private let streets = [
        Road(points: [Point(x: 0, y: 0), Point(x: 400, y: 0)]),
        Road(points: [Point(x: 0, y: 200), Point(x: 400, y: 200)]),
    ]

    func testThePiecesDrawnAreTheOnesTheBusesTake() {
        let ends = [Point(x: 200, y: 40), Point(x: 200, y: 160), Point(x: 100, y: 100), Point(x: 300, y: 0)]
        let drawn = BusRoadNetwork.ownEndJoins(ends: ends, to: streets).map(\.points)
        let taken = BusRoadNetwork.joining(own: [], ends: ends, to: streets).map(\.points)
        XCTAssertEqual(drawn, taken)
        // A T from each street's side; none from 100 m away, none from on a street.
        XCTAssertEqual(drawn, [[Point(x: 200, y: 40), Point(x: 200, y: 0)], [Point(x: 200, y: 160), Point(x: 200, y: 200)]])
    }

    func testNoPieceToATunnel() {
        let tunnel = [Road(points: [Point(x: 0, y: 0), Point(x: 400, y: 0)], tunnel: true)]
        XCTAssertTrue(BusRoadNetwork.ownEndJoins(ends: [Point(x: 200, y: 30)], to: tunnel).isEmpty)
    }
}

/// The same on the app's own base map, by 大社路, 田中 (彰化)
/// (``RoadDrawRealMapTests``'): a road drawn out from beside a farm road is
/// drawn joined to it, faint while drawn and once laid, in 2D and 3D.
@MainActor
final class RoadJoinDrawRealMapTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private static let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
    private static let daShe = (latitude: 23.8640, longitude: 120.5760)

    private func game() throws -> (GameSession, CellPosition) {
        let position = Self.frame.worldPosition(latitude: Self.daShe.latitude, longitude: Self.daShe.longitude)
        let point = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        let session = GameSession(world: GameWorld.newWholeTaiwanGame())
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLand(within: WholeTaiwan.landReach, of: point)
        session.selectTool(.bus)
        session.setBusMode(.roads)
        return (session, CellPosition(containing: point))
    }

    private func metres(_ line: [PlanPoint]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + hypot(Double($1.0.x - $1.1.x), Double($1.0.y - $1.1.y)) } / Double(WorldCoordinate.unitsPerMetre)
    }

    func testARoadEndingBesideAStreetIsDrawnJoinedToIt() throws {
        let (session, middle) = try game()
        let city = try XCTUnwrap(session.world.roads).cells
        let onRoads = try XCTUnwrap(session.busRoads)
        // A cell beside a street, not on it, from which four new cells run
        // away from the street.
        var found: (along: [CellPosition], join: [PlanPoint])?
        search: for ring in 0...15 {
            for start in RoadGrid.ring(ring, round: middle) {
                guard let join = onRoads.joins(ofEnds: [start.middle]).first, metres(join) > 10 else { continue }
                for (dr, dc) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                    let along = (0...3).map { CellPosition(row: start.row + dr * $0, column: start.column + dc * $0) }
                    guard along.allSatisfy({ !city.contains($0) }) else { continue }
                    session.clearRoadDraft()
                    session.dragRoad(from: along[0].middle, to: along[3].middle)
                    guard session.roadDraft.cells == along, session.roadPreview?.canBuild == true else { continue }
                    found = (along, join)
                    break search
                }
            }
        }
        let (along, join) = try XCTUnwrap(found, "no road by 大社路 can be drawn out from beside a street")
        XCTAssertEqual(join.first, along[0].middle, "from the road's end")

        // Faint while drawn, with its join.
        XCTAssertTrue(try XCTUnwrap(session.roadMapOverlay).draft.contains(join), "the road drawn shows its join")

        XCTAssertTrue(session.confirmRoad(), session.message?.text ?? "")
        XCTAssertEqual(session.world.roads?.built, Set(along))
        let laid = try XCTUnwrap(session.busRoads)
        XCTAssertTrue(laid.ownJoins.contains(join), "the buses take that piece")
        session.setBusMode(.routes)
        let streets = try XCTUnwrap(session.roadMapOverlay).streets
        XCTAssertTrue(streets.contains(join), "the 2D map draws it out of the mode too")
        XCTAssertTrue(streets.contains(along.map(\.middle)) || streets.contains(along.map(\.middle).reversed()), "beside the road itself")

        // 3D: laid as a road beside the player's own.
        let tiles = try Self.tiles.get()
        let (region, originX, originY) = Map3DScene.frame(world: session.world, focus: (Double(along[0].middle.x), Double(along[0].middle.y)))
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: session.world)
        builder.addOwnRoads(baseMap: tiles, frame: try XCTUnwrap(RealWorldFrame(world: session.world)))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let scene = join.map { Map3DPoint(Float((Double($0.x) - originX) / metre), 0, Float((Double($0.y) - originY) / metre)) }
        XCTAssertTrue(builder.roadLines.contains { line in
            line.points.count == 2 && zip(line.points, scene).allSatisfy { ($0.0 - $0.1).length < 0.01 }
        }, "the 3D map lays the join")
        var without = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: session.world)
        without.addOwnRoads()
        XCTAssertGreaterThan(builder.roadLines.count, without.roadLines.count, "and none without the base map")
    }
}
