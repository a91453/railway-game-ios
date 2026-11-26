import GameCore

/// The city's buildings as the plain map draws them (ARCHITECTURE decision
/// 126): every cell's building, by its use and density, and the parks and
/// farms as open ground, without choosing a layer. The city layers
/// (``CityMap``, decision 76) colour whole cells for one question at a
/// time; this is what a player sees of the town by default, so a station
/// that makes it grow shows taller buildings round it.
///
/// Derived from ``GameWorld/land`` and ``GameWorld/buildings`` and never
/// kept as a second copy of them: the map makes a new one when either
/// changes (each night at most), off the main thread, and asks it only for
/// what is in view. Nothing here is saved.
///
/// The references draw no city to port (`Ci/` shows its land from vector
/// tiles it does not ship; gap): the shapes and heights are this project's.
public struct CitySkyline: Sendable {
    /// What stands on one cell.
    public struct Lot: Hashable, Sendable {
        public let row: Int
        public let column: Int
        public let use: LandUse
        /// The building's density, 1 to 4 (existing stock, which is taller
        /// than D4 holds, draws as 4); 0 for open ground, a park or a farm.
        /// Other land whose building was bought out (decision 95) has no
        /// lot.
        public let density: Int
        /// The side of the square its building stands on, in world units
        /// (``GameWorld/cityBuildingSide(row:column:)``: its density's with
        /// the city's footprints, decision 142).
        public let side: Int64
        /// Decision 1006: how much of a full lot's houses stand on it, over
        /// 0 up to 1: a D1 lot's people and jobs over the floor its table
        /// gives them (``CitySkyline/fill(residents:jobs:density:)``), so a
        /// cell where a few live has a house or two, not a street of them;
        /// 1 for every denser lot and open ground.
        public let fill: Double

        public init(row: Int, column: Int, use: LandUse, density: Int, side: Int64 = PlacedBuildingRules.cityBuildingSide, fill: Double = 1) {
            self.row = row
            self.column = column
            self.use = use
            self.density = density
            self.side = side
            self.fill = min(1, max(0, fill))
        }

        /// Whether it is open ground rather than a building.
        public var isOpenGround: Bool {
            density == 0
        }
    }

    /// Every lot, by row and then column: north to south, so a building
    /// drawn later stands in front of the ones behind it.
    public let lots: [Lot]
    /// The world's time when it was made, so the next one can tell a night's
    /// growth (``SkylineGrowth``, decision 140) from a loaded game.
    public let time: GameTime

    public init(world: GameWorld) {
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        var lots: [Lot] = []
        lots.reserveCapacity(world.land.cells.count)
        // Decision 1006: only where the people are an official census's.
        let byPeople = world.geoAnchor != nil && Self.housesByPeople(Map3DRegionLook(world: world).buildings)
        for cell in world.land.cells where cell.row < rows && cell.column < columns {
            let building = world.buildings.building(row: cell.row, column: cell.column)
            let use = building?.use ?? cell.use
            if Self.openGround.contains(use) {
                // The city keeps a building record on every cell of land,
                // a park's and a farm's too; they draw as open ground.
                lots.append(Lot(row: cell.row, column: cell.column, use: use, density: 0))
            } else if let building {
                let density = building.kind == .existingStock ? BuildingDensity.d4.rawValue : building.density.rawValue
                lots.append(Lot(row: cell.row, column: cell.column, use: use, density: density,
                                side: world.cityBuildingSide(row: cell.row, column: cell.column),
                                fill: byPeople ? Self.fill(residents: cell.residents, jobs: cell.jobs, density: density) : 1))
            }
        }
        self.lots = lots.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        time = world.clock.now
    }

    /// A skyline of the given lots, put in drawing order.
    public init(lots: [Lot], time: GameTime) {
        self.lots = lots.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        self.time = time
    }

