// Decision 400, sequel 10i-2: the company's buses, feeding its stations.
// A route runs along the roads (``RoadGrid``) from its stops to the train
// station it feeds; the land within ``BusRoute/stopReach`` of a stop that
// no station reaches on foot joins that station's share, and its riders
// take the bus to the train: walk to the stop, wait half the headway,
// ride at ``BusRoute/metresPerHour``. Their door-to-door minutes take the
// place of one end's walk in the mode shift (decision 332), and each pays
// one bus fare, booked to the route's own day (`dailyBuses`).
//
// The balance (decision 400's sequel of 2026-10-25): the land a stop
// reaches rides half as much as the land a station reaches on foot
// (``BusRoute/riderShare``), riders take the bus home again from the
// train, and a route costs ``BusRoute/costPerKilometre`` for every
// kilometre its buses run.
//
// The player draws a route from its stops, and GameCore finds the way
// along the roads; a real route the app sells is laid with its real
// lengths, motorway stretches and all (the roads GameCore keeps have no
// motorways: decision 400's author's choice B). GameCore reads no real
// data: the app gives the stops and lengths as numbers, as it gives a
// bought line's riders (decision 315).
//
// The references: geo-scene's `BusEngine.ts` moves real buses from their
// GPS and draws them; the Taiwan rail site's bus transfers list each
// station's stops within 600 m, the walk 1.25 times the straight line at
// 75 m a minute (`great_circle_x1.25_at_75m_per_min`), kept here. Neither
// runs buses of a company's own (gap): the rest is the project's own.

/// A bus route's number, handed out in order and never used again.
public struct BusRouteID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: BusRouteID, rhs: BusRouteID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// When a route's buses leave its first stop.
public enum BusService: Hashable, Sendable {
    /// One every so many minutes, all day.
    case every(minutes: Int64)
    /// At these minutes of the day (0 to 1439), in order: a real
    /// route's timetable.
    case runs([Int64])

    /// The longest headway set: half a day.
    public static let longestHeadway: Int64 = 720
    /// The most runs a day.
    public static let maximumRuns = 480

    var isValid: Bool {
        switch self {
        case .every(let minutes):
            (1...Self.longestHeadway).contains(minutes)
        case .runs(let minutes):
            (1...Self.maximumRuns).contains(minutes.count) && minutes.allSatisfy { (0..<GameTime.minutesPerDay).contains($0) }
                && zip(minutes, minutes.dropFirst()).allSatisfy { $0 < $1 }
        }
    }

    /// The minutes between buses it sets: the headway, or the runs'
    /// average gap, rounded half up (a day for one run).
    var minutesApart: Int64 {
        switch self {
        case .every(let minutes):
            minutes
        case .runs(let minutes):
            minutes.count < 2 ? GameTime.minutesPerDay
                : ((minutes.last! - minutes.first!) * 2 + Int64(minutes.count - 1)) / (2 * Int64(minutes.count - 1))
        }
    }
}

/// One day of a route's takings.
public struct BusDay: Hashable, Codable, Sendable {
    public let day: Int64
    public let riders: Int64
    public let fares: Money
    public let cost: Money
}

/// A bus route feeding a train station (decision 400, 10i-2).
public struct BusRoute: Hashable, Sendable {
    public let id: BusRouteID
    /// The train station it feeds, its last stop.
    public let station: StationID
    /// Its stops, in order, each on a road cell; the station follows the
    /// last.
    public internal(set) var stops: [CellPosition]
    /// The road's metres from each stop to the next, the last to the
    /// station.
    public internal(set) var legMetres: [Int64]
    public internal(set) var service: BusService
    public internal(set) var buses: Int
    /// The trips a day its land makes, and their door-to-door minutes to
    /// the station, the people's average: worked out with the land's
    /// demand (``GameWorld/refreshLandDemand()``), 0 while it does not run.
    public internal(set) var feederTrips: Int64 = 0
    public internal(set) var feederMinutes: Int64 = 0
    /// Riders today, and the thousandths of one carried over.
    public internal(set) var ridersToday: Int64 = 0
    var riderThousandths: Int64 = 0
    /// The last ``keptDays`` days, oldest first.
    public internal(set) var days: [BusDay] = []

