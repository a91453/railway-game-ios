// Land (Phase 6a, ARCHITECTURE decision 72): the city the railway serves,
// as a hidden grid of 64 m cells over the world, each used for homes, shops
// or offices and holding its residents and jobs.
//
// The owner's references have no land model to port: `Ci/` draws a land-use
// map from vector tiles it does not ship (`virtual_island_city`'s
// `city.pmtiles`) and a population grid it uses for a station's first
// ridership; the reference pack names OpenTTD's towns (`town_cmd.cpp`) only
// by path; `Railway/` and `taipei_gta_reference` draw buildings and districts
// without residents or jobs (the study, `docs/research/PHASE6_LAND_USE_STUDY.md`
// in PR #172). So the cells, the towns a blank map starts with and their
// numbers are this project's (gap):
//
// - a cell is 4096 × 4096 world units (64 m) from the world's origin; the
//   grid is not drawn and does not bind the railway, which stays continuous
//   (decisions 28, 54): only land is counted by cell;
// - a cell is listed only while someone lives or works there, and holds one
//   use, at most 100,000 residents and 100,000 jobs;
// - a blank map starts with three towns drawn from a seed (``Land/towns(seed:in:)``),
//   a real-world map with its people (`LandImport` in GamePresentation);
// - a station's catchment is the cells whose middles lie within 800 m of
//   it, the radius the real-world ridership already uses.
//
// Phase 6a only records land: ridership is still each station's own
// (`StationDemand`) and town growth still grows it (decision 70); deriving
// demand from land is Phase 6b.

/// What a cell of land is used for.
public enum LandUse: String, CaseIterable, Codable, Sendable {
    /// Homes.
    case residential
    /// Shops.
    case commercial
    /// Offices.
    case office
}

/// One cell of land with someone living or working in it.
public struct LandCell: Hashable, Sendable {
    /// Its row, from the world's north edge, and column, from its west edge,
    /// in cells of ``Land/cellLength``.
    public let row: Int
    public let column: Int
    public let use: LandUse
    /// The people living there and the jobs there: 0 to
    /// ``Land/maximumPerCell`` each, not both 0.
    public let residents: Int64
    public let jobs: Int64

    public init(row: Int, column: Int, use: LandUse, residents: Int64, jobs: Int64) {
        self.row = row
        self.column = column
        self.use = use
        self.residents = residents
        self.jobs = jobs
    }

    /// The world point at its middle.
    public var middle: PlanPoint {
        PlanPoint(
            x: Int64(column) * Land.cellLength + Land.cellLength / 2,
            y: Int64(row) * Land.cellLength + Land.cellLength / 2
        )
    }

    var isValid: Bool {
        row >= 0 && column >= 0
            && (0...Land.maximumPerCell).contains(residents) && (0...Land.maximumPerCell).contains(jobs)
            && residents + jobs > 0
    }
}

/// People and jobs added up.
public struct LandTotals: Hashable, Sendable {
    public var residents: Int64
    public var jobs: Int64

    public init(residents: Int64 = 0, jobs: Int64 = 0) {
        self.residents = residents
        self.jobs = jobs
    }
}

/// A world's land: its cells with someone living or working in them, by
/// row and then column.
public struct Land: Hashable, Sendable {
    /// A cell's side: 64 m.
    public static let cellLength: Int64 = 4_096
    /// The most residents, and the most jobs, a cell holds: some 24 million
    /// a km², far above any real city, so only a damaged save meets it.
    public static let maximumPerCell: Int64 = 100_000
    /// How far a station's catchment reaches: 800 m, about ten minutes'
    /// walk (the real-world ridership's radius, GamePresentation's
    /// `StationDemand.catchmentRadius`).
    public static let catchmentRadius: Int64 = 51_200

    /// By ascending row, then column; each cell once.
    public internal(set) var cells: [LandCell]

    public init() {
        cells = []
    }

    public var isEmpty: Bool {
        cells.isEmpty
    }

    /// Everyone and every job on the land.
    public var totals: LandTotals {
        cells.reduce(into: LandTotals()) {
            $0.residents += $1.residents
            $0.jobs += $1.jobs
        }
    }

    /// How many columns and rows of cells cover `bounds`: the last of each
    /// may reach past its edge.
    public static func columns(in bounds: WorldBounds) -> Int {
        Int((bounds.width + cellLength - 1) / cellLength)
    }

    public static func rows(in bounds: WorldBounds) -> Int {
        Int((bounds.height + cellLength - 1) / cellLength)
    }

    /// The cell at `row`, `column`, if anyone lives or works there.
    public func cell(row: Int, column: Int) -> LandCell? {
        let index = firstIndex(atOrAfterRow: row, column: column)
        guard index < cells.count, cells[index].row == row, cells[index].column == column else { return nil }
        return cells[index]
    }

