// Land value (Phase 6c-3, ARCHITECTURE decision 76): what a cell of land is
// worth, worked out when asked from its use, its building's density and the
// service of the stations round it. Never saved, never kept as a history,
// never booked: trading, rent and costs are Phase 7.
//
// The owner's references have no land value to port (the study,
// `docs/research/PHASE6C_BUILDINGS_STUDY.md` in PR #174, §4: no land price,
// rent, property or development rule in `Ci/`, `Railway/` or the reference
// pack). So the formula and its numbers are this project's (gap), the
// study's §6.2:
//
//     base  = floor(B × D / 1000)
//     value = clamp(base + 15 × S + 1000 × A + P, 500, 50000)   cents a m²
//
// - B, the use's base: 1,000 for an empty cell, 2,000 homes, 3,000 shops,
//   3,500 offices; since decision 91, 1,500 factories, 2,500 schools and
//   public offices, 3,000 sights, 600 farms and 1,200 parks;
// - D, the density's factor in thousandths: 1,000, 1,250, 1,600, 2,000 for
//   D1 to D4 (existing stock is D4), 1,000 without a building;
// - S and A, the best station's service: of the stations whose catchment
//   reaches the cell (d² < R², R = 800 m) and that served some of their
//   trips on the last measured day (``TownGrowth/Place/lastService`` > 0),
//   the one with the highest `floor(w × lastService / 1000)`, where `w =
//   1000 − floor(d² × 1000 / R²)` (ties to the lower station); S is that
//   score, A its ``TownGrowth/Place/lastReached``;
// - P, decision 91: 600 for a cell whose middle lies within 400 m of a
//   park's (a park's own included), else 0; since decision 361 the
//   company's parks count, by their centres;
// - C, decision 98: 600 for a cell zoned for a use whose middle lies
//   within 400 m of the centre of one of the company's buildings, else 0
//   (the company's buildings leading development; only zoned cells, so
//   a world without zones is worth what it was);
//   Since decision 728, the more of C and 300 × the tenths the uses of the
//   company's buildings within 400 m lift the cell's use
//   (``LandValueRules/industryTenths(from:to:)``, at most 14), on any cell
//   with a use, less a factory's drop by homes;
// - W, decision 111: 600 for a cell whose middle lies within 160 m of a
//   cell of water's (water included), else 0: the sea view and the river
//   bank (a world without water is worth what it was);
// - E, decision 361's sequel: 900 for a cell whose middle lies within
//   400 m of the centre of one of the company's schools, and 500 of one of
//   its hospitals, the two added, else 0: the island city reference's
//   `LV_W.school = 9` and `hospital = 5` (g23.js) on the scale its
//   `park = 6` has here (P's 600).
//
// The value reads the world and changes nothing: raising buildings
// (decision 75) never reads it, and growth only to choose which zoned cell
// to build on (decision 98).

/// What a cell of land is worth, in cents a m², and its parts.
public struct LandValue: Hashable, Sendable {
    /// `clamp(base + servicePremium + accessPremium + parkPremium +
    /// companyPremium + waterPremium, minimum, maximum)`.
    public let value: Int64
    /// `floor(B × D / 1000)`: the use's base by the density's factor.
    public let base: Int64
    /// ``LandValueRules/servicePremium`` × S.
    public let servicePremium: Int64
    /// ``LandValueRules/accessPremium`` × A.
    public let accessPremium: Int64
    /// The station S and A are measured at, or `nil` when none is.
    public let station: StationID?

    /// ``LandValueRules/parkPremium`` near a park, else 0 (decision 91).
    public let parkPremium: Int64
    /// ``LandValueRules/companyPremium`` for a zoned cell near the
    /// company's buildings, else 0 (decision 98); since decision 728 the
    /// more of that and what the uses of the company's buildings round it
    /// lift its use (``LandValueRules/industryTenths(from:to:)``), less
    /// what they drop it (a factory by homes, so it can be below 0).
    public let companyPremium: Int64
    /// ``LandValueRules/waterPremium`` by the water, else 0 (decision 111).
    public let waterPremium: Int64
    /// ``LandValueRules/schoolPremium`` near the company's schools and
    /// ``LandValueRules/hospitalPremium`` near its hospitals, added, else 0
    /// (decision 361's sequel).
    public let civicPremium: Int64

