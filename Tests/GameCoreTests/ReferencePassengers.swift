import Foundation
import GameCore

/// G1a (ARCHITECTURE decision 34) written a second time for
/// ``ReferenceWorld``, straight from the rules, and differently on purpose:
///
/// - the hourly shapes are worked out from the reference's Gaussian formula
///   with Foundation's `exp`, not read from tables;
/// - trips are looked up again every minute, with no plan kept for a call;
/// - largest remainders are handed out by picking the largest one left, one
///   unit at a time, not by sorting;
/// - a minute's share is `60·R_h + m·(R_{h+1} − R_h)`, not `(60 − m)·R_h +
///   m·R_{h+1}`;
/// - the queue is a list of groups per station and how many wait is summed
///   whenever it is needed; the counts are dictionaries by station.
///
/// G1b (decision 35) likewise:
///
/// - Stage W2b: who gets off and who gets on are worked out in one pass
///   over the stop, and a full train's refused are counted the moment it
///   leaves, not after the step's departures;
/// - riders are dictionaries of train, origin and destination;
/// - the next group to board is picked by scanning for the farthest call,
///   the earliest in the queue among equals, one group at a time, not by
///   sorting;
/// - the capacity is `cars × 320 × 11 / 10`, the rated load and the
///   reference's 1.1 as a fraction.
struct ReferencePassengers: Equatable {
    struct Demand: Equatable {
        var kind: StationDemandKind
        var trips: Int64
    }

    struct Group: Equatable {
        var line: Int
        var outbound: Bool
        var destination: Int
        var since: Int64
        var count: Int64
    }

    var demand: [Int: Demand] = [:]
    var queue: [Int: [Group]] = [:]
    var released: [Int: Int64] = [:]
    var overflowed: [Int: Int64] = [:]
    var abandoned: [Int: Int64] = [:]
    /// By origin, then destination: the 3600ths not yet released; no zeros.
    var fraction: [Int: [Int: Int64]] = [:]
    /// By train, origin and destination: who rides; no zeros, no empties.
    var riders: [Int: [Int: [Int: Int64]]] = [:]
    var arrived: [Int: Int64] = [:]
    var refused: [Int: Int64] = [:]

    static let capacity: Int64 = 4_000
}

extension ReferenceWorld {
    // MARK: - Shapes

    /// The reference's normalised curve in thousandths: `Math.round(1000 ×
    /// clamp(v × 24 / Σv, 0, 11))`.
    static func shape(_ curve: (Double) -> Double) -> [Int64] {
        let values = (0..<24).map { curve(Double($0)) }
        let total = values.reduce(0, +)
        return values.map { Int64((min(11, max(0, $0 * 24 / total)) * 1000 + 0.5).rounded(.down)) }
    }

    static func bell(_ hour: Double, _ mean: Double, _ spread: Double) -> Double {
        exp(-0.5 * ((hour - mean) / spread) * ((hour - mean) / spread))
    }

    static func departures(_ kind: StationDemandKind) -> [Int64] {
        switch kind {
        case .residential: shape { 1 + bell($0, 8, 1.15) * 0.6 }
        case .office: shape { 1 + bell($0, 18, 1.15) * 0.6 }
        case .shopping: shape { 1 + bell($0, 14, 2.4) * 0.42 + bell($0, 19, 1.8) * 0.5 }
        case .scenic: shape { 1 + bell($0, 16, 2.1) * 0.75 }
        // Not the reference's: decision 91's school day, the office's curve
        // with pupils leaving at 16.
        case .civic: shape { 1 + bell($0, 16, 1.15) * 0.6 }
        }
    }

    static func arrivals(_ kind: StationDemandKind) -> [Int64] {
        switch kind {
        case .residential: shape { 1 + bell($0, 18, 1.15) * 0.6 }
        case .office: shape { 1 + bell($0, 8, 1.15) * 0.6 }
        case .shopping: shape { 1 + bell($0, 13, 2.4) * 0.42 + bell($0, 18, 1.8) * 0.5 }
        case .scenic: shape { 1 + bell($0, 11, 2.1) * 0.75 }
        // Decision 91's school day: pupils arrive at 7.
        case .civic: shape { 1 + bell($0, 7, 1.15) * 0.6 }
        }
    }

    static let departureShapes = Dictionary(uniqueKeysWithValues: StationDemandKind.allCases.map { ($0, departures($0)) })
    static let arrivalShapes = Dictionary(uniqueKeysWithValues: StationDemandKind.allCases.map { ($0, arrivals($0)) })

