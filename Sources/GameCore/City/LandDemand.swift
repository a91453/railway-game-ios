// Demand from land (Phase 6b, ARCHITECTURE decision 73): a managed
// company's stations draw their ridership from the land round them, and
// the land round well-served stations grows and spreads, the A-Train loop
// of a railway that makes its city.
//
// The owner's references have no rule for it (the study, PR #172): `Ci/`
// works a station's flows out on a server it does not ship
// (`/api/flowFull`), and the reference pack names OpenTTD's towns only by
// path. So the rules are this project's (gap), built on what the game
// already has:
//
// - every resident and every job of a station's catchment makes 40 trips a
//   day for every 100 (the real-world ridership's 40 per 100 residents,
//   decision 50): homes send people out in the morning, offices and shops
//   in the evening, and the existing gravity model sends each station's
//   trips to the others in proportion to theirs;
// - a station's kind (its hours) is what most of its catchment is: homes,
//   offices or shops;
// - a cell within reach of several stations is shared among them by
//   nearness, so no one is counted twice;
// - each midnight a station's daily growth rate (decision 70's: up to 1.5 %
//   a day for good service and stations reached) grows the people of its
//   catchment, and a growing station builds one new cell a day at the edge
//   of its town, nearest to it. Land never shrinks.
//
// Old saves and free play keep each station's own ridership: land drives it
// only where ``GameWorld/landDemand`` is on (the app's new games) and the
// company is managed.

/// The rules of demand from land (Phase 6b).
public enum LandDemand {
    /// Trips a day for every 100 residents and jobs of a station's share.
    public static let tripsPerHundred: Int64 = 40
    /// The residents of a cell a growing station builds.
    public static let newCellResidents: Int64 = 4
    /// How many residents, and how many jobs, growth fills a cell to: some
    /// 98,000 and 290,000 a km², a dense city's centre. Land set or
    /// imported above it keeps what it has and does not grow.
    public static let grownResidents: Int64 = 400
    public static let grownJobs: Int64 = 1_200

    /// What a station's share of the land holds.
    public struct Share: Hashable, Sendable {
        public var residents: Int64 = 0
        /// Jobs in offices, and in shops (with any jobs in homes).
        public var officeJobs: Int64 = 0
        public var shopJobs: Int64 = 0

        public init(residents: Int64 = 0, officeJobs: Int64 = 0, shopJobs: Int64 = 0) {
            self.residents = residents
            self.officeJobs = officeJobs
            self.shopJobs = shopJobs
        }

        /// The ridership it makes: ``tripsPerHundred`` for every 100
        /// residents and jobs, rounded half up, at most
        /// ``StationDemand/maximumDailyTrips``, of the kind most of it is
        /// (homes, then offices, then shops on a tie); `nil` for none.
        public var demand: StationDemand? {
            let people = residents + officeJobs + shopJobs
            let trips = min(StationDemand.maximumDailyTrips, (people * tripsPerHundred + 50) / 100)
            guard trips > 0 else { return nil }
            let kind: StationDemandKind = residents >= officeJobs && residents >= shopJobs
                ? .residential
                : officeJobs >= shopJobs ? .office : .shopping
            return StationDemand(kind: kind, dailyTrips: trips)
        }
    }

