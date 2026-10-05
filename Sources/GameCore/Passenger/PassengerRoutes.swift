// Passenger service paths (Phase 5C, first part of 5F). The Ci global OD
// dispatch cache stores a first ride or transfer link per origin/destination;
// `metroExpandODDispatchPath` follows those links to the destination. Here
// the equivalent graph is derived from GameWorld's lines, so it needs no
// second authoritative copy and no save field. A change to the lines or
// service is visible on the next query.

/// One uninterrupted ride in a passenger's planned path.
public struct PassengerRouteLeg: Hashable, Sendable {
    public let line: LineID
    public let direction: LineDirection
    public let from: StationID
    public let to: StationID
    public let rideMinutes: Int64
}

/// A route between stations, with whole-minute costs. Consecutive legs on
/// different lines meet at the same station in this first transfer stage.
public struct PassengerRoute: Hashable, Sendable {
    public let legs: [PassengerRouteLeg]
    public let rideMinutes: Int64
    public let waitMinutes: Int64
    public let transferMinutes: Int64

    public var totalMinutes: Int64 { rideMinutes + waitMinutes + transferMinutes }
    public var transfers: Int {
        zip(legs, legs.dropFirst()).reduce(0) { $0 + ($1.0.line == $1.1.line ? 0 : 1) }
    }
}

private func passengerMinutesRoundingUp(_ value: Int64, by divisor: Int64) -> Int64 {
    guard value > 0 else { return 0 }
    return 1 + (value - 1) / divisor
}

private struct PassengerRideEdge: Hashable {
    let line: Int
    let from: Int
    let to: Int
    let direction: Int
}

private struct PassengerRouteNode: Hashable, Comparable {
    let line: Int
    let stop: Int
    let direction: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.stop != rhs.stop { return lhs.stop < rhs.stop }
        return lhs.direction > rhs.direction
    }
}

private struct PassengerRouteLabel {
    enum Arrival {
        case board
        case ride(PassengerRideEdge, Int64)
    }

    let node: PassengerRouteNode
    let total: Int64
    let ride: Int64
    let wait: Int64
    let transfer: Int64
    let changes: Int
    let previous: PassengerRouteNode?
    let arrival: Arrival
}

private struct PassengerRouteGraph {
    // The Ci snapshot receives transfer minutes from its flow service's
    // path plan; that service is absent from the reference snapshot. Four
    // minutes is this first native graph's same-station interchange cost.
    static let sameStationTransferMinutes: Int64 = 4

    let lines: [ServiceLine]
    let stopsAt: [StationID: [PassengerRouteNode]]
    let rideTimes: [[Int64]]
    let headways: [Int64]

    init(world: GameWorld) {
        let level = world.serviceDay.level(atMinuteOfDay: world.clock.now.minuteOfDay)
        var included: [ServiceLine] = []
        var times: [[Int64]] = []
        var gaps: [Int64] = []
        var calls: [StationID: [PassengerRouteNode]] = [:]
        for line in world.lines where line.window.contains(minuteOfDay: world.clock.now.minuteOfDay) {
            var legs: [Int64] = []
            for index in 0..<(line.stops.count - 1) {
                let a = world.station(id: line.stops[index])!.point
                let b = world.station(id: line.stops[index + 1])!.point
                let dx = b.x - a.x
                let dy = b.y - a.y
                let length = max(1, FixedPoint.roundedSquareRoot(dx * dx + dy * dy))
                let seconds = RunningCurve.leastSeconds(length: length, performance: line.performance) ?? 60
                legs.append(max(1, passengerMinutesRoundingUp(seconds, by: 60)))
            }
            let running = legs.reduce(0, +)
            let roundTrip: Int64
            let plan: (trains: Int, headway: Int64)?
            if line.isRing {
                let a = world.station(id: line.stops.last!)!.point
                let b = world.station(id: line.stops.first!)!.point
                let dx = b.x - a.x
                let dy = b.y - a.y
                let length = max(1, FixedPoint.roundedSquareRoot(dx * dx + dy * dy))
                let seconds = RunningCurve.leastSeconds(length: length, performance: line.performance) ?? 60
                legs.append(max(1, passengerMinutesRoundingUp(seconds, by: 60)))
                roundTrip = running + legs.last! + Int64(line.stops.count) * ServiceLine.dwellMinutes
                plan = ServiceLine.ringService(line.trainsInService, line.targetHeadways, at: level, lap: roundTrip)
            } else {
                roundTrip = 2 * (running + Int64(max(0, line.stops.count - 2)) * ServiceLine.dwellMinutes
                    + ServiceLine.terminalDwellMinutes)
                plan = line.service(at: level, roundTrip: roundTrip)
            }
            guard let plan else { continue }
            let lineIndex = included.count
            included.append(line)
            times.append(legs)
            gaps.append(plan.headway)
            for (stop, station) in line.stops.enumerated() {
                for direction in [1, -1] {
                    calls[station, default: []].append(PassengerRouteNode(line: lineIndex, stop: stop, direction: direction))
                }
            }
        }
        lines = included
        stopsAt = calls
        rideTimes = times
        headways = gaps
    }

