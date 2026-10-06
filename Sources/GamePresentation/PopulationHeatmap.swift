import Foundation
import GameCore

/// The population grid laid out on a real-world map, for drawing and for
/// the tooltip of a tapped cell: made once for a grid and a map, then asked
/// only for what is in view.
///
/// On a real-world map a cell of whole degrees is an upright rectangle (the
/// map is Web Mercator around its anchor, see ``RealWorldFrame``): its
/// west and east edges depend only on longitude, its north and south only
/// on latitude. So each row keeps its non-empty cells sorted by column, and
/// a view looks up its rows and columns directly instead of every cell of
/// the rectangle (the old `cells(north:south:west:east:)` walked every
/// row × column of the view, up to some 350,000 lookups).
///
/// The reference draws its grid from vector tiles, whose zoom levels thin
/// it out when zoomed out; here, when a cell would be drawn smaller than
/// ``minimumTilePoints``, cells are merged into square blocks of 2, 4, 8 …
/// cells a side, each coloured by its cells' average, so a view never
/// fills more than a few thousand rectangles.
public struct PopulationHeatmap: Sendable {
    /// One rectangle to fill: the world rectangle of a cell or a block of
    /// cells, and the people in it.
    public struct Tile: Hashable, Sendable {
        public let minX: Double
        public let minY: Double
        public let maxX: Double
        public let maxY: Double
        /// Everyone in the tile.
        public let people: Int
        /// How many grid cells it covers (1 for a single cell).
        public let cells: Int

        /// The step of the population gradient it is filled with
        /// (``PopTravel/populationBand(people:)`` of its cells' average).
        public var band: Int {
            PopTravel.populationBand(people: Double(people) / Double(max(cells, 1)))
        }
    }

    /// What a tapped cell's tooltip shows (the reference's
    /// `pop-grid-tooltip`: estimated people, and density per km²).
    public struct CellInfo: Hashable, Sendable {
        public let people: Int
        /// The cell's area on the ground, in km².
        public let squareKilometres: Double

        /// People per km².
        public var density: Double {
            squareKilometres > 0 ? Double(people) / squareKilometres : 0
        }

        /// `value` grouped by thousands with at most two decimals, as the
        /// reference's `toLocaleString(…, {maximumFractionDigits: 2})`, the
        /// same in every locale: "9,876.5".
        static func decimalText(_ value: Double) -> String {
            guard value.isFinite else { return "0" }
            let hundredths = Int64((max(value, 0) * 100).rounded())
            var text = Money(hundredths / 100).displayText
            let fraction = hundredths % 100
            if fraction != 0 {
                text += fraction % 10 == 0 ? ".\(fraction / 10)" : (fraction < 10 ? ".0\(fraction)" : ".\(fraction)")
            }
            return text
        }

        /// "Estimated people: 12,345" and "Population density (people/km²): 9,876.5".
        public func lines(in language: DisplayLanguage) -> [String] {
            let people = Money(Int64(self.people)).displayText
            let density = Self.decimalText(self.density)
            return [
                language.text("Estimated people: \(people)", "估算人口：\(people) 人"),
                language.text("Population density (people/km²): \(density)", "人口密度（人/平方公里）：\(density)")
            ]
        }
    }

    /// The smallest a drawn rectangle may be on screen, in points.
    public static let minimumTilePoints = 6.0

    private let grid: GridCounts
    private let frame: RealWorldFrame
    /// Each row's non-empty cells, by column.
    private let rows: [[(column: Int, count: Int)]]
    private let columnCount: Int

    public init(grid population: PopulationGrid, frame: RealWorldFrame) {
        let grid = population.people
        var rows: [[(column: Int, count: Int)]] = []
        var columnCount = 0
        for (cell, count) in grid.counts where count > 0 && cell.row >= 0 && cell.column >= 0 {
            if cell.row >= rows.count {
                rows.append(contentsOf: Array(repeating: [], count: cell.row - rows.count + 1))
            }
            rows[cell.row].append((cell.column, count))
            columnCount = max(columnCount, cell.column + 1)
        }
        for index in rows.indices {
            rows[index].sort { $0.column < $1.column }
        }
        self.grid = grid
        self.frame = frame
        self.rows = rows
        self.columnCount = columnCount
    }