    public init(
        value: Int64, base: Int64, servicePremium: Int64, accessPremium: Int64, station: StationID?, parkPremium: Int64 = 0, companyPremium: Int64 = 0,
        waterPremium: Int64 = 0, civicPremium: Int64 = 0
    ) {
        self.value = value
        self.base = base
        self.servicePremium = servicePremium
        self.accessPremium = accessPremium
        self.station = station
        self.parkPremium = parkPremium
        self.companyPremium = companyPremium
        self.waterPremium = waterPremium
        self.civicPremium = civicPremium
    }
}

/// The numbers of land value (Phase 6c-3): this project's (gap).
///
/// Decision 499: every amount is in cents of the New Taiwan dollar, 3 to
/// the dollar these rules were written in, so each base, premium and bound
/// is the comment's number times 3; the bases times the density factors
/// stay whole, so every value is exactly 3 times what it was.
public enum LandValueRules {
    /// B for a cell with no land and no building, in cents a m².
    public static let vacantBase: Int64 = 3_000

    /// B for a use, in cents a m².
    public static func base(of use: LandUse) -> Int64 {
        switch use {
        case .residential: 6_000
        case .commercial, .leisure: 9_000
        case .office: 10_500
        case .industrial: 4_500
        case .civic: 7_500
        case .agricultural: 1_800
        case .park: 3_600
        }
    }

    /// D for a density, in thousandths.
    public static func densityFactor(_ density: BuildingDensity) -> Int64 {
        switch density {
        case .d1: 1_000
        case .d2: 1_250
        case .d3: 1_600
        case .d4: 2_000
        }
    }

    /// D without a building, in thousandths.
    public static let vacantDensityFactor: Int64 = 1_000
    /// Cents a m² for each point of the best station's score S (0 to 1,000).
    public static let servicePremium: Int64 = 45
    /// Cents a m² for each station the best station reached (0 to 5).
    public static let accessPremium: Int64 = 3_000
    /// Cents a m² near a park (decision 91), and how near: 400 m.
    public static let parkPremium: Int64 = 1_800
    public static let parkReach: Int64 = 25_600
    /// Cents a m² on a cell zoned for a use near the company's buildings
    /// (decision 98), and how near their centres: 400 m, as a park.
    public static let companyPremium: Int64 = 1_800
    public static let companyReach: Int64 = 25_600
    /// Cents a m² by the water (decision 111), and how near a cell of
    /// water's middle: 160 m, two and a half cells.
    public static let waterPremium: Int64 = 1_800
    public static let waterReach: Int64 = 10_240
    /// Cents a m² near the company's schools and hospitals (decision 361's
    /// sequel), and how near their centres: 400 m, as a park.
    public static let schoolPremium: Int64 = 2_700
    public static let hospitalPremium: Int64 = 1_500
    public static let civicReach: Int64 = 25_600
    /// Decision 728 (the subsidiary design's step 3): how much one of the
    /// company's buildings of use `source` within ``companyReach`` of its
    /// centre lifts the city's land of use `target`, in tenths: 9 strong,
    /// 5 middling, 3 weak, -9 for a factory by homes, else 0. A use counts
    /// once however many of it stand near. Culture by homes stays the
    /// schools' and hospitals' own (``schoolPremium``, decision 361's
    /// sequel); parks are decision 91's and 361's.
    public static func industryTenths(from source: LandUse, to target: LandUse) -> Int64 {
        switch (source, target) {
        case (.residential, .commercial): 9
        case (.residential, .office), (.residential, .leisure): 3
        case (.residential, .civic): 5
        case (.commercial, .residential): 9
        case (.commercial, .office): 5
        case (.commercial, .leisure): 3
        case (.office, .residential): 5
        case (.office, .commercial): 9
        case (.office, .civic): 3
        case (.industrial, .residential): -9
        case (.industrial, .commercial): 3
        case (.industrial, .office): 5
        case (.agricultural, .commercial): 3
        case (.agricultural, .industrial), (.agricultural, .leisure): 5
        case (.leisure, .residential): 3
        case (.leisure, .commercial): 9
        case (.leisure, .civic): 5
        case (.civic, .commercial): 3
        case (.civic, .leisure): 5
        default: 0
        }
    }
    /// Cents a m² for each tenth of ``industryTenths(from:to:)``: 300, so
    /// strong is a school's 2,700, middling a hospital's 1,500.
    public static let industryPremiumPerTenth: Int64 = 300
    /// The most the uses round a cell lift it, in tenths: 14, a school's
    /// and a hospital's together.
    public static let industryMostTenths: Int64 = 14

