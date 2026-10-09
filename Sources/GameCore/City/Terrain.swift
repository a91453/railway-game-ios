// Terrain (ARCHITECTURE decision 105): the ground under the land, a layer
// of its own beside the land's uses (decision 72, 91) and the player's
// zones (decision 98). Its first kind is water: the sea off the coast,
// rivers and lakes, the one real obstacle decision 96 found among the
// land a player meets. The city does not spread onto water, grow or raise
// what stands there; the player cannot place a building on it or zone it.
// Track and stations may still cross it for now: bridges and what they
// cost come later.
//
// Water is a set of 64 m cells, kept as runs along each row, so a coast
// costs a few runs a row however much sea lies off it. A real-world map's
// water comes from GamePresentation (`WaterGrid`, from OpenStreetMap's
// coastline and water areas); a blank map has none. A world whose land is
// read as it is needed (decision 88) reads its water with each block, and
// the runs of the blocks read join up the same whatever order they came
// in.
//
// Since decision 115 the terrain also marks steep slopes: dry cells on a
// hillside of more than 30 %, where the city puts up nothing new and raises
// nothing, and the player neither builds nor zones. Land may stand on them
// (people live on Jiufen's hillside); only what is new is held back. They
// are kept as runs too, never on water.
//
// The owner's references keep water the same way, as a kind of ground
// (`taipei_gta_reference`'s `surfaceAt` gives `'water'`, and its
// placement samples a building's footprint against the ground it may
// stand on); its rules and numbers here are this project's (gap).

/// Cells of water (or, since decision 115, of steep slope) next to each
/// other along a row: `count` cells from `column`.
public struct WaterRun: Hashable, Codable, Sendable {
    public let row: Int
    public let column: Int
    public let count: Int

    public init(row: Int, column: Int, count: Int) {
        self.row = row
        self.column = column
        self.count = count
    }

    /// The column after its last cell.
    var end: Int { column + count }
}

/// The world's terrain (decision 105): which of its 64 m cells are water,
/// and (decision 115) which are steep.
public struct Terrain: Hashable, Sendable {
    /// The water, by ascending row and then column: runs that neither
    /// overlap nor touch (two touching runs are one), so one set of cells
    /// is always the same runs.
    public private(set) var water: [WaterRun]
    /// The steep slopes (decision 115), runs as the water's, none on water.
    public private(set) var steep: [WaterRun] = []

    public init() {
        water = []
    }

    /// The terrain whose water is `cells`, and steep slopes `steep`, in any
    /// order. A cell listed more than once counts once.
    public init(water cells: [CellPosition], steep: [CellPosition] = []) {
        water = Self.runs(of: cells.sorted())
        self.steep = Self.runs(of: steep.sorted())
    }

    public var isEmpty: Bool {
        water.isEmpty && steep.isEmpty
    }

    /// How many cells are water.
    public var waterCellCount: Int {
        water.reduce(0) { $0 + $1.count }
    }

    /// How many cells are steep (decision 115).
    public var steepCellCount: Int {
        steep.reduce(0) { $0 + $1.count }
    }

    /// Whether the cell at `row`, `column` is water.
    public func isWater(row: Int, column: Int) -> Bool {
        Self.contains(water, row: row, column: column)
    }

    /// Whether the cell at `row`, `column` is steep (decision 115).
    public func isSteep(row: Int, column: Int) -> Bool {
        Self.contains(steep, row: row, column: column)
    }

    /// Whether `runs` (sorted, apart) hold the cell at `row`, `column`.
    static func contains(_ runs: [WaterRun], row: Int, column: Int) -> Bool {
        // The last run starting at or before the cell.
        var low = 0, high = runs.count
        while low < high {
            let middle = (low + high) / 2
            if (runs[middle].row, runs[middle].column) <= (row, column) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return false }
        let run = runs[low - 1]
        return run.row == row && column < run.end
    }

