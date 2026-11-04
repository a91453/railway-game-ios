// Decision 574: the company's cableways (gondola lifts).
//
// A cableway is drawn as a line is, but simpler: its stops in order, each
// on a 64 m land cell, joined by straight spans that cross hills, rivers
// and roads alike. Its cabins come with it: they run all day, one every
// ``Cableway/cabinIntervalSeconds``, so there is nothing to buy or
// timetable. A stop that boards no one is an angle station, where the rope
// turns (the Maokong Gondola has two).
//
// Its riders are the city bus's (decision 438) on a rope: the land within
// ``BusRoute/stopReach`` of a boarding stop that no station reaches on foot
// rides it, to the station it meets (``Cableway/transfer``, the nearest
// within reach of a boarding stop) and between its own stops. Each rider
// pays one ``Cableway/fare``, the Maokong Gondola's single-trip fare,
// whatever the stops: the real fare is not by distance. It runs
// ``Cableway/operatingHours(onDay:)``, so a day carries at most
// ``Cableway/dailyCapacity(onDay:)``; and it stands still on Monday for
// maintenance (a holiday Monday runs), in a thunderstorm, and while a
// typhoon covers its first stop (``GameWorld/cablewayIsOpen(_:onDay:)``):
// the riders that day stay off, and its running is paid all the same.
//
// The references: the owner's transit map site gives a gondola 20 km/h and
// no stop time (`_app`'s `H` table, `GONDOLA`), and OpenWorld's Sun Moon
// Lake ropeway runs six cabins on a fixed cycle along a polyline
// (`sunmoon-ropeway.js`). Neither carries riders or money (gap). The
// Maokong Gondola's figures come from its operator's pages (gondola.taipei)
// and, where those are silent, Wikipedia: decision 574 lists each one.

/// Decision 586: how tourists reach a sight no station serves on foot:
/// by train to ``station``, then on by ``feeder``
/// (``GameWorld/feederAccess(to:onDay:)``).
struct FeederAccess: Hashable, Sendable {
    /// What takes them on from the station: a cableway, or since
    /// decision 587 a bus route.
    enum Feeder: Hashable, Sendable {
        case cableway(CablewayID)
        case bus(BusRouteID)
    }

    let station: StationID
    let feeder: Feeder
}

/// A cableway's number, handed out in order and never used again.
public struct CablewayID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: CablewayID, rhs: CablewayID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A cableway's stop: a station, or an angle station where the rope turns
/// and no one boards.
public struct CablewayStop: Hashable, Sendable {
    public let cell: CellPosition
    public let boards: Bool

    public init(cell: CellPosition, boards: Bool = true) {
        self.cell = cell
        self.boards = boards
    }
}

/// One day of a cableway's takings.
public struct CablewayDay: Hashable, Codable, Sendable {
    public let day: Int64
    public let riders: Int64
    public let fares: Money
    public let cost: Money
    /// Whether it stood still that day (Monday, a thunderstorm, a typhoon).
    public let closed: Bool

    public init(day: Int64, riders: Int64, fares: Money, cost: Money, closed: Bool) {
        self.day = day
        self.riders = riders
        self.fares = fares
        self.cost = cost
        self.closed = closed
    }
}

/// A cableway (decision 574).
public struct Cableway: Hashable, Sendable {
    public let id: CablewayID
    /// Its stops, in order: the first and last board, two boarding at
    /// least, no two in a row on one cell.
    public internal(set) var stops: [CablewayStop]
    /// The rope's metres from each stop to the next: one fewer than its
    /// stops.
    public internal(set) var legMetres: [Int64]
    /// The trips a day its land makes to the station it meets, and their
    /// door-to-door minutes to it, the people's average: worked out with
    /// the land's demand, 0 when it meets none.
    public internal(set) var feederTrips: Int64 = 0
    public internal(set) var feederMinutes: Int64 = 0
    /// The trips a day between its own stops, and their door-to-door
    /// minutes, the trips' average.
    public internal(set) var localTrips: Int64 = 0
    public internal(set) var localMinutes: Int64 = 0
    /// The station it meets: the nearest within ``BusRoute/stopReach`` of
    /// a boarding stop, and that stop; `nil` when none is. With
    /// ``meetsNear`` (decision 586), the station nearest that point within
    /// ``namedTransferReach`` of a boarding stop instead.
    public internal(set) var transfer: BusTransfer?
    /// Decision 586: where the station a real cableway meets stands (the
    /// Maokong Gondola's, MRT Taipei Zoo), given when it is built, so it
    /// meets that station once one stands there, whenever it is built;
    /// `nil` for one that meets the nearest.
    public internal(set) var meetsNear: PlanPoint?
    /// Riders today brought to or from the trains, and the thousandths of
    /// one carried over.
    public internal(set) var ridersToday: Int64 = 0
    var riderThousandths: Int64 = 0
    /// The last ``keptDays`` days, oldest first.
    public internal(set) var days: [CablewayDay] = []