    /// The least and the most a cell is worth, in cents a m².
    public static let minimum: Int64 = 1_500
    public static let maximum: Int64 = 150_000

    /// `base + service + access + park + company + water + civic` within
    /// ``minimum`` … ``maximum``.
    static func value(base: Int64, service: Int64, access: Int64, park: Int64 = 0, company: Int64 = 0, water: Int64 = 0, civic: Int64 = 0) -> Int64 {
        min(maximum, max(minimum, base + service + access + park + company + water + civic))
    }
}

extension GameWorld {
    // MARK: - Queries

    /// What the cell at `row`, `column` is worth (see ``LandValue``), or
    /// `nil` for a cell outside the world. Without the land setting a
    /// managed company's ridership (free play, demand from land off, or no
    /// town growth) S and A are 0: the value is its base.
    public func landValue(row: Int, column: Int) -> LandValue? {
        guard (0..<Land.rows(in: bounds)).contains(row), (0..<Land.columns(in: bounds)).contains(column) else { return nil }
        return landValue(row: row, column: column, near: landValueStations(), parks: landValueParks(), companies: landValueCompanies(), civics: landValueCivics())
    }

    /// What every cell of the world is worth, by row and then column
    /// (``Land/rows(in:)`` × ``Land/columns(in:)`` of them): the same as
    /// ``landValue(row:column:)`` for each, worked out together.
    public func landValues() -> [LandValue] {
        landValues(rows: 0...(Land.rows(in: bounds) - 1), columns: 0...(Land.columns(in: bounds) - 1))
    }

    /// What the cells of `rows` × `columns` are worth, by row and then
    /// column, those outside the world left out.
    public func landValues(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> [LandValue] {
        // Clamped apart, as a range wholly outside the world crosses over.
        let (firstRow, lastRow) = (max(0, rows.lowerBound), min(Land.rows(in: bounds) - 1, rows.upperBound))
        let (firstColumn, lastColumn) = (max(0, columns.lowerBound), min(Land.columns(in: bounds) - 1, columns.upperBound))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return [] }
        let rows = firstRow...lastRow, columns = firstColumn...lastColumn
        let stations = landValueStations(), parks = landValueParks(), companies = landValueCompanies(), civics = landValueCivics()
        var values: [LandValue] = []
        values.reserveCapacity(rows.count * columns.count)
        for row in rows {
            for column in columns {
                values.append(landValue(row: row, column: column, near: stations, parks: parks, companies: companies, civics: civics))
            }
        }
        return values
    }

    /// What the cells at `positions` are worth, in that order: the same as
    /// ``landValue(row:column:)`` for each, worked out together. Positions
    /// outside the world are left out. For a layer that needs only some
    /// cells (the city map's: those with land or in a catchment), where
    /// ``landValues()`` works out every cell of the world.
    public func landValues(at positions: [CellPosition]) -> [LandValue] {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let stations = landValueStations(), parks = landValueParks(), companies = landValueCompanies(), civics = landValueCivics()
        return positions.compactMap { position in
            guard (0..<rows).contains(position.row), (0..<columns).contains(position.column) else { return nil }
            return landValue(row: position.row, column: position.column, near: stations, parks: parks, companies: companies, civics: civics)
        }
    }