    /// Each station's share of `land`: every cell whose middle lies within
    /// ``Land/catchmentRadius`` of one or more stations is shared among
    /// them in proportion to `1000 − 1000 d² / R²` (1 to 1000, nearer more)
    /// by the largest remainder, ties to the lower station; its residents
    /// and jobs separately. Stations reaching no land have none.
    public static func shares(of land: Land, among stations: [Station]) -> [StationID: Share] {
        let radius = Land.catchmentRadius
        let squaredRadius = radius * radius
        // Each cell's stations (in the stations' order) and their weights.
        var reaching: [Int: [(station: Int, weight: Int64)]] = [:]
        for (position, station) in stations.enumerated() {
            land.forEachCell(within: radius, of: station.location) { index, squared in
                reaching[index, default: []].append((position, 1_000 - squared * 1_000 / squaredRadius))
            }
        }
        var shares: [StationID: Share] = [:]
        for index in reaching.keys.sorted() {
            guard let near = reaching[index] else { continue }
            let cell = land.cells[index]
            let weights = near.map(\.weight)
            let residents = GameWorld.apportion(cell.residents, by: weights)
            let jobs = GameWorld.apportion(cell.jobs, by: weights)
            for (offset, entry) in near.enumerated() {
                var share = shares[stations[entry.station].id, default: Share()]
                share.residents += residents[offset]
                if cell.use == .office {
                    share.officeJobs += jobs[offset]
                } else {
                    share.shopJobs += jobs[offset]
                }
                shares[stations[entry.station].id] = share
            }
        }
        return shares
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns demand from land on or off (Phase 6b). On, a managed
    /// company's stations take their ridership from the land round them
    /// at once, whenever a station is built or the land changes, and each
    /// midnight, and the land grows instead of each station's ridership
    /// (town growth, decision 70, measures it). Off, every station keeps
    /// the ridership it has, which the player may then set.
    public mutating func setLandDemand(_ enabled: Bool) {
        guard enabled != landDemand else { return }
        landDemand = enabled
        refreshLandDemand()
    }

    // MARK: - Deriving

    /// Whether the land sets the stations' ridership now: demand from land
    /// is on and the company is managed.
    var drawsDemandFromLand: Bool {
        landDemand && accounts.mode == .management
    }

    /// Gives every station the ridership of its share of the land (see
    /// ``LandDemand/shares(of:among:)``), when the land sets it.
    /// Passengers already waiting stay.
    mutating func refreshLandDemand() {
        guard drawsDemandFromLand else { return }
        let shares = LandDemand.shares(of: land, among: stations)
        var changed = false
        for station in stations {
            let demand = shares[station.id]?.demand
            if let index = passengers.firstIndex(where: { $0.station == station.id }) {
                guard passengers[index].demand != demand else { continue }
                passengers[index].demand = demand
                if passengers[index].isEmpty {
                    passengers.remove(at: index)
                }
                changed = true
            } else if let demand {
                var record = StationPassengers(station: station.id)
                record.demand = demand
                passengers.insert(record, at: passengers.firstIndex { $0.station > station.id } ?? passengers.count)
                changed = true
            }
        }
        if changed {
            passengerPlan = PassengerPlanCache()
        }
    }

    // MARK: - Growth

    /// Midnight's growth of the land (Phase 6b), from the day that ended,
    /// in place of each station's (decision 70): `reached` is how many
    /// stations each origin's passengers could reach in that day's plan.
    ///
    /// Each station with ridership that town growth has seen before gets
    /// decision 70's rate from yesterday's service; then, by ascending
    /// station, each with a positive rate `g`:
    ///
    /// - adds `(R × g + 500) / 1000` residents (at least 1) to its share's
    ///   `R` residents and likewise jobs, shared among the cells of its
    ///   catchment by their residents (jobs) by the largest remainder, each
    ///   filled to at most ``LandDemand/grownResidents``
    ///   (``LandDemand/grownJobs``); what does not fit is not added;
    /// - builds one new home of ``LandDemand/newCellResidents``: the empty
    ///   cell of its catchment, in the world, beside (north, south, east
    ///   or west of) a cell with people, nearest the station (then by row
    ///   and column), with its building (D1 homes) when the city's
    ///   buildings are on (Phase 6c-1).
    ///
    /// The stations' ridership then follows the land, and each station's
    /// last growth is how its daily trips changed, in thousandths.
    mutating func growLand(reached: [StationID: Int]) {
        guard var growth = townGrowth, drawsDemandFromLand else { return }
        var places: [TownGrowth.Place] = []
        var growing: [(station: Station, rate: Int64)] = []
        var before: [StationID: Int64] = [:]
        for record in passengers {
            guard let demand = record.demand, demand.dailyTrips > 0, let station = station(id: record.station) else { continue }
            before[record.station] = demand.dailyTrips
            guard var place = growth.places.first(where: { $0.station == record.station }) else {
                places.append(TownGrowth.Place(station: record.station, base: demand.dailyTrips, counted: record.arrived))
                continue
            }
            let served = record.arrived - place.counted
            place.counted = record.arrived
            places.append(place)
            let rate = TownGrowth.growth(served: served, trips: demand.dailyTrips, reached: reached[record.station] ?? 0)
            if rate > 0 {
                growing.append((station, rate))
            }
        }
        if !growing.isEmpty {
            let shares = LandDemand.shares(of: land, among: stations)
            for (station, rate) in growing {
                let share = shares[station.id] ?? LandDemand.Share()
                let jobs = share.officeJobs + share.shopJobs
                grow(around: station, residents: Self.grown(share.residents, rate), jobs: Self.grown(jobs, rate))
                spread(towards: station)
            }
        }
        refreshLandDemand()
        for index in places.indices {
            let id = places[index].station
            guard let was = before[id], was > 0 else { continue }
            let now = stationDemand(of: id)?.dailyTrips ?? 0
            places[index].lastGrowth = max(-1_000, min(1_000, (now - was) * 1_000 / was))
        }
        growth.places = places
        townGrowth = growth
    }

    /// What `amount` grows by in a day at `rate` thousandths: rounded half
    /// up, at least 1 of anything.
    static func grown(_ amount: Int64, _ rate: Int64) -> Int64 {
        guard amount > 0, rate > 0 else { return 0 }
        return max(1, (amount * rate + 500) / 1_000)
    }

    /// Adds `residents` and `jobs` to the cells of `station`'s catchment,
    /// shared by their residents (jobs) by the largest remainder, each cell
    /// filled to at most its growth limit.
    private mutating func grow(around station: Station, residents: Int64, jobs: Int64) {
        var indices: [Int] = []
        land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in
            indices.append(index)
        }
        let addedResidents = Self.apportion(residents, by: indices.map { land.cells[$0].residents })
        let addedJobs = Self.apportion(jobs, by: indices.map { land.cells[$0].jobs })
        for (offset, index) in indices.enumerated() {
            let cell = land.cells[index]
            let newResidents = cell.residents >= LandDemand.grownResidents
                ? cell.residents : min(LandDemand.grownResidents, cell.residents + addedResidents[offset])
            let newJobs = cell.jobs >= LandDemand.grownJobs ? cell.jobs : min(LandDemand.grownJobs, cell.jobs + addedJobs[offset])
            land.cells[index] = LandCell(row: cell.row, column: cell.column, use: cell.use, residents: newResidents, jobs: newJobs)
        }
    }