    /// The cell `point` lies in, if anyone lives or works there.
    public func cell(at point: PlanPoint) -> LandCell? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        return cell(row: Int(point.y / Self.cellLength), column: Int(point.x / Self.cellLength))
    }

    /// The residents and jobs of the cells whose middles lie closer than
    /// `radius` to `point`, compared squared, exactly.
    public func totals(within radius: Int64, of point: PlanPoint) -> LandTotals {
        var totals = LandTotals()
        guard radius > 0, let first = cells.first, let last = cells.last, point.isWithinLimits, radius <= WorldCoordinate.limit
        else { return totals }
        let length = Self.cellLength
        let firstRow = max(first.row, Self.cellIndex(point.y - radius)), lastRow = min(last.row, Self.cellIndex(point.y + radius))
        let firstColumn = max(0, Self.cellIndex(point.x - radius)), lastColumn = Self.cellIndex(point.x + radius)
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return totals }
        let reach = radius * radius
        for row in firstRow...lastRow {
            let dy = Int64(row) * length + length / 2 - point.y
            var index = firstIndex(atOrAfterRow: row, column: firstColumn)
            while index < cells.count, cells[index].row == row, cells[index].column <= lastColumn {
                let cell = cells[index]
                let dx = Int64(cell.column) * length + length / 2 - point.x
                if dx * dx + dy * dy < reach {
                    totals.residents += cell.residents
                    totals.jobs += cell.jobs
                }
                index += 1
            }
        }
        return totals
    }

    /// The cell index of world coordinate `value`, rounded down (negative
    /// for a coordinate west or north of the world).
    static func cellIndex(_ value: Int64) -> Int {
        let floor = value >= 0 ? value / cellLength : -((-value + cellLength - 1) / cellLength)
        return Int(floor)
    }

    /// The index of the first cell at or after `row`, `column`.
    private func firstIndex(atOrAfterRow row: Int, column: Int) -> Int {
        var low = 0, high = cells.count
        while low < high {
            let middle = (low + high) / 2
            let cell = cells[middle]
            if (cell.row, cell.column) < (row, column) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// Why the land breaks a rule in a world of `bounds`, or `nil`: cells in
    /// the bounds, each once and in order, with counts in range.
    func problem(in bounds: WorldBounds) -> String? {
        let columns = Self.columns(in: bounds), rows = Self.rows(in: bounds)
        for cell in cells {
            guard cell.isValid else { return "A cell of land is out of range." }
            guard cell.row < rows, cell.column < columns else { return "A cell of land is outside the world." }
        }
        guard zip(cells, cells.dropFirst()).allSatisfy({ ($0.row, $0.column) < ($1.row, $1.column) }) else {
            return "Land must list each cell once, by row and then column."
        }
        return nil
    }
}

// MARK: - Towns

extension Land {
    /// How many towns a blank map starts with.
    public static let townCount = 3

    /// The land of the towns a blank map of `bounds` starts with, drawn from
    /// `seed` (gap, this project's):
    ///
    /// - the first town stands in the middle of the world, where the map
    ///   opens; its radius is 12 cells (768 m) and its middle cell holds 130
    ///   residents;
    /// - the second stands 2 to 5 km east or west and 2 to 5 km north or
    ///   south of the middle, in a quarter drawn from the seed, and the third
    ///   as far in the opposite quarter; each has a radius of 7 to 10 cells
    ///   and 80 to 120 residents in its middle cell;
    /// - a cell whose middle is `d` cells from its town's middle cell, closer
    ///   than the radius `r`, holds `peak × (r² − d²) / r²` residents,
    ///   rounded down in thousandths of the peak;
    /// - the core, `9d² < r²`, is shops or offices, drawn per cell: it holds
    ///   a quarter of those residents and three times as many jobs; the
    ///   rest is homes;
    /// - cells outside the bounds are left out. The towns never meet: the
    ///   outer two stand at least 2 km from the middle in both directions,
    ///   some 2.8 km away and farther from each other, and the widest two
    ///   reach 768 m and 640 m.
    ///
    /// The draws are FNV-1a hashes of the seed and a key (``SeedDraw``), as
    /// the demand events' are, so a seed always makes the same towns.
    public static func towns(seed: UInt32, in bounds: WorldBounds) -> Land {
        let draw = SeedDraw(seed: seed)
        let metre = WorldCoordinate.unitsPerMetre
        let middle = (x: bounds.width / 2, y: bounds.height / 2)
        // The quarter of the second town: 0 north-east, 1 south-east, 2
        // south-west, 3 north-west; the third is opposite.
        let quarter = draw.roll("town.quarter", in: 0...3)
        var towns: [(x: Int64, y: Int64, radius: Int64, peak: Int64)] = [(middle.x, middle.y, 12, 130)]
        for (number, side) in [(1, quarter), (2, (quarter + 2) % 4)] {
            let east: Int64 = side == 0 || side == 1 ? 1 : -1
            let south: Int64 = side == 1 || side == 2 ? 1 : -1
            let dx = draw.roll("town.\(number).east", in: 2_000...5_000) * metre
            let dy = draw.roll("town.\(number).south", in: 2_000...5_000) * metre
            let radius = draw.roll("town.\(number).radius", in: 7...10)
            let peak = draw.roll("town.\(number).peak", in: 80...120)
            towns.append((middle.x + east * dx, middle.y + south * dy, radius, peak))
        }

        let columns = columns(in: bounds), rows = rows(in: bounds)
        var cells: [LandCell] = []
        for (number, town) in towns.enumerated() {
            let middleRow = cellIndex(town.y), middleColumn = cellIndex(town.x)
            let radius = town.radius, squared = radius * radius
            for dr in -radius...radius {
                for dc in -radius...radius {
                    let distance = dr * dr + dc * dc
                    guard distance < squared else { continue }
                    let row = middleRow + Int(dr), column = middleColumn + Int(dc)
                    guard (0..<rows).contains(row), (0..<columns).contains(column) else { continue }
                    let share = (squared - distance) * 1_000 / squared
                    var residents = town.peak * share / 1_000
                    var jobs: Int64 = 0
                    var use = LandUse.residential
                    if 9 * distance < squared {
                        use = draw.roll("town.\(number).cell.\(dr).\(dc)", in: 0...1) == 0 ? .office : .commercial
                        jobs = 3 * residents
                        residents /= 4
                    }
                    guard residents + jobs > 0 else { continue }
                    cells.append(LandCell(row: row, column: column, use: use, residents: residents, jobs: jobs))
                }
            }
        }
        var land = Land()
        land.cells = cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        return land
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Replaces the world's land with `cells`, in any order (a real-world
    /// map's people, GamePresentation's `LandImport`). An empty list clears
    /// it.
    ///
    /// - Throws: ``GameError/invalidLand`` for a cell outside the world,
    ///   listed twice, with a negative count, more than
    ///   ``Land/maximumPerCell`` residents or jobs, or no one living or
    ///   working there.
    public mutating func setLand(_ cells: [LandCell]) throws(GameError) {
        var land = Land()
        land.cells = cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        guard land.problem(in: bounds) == nil else { throw .invalidLand }
        self.land = land
    }

    /// Replaces the world's land with the towns a blank map starts with,
    /// drawn from `seed` (see ``Land/towns(seed:in:)``).
    public mutating func foundTowns(seed: UInt32) {
        land = Land.towns(seed: seed, in: bounds)
    }

    // MARK: - Queries

    /// The residents and jobs of station `id`'s catchment: the cells whose
    /// middles lie within ``Land/catchmentRadius`` of it. `nil` for a
    /// station that does not exist.
    public func landCatchment(of id: StationID) -> LandTotals? {
        guard let station = station(id: id) else { return nil }
        return land.totals(within: Land.catchmentRadius, of: station.location)
    }
}

// MARK: - Codable

extension Land: Codable {
    /// Cells next to each other in a row with the same use: `{"row",
    /// "column", "use", "residents": [n, …], "jobs": [n, …]}`, the first
    /// cell's column, one count a cell, `"jobs"` left out when they are all
    /// 0. A real-world map lists tens of thousands of cells, and a run
    /// writes each as one or two numbers.
    private struct Run: Codable {
        var row: Int
        var column: Int
        var use: LandUse
        var residents: [Int64]
        var jobs: [Int64]?
    }

    /// Decodes a list of runs. The cells must be in order, each once and in
    /// range; the world checks they lie in its bounds.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        var cells: [LandCell] = []
        for run in try container.decode([Run].self) {
            guard !run.residents.isEmpty, run.jobs.map({ $0.count == run.residents.count }) ?? true,
                  run.column >= 0, run.residents.count <= Int.max - run.column
            else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A run of land has no cells, or its counts do not match.")
            }
            for (offset, residents) in run.residents.enumerated() {
                cells.append(LandCell(row: run.row, column: run.column + offset, use: run.use, residents: residents, jobs: run.jobs?[offset] ?? 0))
            }
        }
        self.cells = cells
        guard cells.allSatisfy(\.isValid),
              zip(cells, cells.dropFirst()).allSatisfy({ ($0.row, $0.column) < ($1.row, $1.column) })
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Land must list each cell once, in order, with counts in range.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var runs: [Run] = []
        for cell in cells {
            if var last = runs.last, last.row == cell.row, last.use == cell.use, last.column + last.residents.count == cell.column {
                last.residents.append(cell.residents)
                last.jobs?.append(cell.jobs)
                if last.jobs == nil, cell.jobs != 0 {
                    last.jobs = Array(repeating: 0, count: last.residents.count - 1) + [cell.jobs]
                }
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(row: cell.row, column: cell.column, use: cell.use, residents: [cell.residents], jobs: cell.jobs == 0 ? nil : [cell.jobs]))
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(runs)
    }
}
