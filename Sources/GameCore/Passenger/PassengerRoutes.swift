// Passenger service paths (Phase 5C, first part of 5F). The Ci global OD
// dispatch cache stores a first ride or transfer link per origin/destination;
// `metroExpandODDispatchPath` follows those links to the destination. Here
// the graph uses GameWorld's existing physical LineJourney and capacity-aware
// lineHeadway queries, so it needs no second service planner or save field.
// A change to the network or service is visible on the next query.

/// One uninterrupted ride in a passenger's planned path.
public struct PassengerRouteLeg: Hashable, Sendable {
    public let line: LineID
    /// `nil` for the line's own service; otherwise its pattern index.
    public let pattern: Int?
    public let direction: LineDirection
    public let from: StationID
    public let to: StationID
    /// Actual running seconds from the service's ``LineJourney`` plus
    /// intermediate station dwells. No rounding is done per track segment.
    public let rideSeconds: Int64
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

    struct ServicePath {
        let line: LineID
        let pattern: Int?
        let direction: LineDirection
        let stations: [StationID]
        let runSeconds: [Int64]
        let headway: Int64
        let isRing: Bool
    }

    let paths: [ServicePath]
    let stopsAt: [StationID: [PassengerRouteNode]]

    init(world: GameWorld) {
        var included: [ServicePath] = []
        var calls: [StationID: [PassengerRouteNode]] = [:]
        for line in world.lines {
            guard let level = world.serviceLevel(of: line.id, at: world.clock.now) else { continue }
            for service in 0..<line.serviceCount {
                let pattern = service == 0 ? nil : service - 1
                guard let headway = world.lineHeadway(line.id, at: level, pattern: pattern),
                      let journey = world.lineJourney(line.id, pattern: pattern) else { continue }
                if line.isRing {
                    for direction in [RingDirection.inner, .outer] {
                        guard let lap = direction == .inner ? journey : world.journey(of: line, service: service, direction: .outer) else { continue }
                        let stationIDs = line.ringCalls(direction).map { line.stops[$0] }
                        let path = ServicePath(line: line.id, pattern: nil,
                                               direction: direction == .inner ? .outbound : .inbound,
                                               stations: stationIDs, runSeconds: lap.legs.map(\.seconds),
                                               headway: headway, isRing: true)
                        Self.add(path, to: &included, calls: &calls)
                    }
                } else {
                    let callIndices = line.calls(ofService: service)
                    let half = callIndices.count - 1
                    let forward = ServicePath(line: line.id, pattern: pattern, direction: .outbound,
                                              stations: callIndices.map { line.stops[$0] },
                                              runSeconds: Array(journey.legs.prefix(half).map(\.seconds)),
                                              headway: headway, isRing: false)
                    let backward = ServicePath(line: line.id, pattern: pattern, direction: .inbound,
                                               stations: callIndices.reversed().map { line.stops[$0] },
                                               runSeconds: Array(journey.legs.suffix(half).map(\.seconds)),
                                               headway: headway, isRing: false)
                    Self.add(forward, to: &included, calls: &calls)
                    Self.add(backward, to: &included, calls: &calls)
                }
            }
        }
        paths = included
        stopsAt = calls
    }

    private static func add(_ path: ServicePath, to paths: inout [ServicePath], calls: inout [StationID: [PassengerRouteNode]]) {
        let index = paths.count
        paths.append(path)
        for (stop, station) in path.stations.enumerated() {
            calls[station, default: []].append(PassengerRouteNode(line: index, stop: stop,
                                                                    direction: path.direction == .outbound ? 1 : -1))
        }
    }

    private func station(_ node: PassengerRouteNode) -> StationID {
        paths[node.line].stations[node.stop]
    }

    private func nextRide(_ node: PassengerRouteNode) -> (PassengerRouteNode, PassengerRideEdge, Int64)? {
        let path = paths[node.line]
        let next = node.stop + 1 == path.stations.count ? (path.isRing ? 1 : -1) : node.stop + 1
        guard next >= 0 else { return nil }
        let segment = next == 1 && node.stop == path.stations.count - 1 ? 0 : node.stop
        let edge = PassengerRideEdge(line: node.line, from: node.stop, to: next, direction: node.direction)
        return (PassengerRouteNode(line: node.line, stop: next, direction: node.direction), edge,
                path.runSeconds[segment] + (node.stop == 0 ? 0 : ServiceLine.dwellMinutes * GameTime.secondsPerMinute))
    }

    /// Dijkstra over (service, call, direction). A line change at the same
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
            let wait = max(1, passengerMinutesRoundingUp(paths[node.line].headway, by: 2)) * GameTime.secondsPerMinute
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
            if station(node) == destination {
                return reconstruct(label, from: best)
            }
            if let (next, edge, minutes) = nextRide(node), !forbidden.contains(edge) {
                offer(PassengerRouteLabel(node: next, total: label.total + minutes,
                                          ride: label.ride + minutes, wait: label.wait,
                                          transfer: label.transfer, changes: label.changes,
                                          previous: node, arrival: .ride(edge, minutes)))
            }
            for other in stopsAt[station(node)] ?? [] where other != node {
                guard other.line != node.line else { continue }
                let sameLine = paths[other.line].line == paths[node.line].line
                let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
                let transfer: Int64 = sameLine ? 0 : Self.sameStationTransferMinutes * GameTime.secondsPerMinute
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
            let path = paths[edge.line]
            let from = path.stations[edge.from]
            let to = path.stations[edge.to]
            if let last = legs.last, last.line == path.line && last.pattern == path.pattern &&
                last.direction == path.direction && last.to == from {
                legs[legs.count - 1] = PassengerRouteLeg(line: path.line, pattern: path.pattern,
                                                          direction: path.direction, from: last.from,
                                                          to: to, rideSeconds: last.rideSeconds + minutes)
            } else {
                legs.append(PassengerRouteLeg(line: path.line, pattern: path.pattern,
                                              direction: path.direction, from: from,
                                              to: to, rideSeconds: minutes))
            }
        }
        return (PassengerRoute(legs: legs,
                               rideMinutes: passengerMinutesRoundingUp(end.ride, by: GameTime.secondsPerMinute),
                               waitMinutes: end.wait / GameTime.secondsPerMinute,
                               transferMinutes: end.transfer / GameTime.secondsPerMinute), edges)
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
