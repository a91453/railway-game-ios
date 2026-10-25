// Decision 400 B.1–B.3: the roads, on the land's 64 m grid. Each cell has
// a road or none. A blank map's roads start as a small square in the middle
// of each town; a real-world map's are the base map's, which GamePresentation
// reads cell by cell as it reads the land and hands to the world
// (``GameWorld/setRoads(_:in:)``), as it does the land: GameCore keeps only
// the result. Once a month the roads grow one cell toward the stations, and
// the player can pay for a short road from a station to the nearest one
// (``GameWorld/buildStationRoad(at:)``). Off in a new world and in saves from
// before it (save version 72); the player's new games turn it on.
//
// The references have no roads that grow by themselves (gap): the island
// city's are laid by the player a cell at a time. OpenTTD's towns grow
// their roads out from the middle (GPL-2.0, ideas only, no code); this rule
// is the project's own, with no draw at all.

/// The world's roads: which 64 m cells of ``Land``'s grid have one.
public struct RoadGrid: Hashable, Sendable {
    /// The cells with a road.
    public internal(set) var cells: Set<CellPosition>
    /// The middle cells of the towns whose roads grow toward their nearest
    /// station, in order (a blank map's); none on a real-world map, where
    /// each station draws the nearest road toward it instead.
    public internal(set) var towns: [CellPosition]
    /// The blocks whose base-map roads have been read (a real-world map's),
    /// so each is read once.
    public internal(set) var readBlocks: Set<LandBlock>

    /// How many cells round a town's middle its first roads cover each way:
    /// a square of 3 × 3 cells.
    public static let seedReach = 1
    /// How many days apart the roads grow: once a game month.
    public static let growthDays: Int64 = 30
    /// The farthest a station draws a road from, in cells each way (16 km):
    /// past it the roads leave it alone.
    public static let growthReach = 256
    /// What a station road costs a metre: $50, half the track's $100
    /// (decision 400's research 3.2).
    public static let pricePerMetre = Money(5_000)
    /// The longest station road: 512 m, eight cells in a line.
    public static let stationRoadMetres: Int64 = 512
    /// A cell's side, and the way across one corner to corner, in metres
    /// (64 × 1.414, to the metre below).
    public static let straightMetres: Int64 = 64
    public static let diagonalMetres: Int64 = 90

    public init(cells: Set<CellPosition> = [], towns: [CellPosition] = [], readBlocks: Set<LandBlock> = []) {
        self.cells = cells
        self.towns = towns
        self.readBlocks = readBlocks
    }

    /// Whether cell `row`, `column` has a road.
    public func hasRoad(row: Int, column: Int) -> Bool {
        cells.contains(CellPosition(row: row, column: column))
    }

    /// How long a road is from cell `a`'s middle to cell `b`'s, going
    /// corner to corner while both differ and then straight on.
    public static func metres(from a: CellPosition, to b: CellPosition) -> Int64 {
        let rows = Int64(abs(a.row - b.row)), columns = Int64(abs(a.column - b.column))
        let diagonal = min(rows, columns)
        return diagonal * diagonalMetres + (max(rows, columns) - diagonal) * straightMetres
    }

    /// The cells from `start` toward `end`, `start` first, `end` left out:
    /// corner to corner while both differ, then straight on.
    static func path(from start: CellPosition, to end: CellPosition) -> [CellPosition] {
        var path: [CellPosition] = []
        var row = start.row, column = start.column
        while row != end.row || column != end.column {
            path.append(CellPosition(row: row, column: column))
            row += (end.row - row).signum()
            column += (end.column - column).signum()
        }
        return path
    }

    /// The square distance between two cells, in cells.
    static func squared(_ a: CellPosition, _ b: CellPosition) -> Int {
        let rows = a.row - b.row, columns = a.column - b.column
        return rows * rows + columns * columns
    }

