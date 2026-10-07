import GameCore

/// The travel demand and demand change layers (`travel` and `movement` of
/// the reference's `panel-poptravel`), worked out from the world: the trips
/// that start at each station in each hour (``GameWorld/stationFlow(of:)``,
/// the sums of `GameWorld.hourlyDemand(from:to:)`) gathered on a grid of
/// 1 km squares, as the reference draws its hourly `heat_grid`.
///
/// The reference's hourly grids come from its server ("AI模拟", not in the
/// snapshot) with each square's grade (`g`, `g_abs` and `sign`) already
/// worked out; here a square's grade is its trips against the busiest
/// square of the whole day (``PopTravel/grade(_:maximum:)``), so playing
/// the hours shows the day rise and fall. Demand change is, as the
/// reference describes it ("相邻小时出行需求量的增减"), the change from the
/// hour before (hour 0 against hour 23), so it needs no history: GameCore
/// keeps no record of past days, and the demand model gives every hour.
///
/// Presentation only: worked out when the stations or their demand change,
/// never stored.
public struct TravelDemandMap: Hashable, Sendable {
    /// A square of the grid: whole multiples of ``cellUnits`` from the
    /// world's origin.
    public struct Cell: Hashable, Sendable, Comparable {
        public let column: Int
        public let row: Int

        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }

        public static func < (lhs: Cell, rhs: Cell) -> Bool {
            (lhs.row, lhs.column) < (rhs.row, rhs.column)
        }
    }

    /// One square to fill.
    public struct Tile: Hashable, Sendable {
        public let minX: Double
        public let minY: Double
        public let maxX: Double
        public let maxY: Double
        /// Its colour (``PopTravel/travelColors``, ``PopTravel/increaseColors``
        /// or ``PopTravel/decreaseColors``).
        public let color: PopTravel.RGB
        /// Trips in the hour, or the change from the hour before.
        public let value: Int64
    }

    /// A square's side: 1 km.
    public static let cellMetres: Int64 = 1_000
    public static var cellUnits: Int64 {
        cellMetres * WorldCoordinate.unitsPerMetre
    }

    /// The trips starting in each square in each hour (24 a square).
    public let trips: [Cell: [Int64]]
    /// The most trips any square has in any hour.
    public let busiest: Int64
    /// The largest change from one hour to the next of any square.
    public let largestChange: Int64

    public init(trips: [Cell: [Int64]]) {
        self.trips = trips
        busiest = trips.values.lazy.flatMap { $0 }.max() ?? 0
        largestChange = trips.values.lazy.map { hours in
            hours.indices.lazy.map { abs(Self.change(in: hours, at: $0)) }.max() ?? 0
        }.max() ?? 0
    }

    /// The change in `hours` at `hour` from the hour before (23 before 0).
    static func change(in hours: [Int64], at hour: Int) -> Int64 {
        guard hours.count == 24 else { return 0 }
        let hour = PopTravel.clampedHour(hour)
        return hours[hour] - hours[(hour + 23) % 24]
    }

    /// The trips starting in `cell` in `hour`.
    public func trips(in cell: Cell, at hour: Int) -> Int64 {
        trips[cell].map { $0[PopTravel.clampedHour(hour)] } ?? 0
    }

    /// The change in `cell` at `hour` from the hour before.
    public func change(in cell: Cell, at hour: Int) -> Int64 {
        trips[cell].map { Self.change(in: $0, at: hour) } ?? 0
    }

    /// The squares to fill for `mode` at `hour` (nothing for a layer that
    /// does not follow the hour), in a fixed order; a square of grade 0 is
    /// left out, as the reference's `rgba(0,0,0,0)`.
    public func tiles(for mode: PopTravelMode, at hour: Int) -> [Tile] {
        guard mode.usesHour else { return [] }
        let size = Double(Self.cellUnits)
        return trips.keys.sorted().compactMap { cell in
            let value: Int64
            let color: PopTravel.RGB
            if mode == .travel {
                value = trips(in: cell, at: hour)
                let grade = PopTravel.grade(value, maximum: busiest)
                guard grade > 0 else { return nil }
                color = PopTravel.travelColors[grade - 1]
            } else {
                value = change(in: cell, at: hour)
                let grade = PopTravel.grade(abs(value), maximum: largestChange)
                guard grade > 0 else { return nil }
                color = value < 0 ? PopTravel.decreaseColors[grade - 1] : PopTravel.increaseColors[grade - 1]
            }
            let x = Double(cell.column) * size, y = Double(cell.row) * size
            return Tile(minX: x, minY: y, maxX: x + size, maxY: y + size, color: color, value: value)
        }
    }

    /// The square a world point lies in.
    public static func cell(atX x: Int64, y: Int64) -> Cell {
        Cell(column: Int(floorDivide(x, cellUnits)), row: Int(floorDivide(y, cellUnits)))
    }

    private static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let quotient = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? quotient - 1 : quotient
    }
}

extension GameWorld {
    /// The travel demand map of this world (see ``TravelDemandMap``): each
    /// station's trips in each hour (``stationFlow(of:)``'s entries) in the
    /// square it stands in.
    public func travelDemandMap() -> TravelDemandMap {
        var trips: [TravelDemandMap.Cell: [Int64]] = [:]
        for station in stations {
            guard let flow = stationFlow(of: station.id), flow.entries.count == 24 else { continue }
            let cell = TravelDemandMap.cell(atX: station.location.x, y: station.location.y)
            var hours = trips[cell] ?? Array(repeating: 0, count: 24)
            for hour in 0..<24 {
                hours[hour] += flow.entries[hour]
            }
            trips[cell] = hours
        }
        return TravelDemandMap(trips: trips)
    }
}
