// The company's buildings (city building P0-C1, ARCHITECTURE decision 94):
// the A-Train way. The buildings the player places (decision 92) are the
// company's: a managed company pays for each, the building and the right to
// use the land under it, and keeps it on its books; it fills with residents
// and jobs while a station serves it, who ride from the stations near it as
// the city's own people do; and each midnight it earns rent and pays its
// upkeep and the tax on its land. Demolishing it costs a tenth of what it
// cost, and its book value is written off. Free play keeps no accounts:
// there a building costs nothing and earns nothing.
//
// P0-C2 (decision 95): a building buys out the city's buildings in its way,
// the A-Train's buy-out and demolition, and track and stations built later
// clear the company's buildings in theirs for the fee demolishing costs.
// A city building stands on the middle of its cell, a square
// ``PlacedBuildingRules/cityBuildingSide`` across: the cell is statistics,
// but the building on it has a place, so a small building can stand at the
// edge of a cell and leave the city's alone.
//
// Buying out by area (decision 146): on a real-world map the city's
// buildings are the base map's, and the game's squares in the middle of
// each cell match none of them, so they stand in no one's way there. A
// company building buys out the share of each cell of land it covers,
// that share of the cell's city building's price, and that share of the
// cell's people move in; the cell stays, and grows to its limits less the
// share the company covers.
//
// The reference has no property (docs/research/CITY_BUILDING_STUDY.md §2):
// the rules and every number are native, the formulas the Phase 7 study's
// (docs/research/PHASE7_COMPANY_STUDY.md §3.3) with a building's own
// residents and jobs and its centre's land value.

extension PlacedBuildingRules {
    /// What a m² of floor costs to build: $40 (the Phase 7 study's `B`).
    public static let floorCost: Money = 4_000
    /// The day's upkeep, in ten-thousandths of the building's cost, rounded
    /// up, and the day's tax on the land, in ten-thousandths of what its use
    /// cost, rounded half up.
    public static let upkeepBasisPoints: Int64 = 2
    public static let taxBasisPoints: Int64 = 1
    /// What demolishing costs, in hundredths of what the building cost.
    public static let demolitionPercent: Int64 = 10
    /// How fast a building fills each midnight, in thousandths of its
    /// capacity: 20 and up to 80 more as the station serving it serves
    /// better (the land value's `S`, 0 to 1000); with no station serving it,
    /// it loses 20 thousandths of who is there. Each at least one.
    public static let fillBase: Int64 = 20
    public static let fillByService: Int64 = 80
    public static let emptying: Int64 = 20
    /// The side of the square a city building stands on, in the middle of
    /// its cell (decision 95): 40 m, 1,600 m², about a storey's
    /// ``Building/floorArea`` (1,536 m²).
    public static let cityBuildingSide: Int64 = 2_560
    /// With the city's footprints (decision 142), the side of the square a
    /// city building of `density` stands on: 20, 28, 34 and 40 m, so a low
    /// town leaves room between its buildings and a dense centre does not.
    public static func cityBuildingSide(of density: BuildingDensity) -> Int64 {
        switch density {
        case .d1: 1_280
        case .d2: 1_792
        case .d3: 2_176
        case .d4: cityBuildingSide
        }
    }
    /// What buying out a city building costs, in hundredths of its value:
    /// its floor at ``floorCost`` and the land of its square at the cell's
    /// land value, and a fifth more (the A-Train's buy-out costs more than
    /// building).
    public static let buyOutPercent: Int64 = 120
}

/// What placing a building costs a managed company (decision 94).
public struct PlacedBuildingQuote: Hashable, Sendable {
    /// The building: its floor at ``PlacedBuildingRules/floorCost``.
    public let building: Money
    /// The right to use the land: the land value of the cell under its
    /// centre (cents a m²) by its footprint.
    public let land: Money
    /// Buying out the city's buildings it claims (decision 95), together;
    /// buying out by area (decision 146), the shares of the cells it covers.
    public let buyOut: Money
    /// The cells of land whose city buildings it buys out and pulls down,
    /// by row and then column; free play pulls them down too. None when
    /// buying out by area, which pulls nothing down.
    public let cleared: [CellPosition]

    public init(building: Money, land: Money, buyOut: Money = .zero, cleared: [CellPosition] = []) {
        self.building = building
        self.land = land
        self.buyOut = buyOut
        self.cleared = cleared
    }