    /// Builds the new home of a growing `station` (see ``growLand(reached:)``),
    /// if its catchment has an empty cell beside one with people.
    private mutating func spread(towards station: Station) {
        let radius = Land.catchmentRadius, length = Land.cellLength
        let point = station.location
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let firstRow = max(0, Land.cellIndex(point.y - radius)), lastRow = min(rows - 1, Land.cellIndex(point.y + radius))
        let firstColumn = max(0, Land.cellIndex(point.x - radius)), lastColumn = min(columns - 1, Land.cellIndex(point.x + radius))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }
        var best: (squared: Int64, row: Int, column: Int)?
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let dx = Int64(column) * length + length / 2 - point.x
                let dy = Int64(row) * length + length / 2 - point.y
                let squared = dx * dx + dy * dy
                guard squared < radius * radius, land.cell(row: row, column: column) == nil else { continue }
                if let best, (best.squared, best.row, best.column) <= (squared, row, column) { continue }
                let beside = [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
                guard beside.contains(where: { land.cell(row: $0.0, column: $0.1) != nil }) else { continue }
                best = (squared, row, column)
            }
        }
        guard let best else { return }
        addLand(LandCell(row: best.row, column: best.column, use: .residential, residents: LandDemand.newCellResidents, jobs: 0))
    }
}
