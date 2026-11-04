// Decision 585: the company's ferries.
//
// A ferry route is a bus route on the water: its piers in order, each on a
// land cell with water beside it, joined by straight crossings, and its
// boats, bought as buses are, leaving the first pier on a headway or a
// day's runs (``BusService``). A headway runs through the day's
// ``FerryRoute/operatingMinutes(onDay:)``, the Tamsui–Bali ferry's hours.
// GameCore does not look for a way through the water: as a cableway's rope,
// a crossing is the straight line between two piers, or a real route's
// given length.
//
// Its riders are the cableway's (decision 574): the land within
// ``BusRoute/stopReach`` of a pier that no station reaches on foot, and no
// cableway takes, rides it, to the station it meets
// (``FerryRoute/transfer``, the nearest within reach of a pier) and
// between its own piers, waiting half the headway as a bus's riders do.
// Each pays one ``FerryRoute/fare``, the Tamsui–Bali ferry's full fare; a
// day carries at most ``FerryRoute/dailyCapacity(onDay:)``; and no boat
// sails while a typhoon covers one of its piers
// (``GameWorld/ferryRouteIsOpen(_:onDay:)``): the riders that day stay off,
// and the boats' running is paid all the same.
//
// The references: the owner's transit map site gives a ferry 0.7 km a
// minute and a 1,500 ms stop (`_app`'s `H` table, `FERRY`), and the Hong
// Kong commuter game sails the Star Ferry in 26 seconds of boarding,
// sailing and docking (`ferryConfig.js`). Neither carries riders or money
// (gap). The Tamsui–Bali and Gushan–Cijin ferries' figures come from New
// Taipei's transport department and the Kaohsiung ferry's published fares:
// decision 585 lists each one.

/// A ferry route's number, handed out in order and never used again.
public struct FerryRouteID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: FerryRouteID, rhs: FerryRouteID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One day of a ferry route's takings.
public struct FerryDay: Hashable, Codable, Sendable {
    public let day: Int64
    public let riders: Int64
    public let fares: Money
    public let cost: Money
    /// Whether no boat sailed that day (a typhoon).
    public let closed: Bool

    public init(day: Int64, riders: Int64, fares: Money, cost: Money, closed: Bool) {
        self.day = day
        self.riders = riders
        self.fares = fares
        self.cost = cost
        self.closed = closed
    }
}

/// A ferry route (decision 585).
public struct FerryRoute: Hashable, Sendable {
    public let id: FerryRouteID
    /// Its piers, in order, each on a land cell beside the water: two at
    /// least, no two in a row on one cell.
    public internal(set) var piers: [CellPosition]
    /// The crossing's metres from each pier to the next: one fewer than
    /// its piers.
    public internal(set) var legMetres: [Int64]
    public internal(set) var service: BusService
    public internal(set) var boats: Int
    /// The trips a day its land makes to the station it meets, and their
    /// door-to-door minutes to it, the people's average: worked out with
    /// the land's demand, 0 while no boat sails or it meets none.
    public internal(set) var feederTrips: Int64 = 0
    public internal(set) var feederMinutes: Int64 = 0
    /// The trips a day between its own piers, and their door-to-door
    /// minutes, the trips' average.
    public internal(set) var localTrips: Int64 = 0
    public internal(set) var localMinutes: Int64 = 0
    /// The station it meets: the nearest within ``BusRoute/stopReach`` of
    /// a pier, and that pier; `nil` when none is.
    public internal(set) var transfer: BusTransfer?
    /// Riders today brought to or from the trains, and the thousandths of
    /// one carried over.
    public internal(set) var ridersToday: Int64 = 0
    var riderThousandths: Int64 = 0
    /// The last ``keptDays`` days, oldest first.
    public internal(set) var days: [FerryDay] = []