    public var total: Money {
        building + land + buyOut
    }
}

extension GameWorld {
    // MARK: - Queries

    /// What placing a building of `kind` centred on `centre` costs now, or
    /// `nil` outside the world. Free play pays nothing.
    public func placedBuildingQuote(_ kind: PlacedBuildingKind, at centre: PlanPoint) -> PlacedBuildingQuote? {
        guard bounds.contains(centre) else { return nil }
        let candidate = PlacedBuilding(id: PlacedBuildingID(rawValue: 0), kind: kind, centre: centre)
        let cleared = areaBuyOut ? [] : cityCells(claimedBy: candidate)
        guard accounts.mode == .management else {
            return PlacedBuildingQuote(building: .zero, land: .zero, cleared: cleared.map(\.position))
        }
        let value = landValue(row: Land.cellIndex(centre.y), column: Land.cellIndex(centre.x))?.value ?? 0
        let buyOut = areaBuyOut
            ? cityShares(coveredBy: candidate).reduce(.zero) { $0 + buyOutPrice(of: $1.cell, covered: $1.area) }
            : cleared.reduce(.zero) { $0 + buyOutPrice(of: $1) }
        return PlacedBuildingQuote(
            building: Money(kind.floorArea * PlacedBuildingRules.floorCost.amount),
            land: Money(kind.footprintArea * value),
            buyOut: buyOut,
            cleared: cleared.map(\.position)
        )
    }