    /// Whether any cell of `rows` × `columns` is water.
    func hasWater(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> Bool {
        guard !water.isEmpty else { return false }
        return rows.contains { row in
            columns.contains { isWater(row: row, column: $0) }
        }
    }

    /// Whether a cell of water's middle lies within ``LandValueRules/waterReach``
    /// of the middle of the cell at `row`, `column` (the cell itself
    /// included): the rows within reach, and in each the run nearest the
    /// column.
    func isNearWater(row: Int, column: Int) -> Bool {
        guard !water.isEmpty else { return false }
        let length = Land.cellLength, reach = LandValueRules.waterReach
        let rows = Int(reach / length)
        for dr in -rows...rows {
            let target = row + dr
            // The first run of that row ending after the column reach.
            var low = 0, high = water.count
            let from = column - rows
            while low < high {
                let middle = (low + high) / 2
                if (water[middle].row, water[middle].end) <= (target, from) {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            var index = low
            while index < water.count, water[index].row == target, water[index].column <= column + rows {
                let run = water[index]
                let nearest = min(max(column, run.column), run.end - 1)
                let dx = Int64(nearest - column) * length, dy = Int64(dr) * length
                if dx * dx + dy * dy < reach * reach { return true }
                index += 1
            }
        }
        return false
    }

    /// Replaces the water with `cells`, sorted and each once.
    mutating func setWater(_ cells: [CellPosition]) {
        water = Self.runs(of: cells)
    }

    /// Replaces the steep slopes with `cells`, sorted and each once.
    mutating func setSteep(_ cells: [CellPosition]) {
        steep = Self.runs(of: cells)
    }

    /// Adds `cells`, in any order, to the water.
    mutating func add(_ cells: [CellPosition]) {
        guard !cells.isEmpty else { return }
        water = Self.union(water, Self.runs(of: cells.sorted()))
    }

    /// Adds `cells`, in any order, to the steep slopes (decision 115).
    mutating func addSteep(_ cells: [CellPosition]) {
        guard !cells.isEmpty else { return }
        steep = Self.union(steep, Self.runs(of: cells.sorted()))
    }

    /// The runs of `cells`, sorted (a cell listed twice counts once).
    static func runs(of cells: [CellPosition]) -> [WaterRun] {
        var runs: [WaterRun] = []
        for cell in cells {
            if let last = runs.last, last.row == cell.row, cell.column <= last.end {
                if cell.column == last.end {
                    runs[runs.count - 1] = WaterRun(row: last.row, column: last.column, count: last.count + 1)
                }
            } else {
                runs.append(WaterRun(row: cell.row, column: cell.column, count: 1))
            }
        }
        return runs
    }

    /// The cells of either `a` or `b`, both sorted, as runs.
    static func union(_ a: [WaterRun], _ b: [WaterRun]) -> [WaterRun] {
        var merged: [WaterRun] = []
        merged.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            let next: WaterRun
            if j == b.count || (i < a.count && (a[i].row, a[i].column) <= (b[j].row, b[j].column)) {
                next = a[i]
                i += 1
            } else {
                next = b[j]
                j += 1
            }
            if let last = merged.last, last.row == next.row, next.column <= last.end {
                merged[merged.count - 1] = WaterRun(row: last.row, column: last.column, count: max(last.end, next.end) - last.column)
            } else {
                merged.append(next)
            }
        }
        return merged
    }

    /// Why the water or the steep slopes break a rule in a world of
    /// `bounds`, or `nil`: each run in the world, not empty, in order,
    /// neither overlapping nor touching the one before; no steep cell on
    /// water.
    func problem(in bounds: WorldBounds) -> String? {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        for runs in [water, steep] {
            guard runs.allSatisfy({ (0..<rows).contains($0.row) && $0.column >= 0 && $0.count > 0 && $0.count <= columns - $0.column }) else {
                return "A run of terrain is empty or outside the world."
            }
            guard zip(runs, runs.dropFirst()).allSatisfy({ $0.row < $1.row || ($0.row == $1.row && $0.end < $1.column) }) else {
                return "Terrain must list its runs in order, apart from each other."
            }
        }
        if !steep.isEmpty, !water.isEmpty,
           steep.contains(where: { run in (run.column..<run.end).contains { isWater(row: run.row, column: $0) } }) {
            return "A steep slope lies on water."
        }
        return nil
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Replaces the world's water with `cells`, in any order (decision
    /// 105): a real-world map's sea, rivers and lakes, from
    /// GamePresentation's `WaterGrid`. An empty list clears it. Only for a
    /// world whose land is whole: one read as it is needed reads its water
    /// with each block (``expandLand(_:cells:water:steep:)``).
    ///
    /// - Throws: ``GameError/invalidTerrain`` for a world whose land is read
    ///   as it is needed, a cell outside the world, listed twice, or where
    ///   there is land (the land goes on the ground, so a real-world map
    ///   sets its water first) or a steep slope (decision 115).
    public mutating func setWater(_ cells: [CellPosition]) throws(GameError) {
        guard landBlocks == nil else { throw .invalidTerrain }
        let sorted = cells.sorted()
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard sorted.allSatisfy({
                  (0..<rows).contains($0.row) && (0..<columns).contains($0.column) && land.cell(row: $0.row, column: $0.column) == nil
                      && !terrain.isSteep(row: $0.row, column: $0.column)
              }),
              zip(sorted, sorted.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw .invalidTerrain }
        terrain.setWater(sorted)
    }

    /// Replaces the world's steep slopes with `cells`, in any order
    /// (decision 115): a real-world map's hillsides of more than 30 %, from
    /// GamePresentation's `WaterGrid`. An empty list clears them. Land may
    /// stand on them. Only for a world whose land is whole, as
    /// ``setWater(_:)``.
    ///
    /// - Throws: ``GameError/invalidTerrain`` for a world whose land is read
    ///   as it is needed, a cell outside the world, listed twice, or on
    ///   water.
    public mutating func setSteep(_ cells: [CellPosition]) throws(GameError) {
        guard landBlocks == nil else { throw .invalidTerrain }
        let sorted = cells.sorted()
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard sorted.allSatisfy({
                  (0..<rows).contains($0.row) && (0..<columns).contains($0.column) && !terrain.isWater(row: $0.row, column: $0.column)
              }),
              zip(sorted, sorted.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw .invalidTerrain }
        terrain.setSteep(sorted)
    }

    // MARK: - Queries

    /// Whether the cell at `row`, `column` is water.
    public func isWater(row: Int, column: Int) -> Bool {
        terrain.isWater(row: row, column: column)
    }

    /// Whether the cell at `row`, `column` is steep (decision 115).
    public func isSteep(row: Int, column: Int) -> Bool {
        terrain.isSteep(row: row, column: column)
    }

    /// The steep cell under any part of `building`'s square (decision
    /// 115), the first by row and then column, or `nil`.
    func steepUnder(_ building: PlacedBuilding) -> CellPosition? {
        guard !terrain.steep.isEmpty else { return nil }
        let firstRow = Land.cellIndex(building.minY), lastRow = Land.cellIndex(building.maxY - 1)
        let firstColumn = Land.cellIndex(building.minX), lastColumn = Land.cellIndex(building.maxX - 1)
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn where terrain.isSteep(row: row, column: column) {
                return CellPosition(row: row, column: column)
            }
        }
        return nil
    }

    /// Whether `building`'s square has both water and land under it: it
    /// stands on the shore (decision 111).
    func straddlesShore(_ building: PlacedBuilding) -> Bool {
        let firstRow = Land.cellIndex(building.minY), lastRow = Land.cellIndex(building.maxY - 1)
        let firstColumn = Land.cellIndex(building.minX), lastColumn = Land.cellIndex(building.maxX - 1)
        var wet = false, dry = false
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                if terrain.isWater(row: row, column: column) { wet = true } else { dry = true }
            }
        }
        return wet && dry
    }