    /// Decision 1006: the share of a full lot's houses a lot of `density`
    /// with `residents` and `jobs` draws: on a D1 lot the floor they need
    /// (``Building/areaPerResident`` and ``Building/areaPerJob`` each)
    /// over the floor a D1 cell has (``Building/floorArea`` on each of its
    /// storeys), at most 1; on a denser lot 1, its houses full. A D1
    /// home's table (56 residents and 12 jobs) fills it exactly.
    public static func fill(residents: Int64, jobs: Int64, density: Int) -> Double {
        guard density == BuildingDensity.d1.rawValue else { return 1 }
        let floor = Double(Building.floorArea * BuildingDensity.d1.floors)
        let needed = Double(max(0, residents) * Building.areaPerResident + max(0, jobs) * Building.areaPerJob)
        return min(1, needed / floor)
    }

    /// Decision 1006: the maps whose people and jobs come from an official
    /// census on a fine grid (Japan's 500 m one, decision 1000), whose 64 m
    /// cells' counts the game's houses follow. Elsewhere (WorldPop's 1 km
    /// people spread evenly over every 64 m cell, and the blank map's
    /// towns) every lot stays full as before: the owner, 2026-11-26, 「但也要顧慮目前照官方的只有日本 日本先做 其他還在使用world pop」
    /// 「我怕會影響精確度」. A map whose people move to an official census
    /// (Taiwan's, Hong Kong's, Finland's, in the same `population.json`
    /// with its `jobs`) adds its look here in the same pull request.
    public static let censusLooks: [Map3DRegionLook.Buildings] = [.japan]

    /// Decision 1006: whether a map drawn with `buildings` lays the game's
    /// houses by its cells' people (``censusLooks``).
    public static func housesByPeople(_ buildings: Map3DRegionLook.Buildings) -> Bool {
        censusLooks.contains(buildings)
    }

    /// Decision 1006: below this ``Lot/fill`` a lot's ground is not drawn
    /// as a town's yard or paving but as the land round it (its field or
    /// forest): a house or two among the fields, not a 64 m square of yard.
    public static let thinFill = 0.25

    /// The uses drawn as open ground rather than buildings.
    public static let openGround: Set<LandUse> = [.park, .agricultural]

    public var isEmpty: Bool {
        lots.isEmpty
    }

    /// The lots whose cells `region` reaches, north to south and west to
    /// east, and those up to `rowsBelow` rows south of it: a tall building
    /// there rises into the region.
    public func lots(in region: WorldRegion, rowsBelow: Int = 0) -> [Lot] {
        guard !lots.isEmpty, region.minX.isFinite, region.minY.isFinite, region.maxX.isFinite, region.maxY.isFinite
        else { return [] }
        let length = Double(Land.cellLength)
        let firstRow = Int((region.minY / length).rounded(.down)), lastRow = Int((region.maxY / length).rounded(.down)) + max(0, rowsBelow)
        let firstColumn = Int((region.minX / length).rounded(.down)), lastColumn = Int((region.maxX / length).rounded(.down))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return [] }
        let start = firstIndex(atOrAfterRow: firstRow), end = firstIndex(atOrAfterRow: lastRow + 1)
        return lots[start..<end].filter { (firstColumn...lastColumn).contains($0.column) }
    }

    /// The first lot at or south of `row`, by halving.
    private func firstIndex(atOrAfterRow row: Int) -> Int {
        var low = 0, high = lots.count
        while low < high {
            let middle = (low + high) / 2
            if lots[middle].row < row { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// How tall a building of `density` (1–4) is drawn, as a share of its
    /// footprint's side: D1 houses low, D4 towers rising over the cells
    /// behind them. Not to scale (D1–D4 are 2, 6, 18 and 40 floors): at
    /// scale a D4 tower would cover two cells north of it, and a dense
    /// town would be a wall of columns.
    public static func heightShare(density: Int) -> Double {
        switch density {
        case ...0: 0
        case 1: 0.2
        case 2: 0.45
        case 3: 0.8
        default: 1.4
        }
    }

    /// The most rows a building rises over: a D4 tower's height, in cells.
    public static let rowsRisenOver = 1
}