    /// The cells of land `building`'s square covers part of, by row and
    /// then column, each with the area it covers in square world units
    /// (decision 146): more than 0 and, as no building is a cell across,
    /// less than ``Land/cellArea``.
    public func cityShares(coveredBy building: PlacedBuilding) -> [(cell: LandCell, area: Int64)] {
        let firstRow = Land.cellIndex(building.minY), lastRow = Land.cellIndex(building.maxY - 1)
        let firstColumn = Land.cellIndex(building.minX), lastColumn = Land.cellIndex(building.maxX - 1)
        var shares: [(cell: LandCell, area: Int64)] = []
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let area = Self.area(of: building, onRow: row, column: column)
                if area > 0, let cell = land.cell(row: row, column: column) {
                    shares.append((cell, area))
                }
            }
        }
        return shares
    }

    /// The ground `building`'s square shares with the cell at `row`,
    /// `column`, in square world units.
    static func area(of building: PlacedBuilding, onRow row: Int, column: Int) -> Int64 {
        let minX = Int64(column) * Land.cellLength, minY = Int64(row) * Land.cellLength
        let width = min(building.maxX, minX + Land.cellLength) - max(building.minX, minX)
        let height = min(building.maxY, minY + Land.cellLength) - max(building.minY, minY)
        return width > 0 && height > 0 ? width * height : 0
    }

    /// The ground of the cell at `row`, `column` the company's buildings
    /// cover, in square world units (decision 146): at most
    /// ``Land/cellArea``, as they share no ground.
    func coveredArea(row: Int, column: Int) -> Int64 {
        guard !placedBuildings.isEmpty else { return 0 }
        return min(Land.cellArea, placedBuildings.reduce(0) { $0 + Self.area(of: $1, onRow: row, column: column) })
    }

    /// ``coveredArea(row:column:)`` of every cell the company's buildings
    /// cover part of.
    func coveredAreas() -> [CellPosition: Int64] {
        var covered: [CellPosition: Int64] = [:]
        for building in placedBuildings {
            for row in Land.cellIndex(building.minY)...Land.cellIndex(building.maxY - 1) {
                for column in Land.cellIndex(building.minX)...Land.cellIndex(building.maxX - 1) {
                    covered[CellPosition(row: row, column: column), default: 0] += Self.area(of: building, onRow: row, column: column)
                }
            }
        }
        return covered
    }

    /// The cells of land whose city building `building` claims (decision
    /// 95), by row and then column: those whose square, a
    /// ``cityBuildingSide(row:column:)`` square in the middle of the cell,
    /// shares ground with `building`'s square grown by the clearance
    /// (touching does not). A cell of land with no city building on it
    /// (the city's buildings off) counts as if it had one.
    public func cityCells(claimedBy building: PlacedBuilding) -> [LandCell] {
        let c = PlacedBuildingRules.clearance
        let firstRow = Land.cellIndex(building.minY - c), lastRow = Land.cellIndex(building.maxY + c)
        let firstColumn = Land.cellIndex(building.minX - c), lastColumn = Land.cellIndex(building.maxX + c)
        var cells: [LandCell] = []
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                if let cell = land.cell(row: row, column: column),
                   Self.claims(building, row: row, column: column, side: cityBuildingSide(row: row, column: column)) {
                    cells.append(cell)
                }
            }
        }
        return cells
    }

    /// The side of the square the city's building on the cell at `row`,
    /// `column` stands on, in the middle of the cell (decision 95):
    /// ``PlacedBuildingRules/cityBuildingSide``, or with the city's
    /// footprints (decision 142) its density's: the building's on it, else
    /// the one the city would put up on its land, else a D1's for a cell
    /// with no land yet, as the city's growth puts up there.
    public func cityBuildingSide(row: Int, column: Int) -> Int64 {
        guard cityFootprints else { return PlacedBuildingRules.cityBuildingSide }
        if let building = buildings.building(row: row, column: column) {
            return PlacedBuildingRules.cityBuildingSide(of: building.density)
        }
        if let cell = land.cell(row: row, column: column) {
            return cityBuildingSide(for: cell)
        }
        return PlacedBuildingRules.cityBuildingSide(of: .d1)
    }

    /// The side of the square of the building the city would put up on
    /// `cell` (see ``cityBuildingSide(row:column:)``), for land not yet in
    /// place.
    func cityBuildingSide(for cell: LandCell) -> Int64 {
        guard cityFootprints else { return PlacedBuildingRules.cityBuildingSide }
        return PlacedBuildingRules.cityBuildingSide(of: Building.fitting(cell, id: BuildingID(rawValue: 1)).density)
    }

    /// Whether `building` claims the city building of the cell at `row`,
    /// `column` whose square is `side` across (see
    /// ``cityCells(claimedBy:)``).
    static func claims(_ building: PlacedBuilding, row: Int, column: Int, side: Int64) -> Bool {
        let c = PlacedBuildingRules.clearance
        let inset = (Land.cellLength - side) / 2
        let minX = Int64(column) * Land.cellLength + inset, minY = Int64(row) * Land.cellLength + inset
        let maxX = minX + side, maxY = minY + side
        return building.minX - c < maxX && minX < building.maxX + c && building.minY - c < maxY && minY < building.maxY + c
    }

    /// Whether one of the company's buildings claims the cell at `row`,
    /// `column`: the city puts up nothing there (decision 95). Its square
    /// is `side` across, or ``cityBuildingSide(row:column:)``.
    /// Buying out by area (decision 146), only a cell they cover whole is
    /// theirs.
    func isClaimedByPlacedBuilding(row: Int, column: Int, side: Int64? = nil) -> Bool {
        guard !placedBuildings.isEmpty else { return false }
        if areaBuyOut { return coveredArea(row: row, column: column) == Land.cellArea }
        let side = side ?? cityBuildingSide(row: row, column: column)
        return placedBuildings.contains { Self.claims($0, row: row, column: column, side: side) }
    }

    /// Whether the city building on `position` cannot be raised because
    /// its square, grown to the next density's with the city's footprints
    /// (decision 142), would reach one of the company's buildings. Never
    /// when buying out by area (decision 146): the cell's limits leave out
    /// what they cover instead.
    func raiseIsBlocked(at position: CellPosition) -> Bool {
        guard cityFootprints, !areaBuyOut, !placedBuildings.isEmpty,
              let building = buildings.building(row: position.row, column: position.column),
              let next = BuildingDensity(rawValue: building.density.rawValue + 1)
        else { return false }
        return isClaimedByPlacedBuilding(row: position.row, column: position.column, side: PlacedBuildingRules.cityBuildingSide(of: next))
    }

    // MARK: - Commands

    /// Turns the city's footprints on or off (decision 142): on, a city
    /// building's square is its density's (20 to 40 m) rather than 40 m
    /// whatever its height. Free; nothing on the map changes but what a
    /// building claims and buys out from now on.
    public mutating func setCityFootprints(_ enabled: Bool) {
        cityFootprints = enabled
    }

    /// Turns buying out by area on or off (decision 146): on, a company
    /// building buys out the share of each cell it covers, rather than the
    /// city buildings whose squares it reaches. Free; nothing on the map
    /// changes but what is bought out from now on and what the cells under
    /// the company's buildings grow to.
    public mutating func setAreaBuyOut(_ enabled: Bool) {
        areaBuyOut = enabled
    }

    /// What buying out the city building on `cell` costs a managed company
    /// (decision 95): ``PlacedBuildingRules/buyOutPercent`` of its floor at
    /// ``PlacedBuildingRules/floorCost`` (a park has none) and its square's
    /// land at the cell's land value. Its floor is its density's storeys of
    /// ``Building/floorArea``: the density of the building on it, or with
    /// the city's buildings off, the one the city would put up.
    public func buyOutPrice(of cell: LandCell) -> Money {
        guard accounts.mode == .management else { return .zero }
        let density = buildings.building(row: cell.row, column: cell.column)?.density
            ?? Building.fitting(cell, id: BuildingID(rawValue: 1)).density
        let floor = cell.use == .park ? 0 : Building.floorArea * density.floors
        let side = cityBuildingSide(row: cell.row, column: cell.column) / WorldCoordinate.unitsPerMetre
        let value = landValue(row: cell.row, column: cell.column)?.value ?? 0
        return Money((floor * PlacedBuildingRules.floorCost.amount + side * side * value) * PlacedBuildingRules.buyOutPercent / 100)
    }

    /// What buying out `covered` square world units of `cell` costs a
    /// managed company (decision 146): that share of ``buyOutPrice(of:)``,
    /// rounded down, as if the city building stood spread over its cell.
    public func buyOutPrice(of cell: LandCell, covered: Int64) -> Money {
        let whole = buyOutPrice(of: cell).amount
        // The cell's area is 2^24: split the price so its product stays
        // far inside 64 bits whatever the land is worth.
        let high = whole / Land.cellArea, low = whole % Land.cellArea
        return Money(high * covered + low * covered / Land.cellArea)
    }

    /// The company's buildings, by ID, that track along `points` would
    /// run through (decision 95): its centre line comes closer than the
    /// clearance to their squares.
    public func placedBuildings(inTheWayOf points: [PlanPoint]) -> [PlacedBuilding] {
        placedBuildings.filter { Self.line(points, comesNear: $0) }
    }

    /// What clearing `cleared` costs: each one's ``demolitionCost(of:)``.
    public func clearingCost(of cleared: [PlacedBuilding]) -> Money {
        cleared.reduce(.zero) { $0 + demolitionCost(of: $1) }
    }

    /// The land value of the cell under `building`'s centre, and the
    /// station service there (the land value's `S`: its service premium ÷
    /// ``LandValueRules/servicePremium``).
    func landTerms(of building: PlacedBuilding) -> (value: Int64, service: Int64) {
        let value = landValue(row: Land.cellIndex(building.centre.y), column: Land.cellIndex(building.centre.x))
        return (value?.value ?? 0, (value?.servicePremium ?? 0) / LandValueRules.servicePremium)
    }

    /// The day's rent of `building` (the Phase 7 study's formula with its
    /// residents `R` and jobs `J`): `floor((R × 1000 + J × 1500) × (1000 +
    /// floor(S / 2)) × V / 10,000,000)` cents, where `S` is the station
    /// service and `V` the land value under its centre.
    public func dailyRent(of building: PlacedBuilding) -> Money {
        let (value, service) = landTerms(of: building)
        let base = building.residents * 1_000 + building.jobs * 1_500
        return Money(base * (1_000 + service / 2) * value / 10_000_000)
    }

    /// The day's upkeep of `building`, ``PlacedBuildingRules/upkeepBasisPoints``
    /// of its building cost rounded up, and the tax on its land,
    /// ``PlacedBuildingRules/taxBasisPoints`` of what the land's use cost,
    /// rounded half up.
    public func dailyUpkeep(of building: PlacedBuilding) -> (upkeep: Money, tax: Money) {
        let upkeep = (building.buildingCost.amount * PlacedBuildingRules.upkeepBasisPoints + 9_999) / 10_000
        let tax = (building.landCost.amount * PlacedBuildingRules.taxBasisPoints + 5_000) / 10_000
        return (Money(upkeep), Money(tax))
    }

    /// What demolishing `building` costs a managed company:
    /// ``PlacedBuildingRules/demolitionPercent`` of what it cost, rounded up.
    public func demolitionCost(of building: PlacedBuilding) -> Money {
        guard accounts.mode == .management else { return .zero }
        return Money((building.cost.amount * PlacedBuildingRules.demolitionPercent + 99) / 100)
    }

    // MARK: - Commands

    /// Demolishes the company's building `id` (decision 94): a managed
    /// company pays ``demolitionCost(of:)``, a ledger row of its own that
    /// counts with the buildings' costs, and writes off what is left of it
    /// on the books; nothing is refunded. Its people go, and the stations
    /// near it lose their riders at once. Its ID is not handed out again.
    ///
    /// - Throws, checked in this order: ``GameError/unknownPlacedBuilding(_:)``
    ///   or ``GameError/insufficientFunds(required:available:)``.
    public mutating func removePlacedBuilding(_ id: PlacedBuildingID) throws(GameError) {
        guard let index = placedBuildings.firstIndex(where: { $0.id == id }) else { throw .unknownPlacedBuilding(id) }
        let fee = demolitionCost(of: placedBuildings[index])
        guard economy.canAfford(fee) else { throw .insufficientFunds(required: fee, available: economy.balance) }
        clear([placedBuildings[index]])
    }

    /// Pulls down `cleared`, the company's buildings, each for its
    /// ``demolitionCost(of:)`` (a ledger row of its own, when it costs
    /// anything), writing off their book value; the stations near them lose
    /// their riders. The caller has checked the money is there.
    mutating func clear(_ cleared: [PlacedBuilding]) {
        guard !cleared.isEmpty else { return }
        for building in cleared {
            let fee = demolitionCost(of: building)
            if fee > .zero {
                write(LedgerEntry(
                    kind: .buildingDemolition, time: clock.now, amount: .zero - fee,
                    breakdown: [LedgerLine(item: .propertyDemolition, amount: .zero - fee)]
                ), day: dayIndex(of: clock.now))
            }
            placedBuildings.removeAll { $0.id == building.id }
            disposeAsset(.building, owner: building.id.rawValue)
        }
        refreshLandDemand()
    }

    // MARK: - Midnight

    /// Fills the company's buildings by the service `measured` tonight
    /// (decision 94): each served building takes ``PlacedBuildingRules/fillBase``
    /// plus up to ``PlacedBuildingRules/fillByService`` thousandths of its
    /// capacity of residents and of jobs (at least one of each it has room
    /// for), up to its capacity; one no station serves loses
    /// ``PlacedBuildingRules/emptying`` thousandths of each (at least one).
    /// The service is the land value's `S` with tonight's measures, so this
    /// runs once town growth has stored them.
    mutating func fillPlacedBuildings() {
        for index in placedBuildings.indices {
            let building = placedBuildings[index]
            let service = landTerms(of: building).service
            let capacity = building.kind.capacity
            func filled(_ now: Int64, _ room: Int64) -> Int64 {
                if service > 0 {
                    let step = max(1, room * (PlacedBuildingRules.fillBase + service * PlacedBuildingRules.fillByService / 1_000) / 1_000)
                    return min(room, now + step)
                }
                return max(0, now - max(1, now * PlacedBuildingRules.emptying / 1_000))
            }
            placedBuildings[index].residents = filled(building.residents, capacity.residents)
            placedBuildings[index].jobs = filled(building.jobs, capacity.jobs)
        }
    }

    /// Settles day `day`'s rent, upkeep and tax of the company's buildings
    /// (decision 94) as one ledger row at `time`, the day's last minute.
    mutating func settleProperty(day: Int64, time: GameTime) {
        var rent = Money.zero, upkeep = Money.zero, tax = Money.zero
        for building in placedBuildings {
            rent = rent + dailyRent(of: building)
            let costs = dailyUpkeep(of: building)
            upkeep = upkeep + costs.upkeep
            tax = tax + costs.tax
        }
        guard rent > .zero || upkeep > .zero || tax > .zero else { return }
        write(LedgerEntry(
            kind: .dailyProperty, time: time, amount: rent - upkeep - tax,
            breakdown: [
                LedgerLine(item: .propertyRent, amount: rent),
                LedgerLine(item: .propertyUpkeep, amount: .zero - upkeep),
                LedgerLine(item: .propertyTax, amount: .zero - tax),
            ]
        ), day: day)
    }
}