    /// How far a stop draws riders on foot: 400 m.
    public static let stopReach: Int64 = 400 * WorldCoordinate.unitsPerMetre
    /// A bus's speed with its stops: 18 km/h.
    public static let metresPerHour: Int64 = 18_000
    /// Minutes at the ends of each round trip.
    public static let layoverMinutes: Int64 = 10
    /// What a stop and a bus cost: $10,000 and $50,000.
    public static let stopPrice = Money(1_000_000)
    public static let busPrice = Money(5_000_000)
    /// A rider's fare: one fare segment, $5.
    public static let fare = Money(500)
    /// What a bus costs for each kilometre it runs, driver, fuel and
    /// upkeep: $20 (Taiwan's city buses, NT$52–66 a bus-kilometre, at
    /// NT$3 a dollar).
    public static let costPerKilometre = Money(2_000)
    /// The part of the land a stop reaches that rides as much as the land
    /// a station reaches on foot: a half, the rest taking a scooter or
    /// staying near home.
    public static let riderShare: (numerator: Int64, denominator: Int64) = (1, 2)
    /// The most stops and buses a route has.
    public static let maximumStops = 64
    public static let maximumBuses = 99
    /// The longest leg a real route is given: 200 km.
    public static let maximumLegMetres: Int64 = 200_000
    /// The days of takings kept.
    public static let keptDays = 30
    /// The most road cells the way between two stops is looked for in.
    static let searchLimit = 65_536

    /// The road's metres from end to end.
    public var metres: Int64 {
        legMetres.reduce(0, +)
    }

    /// The minutes there and back, the layovers with them, rounded up.
    public var roundTripMinutes: Int64 {
        (2 * metres * 60 + Self.metresPerHour - 1) / Self.metresPerHour + Self.layoverMinutes
    }

    /// The minutes between buses: as set, but no closer than its buses
    /// can keep; `nil` with no bus.
    public var headway: Int64? {
        guard buses > 0 else { return nil }
        let fewest = (roundTripMinutes + Int64(buses) - 1) / Int64(buses)
        return max(service.minutesApart, fewest)
    }

    /// The buses that leave its first stop a day, and as many back: one
    /// each headway all day, or its runs, as many as its buses keep; none
    /// without a bus.
    public var dailyDepartures: Int64 {
        guard let headway else { return 0 }
        let kept = GameTime.minutesPerDay / headway
        switch service {
        case .every: return kept
        case .runs(let minutes): return min(Int64(minutes.count), max(1, kept))
        }
    }

    /// What its buses cost a day: ``costPerKilometre`` for each kilometre
    /// there and back of each departure, rounded half up to the cent.
    public var dailyCost: Money {
        Money((dailyDepartures * 2 * metres * Self.costPerKilometre.amount + 500) / 1_000)
    }

    /// Minutes on board from stop `index` to the station, rounded half up.
    func rideMinutes(fromStop index: Int) -> Int64 {
        let metres = legMetres[index...].reduce(0, +)
        return (metres * 60 + Self.metresPerHour / 2) / Self.metresPerHour
    }

    /// Minutes walking `units` in a straight line: 1.25 times as far, at
    /// 75 m a minute, rounded half up.
    static func walkMinutes(units: Int64) -> Int64 {
        let per = 75 * WorldCoordinate.unitsPerMetre * 4 / 5
        return (units + per / 2) / per
    }

    var isValid: Bool {
        (1...Self.maximumStops).contains(stops.count) && legMetres.count == stops.count
            && legMetres.allSatisfy { (0...Self.maximumLegMetres).contains($0) } && service.isValid
            && (0...Self.maximumBuses).contains(buses) && (0...StationDemand.maximumDailyTrips).contains(feederTrips)
            && feederMinutes >= 0 && feederMinutes <= GameTime.minutesPerDay && ridersToday >= 0 && (0..<1_000).contains(riderThousandths)
            && days.count <= Self.keptDays && days.allSatisfy { $0.riders >= 0 && $0.fares >= .zero && $0.cost >= .zero }
            && zip(days, days.dropFirst()).allSatisfy { $0.day < $1.day }
    }
}

// MARK: - Codable

extension BusService: Codable {
    private enum CodingKeys: String, CodingKey {
        case every, runs
    }

