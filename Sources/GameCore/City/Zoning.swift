// Zoning (city building P0-B, ARCHITECTURE decision 98): the SimCity half
// of the city building study (docs/research/CITY_BUILDING_STUDY.md §4.4).
// The player marks 64 m cells of the world for a use, and a growing
// station's town spreads onto the empty cells marked for a use, putting up
// that use, before it spreads anywhere else; or marks them so the city
// keeps off: "no development" (the A-Train's frozen land: nothing new,
// nothing grows, nothing is raised) and "reserved" (land kept for the
// player's track or buildings: nothing new). Zones are a layer of their own,
// not cells of land with no one in them, so land, its counts and its
// buildings mean what they meant; a world with no zones grows as before.
//
// The company's buildings (decision 94) make the zoned cells within 400 m of
// them worth more, as a park does (decision 91), and the zoned cells worth
// most are built on first: the A-Train's subsidiaries leading the city's
// development.
//
// The owner's references have no zoning (decision 98's reference check):
// the zones, their rules and their numbers are this project's (gap). The
// study's outside projects (Micropolis, Cytopia, Citybound; GPL and AGPL)
// were read for their ideas only: a layer of zones per cell (Cytopia), and
// zoned land developing where land is worth most (Micropolis's `zscore`).

/// What a cell of the world is zoned for (decision 98).
public enum Zone: String, CaseIterable, Codable, Sendable {
    /// Homes, shops, offices, factories, schools and public offices, and
    /// sights: the city spreads onto these empty cells with that use.
    case residential
    case commercial
    case office
    case industrial
    case civic
    case leisure
    /// No development: the city puts up nothing new here, and what stands
    /// here neither grows nor is raised.
    case noDevelopment
    /// Reserved for the player's track or buildings: the city puts up
    /// nothing new here; what stands here grows as before.
    case reserved

    /// The use the city puts up on an empty cell of this zone, or `nil` for
    /// the two that keep it off.
    public var use: LandUse? {
        switch self {
        case .residential: .residential
        case .commercial: .commercial
        case .office: .office
        case .industrial: .industrial
        case .civic: .civic
        case .leisure: .leisure
        case .noDevelopment, .reserved: nil
        }
    }

    /// Who a new cell of this zone holds: a new home's
    /// ``LandDemand/newCellResidents`` (4), and for the other uses the
    /// shares a blank map's towns give them (``Land/towns(seed:in:)``) of
    /// those 4: shops and offices a quarter living there and three times as
    /// many jobs (1 and 12), schools and public offices a quarter and as
    /// many (1 and 4), sights as many visitors and no one living there (0
    /// and 4), factories twice as many jobs (0 and 8).
    var newCell: (residents: Int64, jobs: Int64) {
        let base = LandDemand.newCellResidents
        switch self {
        case .residential: return (base, 0)
        case .commercial, .office: return (base / 4, 3 * base)
        case .civic: return (base / 4, base)
        case .leisure: return (0, base)
        case .industrial: return (0, 2 * base)
        case .noDevelopment, .reserved: return (0, 0)
        }
    }
}

/// One cell of the world and its zone.
public struct ZonedCell: Hashable, Sendable {
    /// Its row and column of 64 m cells, as a cell of land's.
    public let row: Int
    public let column: Int
    public let zone: Zone

    public init(row: Int, column: Int, zone: Zone) {
        self.row = row
        self.column = column
        self.zone = zone
    }

    public var position: CellPosition {
        CellPosition(row: row, column: column)
    }
}

/// The zones of a world (decision 98): the cells the player zoned, by row
/// and then column, each once.
public struct Zoning: Hashable, Sendable {
    /// The most cells a side of the rectangle one ``GameWorld/setZone(_:rows:columns:)``
    /// zones: 128, 8 km.
    public static let maximumSide = 128

    /// By ascending row, then column; each cell once.
    public internal(set) var cells: [ZonedCell]

    public init() {
        cells = []
    }

    public var isEmpty: Bool {
        cells.isEmpty
    }

    /// The zone of the cell at `row`, `column`, or `nil` when it has none.
    public func zone(row: Int, column: Int) -> Zone? {
        let index = firstIndex(atOrAfterRow: row, column: column)
        guard index < cells.count, cells[index].row == row, cells[index].column == column else { return nil }
        return cells[index].zone
    }