    /// The stations that can set a value: open ones with a measured service,
    /// by ascending station, with their point, service and stations
    /// reached; none while the land does not set ridership.
    private func landValueStations() -> [(id: StationID, point: PlanPoint, service: Int64, reached: Int64)] {
        guard drawsDemandFromLand, let growth = townGrowth else { return [] }
        return growth.places.compactMap { place in
            // A closed station serves no one (decision 77).
            guard place.lastService > 0, let station = station(id: place.station), station.operationMode != .closed else { return nil }
            return (place.station, station.location, place.lastService, place.lastReached)
        }
    }

    /// The middles of the parks (decision 91), by their row; and the
    /// centres of the company's parks (decision 361), by the row of the
    /// cell they lie in.
    private func landValueParks() -> [Int: [PlanPoint]] {
        var parks: [Int: [PlanPoint]] = [:]
        for cell in land.cells where cell.use == .park {
            parks[cell.row, default: []].append(cell.middle)
        }
        for building in placedBuildings where building.kind == .park {
            parks[Land.cellIndex(building.centre.y), default: []].append(building.centre)
        }
        return parks
    }

    /// The centres of the company's buildings (decision 98), none in a
    /// world without zones, which nothing near them makes worth more; and
    /// (decision 728) the centres of those of each use but parks, by use.
    private func landValueCompanies() -> (zoned: [PlanPoint], byUse: [LandUse: [PlanPoint]]) {
        (zones.isEmpty ? [] : placedBuildings.map(\.centre), companyCentresByUse())
    }

    /// The centres of the company's buildings by their use, parks left out
    /// (decision 728).
    func companyCentresByUse(excluding excluded: PlacedBuildingID? = nil) -> [LandUse: [PlanPoint]] {
        var byUse: [LandUse: [PlanPoint]] = [:]
        for building in placedBuildings where building.kind.use != .park && building.id != excluded {
            byUse[building.kind.use, default: []].append(building.centre)
        }
        return byUse
    }

    /// The tenths the company's buildings `byUse` lift land of use `target`
    /// whose middle is `point` (decision 728): each use within
    /// ``LandValueRules/companyReach`` once, by
    /// ``LandValueRules/industryTenths(from:to:)``; the lifts added up to
    /// ``LandValueRules/industryMostTenths``, and the drops.
    static func industryTenths(at point: PlanPoint, of target: LandUse, _ byUse: [LandUse: [PlanPoint]]) -> (lift: Int64, drop: Int64) {
        guard !byUse.isEmpty else { return (0, 0) }
        let reach = LandValueRules.companyReach * LandValueRules.companyReach
        var lift: Int64 = 0, drop: Int64 = 0
        // In LandUse's order, so the sum never depends on a dictionary's.
        for source in LandUse.allCases {
            let tenths = LandValueRules.industryTenths(from: source, to: target)
            guard tenths != 0, let centres = byUse[source] else { continue }
            let near = centres.contains { centre in
                let dx = point.x - centre.x, dy = point.y - centre.y
                return dx * dx + dy * dy < reach
            }
            guard near else { continue }
            if tenths > 0 { lift += tenths } else { drop += tenths }
        }
        return (min(lift, LandValueRules.industryMostTenths), drop)
    }

