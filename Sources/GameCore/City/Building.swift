// City buildings (Phase 6c-1, ARCHITECTURE decision 74): the homes, shops
// and offices the city puts up on its land, each one cell of land, and how
// many residents and jobs each can hold.
//
// The owner's references have no capacity to port (the study,
// `docs/research/PHASE6C_BUILDINGS_STUDY.md` in PR #174, §4 and §11): `Ci/`
// draws buildings from vector tiles it does not ship and extrudes them by
// height alone; `Railway/` and `taipei_gta_reference` give buildings
// floors, footprints and models but no residents or jobs. So the table and
// the rules are this project's (gap), as the study's §5 proposes and the
// author settled:
//
// - the city puts up and (from 6c-2) raises its ordinary buildings itself;
//   the player builds none (the company's buildings are Phase 7);
// - a building is its number, kind, use, density and the cells it stands
//   on: no position, rotation, outline or model, which are the renderer's.
//   The first version stands each building on one cell;
// - a storey of a cell holds 1,536 m² of floor, a resident needs 48 m² and
//   a job 32 m²; homes take 7, 2 or 1 eighths of the floor of homes, shops
//   or offices, and densities D1 to D4 have 2, 6, 18 and 40 storeys;
// - a cell gets the lowest density that holds its main count (residents of
//   homes, jobs of shops and offices); the other count's capacity is the
//   table's or what the cell holds, whichever is more, so no one is turned
//   out; a cell too full for D4 gets existing stock, which holds what it
//   has or D4's, whichever is more.
//
// In 6c-1 capacity is only recorded: land still grows to 400 residents and
// 1,200 jobs a cell (decision 73), and buildings are not raised; growth up
// to capacity and raising buildings are 6c-2.

/// A building's number: handed out from 1 in order, never reused while the
/// buildings stand.
public struct BuildingID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: BuildingID, rhs: BuildingID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A cell of land's place: its row and column (see ``LandCell``).
public struct CellPosition: Hashable, Comparable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static func < (lhs: CellPosition, rhs: CellPosition) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

extension LandCell {
    /// Where the cell is.
    public var position: CellPosition {
        CellPosition(row: row, column: column)
    }
}

/// What kind of building stands on a cell.
public enum BuildingKind: String, CaseIterable, Codable, Sendable {
    /// One of the city's ordinary buildings: its density's table capacity.
    case city
    /// What a cell already held when the city's buildings came, more than
    /// D4 holds of its main count: it holds what it had (or D4's, if more).
    case existingStock
}

/// How tall a city building is: D1 to D4.
public enum BuildingDensity: Int, CaseIterable, Comparable, Codable, Sendable {
    case d1 = 1
    case d2
    case d3
    case d4

    /// Its storeys: 2, 6, 18 and 40.
    public var floors: Int64 {
        switch self {
        case .d1: 2
        case .d2: 6
        case .d3: 18
        case .d4: 40
        }
    }

