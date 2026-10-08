import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Step A of docs/research/WHOLE_TAIWAN_MAP.md: the city map keeps only the
/// cells a layer can draw, and a real-world map's land is laid out a row and
/// a column at a time, not a cell at a time. Neither changes a result: each
/// is checked here against the dense reading it replaces, kept below as it
/// was, on Taipei's real land with served stations.
final class SparseCityLandTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let taipei = (latitude: 25.047882, longitude: 121.517219)

    private static func grids() throws -> (PopulationGrid, PlaceGrid) {
        let population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        let places = try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        return (population, places)
    }

    // MARK: - Land import

    /// Taipei's 16 km map, a map cut by the edge of the grid's people, and
    /// small maps whose edges cut WorldPop cells, with and without places.
    func testLandIsLaidOutAsTheCellByCellWalkLaidItOut() throws {
        let (population, places) = try Self.grids()
        let cases: [(Double, Double, WorldBounds)] = try [
            (Self.taipei.latitude, Self.taipei.longitude, GameWorld.newGameBounds),
            (22.6273, 120.3014, GameWorld.newGameBounds),
            (25.13, 121.74, WorldBounds(width: 131_072, height: 131_072)),
            (24.1477, 120.6736, WorldBounds(width: 200_000, height: 70_000)),
            (35.6812, 139.7671, WorldBounds(width: 131_072, height: 131_072)),
        ]
        for (latitude, longitude, bounds) in cases {
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
            let frame = RealWorldFrame(anchor: anchor, bounds: bounds)
            for withPlaces in [false, true] {
                let grid = withPlaces ? places : nil
                XCTAssertEqual(
                    LandImport.cells(population: population, places: grid, frame: frame, bounds: bounds),
                    Self.denseCells(population: population, places: grid, frame: frame, bounds: bounds),
                    "\(latitude), \(longitude), places \(withPlaces)"
                )
            }
        }
    }

    /// `LandImport.cells` as it was: every 64 m cell of the world, one by one.
    private static func denseCells(population: PopulationGrid, places: PlaceGrid?, frame: RealWorldFrame, bounds: WorldBounds) -> [LandCell]? {
        let grid = population.people
        let length = Double(Land.cellLength)
        // Decision 90: offices, shops, schools and sights, each its own.
        func jobs(_ cell: GridCounts.Cell) -> [Int64] {
            guard let places else { return [0, 0, 0, 0] }
            func count(_ kind: PlaceGrid.Kind) -> Int64 {
                Int64(places.layers[kind]?.counts[cell] ?? 0) * (LandImport.jobsPerPlace[kind] ?? 0)
            }
            return [count(.offices), count(.shops), count(.schools), count(.attractions)]
        }
        var members: [GridCounts.Cell: [(row: Int, column: Int)]] = [:]
        var sourceJobs: [GridCounts.Cell: [Int64]] = [:]
        for row in 0..<Land.rows(in: bounds) {
            for column in 0..<Land.columns(in: bounds) {
                let place = frame.coordinate(worldX: (Double(column) + 0.5) * length, worldY: (Double(row) + 0.5) * length)
                let source = grid.cell(latitude: place.latitude, longitude: place.longitude)
                if members[source] == nil {
                    let work = jobs(source)
                    guard (grid.counts[source] ?? 0) > 0 || work.reduce(0, +) > 0 else { continue }
                    sourceJobs[source] = work
                }
                members[source, default: []].append((row, column))
            }
        }
        guard !members.isEmpty else { return nil }
        let cellArea = length * length / Double(WorldCoordinate.unitsPerMetre * WorldCoordinate.unitsPerMetre)
        let lastRow = Land.rows(in: bounds) - 1, lastColumn = Land.columns(in: bounds) - 1
        var cells: [LandCell] = []
        for (source, inside) in members {
            let people = Int64(grid.counts[source] ?? 0)
            let work = sourceJobs[source] ?? [0, 0, 0, 0]
            // The first kind with the most jobs, if they are at least the
            // people; else homes.
            let most = work.indices.first { work[$0] == work.max()! }!
            let use: LandUse = work[most] >= people ? [.office, .commercial, .civic, .leisure][most] : .residential
            let atEdge = inside.contains { $0.row == 0 || $0.column == 0 || $0.row == lastRow || $0.column == lastColumn }
            let slots = Int64(atEdge ? max(inside.count, Int((grid.area(of: source) / cellArea).rounded())) : inside.count)
            func share(_ total: Int64, _ index: Int) -> Int64 {
                let (base, extra) = total.quotientAndRemainder(dividingBy: slots)
                return min(Land.maximumPerCell, base + (Int64(index) < extra ? 1 : 0))
            }
            for (index, cell) in inside.enumerated() {
                let residents = share(people, index), jobs = share(work.reduce(0, +), index)
                guard residents + jobs > 0 else { continue }
                cells.append(LandCell(row: cell.row, column: cell.column, use: use, residents: residents, jobs: jobs))
            }
        }
        return cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    // MARK: - City map

    /// Taipei's land with its buildings, stations served and not, one
    /// closed, and one in the open country: every city layer, at every block
    /// size, over the whole map and over parts of it, is drawn as the dense
    /// map drew it.
    func testTheCityMapDrawsWhatTheDenseMapDrew() throws {
        let (population, places) = try Self.grids()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: Self.taipei.latitude, longitudeDegrees: Self.taipei.longitude))
        let cells = try XCTUnwrap(LandImport.cells(
            population: population, places: places, frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds
        ))
        var world = GameWorld.newGame(anchor: anchor, land: cells)
        let points = [(524_288, 524_288), (480_000, 530_000), (600_000, 500_000), (60_000, 990_000), (1_040_000, 20_000)]
        for (index, point) in points.enumerated() {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: Int64(point.0), y: Int64(point.1)))
        }
        // The measures a midnight would have left: some served, one not.
        for index in world.townGrowth!.places.indices {
            world.townGrowth!.places[index].lastService = [900, 300, 0, 650, 1_000][index % 5]
            world.townGrowth!.places[index].lastReached = [3, 1, 0, 2, 5][index % 5]
        }
        try world.setStationOperationMode(StationID(rawValue: 2), to: .closed)

        let map = CityMap(world: world)
        let dense = DenseCityMap(world: world)
        XCTAssertLessThan(map.cells.count, map.rows * map.columns)
        let regions = [
            WorldRegion(minX: 0, minY: 0, maxX: 1_048_576, maxY: 1_048_576),
            WorldRegion(minX: 470_000, minY: 470_000, maxX: 580_000, maxY: 560_000),
            WorldRegion(minX: -50_000, minY: 900_000, maxX: 130_000, maxY: 1_100_000),
            WorldRegion(minX: 5_000, minY: 5_000, maxX: 9_000, maxY: 9_000),
        ]
        for mode in [PopTravelMode.landUse, .landValue, .coverage] {
            for region in regions {
                for size in [1, 2, 3, 8, 64, 4_096] {
                    XCTAssertEqual(map.tiles(for: mode, in: region, blockSize: size), dense.tiles(for: mode, in: region, blockSize: size), "\(mode) \(region) \(size)")
                }
            }
        }
    }
}

