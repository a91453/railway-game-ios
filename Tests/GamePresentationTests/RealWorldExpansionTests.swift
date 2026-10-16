import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// A real place of Taiwan bought tile by tile (decision 167): the world is
/// the island, the company owns the 16 km tile round where the player
/// pointed, its land is read in whole as the game begins and as each next
/// tile is bought, and the riders each tile asks follow the first tile's
/// people.
///
/// Expected values are worked out from the rules, never taken from a
/// previous run.
@MainActor
final class RealWorldExpansionTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let population: PopulationGrid = {
        do {
            return try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let places: PlaceGrid = {
        do {
            return try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private let tile = Double(MapExpansion.tileLength)

    private func pick(_ latitude: Double, _ longitude: Double) throws -> GeoAnchor {
        try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
    }

    /// The place of the app's list called `id`.
    private func place(_ id: String) throws -> RealWorldPlace {
        try XCTUnwrap(RealWorldPlace.all.first { $0.id == id }, id)
    }

    private func expansion(_ id: String) throws -> RealWorldExpansion {
        try XCTUnwrap(RealWorldExpansion(around: place(id).anchor), id)
    }

    // MARK: - The layout

    /// Wherever in the box of Taiwan the player points, the first tile is
    /// centred on it, the tiles are whole, and the island lies inside the
    /// world.
    func testTheLayoutCentresTheFirstTileOnThePickAndHoldsTheIsland() throws {
        var picks = RealWorldPlace.taiwan.map(\.anchor)
        // The box's corners and edges exactly, and a grid over it.
        for latitude in [WholeTaiwan.south, WholeTaiwan.north] {
            for longitude in [WholeTaiwan.west, WholeTaiwan.east] {
                picks.append(try pick(latitude, longitude))
            }
        }
        for latitude in stride(from: WholeTaiwan.south, through: WholeTaiwan.north, by: 0.35) {
            for longitude in stride(from: WholeTaiwan.west, through: WholeTaiwan.east, by: 0.28) {
                picks.append(try pick(latitude, longitude))
            }
        }
        XCTAssertGreaterThan(picks.count, 100)
        for anchor in picks {
            let name = "\(anchor.latitudeDegrees), \(anchor.longitudeDegrees)"
            let layout = try XCTUnwrap(RealWorldExpansion(around: anchor), name)
            let bounds = layout.bounds
            XCTAssertEqual(bounds.width % MapExpansion.tileLength, 0, name)
            XCTAssertEqual(bounds.height % MapExpansion.tileLength, 0, name)
            let columns = Int(bounds.width / MapExpansion.tileLength), rows = Int(bounds.height / MapExpansion.tileLength)
            XCTAssertTrue((18...20).contains(columns) && (24...26).contains(rows), "\(columns) × \(rows) tiles: \(name)")
            XCTAssertLessThanOrEqual(bounds.width, WorldBounds.maximumSide)
            XCTAssertLessThanOrEqual(bounds.height, WorldBounds.maximumSide)
            XCTAssertTrue((0..<rows).contains(layout.start.row) && (0..<columns).contains(layout.start.column), name)
            // The pick is where the tile's middle is, to the centimetre.
            let frame = layout.frame
            let middle = frame.worldPosition(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees)
            XCTAssertEqual(middle.x, (Double(layout.start.column) + 0.5) * tile, accuracy: 4, name)
            XCTAssertEqual(middle.y, (Double(layout.start.row) + 0.5) * tile, accuracy: 4, name)
            // The island's box is inside the world.
            let northWest = frame.worldPosition(latitude: WholeTaiwan.north, longitude: WholeTaiwan.west)
            let southEast = frame.worldPosition(latitude: WholeTaiwan.south, longitude: WholeTaiwan.east)
            XCTAssertGreaterThanOrEqual(northWest.x, 0, name)
            XCTAssertGreaterThanOrEqual(northWest.y, 0, name)
            XCTAssertLessThanOrEqual(southEast.x, Double(bounds.width), name)
            XCTAssertLessThanOrEqual(southEast.y, Double(bounds.height), name)
            // No more world than the island needs: a tile and a half of sea
            // at most beyond it on any side (the pick's tile may reach out).
            XCTAssertLessThanOrEqual(northWest.x, 1.5 * tile + tile, name)
        }
    }

    /// Two picks in one tile of a layout are in different layouts: the
    /// world follows the pick, so the tile round each is whole.
    func testTheWorldFollowsThePick() throws {
        let taipei = try expansion("tra-taipei"), kaohsiung = try expansion("tra-kaohsiung")
        XCTAssertNotEqual(taipei.anchor, kaohsiung.anchor)
        XCTAssertNotEqual(taipei.anchor, WholeTaiwan.anchor)
        XCTAssertNotEqual(taipei.start, kaohsiung.start)
        // The same pick, the same layout.
        XCTAssertEqual(try expansion("tra-taipei"), taipei)
        // A tile's ground is a new game's 16.384 km at the anchor's scale.
        let frame = taipei.frame
        let start = taipei.start
        let west = frame.coordinate(worldX: Double(start.column) * tile, worldY: (Double(start.row) + 0.5) * tile)
        let east = frame.coordinate(worldX: Double(start.column + 1) * tile, worldY: (Double(start.row) + 0.5) * tile)
        let kilometres = (east.longitude - west.longitude) * .pi / 180 * 6_378.137 * cos(west.latitude * .pi / 180)
        XCTAssertEqual(kilometres, 16.384 * cos(west.latitude * .pi / 180) / cos(taipei.anchor.latitudeDegrees * .pi / 180), accuracy: 0.001)
    }

    func testAPlaceBeyondTheBoxHasNoLayout() throws {
        for (name, latitude, longitude) in [
            ("Kinmen", 24.4321, 118.3171), ("Matsu", 26.1505, 119.9499), ("Shanghai", 31.2304, 121.4737), ("London", 51.5074, -0.1278),
            ("north of the box", 25.3501, 121.5), ("south of the box", 21.8499, 120.8), ("west of the box", 23.5, 119.2499), ("east of the box", 24.0, 122.0501),
        ] {
            XCTAssertNil(RealWorldExpansion(around: try pick(latitude, longitude)), name)
        }
        XCTAssertTrue(WholeTaiwan.contains(latitude: 23.5, longitude: 120.0))
        XCTAssertFalse(WholeTaiwan.contains(latitude: .nan, longitude: 120.0))
    }

    // MARK: - The game

    func testANewGameOwnsOnlyItsFirstTileAndReadsNoLandYet() throws {
        let layout = try expansion("tra-hualien")
        let world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: 12_000, eventSeed: 9)
        XCTAssertEqual(world.bounds, layout.bounds)
        XCTAssertEqual(world.geoAnchor, layout.anchor)
        XCTAssertEqual(world.mapExpansion, MapExpansion(owned: [layout.start], townSeed: nil, ridersStep: 12_000))
        XCTAssertEqual(world.mapTilesForSale().count, 4, "the island is wide enough for the tiles on every side of Hualien")
        XCTAssertEqual(world.landBlocks, [])
        XCTAssertTrue(world.land.isEmpty)
        XCTAssertTrue(world.landDemand && world.cityBuildings, "a new game's city, once its land comes")
        XCTAssertTrue(world.outsideConnections, "the towns beyond stand in for the tiles not bought yet, as on any map but the island")
        XCTAssertTrue(world.distanceDemand, "short trips still walk")
        XCTAssertEqual(world.accounts.mode, .management)
        // Only on the tile owned.
        var built = world
        let outside = PlanPoint(x: Int64((Double(layout.start.column) + 1.5) * tile), y: Int64((Double(layout.start.row) + 0.5) * tile))
        XCTAssertThrowsError(try built.buildStation(named: "Beyond", at: outside)) { error in
            XCTAssertEqual(error as? GameError, .mapTileNotOwned(MapTile(row: layout.start.row, column: layout.start.column + 1)))
        }
        // The save holds the step, and loads.
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, world)
        // No land yet: a few hundred bytes, and the 214 sights of Taiwan (decisions 174 and
        // 249) about 27 KB.
        XCTAssertLessThan(saved.count, 32_000, "no land yet: the sights' few tens of kilobytes at most")
    }

    /// The first tile's land is all there when the game begins: exactly the
    /// cells a whole import would give its blocks.
    func testTheFirstTilesLandIsReadWhenTheGameBegins() throws {
        let layout = try expansion("tra-hualien")
        let session = GameSession(world: .newRealWorldExpansionGame(layout, ridersStep: 10_000), language: .english)
        session.population = Self.population
        session.places = Self.places
        session.readLandRoundStations()
        let world = session.world
        let blocks = layout.start.landBlocks(in: layout.bounds)
        XCTAssertEqual(blocks.count, 256, "16 × 16 blocks of 1,024 m")
        XCTAssertEqual(world.landBlocks, blocks.sorted())
        let expected = LandImport.cells(in: Set(blocks), population: Self.population, places: Self.places, frame: layout.frame, bounds: layout.bounds)
        XCTAssertEqual(world.land.cells, expected)
        XCTAssertEqual(world.buildings.all.count, expected.count)
        let residents = expected.reduce(0) { $0 + $1.residents }
        XCTAssertGreaterThan(residents, 150_000, "Hualien's tile holds some 190,000")
        XCTAssertEqual(world.land.cells.reduce(0) { $0 + $1.residents }, residents)
        // Again: nothing more to read, nothing changes.
        session.readLandRoundStations()
        XCTAssertEqual(session.world, world)
    }

    /// The land of a game that begins before the app has the people is read
    /// when they arrive.
    func testTheLandComesWhenThePeopleDo() throws {
        let layout = try expansion("tra-yilan")
        let session = GameSession(world: .newRealWorldExpansionGame(layout, ridersStep: 10_000), language: .english)
        session.readLandRoundStations()
        XCTAssertEqual(session.world.landBlocks, [])
        session.population = Self.population
        session.places = Self.places
        session.readLandRoundStations()
        XCTAssertEqual(session.world.landBlocks?.count, 256)
        XCTAssertFalse(session.world.land.isEmpty)
    }

    /// Buying a tile reads in its land in the same edit, so Undo takes
    /// both back; the tile's land is exactly what a whole import gives its
    /// blocks.
    func testBuyingATileReadsItsLandAndUndoTakesBothBack() throws {
        let layout = try expansion("tra-hsinchu")
        var world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: 10_000, balance: 5_000_000_000)
        world.setEconomyMode(.free)
        let session = GameSession(world: world, language: .english)
        session.population = Self.population
        session.places = Self.places
        session.readLandRoundStations()
        let first = session.world
        XCTAssertEqual(first.landBlocks?.count, 256)

        let north = MapTile(row: layout.start.row - 1, column: layout.start.column)
        session.startChoosingMapTile()
        let inside = PlanPoint(x: Int64((Double(north.column) + 0.5) * tile), y: Int64((Double(north.row) + 0.5) * tile))
        XCTAssertTrue(session.tapMapExpansion(at: inside))
        XCTAssertTrue(session.buyChosenMapTile())
        let bought = session.world
        XCTAssertEqual(bought.mapExpansion?.owned, [north, layout.start])
        let blocks = north.landBlocks(in: layout.bounds) + layout.start.landBlocks(in: layout.bounds)
        XCTAssertEqual(bought.landBlocks, blocks.sorted())
        let expected = LandImport.cells(in: Set(blocks), population: Self.population, places: Self.places, frame: layout.frame, bounds: layout.bounds)
        XCTAssertEqual(bought.land.cells, expected)
        XCTAssertGreaterThan(bought.land.cells.count, first.land.cells.count, "Zhubei and Zhongli lie in the tile to the north")
        XCTAssertEqual(session.message?.kind, .success)

        session.undo()
        XCTAssertEqual(session.world.mapExpansion?.owned, [layout.start])
        XCTAssertEqual(session.world.landBlocks, first.landBlocks)
        XCTAssertEqual(session.world.land.cells, first.land.cells)
    }