    public static func < (lhs: BuildingDensity, rhs: BuildingDensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How many residents and jobs a cell's building holds.
public struct BuildingCapacity: Hashable, Sendable {
    public var residents: Int64
    public var jobs: Int64

    public init(residents: Int64, jobs: Int64) {
        self.residents = residents
        self.jobs = jobs
    }
}

/// A building of the city: the cells it stands on, with the use of their
/// land.
public struct Building: Hashable, Sendable {
    public let id: BuildingID
    public let kind: BuildingKind
    /// The use of its cells' land.
    public let use: LandUse
    /// Its density; D4 for existing stock.
    public let density: BuildingDensity
    /// The cells it stands on, by row and then column: one in this version.
    public let cells: [CellPosition]

    init(id: BuildingID, kind: BuildingKind, use: LandUse, density: BuildingDensity, cells: [CellPosition]) {
        self.id = id
        self.kind = kind
        self.use = use
        self.density = density
        self.cells = cells
    }

    // MARK: - The table

    /// The floor a storey of a cell holds, in m²: three eighths of its
    /// 4,096 m², the rest streets, yards and setbacks.
    public static let floorArea: Int64 = 1_536
    /// The floor a resident needs, and a job, in m².
    public static let areaPerResident: Int64 = 48
    public static let areaPerJob: Int64 = 32

    /// The eighths of a building's floor that are homes: 7 for homes, 2
    /// for shops, 1 for offices; the rest is jobs.
    public static func homeEighths(of use: LandUse) -> Int64 {
        switch use {
        case .residential: 7
        case .commercial: 2
        case .office: 1
        }
    }

    /// What a city building of `use` and `density` holds on a cell: its
    /// floor, `floorArea × floors`, by ``homeEighths(of:)`` into homes of
    /// ``areaPerResident`` and jobs of ``areaPerJob``, each step rounded
    /// down (none has a remainder).
    public static func tableCapacity(of use: LandUse, _ density: BuildingDensity) -> BuildingCapacity {
        let floor = floorArea * density.floors
        let homes = homeEighths(of: use)
        return BuildingCapacity(residents: floor * homes / 8 / areaPerResident, jobs: floor * (8 - homes) / 8 / areaPerJob)
    }

    /// What a cell of `use` mainly holds: residents for homes, jobs for
    /// shops and offices.
    static func mainCount(of use: LandUse, residents: Int64, jobs: Int64) -> Int64 {
        use == .residential ? residents : jobs
    }

    /// The building the city puts up on `cell`, numbered `id`: a city
    /// building of the lowest density whose table holds the cell's main
    /// count, or existing stock when not even D4's does.
    static func fitting(_ cell: LandCell, id: BuildingID) -> Building {
        let main = mainCount(of: cell.use, residents: cell.residents, jobs: cell.jobs)
        let density = BuildingDensity.allCases.first { density in
            let table = tableCapacity(of: cell.use, density)
            return mainCount(of: cell.use, residents: table.residents, jobs: table.jobs) >= main
        }
        return Building(id: id, kind: density == nil ? .existingStock : .city, use: cell.use, density: density ?? .d4, cells: [cell.position])
    }

    /// What it holds on a cell of its land with `cell`'s residents and
    /// jobs. A city building holds its table's main count, and of the
    /// other the table's or the cell's, whichever is more; existing stock
    /// holds the cell's or D4's of each, whichever is more.
    public func capacity(on cell: LandCell) -> BuildingCapacity {
        let table = Self.tableCapacity(of: use, density)
        switch kind {
        case .existingStock:
            return BuildingCapacity(residents: max(table.residents, cell.residents), jobs: max(table.jobs, cell.jobs))
        case .city:
            return use == .residential
                ? BuildingCapacity(residents: table.residents, jobs: max(table.jobs, cell.jobs))
                : BuildingCapacity(residents: max(table.residents, cell.residents), jobs: table.jobs)
        }
    }
}

/// The city's buildings: by ascending number, each cell under at most one.
public struct CityBuildings: Sendable {
    /// By ascending ID.
    public private(set) var all: [Building]
    /// The index in ``all`` of the building on each cell; derived.
    private var onCell: [CellPosition: Int]

    public init() {
        all = []
        onCell = [:]
    }

    public var isEmpty: Bool {
        all.isEmpty
    }

    /// The building on the cell at `row`, `column`, if one stands there.
    public func building(row: Int, column: Int) -> Building? {
        onCell[CellPosition(row: row, column: column)].map { all[$0] }
    }

    /// The buildings the city puts up on `land`, one a cell, numbered from
    /// 1 by row and then column (see ``Building/fitting(_:id:)``).
    static func fitting(_ land: Land) -> CityBuildings {
        var buildings = CityBuildings()
        for (index, cell) in land.cells.enumerated() {
            buildings.append(Building.fitting(cell, id: BuildingID(rawValue: index + 1)))
        }
        return buildings
    }

    /// The number the next building takes, or `nil` when there is none.
    var nextID: BuildingID? {
        guard let last = all.last else { return BuildingID(rawValue: 1) }
        let (next, overflow) = last.id.rawValue.addingReportingOverflow(1)
        return overflow ? nil : BuildingID(rawValue: next)
    }

    /// Adds `building`, numbered after every other and on free cells.
    mutating func append(_ building: Building) {
        for cell in building.cells {
            onCell[cell] = all.count
        }
        all.append(building)
    }

    /// Why the buildings break a rule for `land`, or `nil`: a building on
    /// each cell of the land and on no other cell, of its use.
    func problem(on land: Land) -> String? {
        guard onCell.count == land.cells.count else { return "Every cell of land must have one building, and only those cells." }
        for cell in land.cells {
            guard let index = onCell[cell.position] else { return "Every cell of land must have one building, and only those cells." }
            guard all[index].use == cell.use else { return "A building's use must be its land's." }
        }
        return nil
    }
}

extension CityBuildings: Hashable {
    public static func == (lhs: CityBuildings, rhs: CityBuildings) -> Bool {
        lhs.all == rhs.all
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(all)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns the city's buildings on or off (Phase 6c-1). On, every cell
    /// of land gets the building that holds it (see
    /// ``Building/fitting(_:id:)``), numbered from 1 by row and then
    /// column, and land set, towns founded or built by growth from then on
    /// gets its buildings with it. Off, the buildings are gone. Nothing
    /// else changes: in 6c-1 no rule reads capacity.
    public mutating func setCityBuildings(_ enabled: Bool) {
        guard enabled != cityBuildings else { return }
        cityBuildings = enabled
        buildings = enabled ? CityBuildings.fitting(land) : CityBuildings()
    }

    // MARK: - Queries

    /// What the building on the cell at `row`, `column` holds: `nil` where
    /// no building stands (no one lives or works there, or the city's
    /// buildings are off).
    public func buildingCapacity(row: Int, column: Int) -> BuildingCapacity? {
        guard let building = buildings.building(row: row, column: column), let cell = land.cell(row: row, column: column) else { return nil }
        return building.capacity(on: cell)
    }

    /// What the building on the cell `point` lies in holds (see
    /// ``buildingCapacity(row:column:)``).
    public func buildingCapacity(at point: PlanPoint) -> BuildingCapacity? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        return buildingCapacity(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
    }

    /// The buildings on the cells of station `id`'s catchment (the cells
    /// whose middles lie within ``Land/catchmentRadius`` of it), by row and
    /// then column: `nil` for a station that does not exist.
    public func catchmentBuildings(of id: StationID) -> [Building]? {
        guard let station = station(id: id) else { return nil }
        var found: [Building] = []
        land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in
            let cell = land.cells[index]
            if let building = buildings.building(row: cell.row, column: cell.column) {
                found.append(building)
            }
        }
        return found
    }

    // MARK: - Land

    /// Puts `land` in place with its buildings, when the city's buildings
    /// are on.
    mutating func replaceLand(with land: Land) {
        if cityBuildings {
            buildings = CityBuildings.fitting(land)
        }
        self.land = land
    }

    /// Adds `cell`, which is not listed yet, with the building that holds
    /// it when the city's buildings are on; neither when no number is left
    /// for the building.
    mutating func addLand(_ cell: LandCell) {
        if cityBuildings {
            guard let id = buildings.nextID else { return }
            buildings.append(Building.fitting(cell, id: id))
        }
        land.insert(cell)
    }

    /// Why the buildings break a rule, or `nil`: none while they are off,
    /// one on each cell of land while they are on.
    func buildingProblem() -> String? {
        cityBuildings ? buildings.problem(on: land) : (buildings.isEmpty ? nil : "Buildings need the city's buildings on.")
    }
}

// MARK: - Codable

extension CityBuildings: Codable {
    /// One-cell buildings next to each other in a row, numbered one after
    /// another, of the same use and kind: `{"id", "row", "column", "use",
    /// "density": [d, …], "kind"}`, the first building's number and cell,
    /// one density (1 to 4) a building, `"kind"` left out for city
    /// buildings. Buildings put up together are numbered by row and column,
    /// so a real-world map's tens of thousands save as about as many runs
    /// as its land.
    private struct Run: Codable {
        var id: Int
        var row: Int
        var column: Int
        var use: LandUse
        var density: [BuildingDensity]
        var kind: BuildingKind?
    }

    /// Decodes a list of runs. Numbers must rise, each cell must be under
    /// one building, and existing stock is D4; the world checks the
    /// buildings stand on its land.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init()
        for run in try container.decode([Run].self) {
            let kind = run.kind ?? .city
            guard !run.density.isEmpty, run.id > (all.last?.id.rawValue ?? 0), run.row >= 0, run.column >= 0,
                  run.density.count - 1 <= Int.max - run.id, run.density.count - 1 <= Int.max - run.column,
                  kind == .city || run.density.allSatisfy({ $0 == .d4 })
            else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A run of buildings is empty, out of order or out of range, or has existing stock below D4.")
            }
            for (offset, density) in run.density.enumerated() {
                let cell = CellPosition(row: run.row, column: run.column + offset)
                guard onCell[cell] == nil else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Two buildings stand on one cell.")
                }
                append(Building(id: BuildingID(rawValue: run.id + offset), kind: kind, use: run.use, density: density, cells: [cell]))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var runs: [Run] = []
        for building in all {
            // One cell in this version (the decoder makes no other).
            let cell = building.cells[0]
            let kind: BuildingKind? = building.kind == .city ? nil : building.kind
            if var last = runs.last, last.row == cell.row, last.use == building.use, last.kind == kind,
               last.column + last.density.count == cell.column, last.id + last.density.count == building.id.rawValue {
                last.density.append(building.density)
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(id: building.id.rawValue, row: cell.row, column: cell.column, use: building.use, density: [building.density], kind: kind))
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(runs)
    }
}
