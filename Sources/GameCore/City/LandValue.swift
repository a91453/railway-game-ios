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
//     value = clamp(base + 15 × S + 1000 × A, 500, 50000)   cents a m²
//
// - B, the use's base: 1,000 for an empty cell, 2,000 homes, 3,000 shops,
//   3,500 offices;
// - D, the density's factor in thousandths: 1,000, 1,250, 1,600, 2,000 for
//   D1 to D4 (existing stock is D4), 1,000 without a building;
// - S and A, the best station's service: of the stations whose catchment
//   reaches the cell (d² < R², R = 800 m) and that served some of their
//   trips on the last measured day (``TownGrowth/Place/lastService`` > 0),
//   the one with the highest `floor(w × lastService / 1000)`, where `w =
//   1000 − floor(d² × 1000 / R²)` (ties to the lower station); S is that
//   score, A its ``TownGrowth/Place/lastReached``.
//
// The value reads the world and changes nothing: growth and raising
// buildings (decision 75) never read it.

/// What a cell of land is worth, in cents a m², and its parts.
public struct LandValue: Hashable, Sendable {
    /// `clamp(base + servicePremium + accessPremium, minimum, maximum)`.
    public let value: Int64
    /// `floor(B × D / 1000)`: the use's base by the density's factor.
    public let base: Int64
    /// ``LandValueRules/servicePremium`` × S.
    public let servicePremium: Int64
    /// ``LandValueRules/accessPremium`` × A.
    public let accessPremium: Int64
    /// The station S and A are measured at, or `nil` when none is.
    public let station: StationID?

    public init(value: Int64, base: Int64, servicePremium: Int64, accessPremium: Int64, station: StationID?) {
        self.value = value
        self.base = base
        self.servicePremium = servicePremium
        self.accessPremium = accessPremium
        self.station = station
    }
}

/// The numbers of land value (Phase 6c-3): this project's (gap).
public enum LandValueRules {
    /// B for a cell with no land and no building, in cents a m².
    public static let vacantBase: Int64 = 1_000

    /// B for a use, in cents a m².
    public static func base(of use: LandUse) -> Int64 {
        switch use {
        case .residential: 2_000
        case .commercial: 3_000
        case .office: 3_500
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
    public static let servicePremium: Int64 = 15
    /// Cents a m² for each station the best station reached (0 to 5).
    public static let accessPremium: Int64 = 1_000
    /// The least and the most a cell is worth, in cents a m².
    public static let minimum: Int64 = 500
    public static let maximum: Int64 = 50_000

    /// `base + service + access` within ``minimum`` … ``maximum``.
    static func value(base: Int64, service: Int64, access: Int64) -> Int64 {
        min(maximum, max(minimum, base + service + access))
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
        return landValue(row: row, column: column, near: landValueStations())
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
        let stations = landValueStations()
        var values: [LandValue] = []
        values.reserveCapacity(rows.count * columns.count)
        for row in rows {
            for column in columns {
                values.append(landValue(row: row, column: column, near: stations))
            }
        }
        return values
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

    private func landValue(row: Int, column: Int, near stations: [(id: StationID, point: PlanPoint, service: Int64, reached: Int64)]) -> LandValue {
        let base: Int64
        if let building = buildings.building(row: row, column: column) {
            base = LandValueRules.base(of: building.use) * LandValueRules.densityFactor(building.density) / 1_000
        } else if let cell = land.cell(row: row, column: column) {
            base = LandValueRules.base(of: cell.use) * LandValueRules.vacantDensityFactor / 1_000
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
        return LandValue(
            value: LandValueRules.value(base: base, service: service, access: access),
            base: base, servicePremium: service, accessPremium: access, station: best?.id
        )
    }
}