    /// The most stops a cableway has.
    public static let maximumStops = 8
    /// Decision 586: how far a boarding stop may be from the station a
    /// cableway is given to meet (``meetsNear``): 500 m, so the Maokong
    /// Gondola's Taipei Zoo stop, 413 m from MRT Taipei Zoo (447 m once on
    /// the map's cells), meets it.
    public static let namedTransferReach: Int64 = 500 * WorldCoordinate.unitsPerMetre
    /// The longest span between two stops: 5 km. The Maokong Gondola's
    /// longest is under 2 km; its towers stand between, and the rope does
    /// not care what lies below.
    public static let maximumLegMetres: Int64 = 5_000
    /// The rope's speed: 5 m/s, the Maokong Gondola's (Wikipedia, zh; its
    /// design speed is 6).
    public static let metresPerSecond: Int64 = 5
    /// The seconds a cabin takes through each stop between the ends,
    /// angle stations too: 60, so Maokong's 4,033 m take about 17 minutes
    /// (Wikipedia, zh).
    public static let stopPassSeconds: Int64 = 60
    /// The seconds between cabins: 12, so its 8 seats carry 2,400 people
    /// an hour each way (Wikipedia, zh).
    public static let cabinIntervalSeconds: Int64 = 12
    /// The seats in a cabin: 8 (gondola.taipei).
    public static let cabinSeats: Int64 = 8
    /// The minutes waiting for a cabin and stepping in: 1.
    public static let waitMinutes: Int64 = 1
    /// A rider's fare: NT$180, Maokong's single trip (gondola.taipei).
    public static let fare = Money(18_000)
    /// What a boarding stop, an angle station and each metre of rope cost
    /// to build: NT$600,000 (a station's), NT$200,000 and NT$1,500 (five
    /// times a track's). The project's own: the game's prices are not
    /// real ones.
    public static let stationPrice = Money(60_000_000)
    public static let angleStationPrice = Money(20_000_000)
    public static let pricePerMetre = Money(150_000)
    /// What each metre of rope costs to run a day, staff, power and upkeep:
    /// NT$5. The project's own.
    public static let dailyCostPerMetre = Money(500)
    /// The part of the land a boarding stop reaches that rides to its
    /// other stops: a quarter, as a city bus route's (decision 438).
    public static let localShare: (numerator: Int64, denominator: Int64) = (1, 4)
    /// The part that rides to the trains: a half, as a bus feeder's.
    public static let riderShare: (numerator: Int64, denominator: Int64) = (1, 2)
    /// The days of takings kept.
    public static let keptDays = 30

    /// The rope's metres from end to end.
    public var metres: Int64 {
        legMetres.reduce(0, +)
    }

    /// The hours it runs on game day `day`: 9:00 to 21:00, and to 22:00 on
    /// a weekend (gondola.taipei).
    public static func operatingHours(onDay day: Int64) -> Int64 {
        StationDemand.isWeekend(day: day) ? 13 : 12
    }

    /// The people an hour it carries each way.
    public static var hourlyCapacity: Int64 {
        3_600 / cabinIntervalSeconds * cabinSeats
    }

    /// The most riders it carries on game day `day`, both ways.
    public static func dailyCapacity(onDay day: Int64) -> Int64 {
        hourlyCapacity * operatingHours(onDay: day) * 2
    }

