import Foundation
import GameCore

// Taiwan's water on a real-world map (ARCHITECTURE decision 105): the sea
// off its coast, its rivers and its lakes, which GameCore keeps as a layer
// of terrain (`GameWorld.terrain`) where the city does not spread and the
// player neither places a building nor zones.
//
// OpenStreetMap's coastline and water areas (ODbL 1.0) mapped on a fine cut
// of WorldPop's grid (1.875″, some 58 × 53 m, about one of the game's 64 m
// cells) and bundled as `Resources/RealWorld/taiwan_water.json` by
// `tools/real-world-population/build_water_grid.py`. Like the population,
// only the presentation reads it: a new game's water goes to GameCore
// through `GameWorld.setWater(_:)`, a whole-island map's with each block of
// land (`GameWorld.expandLand(_:cells:water:)`), and the world saves the
// cells, so a save does not depend on the file.

/// Which cells of a grid over Taiwan are water.
public struct WaterGrid: Sendable {
    let north: Double
    let west: Double
    let cellDegrees: Double
    let rows: Int
    let columns: Int
    /// Each row's runs of water, as columns, in order and apart; empty for
    /// a row with none.
    let water: [[Range<Int>]]

    /// Reads the app's water file: the grid's north-west corner, cell size
    /// in degrees, rows and columns, and each row with water once, in
    /// order, as `[row, column, count, gap, count, …]`. Throws for a file
    /// out of shape, a row out of order or outside the grid, or a run
    /// empty or past its last column.
    public init(data: Data) throws {
        struct File: Decodable {
            let north: Double
            let west: Double
            let cellDegrees: Double
            let rows: Int
            let columns: Int
            let water: [[Int]]
        }
        func corrupt(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: why))
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.cellDegrees > 0, file.north.isFinite, file.west.isFinite, (1...1 << 20).contains(file.rows), (1...1 << 20).contains(file.columns) else {
            throw corrupt("The water grid needs a corner, a positive cell size and its rows and columns.")
        }
        var water = Array(repeating: [Range<Int>](), count: file.rows)
        var lastRow = -1
        for numbers in file.water {
            guard numbers.count >= 3, numbers.count % 2 == 1, let row = numbers.first, row > lastRow, row < file.rows else {
                throw corrupt("Rows of water are [row, column, count, gap, count, …], in order, in the grid.")
            }
            lastRow = row
            var runs: [Range<Int>] = []
            var column = numbers[1]
            guard column >= 0 else { throw corrupt("A run of water starts before the grid.") }
            for index in stride(from: 2, to: numbers.count, by: 2) {
                let count = numbers[index]
                if index > 2 {
                    let gap = numbers[index - 1]
                    guard gap > 0 else { throw corrupt("Runs of water are apart.") }
                    column += gap
                }
                guard count > 0, count <= file.columns - column else { throw corrupt("A run of water is empty or past the grid.") }
                runs.append(column..<column + count)
                column += count
            }
            water[row] = runs
        }
        north = file.north
        west = file.west
        cellDegrees = file.cellDegrees
        rows = file.rows
        columns = file.columns
        self.water = water
    }

    /// The row of the grid holding `latitude`, or `nil` outside it.
    func row(latitude: Double) -> Int? {
        let index = ((north - latitude) / cellDegrees).rounded(.down)
        guard index.isFinite, index >= 0, index < Double(rows) else { return nil }
        return Int(index)
    }

    /// The column of the grid holding `longitude`, or `nil` outside it.
    func column(longitude: Double) -> Int? {
        let index = ((longitude - west) / cellDegrees).rounded(.down)
        guard index.isFinite, index >= 0, index < Double(columns) else { return nil }
        return Int(index)
    }

    /// Whether the cell at `row`, `column` of the grid is water.
    func isWater(row: Int, column: Int) -> Bool {
        let runs = water[row]
        var low = 0, high = runs.count
        while low < high {
            let middle = (low + high) / 2
            if runs[middle].upperBound <= column {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < runs.count && runs[low].contains(column)
    }

    /// Whether `latitude`° north, `longitude`° east is water: `false`
    /// outside the grid, which covers Taiwan's land and some 11 km round it.
    public func isWater(latitude: Double, longitude: Double) -> Bool {
        guard let row = row(latitude: latitude), let column = column(longitude: longitude) else { return false }
        return isWater(row: row, column: column)
    }

    /// The grid's row for each 64 m row of a world of `bounds` laid over
    /// the Earth by `frame`, and its column for each 64 m column: the cell
    /// a 64 m cell's middle lies in (Web Mercator puts it in a row by its y
    /// alone and in a column by its x alone, as ``LandImport`` finds
    /// WorldPop's cells).
    func lookup(frame: RealWorldFrame, bounds: WorldBounds) -> (rows: [Int?], columns: [Int?]) {
        let length = Double(Land.cellLength)
        let rows = (0..<Land.rows(in: bounds)).map { row in
            self.row(latitude: frame.coordinate(worldX: 0.5 * length, worldY: (Double(row) + 0.5) * length).latitude)
        }
        let columns = (0..<Land.columns(in: bounds)).map { column in
            self.column(longitude: frame.coordinate(worldX: (Double(column) + 0.5) * length, worldY: 0.5 * length).longitude)
        }
        return (rows, columns)
    }

    /// The 64 m cells of water of a world of `bounds` laid over the Earth
    /// by `frame` (each takes the water cell its middle lies in), or with
    /// `blocks` only those in the blocks: exactly the whole world's cells
    /// that lie in them, so the water does not depend on which blocks are
    /// read first. By row and then column.
    public func cells(frame: RealWorldFrame, bounds: WorldBounds, in blocks: Set<LandBlock>? = nil) -> [CellPosition] {
        let lookup = lookup(frame: frame, bounds: bounds)
        var cells: [CellPosition] = []
        func add(row: Int, columns: Range<Int>) {
            guard let source = lookup.rows[row], !water[source].isEmpty else { return }
            for column in columns {
                if let target = lookup.columns[column], isWater(row: source, column: target) {
                    cells.append(CellPosition(row: row, column: column))
                }
            }
        }
        guard let blocks else {
            for row in lookup.rows.indices {
                add(row: row, columns: lookup.columns.indices)
            }
            return cells
        }
        let rows = lookup.rows.count, columns = lookup.columns.count
        for block in blocks.sorted() {
            let firstRow = block.row * Land.blockCells, firstColumn = block.column * Land.blockCells
            for row in firstRow..<min(rows, firstRow + Land.blockCells) {
                add(row: row, columns: firstColumn..<min(columns, firstColumn + Land.blockCells))
            }
        }
        return cells.sorted()
    }
}
