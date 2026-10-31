import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 487, on the app's own base map: 95.1's report from the fields
/// by 大社路, 田中 (彰化): a road drawn in the bus tool's roads mode is laid
/// as drawn. Where it went over the city's road cells (any 64 m cell a
/// base-map road, an alley or a farm track crosses) only the cells with no
/// road were the player's, so the 2D map, which draws the base map's own
/// streets and not those cells, showed a square drawn as one of its sides.
@MainActor
final class RoadDrawRealMapTests: XCTestCase {
    private static let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)

    /// The fields west of 田中 along 大社路, by 八堡二圳.
    private static let daShe = (latitude: 23.8640, longitude: 120.5760)

    /// The whole of Taiwan, its land and roads read round 大社路, the bus
    /// tool's roads mode open.
    private func game() throws -> (GameSession, CellPosition) {
        let position = Self.frame.worldPosition(latitude: Self.daShe.latitude, longitude: Self.daShe.longitude)
        let point = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        let world = GameWorld.newWholeTaiwanGame()
        let session = GameSession(world: world)
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLand(within: WholeTaiwan.landReach, of: point)
        session.selectTool(.bus)
        session.setBusMode(.roads)
        return (session, CellPosition(containing: point))
    }

    /// The cells round a square `side` cells a side from `corner`, clockwise
    /// and back to the corner.
    private func square(from corner: CellPosition, side: Int) -> [CellPosition] {
        let r = corner.row, c = corner.column
        return [corner, CellPosition(row: r, column: c + side), CellPosition(row: r + side, column: c + side),
                CellPosition(row: r + side, column: c), corner]
    }

    /// A square near `middle` whose sides are partly on the city's road
    /// cells and partly not, as the report's was, that can be laid.
    private func mixedSquare(_ session: GameSession, near middle: CellPosition) throws -> [CellPosition] {
        let roads = try XCTUnwrap(session.world.roads)
        for ring in 0...12 {
            for corner in RoadGrid.ring(ring, round: middle) {
                let corners = square(from: corner, side: 3)
                session.clearRoadDraft()
                for end in corners.dropFirst() {
                    session.dragRoad(from: corners[0].middle, to: end.middle)
                }
                guard let preview = session.roadPreview, preview.canBuild,
                      session.roadDraft.cells.contains(where: { roads.cells.contains($0) }) else { continue }
                return corners
            }
        }
        XCTFail("no square by 大社路 is partly on the city's roads")
        return []
    }

    func testARoadDrawnOverTheCitysCellsIsLaidAndDrawnAsPreviewed() throws {
        let (session, middle) = try game()
        let corners = try mixedSquare(session, near: middle)
        let drawn = session.roadDraft.cells
        let preview = try XCTUnwrap(session.roadPreview)
        XCTAssertGreaterThan(preview.joined, 0, "part of it is on the city's road cells")
        XCTAssertTrue(preview.canBuild)
        let draft = try XCTUnwrap(session.roadMapOverlay).draft
        XCTAssertFalse(draft.isEmpty)
        let before = session.world.economy.balance
        XCTAssertTrue(session.confirmRoad(), session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, before - preview.price, "only the new cells are paid for")

        // Every cell drawn is the player's road now, and the map draws the
        // road laid as the preview drew it.
        XCTAssertEqual(session.world.roads?.built, Set(drawn))
        let overlay = try XCTUnwrap(session.roadMapOverlay)
        XCTAssertEqual(Set(overlay.own.flatMap { $0 }), Set(draft.flatMap { $0 }), "laid as previewed: \(corners)")
        XCTAssertEqual(Set(overlay.streets.flatMap { $0 }), Set(draft.flatMap { $0 }), "and drawn so out of the mode too")

        // Drawn again, it is road already.
        for end in corners.dropFirst() {
            session.dragRoad(from: corners[0].middle, to: end.middle)
        }
        XCTAssertEqual(session.roadPreview?.line(in: .traditionalChinese), "這裡已經有路了。")
        XCTAssertFalse(session.roadPreview?.canBuild ?? true)
    }

    /// The report's first tap: on a real-world map the city's road cells
    /// are not drawn (the base map draws its streets), so a tap on one does
    /// not say it is the city's road; it says how to draw one.
    func testATapOnTheCitysUnseenRoadCellSaysHowToDrawARoad() throws {
        let (session, middle) = try game()
        let roads = try XCTUnwrap(session.world.roads)
        var city: CellPosition?
        for ring in 0...12 {
            city = RoadGrid.ring(ring, round: middle).first { roads.cells.contains($0) && !roads.built.contains($0) }
            if city != nil { break }
        }
        session.tapRoadTool(at: try XCTUnwrap(city).middle)
        XCTAssertEqual(session.message?.text, "Drag across the map to lay a road. Tap one of your roads to take it up.")
        XCTAssertNil(session.roadRemoval)
    }
    /// BUGHUNT_BUILD P2-1: on a real-world map a bus goes along the base
    /// map's roads and the player's own. A road laid over the city's road
    /// cells where the base map has no bus road (an alley, a farm track)
    /// carries a city route GameCore measures along the cells, which stay
    /// the city's when it is taken up; the map's way would break. Taking it
    /// up is refused, naming the route.
    func testARoadACityBusNeedsOnARealMapIsNotTakenUp() throws {
        let (session, middle) = try game()
        let roads = try XCTUnwrap(session.world.roads)
        let onRoads = try XCTUnwrap(session.busRoads)
        var found: (stops: [CellPosition], along: [CellPosition])?
        search: for ring in 0...12 {
            for start in RoadGrid.ring(ring, round: middle) {
                for (dr, dc) in [(0, 1), (1, 0)] {
                    let along = (0...4).map { CellPosition(row: start.row + dr * $0, column: start.column + dc * $0) }
                    guard along.allSatisfy({ roads.cells.contains($0) && !roads.built.contains($0) }) else { continue }
                    let stops = [along[0], along[4]]
                    guard onRoads.way(ofSaved: stops, station: nil).firstBroken != nil else { continue }
                    found = (stops, along)
                    break search
                }
            }
        }
        let (stops, along) = try XCTUnwrap(found, "no line of the city's cells by 大社路 with no bus road along it")
        try session.performEdit { (world: inout GameWorld) throws(GameError) in
            try world.buildRoad(along: along)
        }
        let way = try XCTUnwrap(session.busRoads).way(ofSaved: stops, station: nil)
        XCTAssertNil(way.firstBroken, "the player's road joins the stops")
        let route = try session.performEdit { (world: inout GameWorld) throws(GameError) -> BusRouteID in
            try world.createBusRoute(to: nil, stops: stops, legMetres: way.legMetres, service: .every(minutes: 30), buses: 1).id
        }

        session.tapRoadTool(at: along[2].middle)
        let removal = try XCTUnwrap(session.roadRemoval)
        XCTAssertFalse(removal.canRemove, "the way along the map would break")
        XCTAssertEqual(removal.problem, "City bus \(route.rawValue) runs on this road. Change the route first.")
        XCTAssertFalse(session.confirmRoad())
        XCTAssertEqual(session.world.roads?.built, Set(along))
        XCTAssertNil(try XCTUnwrap(session.busRoads).way(ofSaved: stops, station: nil).firstBroken, "the bus roads are as they were")
    }

    /// Review L1-1: with many city routes, a tap on the player's road works
    /// out again only the routes whose way goes along it, on a copy of the
    /// bus roads. Before, every route was worked out twice and the bus
    /// roads' networks were let go each time: 19 routes held the tap 2.1 s
    /// (Linux debug).
    func testTakingUpARoadWithManyRoutesIsQuick() throws {
        let (session, middle) = try game()
        let roads = try XCTUnwrap(session.world.roads)
        let onRoads = try XCTUnwrap(session.busRoads)
        var own: [CellPosition]?
        search: for ring in 3...30 {
            for start in RoadGrid.ring(ring, round: middle) {
                let along = (0...4).map { CellPosition(row: start.row, column: start.column + $0) }
                if along.allSatisfy({ !roads.cells.contains($0) }) {
                    own = along
                    break search
                }
            }
        }
        let road = try XCTUnwrap(own, "no five cells without a road by 大社路")
        try session.performEdit { (world: inout GameWorld) throws(GameError) in
            try world.buildRoad(along: road)
        }
        // City routes of three stops along the city's roads round it.
        let cells = roads.cells.filter { abs($0.row - middle.row) < 40 && abs($0.column - middle.column) < 40 }
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        var made = 0, index = 0
        while made < 20, index + 600 < cells.count {
            let stops = [cells[index], cells[index + 300], cells[index + 600]]
            index += 37
            let way = onRoads.way(ofSaved: stops, station: nil)
            guard way.firstBroken == nil, let metres = way.legMetres else { continue }
            _ = try session.performEdit { (world: inout GameWorld) throws(GameError) -> BusRouteID in
                try world.createBusRoute(to: nil, stops: stops, legMetres: metres, service: .every(minutes: 30), buses: 1).id
            }
            made += 1
        }
        XCTAssertGreaterThanOrEqual(made, 15, "city routes by 大社路")
        // As the map draws them.
        XCTAssertNotNil(session.busMapOverlay)
        let version = try XCTUnwrap(session.busRoads).ownVersion
        // What the check cost before: every route's way on roads worked
        // out afresh (it did that twice).
        let fresh = Date()
        let again = try XCTUnwrap(session.busRoads).trying(ownRoads: roads.built.union(road))
        for route in session.world.busRoutes { _ = again.way(ofSaved: route.stops, station: nil) }
        let once = Date().timeIntervalSince(fresh)

        let start = Date()
        XCTAssertNil(session.routeBroken(byTakingUp: road, from: try XCTUnwrap(session.world.roads)))
        let took = Date().timeIntervalSince(start)
        XCTAssertLessThan(took, once, "the check took \(took) s, every way afresh \(once) s, with \(made) routes")
        session.tapRoadTool(at: road[2].middle)
        let removal = try XCTUnwrap(session.roadRemoval)
        XCTAssertTrue(removal.canRemove, "no route goes along it")
        XCTAssertEqual(try XCTUnwrap(session.busRoads).ownVersion, version, "the bus roads and the map's ways are left as they are")
    }
}