    /// `{"every": minutes}` or `{"runs": [minutes]}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (try container.decodeIfPresent(Int64.self, forKey: .every), try container.decodeIfPresent([Int64].self, forKey: .runs)) {
        case (let minutes?, nil): self = .every(minutes: minutes)
        case (nil, let runs?): self = .runs(runs)
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A bus service is a headway or runs, one of them."))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .every(let minutes): try container.encode(minutes, forKey: .every)
        case .runs(let minutes): try container.encode(minutes, forKey: .runs)
        }
    }
}

extension BusRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, station, stops, legMetres, service, buses, feederTrips, feederMinutes, ridersToday, riderThousandths, days
    }

    private struct Stop: Codable {
        var row: Int
        var column: Int
    }

    /// The route, with its derived figures and takings; refused when
    /// malformed. The world checks its station and stops.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BusRouteID.self, forKey: .id)
        station = try container.decode(StationID.self, forKey: .station)
        let stops = try container.decode([Stop].self, forKey: .stops)
        guard stops.count <= Self.maximumStops else {
            throw DecodingError.dataCorruptedError(forKey: .stops, in: container, debugDescription: "A bus route has at most \(Self.maximumStops) stops.")
        }
        self.stops = stops.map { CellPosition(row: $0.row, column: $0.column) }
        legMetres = try container.decode([Int64].self, forKey: .legMetres)
        service = try container.decode(BusService.self, forKey: .service)
        buses = try container.decode(Int.self, forKey: .buses)
        feederTrips = try container.decodeIfPresent(Int64.self, forKey: .feederTrips) ?? 0
        feederMinutes = try container.decodeIfPresent(Int64.self, forKey: .feederMinutes) ?? 0
        ridersToday = try container.decodeIfPresent(Int64.self, forKey: .ridersToday) ?? 0
        riderThousandths = try container.decodeIfPresent(Int64.self, forKey: .riderThousandths) ?? 0
        days = try container.decodeIfPresent([BusDay].self, forKey: .days) ?? []
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .stops, in: container, debugDescription: "A bus route has 1 to \(Self.maximumStops) stops, a leg for each, a service and 0 to \(Self.maximumBuses) buses.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(station, forKey: .station)
        try container.encode(stops.map { Stop(row: $0.row, column: $0.column) }, forKey: .stops)
        try container.encode(legMetres, forKey: .legMetres)
        try container.encode(service, forKey: .service)
        try container.encode(buses, forKey: .buses)
        if feederTrips != 0 { try container.encode(feederTrips, forKey: .feederTrips) }
        if feederMinutes != 0 { try container.encode(feederMinutes, forKey: .feederMinutes) }
        if ridersToday != 0 { try container.encode(ridersToday, forKey: .ridersToday) }
        if riderThousandths != 0 { try container.encode(riderThousandths, forKey: .riderThousandths) }
        if !days.isEmpty { try container.encode(days, forKey: .days) }
    }
}

// MARK: - Commands

extension GameWorld {
    /// Opens a bus route to `station` through `stops`, each on a road cell
    /// (decision 400, 10i-2), with `buses` buses: pays
    /// ``BusRoute/stopPrice`` a stop and ``BusRoute/busPrice`` a bus. With
    /// `legMetres` (a real route's, one a stop, the last to the station)
    /// it runs those lengths; without, the shortest way along the roads,
    /// the station's own cell on one.
    ///
    /// - Throws, checked in this order: ``GameError/roadsNotEnabled``;
    ///   ``GameError/unknownStation(_:)``; ``GameError/idsExhausted`` once
    ///   the numbers run out; ``GameError/invalidBusRoute``
    ///   for no stops or too many, legs not one a stop or too long, a
    ///   headway or runs out of range, or too many buses;
    ///   ``GameError/busStopOffRoad`` for a stop, or a drawn route's
    ///   station, on no road; ``GameError/busStopsNotConnected(leg:)``;
    ///   ``GameError/insufficientFunds(required:available:)``. The world is
    ///   then unchanged.
    @discardableResult
    public mutating func createBusRoute(to station: StationID, stops: [CellPosition], legMetres: [Int64]? = nil,
                                        service: BusService, buses: Int) throws(GameError) -> BusRoute {
        guard roads != nil else { throw .roadsNotEnabled }
        guard stations.contains(where: { $0.id == station }) else { throw .unknownStation(station) }
        guard service.isValid, (0...BusRoute.maximumBuses).contains(buses) else { throw .invalidBusRoute }
        let (id, next) = try Self.allocateID(from: nextBusRouteID)
        let legs = try busLegs(to: station, stops: stops, given: legMetres)
        let route = BusRoute(id: BusRouteID(rawValue: id), station: station, stops: stops, legMetres: legs, service: service, buses: buses)
        guard route.isValid else { throw .invalidBusRoute }
        let price = Money(BusRoute.stopPrice.amount * Int64(stops.count) + BusRoute.busPrice.amount * Int64(buses))
        try spendOnBuses(price)
        busRoutes.append(route)
        nextBusRouteID = next
        busRoutesChanged()
        return busRoutes[busRoutes.count - 1]
    }

