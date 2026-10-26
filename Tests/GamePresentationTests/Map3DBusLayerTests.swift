import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 424's second sequel: the 3D map's buses are laid off the main
/// actor. The frame that asks first gets none (or the ones laid before for
/// the same scene) and never waits; once laid, they are the same buses
/// laying them on the main actor gave.
@MainActor
final class Map3DBusLayerTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private static let morning = 8.0 * 3_600 + 180

    /// What a frame lays from: the world, its scene and the base map's roads.
    private struct Laid {
        var world: GameWorld
        var scene: Map3DScene
        var roads: BusRoads?
        let station: PlanPoint
        let route: BusRouteID

        var signature: Map3DBuses.Signature { Map3DBuses.Signature(world: world, palette: .standard, roads: roads) }
        var target: Map3DPoint { scene.point(worldX: Double(station.x), worldY: Double(station.y), height: 0) }
    }

    /// The new game's line between its first two towns, a road along the
    /// first station's row 24 cells east, and a route of two stops on it
    /// (``Map3DBusesTests``'s).
    private func gridMap(buses: Int = 2) throws -> Laid {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(world.stations.first)
        let home = CellPosition(containing: station.location)
        let cells = (0...24).map { CellPosition(row: home.row, column: home.column + $0) }
        try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
        let route = try world.createBusRoute(to: station.id, stops: [cells[24], cells[14]], service: .every(minutes: 10), buses: buses)
        return Laid(world: world, scene: Map3DScene(world: world), roads: nil, station: station.location, route: route.id)
    }

    /// Taipei Station's neighbourhood with the base map, a route along the
    /// row 20 cells east of a station, and the base map's bus roads
    /// (``Map3DBusesTests/testOnARealMapGivenItsBusRoadsTheWayFollowsThem``'s).
    private func realMap() throws -> Laid {
        let tiles = try Self.tiles.get()
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        let station = try world.buildStation(named: "A", at: middle)
        let home = CellPosition(containing: middle)
        let cells = (0...20).map { CellPosition(row: home.row, column: home.column + $0) }
        world.enableRoads()
        try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
        let route = try world.createBusRoute(to: station.id, stops: [cells[20], cells[10]], legMetres: [640, 640], service: .every(minutes: 10),
                                             buses: 2)
        return Laid(world: world, scene: Map3DScene(world: world, baseMap: tiles),
                    roads: BusRoads(tiles: tiles, frame: try XCTUnwrap(RealWorldFrame(world: world))), station: station.location, route: route.id)
    }

    private func ask(_ layer: Map3DBuses.Layer, _ laid: Laid) -> Map3DBuses? {
        layer.buses(laid.signature, world: laid.world, in: laid.scene, palette: .standard, roads: laid.roads)
    }

    /// The buses `layer` laid for `laid`, once its laying is done.
    private func layDone(_ layer: Map3DBuses.Layer, _ laid: Laid) async throws -> Map3DBuses {
        _ = ask(layer, laid)
        await layer.laying?.task.value
        return try XCTUnwrap(ask(layer, laid), "laid once its laying is done")
    }

    /// That `a` and `b` are the same buses: the same routes, each with the
    /// same points and stops, and the same frame round the station.
    private func assertSame(_ a: Map3DBuses, _ b: Map3DBuses, _ laid: Laid, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (one, other) in zip(a.routes, b.routes) {
            XCTAssertEqual(one.out.points, other.out.points, file: file, line: line)
            XCTAssertEqual(one.back.points, other.back.points, file: file, line: line)
            XCTAssertEqual(one.stops, other.stops, file: file, line: line)
            XCTAssertEqual(one.length, other.length, file: file, line: line)
            XCTAssertEqual(one.tint, other.tint, file: file, line: line)
            XCTAssertEqual(one.motion, other.motion, file: file, line: line)
        }
        for second in [Self.morning, Self.morning + 400, 17.5 * 3_600] {
            let frames = [a, b].map { $0.frame(second: second, target: laid.target, distance: 900, detail: .full) }
            XCTAssertEqual(frames[0].instances.map(\.floats), frames[1].instances.map(\.floats), file: file, line: line)
        }
    }

    // MARK: - Laid off the main actor

    func testTheFirstAskLaysNothingThenAndGetsTheSameBusesOnceLaid() async throws {
        let map = try realMap()
        let layer = Map3DBuses.Layer()
        XCTAssertNil(ask(layer, map), "the first frame gets no bus")
        XCTAssertNil(layer.laid, "nor is anything laid as it asks")
        XCTAssertEqual(layer.started, 1)
        XCTAssertEqual(map.roads?.kept.regions, 0, "the roads are not read as it asks")
        let buses = try await layDone(layer, map)
        XCTAssertEqual(layer.started, 1)
        XCTAssertNil(layer.laying)
        XCTAssertTrue(buses.isLaid(from: map.signature, in: map.scene))

        // The same as laying them on the main actor, on fresh roads.
        let roads = BusRoads(tiles: try Self.tiles.get(), frame: try XCTUnwrap(RealWorldFrame(world: map.world)))
        let direct = Map3DBuses(world: map.world, scene: map.scene, palette: .standard, roads: roads)
        XCTAssertEqual(direct.count, 1)
        assertSame(buses, direct, map)
        XCTAssertFalse(buses.frame(second: Self.morning, target: map.target, distance: 900, detail: .full).instances.isEmpty)
    }

    func testAskingAgainWhileTheyAreLaidStartsNoOtherLaying() async throws {
        let map = try gridMap()
        let layer = Map3DBuses.Layer()
        for _ in 0..<5 { XCTAssertNil(ask(layer, map)) }
        XCTAssertEqual(layer.started, 1)
        let task = try XCTUnwrap(layer.laying?.task)
        await task.value
        for _ in 0..<5 { XCTAssertNotNil(ask(layer, map)) }
        XCTAssertEqual(layer.started, 1, "laid, they are handed out")
    }

    // MARK: - An ask that replaced the laying

    func testRoutesChangedBeforeTheyAreLaidKeepTheEarlierOnesOut() async throws {
        var map = try gridMap()
        let layer = Map3DBuses.Layer()
        XCTAssertNil(ask(layer, map))
        let earlier = try XCTUnwrap(layer.laying)
        // The main actor does not yield before the routes change, so the
        // earlier laying is done after the later one started.
        try map.world.setBusCount(map.route, to: 3)
        XCTAssertNil(ask(layer, map))
        let later = try XCTUnwrap(layer.laying)
        XCTAssertNotEqual(later.serial, earlier.serial)
        XCTAssertEqual(layer.started, 2)
        await earlier.task.value
        await later.task.value
        let laid = try XCTUnwrap(layer.laid)
        XCTAssertTrue(laid.isLaid(from: map.signature, in: map.scene), "the later routes' buses")
        assertSame(laid, Map3DBuses(world: map.world, scene: map.scene, palette: .standard), map)
    }

    func testWhileChangedRoutesAreLaidTheOldBusesRunOnThenTheNewOnes() async throws {
        var map = try gridMap()
        let layer = Map3DBuses.Layer()
        let old = try await layDone(layer, map)
        try map.world.setBusCount(map.route, to: 3)
        let meanwhile = try XCTUnwrap(ask(layer, map), "the same scene's buses run on")
        XCTAssertTrue(meanwhile.isLaid(from: old.signature, in: map.scene))
        XCTAssertFalse(meanwhile.isLaid(from: map.signature, in: map.scene))
        let new = try await layDone(layer, map)
        XCTAssertTrue(new.isLaid(from: map.signature, in: map.scene))
        XCTAssertEqual(layer.started, 2)
    }

    func testRoutesChangedBackWhileTheChangeIsLaidKeepTheOldBuses() async throws {
        let map = try gridMap()
        let layer = Map3DBuses.Layer()
        let old = try await layDone(layer, map)
        var changed = map
        try changed.world.setBusCount(map.route, to: 3)
        _ = ask(layer, changed)
        let replaced = try XCTUnwrap(layer.laying)
        // Back as they were before it is laid: the old ones, and the
        // change's laying is thrown away.
        XCTAssertTrue(try XCTUnwrap(ask(layer, map)).isLaid(from: old.signature, in: map.scene))
        XCTAssertNil(layer.laying)
        await replaced.task.value
        XCTAssertTrue(try XCTUnwrap(layer.laid).isLaid(from: map.signature, in: map.scene))
        XCTAssertEqual(layer.started, 2)
    }

    func testANewSceneGetsNoneOfTheOldScenesBuses() async throws {
        let map = try gridMap()
        let layer = Map3DBuses.Layer()
        _ = try await layDone(layer, map)
        var moved = map
        moved.scene = Map3DScene(world: map.world, focus: (x: 0, y: 0))
        XCTAssertNotEqual(Map3DBuses.SceneKey(moved.scene), Map3DBuses.SceneKey(map.scene), "another scene")
        XCTAssertNil(ask(layer, moved), "the old scene's buses are not drawn in the new one")
        let laid = try await layDone(layer, moved)
        XCTAssertTrue(laid.isLaid(from: moved.signature, in: moved.scene))
        XCTAssertFalse(laid.isLaid(from: map.signature, in: map.scene))
        XCTAssertEqual(layer.started, 2)
    }

    // MARK: - As before

    func testOnAMapWithoutABaseMapTheBusesAreTheRoadCellsAsBefore() async throws {
        let map = try gridMap()
        let layer = Map3DBuses.Layer()
        XCTAssertNil(ask(layer, map))
        let buses = try await layDone(layer, map)
        XCTAssertEqual(buses.count, 1)
        assertSame(buses, Map3DBuses(world: map.world, scene: map.scene, palette: .standard), map)
    }

    func testNoRouteLaysNoBusAsBefore() async throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(world.stations.first)
        let map = Laid(world: world, scene: Map3DScene(world: world), roads: nil, station: station.location, route: BusRouteID(rawValue: 1))
        let layer = Map3DBuses.Layer()
        let buses = try await layDone(layer, map)
        XCTAssertEqual(buses.count, 0)
        XCTAssertTrue(buses.frame(second: Self.morning, target: map.target, distance: 900, detail: .full).instances.isEmpty)
        assertSame(buses, Map3DBuses(world: world, scene: map.scene, palette: .standard), map)
    }

    // MARK: - How long it takes

    /// `BUS_3D_REPORT=1`: on a real-world map of Taipei with the base map's
    /// roads, 1, 5 and 20 saved routes round a station, each on fresh
    /// (cold) roads: laying them on the main actor as before, and now the
    /// main actor's ask a frame while they are laid and the laying off it
    /// (decision 424's second sequel, "量到的").
    func testHowLongItTakesOnARealMap() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUS_3D_REPORT"] != nil, "BUS_3D_REPORT=1 to measure")
        let tiles = try Self.tiles.get()
        var start = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        // Cash enough for twenty routes' buses.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(start)) as? [String: Any])
        var economy = try XCTUnwrap(json["economy"] as? [String: Any])
        economy["balance"] = Int64(1_000_000_000_000)
        json["economy"] = economy
        start = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        let middle = PlanPoint(x: start.bounds.width / 2, y: start.bounds.height / 2)
        let station = try start.buildStation(named: "A", at: middle)
        start.enableRoads()
        let home = CellPosition(containing: middle)
        let frame = try XCTUnwrap(RealWorldFrame(world: start))
        var rows: [String] = []
        for count in [1, 5, 20] {
            var world = start
            // East, west, north and south of the station, on rows (or
            // columns) 3 cells apart, each joined to it.
            var routes: [[CellPosition]] = [], cells: [CellPosition] = []
            for route in 0..<count {
                let (along, across) = [(0, 1), (0, -1), (1, 0), (-1, 0)][route % 4]
                let side = (route / 4 - 2) * 3
                func cell(_ out: Int, _ aside: Int) -> CellPosition {
                    CellPosition(row: home.row + along * out + across * aside, column: home.column + across * out + along * aside)
                }
                cells += (0...abs(side)).map { cell(0, side < 0 ? -$0 : $0) } + (0...20).map { cell($0, side) }
                routes.append([cell(20, side), cell(10, side)])
            }
            try world.setRoads(Array(Set(cells)), in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
            for stops in routes {
                _ = try world.createBusRoute(to: station.id, stops: stops, legMetres: [640, 640], service: .every(minutes: 10), buses: 2)
            }
            let scene = Map3DScene(world: world, baseMap: tiles)

            // Before: on the main actor, in the frame.
            var clock = Date()
            let direct = Map3DBuses(world: world, scene: scene, palette: .standard, roads: BusRoads(tiles: tiles, frame: frame))
            let before = Date().timeIntervalSince(clock)

            // Now: the frame's ask, the first and the 600 after while it is laid.
            let roads = BusRoads(tiles: tiles, frame: frame)
            let signature = Map3DBuses.Signature(world: world, palette: .standard, roads: roads)
            let layer = Map3DBuses.Layer()
            clock = Date()
            XCTAssertNil(layer.buses(signature, world: world, in: scene, palette: .standard, roads: roads))
            let first = Date().timeIntervalSince(clock)
            clock = Date()
            for _ in 0..<600 { _ = layer.buses(signature, world: world, in: scene, palette: .standard, roads: roads) }
            let waiting = Date().timeIntervalSince(clock) / 600
            let background = Date()
            await layer.laying?.task.value
            let laid = try XCTUnwrap(layer.buses(signature, world: world, in: scene, palette: .standard, roads: roads))
            // The laying started with the first ask; what is left of it once the frames above ran.
            let off = Date().timeIntervalSince(background) + waiting * 600 + first
            XCTAssertEqual(laid.count, direct.count)
            clock = Date()
            for _ in 0..<600 { _ = layer.buses(signature, world: world, in: scene, palette: .standard, roads: roads) }
            let after = Date().timeIntervalSince(clock) / 600
            rows.append(String(format: "| %d | %d | %.0f ms | %.3f ms | %.4f ms | %.0f ms | %.4f ms |", count, direct.count, before * 1_000,
                               first * 1_000, waiting * 1_000, off * 1_000, after * 1_000))
        }
        print((["| routes | laid | before: on the main actor | now: first ask | a frame while laid | laid off the main actor | a frame once laid |",
                "| --: | --: | --: | --: | --: | --: | --: |"] + rows).joined(separator: "\n"))
    }
}