    /// Whether a zone lies in rows `rows` and columns `columns`, for the
    /// growth of a world without zones to skip every look.
    func hasZone(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> Bool {
        rows.contains { row in
            let index = firstIndex(atOrAfterRow: row, column: columns.lowerBound)
            return index < cells.count && cells[index].row == row && cells[index].column <= columns.upperBound
        }
    }

    /// Zones every cell of `rows` × `columns` `zone`, but those `skipping`
    /// (water, decision 105), which hold none, or clears them for `nil`, and
    /// returns how many cells changed.
    mutating func set(
        _ zone: Zone?, rows: ClosedRange<Int>, columns: ClosedRange<Int>, skipping: (_ row: Int, _ column: Int) -> Bool = { _, _ in false }
    ) -> Int {
        var kept: [ZonedCell] = [], changed = 0, unchanged = 0
        kept.reserveCapacity(cells.count)
        for cell in cells {
            guard rows.contains(cell.row), columns.contains(cell.column) else {
                kept.append(cell)
                continue
            }
            // A cell skipped now (zoned before its water was read) loses
            // its zone, whatever it was: a change.
            if zone == nil || skipping(cell.row, cell.column) {
                changed += 1
            } else if cell.zone == zone {
                unchanged += 1
            }
        }
        guard let zone else {
            cells = kept
            return changed
        }
        var added: [ZonedCell] = []
        added.reserveCapacity(rows.count * columns.count)
        for row in rows {
            for column in columns where !skipping(row, column) {
                added.append(ZonedCell(row: row, column: column, zone: zone))
            }
        }
        // Both in order: merge them.
        var merged: [ZonedCell] = []
        merged.reserveCapacity(kept.count + added.count)
        var i = 0, j = 0
        while i < kept.count || j < added.count {
            if j == added.count || (i < kept.count && (kept[i].row, kept[i].column) < (added[j].row, added[j].column)) {
                merged.append(kept[i])
                i += 1
            } else {
                merged.append(added[j])
                j += 1
            }
        }
        cells = merged
        return added.count - unchanged + changed
    }

    /// The index of the first cell at or after `row`, `column`.
    func firstIndex(atOrAfterRow row: Int, column: Int) -> Int {
        var low = 0, high = cells.count
        while low < high {
            let middle = (low + high) / 2
            if (cells[middle].row, cells[middle].column) < (row, column) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// Why the zones break a rule in a world of `bounds`, or `nil`: each
    /// cell in the world, once and in order.
    func problem(in bounds: WorldBounds) -> String? {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard cells.allSatisfy({ (0..<rows).contains($0.row) && (0..<columns).contains($0.column) }) else {
            return "A zoned cell is outside the world."
        }
        guard zip(cells, cells.dropFirst()).allSatisfy({ ($0.row, $0.column) < ($1.row, $1.column) }) else {
            return "Zones must list each cell once, by row and then column."
        }
        return nil
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Zones every cell of `rows` × `columns` `zone`, or clears their zones
    /// for `nil` (decision 98): one cell, or the rectangle the player
    /// dragged. Zoning is free, and changes nothing at once: the city
    /// follows the zones as it grows (``growLand(reached:)``), and the
    /// zoned cells near the company's buildings are worth more
    /// (``landValue(row:column:)``). Returns how many cells changed.
    ///
    /// Water is never zoned (decision 105), nor a steep slope (decision
    /// 115): their cells in the rectangle are left without a zone, and the
    /// rest zoned.
    ///
    /// - Throws: ``GameError/invalidZoneArea`` for a rectangle reaching
    ///   outside the world or more than ``Zoning/maximumSide`` cells a side;
    ///   when no cell of the rectangle may be zoned and `zone` is not `nil`,
    ///   ``GameError/onWater(row:column:)`` naming its first cell if that is
    ///   water, else ``GameError/onSteepSlope(row:column:)``.
    @discardableResult
    public mutating func setZone(_ zone: Zone?, rows: ClosedRange<Int>, columns: ClosedRange<Int>) throws(GameError) -> Int {
        guard rows.lowerBound >= 0, columns.lowerBound >= 0,
              rows.upperBound < Land.rows(in: bounds), columns.upperBound < Land.columns(in: bounds),
              rows.count <= Zoning.maximumSide, columns.count <= Zoning.maximumSide
        else { throw .invalidZoneArea }
        guard zone != nil, !terrain.isEmpty else {
            return zones.set(zone, rows: rows, columns: columns)
        }
        let terrain = terrain
        func barred(_ row: Int, _ column: Int) -> Bool {
            terrain.isWater(row: row, column: column) || terrain.isSteep(row: row, column: column)
        }
        guard rows.contains(where: { row in columns.contains { !barred(row, $0) } }) else {
            if terrain.isWater(row: rows.lowerBound, column: columns.lowerBound) {
                throw .onWater(row: rows.lowerBound, column: columns.lowerBound)
            }
            throw .onSteepSlope(row: rows.lowerBound, column: columns.lowerBound)
        }
        return zones.set(zone, rows: rows, columns: columns, skipping: barred)
    }

    // MARK: - Growth

    /// Whether the city may grow or raise what stands on the cell at `row`,
    /// `column`: not where it is zoned no development.
    func allowsGrowth(row: Int, column: Int) -> Bool {
        zones.isEmpty || zones.zone(row: row, column: column) != .noDevelopment
    }
}

// MARK: - Codable

extension Zoning: Codable {
    /// Cells next to each other in a row with the same zone: `{"row",
    /// "column", "zone", "count"}`, the first cell's column and how many.
    private struct Run: Codable {
        var row: Int
        var column: Int
        var zone: Zone
        var count: Int
    }

    /// Decodes a list of runs. The cells must be in order and each once;
    /// the world checks they lie in its bounds.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        var cells: [ZonedCell] = []
        for run in try container.decode([Run].self) {
            guard run.row >= 0, run.column >= 0, run.count > 0, run.count <= Int.max - run.column, cells.count + run.count <= 1 << 26 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A run of zones is empty or out of range.")
            }
            for offset in 0..<run.count {
                cells.append(ZonedCell(row: run.row, column: run.column + offset, zone: run.zone))
            }
        }
        guard zip(cells, cells.dropFirst()).allSatisfy({ ($0.row, $0.column) < ($1.row, $1.column) }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Zones must list each cell once, in order.")
        }
        self.cells = cells
    }

    public func encode(to encoder: any Encoder) throws {
        var runs: [Run] = []
        for cell in cells {
            if var last = runs.last, last.row == cell.row, last.zone == cell.zone, last.column + last.count == cell.column {
                last.count += 1
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(row: cell.row, column: cell.column, zone: cell.zone, count: 1))
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(runs)
    }
}