/// `CityMap` as it was: an entry for every cell of the world.
private struct DenseCityMap {
    let rows: Int
    let columns: Int
    let values: [Int64]
    let kinds: [UInt8]
    let covered: [Bool]
    let peopled: [Bool]

    init(world: GameWorld) {
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        self.rows = rows
        self.columns = columns
        values = world.landValues().map(\.value)
        var kinds = [UInt8](repeating: 0, count: rows * columns)
        var peopled = [Bool](repeating: false, count: rows * columns)
        func useCode(_ use: LandUse) -> Int { (LandUse.allCases.firstIndex(of: use) ?? 0) + 1 }
        for cell in world.land.cells where cell.row < rows && cell.column < columns {
            let index = cell.row * columns + cell.column
            peopled[index] = cell.residents + cell.jobs > 0
            if let building = world.buildings.building(row: cell.row, column: cell.column) {
                let density = building.kind == .existingStock ? 5 : building.density.rawValue
                kinds[index] = UInt8(useCode(building.use) * 8 + density)
            } else {
                kinds[index] = UInt8(useCode(cell.use) * 8)
            }
        }
        var covered = [Bool](repeating: false, count: rows * columns)
        let length = Land.cellLength, radius = Land.catchmentRadius
        for station in world.stations where station.operationMode != .closed {
            let point = station.location
            let firstRow = max(0, Int((point.y - radius) / length) - 1), lastRow = min(rows - 1, Int((point.y + radius) / length) + 1)
            let firstColumn = max(0, Int((point.x - radius) / length) - 1), lastColumn = min(columns - 1, Int((point.x + radius) / length) + 1)
            guard firstRow <= lastRow, firstColumn <= lastColumn else { continue }
            for row in firstRow...lastRow {
                let dy = Int64(row) * length + length / 2 - point.y
                for column in firstColumn...lastColumn {
                    let dx = Int64(column) * length + length / 2 - point.x
                    if dx * dx + dy * dy < radius * radius { covered[row * columns + column] = true }
                }
            }
        }
        self.kinds = kinds
        self.covered = covered
        self.peopled = peopled
    }