    /// What it costs a day: ``dailyCostPerMetre`` for each metre of rope.
    public var dailyCost: Money {
        Money(metres * Self.dailyCostPerMetre.amount)
    }

    /// What building `stops` with `metres` of rope costs.
    public static func price(of stops: [CablewayStop], metres: Int64) -> Money {
        let stations = stops.reduce(Int64(0)) { $0 + ($1.boards ? stationPrice.amount : angleStationPrice.amount) }
        return Money(stations + metres * pricePerMetre.amount)
    }

    /// Seconds on board from stop `a` to stop `b`: the rope's metres at
    /// ``metresPerSecond``, rounded up, and ``stopPassSeconds`` for each
    /// stop passed between.
    public func rideSeconds(from a: Int, to b: Int) -> Int64 {
        let low = min(a, b), high = max(a, b)
        let metres = legMetres[low..<high].reduce(0, +)
        return (metres + Self.metresPerSecond - 1) / Self.metresPerSecond + Int64(max(0, high - low - 1)) * Self.stopPassSeconds
    }

    /// Minutes on board from stop `a` to stop `b`, rounded half up.
    func rideMinutes(from a: Int, to b: Int) -> Int64 {
        (rideSeconds(from: a, to: b) + 30) / 60
    }

    var isValid: Bool {
        (2...Self.maximumStops).contains(stops.count) && legMetres.count == stops.count - 1
            && stops.first!.boards && stops.last!.boards
            && zip(stops, stops.dropFirst()).allSatisfy { $0.cell != $1.cell }
            && legMetres.allSatisfy { (1...Self.maximumLegMetres).contains($0) }
            && transfer.map({ stops.indices.contains($0.stop) && stops[$0.stop].boards }) ?? true
            && (0...StationDemand.maximumDailyTrips).contains(feederTrips) && (0...GameTime.minutesPerDay).contains(feederMinutes)
            && (0...StationDemand.maximumDailyTrips).contains(localTrips) && (0...GameTime.minutesPerDay).contains(localMinutes)
            && ridersToday >= 0 && (0..<1_000).contains(riderThousandths)
            && days.count <= Self.keptDays && days.allSatisfy { $0.riders >= 0 && $0.fares >= .zero && $0.cost >= .zero }
            && zip(days, days.dropFirst()).allSatisfy { $0.day < $1.day }
    }
}

// MARK: - Codable

extension CablewayStop: Codable {
    private enum CodingKeys: String, CodingKey {
        case row, column, angle
    }

    /// `{"row": r, "column": c}`, with `"angle": true` for an angle station.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cell = CellPosition(row: try container.decode(Int.self, forKey: .row), column: try container.decode(Int.self, forKey: .column))
        boards = !(try container.decodeIfPresent(Bool.self, forKey: .angle) ?? false)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cell.row, forKey: .row)
        try container.encode(cell.column, forKey: .column)
        if !boards { try container.encode(true, forKey: .angle) }
    }
}

