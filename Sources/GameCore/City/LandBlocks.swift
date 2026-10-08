// Land read in as it is needed (decision 88): a map of the whole of Taiwan
// holds some 5 million cells of people, too many to spread over the world
// when the game starts, so its land starts empty and comes in by blocks of
// 16 × 16 cells (1,024 m) round each station the player builds. The world
// keeps which blocks it has read in (``GameWorld/landBlocks``), so a block
// is read once, and a save holds them; where the land comes from (a
// real-world map's people) is GamePresentation's, as for ``GameWorld/setLand(_:)``.
//
// The references have no land read in as it is needed (gap): `Ci/` and the
// `Railway/` site read their population grids whole, for one city.

/// A block of land: ``Land/blockCells`` cells a side, 1,024 m, from the
/// world's origin.
public struct LandBlock: Hashable, Comparable, Sendable {
    /// Its row, from the world's north edge, and column, from its west edge,
    /// in blocks.
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// The block cell `row`, `column` lies in.
    public init(cellRow row: Int, column: Int) {
        self.init(row: row / Land.blockCells, column: column / Land.blockCells)
    }

    public static func < (lhs: LandBlock, rhs: LandBlock) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

extension Land {
    /// A block's side, in cells: 16, 1,024 m.
    public static let blockCells = 16
    /// A block's side, in world units.
    public static let blockLength = cellLength * Int64(blockCells)

    /// How many rows and columns of blocks cover `bounds`: the last of each
    /// may reach past its edge.
    public static func blockRows(in bounds: WorldBounds) -> Int {
        (rows(in: bounds) + blockCells - 1) / blockCells
    }

    public static func blockColumns(in bounds: WorldBounds) -> Int {
        (columns(in: bounds) + blockCells - 1) / blockCells
    }

    /// The blocks of a world of `bounds` some part of which lies closer
    /// than `radius` to `point`, compared squared, exactly; by row and then
    /// column.
    public static func blocks(within radius: Int64, of point: PlanPoint, in bounds: WorldBounds) -> [LandBlock] {
        guard radius > 0, point.isWithinLimits, radius <= WorldCoordinate.limit else { return [] }
        let length = blockLength
        func index(_ value: Int64) -> Int {
            Int(value >= 0 ? value / length : -((-value + length - 1) / length))
        }
        // How far `value` lies outside the block's span `[start, start + length)`.
        func gap(_ value: Int64, _ start: Int64) -> Int64 {
            max(0, start - value, value - (start + length - 1))
        }
        let firstRow = max(0, index(point.y - radius)), lastRow = min(blockRows(in: bounds) - 1, index(point.y + radius))
        let firstColumn = max(0, index(point.x - radius)), lastColumn = min(blockColumns(in: bounds) - 1, index(point.x + radius))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return [] }
        var found: [LandBlock] = []
        for row in firstRow...lastRow {
            let dy = gap(point.y, Int64(row) * length)
            for column in firstColumn...lastColumn {
                let dx = gap(point.x, Int64(column) * length)
                if dx * dx + dy * dy < radius * radius {
                    found.append(LandBlock(row: row, column: column))
                }
            }
        }
        return found
    }

