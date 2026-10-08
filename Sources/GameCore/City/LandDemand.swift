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
//   of its town, nearest to it. Land never shrinks;
// - with the city's buildings on (Phase 6c-2, decision 75), a cell grows to
//   its building's capacity, and a station that served most of its trips
//   raises up to two full buildings of its catchment a density each night.
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
    /// How many residents, and how many jobs, growth fills a cell to
    /// without the city's buildings: some 98,000 and 290,000 a km², a dense
    /// city's centre. Land set or imported above it keeps what it has and
    /// does not grow. With the city's buildings on, each cell's building
    /// sets them instead (Phase 6c-2, ARCHITECTURE decision 75).
    public static let grownResidents: Int64 = 400
    public static let grownJobs: Int64 = 1_200

    // Raising the city's buildings (Phase 6c-2, ARCHITECTURE decision 75):
    // this project's numbers (gap), the study's §7.2.

    /// How many buildings a growing station raises a night, at most.
    public static let upgradesPerStation = 2
    /// The share of its trips a station must have served the day before, in
    /// thousandths, to raise buildings: 80 %.
    public static let upgradeService: Int64 = 800
    /// The stations its passengers must have reached the day before.
    public static let upgradeReached: Int64 = 1

    /// What a station's share of the land holds.
    public struct Share: Hashable, Sendable {
        public var residents: Int64 = 0
        /// Jobs in offices (and, since decision 91, in factories and on
        /// farms, which commute as offices do), and in shops (with any jobs
        /// in homes).
        public var officeJobs: Int64 = 0
        public var shopJobs: Int64 = 0
        /// Decision 91: the jobs, pupils and patients of schools, hospitals
        /// and public offices, and the visitors of sights.
        public var civicJobs: Int64 = 0
        public var leisureJobs: Int64 = 0

        public init(residents: Int64 = 0, officeJobs: Int64 = 0, shopJobs: Int64 = 0, civicJobs: Int64 = 0, leisureJobs: Int64 = 0) {
            self.residents = residents
            self.officeJobs = officeJobs
            self.shopJobs = shopJobs
            self.civicJobs = civicJobs
            self.leisureJobs = leisureJobs
        }

        /// The ridership it makes: ``tripsPerHundred`` for every 100
        /// residents and jobs, rounded half up, at most
        /// ``StationDemand/maximumDailyTrips``, of the kind most of it is
        /// (homes, then offices, then shops, then schools and public
        /// offices, then sights on a tie); `nil` for none.
        public var demand: StationDemand? {
            let people = residents + officeJobs + shopJobs + civicJobs + leisureJobs
            let trips = min(StationDemand.maximumDailyTrips, (people * tripsPerHundred + 50) / 100)
            guard trips > 0 else { return nil }
            let kinds: [(StationDemandKind, Int64)] = [
                (.residential, residents), (.office, officeJobs), (.shopping, shopJobs), (.civic, civicJobs), (.scenic, leisureJobs),
            ]
            // The first of the most, so the order above settles a tie.
            var kind = kinds[0]
            for candidate in kinds.dropFirst() where candidate.1 > kind.1 {
                kind = candidate
            }
            return StationDemand(kind: kind.0, dailyTrips: trips)
        }
    }

    /// Each station's share of `land`: every cell whose middle lies within
    /// ``Land/catchmentRadius`` of one or more stations is shared among
    /// them in proportion to `1000 − 1000 d² / R²` (1 to 1000, nearer more)
    /// by the largest remainder, ties to the lower station; its residents
    /// and jobs separately. Stations reaching no land have none.
    ///
    /// Decision 94: each building the player placed with someone in it is
    /// shared the same way after the cells, by ascending ID, as a point at
    /// its centre with its residents and jobs and its kind's use.
    public static func shares(of land: Land, among stations: [Station], placed: [PlacedBuilding] = []) -> [StationID: Share] {
        let radius = Land.catchmentRadius
        let squaredRadius = radius * radius
        // Each cell's stations (in the stations' order) and their weights,
        // by cell and then station.
        var reaching: [(cell: Int, station: Int, weight: Int64)] = []
        for (position, station) in stations.enumerated() {
            land.forEachCell(within: radius, of: station.location) { index, squared in
                reaching.append((index, position, 1_000 - squared * 1_000 / squaredRadius))
            }
        }
        reaching.sort { ($0.cell, $0.station) < ($1.cell, $1.station) }
        var byStation = [Share?](repeating: nil, count: stations.count)
        func add(_ residents: Int64, _ jobs: Int64, of use: LandUse, to station: Int) {
            var share = byStation[station] ?? Share()
            share.residents += residents
            switch use {
            case .office, .industrial, .agricultural:
                share.officeJobs += jobs
            case .civic:
                share.civicJobs += jobs
            case .leisure:
                share.leisureJobs += jobs
            case .residential, .commercial, .park:
                share.shopJobs += jobs
            }
            byStation[station] = share
        }
        var start = 0
        while start < reaching.count {
            var end = start + 1
            while end < reaching.count, reaching[end].cell == reaching[start].cell {
                end += 1
            }
            let cell = land.cells[reaching[start].cell]
            if end - start == 1 {
                // One station has it all, as the largest remainder of one
                // weight gives.
                add(cell.residents, cell.jobs, of: cell.use, to: reaching[start].station)
            } else {
                let near = reaching[start..<end]
                let weights = near.map(\.weight)
                let residents = GameWorld.apportion(cell.residents, by: weights)
                let jobs = GameWorld.apportion(cell.jobs, by: weights)
                for (offset, entry) in near.enumerated() {
                    add(residents[offset], jobs[offset], of: cell.use, to: entry.station)
                }
            }
            start = end
        }
        for building in placed where building.residents + building.jobs > 0 {
            let near = stations.enumerated().compactMap { position, station -> (station: Int, weight: Int64)? in
                let dx = building.centre.x - station.location.x, dy = building.centre.y - station.location.y
                let squared = dx * dx + dy * dy
                return squared < squaredRadius ? (position, 1_000 - squared * 1_000 / squaredRadius) : nil
            }
            guard !near.isEmpty else { continue }
            let weights = near.map(\.weight)
            let residents = GameWorld.apportion(building.residents, by: weights)
            let jobs = GameWorld.apportion(building.jobs, by: weights)
            for (offset, entry) in near.enumerated() {
                add(residents[offset], jobs[offset], of: building.kind.use, to: entry.station)
            }
        }
        var shares: [StationID: Share] = [:]
        for (position, share) in byStation.enumerated() {
            if let share {
                shares[stations[position].id] = share
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
    /// the ridership it has, which the player may then set. Either way town
    /// growth starts again, as after ``setStationDemand(_:to:)``: the start
    /// it kept for a station would pull the other rule's ridership back to
    /// it, and its growth would be out of range.
    public mutating func setLandDemand(_ enabled: Bool) {
        guard enabled != landDemand else { return }
        landDemand = enabled
        townGrowth?.places = []
        refreshLandDemand()
    }

    // MARK: - Deriving

    /// Whether the land sets the stations' ridership now: demand from land
    /// is on and the company is managed.
    var drawsDemandFromLand: Bool {
        landDemand && accounts.mode == .management
    }

    /// The stations the land is shared among: all but the closed ones
    /// (decision 77), whose catchments go back to their neighbours. A
    /// station whose passengers may only not set out (flow control) keeps
    /// its share.
    var landStations: [Station] {
        stations.filter { $0.operationMode != .closed }
    }

    /// Gives every station the ridership of its share of the land (see
    /// ``LandDemand/shares(of:among:)``), when the land sets it; a closed
    /// station has none (decision 77). Passengers already waiting stay.
    mutating func refreshLandDemand() {
        guard drawsDemandFromLand else { return }
        // Decision 94: the people in the player's buildings ride too.
        let shares = LandDemand.shares(of: land, among: landStations, placed: placedBuildings)
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
    /// - with the city's buildings on, if it served at least
    ///   ``LandDemand/upgradeService`` thousandths of its trips and reached
    ///   at least ``LandDemand/upgradeReached`` stations (Phase 6c-2), raises
    ///   up to ``LandDemand/upgradesPerStation`` city buildings of its
    ///   catchment by one density, by row and column: those below D4 that
    ///   were full when the midnight began (their main count, residents of
    ///   homes or jobs of shops and offices, at their table's; decision 77),
    ///   each at most once a night (a cell a lower station raised is passed
    ///   over);
    /// - adds `(R × g + 500) / 1000` residents (at least 1) to its share's
    ///   `R` residents and likewise jobs, shared among the cells of its
    ///   catchment by their residents (jobs) by the largest remainder, each
    ///   filled to at most its building's capacity with the city's buildings
    ///   on (Phase 6c-2), else ``LandDemand/grownResidents``
    ///   (``LandDemand/grownJobs``); a count already there keeps what it
    ///   has, and what does not fit is not added;
    /// - builds one new home of ``LandDemand/newCellResidents``: the empty
    ///   cell of its catchment, in the world, beside (north, south, east
    ///   or west of) a cell with people, nearest the station (then by row
    ///   and column), with its building (D1 homes) when the city's
    ///   buildings are on (Phase 6c-1); since decision 98, the zoned empty
    ///   cell worth most first, with its zone's use (``spread(towards:)``).
    ///
    /// Decision 98: cells zoned no development neither grow nor are raised.
    ///
    /// Each station growth has seen before records that day's service share
    /// and stations reached (``TownGrowth/Place/lastService``,
    /// ``TownGrowth/Place/lastReached``). The stations' ridership then
    /// follows the land, and each station's last growth is how its daily
    /// trips changed, in thousandths.
    mutating func growLand(reached: [StationID: Int]) {
        guard var growth = townGrowth, drawsDemandFromLand else { return }
        var places: [TownGrowth.Place] = []
        var growing: [(station: Station, rate: Int64, raises: Bool)] = []
        var before: [StationID: Int64] = [:]
        for record in passengers {
            guard let demand = record.demand, demand.dailyTrips > 0, let station = station(id: record.station) else { continue }
            before[record.station] = demand.dailyTrips
            guard var place = growth.places.first(where: { $0.station == record.station }) else {
                places.append(TownGrowth.Place(station: record.station, base: demand.dailyTrips, counted: record.arrived))
                continue
            }
            let served = record.arrived - place.counted
            let stationReached = reached[record.station] ?? 0
            place.counted = record.arrived
            place.lastService = TownGrowth.serviceShare(served: served, trips: demand.dailyTrips)
            place.lastReached = TownGrowth.reachedCount(stationReached)
            places.append(place)
            let rate = TownGrowth.growth(served: served, trips: demand.dailyTrips, reached: stationReached)
            if rate > 0 {
                let raises = place.lastService >= LandDemand.upgradeService && place.lastReached >= LandDemand.upgradeReached
                growing.append((station, rate, raises))
            }
        }
        if !growing.isEmpty {
            let shares = LandDemand.shares(of: land, among: landStations)
            // Phase 6c-2: the buildings full as the midnight begins, and
            // those raised tonight (membership only: the order is the
            // stations' and the cells').
            let full = cityBuildings ? fullBuildingCells() : []
            var raised: Set<CellPosition> = []
            for (station, rate, raises) in growing {
                if raises, !full.isEmpty {
                    raiseBuildings(around: station, full: full, raised: &raised)
                }
                let share = shares[station.id] ?? LandDemand.Share()
                let jobs = share.officeJobs + share.shopJobs + share.civicJobs + share.leisureJobs
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
        // Decision 94: the company's buildings fill or empty by the service
        // measured tonight, and their riders count from now.
        if !placedBuildings.isEmpty {
            fillPlacedBuildings()
            refreshLandDemand()
        }
    }

    /// What `amount` grows by in a day at `rate` thousandths: rounded half
    /// up, at least 1 of anything.
    static func grown(_ amount: Int64, _ rate: Int64) -> Int64 {
        guard amount > 0, rate > 0 else { return 0 }
        return max(1, (amount * rate + 500) / 1_000)
    }

    /// The cells of the city buildings below D4 that are full: their main
    /// count (residents of homes, jobs of shops and offices) at or above the
    /// table's (decision 77).
    private func fullBuildingCells() -> Set<CellPosition> {
        var full: Set<CellPosition> = []
        for cell in land.cells {
            guard let building = buildings.building(row: cell.row, column: cell.column),
                  building.kind == .city, building.density < .d4
            else { continue }
            // Decision 77: full by its main count only (residents of homes,
            // jobs of shops and offices), the count its density was chosen
            // by; the other count's capacity is what the cell already holds
            // whenever that is above the table's, so it would make nearly
            // every mixed cell of a real-world map full.
            let table = Building.tableCapacity(of: building.use, building.density)
            let main = Building.mainCount(of: building.use, residents: table.residents, jobs: table.jobs)
            if main > 0, Building.mainCount(of: building.use, residents: cell.residents, jobs: cell.jobs) >= main {
                full.insert(cell.position)
            }
        }
        return full
    }

    /// Raises up to ``LandDemand/upgradesPerStation`` of the `full`
    /// buildings of `station`'s catchment that no station has `raised`
    /// tonight by one density, by row and then column.
    mutating func raiseBuildings(around station: Station, full: Set<CellPosition>, raised: inout Set<CellPosition>) {
        var cells: [CellPosition] = []
        land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in
            let position = land.cells[index].position
            // Decision 98: nothing is raised on land zoned no development.
            if full.contains(position), !raised.contains(position), allowsGrowth(row: position.row, column: position.column) {
                cells.append(position)
            }
        }
        for position in cells.prefix(LandDemand.upgradesPerStation) {
            buildings.raise(at: position)
            raised.insert(position)
        }
    }

    /// Adds `residents` and `jobs` to the cells of `station`'s catchment,
    /// shared by their residents (jobs) by the largest remainder, each cell
    /// filled to at most its growth limit: its building's capacity with the
    /// city's buildings on (Phase 6c-2), else the fixed limits.
    mutating func grow(around station: Station, residents: Int64, jobs: Int64) {
        var indices: [Int] = []
        land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in
            indices.append(index)
        }
        let addedResidents = Self.apportion(residents, by: indices.map { land.cells[$0].residents })
        let addedJobs = Self.apportion(jobs, by: indices.map { land.cells[$0].jobs })
        for (offset, index) in indices.enumerated() {
            let cell = land.cells[index]
            // Decision 98: nothing grows on land zoned no development; its
            // share is not added.
            guard allowsGrowth(row: cell.row, column: cell.column) else { continue }
            let capacity = cityBuildings ? buildings.building(row: cell.row, column: cell.column)?.capacity(on: cell) : nil
            let residentLimit = capacity?.residents ?? LandDemand.grownResidents
            let jobLimit = capacity?.jobs ?? LandDemand.grownJobs
            let newResidents = cell.residents >= residentLimit ? cell.residents : min(residentLimit, cell.residents + addedResidents[offset])
            let newJobs = cell.jobs >= jobLimit ? cell.jobs : min(jobLimit, cell.jobs + addedJobs[offset])
            land.cells[index] = LandCell(row: cell.row, column: cell.column, use: cell.use, residents: newResidents, jobs: newJobs)
        }
    }

    /// Builds the new cell of a growing `station` (see ``growLand(reached:)``),
    /// on an empty cell of its catchment that none of the company's
    /// buildings claims (decision 95):
    ///
    /// - decision 98: if any such cell is zoned for a use, the one worth
    ///   most (``landValue(row:column:)``; then the nearest, then by row
    ///   and column), with that use and its zone's new cell
    ///   (``Zone/newCell``), whether or not people live beside it;
    /// - else a new home of ``LandDemand/newCellResidents`` on the one
    ///   nearest the station (then by row and column) beside (north, south,
    ///   east or west of) a cell with people, none zoned: a cell zoned no
    ///   development or reserved is passed over.
    ///
    /// A world without zones builds as before decision 98.
    mutating func spread(towards station: Station) {
        let radius = Land.catchmentRadius, length = Land.cellLength
        let point = station.location
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let firstRow = max(0, Land.cellIndex(point.y - radius)), lastRow = min(rows - 1, Land.cellIndex(point.y + radius))
        let firstColumn = max(0, Land.cellIndex(point.x - radius)), lastColumn = min(columns - 1, Land.cellIndex(point.x + radius))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }
        let zoned = !zones.isEmpty && zones.hasZone(rows: firstRow...lastRow, columns: firstColumn...lastColumn)
        var best: (squared: Int64, row: Int, column: Int)?
        var candidates: [(squared: Int64, position: CellPosition, use: LandUse, zone: Zone)] = []
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let dx = Int64(column) * length + length / 2 - point.x
                let dy = Int64(row) * length + length / 2 - point.y
                let squared = dx * dx + dy * dy
                guard squared < radius * radius, land.cell(row: row, column: column) == nil,
                      !isClaimedByPlacedBuilding(row: row, column: column)
                else { continue }
                if zoned, let zone = zones.zone(row: row, column: column) {
                    if let use = zone.use {
                        candidates.append((squared, CellPosition(row: row, column: column), use, zone))
                    }
                    continue
                }
                guard candidates.isEmpty else { continue }
                if let best, (best.squared, best.row, best.column) <= (squared, row, column) { continue }
                let beside = [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
                // A park beside it has no people (decision 91).
                guard beside.contains(where: { land.cell(row: $0.0, column: $0.1).map { $0.residents + $0.jobs > 0 } ?? false }) else { continue }
                best = (squared, row, column)
            }
        }
        if !candidates.isEmpty {
            // By row and then column, so a tie keeps the first.
            let values = landValues(at: candidates.map(\.position)).map(\.value)
            var chosen = 0
            for index in candidates.indices.dropFirst()
            where (values[index], -candidates[index].squared) > (values[chosen], -candidates[chosen].squared) {
                chosen = index
            }
            let cell = candidates[chosen], counts = cell.zone.newCell
            addLand(LandCell(row: cell.position.row, column: cell.position.column, use: cell.use, residents: counts.residents, jobs: counts.jobs))
            return
        }
        guard let best else { return }
        addLand(LandCell(row: best.row, column: best.column, use: .residential, residents: LandDemand.newCellResidents, jobs: 0))
    }
}