extension Cableway: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, stops, legMetres, feederTrips, feederMinutes, localTrips, localMinutes, transfer, meetsNear, ridersToday, riderThousandths, days
    }

    /// The cableway, with its derived figures and takings; refused when
    /// malformed. The world checks its stops and transfer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CablewayID.self, forKey: .id)
        let stops = try container.decode([CablewayStop].self, forKey: .stops)
        guard stops.count <= Self.maximumStops else {
            throw DecodingError.dataCorruptedError(forKey: .stops, in: container, debugDescription: "A cableway has at most \(Self.maximumStops) stops.")
        }
        self.stops = stops
        legMetres = try container.decode([Int64].self, forKey: .legMetres)
        feederTrips = try container.decodeIfPresent(Int64.self, forKey: .feederTrips) ?? 0
        feederMinutes = try container.decodeIfPresent(Int64.self, forKey: .feederMinutes) ?? 0
        localTrips = try container.decodeIfPresent(Int64.self, forKey: .localTrips) ?? 0
        localMinutes = try container.decodeIfPresent(Int64.self, forKey: .localMinutes) ?? 0
        transfer = try container.decodeIfPresent(BusTransfer.self, forKey: .transfer)
        meetsNear = try container.decodeIfPresent(PlanPoint.self, forKey: .meetsNear)
        ridersToday = try container.decodeIfPresent(Int64.self, forKey: .ridersToday) ?? 0
        riderThousandths = try container.decodeIfPresent(Int64.self, forKey: .riderThousandths) ?? 0
        days = try container.decodeIfPresent([CablewayDay].self, forKey: .days) ?? []
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .stops, in: container,
                debugDescription: "A cableway has 2 to \(Self.maximumStops) stops, boarding at both ends, a span of 1 to \(Self.maximumLegMetres) m between each two."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(stops, forKey: .stops)
        try container.encode(legMetres, forKey: .legMetres)
        if feederTrips != 0 { try container.encode(feederTrips, forKey: .feederTrips) }
        if feederMinutes != 0 { try container.encode(feederMinutes, forKey: .feederMinutes) }
        if localTrips != 0 { try container.encode(localTrips, forKey: .localTrips) }
        if localMinutes != 0 { try container.encode(localMinutes, forKey: .localMinutes) }
        try container.encodeIfPresent(transfer, forKey: .transfer)
        try container.encodeIfPresent(meetsNear, forKey: .meetsNear)
        if ridersToday != 0 { try container.encode(ridersToday, forKey: .ridersToday) }
        if riderThousandths != 0 { try container.encode(riderThousandths, forKey: .riderThousandths) }
        if !days.isEmpty { try container.encode(days, forKey: .days) }
    }
}

// MARK: - Commands

extension GameWorld {
    /// Builds a cableway through `stops` (decision 574), paying
    /// ``Cableway/price(of:metres:)``. With `legMetres` (a real one's, one
    /// fewer than the stops) its spans are those lengths; without, the
    /// straight line between the cells' middles, a metre at least. With
    /// `meetsNear` (decision 586, a real one's station) it meets the
    /// station nearest that point (``Cableway/meetsNear``).
    ///
    /// - Throws, checked in this order: ``GameError/idsExhausted`` once the
    ///   numbers run out; ``GameError/invalidCableway`` for fewer than 2
    ///   stops or more than ``Cableway/maximumStops``, an end that boards
    ///   no one, two stops in a row on one cell, a stop off the world, a
    ///   span not 1 to ``Cableway/maximumLegMetres`` m, or a `meetsNear`
    ///   farther than ``Cableway/namedTransferReach`` from every boarding
    ///   stop;
    ///   ``GameError/insufficientFunds(required:available:)``. The world is
    ///   then unchanged.
    @discardableResult
    public mutating func createCableway(stops: [CablewayStop], legMetres: [Int64]? = nil, meetsNear: PlanPoint? = nil) throws(GameError) -> Cableway {
        let (id, next) = try Self.allocateID(from: nextCablewayID)
        let legs = try cablewayLegs(stops: stops, given: legMetres)
        var cableway = Cableway(id: CablewayID(rawValue: id), stops: stops, legMetres: legs)
        guard cableway.isValid else { throw .invalidCableway }
        if let meetsNear {
            let reach = Cableway.namedTransferReach * Cableway.namedTransferReach
            guard stops.contains(where: { $0.boards && Self.squaredDistance(Self.middle(of: $0.cell), meetsNear) <= reach }) else {
                throw .invalidCableway
            }
            cableway.meetsNear = meetsNear
        }
        try spendOnCableways(Cableway.price(of: stops, metres: cableway.metres))
        cableways.append(cableway)
        nextCablewayID = next
        cablewaysChanged()
        return cableways[cableways.count - 1]
    }

    /// Takes cableway `id` down; nothing is sold back.
    ///
    /// - Throws: ``GameError/unknownCableway(_:)``.
    public mutating func removeCableway(_ id: CablewayID) throws(GameError) {
        let index = try cablewayIndex(of: id)
        cableways.remove(at: index)
        cablewaysChanged()
    }

    // MARK: - Queries

    /// Cableway `id`, or `nil`.
    public func cableway(id: CablewayID) -> Cableway? {
        cableways.first { $0.id == id }
    }