    /// Moves route `id`'s stops, paying ``BusRoute/stopPrice`` for each
    /// stop more than it had; `legMetres` as ``createBusRoute(to:stops:legMetres:service:buses:)``.
    ///
    /// - Throws: ``GameError/unknownBusRoute(_:)``, then as
    ///   ``createBusRoute(to:stops:legMetres:service:buses:)``. The world is
    ///   then unchanged.
    public mutating func setBusRouteStops(_ id: BusRouteID, stops: [CellPosition], legMetres: [Int64]? = nil) throws(GameError) {
        let index = try busRouteIndex(of: id)
        var route = busRoutes[index]
        route.legMetres = try busLegs(to: route.station, stops: stops, given: legMetres)
        let added = max(0, stops.count - route.stops.count)
        route.stops = stops
        guard route.isValid else { throw .invalidBusRoute }
        try spendOnBuses(Money(BusRoute.stopPrice.amount * Int64(added)))
        busRoutes[index] = route
        busRoutesChanged()
    }

    /// Runs `buses` buses on route `id`, paying ``BusRoute/busPrice`` for
    /// each more; fewer are sold for nothing. None stops the route.
    ///
    /// - Throws: ``GameError/unknownBusRoute(_:)``;
    ///   ``GameError/invalidBusRoute`` outside 0 to
    ///   ``BusRoute/maximumBuses``; ``GameError/insufficientFunds(required:available:)``.
    public mutating func setBusCount(_ id: BusRouteID, to buses: Int) throws(GameError) {
        let index = try busRouteIndex(of: id)
        guard (0...BusRoute.maximumBuses).contains(buses) else { throw .invalidBusRoute }
        guard buses != busRoutes[index].buses else { return }
        try spendOnBuses(Money(BusRoute.busPrice.amount * Int64(max(0, buses - busRoutes[index].buses))))
        busRoutes[index].buses = buses
        busRoutesChanged()
    }

    /// Sets when route `id`'s buses leave: a headway or a day's runs. Free.
    ///
    /// - Throws: ``GameError/unknownBusRoute(_:)``;
    ///   ``GameError/invalidBusRoute`` for a headway outside 1 to
    ///   ``BusService/longestHeadway`` or runs out of order or range.
    public mutating func setBusRuns(_ id: BusRouteID, to service: BusService) throws(GameError) {
        let index = try busRouteIndex(of: id)
        guard service.isValid else { throw .invalidBusRoute }
        guard service != busRoutes[index].service else { return }
        busRoutes[index].service = service
        busRoutesChanged()
    }

    /// Closes route `id`; its stops and buses are not sold back.
    ///
    /// - Throws: ``GameError/unknownBusRoute(_:)``.
    public mutating func removeBusRoute(_ id: BusRouteID) throws(GameError) {
        busRoutes.remove(at: try busRouteIndex(of: id))
        busRoutesChanged()
    }

    /// Records that route `id` is real route `realRoute`, bought: pays
    /// ``LineAcquisition/value(ofDailyRiders:tier:)`` for its `dailyRiders`, as
    /// a real line's (decision 315), on the books as capital spending.
    ///
    /// - Throws, checked in this order: ``GameError/unknownBusRoute(_:)``;
    ///   ``GameError/lineAlreadyAcquired`` if `realRoute` or the route was
    ///   bought before; ``GameError/invalidAcquisition`` for an empty or
    ///   too long name or riders outside 0 to
    ///   ``LineAcquisition/maximumDailyRiders``;
    ///   ``GameError/insufficientFunds(required:available:)``. The world is
    ///   then unchanged.
    public mutating func recordBusAcquisition(route id: BusRouteID, realRoute: String, dailyRiders: Int64) throws(GameError) {
        _ = try busRouteIndex(of: id)
        guard !acquisitions.contains(where: { $0.realLine == realRoute || $0.busRoute == id }) else { throw .lineAlreadyAcquired }
        guard !realRoute.isEmpty, realRoute.count <= LineAcquisition.maximumNameLength,
              (0...LineAcquisition.maximumDailyRiders).contains(dailyRiders) else {
            throw .invalidAcquisition
        }
        let value = LineAcquisition.value(ofDailyRiders: dailyRiders)
        try spendOnBuses(value)
        acquisitions.append(LineAcquisition(realLine: realRoute, busRoute: id, day: dayIndex(of: clock.now), value: value))
    }