    /// The road cell nearest `target` within `reach` cells each way: the
    /// least square distance, then the lower row and column; `nil` when
    /// there is none.
    func nearestRoad(to target: CellPosition, within reach: Int) -> CellPosition? {
        guard !cells.isEmpty else { return nil }
        var best: (squared: Int, cell: CellPosition)?
        var ring = 0
        // A cell of ring k is at least k cells away, so once k² passes the
        // best found no farther ring holds a nearer one.
        while ring <= reach, best.map({ ring * ring <= $0.squared }) ?? true {
            for cell in Self.ring(ring, round: target) where cells.contains(cell) {
                let squared = Self.squared(cell, target)
                if best.map({ (squared, cell) < ($0.squared, $0.cell) }) ?? true {
                    best = (squared, cell)
                }
            }
            ring += 1
        }
        return best?.cell
    }

    /// The cells `k` cells from `middle` along the farther of the row and
    /// the column (the square ring), in no particular order.
    static func ring(_ k: Int, round middle: CellPosition) -> [CellPosition] {
        guard k > 0 else { return [middle] }
        var ring: [CellPosition] = []
        ring.reserveCapacity(8 * k)
        for offset in -k...k {
            ring.append(CellPosition(row: middle.row - k, column: middle.column + offset))
            ring.append(CellPosition(row: middle.row + k, column: middle.column + offset))
        }
        for offset in (-k + 1)...(k - 1) {
            ring.append(CellPosition(row: middle.row + offset, column: middle.column - k))
            ring.append(CellPosition(row: middle.row + offset, column: middle.column + k))
        }
        return ring
    }

    /// Why the roads break a rule in a world of `bounds`, or `nil`: every
    /// cell, town and block in the world.
    func problem(in bounds: WorldBounds) -> String? {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        func inWorld(_ cell: CellPosition) -> Bool { (0..<rows).contains(cell.row) && (0..<columns).contains(cell.column) }
        guard cells.allSatisfy(inWorld), towns.allSatisfy(inWorld) else { return "A road or a town's middle is outside the world." }
        let blockRows = Land.blockRows(in: bounds), blockColumns = Land.blockColumns(in: bounds)
        guard readBlocks.allSatisfy({ (0..<blockRows).contains($0.row) && (0..<blockColumns).contains($0.column) }) else {
            return "A block whose roads were read is outside the world."
        }
        return nil
    }
}

/// What a station road costs (``GameWorld/stationRoadQuote(at:)``).
public struct StationRoadQuote: Hashable, Sendable {
    /// The cells the road takes, from the station's own to the one beside
    /// the road it joins.
    public let cells: [CellPosition]
    /// The road it joins.
    public let joins: CellPosition
    public let metres: Int64
    public let price: Money
}

extension GameWorld {
    // MARK: - Commands

    /// Turns the roads on (decision 400): a 3 × 3 square of cells round
    /// each of `towns` (a blank map's town middles, ``Land/townCentres(seed:in:)``),
    /// off the water and steep slopes, and those towns' roads grow toward
    /// their nearest station once a month. A real-world map passes none:
    /// its roads come from the base map (``setRoads(_:in:)``) and each
    /// station draws the nearest toward it. Any roads the world had are
    /// replaced. Points outside the world are left out.
    public mutating func enableRoads(towns: [PlanPoint] = []) {
        var grid = RoadGrid()
        seedRoads(of: towns, in: &grid)
        roads = grid
    }

    /// Adds `towns` to `grid`'s, each with the 3 × 3 square of cells round
    /// its middle that are off the water and steep slopes; a town outside
    /// the world, or in the cell of one `grid` has, is left out.
    func seedRoads(of towns: [PlanPoint], in grid: inout RoadGrid) {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        for town in towns where town.x >= 0 && town.y >= 0 {
            let middle = CellPosition(row: Int(town.y / Land.cellLength), column: Int(town.x / Land.cellLength))
            // Two towns in one cell are one: its roads grow once a month.
            guard (0..<rows).contains(middle.row), (0..<columns).contains(middle.column), !grid.towns.contains(middle) else { continue }
            grid.towns.append(middle)
            let reach = RoadGrid.seedReach
            for row in (middle.row - reach)...(middle.row + reach) {
                for column in (middle.column - reach)...(middle.column + reach) {
                    if canHaveRoad(row: row, column: column, rows: rows, columns: columns) {
                        grid.cells.insert(CellPosition(row: row, column: column))
                    }
                }
            }
        }
    }

