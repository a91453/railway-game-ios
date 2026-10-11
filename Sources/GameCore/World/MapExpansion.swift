// Buying the map (ARCHITECTURE decision 160): a world can be split into
// tiles the size of a new game's map, 16.384 km a side, of which the
// company owns some. It builds only on the tiles it owns: track, stations,
// its buildings and zones. It starts with one and buys the others one at a
// time, each next to one it owns, for a price that rises with how many it
// has, once its best day's riders have passed the milestone for one more.
// A bought tile on a blank map grows towns of its own, drawn as a new
// game's are, so the map opens up as the railway carries more people.
// The stations by the edge of the land it owns are the outside connections
// (decision 137): a tile bought beyond one makes it an ordinary station,
// and the towns there the real trips instead.
//
// The owner's references have nothing to port (gap): `Ci/`'s "扩建"
// buys capacity quotas for stations, airports and halls
// (`hsr.capacity.platform_expanded`, `metroQuotaFormatValue`), not land,
// and the reference pack has no map that grows. Cities: Skylines buys
// tiles of its map once milestones are reached; it is not open source,
// so only the idea is taken. The tile size, prices and milestones are this
// project's, chosen by `BalanceReportTests`.

/// One tile of a world's map that can be bought (decision 160): its row,
/// from the world's north edge, and column, from its west edge, in tiles of
/// ``MapExpansion/tileLength``.
public struct MapTile: Hashable, Comparable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static func < (lhs: MapTile, rhs: MapTile) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }

    /// The four tiles beside it, north, west, east and south: some may lie
    /// outside the world.
    public var neighbours: [MapTile] {
        [MapTile(row: row - 1, column: column), MapTile(row: row, column: column - 1),
         MapTile(row: row, column: column + 1), MapTile(row: row + 1, column: column)]
    }
}

/// The tiles a company owns of a map it buys as it grows (decision 160),
/// its best day's riders, and the seed a bought tile's towns are drawn
/// from.
public struct MapExpansion: Hashable, Sendable {
    /// A tile's side: 2^20 units, 16.384 km, a new game's map
    /// (``WorldBounds/standard``).
    public static let tileLength: Int64 = 1 << 20
    /// What each tile owned adds to the price of the next: $5,000,000, so
    /// the second costs $5 million, the third $10 million, and the last of
    /// a blank map's 25 $120 million.
    public static let priceStep: Money = 500_000_000
    /// The riders in a day each tile owned beyond the first needs: a
    /// company may own one tile, and one more for every 100,000 riders of
    /// its best day. A line between a new game's first two towns carries
    /// some 60,000 a day and its best day passes 100,000 around day 19
    /// (`BalanceReportTests.testBuyingTheMap`), when it has saved the
    /// second tile's price; the third needs a second line.
    public static let ridersStep: Int64 = 100_000

    /// The tiles owned, by row and then column, each once: at least one,
    /// each beside another (they were bought next to one owned).
    public internal(set) var owned: [MapTile]
    /// The most riders who paid a fare in one day since it began.
    public internal(set) var bestDayRiders: Int64
    /// The seed the towns of a tile bought are drawn from (a blank map), or
    /// `nil` for a map that brings its own land.
    public let townSeed: UInt32?

    public init(owned: [MapTile], bestDayRiders: Int64 = 0, townSeed: UInt32?) {
        self.owned = owned.sorted()
        self.bestDayRiders = bestDayRiders
        self.townSeed = townSeed
    }

    /// Whether `tile` is owned.
    public func owns(_ tile: MapTile) -> Bool {
        var low = 0, high = owned.count
        while low < high {
            let middle = (low + high) / 2
            if owned[middle] == tile { return true }
            if owned[middle] < tile { low = middle + 1 } else { high = middle }
        }
        return false
    }

    /// How many tiles the company may own with its best day: one, and one
    /// more for every ``ridersStep`` riders.
    public var allowance: Int {
        1 + Int(min(bestDayRiders / Self.ridersStep, Int64(Int32.max)))
    }

    /// The riders of a day the company needs to own `count` tiles.
    public static func ridersNeeded(toOwn count: Int) -> Int64 {
        Int64(max(0, count - 1)) * ridersStep
    }