    /// The x of column `column`'s west edge.
    private func columnX(_ column: Int) -> Double {
        frame.worldPosition(latitude: grid.north, longitude: grid.west + Double(column) * grid.cellDegrees).x
    }

    /// The y of row `row`'s north edge.
    private func rowY(_ row: Int) -> Double {
        frame.worldPosition(latitude: grid.north - Double(row) * grid.cellDegrees, longitude: grid.west).y
    }

    /// How many cells a side a block has at `pointsPerUnit` (the camera's
    /// scale): 1, or the smallest power of two that makes a block at least
    /// ``minimumTilePoints`` wide.
    public func blockSize(pointsPerUnit: Double) -> Int {
        let cellWidth = abs(columnX(1) - columnX(0)) * pointsPerUnit
        guard cellWidth.isFinite, cellWidth > 0 else { return 1 }
        var size = 1
        while Double(size) * cellWidth < Self.minimumTilePoints, size < 1 << 12 {
            size *= 2
        }
        return size
    }

    /// The rows and columns of cells that `region` overlaps, one more on
    /// each side; `nil` when it misses the grid.
    private func range(of region: WorldRegion) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        guard !rows.isEmpty, columnCount > 0,
              region.minX.isFinite, region.minY.isFinite, region.maxX.isFinite, region.maxY.isFinite else { return nil }
        let northWest = frame.coordinate(worldX: region.minX, worldY: region.minY)
        let southEast = frame.coordinate(worldX: region.maxX, worldY: region.maxY)
        let first = grid.cell(latitude: northWest.latitude, longitude: northWest.longitude)
        let last = grid.cell(latitude: southEast.latitude, longitude: southEast.longitude)
        let rowRange = (max(0, min(first.row, last.row) - 1), min(rows.count - 1, max(first.row, last.row) + 1))
        let columnRange = (max(0, min(first.column, last.column) - 1), min(columnCount - 1, max(first.column, last.column) + 1))
        guard rowRange.0 <= rowRange.1, columnRange.0 <= columnRange.1 else { return nil }
        return (rowRange.0 ... rowRange.1, columnRange.0 ... columnRange.1)
    }

    /// The rectangles to fill for `region`, cells merged into blocks of
    /// `blockSize` a side (see ``blockSize(pointsPerUnit:)``), in a fixed
    /// order (north to south, west to east).
    public func tiles(in region: WorldRegion, blockSize: Int = 1) -> [Tile] {
        guard let range = range(of: region) else { return [] }
        let size = max(1, blockSize)
        struct Block: Hashable { let row: Int; let column: Int }
        var people: [Block: Int] = [:]
        var order: [Block] = []
        for row in range.rows {
            let entries = rows[row]
            var index = Self.firstIndex(in: entries, atLeast: range.columns.lowerBound)
            while index < entries.count, entries[index].column <= range.columns.upperBound {
                let entry = entries[index]
                let block = Block(row: row / size, column: entry.column / size)
                if people[block] == nil { order.append(block) }
                people[block, default: 0] += entry.count
                index += 1
            }
        }
        order.sort { ($0.row, $0.column) < ($1.row, $1.column) }
        return order.map { block in
            let x0 = columnX(block.column * size), x1 = columnX((block.column + 1) * size)
            let y0 = rowY(block.row * size), y1 = rowY((block.row + 1) * size)
            return Tile(minX: min(x0, x1), minY: min(y0, y1), maxX: max(x0, x1), maxY: max(y0, y1), people: people[block] ?? 0, cells: size * size)
        }
    }

    /// The cell at world point (`x`, `y`), or `nil` where no one lives.
    public func cellInfo(atX x: Double, y: Double) -> CellInfo? {
        guard x.isFinite, y.isFinite else { return nil }
        let place = frame.coordinate(worldX: x, worldY: y)
        let cell = grid.cell(latitude: place.latitude, longitude: place.longitude)
        guard let count = grid.counts[cell], count > 0 else { return nil }
        return CellInfo(people: count, squareKilometres: grid.area(of: cell) / 1_000_000)
    }

    private static func firstIndex(in entries: [(column: Int, count: Int)], atLeast column: Int) -> Int {
        var low = 0, high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].column < column { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
