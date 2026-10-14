import Foundation
import GameCore

// The sea on a real-world postcard (decision 215, v2): the postcard draws
// no base map, so without it a whole-island network stands on a bare
// ground; the water grid the app already has (``WaterGrid``,
// OpenStreetMap's coastline, ODbL, credited with the railways) gives the
// coast. Only water that reaches the map's edge is drawn: the sea, not
// rivers and ponds, which at a postcard's scale are specks.

/// The sea over a postcard's map, as runs of small square cells, row by
/// row.
public struct PostcardSea: Hashable, Sendable {
    /// Cells of one row, `columns` of them across, in cells of ``cell``.
    public struct Run: Hashable, Sendable {
        public let row: Int
        public let columns: Range<Int>
    }

    /// A cell's side, in points.
    public let cell: Double
    public let runs: [Run]

    /// The sea of a map `size` large drawn by `projection` (north up) over
    /// a world laid on the Earth by `frame`. Beyond the grid (which reaches
    /// some 11 km off Taiwan's coast) is sea.
    public init(water: WaterGrid, frame: RealWorldFrame, projection: some MapProjection, size: ScreenSize, cell: Double = 0.5) {
        self.cell = cell
        let columns = max(0, Int((size.width / cell).rounded(.up)))
        let rows = max(0, Int((size.height / cell).rounded(.up)))
        // North up, and Web Mercator: a row's latitude is its y's alone, a
        // column's longitude its x's alone.
        let origin = projection.worldPosition(at: ScreenPoint(x: 0, y: 0))
        let gridRows: [Int?] = (0..<rows).map { row in
            let y = projection.worldPosition(at: ScreenPoint(x: 0, y: (Double(row) + 0.5) * cell)).y
            return water.row(latitude: frame.coordinate(worldX: origin.x, worldY: y).latitude)
        }
        let gridColumns: [Int?] = (0..<columns).map { column in
            let x = projection.worldPosition(at: ScreenPoint(x: (Double(column) + 0.5) * cell, y: 0)).x
            return water.column(longitude: frame.coordinate(worldX: x, worldY: origin.y).longitude)
        }
        var wet = [Bool](repeating: false, count: rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                guard let r = gridRows[row], let c = gridColumns[column] else {
                    wet[row * columns + column] = true
                    continue
                }
                wet[row * columns + column] = water.isWater(row: r, column: c)
            }
        }
        runs = Self.runs(of: Self.sea(wet, rows: rows, columns: columns), rows: rows, columns: columns)
    }

    /// The wet cells joined (side by side) to a wet cell on the edge.
    static func sea(_ wet: [Bool], rows: Int, columns: Int) -> [Bool] {
        var sea = [Bool](repeating: false, count: wet.count)
        var queue: [Int] = []
        func visit(_ index: Int) {
            if wet[index], !sea[index] {
                sea[index] = true
                queue.append(index)
            }
        }
        for row in 0..<rows {
            visit(row * columns)
            if columns > 1 { visit(row * columns + columns - 1) }
        }
        for column in 0..<columns {
            visit(column)
            if rows > 1 { visit((rows - 1) * columns + column) }
        }
        var next = 0
        while next < queue.count {
            let index = queue[next]
            next += 1
            let row = index / columns, column = index % columns
            if column > 0 { visit(index - 1) }
            if column + 1 < columns { visit(index + 1) }
            if row > 0 { visit(index - columns) }
            if row + 1 < rows { visit(index + columns) }
        }
        return sea
    }

    static func runs(of cells: [Bool], rows: Int, columns: Int) -> [Run] {
        var runs: [Run] = []
        for row in 0..<rows {
            var column = 0
            while column < columns {
                guard cells[row * columns + column] else {
                    column += 1
                    continue
                }
                let start = column
                while column < columns, cells[row * columns + column] { column += 1 }
                runs.append(Run(row: row, columns: start..<column))
            }
        }
        return runs
    }
}