    private func station(_ node: PassengerRouteNode) -> StationID {
        lines[node.line].stops[node.stop]
    }

    private func nextRide(_ node: PassengerRouteNode) -> (PassengerRouteNode, PassengerRideEdge, Int64)? {
        let line = lines[node.line]
        var next = node.stop + node.direction
        if line.isRing {
            if next == line.stops.count { next = 0 }
            if next < 0 { next = line.stops.count - 1 }
        } else if next < 0 || next == line.stops.count {
            return nil
        }
        let segment = node.direction == 1 ? node.stop : next
        let edge = PassengerRideEdge(line: node.line, from: node.stop, to: next, direction: node.direction)
        return (PassengerRouteNode(line: node.line, stop: next, direction: node.direction), edge,
                rideTimes[node.line][segment] + ServiceLine.dwellMinutes)
    }

    /// Dijkstra over (line, call, direction). A line change at the same
    /// station adds a transfer penalty and another expected wait. A reversal
    /// on the same line is possible only at a terminal, and also waits.
    func shortest(from origin: StationID, to destination: StationID, banning forbidden: Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])? {
        guard let starts = stopsAt[origin], stopsAt[destination] != nil else { return nil }
        var best: [PassengerRouteNode: PassengerRouteLabel] = [:]
        var open: [PassengerRouteNode] = []

        func offer(_ label: PassengerRouteLabel) {
            if let earlier = best[label.node] {
                if label.total > earlier.total || label.total == earlier.total && label.changes >= earlier.changes { return }
            } else {
                open.append(label.node)
            }
            best[label.node] = label
        }

        for node in starts {
            let wait = max(1, passengerMinutesRoundingUp(headways[node.line], by: 2))
            offer(PassengerRouteLabel(node: node, total: wait, ride: 0, wait: wait,
                                      transfer: 0, changes: 0, previous: nil, arrival: .board))
        }
        while !open.isEmpty {
            open.sort { a, b in
                let left = best[a]!
                let right = best[b]!
                if left.total != right.total { return left.total < right.total }
                if left.changes != right.changes { return left.changes < right.changes }
                return a < b
            }
            let node = open.removeFirst()
            let label = best[node]!
            if station(node) == destination, label.ride > 0 {
                return reconstruct(label, from: best)
            }
            if let (next, edge, minutes) = nextRide(node), !forbidden.contains(edge) {
                offer(PassengerRouteLabel(node: next, total: label.total + minutes,
                                          ride: label.ride + minutes, wait: label.wait,
                                          transfer: label.transfer, changes: label.changes,
                                          previous: node, arrival: .ride(edge, minutes)))
            }
            for other in stopsAt[station(node)] ?? [] where other != node {
                let sameLine = other.line == node.line
                if sameLine {
                    guard !lines[node.line].isRing,
                          (node.stop == 0 || node.stop == lines[node.line].stops.count - 1),
                          other.stop == node.stop, other.direction != node.direction else { continue }
                }
                let wait = max(1, passengerMinutesRoundingUp(headways[other.line], by: 2))
                let transfer: Int64 = sameLine ? 0 : Self.sameStationTransferMinutes
                offer(PassengerRouteLabel(node: other, total: label.total + wait + transfer,
                                          ride: label.ride, wait: label.wait + wait,
                                          transfer: label.transfer + transfer,
                                          changes: label.changes + (sameLine ? 0 : 1),
                                          previous: node, arrival: .board))
            }
        }
        return nil
    }

    private func reconstruct(_ end: PassengerRouteLabel, from labels: [PassengerRouteNode: PassengerRouteLabel]) -> (PassengerRoute, [PassengerRideEdge]) {
        var chain: [PassengerRouteLabel] = []
        var current: PassengerRouteLabel? = end
        while let label = current {
            chain.append(label)
            current = label.previous.flatMap { labels[$0] }
        }
        var legs: [PassengerRouteLeg] = []
        var edges: [PassengerRideEdge] = []
        for label in chain.reversed() {
            guard case .ride(let edge, let minutes) = label.arrival else { continue }
            edges.append(edge)
            let line = lines[edge.line].id
            let direction: LineDirection = edge.direction == 1 ? .outbound : .inbound
            let from = lines[edge.line].stops[edge.from]
            let to = lines[edge.line].stops[edge.to]
            if let last = legs.last, last.line == line && last.direction == direction && last.to == from {
                legs[legs.count - 1] = PassengerRouteLeg(line: line, direction: direction,
                                                           from: last.from, to: to,
                                                           rideMinutes: last.rideMinutes + minutes)
            } else {
                legs.append(PassengerRouteLeg(line: line, direction: direction,
                                              from: from, to: to, rideMinutes: minutes))
            }
        }
        return (PassengerRoute(legs: legs, rideMinutes: end.ride,
                               waitMinutes: end.wait, transferMinutes: end.transfer), edges)
    }
}

