import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 474, on the app's own base map: the three bus reports of
/// 2026-10-29 (`docs/research/PLAYER_FEEDBACK.md`). A road in a tunnel
/// (辛亥隧道) joins the stops on either side; on a divided road (新港三路 by
/// 豐富 Station) a stop goes on the carriageway its bus takes to the
/// station; and a saved route a leg of which no road joins is drawn broken,
/// never straight across the blocks, in 2D or 3D.
@MainActor
final class BusOneWayAndTunnelRealMapTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    private static let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)

    private static func point(_ latitude: Double, _ longitude: Double) -> PlanPoint {
        let position = frame.worldPosition(latitude: latitude, longitude: longitude)
        return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
    }

    private static func metres(_ a: PlanPoint, _ b: PlanPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y)) / Double(WorldCoordinate.unitsPerMetre)
    }

    /// The whole of Taiwan with a station at `station`, its land and roads
    /// read round it, the bus tool open.
    private func game(station at: PlanPoint) throws -> (GameSession, StationID) {
        var world = GameWorld.newWholeTaiwanGame()
        let station = try world.buildStation(named: "Station", at: at)
        let session = GameSession(world: world)
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLand(within: WholeTaiwan.landReach, of: at)
        session.selectTool(.bus)
        return (session, station.id)
    }

    // MARK: - 93.1: 「山洞公車無法通行」

    /// 辛亥路 runs through 辛亥隧道 (two one-way bores): stops on either
    /// side are joined through it, the bus taking the bore of its way, and
    /// the 3D bus is not drawn while inside.
    func testStopsEitherSideOfATunnelAreJoinedThroughIt() throws {
        let roads = BusRoads(tiles: try Self.tiles.get(), frame: Self.frame)
        // Taps on 辛亥路 by the tunnel's north-west mouth, and its south-east one.
        let west = Self.point(25.01390, 121.55340), east = Self.point(25.00940, 121.55800)
        // No stop in the tunnel: over its middle is the hill.
        XCTAssertNil(roads.place(near: Self.point(25.01170, 121.55573), within: 25))
        for (first, second) in [(west, east), (east, west)] {
            // Each on the carriageway of the bus's way, as the bus tool puts them.
            let from = try XCTUnwrap(roads.place(near: first, within: 25, leadingTo: BusEnd(second)))
            let to = try XCTUnwrap(roads.place(near: second, within: 25, from: BusEnd(from)))
            let way = roads.way(stops: [from, to], station: nil)
            XCTAssertNil(way.firstBroken, "the tunnel joins them")
            let metres = Double(try XCTUnwrap(way.legMetres?.first))
            XCTAssertLessThan(metres, Self.metres(from, to) * 1.3, "through the tunnel, not round the hill")
            let inside = zip(zip(way.points, way.points.dropFirst()), way.tunnels).filter(\.1).reduce(0.0) { $0 + Self.metres($1.0.0, $1.0.1) }
            XCTAssertGreaterThan(inside, 400, "some 480 m of it in the tunnel")
        }
    }

    // MARK: - 93.1: 「把圖資上兩條不同方向的路都當成皆可雙向」

    /// 新港三路 north-west of 豐富 Station is two one-way carriageways: a tap
    /// between them, nearer the one going away from the station, puts the
    /// stop on the one going to it, and the way there keeps to the
    /// carriageways' ways.
    func testOnADividedRoadTheStopGoesOnTheCarriagewayToTheStation() throws {
        let station = Self.point(24.60530, 120.82530)
        let (session, id) = try game(station: station)
        let roads = try XCTUnwrap(session.busRoads)
        session.tapBusTool(at: station, reach: Land.cellLength)
        XCTAssertEqual(session.busDraft.station, id)
        // The north-west-bound carriageway, a point on it, and a tap 3 m
        // off it towards the other one.
        let away = try XCTUnwrap(roads.place(near: Self.point(24.60680, 120.82050), within: 25))
        let network = roads.network(from: BusRoadNetwork.Point(away), to: BusRoadNetwork.Point(away))
        let piece = try XCTUnwrap(network.nearest(to: BusRoadNetwork.Point(away), within: 1))
        XCTAssertTrue(network.isOneway(piece))
        let heading = network.direction(of: piece.segment)
        XCTAssertLessThan(heading.dx, 0, "it runs west, away from the station")
        let other = try XCTUnwrap(network.nearest(to: BusRoadNetwork.Point(away), within: 25, facing: heading), "the other carriageway")
        let toward = (dx: other.point.x - piece.point.x, dy: other.point.y - piece.point.y)
        let gap = hypot(toward.dx, toward.dy)
        let tap = PlanPoint(x: away.x + Int64(toward.dx / gap * 3 * 64), y: away.y + Int64(toward.dy / gap * 3 * 64))
        session.tapBusTool(at: tap, reach: Land.cellLength)
        XCTAssertEqual(session.busDraft.stops.count, 1, session.message?.text ?? "")
        let pin = try XCTUnwrap(session.busDraft.stopPoints.first)
        let on = try XCTUnwrap(network.nearest(to: BusRoadNetwork.Point(pin), within: 1))
        XCTAssertTrue(network.isOneway(on))
        XCTAssertGreaterThan(network.direction(of: on.segment).dx, 0, "on the carriageway going east, to the station")
        // And the way it takes is no detour round the blocks.
        let metres = Double(try XCTUnwrap(session.busDraft.legMetres?.first))
        XCTAssertLessThan(metres, Self.metres(pin, station) * 1.6)
        XCTAssertNil(session.busPreview?.problem)
    }

    // MARK: - 92.1: 「公車模式未依照實際道路行駛」

    /// A saved route whose stop no bus road reaches (a road cell in the
    /// Tamsui River by 萬華 Station) is drawn broken between that stop and
    /// the station, the rest along the roads, and has no 3D bus: no line
    /// straight across the blocks, as the road cells drew it before.
    func testASavedLegNoRoadJoinsIsDrawnBrokenNotStraight() throws {
        let tiles = try Self.tiles.get()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0334, longitudeDegrees: 121.4998))
        var world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let roads = BusRoads(tiles: tiles, frame: frame)
        func point(_ latitude: Double, _ longitude: Double) -> PlanPoint {
            let position = frame.worldPosition(latitude: latitude, longitude: longitude)
            return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        }
        let wanhua = point(25.03340, 121.49980)
        let station = try world.buildStation(named: "Wanhua", at: wanhua)
        // A cell west of the station that no bus road is within 130 m of
        // (the river), and a stop on a road between them.
        var river: CellPosition?
        for step in 6...30 {
            let candidate = PlanPoint(x: wanhua.x - Int64(step) * Land.cellLength, y: wanhua.y)
            if roads.place(near: candidate, within: 130) == nil {
                river = CellPosition(containing: candidate)
                break
            }
        }
        let wet = try XCTUnwrap(river)
        let street = try XCTUnwrap(roads.place(near: PlanPoint(x: wanhua.x, y: wanhua.y - 300 * 64), within: 60))
        let cells = [wet, CellPosition(containing: street), CellPosition(containing: wanhua)]
        world.enableRoads()
        try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
        let route = try world.createBusRoute(to: station.id, stops: [cells[0], cells[1]], legMetres: [1_000, 400], service: .every(minutes: 10), buses: 2)

        let session = GameSession(world: world)
        try CommandLogReplay.realWorld.install(RealWorldDataSet(baseMap: true), in: session)
        let onRoads = try XCTUnwrap(session.busRoads)
        let saved = onRoads.way(ofSaved: route.stops, station: wanhua)
        XCTAssertEqual(saved.firstBroken, 0, "no road reaches the stop in the river")
        let overlay = try XCTUnwrap(session.busMapOverlay)
        let drawn = try XCTUnwrap(overlay.routes.first)
        XCTAssertEqual(drawn.broken.count, 2, "the leg drawn broken")
        XCTAssertEqual(drawn.stops.count, 2, "both stops still shown")
        XCTAssertFalse(drawn.points.isEmpty, "the leg after it drawn along the roads")
        for (a, b) in zip(drawn.points, drawn.points.dropFirst()) {
            let middle = PlanPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            guard Self.metres(middle, wanhua) > Double(BusRoadNetwork.stationReach) else { continue }
            XCTAssertNotNil(onRoads.place(near: middle, within: 12), "\(a)–\(b) runs off the roads")
        }
        // The legs GameCore was given stay.
        XCTAssertEqual(session.world.busRoutes.first?.legMetres, [1_000, 400])
        // Opened in the bus tool, it says which leg has no road and cannot
        // be saved until it does.
        session.editBusRoute(route.id)
        XCTAssertEqual(session.busPreview?.brokenLeg.count, 2)
        XCTAssertEqual(session.busPreview?.canOpen, false)

        // No 3D bus drives straight across the blocks.
        let scene = Map3DScene(world: world, baseMap: tiles)
        XCTAssertEqual(Map3DBuses(world: world, scene: scene, palette: .standard, roads: onRoads).count, 0)
    }
}