    /// The most piers and boats a route has.
    public static let maximumPiers = 8
    public static let maximumBoats = 20
    /// The longest crossing between two piers: 30 km, as far as the
    /// Taiwan Strait's short island runs; Tamsui–Bali is about 1.4 km.
    public static let maximumLegMetres: Int64 = 30_000
    /// A boat's speed under way: 12 km/h, so Tamsui–Bali's 1.4 km take
    /// about 7 minutes and Gushan–Cijin's 700 m about 4 (both piers'
    /// published crossings: 10 and 5 minutes with the docking).
    public static let metresPerHour: Int64 = 12_000
    /// The minutes a boat spends at each pier it calls at, its ends too:
    /// tying up, the riders off and on, casting off.
    public static let dockMinutes: Int64 = 2
    /// What a pier and a boat cost: NT$300,000 and NT$1,000,000. The
    /// project's own: the game's prices are not real ones (a bus is
    /// NT$150,000).
    public static let pierPrice = Money(30_000_000)
    public static let boatPrice = Money(100_000_000)
    /// A rider's fare: NT$40, the Tamsui–Bali ferry's full fare (New
    /// Taipei City, 2026-05-18; Gushan–Cijin's is NT$30).
    public static let fare = Money(4_000)
    /// What a boat costs for each kilometre it sails, crew, fuel and
    /// upkeep: NT$300, five buses'. The project's own.
    public static let costPerKilometre = Money(30_000)
    /// The riders a boat holds one way: 99, the Tamsui–Bali boat Shun
    /// Feng 166's (decision 579's source).
    public static let capacity: Int64 = 99
    /// The part of the land a pier reaches that rides to the trains: a
    /// half, as a bus feeder's.
    public static let riderShare: (numerator: Int64, denominator: Int64) = (1, 2)
    /// The part that rides to its other piers: a quarter, as a city bus
    /// route's (decision 438).
    public static let localShare: (numerator: Int64, denominator: Int64) = (1, 4)
    /// The minute of the day a headway's first boat leaves: 07:00.
    public static let firstDeparture: Int64 = 7 * 60
    /// The days of takings kept.
    public static let keptDays = 30

    public init(id: FerryRouteID, piers: [CellPosition], legMetres: [Int64], service: BusService, boats: Int) {
        self.id = id
        self.piers = piers
        self.legMetres = legMetres
        self.service = service
        self.boats = boats
    }

    /// The crossing's metres from end to end.
    public var metres: Int64 {
        legMetres.reduce(0, +)
    }

    /// The minutes a headway's boats sail on game day `day`: 07:00 to
    /// 19:00, and to 20:00 on a weekend (the Tamsui–Bali ferry's hours).
    public static func operatingMinutes(onDay day: Int64) -> Int64 {
        (StationDemand.isWeekend(day: day) ? 13 : 12) * 60
    }

    /// The minutes there and back: the crossings at ``metresPerHour``,
    /// rounded up, and ``dockMinutes`` at every pier called at, each end
    /// once.
    public var roundTripMinutes: Int64 {
        (2 * metres * 60 + Self.metresPerHour - 1) / Self.metresPerHour + 2 * Int64(piers.count - 1) * Self.dockMinutes
    }

    /// The minutes between boats: as set, but no closer than its boats can
    /// keep; `nil` with no boat.
    public var headway: Int64? {
        guard boats > 0 else { return nil }
        let fewest = (roundTripMinutes + Int64(boats) - 1) / Int64(boats)
        return max(service.minutesApart, fewest)
    }

    /// The boats that leave its first pier on game day `day`, and as many
    /// back: one each headway through ``operatingMinutes(onDay:)``, or its
    /// runs, as many as its boats keep; none without a boat.
    public func dailyDepartures(onDay day: Int64) -> Int64 {
        guard let headway else { return 0 }
        switch service {
        case .every: return Self.operatingMinutes(onDay: day) / headway
        case .runs(let minutes): return min(Int64(minutes.count), max(1, GameTime.minutesPerDay / headway))
        }
    }

