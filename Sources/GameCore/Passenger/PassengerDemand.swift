// Passenger demand, release and queues (G1a, ARCHITECTURE decision 34),
// ported from the owner's `Ci/` reference
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - a station's demand shapes its trips over the day
//   (`buildStationFlowPresetCurves`, `applyStationHourlyODMultsToHourlyOD`:
//   the origin's `out` curve times the destination's `in` curve);
// - each origin–destination pair releases its hourly trips minute by
//   minute, interpolated between this hour and the next, keeping the
//   fraction for the next minute (`metroSpawnPassengersFromDispatchRuntime`,
//   `_metroFlowSpawnCountFromRate`);
// - released passengers wait at the origin, grouped by line, direction and
//   destination, up to the station's capacity, and the rest leave at once
//   (`_metroAdmitDispatchPassengers`, `metroGetStationWaitAdmitHeadroom`).
//
// Everything is integer arithmetic: the reference's floating-point rates
// become whole trips per hour, apportioned by largest remainder, and the
// minute's interpolation becomes a numerator over 3600.
//
// Dependency direction (ARCHITECTURE, "GameCore 內部的依賴方向"): this file
// direct demand reads stations, the lines' stops and the clock. Network
// demand also uses the derived physical service queries of PassengerRoutes;
// neither mode changes anything but the passengers and its route credits.

extension GameWorld {
    /// A passenger's release is counted in 1/3600ths: a trip rate per hour,
    /// spread over the 60 minutes of the hour.
    static let releaseUnit: Int64 = 3_600

    /// The game day demand is worked out for, with weekly demand, events
    /// or holidays: today's. `nil` without any, when every day is the same.
    var demandDay: Int64? {
        weeklyDemand || demandEvents != nil || disruptions != nil ? dayIndex(of: clock.now) : nil
    }

    /// Whether today's demand follows the weekend's hours: on a weekend,
    /// and (decision 154) on a holiday.
    var isDemandWeekend: Bool {
        let day = dayIndex(of: clock.now)
        return weeklyDemand && (StationDemand.isWeekend(day: day) || holiday(onDay: day) != nil)
    }

    /// The trips station `station`, with `demand`, starts today: its daily
    /// trips, or with weekly demand today's share of its week (see
    /// ``StationDemand/trips(onDay:)``), raised by any event there (see
    /// ``demandMultiplier(at:)``) and by today's holiday (decision 154,
    /// ``holidayMultiplier``), rounded half up.
    func trips(of demand: StationDemand, at station: StationID) -> Int64 {
        let trips = weeklyDemand ? demand.trips(onDay: dayIndex(of: clock.now)) : demand.dailyTrips
        guard demandEvents != nil || disruptions != nil else { return trips }
        // Without holidays the network's multiplier is 1000, and this is
        // the event's rounding alone, as before them.
        let multiplier = (demandEvents != nil ? demandMultiplier(at: station) : 1_000) * holidayMultiplier
        return (trips * multiplier + 500_000) / 1_000_000
    }

    /// How strongly station `station`, with `demand`, draws travellers
    /// today: its daily trips, raised by any event there.
    func attraction(of demand: StationDemand, at station: StationID) -> Int64 {
        guard demandEvents != nil else { return demand.dailyTrips }
        return demand.dailyTrips * demandMultiplier(at: station)
    }

    // MARK: - Commands

    /// Turns weekly demand on or off (item 4 of the author's order): with
    /// it, each day's trips follow the reference's weekday factors and
    /// weekends its weekend hours. Passengers already waiting stay; the
    /// next release uses the new demand.
    public mutating func setWeeklyDemand(_ enabled: Bool) {
        guard enabled != weeklyDemand else { return }
        weeklyDemand = enabled
        passengerPlan = PassengerPlanCache()
    }

    /// Selects how future passenger releases choose a service. Groups
    /// already waiting or riding keep their chosen trip or journey.
    public mutating func setPassengerRoutingMode(_ mode: PassengerRoutingMode) {
        guard mode != passengerRoutingMode else { return }
        passengerRoutingMode = mode
        passengerRouteBalances = []
        passengerPlan = PassengerPlanCache()
    }

    /// Sets the demand of station `id`, or clears it with `nil` (G1a). Free.
    ///
    /// Passengers already waiting stay: a new demand changes only the trips
    /// released from now on (see ``advance(ticks:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``,
    ///   ``GameError/invalidStationDemand`` for daily trips outside
    ///   `0...StationDemand.maximumDailyTrips`, or
    ///   ``GameError/stationDemandFromLand`` while the land sets a managed
    ///   company's ridership (Phase 6b).
    public mutating func setStationDemand(_ id: StationID, to demand: StationDemand?) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard demand?.isValid ?? true else { throw .invalidStationDemand }
        guard !drawsDemandFromLand else { throw .stationDemandFromLand }
        passengerPlan = PassengerPlanCache()
        // Town growth (item 5) starts again from the demand set here: the
        // old start would pull it back, and its growth would be out of
        // range.
        townGrowth?.places.removeAll { $0.station == id }