    /// A station built near the edge of the tile owned reads in the blocks
    /// of the tile next to it that are within 2 km, and a tile bought later
    /// reads only the blocks that are left.
    func testAStationAtTheEdgeReadsPartOfTheNextTileAndThePurchaseTheRest() throws {
        let layout = try expansion("tra-hualien")
        var world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: 10_000, balance: 5_000_000_000)
        world.setEconomyMode(.free)
        let session = GameSession(world: world, language: .english)
        session.population = Self.population
        session.places = Self.places
        let edge = PlanPoint(x: Int64((Double(layout.start.column) + 1) * tile) - 64_000, y: Int64((Double(layout.start.row) + 0.5) * tile))
        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "Edge", at: edge) }
        let east = MapTile(row: layout.start.row, column: layout.start.column + 1)
        let eastBlocks = Set(east.landBlocks(in: layout.bounds))
        let reached = Set(session.world.landBlocks ?? []).intersection(eastBlocks)
        XCTAssertFalse(reached.isEmpty, "the station's 2 km reach crosses the edge")
        XCTAssertLessThan(reached.count, 256)
        session.startChoosingMapTile()
        XCTAssertTrue(session.tapMapExpansion(at: PlanPoint(x: Int64((Double(east.column) + 0.5) * tile), y: edge.y)))
        XCTAssertTrue(session.buyChosenMapTile())
        XCTAssertEqual(Set(session.world.landBlocks ?? []), Set(layout.start.landBlocks(in: layout.bounds)).union(eastBlocks))
    }

    /// The edge of the world cuts the last tiles: only the blocks inside it.
    func testATileCutByTheWorldsEdgeHasOnlyTheBlocksInsideIt() throws {
        let bounds = try WorldBounds(width: MapExpansion.tileLength + 3 * Land.blockLength + 5, height: MapExpansion.tileLength)
        XCTAssertEqual(MapTile(row: 0, column: 0).landBlocks(in: bounds).count, 256)
        XCTAssertEqual(MapTile(row: 0, column: 1).landBlocks(in: bounds).count, 16 * 4, "three blocks and a few units, so four")
        XCTAssertEqual(MapTile(row: 0, column: 2).landBlocks(in: bounds), [])
        XCTAssertEqual(MapTile(row: -1, column: 0).landBlocks(in: bounds), [])
        XCTAssertEqual(MapTile(row: 0, column: -1).landBlocks(in: bounds), [])
    }

    // MARK: - The milestone follows the people

    func testTheStepFollowsTheRootOfTheFirstTilesTrips() {
        // 40 trips for every 100 residents, 100 riders for every whole
        // number of their square root, to 1,000.
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 0), 5_000, "at least")
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: -5), 5_000)
        // 16,000 trips, root 126: 12,600.
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 40_000), 12_000)
        // 45,509 trips, root 213: 21,300.
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 113_774), 21_000)
        // 400,000 trips, root 632: 63,200.
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 1_000_000), 63_000)
        // 1,000,000 trips, root 1,000: exactly the standard.
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 2_500_000), 100_000)
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 4_777_604), 100_000, "no more than the standard")
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: .max), 100_000)
        // The least: 400 trips, root 20: 2,000, raised.
        XCTAssertEqual(RealWorldExpansion.ridersStep(forResidents: 1_000), 5_000)
    }

    /// Taitung's tile could never carry the standard 100,000 riders a
    /// day; Taipei's asks it.
    func testACountryTilesStepIsLessAndACitysIsTheStandard() throws {
        let taitung = try expansion("tra-taitung"), taipei = try expansion("tra-taipei")
        let country = taitung.ridersStep(population: Self.population, places: Self.places, water: nil)
        XCTAssertTrue((19_000...23_000).contains(country), "Taitung's tile: \(country)")
        XCTAssertEqual(taipei.ridersStep(population: Self.population, places: Self.places, water: nil), MapExpansion.standardRidersStep)
    }

    // MARK: - The launcher

    func testTheLauncherStartsAPlaceOfTaiwanAsAMapBoughtTileByTile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Expansion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let hualien = try place("tra-hualien").anchor
        // Without the people there is no land to buy: the 16 km square.
        launcher.startNewGame(at: hualien)
        var world = try XCTUnwrap(launcher.session?.world)
        XCTAssertNil(world.mapExpansion)
        XCTAssertEqual(world.bounds, GameWorld.newGameBounds)

        launcher.population = Self.population
        launcher.places = Self.places
        launcher.startNewGame(at: hualien)
        world = try XCTUnwrap(launcher.session?.world)
        let layout = try expansion("tra-hualien")
        XCTAssertEqual(world.bounds, layout.bounds)
        XCTAssertEqual(world.geoAnchor, layout.anchor)
        XCTAssertEqual(world.mapExpansion?.owned, [layout.start])
        XCTAssertEqual(world.mapExpansion?.ridersStep, layout.ridersStep(population: Self.population, places: Self.places, water: nil))
        XCTAssertLessThan(try XCTUnwrap(world.mapExpansion?.ridersStep), MapExpansion.standardRidersStep)
        XCTAssertEqual(world.landBlocks?.count, 256, "the first tile's land is read as the game begins")
        XCTAssertFalse(world.land.isEmpty)
        XCTAssertEqual(launcher.session?.mapExpansionText?.hasPrefix("Map: 1 of "), true)

        // A place beyond Taiwan is a 16 km square, as before.
        launcher.startNewGame(at: try place("shanghai").anchor)
        world = try XCTUnwrap(launcher.session?.world)
        XCTAssertNil(world.mapExpansion)
        XCTAssertEqual(world.bounds, GameWorld.newGameBounds)
        XCTAssertEqual(world.geoAnchor, try place("shanghai").anchor)
    }

    /// The map opens on the land owned until something is built; the whole
    /// of Taiwan and a blank map open as they did.
    func testTheMapOpensOnTheLandOwned() throws {
        let layout = try expansion("tra-chiayi")
        let world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: 10_000)
        let region = try XCTUnwrap(WorldRegion.opening(in: world))
        XCTAssertEqual(region, WorldRegion.owned(in: world))
        XCTAssertEqual(region.width, tile, accuracy: 1)
        XCTAssertEqual(region.height, tile, accuracy: 1)
        XCTAssertEqual(WorldRegion.opening(in: .newWholeTaiwanGame()), WorldRegion(bounds: WholeTaiwan.bounds))
        XCTAssertNil(WorldRegion.opening(in: .newGame(buysMap: true)), "a blank map opens as its camera does")
    }

    /// A game on the first tile runs: a line between two of its towns
    /// carries riders on the land read in, and the save of it loads.
    func testALineOnTheFirstTileCarriesRidersAndSaves() throws {
        let layout = try expansion("tra-yilan")
        var world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: 10_000)
        GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
        // The two cells of the most people, a few km apart.
        let frame = layout.frame
        let cells = world.land.cells.sorted { $0.residents > $1.residents }
        let first = try XCTUnwrap(cells.first)
        func point(_ cell: LandCell) -> PlanPoint {
            PlanPoint(x: Int64(cell.column) * Land.cellLength + Land.cellLength / 2, y: Int64(cell.row) * Land.cellLength + Land.cellLength / 2)
        }
        let a = point(first)
        let b = try XCTUnwrap(cells.map(point).first { hypot(Double($0.x - a.x), Double($0.y - a.y)) > 4_000 * 64 && world.ownsGround(at: $0) })
        XCTAssertNotNil(RealWorldFrame(world: world))
        XCTAssertEqual(frame, RealWorldFrame(world: world))
        world = try newGameLine(through: [a, b], in: world)
        world.setSpeed(.normal)
        try world.advance(ticks: 2 * 1_440)
        XCTAssertGreaterThan(world.lastDayTrips(), 0, "the first tile's people ride")
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, world)
    }
}