    /// The middles of the towns a bought `tile` grows on a blank map
    /// (``buyMapTile(_:passingMilestone:)``), where they lie in the world.
    func townCentres(of tile: MapTile, seed: UInt32) -> [PlanPoint] {
        let length = MapExpansion.tileLength
        return Land.townCentres(seed: MapExpansion.townSeed(of: tile, from: seed), in: .standard).map {
            PlanPoint(x: Int64(tile.column) * length + $0.x, y: Int64(tile.row) * length + $0.y)
        }
    }

    /// Gives the towns of the tiles a blank map's company bought their
    /// roads, where a save of version 72 bought them without (decision
    /// 400's sequel): each tile owned with none of the roads' towns in it,
    /// by row and then column. The tile the company started on holds the
    /// map's own towns, so it is left as it is; run again it changes
    /// nothing.
    mutating func seedBoughtTilesRoads() {
        guard var grid = roads, let expansion = mapExpansion, let seed = expansion.townSeed else { return }
        for tile in expansion.owned where !grid.towns.contains(where: { MapExpansion.tile(ofCellRow: $0.row, column: $0.column) == tile }) {
            seedRoads(of: townCentres(of: tile, seed: seed), in: &grid)
        }
        roads = grid
    }

    /// Gives the cells of `blocks` the base map's roads: each of `cells`
    /// has one from now on, and the blocks are read (``RoadGrid/readBlocks``).
    /// Roads the blocks had already, grown or built, stay.
    ///
    /// - Throws: ``GameError/roadsNotEnabled``, or ``GameError/invalidRoads``
    ///   for a block outside the world or a cell outside the blocks.
    public mutating func setRoads(_ cells: [CellPosition], in blocks: [LandBlock]) throws(GameError) {
        guard var grid = roads else { throw .roadsNotEnabled }
        let blockRows = Land.blockRows(in: bounds), blockColumns = Land.blockColumns(in: bounds)
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let wanted = Set(blocks)
        guard wanted.allSatisfy({ (0..<blockRows).contains($0.row) && (0..<blockColumns).contains($0.column) }),
              cells.allSatisfy({ (0..<rows).contains($0.row) && (0..<columns).contains($0.column)
                  && wanted.contains(LandBlock(cellRow: $0.row, column: $0.column)) })
        else { throw .invalidRoads }
        grid.cells.formUnion(cells)
        grid.readBlocks.formUnion(wanted)
        roads = grid
    }