    /// `PARAMS.PEAK_FACTOR` in thousandths.
    static func peakFactor(_ hour: Int) -> Int64 {
        switch hour {
        case 8, 18: 1800
        case 7, 9, 16, 17, 19: 1500
        case 6...22: 600 + 20 * Int64(hour)
        default: 100
        }
    }

    // MARK: - Trips

    static func largestRemainder(_ total: Int64, _ weights: [Int64]) -> [Int64] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { total * $0 / sum }
        var fractions = weights.map { total * $0 % sum }
        var left = total - shares.reduce(0, +)
        while left > 0 {
            var best = 0
            for index in fractions.indices where fractions[index] > fractions[best] {
                best = index
            }
            shares[best] += 1
            fractions[best] = -1
            left -= 1
        }
        return shares
    }

    /// The lowest line calling at both, and whether the destination's first
    /// call comes after the origin's.
    func passengerTrip(from origin: Int, to destination: Int) -> (line: Int, outbound: Bool)? {
        Self.trip(on: lines.sorted(by: { $0.id < $1.id }), from: origin, to: destination)
    }

    static func trip(on lines: [Line], from origin: Int, to destination: Int) -> (line: Int, outbound: Bool)? {
        guard origin != destination else { return nil }
        for line in lines {
            if let outbound = outbound(line, from: origin, to: destination) { return (line.id, outbound) }
        }
        return nil
    }

    static func outbound(_ line: Line, from origin: Int, to destination: Int) -> Bool? {
        var from: Int?
        var to: Int?
        for (index, stop) in line.stops.enumerated() {
            if from == nil, stop.rawValue == origin { from = index }
            if to == nil, stop.rawValue == destination { to = index }
        }
        guard origin != destination, let from, let to else { return nil }
        return to > from
    }

    /// The origin's day shared among the stations it reaches that have
    /// trips of their own, by ascending station.
    func dailyTrips(from origin: Int) -> [(destination: Int, trips: Int64)] {
        guard let own = passengers.demand[origin] else { return [] }
        let ordered = lines.sorted(by: { $0.id < $1.id })
        let reached = passengers.demand.keys.sorted().filter { passengers.demand[$0]!.trips > 0 && Self.trip(on: ordered, from: origin, to: $0) != nil }
        // Decision 36: the fare scales each pair's day once fares are set.
        return zip(reached, Self.largestRemainder(own.trips, reached.map { passengers.demand[$0]!.trips })).map { destination, trips in
            guard trips > 0, let factor = demandFactor(from: origin, to: destination) else { return (destination, trips) }
            return (destination, (trips * factor + 500) / 1_000)
        }
    }

    func dailyTrips(from origin: Int, to destination: Int) -> Int64 {
        dailyTrips(from: origin).first { $0.destination == destination }?.trips ?? 0
    }

    func hourlyTrips(_ trips: Int64, from origin: StationDemandKind, to destination: StationDemandKind) -> [Int64] {
        let out = Self.departureShapes[origin]!
        let into = Self.arrivalShapes[destination]!
        return Self.largestRemainder(trips, (0..<24).map { Self.peakFactor($0) * out[$0] * into[$0] })
    }

    func hourlyTrips(from origin: Int, to destination: Int) -> [Int64] {
        let trips = dailyTrips(from: origin, to: destination)
        guard trips > 0 else { return Array(repeating: 0, count: 24) }
        return hourlyTrips(trips, from: passengers.demand[origin]!.kind, to: passengers.demand[destination]!.kind)
    }

    // MARK: - Commands

    mutating func setStationDemand(_ id: StationID, _ demand: StationDemand?) -> GameError? {
        guard stations.contains(where: { $0.id == id.rawValue }) else { return .unknownStation(id) }
        if let demand, demand.dailyTrips < 0 || demand.dailyTrips > 1_000_000 { return .invalidStationDemand }
        passengers.demand[id.rawValue] = demand.map { ReferencePassengers.Demand(kind: $0.kind, trips: $0.dailyTrips) }
        return nil
    }

    /// Every minute's release, before the trains (decision 34).
    mutating func releasePassengers() {
        var day = minutes % 1440
        if day < 0 { day += 1440 }
        let hour = Int(day / 60)
        let into = day % 60
        let origins = passengers.demand.keys.sorted()
        var plan: [(origin: Int, destination: Int, trip: (line: Int, outbound: Bool), share: Int64)] = []
        for origin in origins {
            for (destination, trips) in dailyTrips(from: origin) where trips > 0 {
                let hourly = hourlyTrips(trips, from: passengers.demand[origin]!.kind, to: passengers.demand[destination]!.kind)
                let share = 60 * hourly[hour] + into * (hourly[(hour + 1) % 24] - hourly[hour])
                plan.append((origin, destination, passengerTrip(from: origin, to: destination)!, share))
            }
        }
        for flow in plan {
            let total = (passengers.fraction[flow.origin]?[flow.destination] ?? 0) + flow.share
            let whole = total / 3600
            passengers.fraction[flow.origin, default: [:]][flow.destination] = total % 3600 == 0 ? nil : total % 3600
            if passengers.fraction[flow.origin]?.isEmpty == true { passengers.fraction[flow.origin] = nil }
            guard whole > 0 else { continue }
            let waiting = (passengers.queue[flow.origin] ?? []).reduce(Int64(0)) { $0 + $1.count }
            let room = max(0, ReferencePassengers.capacity - waiting)
            let admitted = min(whole, room)
            if admitted > 0 {
                passengers.queue[flow.origin, default: []].append(ReferencePassengers.Group(
                    line: flow.trip.line, outbound: flow.trip.outbound, destination: flow.destination, since: minutes, count: admitted
                ))
            }
            passengers.released[flow.origin, default: 0] += whole
            passengers.overflowed[flow.origin, default: 0] += whole - admitted
        }
    }

    /// After a line changes or goes: groups whose line no longer takes
    /// them that way leave.
    mutating func abandonStrandedPassengers() {
        for (station, groups) in passengers.queue {
            var kept: [ReferencePassengers.Group] = []
            for group in groups {
                if let line = lines.first(where: { $0.id == group.line }),
                   Self.outbound(line, from: station, to: group.destination) == group.outbound {
                    kept.append(group)
                } else {
                    passengers.abandoned[station, default: 0] += group.count
                }
            }
            passengers.queue[station] = kept.isEmpty ? nil : kept
        }
    }

    // MARK: - Boarding

    /// Stage W2b: train `i`'s doors have opened at stop `stop` of its
    /// timetable (decision 35): riders for its station get off, and
    /// everyone left at a turn or the last stop; then, before the last
    /// stop, it takes on passengers. The larger of the two counts.
    mutating func exchange(_ i: Int, stop: Int) -> Int64 {
        let train = trains[i]
        let station = train.timetable[stop].station.rawValue
        let last = train.timetable.count - 1
        var alighted: Int64 = 0
        if var onBoard = passengers.riders[train.id] {
            for origin in onBoard.keys.sorted() {
                for destination in onBoard[origin]!.keys.sorted() {
                    let count = onBoard[origin]![destination]!
                    if destination == station {
                        passengers.arrived[origin, default: 0] += count
                    } else if train.timetable[stop].reverses || stop == last {
                        passengers.abandoned[origin, default: 0] += count
                    } else {
                        continue
                    }
                    alighted += count
                    onBoard[origin]![destination] = nil
                }
                if onBoard[origin]!.isEmpty { onBoard[origin] = nil }
            }
            passengers.riders[train.id] = onBoard.isEmpty ? nil : onBoard
        }
        return max(alighted, stop < last ? board(i, stop: stop) : 0)
    }

    /// Who train `i` may take on at stop `stop`, as indices into its
    /// station's queue: its line's groups going its way (on a ring,
    /// decision 49, either way) to a station it calls at before it next
    /// turns round, with how far that is.
    func boardable(_ i: Int, stop: Int) -> [(index: Int, far: Int)] {
        let train = trains[i]
        let last = train.timetable.count - 1
        guard stop < last, let line = lines.first(where: { $0.roster.contains(train.id) || $0.patterns.contains { $0.roster.contains(train.id) } }),
              let queue = passengers.queue[train.timetable[stop].station.rawValue]
        else { return [] }
        let outbound = 2 * stop < last
        // Each station ahead, and how far: its first call before the train
        // next turns round.
        var ahead: [Int: Int] = [:]
        var call = stop + 1
        while call <= last {
            let next = train.timetable[call].station.rawValue
            if ahead[next] == nil { ahead[next] = call }
            if train.timetable[call].reverses { break }
            call += 1
        }
        return queue.enumerated().compactMap { index, group in
            guard group.line == line.id, line.ring || group.outbound == outbound, let far = ahead[group.destination] else { return nil }
            return (index, far)
        }
    }

    func room(_ i: Int) -> Int64 {
        Int64(trains[i].cars) * 320 * 11 / 10 - (passengers.riders[trains[i].id] ?? [:]).values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    /// Train `i`, waiting at stop `stop` with its doors open, takes on the
    /// farthest first while it has room; how many boarded.
    mutating func board(_ i: Int, stop: Int) -> Int64 {
        let train = trains[i]
        let station = train.timetable[stop].station.rawValue
        let candidates = boardable(i, stop: stop)
        guard !candidates.isEmpty, var queue = passengers.queue[station] else { return 0 }
        var room = room(i)
        var left = candidates
        var boarded: Int64 = 0
        var paid: [Int: Int64] = [:]
        while room > 0, !left.isEmpty {
            var best = 0
            for k in left.indices where left[k].far > left[best].far {
                best = k
            }
            let index = left.remove(at: best).index
            let taking = min(room, queue[index].count)
            room -= taking
            boarded += taking
            queue[index].count -= taking
            passengers.riders[train.id, default: [:]][station, default: [:]][queue[index].destination, default: 0] += taking
            paid[queue[index].destination, default: 0] += taking
        }
        // Decision 36: each destination's boarders pay, rounded together.
        for (destination, count) in paid {
            chargeFare(count, from: station, to: destination)
        }
        queue.removeAll { $0.count == 0 }
        passengers.queue[station] = queue.isEmpty ? nil : queue
        return boarded
    }

    /// Stage W2b: train `i` has just left stop `stop` full: everyone it
    /// could have taken there is refused (decision 35).
    mutating func refuseLeftBehind(_ i: Int, stop: Int) {
        guard room(i) <= 0 else { return }
        let station = trains[i].timetable[stop].station.rawValue
        let queue = passengers.queue[station] ?? []
        let refused = boardable(i, stop: stop).reduce(Int64(0)) { $0 + queue[$1.index].count }
        if refused > 0 { passengers.refused[station, default: 0] += refused }
    }

    /// A service stopped with riders on board: they are abandoned.
    mutating func abandonRiders(_ i: Int) {
        for (origin, destinations) in passengers.riders[trains[i].id] ?? [:] {
            passengers.abandoned[origin, default: 0] += destinations.values.reduce(0, +)
        }
        passengers.riders[trains[i].id] = nil
    }

    // MARK: - Summaries

    func waitingGroups(at station: Int) -> [WaitingGroupSummary] {
        (passengers.queue[station] ?? []).map {
            WaitingGroupSummary(WaitingGroup(
                line: LineID(rawValue: $0.line), direction: $0.outbound ? .outbound : .inbound, destination: StationID(rawValue: $0.destination),
                since: GameTime(minutes: $0.since), count: $0.count
            ))
        }
    }

    func ledger(of station: Int) -> PassengerLedger {
        PassengerLedger(
            released: passengers.released[station] ?? 0,
            waiting: (passengers.queue[station] ?? []).reduce(0) { $0 + $1.count },
            riding: passengers.riders.values.reduce(0) { $0 + ($1[station]?.values.reduce(0, +) ?? 0) },
            arrived: passengers.arrived[station] ?? 0,
            overflowed: passengers.overflowed[station] ?? 0,
            abandoned: passengers.abandoned[station] ?? 0,
            refused: passengers.refused[station] ?? 0
        )
    }

    func riders(of train: Int) -> [RidingGroup] {
        (passengers.riders[train] ?? [:]).flatMap { origin, destinations in
            destinations.map { RidingGroup(origin: StationID(rawValue: origin), destination: StationID(rawValue: $0.key), count: $0.value) }
        }.sorted { ($0.origin, $0.destination) < ($1.origin, $1.destination) }
    }

    /// The final state's riders, by train.
    var riderSummaries: [RiderSummary] {
        passengers.riders.keys.sorted().map { RiderSummary(train: $0, groups: riders(of: $0).map(RidingGroupSummary.init)) }
    }

    /// The final state's passengers: every station with demand or anyone
    /// ever released there.
    var passengerSummaries: [PassengerSummary] {
        let stations = Set(passengers.demand.keys).union(passengers.released.filter { $0.value > 0 }.keys).sorted()
        return stations.map { station in
            let ledger = ledger(of: station)
            return PassengerSummary(
                station: station,
                demand: passengers.demand[station].map { DemandSummary(StationDemand(kind: $0.kind, dailyTrips: $0.trips)) },
                waiting: waitingGroups(at: station), released: ledger.released, arrived: ledger.arrived,
                overflowed: ledger.overflowed, abandoned: ledger.abandoned, refused: ledger.refused
            )
        }
    }
}