        if let index = passengers.firstIndex(where: { $0.station == id }) {
            passengers[index].demand = demand
            if passengers[index].isEmpty {
                passengers.remove(at: index)
            }
        } else if demand != nil {
            var record = StationPassengers(station: id)
            record.demand = demand
            passengers.insert(record, at: passengers.firstIndex { $0.station > id } ?? passengers.count)
        }
    }

    // MARK: - Queries

    /// The demand of station `id`, or `nil` if it has none (or does not
    /// exist).
    public func stationDemand(of id: StationID) -> StationDemand? {
        passengerRecord(of: id)?.demand
    }

    /// The groups waiting at station `id`, first come first; empty if none.
    public func waitingPassengers(at id: StationID) -> [WaitingGroup] {
        passengerRecord(of: id)?.waiting ?? []
    }

    /// The conservation audit of station `id`: every passenger released
    /// there, and where they are now.
    public func passengerLedger(of id: StationID) -> PassengerLedger {
        guard let record = passengerRecord(of: id) else { return .empty }
        let waiting = passengers.reduce(Int64(0)) { sum, entry in
            entry.waiting.reduce(sum) { $0 + (($1.journey?.origin ?? entry.station) == id ? $1.count : 0) }
        }
        let riding = riders.reduce(Int64(0)) { sum, entry in
            entry.groups.reduce(sum) { $1.origin == id ? $0 + $1.count : $0 }
        }
        return record.ledger(waiting: waiting, riding: riding)
    }

    /// The trip from `origin` to `destination`: the lowest-numbered line
    /// calling at both, and the way from the origin's first call on it to
    /// the destination's first call (the reference's
    /// `metroFindStationIndexOnLine`, which takes the first index), or `nil`
    /// if no line calls at both, or they are the same station. Only same-line
    /// trips exist in G1: no transfers.
    public func passengerTrip(from origin: StationID, to destination: StationID) -> PassengerTrip? {
        guard origin != destination else { return nil }
        for line in lines {
            if let trip = Self.trip(on: line, from: origin, to: destination) { return trip }
        }
        return nil
    }

    /// The trips from `origin` to `destination` each day: the origin's
    /// daily trips shared among the stations it reaches (see
    /// ``passengerTrip(from:to:)``) that have demand, in proportion to their
    /// own daily trips, by largest remainder (ties to the lower station
    /// ID). 0 when the origin has no demand or does not reach the
    /// destination. With network routing a pair's trips also fall with its
    /// fastest route's generalized minutes (see ``PassengerCrowding``).
    public func dailyDemand(from origin: StationID, to destination: StationID) -> Int64 {
        dailyDemand(from: origin).first { $0.destination == destination }?.trips ?? 0
    }

    /// The trips from `origin` to `destination` in each hour of the day
    /// (24 entries, hour 0 first), which add up to
    /// ``dailyDemand(from:to:)``: the day's trips shared among the hours in
    /// proportion to ``StationDemand/dayShape`` × the origin's
    /// ``StationDemandKind/departureShape`` × the destination's
    /// ``StationDemandKind/arrivalShape``, by largest remainder (ties to the
    /// earlier hour). All zero without trips.
    public func hourlyDemand(from origin: StationID, to destination: StationID) -> [Int64] {
        hourlyDemand(of: dailyDemand(from: origin, to: destination), from: origin, to: destination)
    }

    /// The trips from `origin` to each station it reaches each day, as
    /// ``dailyDemand(from:to:)`` gives them one by one, worked out once for
    /// all of them: a station's ridership panel reads every pair, and asking
    /// pair by pair works the origin's whole share out again each time.
    /// Stations it sends no trips to are left out.
    public func dailyDemands(from origin: StationID) -> [StationID: Int64] {
        var trips: [StationID: Int64] = [:]
        for entry in dailyDemand(from: origin) {
            trips[entry.destination] = entry.trips
        }
        return trips
    }

    /// `trips` a day from `origin` to `destination` shared among the 24
    /// hours as ``hourlyDemand(from:to:)`` shares that pair's: for daily
    /// trips already read from ``dailyDemands(from:)``.
    public func hourlyDemand(of trips: Int64, from origin: StationID, to destination: StationID) -> [Int64] {
        guard trips > 0, let from = stationDemand(of: origin), let to = stationDemand(of: destination) else {
            return Array(repeating: 0, count: 24)
        }
        return Self.hourly(trips, from: from.kind, to: to.kind, weekend: isDemandWeekend)
    }

    // MARK: - Derivation

    private func passengerRecord(of id: StationID) -> StationPassengers? {
        passengers.first { $0.station == id }
    }

    /// The trip on `line` from `origin` to `destination`, if it calls at
    /// both: the way from the origin's first call to the destination's.
    static func trip(on line: ServiceLine, from origin: StationID, to destination: StationID) -> PassengerTrip? {
        guard origin != destination,
              let from = line.stops.firstIndex(of: origin),
              let to = line.stops.firstIndex(of: destination),
              // Decision 149: on a line with runs, only a way and stretch
              // some run goes.
              line.runsServe(from: from, to: to)
        else { return nil }
        return PassengerTrip(line: line.id, direction: to > from ? .outbound : .inbound)
    }

    /// Whether `group`, waiting at `station`, still has its trip: its line
    /// exists and still takes it that way.
    func isServed(_ group: WaitingGroup, at station: StationID,
                  checkingLeg check: ((PassengerJourneyLeg) -> Bool)? = nil) -> Bool {
        guard let line = line(id: group.line) else { return false }
        if let journey = group.journey {
            guard journey.leg.from == station,
                  journey.leg.line == group.line,
                  journey.leg.direction == group.direction,
                  journey.leg.to == group.destination else { return false }
            let pending = journey.legs.dropFirst(journey.current)
            return pending.allSatisfy(check ?? isServed) && zip(pending, pending.dropFirst()).allSatisfy(connects)
        }
        // A closed station neither sends nor receives passengers.
        guard allowsService(at: station), allowsService(at: group.destination) else { return false }
        return Self.trip(on: line, from: station, to: group.destination) == group.trip
    }

    /// Whether passengers may board, alight, change or arrive at station
    /// `id` (see ``StationOperationMode/allowsService``); `false` for an
    /// unknown station.
    func allowsService(at id: StationID) -> Bool {
        station(id: id)?.operationMode.allowsService ?? false
    }

    /// Whether new passengers may set out from station `id` (see
    /// ``StationOperationMode/allowsEntry``); `false` for an unknown
    /// station.
    func allowsEntry(at id: StationID) -> Bool {
        station(id: id)?.operationMode.allowsEntry ?? false
    }

    /// Everyone waiting at station `id` leaves it, counted as abandoned at
    /// their original station (the reference's
    /// `clearStationWaitingPassengers` when a station closes).
    mutating func abandonPassengers(waitingAt id: StationID) {
        guard let index = passengers.firstIndex(where: { $0.station == id }) else { return }
        var abandoned: [StationID: Int64] = [:]
        for group in passengers[index].abandonGroups(unless: { _ in false }) {
            abandoned[group.journey?.origin ?? id, default: 0] += group.count
        }
        for origin in abandoned.keys.sorted() {
            if let record = passengers.firstIndex(where: { $0.station == origin }) {
                passengers[record].abandoned += abandoned[origin]!
            }
        }
        passengers.removeAll { $0.isEmpty }
    }

    /// Whether `leg` is served (see ``isServed(_:)``), with whether its
    /// line's service runs from `memo` once worked out there: the journeys
    /// and headways it reads change only by a command, never within an
    /// advance.
    func isServed(_ leg: PassengerJourneyLeg, memo: inout DispatchMemo) -> Bool {
        let key = ScheduledService(line: leg.line, pattern: leg.pattern)
        let runs: Bool
        if let known = memo.scheduledServices[key] {
            runs = known
        } else {
            runs = isScheduled(leg.line, pattern: leg.pattern)
            memo.scheduledServices[key] = runs
        }
        return isServed(leg, scheduled: runs)
    }

    /// A planned ride can wait across the nightly closure, but must still
    /// have a physical journey and a service planned at some level.
    private func isServed(_ leg: PassengerJourneyLeg) -> Bool {
        isServed(leg, scheduled: isScheduled(leg.line, pattern: leg.pattern))
    }

    /// Whether line `id`'s service `pattern` has a journey and runs trains
    /// at some level of its window.
    private func isScheduled(_ id: LineID, pattern: Int?) -> Bool {
        guard let line = line(id: id), lineJourney(id, pattern: pattern) != nil else { return false }
        return scheduledLevels(of: line).contains { lineHeadway(id, at: $0, pattern: pattern) != nil }
    }

    /// ``isServed(_:)`` with `scheduled` whether the leg's service runs
    /// (see ``isScheduled(_:pattern:)``).
    private func isServed(_ leg: PassengerJourneyLeg, scheduled: Bool) -> Bool {
        guard allowsService(at: leg.from), allowsService(at: leg.to),
              let line = line(id: leg.line), scheduled
        else { return false }
        if line.isRing {
            let direction: RingDirection = leg.direction == .outbound ? .inner : .outer
            guard journey(of: line, service: 0, direction: direction) != nil else { return false }
            let calls = line.ringCalls(direction).map { line.stops[$0] }
            return calls.indices.contains { index in
                calls[index] == leg.from && calls.dropFirst(index + 1).contains(leg.to)
            }
        }
        // Decision 149: on a line with runs (no patterns, no station
        // twice), only a way and stretch some run goes.
        if line.hasRuns {
            guard leg.pattern == nil, let from = line.stops.firstIndex(of: leg.from), let to = line.stops.firstIndex(of: leg.to),
                  (from < to) == (leg.direction == .outbound)
            else { return false }
            return line.runsServe(from: from, to: to)
        }
        let service = (leg.pattern ?? -1) + 1
        guard (0..<line.serviceCount).contains(service) else { return false }
        let calls = line.calls(ofService: service).map { line.stops[$0] }
        let ordered = leg.direction == .outbound ? calls : Array(calls.reversed())
        return ordered.indices.contains { index in
            ordered[index] == leg.from && ordered.dropFirst(index + 1).contains(leg.to)
        }
    }

    private func scheduledLevels(of line: ServiceLine) -> [ServiceLevel] {
        var levels = serviceDay.bands.filter { line.window.contains(minuteOfDay: $0.start) }.map(\.level)
        if case .hours(let open, _) = line.window {
            levels.append(serviceDay.level(atMinuteOfDay: open))
        }
        return levels
    }

    /// The origin's daily trips to each station it reaches that has demand,
    /// by ascending station ID, leaving out those with no trips.
    func dailyDemand(from origin: StationID) -> [(destination: StationID, trips: Int64, trip: PassengerTrip)] {
        // The reference releases passengers only where they may enter
        // (`metroStationAllowsEntryForLine`), for destinations that are not
        // closed (`metroStationAllowsPassengerDestination`).
        guard let demand = stationDemand(of: origin), demand.dailyTrips > 0, allowsEntry(at: origin) else { return [] }
        var reached: [(destination: StationID, weight: Int64, trip: PassengerTrip)] = []
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        var fastest: [StationID: Int64] = [:]
        for record in passengers {
            guard let demand = record.demand, demand.dailyTrips > 0, allowsService(at: record.station) else { continue }
            let weight = attraction(of: demand, at: record.station)
            let trip: PassengerTrip?
            if passengerRoutingMode == .network {
                let choices = passengerRouteChoices(from: origin, to: record.station, graph: graph)
                if let leg = choices.first?.route.legs.first {
                    trip = PassengerTrip(line: leg.line, direction: leg.direction)
                    fastest[record.station] = choices.map(\.route.totalMinutes).min()
                } else {
                    trip = nil
                }
            } else {
                trip = passengerTrip(from: origin, to: record.station)
            }
            guard let trip else { continue }
            reached.append((record.station, weight, trip))
        }
        let shares = Self.apportion(trips(of: demand, at: origin), by: reached.map(\.weight))
        return zip(reached, shares).compactMap { reached, trips in
            var trips = keptTrips(trips, from: origin, to: reached.destination)
            if let minutes = fastest[reached.destination] {
                trips = PassengerCrowding.decayed(trips, minutes: minutes)
            }
            return trips > 0 ? (reached.destination, trips, reached.trip) : nil
        }
    }

    /// `trips` as the fare between the pair leaves them (G1c, ARCHITECTURE
    /// decision 36): times its ``FareRules/demandFactor(fare:)`` in
    /// thousandths, rounded half up, while fares change demand (the
    /// company is managed and the player has set fare rules); unchanged
    /// otherwise. The reference scales the pair's hourly rate by the same
    /// factor, so scaling the day scales every hour alike.
    func faredTrips(_ trips: Int64, from origin: StationID, to destination: StationID) -> Int64 {
        guard trips > 0, let factor = demandFactor(from: origin, to: destination) else { return trips }
        return (trips * factor + 500) / 1_000
    }

    /// `trips` shared among the 24 hours (see ``hourlyDemand(from:to:)``).
    static func hourly(_ trips: Int64, from origin: StationDemandKind, to destination: StationDemandKind,
                       weekend: Bool = false) -> [Int64] {
        let departures = origin.departureShape
        let arrivals = destination.arrivalShape
        let day = weekend ? StationDemand.weekendShape : StationDemand.dayShape
        let weights = (0..<24).map { day[$0] * departures[$0] * arrivals[$0] }
        return apportion(trips, by: weights)
    }

    /// `total` shared in proportion to `weights` (all non-negative) by the
    /// largest-remainder method: each share is the whole part of its
    /// quota, and the units left over go one each to the largest
    /// remainders, ties to the lower index. All zero when the weights add up
    /// to 0. The shares add up to `total` otherwise.
    ///
    /// `total` is at most ``StationDemand/maximumDailyTrips`` and every
    /// weight at most 1800 × 1503 × 1503, so `total × weight` stays well
    /// inside an `Int64`.
    static func apportion(_ total: Int64, by weights: [Int64]) -> [Int64] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return Array(repeating: 0, count: weights.count) }
        var shares = weights.map { total * $0 / sum }
        let remainders = weights.map { total * $0 % sum }
        let left = total - shares.reduce(0, +)
        let order = weights.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
        for index in order.prefix(Int(left)) {
            shares[index] += 1
        }
        return shares
    }

    // MARK: - Release

    /// Every trip that releases passengers: the flows, by ascending origin
    /// and then destination, and their hourly trips. Direct plans depend on
    /// demand and calls only; network plans also depend on physical service,
    /// its window and level. A network batch rebuilds when the service level
    /// changes and keeps the previous release's fractional OD remainders.
    struct PassengerPlan: Sendable {
        struct Choice: Sendable {
            let journey: PassengerJourney
            let weight: Int64
        }
        struct Flow: Sendable {
            /// The origin, looked up when the flow releases: a transfer may
            /// insert another station record while a batch is advancing.
            let origin: StationID
            /// Its index when the plan was built, retained for the G1 plan
            /// audit; release looks up `origin` again after transfer inserts.
            let record: Int
            let destination: StationID
            let trip: PassengerTrip
            let choices: [Choice]
        }

        let flows: [Flow]
        /// Each flow's trips in each hour of the day: 24 entries a flow, in
        /// the order of ``flows``.
        let hourly: [Int64]
    }

    /// The plan the world last worked out, if it is still current. Not game
    /// state: it is never saved, and two worlds compare equal whatever
    /// their caches hold.
    struct PassengerPlanCache: Equatable, Sendable {
        /// `nil` until worked out; then the plan, `nil` inside when no pair
        /// has trips.
        var plan: PassengerPlan??
        /// What a network plan was worked out from (see
        /// ``GameWorld/passengerPlanKey()``); `nil` for a direct plan,
        /// which every command that changes it forgets.
        var key: PassengerPlanKey?
        /// The game day the plan is for, with weekly demand; `nil` without,
        /// when every day is the same.
        var day: Int64?

        static func == (_: Self, _: Self) -> Bool {
            true
        }
    }

    /// What a network release plan reads: everything
    /// ``PassengerRouteGraph/init(world:)`` reads (the lines, stations with
    /// their operation modes, track network, traffic control, train lengths
    /// and each line's service level at the current minute), the stations'
    /// records and demands, the fare rules that scale demand, the demand
    /// day, weekly demand and demand events, and demand by distance and the
    /// outside connections (decision 137). A plan
    /// kept while its key is unchanged is exactly the plan worked out
    /// afresh (`PassengerPlanKeyTests`).
    struct PassengerPlanKey: Equatable, Sendable {
        let lines: [ServiceLine]
        let stations: [Station]
        let network: RailwayNetwork
        let trafficControl: Bool
        let trains: [TrainID]
        let trainLengths: [Int64]
        /// Each train's capacity and the service day set a path's daily
        /// capacity (see ``PassengerCrowding``).
        let trainCapacities: [Int64]
        let serviceDay: ServiceDay
        let levels: [ServiceLevel?]
        let records: [StationID]
        let demands: [StationDemand?]
        let economyMode: EconomyMode
        let fareRules: FareRules?
        let fareBaseline: Money
        /// Weekly demand and demand events (decisions 68, 69): a plan is for
        /// one day (see ``GameWorld/demandDay``).
        let day: Int64?
        let weeklyDemand: Bool
        let demandEvents: DemandEventSchedule?
        /// Decision 154: the holidays.
        let disruptions: Disruptions?
        /// Decision 137: each pair's share by its distance, and which
        /// stations are outside connections (their points are in
        /// ``stations``).
        let distanceDemand: Bool
        let outsideConnections: Bool
    }

    /// The key of the network plan ``makePassengerPlan()`` works out now.
    func passengerPlanKey() -> PassengerPlanKey {
        PassengerPlanKey(
            lines: lines, stations: stations, network: network, trafficControl: isTrafficControlEnabled,
            trains: trains.map(\.id), trainLengths: trains.map(\.length),
            trainCapacities: trains.map(\.capacity), serviceDay: serviceDay,
            levels: lines.map { serviceLevel(of: $0.id, at: clock.now) },
            records: passengers.map(\.station), demands: passengers.map(\.demand),
            economyMode: accounts.mode, fareRules: accounts.fareRules, fareBaseline: accounts.fareBaseline,
            day: demandDay, weeklyDemand: weeklyDemand, demandEvents: demandEvents, disruptions: disruptions,
            distanceDemand: distanceDemand, outsideConnections: outsideConnections
        )
    }

    /// Worked out from scratch (see ``dailyDemand(from:to:)`` and
    /// ``hourlyDemand(from:to:)``, which it agrees with), looking each
    /// line's first calls up once.
    func makePassengerPlan() -> PassengerPlan? {
        var memo = PassengerRouteMemo()
        return makePassengerPlan(memo: &memo)
    }

    /// The same, reusing and extending `memo`'s route choices in a network
    /// game.
    func makePassengerPlan(memo: inout PassengerRouteMemo) -> PassengerPlan? {
        if passengerRoutingMode == .network { return makeNetworkPassengerPlan(memo: &memo) }
        let firstCalls = lines.map { line in
            var calls: [StationID: Int] = [:]
            for (index, stop) in line.stops.enumerated() where calls[stop] == nil {
                calls[stop] = index
            }
            return calls
        }
        func trip(from origin: StationID, to destination: StationID) -> PassengerTrip? {
            guard origin != destination else { return nil }
            for (index, calls) in firstCalls.enumerated() {
                if let from = calls[origin], let to = calls[destination] {
                    return PassengerTrip(line: lines[index].id, direction: to > from ? .outbound : .inbound)
                }
            }
            return nil
        }
        let drawing = passengers.filter { ($0.demand?.dailyTrips ?? 0) > 0 && allowsService(at: $0.station) }
        var flows: [PassengerPlan.Flow] = []
        var hourly: [Int64] = []
        for record in passengers {
            guard let origin = record.demand, origin.dailyTrips > 0, allowsEntry(at: record.station) else { continue }
            let reached = drawing.compactMap { other in trip(from: record.station, to: other.station).map { (other, $0) } }
            let shares = Self.apportion(trips(of: origin, at: record.station),
                                        by: reached.map { attraction(of: $0.0.demand!, at: $0.0.station) })
            for ((destination, trip), shared) in zip(reached, shares) {
                let trips = keptTrips(shared, from: record.station, to: destination.station)
                guard trips > 0 else { continue }
                flows.append(PassengerPlan.Flow(origin: record.station,
                    record: passengers.firstIndex(where: { $0.station == record.station })!,
                    destination: destination.station, trip: trip, choices: []))
                hourly += Self.hourly(trips, from: origin.kind, to: destination.demand!.kind, weekend: isDemandWeekend)
            }
        }
        return flows.isEmpty ? nil : PassengerPlan(flows: flows, hourly: hourly)
    }

    /// The network plan. A pair's daily trips fall with its fastest
    /// route's generalized minutes, and its choices' weights follow their
    /// crowded costs under the plan's own daily loads (see
    /// ``PassengerCrowding``).
    private func makeNetworkPassengerPlan(memo: inout PassengerRouteMemo) -> PassengerPlan? {
        let drawing = passengers.filter { ($0.demand?.dailyTrips ?? 0) > 0 && allowsService(at: $0.station) }
        let graph = PassengerRouteGraph(world: self)
        memo.use(graph)
        struct Draft {
            let origin: StationID
            let record: Int
            let destination: StationPassengers
            let kind: StationDemandKind
            let options: [PassengerRouteChoice]
            let journeys: [PassengerJourney]
            let trips: Int64
        }
        var drafts: [Draft] = []
        for (index, record) in passengers.enumerated() {
            guard let origin = record.demand, origin.dailyTrips > 0, allowsEntry(at: record.station) else { continue }
            let reached = drawing.compactMap { other -> (StationPassengers, [PassengerRouteChoice], [PassengerJourney])? in
                let pair = PassengerRouteMemo.Pair(origin: record.station, destination: other.station)
                let found = memo.choices[pair] ?? passengerRouteChoices(from: record.station, to: other.station, graph: graph)
                memo.choices[pair] = found
                var options: [PassengerRouteChoice] = []
                var journeys: [PassengerJourney] = []
                for choice in found {
                    guard let journey = PassengerJourney(origin: record.station, route: choice.route) else { continue }
                    options.append(choice)
                    journeys.append(journey)
                }
                return options.isEmpty ? nil : (other, options, journeys)
            }
            let shares = Self.apportion(trips(of: origin, at: record.station),
                                        by: reached.map { attraction(of: $0.0.demand!, at: $0.0.station) })
            for ((destination, options, journeys), shared) in zip(reached, shares) {
                let fared = keptTrips(shared, from: record.station, to: destination.station)
                let trips = PassengerCrowding.decayed(fared, minutes: options.map(\.route.totalMinutes).min()!)
                guard trips > 0 else { continue }
                drafts.append(Draft(origin: record.station, record: index, destination: destination,
                                    kind: origin.kind, options: options, journeys: journeys, trips: trips))
            }
        }
        // The plan's own daily loads, on the uncrowded weights.
        var used: [PassengerRouteGraph.Segment: Int64] = [:]
        for draft in drafts {
            let shares = Self.apportion(draft.trips, by: draft.options.map(\.weight))
            for (option, share) in zip(draft.options, shares) where share > 0 {
                for segment in graph.segments(of: option.route) ?? [] {
                    used[segment, default: 0] += share
                }
            }
        }
        var flows: [PassengerPlan.Flow] = []
        var hourly: [Int64] = []
        for draft in drafts {
            let weights = PassengerCrowding.crowdedWeights(draft.options, used: used, on: graph)
            let choices = zip(draft.journeys, weights).map { PassengerPlan.Choice(journey: $0.0, weight: $0.1) }
            let first = choices[0].journey.leg
            flows.append(PassengerPlan.Flow(origin: draft.origin, record: draft.record,
                destination: draft.destination.station,
                trip: PassengerTrip(line: first.line, direction: first.direction), choices: choices))
            hourly += Self.hourly(draft.trips, from: draft.kind, to: draft.destination.demand!.kind, weekend: isDemandWeekend)
        }
        return flows.isEmpty ? nil : PassengerPlan(flows: flows, hourly: hourly)
    }

    /// One call's release: the plan, and each flow's remainder, loaded from
    /// the records at the start of the call and kept at its end.
    struct PassengerRelease {
        let plan: PassengerPlan
        var remainders: [Int64]
    }

    /// The release for a call of ``advance(ticks:)``, or `nil` when no pair
    /// has trips; works the plan out first if no current one is kept.
    mutating func passengerRelease() -> PassengerRelease? {
        // With weekly demand a plan is for one day.
        if passengerPlan.plan != nil, passengerPlan.day != demandDay {
            passengerPlan = PassengerPlanCache()
        }
        if passengerPlan.plan == nil {
            passengerPlan.key = passengerRoutingMode == .network ? passengerPlanKey() : nil
            passengerPlan.day = demandDay
            passengerPlan.plan = .some(makePassengerPlan(memo: &passengerRouteMemo))
        }
        guard case .some(.some(let plan)) = passengerPlan.plan else { return nil }
        var remainders = Array(repeating: Int64(0), count: plan.flows.count)
        // A record's flows are together, by ascending destination, like its
        // remainders: one walk through both.
        var index = 0
        while index < plan.flows.count {
            let origin = plan.flows[index].origin
            let kept = passengers.first { $0.station == origin }!.remainders
            var next = 0
            while index < plan.flows.count, plan.flows[index].origin == origin {
                let destination = plan.flows[index].destination
                while next < kept.count, kept[next].destination < destination {
                    next += 1
                }
                if next < kept.count, kept[next].destination == destination {
                    remainders[index] = kept[next].value
                }
                index += 1
            }
        }
        return PassengerRelease(plan: plan, remainders: remainders)
    }

    /// The release phase of the basic step from `now` to the next minute:
    /// every pair adds this minute's share of its trips, interpolated
    /// between this hour's and the next hour's (the reference's
    /// `(1 − f)·R_h + f·R_{h+1}` per hour with `f` the minute's part of the
    /// hour, divided by 60), to its remainder; each whole passenger in it is
    /// released at the origin, pair by pair in ``PassengerPlan/flows``
    /// order (see ``StationPassengers/release(_:to:along:at:)``).
    ///
    /// Over any 1440 minutes in a row a pair releases exactly its daily
    /// trips: each hour's trips are counted `1830 + 1770 = 3600` times, in
    /// its own hour and the one before, so the remainder comes back to what
    /// it was.
    mutating func releasePassengers(at now: GameTime, _ release: inout PassengerRelease) {
        let minute = now.minuteOfDay
        let hour = minute / 60
        let next = (hour + 1) % 24
        let into = Int64(minute % 60)
        let plan = release.plan
        for index in plan.flows.indices {
            let share = (60 - into) * plan.hourly[24 * index + hour] + into * plan.hourly[24 * index + next]
            let total = release.remainders[index] + share
            release.remainders[index] = total % Self.releaseUnit
            let count = total / Self.releaseUnit
            if count > 0 {
                let flow = plan.flows[index]
                guard let record = passengers.firstIndex(where: { $0.station == flow.origin }) else { continue }
                if flow.choices.isEmpty {
                    passengers[record].release(count, to: flow.destination, along: flow.trip, at: now)
                } else {
                    let shares = allocateRouteRelease(count, from: flow.origin, flow: flow)
                    for (choice, share) in zip(flow.choices, shares) where share > 0 {
                        passengers[record].release(share, along: choice.journey, at: now)
                    }
                }
            }
        }
    }

    /// Weighted fair allocation with a saved fractional balance. It assigns
    /// this minute's whole passengers one at a time, so a succession of
    /// one-passenger releases can still use every route in proportion.
    private mutating func allocateRouteRelease(_ count: Int64, from origin: StationID,
                                                flow: PassengerPlan.Flow) -> [Int64] {
        let choices = flow.choices
        let journeys = choices.map(\.journey)
        let weights = choices.map(\.weight)
        let index = passengerRouteBalances.firstIndex { $0.origin == origin && $0.destination == flow.destination }
        var balance = index.map { passengerRouteBalances[$0] }
        if balance?.journeys != journeys || balance?.weights != weights {
            balance = PassengerRouteBalance(origin: origin, destination: flow.destination,
                journeys: journeys, weights: weights, balances: Array(repeating: 0, count: choices.count))
        }
        var state = balance!
        let shares = state.allocate(count)
        if let index { passengerRouteBalances[index] = state }
        else {
            let insert = passengerRouteBalances.firstIndex {
                ($0.origin, $0.destination) > (origin, flow.destination)
            } ?? passengerRouteBalances.count
            passengerRouteBalances.insert(state, at: insert)
        }
        return shares
    }

    /// Keeps the remainders `release` ended the call with, record by record.
    mutating func keepRemainders(of release: PassengerRelease) {
        var index = 0
        let flows = release.plan.flows
        while index < flows.count {
            let origin = flows[index].origin
            var updates: [DemandRemainder] = []
            while index < flows.count, flows[index].origin == origin {
                updates.append(DemandRemainder(destination: flows[index].destination, value: release.remainders[index]))
                index += 1
            }
            if let record = passengers.firstIndex(where: { $0.station == origin }) {
                passengers[record].updateRemainders(updates)
            }
        }
    }

    /// After a line's stops change or it is removed, or anything else its
    /// journey or the service it can run depends on (its track, platforms,
    /// performance, route preferences and trains): every group waiting for
    /// a trip no line takes that way any more leaves its station (see
    /// ``PassengerLedger/abandoned``), and every rider whose train no
    /// longer calls at their destination before it turns round leaves the
    /// train (see ``abandonStrandedRiders()``), so the world still loads.
    mutating func abandonUnservedPassengers() {
        passengerPlan = PassengerPlanCache()
        abandonStrandedRiders()
        // A pair's balanced routes must still be ridable one after another,
        // as the save checks; the next release plans the pair anew.
        let walkable = self
        passengerRouteBalances.removeAll { balance in
            !balance.journeys.allSatisfy { zip($0.legs, $0.legs.dropFirst()).allSatisfy(walkable.connects) }
        }
        let world = self
        let valid = servedWaitingLegs()
        var abandoned: [StationID: Int64] = [:]
        for index in passengers.indices {
            let station = passengers[index].station
            for group in passengers[index].abandonGroups(unless: { world.isServed($0, at: station, checkingLeg: { valid.contains($0) }) }) {
                abandoned[group.journey?.origin ?? station, default: 0] += group.count
            }
        }
        for origin in abandoned.keys.sorted() {
            if let index = passengers.firstIndex(where: { $0.station == origin }) {
                passengers[index].abandoned += abandoned[origin]!
            }
        }
        passengers.removeAll { $0.isEmpty }
    }

    /// Validate each distinct planned leg once, even with a full station's
    /// thousands of minute groups. Legacy direct queues need no graph work.
    private func servedWaitingLegs() -> Set<PassengerJourneyLeg> {
        let pending = Set(passengers.flatMap(\.waiting).flatMap { group in
            group.journey.map { Array($0.legs.dropFirst($0.current)) } ?? []
        })
        return Set(pending.filter(isServed))
    }

    mutating func reindexPassengerJourneys(on line: LineID, removing pattern: Int) {
        var abandoned: [StationID: Int64] = [:]
        for index in passengers.indices {
            for group in passengers[index].reindexJourneys(on: line, removing: pattern) {
                abandoned[group.journey!.origin, default: 0] += group.count
            }
        }
        for index in riders.indices {
            riders[index].groups = riders[index].groups.compactMap { group in
                guard let journey = group.journey else { return group }
                guard let updated = journey.reindexed(on: line, removing: pattern, riding: true) else {
                    abandoned[group.origin, default: 0] += group.count
                    return nil
                }
                return RidingGroup(origin: group.origin, destination: group.destination,
                    count: group.count, journey: updated)
            }
        }
        riders.removeAll { $0.groups.isEmpty }
        for origin in abandoned.keys.sorted() {
            let index = passengers.firstIndex { $0.station == origin }!
            passengers[index].abandoned += abandoned[origin]!
        }
        passengerRouteBalances.removeAll { balance in
            balance.journeys.contains { journey in
                journey.legs.contains { $0.line == line && ($0.pattern ?? -1) >= pattern }
            }
        }
    }

    // MARK: - Validation

    /// Why the passengers break a G1a rule, or `nil`. ``StationPassengers``'
    /// decoder has checked each record on its own.
    ///
    /// Records are by ascending station, each of an existing station; every
    /// group waits for an existing line that takes its trip that way, and
    /// was released before now; every remainder is for another
    /// existing station.
    func passengerProblem() -> String? {
        guard zip(passengers, passengers.dropFirst()).allSatisfy({ $0.station < $1.station }) else {
            return "Passenger records must be listed once each, by ascending station."
        }
        let valid = servedWaitingLegs()
        for record in passengers {
            let id = record.station.rawValue
            guard station(id: record.station) != nil else { return "Passengers wait at station \(id), which does not exist." }
            for group in record.waiting {
                guard isServed(group, at: record.station, checkingLeg: { valid.contains($0) }) else {
                    return "Passengers at station \(id) wait for a trip no line takes that way."
                }
                if let journey = group.journey,
                   !passengers.contains(where: { $0.station == journey.origin && $0.released > 0 }) {
                    return "A transfer group at station \(id) has no releasing origin."
                }
                // The step from minute T releases at T and ends at T + 1.
                guard group.since < clock.now else { return "Passengers at station \(id) were released at or after the current minute." }
            }
            for remainder in record.remainders {
                guard remainder.destination != record.station, station(id: remainder.destination) != nil else {
                    return "Station \(id) keeps a remainder for a station it cannot send passengers to."
                }
            }
        }
        guard zip(passengerRouteBalances, passengerRouteBalances.dropFirst()).allSatisfy({
            ($0.origin, $0.destination) < ($1.origin, $1.destination)
        }) else { return "Route balances must be listed once per OD pair, in order." }
        for balance in passengerRouteBalances {
            guard passengerRoutingMode == .network,
                  balance.origin != balance.destination,
                  station(id: balance.origin) != nil, station(id: balance.destination) != nil,
                  (1...3).contains(balance.journeys.count),
                  Set(balance.journeys).count == balance.journeys.count,
                  balance.weights.count == balance.journeys.count,
                  balance.balances.count == balance.journeys.count,
                  balance.weights.allSatisfy({ (1...10_000).contains($0) }),
                  balance.journeys.allSatisfy({ $0.current == 0 && $0.origin == balance.origin && $0.destination == balance.destination }),
                  // Each next ride starts where the last ends, or a walk
                  // away, as for those riding and waiting.
                  balance.journeys.allSatisfy({ zip($0.legs, $0.legs.dropFirst()).allSatisfy(connects) })
            else { return "An OD route balance is invalid." }
            let sum = balance.weights.reduce(Int64(0), +)
            guard balance.balances.allSatisfy({ (-sum...sum).contains($0) }),
                  balance.balances.reduce(0, +) == 0 else { return "An OD route balance is invalid." }
        }
        return nil
    }
}
