import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400's sequel: a real-world map's roads read cell by cell from
/// the base map's `transportation` layer as its land is read in, handed to
/// GameCore (``GameWorld/setRoads(_:in:)``); the freeways and expressways
/// kept apart (``GameSession/highwayCells()``), and the base map logged
/// for a replay.
@MainActor
final class RealRoadCellsTests: XCTestCase {
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: CommandLogReplay.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                    options: .alwaysMapped))
    }

    private static let taipei = (latitude: 25.0478, longitude: 121.5170)

    // MARK: - A tile laid by hand

    /// A line of `kind` from (`x0`, `z`) to (`x1`, `z`) metres of the world,
    /// in tile `column`, `row`'s units.
    private func line(
        _ kind: String, from x0: Double, to x1: Double, at z: Double, column: Int, row: Int, projection: RealRoadCells.Projection,
        brunnel: String? = nil, ramp: Bool = false
    ) -> VectorTile.Feature {
        let (west, north, scale) = projection.place(column: column, row: row, extent: 4096)
        func point(_ x: Double) -> VectorTile.Point {
            VectorTile.Point(x: Int32(((x - west) / scale).rounded()), y: Int32(((z - north) / scale).rounded()))
        }
        var properties: [String: VectorTile.Value] = ["class": .string(kind)]
        if let brunnel { properties["brunnel"] = .string(brunnel) }
        if ramp { properties["ramp"] = .number(1) }
        return VectorTile.Feature(kind: .line, properties: properties, parts: [[point(x0), point(x1)]])
    }

    func testATilesRoadsAreCellsAndItsFreewaysAreKeptApart() {
        let frame = RealWorldFrame(anchor: GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude)!,
                                   bounds: .standard)
        let projection = RealRoadCells.Projection(frame: frame)
        // A tile in the middle of the map, and roads well inside it.
        let column = projection.column(8_192), row = projection.row(8_192)
        let (west, north, _) = projection.place(column: column, row: row, extent: 4096)
        let x0 = (west / 64).rounded(.up) * 64 + 64 * 4 + 10, z0 = (north / 64).rounded(.up) * 64 + 64 * 4 + 32
        func feature(_ kind: String, cellRow: Double, brunnel: String? = nil, ramp: Bool = false) -> VectorTile.Feature {
            line(kind, from: x0, to: x0 + 64 * 3, at: z0 + 64 * cellRow, column: column, row: row, projection: projection, brunnel: brunnel, ramp: ramp)
        }
        let layer = VectorTile.Layer(name: "transportation", extent: 4096, features: [
            feature("minor", cellRow: 0),
            feature("service", cellRow: 2),
            // A road in a tunnel: no cell.
            feature("primary", cellRow: 4, brunnel: "tunnel"),
            // A freeway, its link, and an expressway in a tunnel: highways.
            feature("motorway", cellRow: 6, brunnel: "bridge"),
            feature("motorway", cellRow: 8, ramp: true),
            feature("trunk", cellRow: 10, brunnel: "tunnel"),
            // Not a road.
            feature("rail", cellRow: 12),
            feature("path", cellRow: 14),
        ])
        let all = Set((0..<Land.blockRows(in: .standard)).flatMap { r in (0..<Land.blockColumns(in: .standard)).map { LandBlock(row: r, column: $0) } })
        var cells = RealRoadCells.Cells()
        RealRoadCells.add(layer, column: column, row: row, projection: projection, blocks: all, bounds: .standard, to: &cells)

        let firstRow = Int(z0 / 64), firstColumn = Int(x0 / 64)
        func run(_ offset: Int) -> Set<CellPosition> {
            Set((firstColumn...firstColumn + 3).map { CellPosition(row: firstRow + offset, column: $0) })
        }
        XCTAssertEqual(cells.roads, run(0).union(run(2)))
        XCTAssertEqual(cells.highways, run(6).union(run(8)).union(run(10)))

        // Only the blocks asked for.
        let one: Set<LandBlock> = [LandBlock(cellRow: firstRow, column: firstColumn)]
        var some = RealRoadCells.Cells()
        RealRoadCells.add(layer, column: column, row: row, projection: projection, blocks: one, bounds: .standard, to: &some)
        XCTAssertFalse(some.roads.isEmpty)
        XCTAssertTrue(some.roads.allSatisfy { one.contains(LandBlock(cellRow: $0.row, column: $0.column)) })
        XCTAssertTrue(some.roads.isSubset(of: cells.roads))
    }

    // MARK: - The app's base map

    /// The whole of Taiwan with its data and base map, the land read round
    /// Taipei Station.
    private func taipeiGame() throws -> (GameSession, PlanPoint) {
        let session = GameSession(world: GameWorld.newWholeTaiwanGame())
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let position = frame.worldPosition(latitude: Self.taipei.latitude, longitude: Self.taipei.longitude)
        return (session, PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())))
    }

    func testARealMapsLandComesWithTheBaseMapsRoads() throws {
        _ = try Self.tiles.get()
        let (session, taipei) = try taipeiGame()
        XCTAssertEqual(session.world.roads, RoadGrid(), "a new real-world map has roads, none yet")
        let started = Date()
        session.readLand(within: WholeTaiwan.landReach, of: taipei)
        let seconds = Date().timeIntervalSince(started)
        let roads = try XCTUnwrap(session.world.roads)
        let blocks = try XCTUnwrap(session.world.landBlocks)
        XCTAssertEqual(roads.readBlocks, Set(blocks), "every block read has its roads read")
        XCTAssertTrue(roads.towns.isEmpty)
        let cells = blocks.count * Land.blockCells * Land.blockCells
        let highwayStart = Date()
        let highways = session.highwayCells()
        let highwaySeconds = Date().timeIntervalSince(highwayStart)
        print("RealRoadCells: \(blocks.count) blocks round Taipei Station (\(cells) cells): \(roads.cells.count) road cells, "
              + "\(highways.count) highway cells (\(highways.subtracting(roads.cells).count) with no other road); "
              + "land and roads \(String(format: "%.2f", seconds)) s, highways \(String(format: "%.2f", highwaySeconds)) s")
        // The city's grid of streets: most cells have one.
        XCTAssertGreaterThan(roads.cells.count, cells / 2)
        XCTAssertLessThan(roads.cells.count, cells)
        // The Civic Boulevard expressway and the freeway's links north of
        // the station.
        XCTAssertFalse(highways.isEmpty)
        // Taipei Station's own cell is the station building, with no road
        // across it; the next cell north has one.
        let row = Int(taipei.y / Land.cellLength), column = Int(taipei.x / Land.cellLength)
        XCTAssertFalse(roads.hasRoad(row: row, column: column))
        XCTAssertTrue(roads.hasRoad(row: row - 1, column: column))

        // Read once: again, nothing changes and nothing is logged.
        let entries = session.commandLog.entries.count
        session.readLand(within: WholeTaiwan.landReach, of: taipei)
        XCTAssertEqual(session.world.roads, roads)
        XCTAssertEqual(session.commandLog.entries.count, entries)
        XCTAssertEqual(session.highwayCells(), highways)
    }

    func testRoadsComeLaterWhenTheBaseMapArrivesAfterTheLand() throws {
        _ = try Self.tiles.get()
        let (session, taipei) = try taipeiGame()
        let baseMap = session.baseMap
        session.baseMap = nil
        session.readLand(within: WholeTaiwan.landReach, of: taipei)
        XCTAssertFalse(try XCTUnwrap(session.world.landBlocks).isEmpty)
        XCTAssertEqual(session.world.roads, RoadGrid(), "no base map, no roads")
        XCTAssertEqual(session.highwayCells(), [])
        session.baseMap = baseMap
        session.readLandRoundStations()
        XCTAssertEqual(session.world.roads?.readBlocks, Set(try XCTUnwrap(session.world.landBlocks)))
        XCTAssertFalse(try XCTUnwrap(session.world.roads).cells.isEmpty)
        XCTAssertEqual(session.commandLog.entries.last?.action, .readLandRoundStations(RealWorldDataSet(
            population: true, places: true, water: true, heights: true, coverage: true, baseMap: true
        )))
    }

    /// An old save, its land read before the game had roads, continued
    /// while the app reads its data: when the data arrives, the roads of
    /// all that land are read off the main actor, with the data
    /// (``GameLauncher/loadRealWorldData(reading:)``), and handed to the
    /// game on it as ``GameSession/readLandRoundStations()`` would read
    /// them there, logged the same.
    func testAnOldSavesRoadsAreReadOffTheMainThreadWhenTheDataArrives() async throws {
        let tiles = try Self.tiles.get()
        let (reading, taipei) = try taipeiGame()
        reading.baseMap = nil
        reading.readLand(within: WholeTaiwan.landReach, of: taipei)
        let land = Set(try XCTUnwrap(reading.world.landBlocks))
        XCTAssertGreaterThan(land.count, 10)
        // What the main thread would read: the same roads.
        var expected = reading.world
        GameSession.readRoads(in: &expected, baseMap: tiles)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.importSave(try SaveLibrary.encode(reading.world, at: Date()))
        let session = try XCTUnwrap(launcher.session)
        XCTAssertEqual(session.world.roads, RoadGrid(), "an old save: its land read, its roads not")

        var arriving = RealWorldData(
            population: reading.population, places: reading.places, water: reading.water, heights: reading.heights, coverage: reading.coverage,
            railways: nil, issues: []
        )
        arriving.baseMap = tiles
        let data = arriving
        let before = RealRoadCells.readsOnTheMainThread.value
        await launcher.loadRealWorldData { data }.value
        XCTAssertTrue(launcher.session === session, "the same game goes on")
        XCTAssertEqual(session.world.roads?.readBlocks, land, "the roads of all its land read")
        XCTAssertEqual(session.world.roads, expected.roads, "the roads the main thread would have read")
        XCTAssertEqual(RealRoadCells.readsOnTheMainThread.value, before, "none read on the main thread")
        XCTAssertEqual(session.commandLog.entries.last?.action, .readLandRoundStations(RealWorldDataSet(
            population: true, places: true, water: true, heights: true, coverage: true, baseMap: true
        )))
    }

    /// A station on the real map: its panel's road section (decision 400
    /// B.3) is there, and the replay of the log reads the same roads.
    func testARealMapsStationHasRoadsAndItsLogReplays() throws {
        _ = try Self.tiles.get()
        let (session, taipei) = try taipeiGame()
        session.readLandRoundStations()
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: taipei.x - 15_000, y: taipei.y), reach: 2_000)
        session.tapNetwork(at: PlanPoint(x: taipei.x + 15_000, y: taipei.y), reach: 2_000)
        session.buildNetworkTrack()
        session.setNetworkMode(.platform)
        session.tapNetwork(at: taipei, reach: 2_000)
        session.addNetworkPlatform()
        let station = try XCTUnwrap(session.world.stations.first, "\(String(describing: session.message))")
        // The roads are on, and pass a cell north of Taipei Station: its
        // panel offers the station road.
        let offer = try XCTUnwrap(session.world.stationRoadOffer(of: station.id, in: .english))
        XCTAssertTrue(offer.canBuild)
        XCTAssertEqual(offer.quote?.metres, 64)
        XCTAssertEqual(offer.quote?.price, Money(320_000))
        XCTAssertNotNil(session.perform(.buildStationRoad(station.id)) { _, _, _ in "" })
        XCTAssertNil(session.world.stationRoadOffer(of: station.id, in: .english), "\(String(describing: session.message))")
        XCTAssertFalse(try XCTUnwrap(session.world.roads).cells.isEmpty)

        let report = try JSONDecoder().decode(CommandLogReport.self, from: session.commandLogReport(
            version: "0.5.0", build: "56.1", data: [:]
        ).encoded())
        XCTAssertTrue(report.startData.baseMap || report.entries.contains {
            if case .readLandRoundStations(let data) = $0.action { return data.baseMap }
            return false
        })
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world.roads, session.world.roads)
        XCTAssertEqual(replay.session.world, session.world)
    }

    // MARK: - The log

    func testALogFromBeforeTheBaseMapReadsWithoutIt() throws {
        let old = Data(#"{"population":true,"places":true,"water":false,"heights":true,"coverage":false}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RealWorldDataSet.self, from: old), RealWorldDataSet(population: true, places: true, heights: true))
        let new = RealWorldDataSet(population: true, baseMap: true)
        XCTAssertEqual(try JSONDecoder().decode(RealWorldDataSet.self, from: JSONEncoder().encode(new)), new)
    }

    /// A blank map's roads stay its towns', and a real-world map with all
    /// its land from the start (one outside Taiwan) has none.
    func testOnlyARealMapReadAsItIsNeededHasTheBaseMapsRoads() {
        XCTAssertFalse(GameWorld.newGame().roads?.towns.isEmpty ?? true)
        XCTAssertNil(GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 35.68, longitudeDegrees: 139.77)!).roads)
        XCTAssertEqual(GameWorld.newWholeTaiwanGame().roads, RoadGrid())
    }
}