    private func landValue(
        row: Int, column: Int, near stations: [(id: StationID, point: PlanPoint, service: Int64, reached: Int64)], parks: [Int: [PlanPoint]],
        companies: (zoned: [PlanPoint], byUse: [LandUse: [PlanPoint]]), civics: (schools: [PlanPoint], hospitals: [PlanPoint])
    ) -> LandValue {
        let base: Int64
        // Decision 728: the use the uses round it lift, none for empty land.
        var use: LandUse?
        if let building = buildings.building(row: row, column: column) {
            base = LandValueRules.base(of: building.use) * LandValueRules.densityFactor(building.density) / 1_000
            use = building.use
        } else if let cell = land.cell(row: row, column: column) {
            base = LandValueRules.base(of: cell.use) * LandValueRules.vacantDensityFactor / 1_000
            use = cell.use
        } else {
            base = LandValueRules.vacantBase * LandValueRules.vacantDensityFactor / 1_000
        }
        let length = Land.cellLength
        let x = Int64(column) * length + length / 2, y = Int64(row) * length + length / 2
        let reach = Land.catchmentRadius * Land.catchmentRadius
        var best: (id: StationID, score: Int64, reached: Int64)?
        for station in stations {
            let dx = x - station.point.x, dy = y - station.point.y
            let squared = dx * dx + dy * dy
            guard squared < reach else { continue }
            let weight = 1_000 - squared * 1_000 / reach
            let score = weight * station.service / 1_000
            // By ascending station, so a tie keeps the lower.
            if best.map({ score > $0.score }) ?? true {
                best = (station.id, score, station.reached)
            }
        }
        let service = LandValueRules.servicePremium * (best?.score ?? 0)
        let access = LandValueRules.accessPremium * (best?.reached ?? 0)
        // Only the rows within the reach can hold a park near enough.
        let parkReach = LandValueRules.parkReach * LandValueRules.parkReach
        let parkRows = Int(LandValueRules.parkReach / Land.cellLength)
        let nearPark = (row - parkRows...row + parkRows).contains { parkRow in
            parks[parkRow]?.contains { park in
                let dx = x - park.x, dy = y - park.y
                return dx * dx + dy * dy < parkReach
            } ?? false
        }
        let park = nearPark ? LandValueRules.parkPremium : 0
        // Decision 98: a zoned cell near the company's buildings.
        let companyReach = LandValueRules.companyReach * LandValueRules.companyReach
        let nearCompany = !companies.zoned.isEmpty && zones.zone(row: row, column: column)?.use != nil && companies.zoned.contains { centre in
            let dx = x - centre.x, dy = y - centre.y
            return dx * dx + dy * dy < companyReach
        }
        // Decision 728: the uses round it, the more of the two, and the
        // drops on top.
        let industry = use.map { Self.industryTenths(at: PlanPoint(x: x, y: y), of: $0, companies.byUse) } ?? (lift: 0, drop: 0)
        let company = max(nearCompany ? LandValueRules.companyPremium : 0, industry.lift * LandValueRules.industryPremiumPerTenth)
            + industry.drop * LandValueRules.industryPremiumPerTenth
        // Decision 111: by the water.
        let water = terrain.isNearWater(row: row, column: column) ? LandValueRules.waterPremium : 0
        // Decision 361's sequel: near the company's schools and hospitals.
        let civic = Self.civicPremium(at: PlanPoint(x: x, y: y), civics)
        return LandValue(
            value: LandValueRules.value(base: base, service: service, access: access, park: park, company: company, water: water, civic: civic),
            base: base, servicePremium: service, accessPremium: access, station: best?.id, parkPremium: park, companyPremium: company,
            waterPremium: water, civicPremium: civic
        )
    }

    // MARK: - Decision 727: what the company's building's land is worth