    /// Builds a road from station `id` to the nearest road and pays for it
    /// (``stationRoadQuote(at:)``), booked as capital spending for a managed
    /// company (it is no asset record, as a freight yard is not).
    ///
    /// - Throws: whatever ``stationRoadQuote(at:)`` throws, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildStationRoad(at id: StationID) throws(GameError) -> StationRoadQuote {
        let quote = try stationRoadQuote(at: id)
        guard var grid = roads else { throw .roadsNotEnabled }
        try economy.spend(quote.price)
        if accounts.mode == .management {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + quote.price }
        }
        grid.cells.formUnion(quote.cells)
        roads = grid
        return quote
    }

    // MARK: - Queries

    /// The road from station `id` to the nearest road cell (the least
    /// metres, then the lower row and column): corner to corner, then
    /// straight on, at ``RoadGrid/pricePerMetre``.
    ///
    /// - Throws, checked in this order: ``GameError/roadsNotEnabled``,
    ///   ``GameError/unknownStation(_:)``, ``GameError/stationOnRoad(_:)``
    ///   when its cell has a road already, ``GameError/roadTooFar`` when
    ///   none is within ``RoadGrid/stationRoadMetres``, or
    ///   ``GameError/onWater(row:column:)`` when the way crosses water.
    public func stationRoadQuote(at id: StationID) throws(GameError) -> StationRoadQuote {
        guard let grid = roads else { throw .roadsNotEnabled }
        guard let station = station(id: id) else { throw .unknownStation(id) }
        let start = roadCell(of: station.point)
        guard !grid.cells.contains(start) else { throw .stationOnRoad(id) }
        let reach = Int(RoadGrid.stationRoadMetres / RoadGrid.straightMetres)
        var best: (metres: Int64, cell: CellPosition)?
        for row in (start.row - reach)...(start.row + reach) {
            for column in (start.column - reach)...(start.column + reach) {
                let cell = CellPosition(row: row, column: column)
                guard grid.cells.contains(cell) else { continue }
                let metres = RoadGrid.metres(from: start, to: cell)
                guard metres <= RoadGrid.stationRoadMetres else { continue }
                if best.map({ (metres, cell) < ($0.metres, $0.cell) }) ?? true {
                    best = (metres, cell)
                }
            }
        }
        guard let best else { throw .roadTooFar }
        let path = RoadGrid.path(from: start, to: best.cell)
        if !terrain.isEmpty, let wet = path.first(where: { terrain.isWater(row: $0.row, column: $0.column) }) {
            throw .onWater(row: wet.row, column: wet.column)
        }
        return StationRoadQuote(cells: path, joins: best.cell, metres: best.metres, price: Money(best.metres * RoadGrid.pricePerMetre.amount))
    }

    /// The cell of the road grid `point` lies in.
    func roadCell(of point: PlanPoint) -> CellPosition {
        CellPosition(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
    }

    /// Whether a road may grow into cell `row`, `column`: in the world, off
    /// the water and steep slopes.
    func canHaveRoad(row: Int, column: Int, rows: Int, columns: Int) -> Bool {
        (0..<rows).contains(row) && (0..<columns).contains(column)
            && (terrain.isEmpty || !(terrain.isWater(row: row, column: column) || terrain.isSteep(row: row, column: column)))
    }

    // MARK: - Growth

    /// The roads grow (decision 400 B.2), at the midnight that begins every
    /// ``RoadGrid/growthDays``-th day. Each town in turn, toward the station
    /// nearest its middle (the lower station ID of equally near ones), and
    /// then each other station in turn (decision 400's sequel), or, on a
    /// map with no towns, each station in turn, toward itself: from
    /// the road cell nearest the station's cell (``RoadGrid/nearestRoad(to:within:)``)
    /// one cell, into one of its eight neighbours nearer the station, in
    /// the world and off the water and steep slopes; a cell where someone
    /// lives or works first, then the nearest the station, then the lower
    /// row and column. None grows toward a station whose cell has a road,
    /// or with no road within ``RoadGrid/growthReach``. No draw.
    mutating func growRoads() {
        guard var grid = roads, !stations.isEmpty else { return }
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let targets: [CellPosition]
        if grid.towns.isEmpty {
            targets = stations.map { roadCell(of: $0.point) }
        } else {
            let towns = grid.towns.map { town in
                var nearest: (squared: Int, id: StationID, cell: CellPosition)?
                for station in stations {
                    let cell = roadCell(of: station.point), squared = RoadGrid.squared(cell, town)
                    if nearest.map({ (squared, station.id.rawValue) < ($0.squared, $0.id.rawValue) }) ?? true {
                        nearest = (squared, station.id, cell)
                    }
                }
                return nearest!.cell
            }
            // Decision 400's sequel: then every other station, so none
            // waits for ever because no town is nearer it than another.
            let drawn = Set(towns)
            targets = towns + stations.map { roadCell(of: $0.point) }.filter { !drawn.contains($0) }
        }
        for target in targets where !grid.cells.contains(target) {
            guard let from = grid.nearestRoad(to: target, within: RoadGrid.growthReach) else { continue }
            let here = RoadGrid.squared(from, target)
            var next: (rank: Int, squared: Int, cell: CellPosition)?
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let cell = CellPosition(row: from.row + dr, column: from.column + dc)
                    let squared = RoadGrid.squared(cell, target)
                    guard squared < here, !grid.cells.contains(cell),
                          canHaveRoad(row: cell.row, column: cell.column, rows: rows, columns: columns) else { continue }
                    let peopled = land.cell(row: cell.row, column: cell.column).map { $0.residents + $0.jobs > 0 } ?? false
                    let rank = peopled ? 0 : 1
                    if next.map({ (rank, squared, cell) < ($0.rank, $0.squared, $0.cell) }) ?? true {
                        next = (rank, squared, cell)
                    }
                }
            }
            if let next { grid.cells.insert(next.cell) }
        }
        roads = grid
    }
}

