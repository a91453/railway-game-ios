import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400, 10i-6: the player's bus routes' buses on the 3D map, laid
/// along the streets and placed from the game's clock alone. A cell is
/// 4,096 units (64 m).
final class Map3DBusesTests: XCTestCase {
    private let cell = Land.cellLength

    // MARK: - The way on the plan

    func testOnAMapWithoutABaseMapTheWayGoesRoundTheRoadCellsEdges() {
        // Along row 0, then a step down and to the right, then row 1.
        let roads: Set<CellPosition> = [CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 1), CellPosition(row: 0, column: 2),
                                        CellPosition(row: 1, column: 3), CellPosition(row: 1, column: 4), CellPosition(row: 1, column: 5)]
        let station = CellPosition(row: 1, column: 5).middle
        let way = Map3DBuses.way(stops: [CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 2)], station: station, roads: roads,
                                 alongEdges: true)
        // Every point a corner of the grid, each piece along a grid line,
        // and each piece an edge of a road cell.
        for point in way.points {
            XCTAssertEqual(point.x % cell, 0)
            XCTAssertEqual(point.y % cell, 0)
        }
        for (a, b) in zip(way.points, way.points.dropFirst()) {
            XCTAssertTrue(a.x == b.x || a.y == b.y, "\(a) to \(b) cuts across a block")
            XCTAssertEqual(abs(a.x - b.x) + abs(a.y - b.y), cell, "one edge at a time")
            let edgeOfARoad = roads.contains { road in
                let corners = Map3DBuses.Corner.corners(of: road).map(\.point)
                return corners.contains(a) && corners.contains(b)
            }
            XCTAssertTrue(edgeOfARoad, "\(a) to \(b)")
        }
        XCTAssertEqual(way.stops.count, 3, "two stops and the station")
        XCTAssertEqual(way.stops.first, 0)
        XCTAssertEqual(way.stops, way.stops.sorted())
        XCTAssertTrue(Map3DBuses.Corner.corners(of: CellPosition(containing: station)).map(\.point).contains(way.points[way.stops[2]]),
                      "ends at a corner of the station's cell")
    }

    func testOnARealMapTheWayGoesThroughTheCellsMiddles() {
        let roads = Set((0...4).map { CellPosition(row: 2, column: $0) })
        let station = CellPosition(row: 2, column: 4).middle
        let way = Map3DBuses.way(stops: [CellPosition(row: 2, column: 0), CellPosition(row: 2, column: 2)], station: station, roads: roads,
                                 alongEdges: false)
        XCTAssertEqual(way.points, (0...4).map { CellPosition(row: 2, column: $0).middle })
        XCTAssertEqual(way.stops, [0, 2, 4])
    }

    // MARK: - In the scene

    /// The new game's line between its first two towns, a road along the
    /// first station's row 24 cells east, and a route of two stops on it.
    private func world(buses: Int, service: BusService = .every(minutes: 10)) throws -> (GameWorld, BusRoute) {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(world.stations.first)
        // The line in a red, for the bus's stripes.
        try world.setLineColor(try XCTUnwrap(world.lines(callingAt: station.id).first?.id), to: LineColor(rgb: 0xE8574A))
        let home = CellPosition(containing: station.location)
        let cells = (0...24).map { CellPosition(row: home.row, column: home.column + $0) }
        try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
        let route = try world.createBusRoute(to: station.id, stops: [cells[24], cells[14]], service: service, buses: buses)
        return (world, route)
    }

    /// The scene's point over `second`'s first bus, and the frame.
    private func busFrame(_ buses: Map3DBuses, second: Double, target: Map3DPoint, distance: Float = 300,
                          detail: Map3DStreetDetail = .full, most: Int? = nil) -> Map3DBuses.Frame {
        buses.frame(second: second, target: target, distance: distance, detail: detail, most: most)
    }

    func testABusDrivesTheRouteInItsLinesColourOnTheRoad() throws {
        let (world, route) = try world(buses: 2)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        XCTAssertEqual(buses.count, 1)
        let station = try XCTUnwrap(world.station(id: route.station))
        let target = scene.point(worldX: Double(station.location.x), worldY: Double(station.location.y), height: 0)
        // 08:03, a bus on its way.
        let frame = busFrame(buses, second: 8 * 3_600 + 180, target: target, distance: 900)
        XCTAssertFalse(frame.instances.isEmpty)
        let model = try XCTUnwrap(Map3DModelPack.standard.index(of: Map3DLowFloorBus.routeModelName))
        let colour = try XCTUnwrap(world.lines(callingAt: route.station).first?.color)
        let tint = Map3DColor.rgb(UInt32(colour.rgb))
        for bus in frame.instances {
            XCTAssertEqual(bus.model, model)
            XCTAssertEqual(bus.stripe.0, Float(tint & 0xFF) / 255, accuracy: 0.001)
            XCTAssertEqual(bus.stripe.1, Float((tint >> 8) & 0xFF) / 255, accuracy: 0.001)
            XCTAssertEqual(bus.stripe.2, Float((tint >> 16) & 0xFF) / 255, accuracy: 0.001)
            // On a lane's height, within the road's width of one, and short
            // of the station's house.
            let foot = Map3DPoint(bus.transform[12], bus.transform[13], bus.transform[14])
            XCTAssertGreaterThan(Map3DPoint(foot.x - target.x, 0, foot.z - target.z).length, Map3DBuses.stationClearance - 4)
            let index = Map3DBuses.RoadIndex(lanes: scene.streetLife.lanes, near: [foot])
            let road = try XCTUnwrap(index.nearest(to: foot, within: 20), "\(foot) is on no road")
            XCTAssertLessThan(road.distance, 6)
            XCTAssertEqual(foot.y, road.point.y, accuracy: 1.5)
        }
        // The same second, the same buses.
        let again = busFrame(Map3DBuses(world: world, scene: scene, palette: .standard), second: 8 * 3_600 + 180, target: target, distance: 900)
        XCTAssertEqual(again.instances.map(\.floats), frame.instances.map(\.floats))
        // The tint is the palette's.
        let safe = Map3DBuses(world: world, scene: scene, palette: .colourBlindSafe)
        let safeTint = Map3DColor.rgb(UInt32(LinePalette.colourBlindSafe.color(for: colour.rgb)))
        XCTAssertEqual(busFrame(safe, second: 8 * 3_600 + 180, target: target, distance: 900).instances.first?.stripe.0 ?? -1,
                       Float(safeTint & 0xFF) / 255, accuracy: 0.001)
    }

    func testNoBusAFarCameraOrNoDetailDrawsNone() throws {
        let (world, route) = try world(buses: 0)
        let scene = Map3DScene(world: world)
        XCTAssertEqual(Map3DBuses(world: world, scene: scene, palette: .standard).count, 0, "a route of no bus")
        let (running, _) = try self.world(buses: 2)
        let busy = Map3DScene(world: running)
        let buses = Map3DBuses(world: running, scene: busy, palette: .standard)
        let station = try XCTUnwrap(world.station(id: route.station))
        let target = busy.point(worldX: Double(station.location.x), worldY: Double(station.location.y), height: 0)
        XCTAssertTrue(busFrame(buses, second: 8 * 3_600 + 180, target: target, distance: Map3DStreetLife.vehiclesFrom + 1).instances.isEmpty)
        XCTAssertTrue(busFrame(buses, second: 8 * 3_600 + 180, target: target, distance: 900, detail: .off).instances.isEmpty)
        XCTAssertTrue(busFrame(buses, second: 8 * 3_600 + 180, target: target + Map3DPoint(20_000, 0, 0)).instances.isEmpty, "out of reach")
    }

    func testItIsLaidAgainOnlyWhenTheRoutesOrTheSceneChange() throws {
        var (world, route) = try world(buses: 2)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        XCTAssertTrue(buses.isLaid(from: Map3DBuses.Signature(world: world, palette: .standard), in: scene))
        try world.advance(ticks: 3)
        XCTAssertTrue(buses.isLaid(from: Map3DBuses.Signature(world: world, palette: .standard), in: scene), "time alone moves nothing")
        try world.setBusCount(route.id, to: 3)
        XCTAssertFalse(buses.isLaid(from: Map3DBuses.Signature(world: world, palette: .standard), in: scene))
        XCTAssertFalse(buses.isLaid(from: Map3DBuses.Signature(world: world, palette: .colourBlindSafe), in: scene))
    }

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    func testOnARealMapTheWayIsPutOnTheBaseMapsRoads() throws {
        let tiles = try Self.tiles.get()
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        let station = try world.buildStation(named: "A", at: middle)
        let home = CellPosition(containing: middle)
        // Road cells along the row east of it, as the base map's roads are
        // read (most of central Taipei's cells have one).
        let cells = (0...20).map { CellPosition(row: home.row, column: home.column + $0) }
        world.enableRoads()
        try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
        _ = try world.createBusRoute(to: station.id, stops: [cells[20], cells[10]], legMetres: [640, 640], service: .every(minutes: 10), buses: 2)
        let scene = Map3DScene(world: world, baseMap: tiles)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let route = try XCTUnwrap(buses.routes.first)
        let index = Map3DBuses.RoadIndex(lanes: scene.streetLife.lanes, near: route.out.points)
        let onRoads = route.out.points.filter { point in index.nearest(to: point, within: 12).map { $0.distance < $0.half + 1 } ?? false }
        XCTAssertGreaterThan(Double(onRoads.count) / Double(route.out.points.count), 0.8, "\(onRoads.count) of \(route.out.points.count)")
    }

    // MARK: - The street's traffic

    func testTheStreetsVehiclesGiveWayToTheBuses() throws {
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(400, 0, 0)]))
        var life = Map3DStreetLife()
        life.lanes = [Map3DStreetLife.Lane(path: path, half: 4, twoWay: true, speed: 11, perHundred: 8, scooters: false, seed: (1, 2))]
        let plain = life.frame(target: Map3DPoint(200, 0, 0), distance: 300, time: 77, detail: .full, activity: .init())
        // A bus over every eastbound car's place: each of them gives way.
        var buses = Map3DBuses.Frame()
        let eastbound = plain.instances.filter { $0.transform[0] > 0.1 }
        XCTAssertGreaterThan(eastbound.count, 5)
        buses.clear = eastbound.map { (Map3DPoint($0.transform[12], 0, $0.transform[14]), Map3DPoint(1, 0, 0)) }
        let given = life.frame(target: Map3DPoint(200, 0, 0), distance: 300, time: 77, detail: .full, activity: .init(), buses: buses)
        XCTAssertTrue(given.instances.filter { $0.transform[0] > 0.1 }.isEmpty)
        XCTAssertEqual(given.instances.filter { $0.transform[0] < -0.1 }.count, plain.instances.filter { $0.transform[0] < -0.1 }.count,
                       "the other way's cars, across the road, go on")
        XCTAssertEqual(Map3DStreetLife.giveWay(at: Map3DPoint(20, 0, 0), to: [(Map3DPoint(0, 0, 0), Map3DPoint(1, 0, 0))]), 1)
        XCTAssertEqual(Map3DStreetLife.giveWay(at: Map3DPoint(11, 0, 1), to: [(Map3DPoint(0, 0, 0), Map3DPoint(1, 0, 0))]), 0.5, accuracy: 0.001)
    }

    func testTheRouteBusesComeFirstAndCountAsVehicles() throws {
        let model = try XCTUnwrap(Map3DModelPack.standard.index(of: Map3DLowFloorBus.routeModelName))
        var buses = Map3DBuses.Frame()
        buses.instances = [.prop(model, at: .zero, forward: Map3DPoint(1, 0, 0), scale: 1, tint: 0)]
        let frame = Map3DStreetLife().frame(target: .zero, distance: 300, time: 0, detail: .full, activity: .init(), buses: buses)
        XCTAssertEqual(frame.vehicles, 1)
        XCTAssertEqual(frame.buses, 1)
        XCTAssertEqual(frame.instances.first?.model, model)
    }

    func testAtMostTheBusModelsBudgetIsDrawnTheNearestFirst() throws {
        let (start, route) = try world(buses: 1)
        // Cash enough for many routes' buses.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(start)) as? [String: Any])
        var economy = try XCTUnwrap(json["economy"] as? [String: Any])
        economy["balance"] = Int64(1_000_000_000_000)
        json["economy"] = economy
        var world = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        for _ in 0..<15 {
            _ = try world.createBusRoute(to: route.station, stops: route.stops, service: .every(minutes: 1), buses: 10)
        }
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let station = try XCTUnwrap(world.station(id: route.station))
        let target = scene.point(worldX: Double(station.location.x), worldY: Double(station.location.y), height: 0)
        let frame = busFrame(buses, second: 8 * 3_600 + 180, target: target, distance: 900)
        XCTAssertEqual(frame.instances.count, Map3DStreetLife.mostBuses)
        let aways = frame.instances.map { Map3DPoint($0.transform[12] - target.x, 0, $0.transform[14] - target.z).length }
        XCTAssertEqual(aways, aways.sorted())
        XCTAssertEqual(busFrame(buses, second: 8 * 3_600 + 180, target: target, distance: 900, detail: .reduced).instances.count,
                       Map3DStreetLife.mostBuses)
        // The street's own buses share the budget: none is left for them.
        let street = Map3DStreetLife().frame(target: .zero, distance: 300, time: 0, detail: .full, activity: .init(), buses: frame)
        XCTAssertEqual(street.buses, Map3DStreetLife.mostBuses)
        // Decision 417: the lower tier's 10, the nearest; then the budget's
        // limits, the route buses among them, never cut.
        let lower = busFrame(buses, second: 8 * 3_600 + 180, target: target, distance: 900, most: Map3DDeviceTier.lower.streetLimits.buses)
        XCTAssertEqual(lower.instances.count, 10)
        XCTAssertEqual(lower.instances.map(\.transform), Array(frame.instances.prefix(10)).map(\.transform))
        let limits = Map3DMotionBudget(tier: .lower, step: .full, trainTriangles: 0).limits(routeBuses: lower.instances.count)
        XCTAssertEqual(limits.buses, 10)
        let kept = Map3DStreetLife().frame(target: .zero, distance: 300, time: 0, detail: .reduced, activity: .init(), buses: lower,
                                           limits: limits)
        XCTAssertEqual(kept.buses, 10)
        XCTAssertEqual(kept.vehicles, 10)
        let squeezed = Map3DStreetLimits(people: 0, vehicles: 3, buses: 3)
        XCTAssertEqual(Map3DStreetLife().frame(target: .zero, distance: 300, time: 0, detail: .reduced, activity: .init(), buses: lower,
                                               limits: squeezed).buses, 10, "the player's buses are never cut")
    }

    func testTheRouteBusIsTheLowFloorBusWithItsStripesTinted() {
        let route = Map3DLowFloorBus.routeModel(), plain = Map3DLowFloorBus.model()
        XCTAssertEqual(route.vertices.count, plain.vertices.count)
        XCTAssertEqual(route.vertices.map(\.x), plain.vertices.map(\.x))
        XCTAssertFalse(route.vertices.contains { $0.color == Map3DLowFloorBus.accentColor })
        XCTAssertTrue(route.vertices.contains { $0.color >> 24 == 0 }, "the stripes take the tint")
        XCTAssertEqual(Map3DModelPack.standard.models.last?.name, Map3DLowFloorBus.routeModelName, "last, so no model before it moves")
    }

    // MARK: - How long it takes

    /// `BUS_3D_REPORT=1`: the time to lay and to place many routes' buses
    /// on the Linux machine (decision 400, 10i-6, "量到的").
    func testHowLongItTakes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUS_3D_REPORT"] != nil, "BUS_3D_REPORT=1 to measure")
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        // Cash enough for twenty routes' buses.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var economy = try XCTUnwrap(json["economy"] as? [String: Any])
        economy["balance"] = Int64(1_000_000_000_000)
        json["economy"] = economy
        world = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        let station = try XCTUnwrap(world.stations.first)
        let home = CellPosition(containing: station.location)
        var rows: [String] = []
        for count in [1, 5, 20] {
            var fed = world
            var cells: [CellPosition] = []
            for route in 0..<count {
                let row = home.row + (route % 2 == 0 ? 1 : -1) * (route / 2)
                cells += (0...24).map { CellPosition(row: row, column: home.column + $0) }
                cells += (0...abs(row - home.row)).map { CellPosition(row: home.row + (row > home.row ? $0 : -$0), column: home.column) }
            }
            try fed.setRoads(Array(Set(cells)), in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
            for route in 0..<count {
                let row = home.row + (route % 2 == 0 ? 1 : -1) * (route / 2)
                _ = try fed.createBusRoute(to: station.id, stops: [CellPosition(row: row, column: home.column + 24),
                                                                   CellPosition(row: row, column: home.column + 12)],
                                           service: .every(minutes: 5), buses: 9)
            }
            let scene = Map3DScene(world: fed)
            var start = Date()
            let buses = Map3DBuses(world: fed, scene: scene, palette: .standard)
            let lay = Date().timeIntervalSince(start)
            let target = scene.point(worldX: Double(station.location.x), worldY: Double(station.location.y), height: 0)
            start = Date()
            var drawn = 0
            for frame in 0..<600 {
                drawn += buses.frame(second: 8 * 3_600 + Double(frame) / 60, target: target, distance: 900, detail: .full).instances.count
            }
            let place = Date().timeIntervalSince(start) / 600
            let plain = scene.streetLife
            start = Date()
            for frame in 0..<200 { _ = plain.frame(target: target, distance: 900, time: Double(frame), detail: .full, activity: .init()) }
            let alone = Date().timeIntervalSince(start) / 200
            let busFrame = buses.frame(second: 8 * 3_600, target: target, distance: 900, detail: .full)
            start = Date()
            for frame in 0..<200 {
                _ = plain.frame(target: target, distance: 900, time: Double(frame), detail: .full, activity: .init(), buses: busFrame)
            }
            let given = Date().timeIntervalSince(start) / 200
            rows.append(String(format: "| %d | %d | %.1f ms | %.3f ms | %.3f ms → %.3f ms |", count, drawn / 600, lay * 1_000, place * 1_000,
                               alone * 1_000, given * 1_000))
        }
        print((["| routes | buses drawn | lay | place a frame | street life a frame (without → with buses) |",
                "| --: | --: | --: | --: | --: |"] + rows).joined(separator: "\n"))
    }
}