    /// What the land under `building`'s centre is worth to the company
    /// (decision 727, the subsidiary design's step 2): the cell's
    /// ``landValue(row:column:)`` with its base raised to the floor of the
    /// mean base of the eight cells round it, when that is more. A cell
    /// round it with a city building counts that building's base; one
    /// without counts as vacant land (``LandValueRules/vacantBase``); one
    /// the company's buildings (`building` among them) claim, and one
    /// outside the world, does not count. So a building put up on empty
    /// land is worth what it was, and one whose neighbours have grown is
    /// worth up to what their land is, never more. `nil` outside the world.
    public func companyLandValue(of building: PlacedBuilding) -> LandValue? {
        let row = Land.cellIndex(building.centre.y), column = Land.cellIndex(building.centre.x)
        guard (0..<Land.rows(in: bounds)).contains(row), (0..<Land.columns(in: bounds)).contains(column) else { return nil }
        // Decision 728: a building does not lift its own land.
        let companies = (zoned: landValueCompanies().zoned, byUse: companyCentresByUse(excluding: building.id))
        let value = landValue(row: row, column: column, near: landValueStations(), parks: landValueParks(), companies: companies, civics: landValueCivics())
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        var sum: Int64 = 0, count: Int64 = 0
        for r in (row - 1)...(row + 1) {
            for c in (column - 1)...(column + 1) where (r, c) != (row, column) {
                guard (0..<rows).contains(r), (0..<columns).contains(c),
                      !claimsForItsLand(building, row: r, column: c), !isClaimedByPlacedBuilding(row: r, column: c) else { continue }
                if let city = buildings.building(row: r, column: c) {
                    sum += LandValueRules.base(of: city.use) * LandValueRules.densityFactor(city.density) / 1_000
                } else {
                    sum += LandValueRules.vacantBase * LandValueRules.vacantDensityFactor / 1_000
                }
                count += 1
            }
        }
        guard count > 0, sum / count > value.base else { return value }
        let base = sum / count
        return LandValue(
            value: LandValueRules.value(base: base, service: value.servicePremium, access: value.accessPremium, park: value.parkPremium,
                                        company: value.companyPremium, water: value.waterPremium, civic: value.civicPremium),
            base: base, servicePremium: value.servicePremium, accessPremium: value.accessPremium, station: value.station,
            parkPremium: value.parkPremium, companyPremium: value.companyPremium, waterPremium: value.waterPremium, civicPremium: value.civicPremium
        )
    }

    /// Whether `building`, placed or not, claims the cell at `row`,
    /// `column` as ``isClaimedByPlacedBuilding(row:column:side:)`` asks of
    /// the placed ones.
    private func claimsForItsLand(_ building: PlacedBuilding, row: Int, column: Int) -> Bool {
        if areaBuyOut { return Self.area(of: building, onRow: row, column: column) == Land.cellArea }
        return Self.claims(building, row: row, column: column, side: cityBuildingSide(row: row, column: column))
    }

    /// The centres of the company's schools and of its hospitals
    /// (decision 361's sequel).
    func landValueCivics() -> (schools: [PlanPoint], hospitals: [PlanPoint]) {
        (placedBuildings.filter { $0.kind == .school }.map(\.centre), placedBuildings.filter { $0.kind == .hospital }.map(\.centre))
    }

    /// Whether `point` lies within ``LandValueRules/civicReach`` of the
    /// centre of one of `civics`' schools, and of one of its hospitals
    /// (decision 361's sequel).
    static func isNearCivics(_ point: PlanPoint, _ civics: (schools: [PlanPoint], hospitals: [PlanPoint])) -> (school: Bool, hospital: Bool) {
        let reach = LandValueRules.civicReach * LandValueRules.civicReach
        func near(_ centres: [PlanPoint]) -> Bool {
            centres.contains { centre in
                let dx = point.x - centre.x, dy = point.y - centre.y
                return dx * dx + dy * dy < reach
            }
        }
        return (near(civics.schools), near(civics.hospitals))
    }

    /// What `point` is worth more near the company's schools and hospitals
    /// `civics` (decision 361's sequel): ``LandValueRules/schoolPremium``
    /// near a school and ``LandValueRules/hospitalPremium`` near a
    /// hospital, added; several of a kind count once.
    static func civicPremium(at point: PlanPoint, _ civics: (schools: [PlanPoint], hospitals: [PlanPoint])) -> Int64 {
        let near = isNearCivics(point, civics)
        return (near.school ? LandValueRules.schoolPremium : 0) + (near.hospital ? LandValueRules.hospitalPremium : 0)
    }
}
