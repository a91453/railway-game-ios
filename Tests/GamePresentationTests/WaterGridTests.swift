import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Taiwan's water on real-world maps (ARCHITECTURE decision 105): the
/// bundled grid, the cells it makes of a map or of its blocks, and the
/// land laid out off it.
final class WaterGridTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/RealWorld")

    private static let water: WaterGrid = {
        do {
            return try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("taiwan_water.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static func population() throws -> PopulationGrid {
        try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("taiwan_population.json")))
    }

    private static func places() throws -> PlaceGrid {
        try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("taiwan_places.json")))
    }

    private static func frame(_ latitude: Double, _ longitude: Double) throws -> RealWorldFrame {
        RealWorldFrame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)), bounds: GameWorld.newGameBounds)
    }

    // MARK: - The grid

    func testTheBundledGridKnowsTheSeaRiversAndLakes() {
        let water = Self.water
        // 1.875″ cells over Taiwan, Penghu, Kinmen and Matsu and 0.1° round.
        XCTAssertEqual(water.cellDegrees * 3_600, 1.875, accuracy: 1e-6)
        XCTAssertEqual(water.rows, 9_296)
        XCTAssertEqual(water.columns, 8_064)
        let wet = [
            ("Taiwan Strait", 24.0, 119.9), ("Pacific", 23.5, 121.8), ("Keelung harbour", 25.1380, 121.7460),
            ("Tamsui River at Dadaocheng", 25.0585, 121.5055), ("Sun Moon Lake", 23.8650, 120.9150),
            ("Kaohsiung harbour", 22.6110, 120.2900), ("between Kinmen and Xiamen", 24.4500, 118.2000),
        ]
        for (name, latitude, longitude) in wet {
            XCTAssertTrue(water.isWater(latitude: latitude, longitude: longitude), name)
        }
        let dry = [
            ("Taipei Main Station", 25.0479, 121.5170), ("Yushan", 23.4700, 120.9573), ("Magong", 23.5655, 119.5793),
            ("Kinmen", 24.4321, 118.3171), ("Nangan, Matsu", 26.1550, 119.9450), ("Green Island", 22.6617, 121.4900),
            // Outside the grid there is no water: a map elsewhere is as it was.
            ("Tokyo", 35.6812, 139.7671),
        ]
        for (name, latitude, longitude) in dry {
            XCTAssertFalse(water.isWater(latitude: latitude, longitude: longitude), name)
        }
    }

    func testAFileOutOfShapeIsRefused() {
        func reads(_ water: String, rows: Int = 4, columns: Int = 10) -> Bool {
            let text = #"{"north": 25, "west": 121, "cellDegrees": 0.01, "rows": \#(rows), "columns": \#(columns), "water": \#(water)}"#
            return (try? WaterGrid(data: Data(text.utf8))) != nil
        }
        XCTAssertTrue(reads("[[0, 0, 2, 3, 1], [3, 9, 1]]"))
        XCTAssertTrue(reads("[]"))
        XCTAssertFalse(reads("[[1, 0, 1], [0, 0, 1]]"), "rows out of order")
        XCTAssertFalse(reads("[[4, 0, 1]]"), "a row outside the grid")
        XCTAssertFalse(reads("[[0, 0, 2, 1]]"), "a gap without a run")
        XCTAssertFalse(reads("[[0, 0, 2, 0, 1]]"), "runs touching")
        XCTAssertFalse(reads("[[0, 0, 0]]"), "an empty run")
        XCTAssertFalse(reads("[[0, 8, 3]]"), "past the last column")
        XCTAssertFalse(reads("[[0, -1, 1]]"), "before the first")
        XCTAssertFalse(reads("[]", rows: 0))
        let grid = try? WaterGrid(data: Data(#"{"north": 25, "west": 121, "cellDegrees": 0.01, "rows": 4, "columns": 10, "water": [[0, 0, 2, 3, 1]]}"#.utf8))
        XCTAssertEqual(grid?.water.first, [0..<2, 5..<6])
        XCTAssertEqual(grid.map { grid in (0..<10).filter { grid.isWater(row: 0, column: $0) } }, [0, 1, 5])
    }

    // MARK: - A map's water

    /// Keelung's harbour and the sea north of it: the cells are the water
    /// cells their middles lie in, and the blocks of a map read as it is
    /// needed get exactly the whole map's cells in them, in any order.
    func testAMapsWaterIsTheSameWholeOrByBlocks() throws {
        let frame = try Self.frame(25.1330324, 121.7392299)
        let bounds = GameWorld.newGameBounds
        let cells = Self.water.cells(frame: frame, bounds: bounds)
        XCTAssertEqual(cells.count, 18_806)
        XCTAssertEqual(cells, cells.sorted())
        let length = Double(Land.cellLength)
        for cell in cells.prefix(500) + cells.suffix(500) {
            let middle = frame.coordinate(worldX: (Double(cell.column) + 0.5) * length, worldY: (Double(cell.row) + 0.5) * length)
            XCTAssertTrue(Self.water.isWater(latitude: middle.latitude, longitude: middle.longitude), "\(cell)")
        }
        let blocks: Set<LandBlock> = [LandBlock(row: 0, column: 0), LandBlock(row: 3, column: 7), LandBlock(row: 4, column: 7), LandBlock(row: 15, column: 15)]
        let byBlocks = Self.water.cells(frame: frame, bounds: bounds, in: blocks)
        XCTAssertEqual(byBlocks, cells.filter { blocks.contains(LandBlock(cellRow: $0.row, column: $0.column)) })
        XCTAssertFalse(byBlocks.isEmpty)
        let oneByOne = blocks.sorted().reversed().flatMap { Self.water.cells(frame: frame, bounds: bounds, in: [$0]) }
        XCTAssertEqual(Terrain(water: oneByOne), Terrain(water: byBlocks))
    }

    /// The land of a real-world map is laid out off its water: no cell of
    /// land is water, everyone who lived on it lives on the dry cells of
    /// the same WorldPop cell, and the new game takes both.
    func testTheLandIsLaidOutOffTheWater() throws {
        let population = try Self.population(), places = try Self.places()
        // (map, water cells, land cells without and with water, residents
        // lost where a WorldPop cell's part in the map is all water, jobs
        // of factories and farms gone with their cells.)
        let maps: [(String, Double, Double, Int, Int, Int, Int64, Int64)] = [
            ("Taipei", 25.047882, 121.517219, 4_048, 64_829, 61_017, 0, 1_109),
            ("Keelung", 25.1330324, 121.7392299, 18_806, 35_437, 32_424, 0, 1_537),
            ("Kaohsiung", 22.6395321, 120.3025585, 21_113, 48_310, 43_912, 7, 3_948),
            ("Magong", 23.5655, 119.5793, 47_130, 19_166, 15_631, 0, 173),
        ]
        for (name, latitude, longitude, waterCells, before, after, lost, jobsLost) in maps {
            let frame = try Self.frame(latitude, longitude)
            let wet = Self.water.cells(frame: frame, bounds: GameWorld.newGameBounds)
            let dry = try XCTUnwrap(LandImport.cells(population: population, places: places, frame: frame, bounds: GameWorld.newGameBounds))
            let land = try XCTUnwrap(LandImport.cells(population: population, places: places, water: Self.water, frame: frame, bounds: GameWorld.newGameBounds))
            XCTAssertEqual(wet.count, waterCells, name)
            XCTAssertEqual(dry.count, before, name)
            XCTAssertEqual(land.count, after, name)
            let wetCells = Set(wet)
            XCTAssertFalse(land.contains { wetCells.contains($0.position) }, name)
            XCTAssertEqual(dry.reduce(0) { $0 + $1.residents } - land.reduce(0) { $0 + $1.residents }, lost, name)
            XCTAssertEqual(dry.reduce(0) { $0 + $1.jobs } - land.reduce(0) { $0 + $1.jobs }, jobsLost, name)
            let world = GameWorld.newGame(anchor: frame.anchor, land: land, water: wet)
            XCTAssertEqual(world.terrain.waterCellCount, waterCells, name)
            XCTAssertEqual(world.land.cells, land, name)
        }
    }

    /// A real-world map with no one on it founds a new game's towns, off
    /// the water: here, out in the Taiwan Strait, none at all.
    func testTownsOfAMapWithNoOneAreFoundedOffTheWater() throws {
        let frame = try Self.frame(24.0, 119.9)
        let wet = Self.water.cells(frame: frame, bounds: GameWorld.newGameBounds)
        XCTAssertEqual(wet.count, Land.rows(in: GameWorld.newGameBounds) * Land.columns(in: GameWorld.newGameBounds), "all sea")
        XCTAssertNil(LandImport.cells(population: try Self.population(), water: Self.water, frame: frame, bounds: GameWorld.newGameBounds))
        let world = GameWorld.newGame(anchor: frame.anchor, water: wet)
        XCTAssertTrue(world.land.isEmpty)
    }

    // MARK: - Steep slopes (decision 115)

    /// The same file marks the hillsides of more than 30 %: none on water,
    /// few in the cities, most of Alishan; land stays on them, and a new
    /// game takes them.
    func testTheBundledGridKnowsTheSteepSlopes() throws {
        let population = try Self.population(), places = try Self.places()
        // (map, steep cells, land cells on them.)
        let maps: [(String, Double, Double, Int, Int)] = [
            ("Taipei", 25.047882, 121.517219, 2_959, 2_784),
            ("Keelung", 25.1330324, 121.7392299, 7_628, 3_295),
            ("Kaohsiung", 22.6395321, 120.3025585, 786, 785),
            ("Magong", 23.5655, 119.5793, 20, 6),
            ("Alishan", 23.5106, 120.8048, 51_912, 4_079),
        ]
        for (name, latitude, longitude, steepCells, landOnSteep) in maps {
            let frame = try Self.frame(latitude, longitude)
            let steep = Self.water.steepCells(frame: frame, bounds: GameWorld.newGameBounds)
            let wet = Set(Self.water.cells(frame: frame, bounds: GameWorld.newGameBounds))
            XCTAssertEqual(steep.count, steepCells, name)
            XCTAssertFalse(steep.contains(where: wet.contains), "\(name): no steep water")
            let land = try XCTUnwrap(LandImport.cells(population: population, places: places, water: Self.water, frame: frame, bounds: GameWorld.newGameBounds))
            let slopes = Set(steep)
            XCTAssertEqual(land.filter { slopes.contains($0.position) }.count, landOnSteep, "\(name): land stays on its hillsides")
            let world = GameWorld.newGame(anchor: frame.anchor, land: land, water: Array(wet), steep: steep)
            XCTAssertEqual(world.terrain.steepCellCount, steepCells, name)
        }
        XCTAssertFalse(Self.water.steep.flatMap { $0 }.isEmpty)
        // Taipei Main Station's cell is flat.
        let station = (row: try XCTUnwrap(Self.water.row(latitude: 25.0479)), column: try XCTUnwrap(Self.water.column(longitude: 121.5170)))
        XCTAssertFalse(Self.water.isSteep(row: station.row, column: station.column))
        // A file without them (as before decision 115) has none.
        let old = try WaterGrid(data: Data(#"{"north": 25, "west": 121, "cellDegrees": 0.01, "rows": 2, "columns": 2, "water": []}"#.utf8))
        XCTAssertTrue(old.steep.allSatisfy(\.isEmpty))
    }
}
