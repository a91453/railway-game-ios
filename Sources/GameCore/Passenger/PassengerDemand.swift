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
// reads stations, the lines' stops and the clock, nothing of the railway's
// physical layer, and changes nothing but the passengers.

extension GameWorld {
    /// A passenger's release is counted in 1/3600ths: a trip rate per hour,
    /// spread over the 60 minutes of the hour.
    static let releaseUnit: Int64 = 3_600

    // MARK: - Commands

    /// Sets the demand of station `id`, or clears it with `nil` (G1a). Free.
    ///
    /// Passengers already waiting stay: a new demand changes only the trips
    /// released from now on (see ``advance(ticks:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)`` or
    ///   ``GameError/invalidStationDemand`` for daily trips outside
    ///   `0...StationDemand.maximumDailyTrips`.
    public mutating func setStationDemand(_ id: StationID, to demand: StationDemand?) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard demand?.isValid ?? true else { throw .invalidStationDemand }
        passengerPlan = PassengerPlanCache()

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
        passengerRecord(of: id)?.ledger ?? .empty
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
    /// destination.
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
        let trips = dailyDemand(from: origin, to: destination)
        guard trips > 0, let from = stationDemand(of: origin), let to = stationDemand(of: destination) else {
            return Array(repeating: 0, count: 24)
        }
        return Self.hourly(trips, from: from.kind, to: to.kind)
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
              let to = line.stops.firstIndex(of: destination)
        else { return nil }
        return PassengerTrip(line: line.id, direction: to > from ? .outbound : .inbound)
    }

    /// Whether `group`, waiting at `station`, still has its trip: its line
    /// exists and still takes it that way.
    func isServed(_ group: WaitingGroup, at station: StationID) -> Bool {
        guard let line = line(id: group.line) else { return false }
        return Self.trip(on: line, from: station, to: group.destination) == group.trip
    }

    /// The origin's daily trips to each station it reaches that has demand,
    /// by ascending station ID, leaving out those with no trips.
    func dailyDemand(from origin: StationID) -> [(destination: StationID, trips: Int64, trip: PassengerTrip)] {
        guard let demand = stationDemand(of: origin), demand.dailyTrips > 0 else { return [] }
        var reached: [(destination: StationID, weight: Int64, trip: PassengerTrip)] = []
        for record in passengers {
            guard let weight = record.demand?.dailyTrips, weight > 0,
                  let trip = passengerTrip(from: origin, to: record.station)
            else { continue }
            reached.append((record.station, weight, trip))
        }
        let shares = Self.apportion(demand.dailyTrips, by: reached.map(\.weight))
        return zip(reached, shares).compactMap { reached, trips in
            trips > 0 ? (reached.destination, trips, reached.trip) : nil
        }
    }

    /// `trips` shared among the 24 hours (see ``hourlyDemand(from:to:)``).
    static func hourly(_ trips: Int64, from origin: StationDemandKind, to destination: StationDemandKind) -> [Int64] {
        let departures = origin.departureShape
        let arrivals = destination.arrivalShape
        let weights = (0..<24).map { StationDemand.dayShape[$0] * departures[$0] * arrivals[$0] }
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
    /// and then destination (the order passengers released in the same
    /// minute join their queues), and their hourly trips. Derived from the
    /// demands and the lines' stops only, so it is kept between calls of
    /// ``advance(ticks:)`` (see ``PassengerPlanCache``) and worked out again
    /// after a command changes either.
    struct PassengerPlan: Sendable {
        struct Flow: Sendable {
            /// The origin's index in ``GameWorld/passengers``: only
            /// ``setStationDemand(_:to:)`` inserts or removes records, and
            /// it forgets the plan.
            let record: Int
            let destination: StationID
            let trip: PassengerTrip
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

        static func == (_: Self, _: Self) -> Bool {
            true
        }
    }

    /// Worked out from scratch (see ``dailyDemand(from:to:)`` and
    /// ``hourlyDemand(from:to:)``, which it agrees with), looking each
    /// line's first calls up once.
    func makePassengerPlan() -> PassengerPlan? {
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
        let drawing = passengers.filter { ($0.demand?.dailyTrips ?? 0) > 0 }
        var flows: [PassengerPlan.Flow] = []
        var hourly: [Int64] = []
        for (index, record) in passengers.enumerated() {
            guard let origin = record.demand, origin.dailyTrips > 0 else { continue }
            let reached = drawing.compactMap { other in trip(from: record.station, to: other.station).map { (other, $0) } }
            let shares = Self.apportion(origin.dailyTrips, by: reached.map { $0.0.demand!.dailyTrips })
            for ((destination, trip), trips) in zip(reached, shares) where trips > 0 {
                flows.append(PassengerPlan.Flow(record: index, destination: destination.station, trip: trip))
                hourly += Self.hourly(trips, from: origin.kind, to: destination.demand!.kind)
            }
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
        if passengerPlan.plan == nil {
            passengerPlan.plan = .some(makePassengerPlan())
        }
        guard case .some(.some(let plan)) = passengerPlan.plan else { return nil }
        var remainders = Array(repeating: Int64(0), count: plan.flows.count)
        // A record's flows are together, by ascending destination, like its
        // remainders: one walk through both.
        var index = 0
        while index < plan.flows.count {
            let record = plan.flows[index].record
            let kept = passengers[record].remainders
            var next = 0
            while index < plan.flows.count, plan.flows[index].record == record {
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
                passengers[flow.record].release(count, to: flow.destination, along: flow.trip, at: now)
            }
        }
    }

    /// Keeps the remainders `release` ended the call with, record by record.
    mutating func keepRemainders(of release: PassengerRelease) {
        var index = 0
        let flows = release.plan.flows
        while index < flows.count {
            let record = flows[index].record
            var updates: [DemandRemainder] = []
            while index < flows.count, flows[index].record == record {
                updates.append(DemandRemainder(destination: flows[index].destination, value: release.remainders[index]))
                index += 1
            }
            passengers[record].updateRemainders(updates)
        }
    }

    /// After a line's stops change or it is removed: every group waiting
    /// for a trip no line takes that way any more leaves its station (see
    /// ``PassengerLedger/abandoned``).
    mutating func abandonUnservedPassengers() {
        passengerPlan = PassengerPlanCache()
        let world = self
        for index in passengers.indices {
            let station = passengers[index].station
            passengers[index].abandonGroups { world.isServed($0, at: station) }
        }
    }

    // MARK: - Validation

    /// Why the passengers break a G1a rule, or `nil`. ``StationPassengers``'
    /// decoder has checked each record on its own.
    ///
    /// Records are by ascending station, each of an existing station; every
    /// group waits for an existing line that takes its trip that way, and
    /// was released no later than now; every remainder is for another
    /// existing station.
    func passengerProblem() -> String? {
        guard zip(passengers, passengers.dropFirst()).allSatisfy({ $0.station < $1.station }) else {
            return "Passenger records must be listed once each, by ascending station."
        }
        for record in passengers {
            let id = record.station.rawValue
            guard station(id: record.station) != nil else { return "Passengers wait at station \(id), which does not exist." }
            for group in record.waiting {
                guard isServed(group, at: record.station) else {
                    return "Passengers at station \(id) wait for a trip no line takes that way."
                }
                guard group.since <= clock.now else { return "Passengers at station \(id) were released after the current minute." }
            }
            for remainder in record.remainders {
                guard remainder.destination != record.station, station(id: remainder.destination) != nil else {
                    return "Station \(id) keeps a remainder for a station it cannot send passengers to."
                }
            }
        }
        return nil
    }
}