    /// The water cell under any part of `building`'s square, the first by
    /// row and then column, or `nil`.
    func waterUnder(_ building: PlacedBuilding) -> CellPosition? {
        guard !terrain.isEmpty else { return nil }
        let firstRow = Land.cellIndex(building.minY), lastRow = Land.cellIndex(building.maxY - 1)
        let firstColumn = Land.cellIndex(building.minX), lastColumn = Land.cellIndex(building.maxX - 1)
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn where terrain.isWater(row: row, column: column) {
                return CellPosition(row: row, column: column)
            }
        }
        return nil
    }

    /// Why the terrain breaks a rule, or `nil`: its runs in the world and in
    /// order, no land on water, and, for land read as it is needed, water
    /// and steep slopes only in the blocks read.
    func terrainProblem() -> String? {
        if let problem = terrain.problem(in: bounds) {
            return problem
        }
        guard !terrain.isEmpty else { return nil }
        if land.cells.contains(where: { terrain.isWater(row: $0.row, column: $0.column) }) {
            return "Land lies on water."
        }
        if let landBlocks {
            let read = Set(landBlocks)
            for run in terrain.water + terrain.steep {
                let first = LandBlock(cellRow: run.row, column: run.column), last = LandBlock(cellRow: run.row, column: run.end - 1)
                guard (first.column...last.column).allSatisfy({ read.contains(LandBlock(row: first.row, column: $0)) }) else {
                    return "Terrain lies outside the blocks of land read."
                }
            }
        }
        return nil
    }
}

// MARK: - Codable

extension Terrain: Codable {
    private enum CodingKeys: String, CodingKey {
        case water, steep
    }

    /// Decodes `{"water": [{"row", "column", "count"}, …]}` and, since save
    /// version 26 (decision 115), `"steep"` alike, each left out when
    /// empty. The runs must be in order and apart; the world checks they
    /// lie in its bounds and no steep cell is water.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func runs(_ key: CodingKeys) throws -> [WaterRun] {
            let runs = try container.decodeIfPresent([WaterRun].self, forKey: key) ?? []
            guard runs.allSatisfy({ $0.row >= 0 && $0.column >= 0 && $0.count > 0 && $0.count <= Int.max - $0.column }),
                  zip(runs, runs.dropFirst()).allSatisfy({ $0.row < $1.row || ($0.row == $1.row && $0.end < $1.column) })
            else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Terrain must list its runs in order, apart and not empty.")
            }
            return runs
        }
        water = try runs(.water)
        steep = try runs(.steep)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !water.isEmpty {
            try container.encode(water, forKey: .water)
        }
        if !steep.isEmpty {
            try container.encode(steep, forKey: .steep)
        }
    }
}
