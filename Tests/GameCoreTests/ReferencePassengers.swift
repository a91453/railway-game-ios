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
        }
    }

    static func arrivals(_ kind: StationDemandKind) -> [Int64] {
        switch kind {
        case .residential: shape { 1 + bell($0, 18, 1.15) * 0.6 }
        case .office: shape { 1 + bell($0, 8, 1.15) * 0.6 }
        case .shopping: shape { 1 + bell($0, 13, 2.4) * 0.42 + bell($0, 18, 1.8) * 0.5 }
        case .scenic: shape { 1 + bell($0, 11, 2.1) * 0.75 }
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
        return Array(zip(reached, Self.largestRemainder(own.trips, reached.map { passengers.demand[$0]!.trips })))
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
            overflowed: passengers.overflowed[station] ?? 0,
            abandoned: passengers.abandoned[station] ?? 0
        )
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
                waiting: waitingGroups(at: station), released: ledger.released, overflowed: ledger.overflowed, abandoned: ledger.abandoned
            )
        }
    }
}