    // MARK: - Queries

    /// Route `id`, or `nil`.
    public func busRoute(id: BusRouteID) -> BusRoute? {
        busRoutes.first { $0.id == id }
    }

    /// The shortest way along the roads from cell `start` to cell `end`,
    /// in metres (``RoadGrid/straightMetres`` a side,
    /// ``RoadGrid/diagonalMetres`` corner to corner), or `nil` when no road
    /// joins them within ``BusRoute/searchLimit`` cells.
    public func busRoadMetres(from start: CellPosition, to end: CellPosition) -> Int64? {
        guard let roads, roads.cells.contains(start), roads.cells.contains(end) else { return nil }
        guard start != end else { return 0 }
        // Dijkstra's search, the nearest first and then by row and column,
        // so the same roads give the same answer.
        var best: [CellPosition: Int64] = [start: 0]
        var heap = BusSearchHeap()
        heap.push((0, start))
        var settled = 0
        while let (metres, cell) = heap.pop() {
            guard metres == best[cell] else { continue }
            if cell == end { return metres }
            settled += 1
            guard settled <= BusRoute.searchLimit else { return nil }
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let next = CellPosition(row: cell.row + dr, column: cell.column + dc)
                    guard roads.cells.contains(next) else { continue }
                    let way = metres + (dr != 0 && dc != 0 ? RoadGrid.diagonalMetres : RoadGrid.straightMetres)
                    if best[next].map({ way < $0 }) ?? true {
                        best[next] = way
                        heap.push((way, next))
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Internals

    func busRouteIndex(of id: BusRouteID) throws(GameError) -> Int {
        guard let index = busRoutes.firstIndex(where: { $0.id == id }) else { throw .unknownBusRoute(id) }
        return index
    }

    /// The legs of a route to `station` through `stops`: `given`, or the
    /// roads' shortest ways.
    private func busLegs(to station: StationID, stops: [CellPosition], given: [Int64]?) throws(GameError) -> [Int64] {
        guard let roads else { throw .roadsNotEnabled }
        guard (1...BusRoute.maximumStops).contains(stops.count) else { throw .invalidBusRoute }
        if let given {
            guard given.count == stops.count, given.allSatisfy({ (0...BusRoute.maximumLegMetres).contains($0) }) else { throw .invalidBusRoute }
        }
        guard stops.allSatisfy(roads.cells.contains) else { throw .busStopOffRoad }
        if let given { return given }
        guard let location = stations.first(where: { $0.id == station })?.location, roads.cells.contains(roadCell(of: location)) else {
            throw .busStopOffRoad
        }
        let end = roadCell(of: location)
        var legs: [Int64] = []
        for (leg, start) in stops.enumerated() {
            guard let metres = busRoadMetres(from: start, to: leg + 1 < stops.count ? stops[leg + 1] : end) else {
                throw .busStopsNotConnected(leg: leg)
            }
            legs.append(metres)
        }
        return legs
    }

    private mutating func spendOnBuses(_ price: Money) throws(GameError) {
        guard price > .zero else { return }
        try economy.spend(price)
        if accounts.mode == .management {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + price }
        }
    }

    /// After a route opens, moves, closes or changes its buses: the land's
    /// shares and the plan follow.
    private mutating func busRoutesChanged() {
        refreshLandDemand()
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - The feeders

    /// Each running route's share of the land, worked out afresh into its
    /// ``BusRoute/feederTrips`` and ``BusRoute/feederMinutes``: every cell
    /// whose middle lies within ``BusRoute/stopReach`` of a stop of a
    /// route that runs (one bus at least) to a station the land is shared
    /// among, and outside every such station's ``Land/catchmentRadius``,
    /// goes whole to its nearest stop (then the lower route, then the
    /// earlier stop). Its minutes are the walk, half the headway rounded
    /// up and the ride, a day at most; a route's, its people's average,
    /// rounded half up. A route's share is its people times
    /// ``BusRoute/riderShare``.
    /// Returns each station's added share. Without land demand every
    /// route's figures are 0. Called by ``refreshLandDemand()``.
    mutating func refreshBusFeeders() -> [StationID: LandDemand.Share] {
        guard !busRoutes.isEmpty else { return [:] }
        var added: [StationID: LandDemand.Share] = [:]
        var figures = [(trips: Int64, minutes: Int64)](repeating: (0, 0), count: busRoutes.count)
        if drawsDemandFromLand {
            let fed = landStations
            var walkable = Set<Int>()
            for station in fed {
                land.forEachCell(within: Land.catchmentRadius, of: station.location) { index, _ in walkable.insert(index) }
            }
            let ids = Set(fed.map(\.id))
            var nearest: [Int: (squared: Int64, route: Int, stop: Int)] = [:]
            for (position, route) in busRoutes.enumerated() where route.buses > 0 && ids.contains(route.station) {
                for (stop, cell) in route.stops.enumerated() {
                    let middle = PlanPoint(x: Int64(cell.column) * Land.cellLength + Land.cellLength / 2,
                                           y: Int64(cell.row) * Land.cellLength + Land.cellLength / 2)
                    land.forEachCell(within: BusRoute.stopReach, of: middle) { index, squared in
                        guard !walkable.contains(index) else { return }
                        let candidate = (squared, position, stop)
                        if nearest[index].map({ candidate < $0 }) ?? true { nearest[index] = candidate }
                    }
                }
            }
            var shares = [LandDemand.Share](repeating: LandDemand.Share(), count: busRoutes.count)
            var weighted = [Int64](repeating: 0, count: busRoutes.count)
            for index in nearest.keys.sorted() {
                let (squared, position, stop) = nearest[index]!
                let cell = land.cells[index]
                let people = cell.residents + cell.jobs
                guard people > 0 else { continue }
                let route = busRoutes[position]
                // More than a day door to door counts as a day, so the
                // save keeps it (decision 400).
                let minutes = min(GameTime.minutesPerDay, BusRoute.walkMinutes(units: FixedPoint.roundedSquareRoot(squared))
                    + (route.headway! + 1) / 2 + route.rideMinutes(fromStop: stop))
                shares[position].add(cell.residents, cell.jobs, of: cell.use)
                weighted[position] += people * minutes
            }
            for position in busRoutes.indices {
                let people = shares[position].people
                shares[position].scale(BusRoute.riderShare)
                guard people > 0, let trips = shares[position].demand?.dailyTrips else { continue }
                figures[position] = (trips, (weighted[position] * 2 + people) / (2 * people))
                var share = added[busRoutes[position].station] ?? LandDemand.Share()
                share.add(shares[position])
                added[busRoutes[position].station] = share
            }
        }
        for position in busRoutes.indices {
            busRoutes[position].feederTrips = figures[position].trips
            busRoutes[position].feederMinutes = figures[position].minutes
        }
        return added
    }

    /// The feeders of `origin`'s trips: each running route's trips and
    /// door-to-door minutes, by route.
    func busFeeders(of origin: StationID) -> [(trips: Int64, minutes: Int64)] {
        busRoutes.compactMap { $0.station == origin && $0.feederTrips > 0 ? ($0.feederTrips, $0.feederMinutes) : nil }
    }

    /// `boarded` riders set out from `station` by train, or arrived there
    /// at the end of their journey: the share of them each of its feeders
    /// brought (or takes home) rides the bus, counted in thousandths.
    mutating func countBusRiders(_ boarded: Int64, at station: StationID) {
        guard boarded > 0, accounts.mode == .management, !busRoutes.isEmpty,
              let trips = passengers.first(where: { $0.station == station })?.demand?.dailyTrips, trips > 0 else { return }
        for index in busRoutes.indices where busRoutes[index].station == station && busRoutes[index].feederTrips > 0 {
            let thousandths = busRoutes[index].riderThousandths + boarded * min(trips, busRoutes[index].feederTrips) * 1_000 / trips
            busRoutes[index].ridersToday = min(Self.maximumHourly, busRoutes[index].ridersToday + thousandths / 1_000)
            busRoutes[index].riderThousandths = thousandths % 1_000
        }
    }

    /// The day's buses, a row for them all: each route's riders'
    /// ``BusRoute/fare`` in, its ``BusRoute/dailyCost`` out, kept
    /// on the route for ``BusRoute/keptDays`` days.
    mutating func settleBuses(day: Int64, time: GameTime) {
        guard accounts.mode == .management, !busRoutes.isEmpty else { return }
        var fares = Money.zero, cost = Money.zero
        for index in busRoutes.indices {
            let route = busRoutes[index]
            let routeFares = Money(route.ridersToday * BusRoute.fare.amount)
            let routeCost = route.dailyCost
            fares = fares + routeFares
            cost = cost + routeCost
            busRoutes[index].days.append(BusDay(day: day, riders: route.ridersToday, fares: routeFares, cost: routeCost))
            if busRoutes[index].days.count > BusRoute.keptDays { busRoutes[index].days.removeFirst() }
            busRoutes[index].ridersToday = 0
        }
        guard fares > .zero || cost > .zero else { return }
        write(LedgerEntry(
            kind: .dailyBuses, time: time, amount: fares - cost,
            breakdown: [LedgerLine(item: .busFares, amount: fares), LedgerLine(item: .busRunning, amount: .zero - cost)]
        ), day: day)
    }

    // MARK: - Validation

    func busRoutesProblem() -> String? {
        guard nextBusRouteID >= 1 else { return "The next bus route's number is 1 or more." }
        guard !busRoutes.isEmpty else { return nil }
        guard roads != nil else { return "Bus routes run only on a world's roads." }
        let ids = Set(stations.map(\.id))
        guard busRoutes.allSatisfy({ $0.isValid && $0.id.rawValue < nextBusRouteID && ids.contains($0.station)
                  && $0.stops.allSatisfy { (0..<Land.rows(in: bounds)).contains($0.row) && (0..<Land.columns(in: bounds)).contains($0.column) } }),
              zip(busRoutes, busRoutes.dropFirst()).allSatisfy({ $0.id < $1.id })
        else {
            return "Each bus route is well formed, a number handed out, in order, to a station the world has, its stops in the world."
        }
        return nil
    }
}

extension LandDemand.Share {
    /// Adds a cell's `residents` and `jobs` by its `use`, as the stations'
    /// shares count them.
    mutating func add(_ residents: Int64, _ jobs: Int64, of use: LandUse) {
        self.residents += residents
        switch use {
        case .office, .industrial, .agricultural: officeJobs += jobs
        case .civic: civicJobs += jobs
        case .leisure: leisureJobs += jobs
        case .residential, .commercial, .park: shopJobs += jobs
        }
    }

    /// Its people times `fraction`, each kind rounded down.
    mutating func scale(_ fraction: (numerator: Int64, denominator: Int64)) {
        residents = residents * fraction.numerator / fraction.denominator
        officeJobs = officeJobs * fraction.numerator / fraction.denominator
        shopJobs = shopJobs * fraction.numerator / fraction.denominator
        civicJobs = civicJobs * fraction.numerator / fraction.denominator
        leisureJobs = leisureJobs * fraction.numerator / fraction.denominator
    }

    /// Adds `other`'s people.
    mutating func add(_ other: LandDemand.Share) {
        residents += other.residents
        officeJobs += other.officeJobs
        shopJobs += other.shopJobs
        civicJobs += other.civicJobs
        leisureJobs += other.leisureJobs
    }
}

/// A binary heap of road cells, the fewest metres first, then by row and
/// column.
private struct BusSearchHeap {
    private var items: [(Int64, CellPosition)] = []

    private static func before(_ a: (Int64, CellPosition), _ b: (Int64, CellPosition)) -> Bool {
        (a.0, a.1.row, a.1.column) < (b.0, b.1.row, b.1.column)
    }

    mutating func push(_ item: (Int64, CellPosition)) {
        items.append(item)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.before(items[child], items[parent]) else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Int64, CellPosition)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1, right = left + 1
            var first = parent
            if left < items.count, Self.before(items[left], items[first]) { first = left }
            if right < items.count, Self.before(items[right], items[first]) { first = right }
            guard first != parent else { return top }
            items.swapAt(first, parent)
            parent = first
        }
    }
}