extension GameWorld {
    /// Up to three distinct service paths between two stations, in ascending
    /// whole-minute cost. Ties prefer fewer transfers, then the line and
    /// stop order. The graph uses lines with service planned at the current
    /// minute; it is derived anew when queried. A route is a plan only:
    /// passenger release and boarding still use `passengerTrip` until the
    /// following transfer stage moves the route into their queue records.
    public func passengerRoutes(from origin: StationID, to destination: StationID, limit: Int = 3) -> [PassengerRoute] {
        guard origin != destination, station(id: origin) != nil, station(id: destination) != nil,
              limit > 0 else { return [] }
        let graph = PassengerRouteGraph(world: self)
        guard let first = graph.shortest(from: origin, to: destination, banning: []) else { return [] }
        var selected = [first.0]
        var candidates: [(route: PassengerRoute, edges: [PassengerRideEdge], bans: Set<PassengerRideEdge>)] = []
        var chosen = (route: first.0, edges: first.1, bans: Set<PassengerRideEdge>())
        var tried: Set<Set<PassengerRideEdge>> = [[]]
        while selected.count < min(limit, 3) {
            for edge in chosen.edges {
                var bans = chosen.bans
                bans.insert(edge)
                guard tried.insert(bans).inserted,
                      let found = graph.shortest(from: origin, to: destination, banning: bans),
                      !selected.contains(found.0), !candidates.contains(where: { $0.route == found.0 })
                else { continue }
                candidates.append((found.0, found.1, bans))
            }
            guard !candidates.isEmpty else { break }
            candidates.sort { a, b in
                if a.route.totalMinutes != b.route.totalMinutes { return a.route.totalMinutes < b.route.totalMinutes }
                if a.route.transfers != b.route.transfers { return a.route.transfers < b.route.transfers }
                let left = a.route.legs.map { ($0.line.rawValue, $0.from.rawValue, $0.to.rawValue) }
                let right = b.route.legs.map { ($0.line.rawValue, $0.from.rawValue, $0.to.rawValue) }
                for (l, r) in zip(left, right) where l != r {
                    if l.0 != r.0 { return l.0 < r.0 }
                    if l.1 != r.1 { return l.1 < r.1 }
                    return l.2 < r.2
                }
                return left.count < right.count
            }
            chosen = candidates.removeFirst()
            selected.append(chosen.route)
        }
        return selected
    }
}