    /// What its boats cost on game day `day`: ``costPerKilometre`` for each
    /// kilometre there and back of each departure, rounded half up to the
    /// cent.
    public func dailyCost(onDay day: Int64) -> Money {
        Money((dailyDepartures(onDay: day) * 2 * metres * Self.costPerKilometre.amount + 500) / 1_000)
    }

    /// The most riders its boats carry on game day `day`, there and back.
    public func dailyCapacity(onDay day: Int64) -> Int64 {
        dailyDepartures(onDay: day) * 2 * Self.capacity
    }

    /// What building `piers` piers with `boats` boats costs.
    public static func price(piers: Int, boats: Int) -> Money {
        Money(pierPrice.amount * Int64(piers) + boatPrice.amount * Int64(boats))
    }

    /// Minutes on board from pier `a` to pier `b`: the crossings at
    /// ``metresPerHour``, rounded half up, and ``dockMinutes`` at each pier
    /// called at between.
    public func rideMinutes(from a: Int, to b: Int) -> Int64 {
        let low = min(a, b), high = max(a, b)
        let metres = legMetres[low..<high].reduce(0, +)
        return (metres * 60 + Self.metresPerHour / 2) / Self.metresPerHour + Int64(max(0, high - low - 1)) * Self.dockMinutes
    }

    var isValid: Bool {
        (2...Self.maximumPiers).contains(piers.count) && legMetres.count == piers.count - 1
            && zip(piers, piers.dropFirst()).allSatisfy { $0 != $1 }
            && legMetres.allSatisfy { (1...Self.maximumLegMetres).contains($0) }
            && service.isValid && (0...Self.maximumBoats).contains(boats)
            && transfer.map({ piers.indices.contains($0.stop) }) ?? true
            && (0...StationDemand.maximumDailyTrips).contains(feederTrips) && (0...GameTime.minutesPerDay).contains(feederMinutes)
            && (0...StationDemand.maximumDailyTrips).contains(localTrips) && (0...GameTime.minutesPerDay).contains(localMinutes)
            && ridersToday >= 0 && (0..<1_000).contains(riderThousandths)
            && days.count <= Self.keptDays && days.allSatisfy { $0.riders >= 0 && $0.fares >= .zero && $0.cost >= .zero }
            && zip(days, days.dropFirst()).allSatisfy { $0.day < $1.day }
    }
}

// MARK: - Codable

extension FerryRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, piers, legMetres, service, boats, feederTrips, feederMinutes, localTrips, localMinutes, transfer, ridersToday, riderThousandths, days
    }

    private struct Pier: Codable {
        var row: Int
        var column: Int
    }

    /// The route, with its derived figures and takings; refused when
    /// malformed. The world checks its piers and transfer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(FerryRouteID.self, forKey: .id)
        let piers = try container.decode([Pier].self, forKey: .piers)
        guard piers.count <= Self.maximumPiers else {
            throw DecodingError.dataCorruptedError(forKey: .piers, in: container, debugDescription: "A ferry route has at most \(Self.maximumPiers) piers.")
        }
        self.piers = piers.map { CellPosition(row: $0.row, column: $0.column) }
        legMetres = try container.decode([Int64].self, forKey: .legMetres)
        service = try container.decode(BusService.self, forKey: .service)
        boats = try container.decode(Int.self, forKey: .boats)
        feederTrips = try container.decodeIfPresent(Int64.self, forKey: .feederTrips) ?? 0
        feederMinutes = try container.decodeIfPresent(Int64.self, forKey: .feederMinutes) ?? 0
        localTrips = try container.decodeIfPresent(Int64.self, forKey: .localTrips) ?? 0
        localMinutes = try container.decodeIfPresent(Int64.self, forKey: .localMinutes) ?? 0
        transfer = try container.decodeIfPresent(BusTransfer.self, forKey: .transfer)
        ridersToday = try container.decodeIfPresent(Int64.self, forKey: .ridersToday) ?? 0
        riderThousandths = try container.decodeIfPresent(Int64.self, forKey: .riderThousandths) ?? 0
        days = try container.decodeIfPresent([FerryDay].self, forKey: .days) ?? []
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .piers, in: container,
                debugDescription: "A ferry route has 2 to \(Self.maximumPiers) piers, a crossing of 1 to \(Self.maximumLegMetres) m between each two, a service and 0 to \(Self.maximumBoats) boats."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(piers.map { Pier(row: $0.row, column: $0.column) }, forKey: .piers)
        try container.encode(legMetres, forKey: .legMetres)
        try container.encode(service, forKey: .service)
        try container.encode(boats, forKey: .boats)
        if feederTrips != 0 { try container.encode(feederTrips, forKey: .feederTrips) }
        if feederMinutes != 0 { try container.encode(feederMinutes, forKey: .feederMinutes) }
        if localTrips != 0 { try container.encode(localTrips, forKey: .localTrips) }
        if localMinutes != 0 { try container.encode(localMinutes, forKey: .localMinutes) }
        try container.encodeIfPresent(transfer, forKey: .transfer)
        if ridersToday != 0 { try container.encode(ridersToday, forKey: .ridersToday) }
        if riderThousandths != 0 { try container.encode(riderThousandths, forKey: .riderThousandths) }
        if !days.isEmpty { try container.encode(days, forKey: .days) }
    }
}

