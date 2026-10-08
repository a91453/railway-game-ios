import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The whole of Taiwan (decision 88): one map of the main island and
/// Penghu, whose land is read in round each station as it is built.
@MainActor
final class WholeTaiwanTests: XCTestCase {
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

    private let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)

    private func point(_ latitude: Double, _ longitude: Double) -> PlanPoint {
        let position = frame.worldPosition(latitude: latitude, longitude: longitude)
        return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
    }

    // MARK: - The map

    /// The map holds the main island and Penghu, about 285 by 390 km, and
    /// leaves out Kinmen and Matsu; it fits in the largest world.
    func testTheMapHoldsTheMainIslandAndPenghuButNotKinmenOrMatsu() throws {
        let bounds = WholeTaiwan.bounds
        XCTAssertEqual(Double(bounds.width / WorldCoordinate.unitsPerMetre), 285_500, accuracy: 1_500)
        XCTAssertEqual(Double(bounds.height / WorldCoordinate.unitsPerMetre), 389_500, accuracy: 1_500)
        XCTAssertLessThan(bounds.height, WorldBounds.maximumSide)
        XCTAssertEqual(WholeTaiwan.anchor.longitudeDegrees, 120.65, accuracy: 1e-7)
        XCTAssertEqual(WholeTaiwan.anchor.latitudeDegrees, 23.61, accuracy: 0.01)
        let inside = [
            ("Keelung", 25.1330324, 121.7392299), ("Taipei", 25.0479308, 121.5170046), ("Fugui Cape", 25.2985, 121.5363),
            ("Kaohsiung", 22.6395321, 120.3025585), ("Eluanbi", 21.9022, 120.8527), ("Hualien", 23.9926399, 121.6009524),
            ("Sandiao Cape", 25.0089, 122.0006), ("Magong", 23.5655, 119.5793), ("Huayu", 23.4126, 119.3183),
            ("Orchid Island", 22.0447, 121.5486), ("Green Island", 22.6617, 121.4900),
        ]
        for (name, latitude, longitude) in inside {
            XCTAssertTrue(bounds.contains(point(latitude, longitude)), name)
        }
        for (name, latitude, longitude) in [("Kinmen", 24.4321, 118.3171), ("Matsu", 26.1505, 119.9499)] {
            XCTAssertFalse(bounds.contains(point(latitude, longitude)), name)
        }
    }

    func testANewGameOnTheWholeOfTaiwanStartsWithNoLandRead() throws {
        let world = GameWorld.newWholeTaiwanGame(eventSeed: 9)
        XCTAssertEqual(world.bounds, WholeTaiwan.bounds)
        XCTAssertEqual(world.geoAnchor, WholeTaiwan.anchor)
        XCTAssertEqual(world.landBlocks, [])
        XCTAssertTrue(world.land.isEmpty)
        XCTAssertTrue(world.landDemand && world.cityBuildings, "a new game's city, once its land comes")
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, world)
        XCTAssertLessThan(saved.count, 2_000, "no land yet: a few hundred bytes")
    }

    // MARK: - Reading the land in

    /// Building a station reads in the land within 2 km of it: exactly the
    /// cells a whole import would give those blocks, so Taipei Main
    /// Station has about the people the grid counts round it; Undo takes
    /// both back, and a station near by reads only the blocks not read.
    func testBuildingAStationReadsInTheLandRoundIt() throws {
        let session = GameSession(world: .newWholeTaiwanGame(), language: .english)
        session.population = Self.population
        session.places = Self.places
        let taipei = point(25.0479308, 121.5170046)
        let station = try session.performEdit { world throws(GameError) in try world.buildStation(named: "Taipei", at: taipei).id }
        let world = session.world
        let blocks = Land.blocks(within: WholeTaiwan.landReach, of: taipei, in: world.bounds)
        XCTAssertEqual(world.landBlocks, blocks)
        XCTAssertEqual(blocks.count, 21, "the blocks of 1,024 m some part of which is within 2 km")
        let expected = LandImport.cells(in: Set(blocks), population: Self.population, places: Self.places, frame: frame, bounds: world.bounds)
        XCTAssertEqual(world.land.cells, expected)
        XCTAssertEqual(world.buildings.all.count, expected.count)
        let catchment = try XCTUnwrap(world.landCatchment(of: station)).residents
        let sampled = Int64(try XCTUnwrap(Self.population.people(within: 800, ofLatitude: 25.0479308, longitude: 121.5170046)))
        XCTAssertEqual(Double(catchment), Double(sampled), accuracy: Double(sampled) * 0.1, "\(catchment) against \(sampled)")
        XCTAssertNotNil(world.stationDemand(of: station))

        session.undo()
        XCTAssertNil(session.world.station(id: station))
        XCTAssertEqual(session.world.landBlocks, [])
        XCTAssertTrue(session.world.land.isEmpty)

        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "Taipei", at: taipei) }
        let east = PlanPoint(x: taipei.x + 100_000, y: taipei.y)
        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "East", at: east) }
        let both = Set(blocks + Land.blocks(within: WholeTaiwan.landReach, of: east, in: world.bounds))
        XCTAssertEqual(session.world.landBlocks, both.sorted())
        XCTAssertEqual(
            session.world.land.cells.count,
            LandImport.cells(in: both, population: Self.population, places: Self.places, frame: frame, bounds: world.bounds).count
        )
    }

    /// Each edit that reads land in keeps a copy of the land for Undo, so
    /// only the last three such edits can be taken back; edits that read
    /// none in between still can.
    func testUndoKeepsOnlyTheLastThreeEditsThatReadLand() throws {
        let session = GameSession(world: .newWholeTaiwanGame(), language: .english)
        session.population = Self.population
        let towns = [(25.0479308, 121.5170046), (24.1370662, 120.6868667), (22.6395321, 120.3025585), (23.9926399, 121.6009524), (24.8014026, 120.971678)]
        var ids: [StationID] = []
        for (number, town) in towns.enumerated() {
            ids.append(try session.performEdit { world throws(GameError) in try world.buildStation(named: "T\(number)", at: point(town.0, town.1)).id })
        }
        XCTAssertEqual(session.undoCount, 3)
        try session.performEdit { world throws(GameError) in try world.renameStation(ids[4], to: "Hsinchu") }
        XCTAssertEqual(session.undoCount, 4, "renaming reads no land")
        for _ in 0..<4 {
            session.undo()
        }
        XCTAssertEqual(session.world.stations.map(\.id), Array(ids.prefix(2)), "back to before the third land-reading edit")
        XCTAssertEqual(session.world.landBlocks?.isEmpty, false)
        XCTAssertFalse(session.canUndo)

        // A 16 km map keeps all 25.
        let blank = GameSession(world: .newGame(), language: .english)
        for number in 0..<5 {
            try blank.performEdit { world throws(GameError) in _ = try world.buildStation(named: "B\(number)", at: PlanPoint(x: 100_000 + Int64(number) * 100_000, y: 524_288)) }
        }
        XCTAssertEqual(blank.undoCount, 5)
    }

    /// Without the app's population a station reads nothing; once there is
    /// one, the game reads in what its stations missed.
    func testAStationBuiltWithoutThePopulationGetsItsLandLater() throws {
        let session = GameSession(world: .newWholeTaiwanGame(), language: .english)
        let kaohsiung = point(22.6395321, 120.3025585)
        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "Kaohsiung", at: kaohsiung) }
        XCTAssertEqual(session.world.landBlocks, [])
        session.population = Self.population
        session.readLandRoundStations()
        XCTAssertEqual(session.world.landBlocks, Land.blocks(within: WholeTaiwan.landReach, of: kaohsiung, in: session.world.bounds))
        XCTAssertFalse(session.world.land.isEmpty)
    }

    /// A 16 km map's land is whole: building a station reads nothing in.
    func testA16KilometreMapsLandIsWhole() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0479308, longitudeDegrees: 121.5170046))
        let land = LandImport.cells(
            population: Self.population, frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds
        )
        let session = GameSession(world: .newGame(anchor: anchor, land: land), language: .english)
        session.population = Self.population
        let before = session.world.land
        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "Taipei", at: PlanPoint(x: 524_288, y: 524_288)) }
        XCTAssertNil(session.world.landBlocks)
        XCTAssertEqual(session.world.land, before)
    }

    /// An empty whole-Taiwan map opens on the whole island (decision 89);
    /// once something is built, on what is built, as any map does. A blank
    /// new game opens where the camera puts it.
    func testAnEmptyWholeTaiwanMapOpensOnTheWholeIsland() throws {
        var world = GameWorld.newWholeTaiwanGame()
        XCTAssertEqual(WorldRegion.opening(in: world), WorldRegion(bounds: world.bounds))
        let phone = ScreenSize(width: 390, height: 700)
        let camera = PlanCamera(bounds: world.bounds, viewport: phone, showing: WorldRegion.opening(in: world))
        XCTAssertEqual(camera.visibleRegion.width, Double(world.bounds.width), accuracy: Double(world.bounds.width) * 0.01, "the island across the phone")
        XCTAssertEqual(MapScale.detail(forReferenceSize: camera.referenceSize), .overview)
        let taipei = point(25.0479308, 121.5170046)
        _ = try world.buildStation(named: "Taipei", at: taipei)
        XCTAssertEqual(WorldRegion.opening(in: world), WorldRegion.built(in: world))
        XCTAssertNil(WorldRegion.opening(in: .newGame()))
    }

    func testTheLauncherStartsTheWholeOfTaiwan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WholeTaiwanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.population = Self.population
        launcher.startWholeTaiwan()
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.bounds, WholeTaiwan.bounds)
        XCTAssertEqual(world.landBlocks, [])
    }
}