    /// Whether cableway `id` runs on game day `day`: not on a Monday that
    /// is no holiday (its maintenance day), not in a thunderstorm (the
    /// operator stops for lightning), and not while a typhoon covers its
    /// first stop. `false` for no such cableway.
    public func cablewayIsOpen(_ id: CablewayID, onDay day: Int64) -> Bool {
        guard let cableway = cableway(id: id) else { return false }
        if StationDemand.weekday(ofDay: day) == 1, holiday(onDay: day) == nil { return false }
        if weather(onDay: day) == .thunderstorm { return false }
        let first = Self.middle(of: cableway.stops[0].cell)
        return !typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(first) }
    }

    // MARK: - Internals

    func cablewayIndex(of id: CablewayID) throws(GameError) -> Int {
        guard let index = cableways.firstIndex(where: { $0.id == id }) else { throw .unknownCableway(id) }
        return index
    }

    /// The spans of a cableway through `stops`: `given`, or the straight
    /// lines between the cells' middles, rounded half up to the metre.
    private func cablewayLegs(stops: [CablewayStop], given: [Int64]?) throws(GameError) -> [Int64] {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard (2...Cableway.maximumStops).contains(stops.count),
              stops.allSatisfy({ (0..<rows).contains($0.cell.row) && (0..<columns).contains($0.cell.column) })
        else { throw .invalidCableway }
        if let given {
            guard given.count == stops.count - 1 else { throw .invalidCableway }
            return given
        }
        return zip(stops, stops.dropFirst()).map { a, b in
            let units = FixedPoint.roundedSquareRoot(Self.squaredDistance(Self.middle(of: a.cell), Self.middle(of: b.cell)))
            return max(1, (units + WorldCoordinate.unitsPerMetre / 2) / WorldCoordinate.unitsPerMetre)
        }
    }

    private mutating func spendOnCableways(_ price: Money) throws(GameError) {
        guard price > .zero else { return }
        try economy.spend(price)
        if accounts.mode == .management {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + price }
        }
    }

    /// After a cableway is built or taken down: the land's shares and the
    /// plan follow.
    private mutating func cablewaysChanged() {
        refreshLandDemand()
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - The land it draws

    /// Each cableway's share of the land, worked out afresh: every cell
    /// whose middle lies within ``BusRoute/stopReach`` of a boarding stop
    /// and outside every station's ``Land/catchmentRadius`` goes whole to
    /// its nearest boarding stop (then the lower cableway, then the earlier
    /// stop). A cableway that meets a station (``Cableway/transfer``,
    /// worked out here first) brings ``Cableway/riderShare`` of its land to
    /// it, their minutes the walk, ``Cableway/waitMinutes``, the ride to
    /// the stop nearest the station and the walk on, a day at most, the
    /// people's average rounded half up; and every cableway carries the
    /// trips between its stops (``refreshCablewayTrips(_:)``).
    ///
    /// Returns each station's added share and the cells it took, which no
    /// bus stop then draws. Without land demand every figure is 0. Called
    /// by ``refreshLandDemand()``, before the buses.
    mutating func refreshCablewayFeeders() -> (shares: [StationID: LandDemand.Share], cells: Set<Int>) {
        guard !cableways.isEmpty else { return ([:], []) }
        let fed = landStations
        refreshCablewayTransfers(among: fed)
        var added: [StationID: LandDemand.Share] = [:]
        var taken = Set<Int>()
        var figures = [(trips: Int64, minutes: Int64)](repeating: (0, 0), count: cableways.count)
        var stopLand = [[CityBusStopLand]](repeating: [], count: cableways.count)
        if drawsDemandFromLand {
            var walkable = Set<Int>()
            for station in fed {
                land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in walkable.insert(index) }
            }
            var nearest: [Int: (squared: Int64, cableway: Int, stop: Int)] = [:]
            for (position, cableway) in cableways.enumerated() {
                for (stop, point) in cableway.stops.enumerated() where point.boards {
                    land.forEachCell(within: BusRoute.stopReach, of: Self.middle(of: point.cell)) { index, squared in
                        guard !walkable.contains(index) else { return }
                        let candidate = (squared, position, stop)
                        if nearest[index].map({ candidate < $0 }) ?? true { nearest[index] = candidate }
                    }
                }
            }
            var shares = [LandDemand.Share](repeating: LandDemand.Share(), count: cableways.count)
            var weighted = [Int64](repeating: 0, count: cableways.count)
            for position in cableways.indices {
                stopLand[position] = Array(repeating: CityBusStopLand(), count: cableways[position].stops.count)
            }
            for index in nearest.keys.sorted() {
                let (squared, position, stop) = nearest[index]!
                let cell = land.cells[index]
                let people = cell.residents + cell.jobs
                guard people > 0 else { continue }
                taken.insert(index)
                let cableway = cableways[position]
                let walk = BusRoute.walkMinutes(units: FixedPoint.roundedSquareRoot(squared))
                stopLand[position][stop].share.add(cell.residents, cell.jobs, of: cell.use)
                stopLand[position][stop].walked += people * walk
                guard let transfer = cableway.transfer, let met = station(id: transfer.station) else { continue }
                let at = cableway.stops[transfer.stop].cell
                let ride = cableway.rideMinutes(from: stop, to: transfer.stop)
                    + BusRoute.walkMinutes(units: FixedPoint.roundedSquareRoot(Self.squaredDistance(Self.middle(of: at), met.location)))
                let minutes = min(GameTime.minutesPerDay, walk + Cableway.waitMinutes + ride)
                shares[position].add(cell.residents, cell.jobs, of: cell.use)
                weighted[position] += people * minutes
            }
            for position in cableways.indices {
                let people = shares[position].people
                shares[position].scale(Cableway.riderShare)
                guard people > 0, let trips = shares[position].demand?.dailyTrips, let feeds = cableways[position].transfer?.station else { continue }
                figures[position] = (trips, (weighted[position] * 2 + people) / (2 * people))
                var share = added[feeds] ?? LandDemand.Share()
                share.add(shares[position])
                added[feeds] = share
            }
        }
        for position in cableways.indices {
            cableways[position].feederTrips = figures[position].trips
            cableways[position].feederMinutes = figures[position].minutes
        }
        refreshCablewayTrips(stopLand)
        return (added, taken)
    }

    /// Each cableway's station: of `stations`, the nearest a boarding
    /// stop's middle within ``BusRoute/stopReach``, then the lower station
    /// ID, then the earlier stop; `nil` when none is.
    mutating func refreshCablewayTransfers(among stations: [Station]) {
        let reach = BusRoute.stopReach * BusRoute.stopReach
        for position in cableways.indices {
            if let near = cableways[position].meetsNear {
                cableways[position].transfer = Self.namedTransfer(of: cableways[position], near: near, among: stations)
                continue
            }
            var best: (squared: Int64, station: Int, stop: Int)?
            for (stop, point) in cableways[position].stops.enumerated() where point.boards {
                let middle = Self.middle(of: point.cell)
                for station in stations {
                    let squared = Self.squaredDistance(middle, station.location)
                    guard squared <= reach else { continue }
                    let candidate = (squared, station.id.rawValue, stop)
                    if best.map({ candidate < $0 }) ?? true { best = candidate }
                }
            }
            cableways[position].transfer = best.map { BusTransfer(station: StationID(rawValue: $0.station), stop: $0.stop) }
        }
    }

    /// Decision 586: the station `cableway` meets when it is given one
    /// near `near`: of `stations` within ``Cableway/namedTransferReach`` of
    /// a boarding stop, the nearest `near` (then the lower station ID),
    /// with its nearest boarding stop (then the earlier); `nil` when none is.
    static func namedTransfer(of cableway: Cableway, near: PlanPoint, among stations: [Station]) -> BusTransfer? {
        let reach = Cableway.namedTransferReach * Cableway.namedTransferReach
        let boarding = cableway.stops.indices.filter { cableway.stops[$0].boards }
        var best: (squared: Int64, station: Int, stop: Int)?
        for station in stations {
            let stops = boarding.map { (squaredDistance(middle(of: cableway.stops[$0].cell), station.location), $0) }.filter { $0.0 <= reach }
            guard let stop = stops.min(by: { $0 < $1 }) else { continue }
            let candidate = (squaredDistance(near, station.location), station.id.rawValue, stop.1)
            if best.map({ (candidate.0, candidate.1) < ($0.squared, $0.station) }) ?? true { best = candidate }
        }
        return best.map { BusTransfer(station: StationID(rawValue: $0.station), stop: $0.stop) }
    }

    /// The trips between each cableway's stops, worked out afresh into its
    /// ``Cableway/localTrips`` and ``Cableway/localMinutes`` from
    /// `stopLand`, as a city bus route's (``refreshCityBusTrips(_:)``):
    /// a boarding stop's land times ``Cableway/localShare`` goes to the
    /// other boarding stops by their people (whole parts, the rest to the
    /// largest remainders, then the earlier stop), each part keeping
    /// ``DistanceDemand/share(squaredDistance:)`` of itself for the
    /// straight line, and with a mode shift a part 2 km and more long
    /// losing those that go by road. The minutes are both walks,
    /// ``Cableway/waitMinutes`` and the ride; a cableway's, its trips'
    /// average, rounded half up.
    mutating func refreshCablewayTrips(_ stopLand: [[CityBusStopLand]]) {
        for position in cableways.indices {
            cableways[position].localTrips = 0
            cableways[position].localMinutes = 0
            let reached = stopLand[position]
            guard !reached.isEmpty else { continue }
            let cableway = cableways[position]
            let people = reached.map(\.share.people)
            let walks = reached.map { $0.share.people > 0 ? ($0.walked * 2 + $0.share.people) / (2 * $0.share.people) : 0 }
            var total: Int64 = 0, weighted: Int64 = 0
            for from in reached.indices {
                var share = reached[from].share
                share.scale(Cableway.localShare)
                guard let trips = share.demand?.dailyTrips else { continue }
                let others = people.indices.filter { $0 != from && people[$0] > 0 }
                let sum = others.reduce(0) { $0 + people[$1] }
                guard sum > 0 else { continue }
                var parts = others.map { (stop: $0, whole: trips * people[$0] / sum, rest: trips * people[$0] % sum) }
                var left = trips - parts.reduce(0) { $0 + $1.whole }
                for index in parts.indices.sorted(by: { (parts[$0].rest, parts[$1].stop) > (parts[$1].rest, parts[$0].stop) }) where left > 0 {
                    parts[index].whole += 1
                    left -= 1
                }
                for part in parts where part.whole > 0 {
                    let squared = Self.squaredDistance(Self.middle(of: cableway.stops[from].cell), Self.middle(of: cableway.stops[part.stop].cell))
                    var kept = part.whole * DistanceDemand.share(squaredDistance: squared) / 1_000
                    let minutes = min(GameTime.minutesPerDay, walks[from] + walks[part.stop] + Cableway.waitMinutes
                        + cableway.rideMinutes(from: from, to: part.stop))
                    if let modeShift, squared >= DistanceDemand.fullDistance * DistanceDemand.fullDistance {
                        let units = FixedPoint.roundedSquareRoot(squared)
                        let metres = (units + WorldCoordinate.unitsPerMetre / 2) / WorldCoordinate.unitsPerMetre
                        kept -= ModeShift.lost(kept, share: modeShift.share(railMinutes: minutes, roadMinutes: ModeShift.roadMinutes(metres: metres)))
                    }
                    total += kept
                    weighted += kept * minutes
                }
            }
            guard total > 0 else { continue }
            cableways[position].localTrips = min(StationDemand.maximumDailyTrips, total)
            cableways[position].localMinutes = (weighted * 2 + total) / (2 * total)
        }
    }

    /// The cableways bringing `origin`'s trips: each one's trips and
    /// door-to-door minutes.
    func cablewayFeeders(of origin: StationID) -> [(trips: Int64, minutes: Int64)] {
        cableways.compactMap { $0.transfer?.station == origin && $0.feederTrips > 0 ? ($0.feederTrips, $0.feederMinutes) : nil }
    }

    /// `boarded` riders set out from `station` by train, or arrived there
    /// at the end of their journey: the share of them each cableway meeting
    /// it brought (or takes home) rides the cabins, counted in thousandths.
    mutating func countCablewayRiders(_ boarded: Int64, at station: StationID) {
        guard boarded > 0, accounts.mode == .management, !cableways.isEmpty,
              let trips = passengers.first(where: { $0.station == station })?.demand?.dailyTrips, trips > 0 else { return }
        for index in cableways.indices where cableways[index].transfer?.station == station && cableways[index].feederTrips > 0 {
            let thousandths = cableways[index].riderThousandths + boarded * min(trips, cableways[index].feederTrips) * 1_000 / trips
            cableways[index].ridersToday = min(Self.maximumHourly, cableways[index].ridersToday + thousandths / 1_000)
            cableways[index].riderThousandths = thousandths % 1_000
        }
    }

    /// Decision 586: adds `rides`, the tourists' rides on of the day that
    /// ended (``TouristFlows/feederRides``), to each cableway's riders of
    /// that day, before it is settled; since decision 587 to each bus
    /// route's too, whose riders stay at most what its buses hold
    /// (``BusRoute/dailyCapacity``) when it is settled. In management mode
    /// only, as the riders from the trains.
    mutating func countFeederRides(_ rides: [FeederAccess.Feeder: Int64]) {
        guard accounts.mode == .management, !rides.isEmpty else { return }
        for index in cableways.indices {
            guard let count = rides[.cableway(cableways[index].id)], count > 0 else { continue }
            cableways[index].ridersToday = min(Self.maximumHourly, cableways[index].ridersToday + count)
        }
        for index in busRoutes.indices {
            guard let count = rides[.bus(busRoutes[index].id)], count > 0 else { continue }
            busRoutes[index].ridersToday = min(Self.maximumHourly, busRoutes[index].ridersToday + count)
        }
    }

    /// The day's cableways, a row for them all: each one's riders (those
    /// from the trains and its ``Cableway/localTrips``, at most
    /// ``Cableway/dailyCapacity(onDay:)``, none on a day it stands still)
    /// pay ``Cableway/fare`` in, and its ``Cableway/dailyCost`` goes out
    /// every day; kept on the cableway for ``Cableway/keptDays`` days.
    mutating func settleCableways(day: Int64, time: GameTime) {
        guard accounts.mode == .management, !cableways.isEmpty else { return }
        var fares = Money.zero, cost = Money.zero
        for index in cableways.indices {
            let cableway = cableways[index]
            let open = cablewayIsOpen(cableway.id, onDay: day)
            let riders = open ? min(Cableway.dailyCapacity(onDay: day), cableway.ridersToday + cableway.localTrips) : 0
            let dayFares = Money(riders * Cableway.fare.amount)
            let dayCost = cableway.dailyCost
            fares = fares + dayFares
            cost = cost + dayCost
            cableways[index].days.append(CablewayDay(day: day, riders: riders, fares: dayFares, cost: dayCost, closed: !open))
            if cableways[index].days.count > Cableway.keptDays { cableways[index].days.removeFirst() }
            cableways[index].ridersToday = 0
        }
        guard fares > .zero || cost > .zero else { return }
        write(LedgerEntry(
            kind: .dailyCableways, time: time, amount: fares - cost,
            breakdown: [LedgerLine(item: .cablewayFares, amount: fares), LedgerLine(item: .cablewayRunning, amount: .zero - cost)]
        ), day: day)
    }

    // MARK: - Validation

    func cablewaysProblem() -> String? {
        guard nextCablewayID >= 1 else { return "The next cableway's number is 1 or more." }
        guard !cableways.isEmpty else { return nil }
        let ids = Set(stations.map(\.id))
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard cableways.allSatisfy({ $0.isValid && (1..<nextCablewayID).contains($0.id.rawValue) && ($0.transfer.map { ids.contains($0.station) } ?? true)
                  && $0.stops.allSatisfy { (0..<rows).contains($0.cell.row) && (0..<columns).contains($0.cell.column) } }),
              zip(cableways, cableways.dropFirst()).allSatisfy({ $0.id < $1.id })
        else {
            return "Each cableway is well formed, a number handed out, in order, its stops in the world and its transfer a station the world has."
        }
        return nil
    }
}