// MARK: - Commands

extension GameWorld {
    /// Opens a ferry route through `piers` with `boats` boats (decision
    /// 585), paying ``FerryRoute/pierPrice`` a pier and
    /// ``FerryRoute/boatPrice`` a boat. With `legMetres` (a real route's,
    /// one fewer than the piers) it crosses those lengths; without, the
    /// straight line between the cells' middles, a metre at least.
    ///
    /// - Throws, checked in this order: ``GameError/idsExhausted`` once the
    ///   numbers run out; ``GameError/invalidFerryRoute`` for fewer than 2
    ///   piers or more than ``FerryRoute/maximumPiers``, a pier off the
    ///   world, two piers in a row on one cell, a crossing not 1 to
    ///   ``FerryRoute/maximumLegMetres`` m, a headway or runs out of range,
    ///   or too many boats; ``GameError/pierNotBesideWater(row:column:)``
    ///   for the first pier on water or with no water beside it;
    ///   ``GameError/insufficientFunds(required:available:)``. The world is
    ///   then unchanged.
    @discardableResult
    public mutating func createFerryRoute(piers: [CellPosition], legMetres: [Int64]? = nil,
                                          service: BusService, boats: Int) throws(GameError) -> FerryRoute {
        let (id, next) = try Self.allocateID(from: nextFerryRouteID)
        let legs = try ferryLegs(piers: piers, given: legMetres)
        let route = FerryRoute(id: FerryRouteID(rawValue: id), piers: piers, legMetres: legs, service: service, boats: boats)
        guard route.isValid else { throw .invalidFerryRoute }
        try checkPiers(piers)
        try spendOnFerries(FerryRoute.price(piers: piers.count, boats: boats))
        ferryRoutes.append(route)
        nextFerryRouteID = next
        ferryRoutesChanged()
        return ferryRoutes[ferryRoutes.count - 1]
    }

    /// Sails `boats` boats on route `id`, paying ``FerryRoute/boatPrice``
    /// for each more; fewer are sold for nothing. None stops the route.
    ///
    /// - Throws: ``GameError/unknownFerryRoute(_:)``;
    ///   ``GameError/invalidFerryRoute`` outside 0 to
    ///   ``FerryRoute/maximumBoats``; ``GameError/insufficientFunds(required:available:)``.
    public mutating func setFerryBoats(_ id: FerryRouteID, to boats: Int) throws(GameError) {
        let index = try ferryRouteIndex(of: id)
        guard (0...FerryRoute.maximumBoats).contains(boats) else { throw .invalidFerryRoute }
        guard boats != ferryRoutes[index].boats else { return }
        try spendOnFerries(Money(FerryRoute.boatPrice.amount * Int64(max(0, boats - ferryRoutes[index].boats))))
        ferryRoutes[index].boats = boats
        ferryRoutesChanged()
    }