    /// Adds `fresh`, in order and none listed yet, in their places.
    mutating func merge(_ fresh: [LandCell]) {
        guard !fresh.isEmpty else { return }
        var merged: [LandCell] = []
        merged.reserveCapacity(cells.count + fresh.count)
        var i = 0, j = 0
        while i < cells.count || j < fresh.count {
            if j == fresh.count || (i < cells.count && (cells[i].row, cells[i].column) < (fresh[j].row, fresh[j].column)) {
                merged.append(cells[i])
                i += 1
            } else {
                merged.append(fresh[j])
                j += 1
            }
        }
        cells = merged
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Makes the world's land read in as it is needed (decision 88): it
    /// has none yet, nor buildings, and no block has been read
    /// (``expandLand(_:cells:)`` reads them). ``setLand(_:)`` and
    /// ``foundTowns(seed:)`` make the land whole again.
    public mutating func setLandOnDemand() {
        replaceLand(with: Land())
        landBlocks = []
        refreshLandDemand()
    }

    /// Reads in `blocks` of land read as it is needed (decision 88), with
    /// `cells`, in any order, the people and jobs in them: a cell already
    /// listed (the land grew there before its block was read) keeps what it
    /// has. With the city's buildings on, each new cell gets its building,
    /// numbered by row and then column after every other.
    ///
    /// - Throws: ``GameError/invalidLand`` for a world whose land is whole
    ///   (``landBlocks`` is `nil`), a block outside the world, listed twice
    ///   or already read, or a cell outside the blocks, listed twice, with a
    ///   negative count, more than ``Land/maximumPerCell`` residents or
    ///   jobs, or no one living or working there.
    public mutating func expandLand(_ blocks: [LandBlock], cells: [LandCell]) throws(GameError) {
        guard let read = landBlocks else { throw .invalidLand }
        let rows = Land.blockRows(in: bounds), columns = Land.blockColumns(in: bounds)
        let new = Set(blocks)
        guard new.count == blocks.count,
              blocks.allSatisfy({ (0..<rows).contains($0.row) && (0..<columns).contains($0.column) }),
              !read.contains(where: new.contains)
        else { throw .invalidLand }
        let sorted = cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        guard sorted.allSatisfy({ $0.isValid && new.contains(LandBlock(cellRow: $0.row, column: $0.column)) }),
              zip(sorted, sorted.dropFirst()).allSatisfy({ ($0.row, $0.column) < ($1.row, $1.column) })
        else { throw .invalidLand }
        var fresh: [LandCell] = []
        for cell in sorted where land.cell(row: cell.row, column: cell.column) == nil {
            if cityBuildings {
                // No number left for its building: neither, as the land's
                // growth does.
                guard let id = buildings.nextID else { break }
                buildings.append(Building.fitting(cell, id: id))
            }
            fresh.append(cell)
        }
        land.merge(fresh)
        landBlocks = (read + blocks).sorted()
        refreshLandDemand()
    }

    // MARK: - Queries

    /// Why the blocks read break a rule, or `nil`: in the world, each once
    /// and in order.
    func landBlocksProblem() -> String? {
        guard let landBlocks else { return nil }
        let rows = Land.blockRows(in: bounds), columns = Land.blockColumns(in: bounds)
        guard landBlocks.allSatisfy({ (0..<rows).contains($0.row) && (0..<columns).contains($0.column) }) else {
            return "A block of land read is outside the world."
        }
        guard zip(landBlocks, landBlocks.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return "The blocks of land read must be listed once each, by row and then column."
        }
        return nil
    }
}

/// The blocks read as runs along a row: `{"row", "column", "count"}`.
struct LandBlockRun: Codable {
    var row: Int
    var column: Int
    var count: Int

    static func runs(of blocks: [LandBlock]) -> [LandBlockRun] {
        var runs: [LandBlockRun] = []
        for block in blocks {
            if let last = runs.last, last.row == block.row, last.column + last.count == block.column {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(LandBlockRun(row: block.row, column: block.column, count: 1))
            }
        }
        return runs
    }

    /// The blocks of `runs`, or `nil` for a run of no blocks, of more than
    /// the widest world has in a row, or past the largest column.
    static func blocks(of runs: [LandBlockRun]) -> [LandBlock]? {
        var blocks: [LandBlock] = []
        for run in runs {
            guard (1...Int(WorldBounds.maximumSide / Land.blockLength)).contains(run.count), run.column >= 0, run.count <= Int.max - run.column
            else { return nil }
            for offset in 0..<run.count {
                blocks.append(LandBlock(row: run.row, column: run.column + offset))
            }
        }
        return blocks
    }
}