    /// What the next tile costs: ``priceStep`` for each tile owned.
    public var nextPrice: Money {
        Money(Int64(owned.count) * Self.priceStep.amount)
    }

    /// The seed of the towns of `tile`, from the map's `seed`: a hash of
    /// both, so each tile has towns of its own.
    static func townSeed(of tile: MapTile, from seed: UInt32) -> UInt32 {
        SeedDraw(seed: seed).hash("tile.\(tile.row).\(tile.column)")
    }

    /// How many rows and columns of tiles cover `bounds`: the last of each
    /// may reach past its edge.
    public static func rows(in bounds: WorldBounds) -> Int {
        Int((bounds.height + tileLength - 1) / tileLength)
    }

    public static func columns(in bounds: WorldBounds) -> Int {
        Int((bounds.width + tileLength - 1) / tileLength)
    }

    /// The tile `point` lies in.
    public static func tile(at point: PlanPoint) -> MapTile {
        MapTile(row: Int(point.y / tileLength), column: Int(point.x / tileLength))
    }

    /// The tile cell `row`, `column` of the land lies in.
    static func tile(ofCellRow row: Int, column: Int) -> MapTile {
        let cells = Int(tileLength / Land.cellLength)
        return MapTile(row: row / cells, column: column / cells)
    }
}

/// The ground a tile covers in a world: `minX ..< maxX` by `minY ..< maxY`
/// in world units, the last row and column cut at the world's edge.
public struct MapTileArea: Hashable, Sendable {
    public let minX: Int64
    public let minY: Int64
    public let maxX: Int64
    public let maxY: Int64
}

/// What buying a tile would cost and change (decision 160), for the screen
/// that offers it.
public struct MapTileQuote: Hashable, Sendable {
    public let tile: MapTile
    public let price: Money
    /// The riders of a day the company needs to buy it, and its best day.
    public let ridersNeeded: Int64
    public let bestDayRiders: Int64
    /// The outside connections that would become ordinary stations.
    public let outsideConnectionsLost: [StationID]