    /// Sets when route `id`'s boats leave its first pier: a headway or a
    /// day's runs. Free.
    ///
    /// - Throws: ``GameError/unknownFerryRoute(_:)``;
    ///   ``GameError/invalidFerryRoute`` for a headway outside 1 to
    ///   ``BusService/longestHeadway`` or runs out of order or range.
    public mutating func setFerryRuns(_ id: FerryRouteID, to service: BusService) throws(GameError) {
        let index = try ferryRouteIndex(of: id)
        guard service.isValid else { throw .invalidFerryRoute }
        guard service != ferryRoutes[index].service else { return }
        ferryRoutes[index].service = service
        ferryRoutesChanged()
    }

    /// Closes route `id`; its piers and boats are not sold back.
    ///
    /// - Throws: ``GameError/unknownFerryRoute(_:)``.
    public mutating func removeFerryRoute(_ id: FerryRouteID) throws(GameError) {
        ferryRoutes.remove(at: try ferryRouteIndex(of: id))
        ferryRoutesChanged()
    }

    // MARK: - Queries

    /// Route `id`, or `nil`.
    public func ferryRoute(id: FerryRouteID) -> FerryRoute? {
        ferryRoutes.first { $0.id == id }
    }

    /// Whether a pier can stand on the cell at `row`, `column`: a land cell
    /// of the world with water on one of its four sides.
    public func isPierCell(row: Int, column: Int) -> Bool {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard (0..<rows).contains(row), (0..<columns).contains(column), !terrain.isWater(row: row, column: column) else { return false }
        return [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)].contains { r, c in
            (0..<rows).contains(r) && (0..<columns).contains(c) && terrain.isWater(row: r, column: c)
        }
    }

    /// Whether route `id`'s boats sail on game day `day`: not while a
    /// typhoon covers one of its piers. `false` for no such route.
    public func ferryRouteIsOpen(_ id: FerryRouteID, onDay day: Int64) -> Bool {
        guard let route = ferryRoute(id: id) else { return false }
        let piers = route.piers.map { Self.middle(of: $0) }
        return !typhoons(onDay: day).contains { typhoon in typhoon.isActive(onDay: day) && piers.contains { typhoon.covers($0) } }
    }

    // MARK: - Internals

    func ferryRouteIndex(of id: FerryRouteID) throws(GameError) -> Int {
        guard let index = ferryRoutes.firstIndex(where: { $0.id == id }) else { throw .unknownFerryRoute(id) }
        return index
    }

    /// The crossings of a route through `piers`: `given`, or the straight
    /// lines between the cells' middles, rounded half up to the metre.
    private func ferryLegs(piers: [CellPosition], given: [Int64]?) throws(GameError) -> [Int64] {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard (2...FerryRoute.maximumPiers).contains(piers.count),
              piers.allSatisfy({ (0..<rows).contains($0.row) && (0..<columns).contains($0.column) })
        else { throw .invalidFerryRoute }
        if let given {
            guard given.count == piers.count - 1 else { throw .invalidFerryRoute }
            return given
        }
        return zip(piers, piers.dropFirst()).map { a, b in
            let units = FixedPoint.roundedSquareRoot(Self.squaredDistance(Self.middle(of: a), Self.middle(of: b)))
            return max(1, (units + WorldCoordinate.unitsPerMetre / 2) / WorldCoordinate.unitsPerMetre)
        }
    }

    /// Refuses the first of `piers` that is not ``isPierCell(row:column:)``.
    private func checkPiers(_ piers: [CellPosition]) throws(GameError) {
        if let pier = piers.first(where: { !isPierCell(row: $0.row, column: $0.column) }) {
            throw .pierNotBesideWater(row: pier.row, column: pier.column)
        }
    }

    private mutating func spendOnFerries(_ price: Money) throws(GameError) {
        guard price > .zero else { return }
        try economy.spend(price)
        if accounts.mode == .management {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + price }
        }
    }

    /// After a route opens, closes or changes its boats or runs: the land's
    /// shares and the plan follow.
    private mutating func ferryRoutesChanged() {
        refreshLandDemand()
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - The land it draws

    /// Each sailing route's share of the land, worked out afresh: every
    /// cell whose middle lies within ``BusRoute/stopReach`` of a pier of a
    /// route with a boat, outside every station's ``Land/catchmentRadius``
    /// and not in `excluded` (a cableway's), goes whole to its nearest pier
    /// (then the lower route, then the earlier pier). A route that meets a
    /// station (``FerryRoute/transfer``, worked out here first) brings
    /// ``FerryRoute/riderShare`` of its land to it, their minutes the walk,
    /// half the headway rounded up, the crossing to the pier nearest the
    /// station and the walk on, a day at most, the people's average rounded
    /// half up; and every route carries the trips between its piers
    /// (``refreshFerryTrips(_:)``).
    ///
    /// Returns each station's added share and the cells it took, which no
    /// bus stop then draws. Without land demand every figure is 0. Called
    /// by ``refreshLandDemand()``, after the cableways and before the
    /// buses.
    mutating func refreshFerryFeeders(excluding excluded: Set<Int>) -> (shares: [StationID: LandDemand.Share], cells: Set<Int>) {
        guard !ferryRoutes.isEmpty else { return ([:], []) }
        let fed = landStations
        refreshFerryTransfers(among: fed)
        var added: [StationID: LandDemand.Share] = [:]
        var taken = Set<Int>()
        var figures = [(trips: Int64, minutes: Int64)](repeating: (0, 0), count: ferryRoutes.count)
        var pierLand = [[CityBusStopLand]](repeating: [], count: ferryRoutes.count)
        if drawsDemandFromLand {
            var walkable = Set<Int>()
            for station in fed {
                land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in walkable.insert(index) }
            }
            var nearest: [Int: (squared: Int64, route: Int, pier: Int)] = [:]
            for (position, route) in ferryRoutes.enumerated() where route.boats > 0 {
                for (pier, cell) in route.piers.enumerated() {
                    land.forEachCell(within: BusRoute.stopReach, of: Self.middle(of: cell)) { index, squared in
                        guard !walkable.contains(index), !excluded.contains(index) else { return }
                        let candidate = (squared, position, pier)
                        if nearest[index].map({ candidate < $0 }) ?? true { nearest[index] = candidate }
                    }
                }
            }
            var shares = [LandDemand.Share](repeating: LandDemand.Share(), count: ferryRoutes.count)
            var weighted = [Int64](repeating: 0, count: ferryRoutes.count)
            for position in ferryRoutes.indices {
                pierLand[position] = Array(repeating: CityBusStopLand(), count: ferryRoutes[position].piers.count)
            }
            for index in nearest.keys.sorted() {
                let (squared, position, pier) = nearest[index]!
                let cell = land.cells[index]
                let people = cell.residents + cell.jobs
                guard people > 0 else { continue }
                taken.insert(index)
                let route = ferryRoutes[position]
                let walk = BusRoute.walkMinutes(units: FixedPoint.roundedSquareRoot(squared))
                pierLand[position][pier].share.add(cell.residents, cell.jobs, of: cell.use)
                pierLand[position][pier].walked += people * walk
                guard let transfer = route.transfer, let met = station(id: transfer.station), let headway = route.headway else { continue }
                let at = route.piers[transfer.stop]
                let ride = route.rideMinutes(from: pier, to: transfer.stop)
                    + BusRoute.walkMinutes(units: FixedPoint.roundedSquareRoot(Self.squaredDistance(Self.middle(of: at), met.location)))
                let minutes = min(GameTime.minutesPerDay, walk + (headway + 1) / 2 + ride)
                shares[position].add(cell.residents, cell.jobs, of: cell.use)
                weighted[position] += people * minutes
            }
            for position in ferryRoutes.indices {
                let people = shares[position].people
                shares[position].scale(FerryRoute.riderShare)
                guard people > 0, let trips = shares[position].demand?.dailyTrips, let feeds = ferryRoutes[position].transfer?.station else { continue }
                figures[position] = (trips, (weighted[position] * 2 + people) / (2 * people))
                var share = added[feeds] ?? LandDemand.Share()
                share.add(shares[position])
                added[feeds] = share
            }
        }
        for position in ferryRoutes.indices {
            ferryRoutes[position].feederTrips = figures[position].trips
            ferryRoutes[position].feederMinutes = figures[position].minutes
        }
        refreshFerryTrips(pierLand)
        return (added, taken)
    }

    /// Each route's station: of `stations`, the nearest a pier's middle
    /// within ``BusRoute/stopReach``, then the lower station ID, then the
    /// earlier pier; `nil` when none is.
    mutating func refreshFerryTransfers(among stations: [Station]) {
        let reach = BusRoute.stopReach * BusRoute.stopReach
        for position in ferryRoutes.indices {
            var best: (squared: Int64, station: Int, pier: Int)?
            for (pier, cell) in ferryRoutes[position].piers.enumerated() {
                let middle = Self.middle(of: cell)
                for station in stations {
                    let squared = Self.squaredDistance(middle, station.location)
                    guard squared <= reach else { continue }
                    let candidate = (squared, station.id.rawValue, pier)
                    if best.map({ candidate < $0 }) ?? true { best = candidate }
                }
            }
            ferryRoutes[position].transfer = best.map { BusTransfer(station: StationID(rawValue: $0.station), stop: $0.pier) }
        }
    }

    /// The trips between each sailing route's piers, worked out afresh
    /// into its ``FerryRoute/localTrips`` and ``FerryRoute/localMinutes``
    /// from `pierLand`, as a cableway's (``refreshCablewayTrips(_:)``),
    /// the wait half the headway rounded up.
    mutating func refreshFerryTrips(_ pierLand: [[CityBusStopLand]]) {
        for position in ferryRoutes.indices {
            ferryRoutes[position].localTrips = 0
            ferryRoutes[position].localMinutes = 0
            let reached = pierLand[position]
            let route = ferryRoutes[position]
            guard !reached.isEmpty, let headway = route.headway else { continue }
            let people = reached.map(\.share.people)
            let walks = reached.map { $0.share.people > 0 ? ($0.walked * 2 + $0.share.people) / (2 * $0.share.people) : 0 }
            var total: Int64 = 0, weighted: Int64 = 0
            for from in reached.indices {
                var share = reached[from].share
                share.scale(FerryRoute.localShare)
                guard let trips = share.demand?.dailyTrips else { continue }
                let others = people.indices.filter { $0 != from && people[$0] > 0 }
                let sum = others.reduce(0) { $0 + people[$1] }
                guard sum > 0 else { continue }
                var parts = others.map { (pier: $0, whole: trips * people[$0] / sum, rest: trips * people[$0] % sum) }
                var left = trips - parts.reduce(0) { $0 + $1.whole }
                for index in parts.indices.sorted(by: { (parts[$0].rest, parts[$1].pier) > (parts[$1].rest, parts[$0].pier) }) where left > 0 {
                    parts[index].whole += 1
                    left -= 1
                }
                for part in parts where part.whole > 0 {
                    let squared = Self.squaredDistance(Self.middle(of: route.piers[from]), Self.middle(of: route.piers[part.pier]))
                    var kept = part.whole * DistanceDemand.share(squaredDistance: squared) / 1_000
                    let minutes = min(GameTime.minutesPerDay, walks[from] + walks[part.pier] + (headway + 1) / 2
                        + route.rideMinutes(from: from, to: part.pier))
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
            ferryRoutes[position].localTrips = min(StationDemand.maximumDailyTrips, total)
            ferryRoutes[position].localMinutes = (weighted * 2 + total) / (2 * total)
        }
    }

    /// The ferry routes bringing `origin`'s trips: each one's trips and
    /// door-to-door minutes.
    func ferryFeeders(of origin: StationID) -> [(trips: Int64, minutes: Int64)] {
        ferryRoutes.compactMap { $0.transfer?.station == origin && $0.feederTrips > 0 ? ($0.feederTrips, $0.feederMinutes) : nil }
    }

    /// `boarded` riders set out from `station` by train, or arrived there
    /// at the end of their journey: the share of them each route meeting it
    /// brought (or takes home) rides the boats, counted in thousandths.
    mutating func countFerryRiders(_ boarded: Int64, at station: StationID) {
        guard boarded > 0, accounts.mode == .management, !ferryRoutes.isEmpty,
              let trips = passengers.first(where: { $0.station == station })?.demand?.dailyTrips, trips > 0 else { return }
        for index in ferryRoutes.indices where ferryRoutes[index].transfer?.station == station && ferryRoutes[index].feederTrips > 0 {
            let thousandths = ferryRoutes[index].riderThousandths + boarded * min(trips, ferryRoutes[index].feederTrips) * 1_000 / trips
            ferryRoutes[index].ridersToday = min(Self.maximumHourly, ferryRoutes[index].ridersToday + thousandths / 1_000)
            ferryRoutes[index].riderThousandths = thousandths % 1_000
        }
    }

    /// The day's ferries, a row for them all: each route's riders (those
    /// from the trains and its ``FerryRoute/localTrips``, at most
    /// ``FerryRoute/dailyCapacity(onDay:)``, none on a day no boat sails)
    /// pay ``FerryRoute/fare`` in, and its
    /// ``FerryRoute/dailyCost(onDay:)`` goes out every day; kept on the
    /// route for ``FerryRoute/keptDays`` days.
    mutating func settleFerries(day: Int64, time: GameTime) {
        guard accounts.mode == .management, !ferryRoutes.isEmpty else { return }
        var fares = Money.zero, cost = Money.zero
        for index in ferryRoutes.indices {
            let route = ferryRoutes[index]
            let open = ferryRouteIsOpen(route.id, onDay: day)
            let riders = open ? min(route.dailyCapacity(onDay: day), route.ridersToday + route.localTrips) : 0
            let dayFares = Money(riders * FerryRoute.fare.amount)
            let dayCost = route.dailyCost(onDay: day)
            fares = fares + dayFares
            cost = cost + dayCost
            ferryRoutes[index].days.append(FerryDay(day: day, riders: riders, fares: dayFares, cost: dayCost, closed: !open))
            if ferryRoutes[index].days.count > FerryRoute.keptDays { ferryRoutes[index].days.removeFirst() }
            ferryRoutes[index].ridersToday = 0
        }
        guard fares > .zero || cost > .zero else { return }
        write(LedgerEntry(
            kind: .dailyFerries, time: time, amount: fares - cost,
            breakdown: [LedgerLine(item: .ferryFares, amount: fares), LedgerLine(item: .ferryRunning, amount: .zero - cost)]
        ), day: day)
    }

    // MARK: - Validation

    func ferryRoutesProblem() -> String? {
        guard nextFerryRouteID >= 1 else { return "The next ferry route's number is 1 or more." }
        guard !ferryRoutes.isEmpty else { return nil }
        let ids = Set(stations.map(\.id))
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        guard ferryRoutes.allSatisfy({ $0.isValid && (1..<nextFerryRouteID).contains($0.id.rawValue) && ($0.transfer.map { ids.contains($0.station) } ?? true)
                  && $0.piers.allSatisfy { (0..<rows).contains($0.row) && (0..<columns).contains($0.column) } }),
              zip(ferryRoutes, ferryRoutes.dropFirst()).allSatisfy({ $0.id < $1.id })
        else {
            return "Each ferry route is well formed, a number handed out, in order, its piers in the world and its transfer a station the world has."
        }
        return nil
    }
}