// MARK: - Codable

extension RoadGrid: Codable {
    private enum CodingKeys: String, CodingKey {
        case cells, towns, blocks
    }

    /// Runs of cells along a row: `{"row", "column", "count"}`.
    private struct Run: Codable {
        var row: Int
        var column: Int
        var count: Int
    }

    private struct Town: Codable {
        var row: Int
        var column: Int
    }

    /// `{"cells": [runs], "towns": [{"row", "column"}], "blocks": [runs]}`,
    /// the cells' runs by row and then column, each key left out when it
    /// has none. The world checks they lie in its bounds.
    public init(from decoder: any Decoder) throws {
        let side = Int(WorldBounds.maximumSide / Land.cellLength), blocks = Int(WorldBounds.maximumSide / Land.blockLength)
        try self.init(from: decoder, cellLimit: side * side, blockLimit: blocks * blocks)
    }

    /// As ``init(from:)``, refusing more than `cellLimit` cells or
    /// `blockLimit` blocks in all before spreading the runs out (decision
    /// 400's later point 2): the world's own.
    init(from decoder: any Decoder, cellLimit: Int, blockLimit: Int) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var cells: Set<CellPosition> = []
        var last: CellPosition?
        // No cell past the widest world's, so no sum below can overflow.
        let side = Int(WorldBounds.maximumSide / Land.cellLength)
        let runs = try container.decodeIfPresent([Run].self, forKey: .cells) ?? []
        var total = 0
        for run in runs where run.count > 0 {
            guard run.count <= cellLimit - total else {
                throw DecodingError.dataCorruptedError(forKey: .cells, in: container, debugDescription: "The roads are more cells than the world has.")
            }
            total += run.count
        }
        for run in runs {
            guard run.count >= 1, (0..<side).contains(run.row), (0..<side).contains(run.column), run.count <= side - run.column,
                  last.map({ ($0.row, $0.column) < (run.row, run.column) }) ?? true
            else {
                throw DecodingError.dataCorruptedError(forKey: .cells, in: container, debugDescription: "Roads must be runs of cells, in order, apart.")
            }
            for offset in 0..<run.count {
                cells.insert(CellPosition(row: run.row, column: run.column + offset))
            }
            last = CellPosition(row: run.row, column: run.column + run.count)
        }
        self.cells = cells
        towns = (try container.decodeIfPresent([Town].self, forKey: .towns) ?? []).map { CellPosition(row: $0.row, column: $0.column) }
        guard Set(towns).count == towns.count else {
            throw DecodingError.dataCorruptedError(forKey: .towns, in: container, debugDescription: "Each town's cell must be named once.")
        }
        let blockRuns = try container.decodeIfPresent([LandBlockRun].self, forKey: .blocks) ?? []
        guard LandBlockRun.count(of: blockRuns, atMost: blockLimit) else {
            throw DecodingError.dataCorruptedError(forKey: .blocks, in: container, debugDescription: "The blocks whose roads were read are more blocks than the world has.")
        }
        guard let blocks = LandBlockRun.blocks(of: blockRuns),
              zip(blocks, blocks.dropFirst()).allSatisfy({ $0 < $1 })
        else {
            throw DecodingError.dataCorruptedError(forKey: .blocks, in: container, debugDescription: "The blocks whose roads were read must be in order, once each.")
        }
        readBlocks = Set(blocks)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var runs: [Run] = []
        for cell in cells.sorted() {
            if let last = runs.last, last.row == cell.row, last.column + last.count == cell.column {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(Run(row: cell.row, column: cell.column, count: 1))
            }
        }
        if !runs.isEmpty {
            try container.encode(runs, forKey: .cells)
        }
        if !towns.isEmpty {
            try container.encode(towns.map { Town(row: $0.row, column: $0.column) }, forKey: .towns)
        }
        if !readBlocks.isEmpty {
            try container.encode(LandBlockRun.runs(of: readBlocks.sorted()), forKey: .blocks)
        }
    }
}