    /// Whether its best day has passed the milestone.
    public var isUnlocked: Bool {
        bestDayRiders >= ridersNeeded
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Splits the world into tiles of ``MapExpansion/tileLength`` of which
    /// the company owns only `tile` (decision 160): it builds only there
    /// until it buys more (``buyMapTile(_:)``). A tile bought grows towns
    /// drawn from `townSeed` (a blank map), or none with `nil`. Turning it
    /// on again starts over from `tile`, the best day forgotten. Free.
    ///
    /// - Throws: ``GameError/invalidMapTile`` for a tile outside the world,
    ///   or when a station, a track node, one of the company's buildings or
    ///   a zone lies outside it.
    public mutating func enableMapExpansion(owning tile: MapTile, townSeed: UInt32?) throws(GameError) {
        let expansion = MapExpansion(owned: [tile], townSeed: townSeed)
        guard isOnMap(tile), mapExpansionProblem(expansion) == nil else { throw .invalidMapTile }
        mapExpansion = expansion
        passengerPlan = PassengerPlanCache()
        refreshLandDemand()
    }

    /// Buys `tile` (decision 160): the company may build there from now
    /// on. It pays ``MapExpansion/nextPrice``, recorded as land that is not
    /// written down; free play needs no milestone and keeps no record, but
    /// pays as it does for track. On a blank map the tile grows its towns
    /// (``Land/towns(seed:in:)`` drawn from the tile's own seed), and their
    /// buildings, but not where land or the company's buildings already
    /// are, nor on water or steep slopes. The stations by its side stop
    /// being outside connections.
    ///
    /// - Throws, checked in this order:
    ///   ``GameError/mapExpansionNotEnabled``;
    ///   ``GameError/invalidMapTile`` for a tile outside the world;
    ///   ``GameError/mapTileOwned`` for one owned already;
    ///   ``GameError/mapTileNotAdjacent`` unless it is beside one owned;
    ///   ``GameError/mapExpansionLocked(ridersNeeded:)`` for a managed
    ///   company whose best day has not passed the milestone for one more
    ///   tile; ``GameError/insufficientFunds(required:available:)``.
    public mutating func buyMapTile(_ tile: MapTile) throws(GameError) {
        guard var expansion = mapExpansion else { throw .mapExpansionNotEnabled }
        guard isOnMap(tile) else { throw .invalidMapTile }
        guard !expansion.owns(tile) else { throw .mapTileOwned }
        guard tile.neighbours.contains(where: expansion.owns) else { throw .mapTileNotAdjacent }
        if accounts.mode == .management, expansion.owned.count >= expansion.allowance {
            throw .mapExpansionLocked(ridersNeeded: MapExpansion.ridersNeeded(toOwn: expansion.owned.count + 1))
        }
        let price = expansion.nextPrice
        try economy.spend(price)
        expansion.owned = (expansion.owned + [tile]).sorted()
        mapExpansion = expansion
        acquireAsset(.mapTile, owner: mapTileNumber(tile), cost: price)
        if let seed = expansion.townSeed {
            foundTowns(in: tile, seed: MapExpansion.townSeed(of: tile, from: seed))
        }
        passengerPlan = PassengerPlanCache()
        refreshLandDemand()
    }

    // MARK: - Queries

    /// The rows and columns of tiles the world is split into.
    public var mapTileRows: Int { MapExpansion.rows(in: bounds) }
    public var mapTileColumns: Int { MapExpansion.columns(in: bounds) }

    /// Whether `tile` lies in the world.
    public func isOnMap(_ tile: MapTile) -> Bool {
        (0..<mapTileRows).contains(tile.row) && (0..<mapTileColumns).contains(tile.column)
    }

    /// The ground `tile` covers, cut at the world's edge.
    public func mapArea(of tile: MapTile) -> MapTileArea {
        let length = MapExpansion.tileLength
        return MapTileArea(
            minX: Int64(tile.column) * length, minY: Int64(tile.row) * length,
            maxX: min(bounds.width, Int64(tile.column + 1) * length), maxY: min(bounds.height, Int64(tile.row + 1) * length)
        )
    }

    /// Whether the company may build at `point`: it lies in a tile it owns,
    /// or the world's map is not bought (decision 160). Says nothing of the
    /// world's bounds.
    public func ownsGround(at point: PlanPoint) -> Bool {
        guard let mapExpansion else { return true }
        return mapExpansion.owns(MapExpansion.tile(at: point))
    }

    /// Whether `tile` is owned: every tile in the world is, while the
    /// world's map is not bought.
    public func ownsMapTile(_ tile: MapTile) -> Bool {
        guard isOnMap(tile) else { return false }
        return mapExpansion?.owns(tile) ?? true
    }

    /// The tiles the company could buy next: beside one it owns, not owned,
    /// in the world; by row and then column. Empty while the map is not
    /// bought.
    public func mapTilesForSale() -> [MapTile] {
        guard let mapExpansion else { return [] }
        var found: Set<MapTile> = []
        for tile in mapExpansion.owned {
            for next in tile.neighbours where isOnMap(next) && !mapExpansion.owns(next) {
                found.insert(next)
            }
        }
        return found.sorted()
    }

    /// What buying `tile` would cost and change, or `nil` for one not for
    /// sale (``mapTilesForSale()``). Free play needs no riders.
    public func mapTileQuote(_ tile: MapTile) -> MapTileQuote? {
        guard let mapExpansion, mapTilesForSale().contains(tile) else { return nil }
        let needed = accounts.mode == .management ? MapExpansion.ridersNeeded(toOwn: mapExpansion.owned.count + 1) : 0
        var after = self
        after.mapExpansion?.owned = (mapExpansion.owned + [tile]).sorted()
        let lost = stations.filter { isOutsideConnection($0.id) && !after.isOutsideConnection($0.id) }.map(\.id)
        return MapTileQuote(
            tile: tile, price: mapExpansion.nextPrice, ridersNeeded: needed, bestDayRiders: mapExpansion.bestDayRiders, outsideConnectionsLost: lost
        )
    }

    /// The first tile the company does not own that `points`, a line from
    /// each to the next, pass over; `nil` when they keep to its tiles (or
    /// the map is not bought). A line that only grazes a tile's last unit
    /// counts.
    func firstTileNotOwned(along points: [PlanPoint]) -> MapTile? {
        guard let mapExpansion else { return nil }
        if let point = points.first(where: { !mapExpansion.owns(MapExpansion.tile(at: $0)) }) {
            return MapExpansion.tile(at: point)
        }
        for (a, b) in zip(points, points.dropFirst()) {
            let low = MapExpansion.tile(at: PlanPoint(x: min(a.x, b.x), y: min(a.y, b.y)))
            let high = MapExpansion.tile(at: PlanPoint(x: max(a.x, b.x), y: max(a.y, b.y)))
            for row in low.row...high.row {
                for column in low.column...high.column {
                    let tile = MapTile(row: row, column: column)
                    guard !mapExpansion.owns(tile) else { continue }
                    let area = mapArea(of: tile)
                    if Self.segment(a, b, touchesMinX: area.minX, minY: area.minY, maxX: area.maxX - 1, maxY: area.maxY - 1) {
                        return tile
                    }
                }
            }
        }
        return nil
    }

    /// The first tile the company does not own that the rectangle
    /// `minX ..< maxX` by `minY ..< maxY` covers part of, by row and then
    /// column; `nil` when it keeps to its tiles (or the map is not bought).
    func firstTileNotOwned(minX: Int64, minY: Int64, maxX: Int64, maxY: Int64) -> MapTile? {
        guard let mapExpansion, minX < maxX, minY < maxY else { return nil }
        let low = MapExpansion.tile(at: PlanPoint(x: minX, y: minY))
        let high = MapExpansion.tile(at: PlanPoint(x: maxX - 1, y: maxY - 1))
        for row in low.row...high.row {
            for column in low.column...high.column where !mapExpansion.owns(MapTile(row: row, column: column)) {
                return MapTile(row: row, column: column)
            }
        }
        return nil
    }

    /// The first tile the company does not own that the cells `rows` ×
    /// `columns` of the land lie in part of, or `nil`.
    func firstTileNotOwned(cellRows rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> MapTile? {
        firstTileNotOwned(
            minX: Int64(columns.lowerBound) * Land.cellLength, minY: Int64(rows.lowerBound) * Land.cellLength,
            maxX: Int64(columns.upperBound + 1) * Land.cellLength, maxY: Int64(rows.upperBound + 1) * Land.cellLength
        )
    }

    /// Whether the straight line from `a` to `b` meets the rectangle
    /// `minX ... maxX` by `minY ... maxY`, edges included: their boxes
    /// overlap, and the rectangle's corners are not all on one side of the
    /// line. Exact in whole units (products below 2^52 in a world).
    static func segment(_ a: PlanPoint, _ b: PlanPoint, touchesMinX minX: Int64, minY: Int64, maxX: Int64, maxY: Int64) -> Bool {
        guard max(a.x, b.x) >= minX, min(a.x, b.x) <= maxX, max(a.y, b.y) >= minY, min(a.y, b.y) <= maxY else { return false }
        let dx = b.x - a.x, dy = b.y - a.y
        let sides = [(minX, minY), (maxX, minY), (minX, maxY), (maxX, maxY)].map { x, y in
            (dx * (y - a.y) - dy * (x - a.x)).signum()
        }
        return !(sides.allSatisfy { $0 > 0 } || sides.allSatisfy { $0 < 0 })
    }

    /// The tile's number for its asset record: row by row from the north
    /// west.
    func mapTileNumber(_ tile: MapTile) -> Int {
        tile.row * mapTileColumns + tile.column
    }

    // MARK: - Recording

    /// Keeps `day`'s riders as the best day, if it is (decision 160), once
    /// the day is settled.
    mutating func recordBestDay(endingWith day: Int64) {
        guard let best = mapExpansion?.bestDayRiders else { return }
        let riders = accounts.days.first { $0.day == day }?.fareTrips ?? 0
        if riders > best {
            mapExpansion?.bestDayRiders = riders
        }
    }

    /// Grows `tile`'s towns, drawn from `seed` as a new game's map draws
    /// them (``Land/towns(seed:in:)``) and laid in the tile, with their
    /// buildings: not on a cell with land already, one the company's
    /// buildings claim, water or a steep slope. What is read in is not
    /// growth (decision 139).
    private mutating func foundTowns(in tile: MapTile, seed: UInt32) {
        let cells = Int(MapExpansion.tileLength / Land.cellLength)
        let rowOffset = tile.row * cells, columnOffset = tile.column * cells
        let cellRows = Land.rows(in: bounds), cellColumns = Land.columns(in: bounds)
        var fresh: [LandCell] = []
        for cell in Land.towns(seed: seed, in: .standard).cells {
            let row = cell.row + rowOffset, column = cell.column + columnOffset
            guard row < cellRows, column < cellColumns, land.cell(row: row, column: column) == nil,
                  !terrain.isWater(row: row, column: column), !terrain.isSteep(row: row, column: column)
            else { continue }
            let placed = LandCell(row: row, column: column, use: cell.use, residents: cell.residents, jobs: cell.jobs)
            guard !isClaimedByPlacedBuilding(row: row, column: column, side: cityBuildingSide(for: placed)) else { continue }
            if cityBuildings {
                guard let id = buildings.nextID else { break }
                buildings.append(Building.fitting(placed, id: id))
            }
            fresh.append(placed)
        }
        keepCityMix(with: fresh, over: land.cells.reduce(0) { $0 + $1.residents })
        land.merge(fresh)
    }

    // MARK: - Validation

    /// Why `expansion` does not fit the world, or `nil`: its tiles in the
    /// world, listed once each in order, joined to each other; everything
    /// the company built on them (its stations, track nodes and the
    /// control points of its curves, its buildings and zones); its best day
    /// not below zero.
    func mapExpansionProblem(_ expansion: MapExpansion? = nil) -> String? {
        guard let expansion = expansion ?? mapExpansion else { return nil }
        let owned = expansion.owned
        guard !owned.isEmpty, owned.allSatisfy(isOnMap), zip(owned, owned.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return "The tiles of the map owned must be in the world, listed once each, by row and then column."
        }
        var reached: Set<MapTile> = [owned[0]], frontier = [owned[0]]
        while let tile = frontier.popLast() {
            for next in tile.neighbours where expansion.owns(next) && reached.insert(next).inserted {
                frontier.append(next)
            }
        }
        guard reached.count == owned.count else { return "The tiles of the map owned must each be beside another." }
        guard expansion.bestDayRiders >= 0 else { return "The best day's riders must not be below zero." }
        func owns(_ point: PlanPoint) -> Bool { expansion.owns(MapExpansion.tile(at: point)) }
        guard stations.allSatisfy({ owns($0.point) }), network.nodes.allSatisfy({ owns($0.position.plan) }),
              network.edges.allSatisfy({ $0.curve.controlPoints.allSatisfy(owns) })
        else { return "The company's railway stands on a tile of the map it does not own." }
        let corners = placedBuildings.flatMap { building in
            [PlanPoint(x: building.minX, y: building.minY), PlanPoint(x: building.maxX - 1, y: building.maxY - 1),
             PlanPoint(x: building.minX, y: building.maxY - 1), PlanPoint(x: building.maxX - 1, y: building.minY)]
        }
        guard corners.allSatisfy(owns) else { return "One of the company's buildings stands on a tile of the map it does not own." }
        guard zones.cells.allSatisfy({ expansion.owns(MapExpansion.tile(ofCellRow: $0.row, column: $0.column)) }) else {
            return "A zone lies on a tile of the map the company does not own."
        }
        return nil
    }
}

// MARK: - Codable

extension MapTile: Codable {
    /// `[row, column]`.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        row = try container.decode(Int.self)
        column = try container.decode(Int.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A tile of the map is [row, column].")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(row)
        try container.encode(column)
    }
}

extension MapExpansion: Codable {
    private enum CodingKeys: String, CodingKey {
        case owned, bestDayRiders, townSeed
    }

    /// `{"owned": [[row, column], …], "bestDayRiders", "townSeed"}`, the
    /// best day left out at 0 and the seed without one. The world checks
    /// the tiles fit it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owned = try container.decode([MapTile].self, forKey: .owned)
        bestDayRiders = try container.decodeIfPresent(Int64.self, forKey: .bestDayRiders) ?? 0
        townSeed = try container.decodeIfPresent(UInt32.self, forKey: .townSeed)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owned, forKey: .owned)
        if bestDayRiders != 0 {
            try container.encode(bestDayRiders, forKey: .bestDayRiders)
        }
        try container.encodeIfPresent(townSeed, forKey: .townSeed)
    }
}