    func tiles(for mode: PopTravelMode, in region: WorldRegion, blockSize: Int) -> [TravelDemandMap.Tile] {
        guard mode.isCityLayer, rows > 0, columns > 0 else { return [] }
        let size = max(1, blockSize)
        let length = Double(Land.cellLength)
        let firstRow = max(0, Int((region.minY / length).rounded(.down))), lastRow = min(rows - 1, Int((region.maxY / length).rounded(.down)))
        let firstColumn = max(0, Int((region.minX / length).rounded(.down))), lastColumn = min(columns - 1, Int((region.maxX / length).rounded(.down)))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return [] }
        var tiles: [TravelDemandMap.Tile] = []
        for blockRow in (firstRow / size)...(lastRow / size) {
            for blockColumn in (firstColumn / size)...(lastColumn / size) {
                var uses = [Int](repeating: 0, count: LandUse.allCases.count + 1), densities = 0, drawn = 0, total: Int64 = 0
                var anyCovered = false, anyPeopled = false, anyUncovered = false
                for row in (blockRow * size)..<min(rows, (blockRow + 1) * size) {
                    for column in (blockColumn * size)..<min(columns, (blockColumn + 1) * size) {
                        let index = row * columns + column
                        switch mode {
                        case .landUse:
                            let kind = Int(kinds[index])
                            guard kind > 0 else { continue }
                            uses[kind / 8] += 1
                            densities += max(1, min(4, kind % 8))
                            drawn += 1
                        case .landValue:
                            guard peopled[index] || values[index] > LandValueRules.vacantBase else { continue }
                            total += values[index]
                            drawn += 1
                        default:
                            if covered[index] {
                                anyCovered = true
                                anyPeopled = anyPeopled || peopled[index]
                            } else if peopled[index] {
                                anyUncovered = true
                            }
                        }
                    }
                }
                let color: PopTravel.RGB
                let value: Int64
                switch mode {
                case .landUse:
                    guard drawn > 0, let use = (1...LandUse.allCases.count).max(by: { uses[$0] < uses[$1] || (uses[$0] == uses[$1] && $0 > $1) }) else { continue }
                    let density = (densities + drawn / 2) / drawn
                    color = CityMap.useColor(use: use, density: density)
                    value = Int64(use * 8 + density)
                case .landValue:
                    guard drawn > 0 else { continue }
                    value = total / Int64(drawn)
                    color = CityMap.valueColor(cents: value)
                default:
                    if anyUncovered {
                        color = CityMap.uncoveredColor
                        value = 2
                    } else if anyCovered {
                        color = anyPeopled ? CityMap.coveredColor : CityMap.coveredEmptyColor
                        value = 1
                    } else {
                        continue
                    }
                }
                let minX = Double(blockColumn * size) * length, minY = Double(blockRow * size) * length
                tiles.append(TravelDemandMap.Tile(minX: minX, minY: minY, maxX: minX + Double(size) * length, maxY: minY + Double(size) * length, color: color, value: value))
            }
        }
        return tiles
    }
}
