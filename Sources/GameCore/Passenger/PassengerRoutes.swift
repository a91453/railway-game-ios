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
    fileprivate var totalSeconds: Int64 {
        legs.reduce(0) { $0 + $1.rideSeconds } + (waitMinutes + transferMinutes) * GameTime.secondsPerMinute
    }
    public var transfers: Int {
        zip(legs, legs.dropFirst()).reduce(0) { $0 + ($1.0.line == $1.1.line ? 0 : 1) }
    }
}

private func passengerRoutePrecedes(_ lhs: PassengerRoute, _ rhs: PassengerRoute) -> Bool {
    if lhs.totalMinutes != rhs.totalMinutes { return lhs.totalMinutes < rhs.totalMinutes }
    if lhs.transfers != rhs.transfers { return lhs.transfers < rhs.transfers }
    if lhs.totalSeconds != rhs.totalSeconds { return lhs.totalSeconds < rhs.totalSeconds }
    let left = lhs.legs.map { ($0.line.rawValue, $0.from.rawValue, $0.to.rawValue) }
    let right = rhs.legs.map { ($0.line.rawValue, $0.from.rawValue, $0.to.rawValue) }
    for (l, r) in zip(left, right) where l != r {
        if l.0 != r.0 { return l.0 < r.0 }
        if l.1 != r.1 { return l.1 < r.1 }
        return l.2 < r.2
    }
    return left.count < right.count
}

private func passengerMinutesRoundingUp(_ value: Int64, by divisor: Int64) -> Int64 {
    guard value > 0 else { return 0 }
    return 1 + (value - 1) / divisor
}

struct PassengerRideEdge: Hashable {
    let line: Int
    let from: Int
    let to: Int
    let direction: Int
}

struct PassengerRouteNode: Hashable, Comparable {
    let line: Int
    let stop: Int
    let direction: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.stop != rhs.stop { return lhs.stop < rhs.stop }
        return lhs.direction > rhs.direction
    }
}

private struct PassengerRouteState: Hashable {
    let node: PassengerRouteNode
    let onboard: Bool
}

private struct PassengerRouteLabel {
    enum Arrival {
        case board
        case ride(PassengerRideEdge, Int64)
    }

    let state: PassengerRouteState
    let total: Int64
    let ride: Int64
    let wait: Int64
    let transfer: Int64
    let changes: Int
    let previous: Int?
    let arrival: Arrival
}

struct PassengerRouteGraph {
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

    init(paths: [ServicePath]) {
        var included: [ServicePath] = []
        var calls: [StationID: [PassengerRouteNode]] = [:]
        for path in paths {
            Self.add(path, to: &included, calls: &calls)
        }
        self.paths = included
        stopsAt = calls
    }

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
        let next = node.stop + 1
        guard next < path.stations.count else { return nil }
        let edge = PassengerRideEdge(line: node.line, from: node.stop, to: next, direction: node.direction)
        return (PassengerRouteNode(line: node.line, stop: next, direction: node.direction), edge,
                path.runSeconds[node.stop])
    }

    /// Dijkstra over service calls and boarding state. Each state keeps the
    /// nondominated (elapsed seconds, line changes) labels, since rounding
    /// to whole minutes can favor a later arrival with fewer changes.
    func shortest(from origin: StationID, to destination: StationID, banning forbidden: Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])? {
        guard let starts = stopsAt[origin], stopsAt[destination] != nil else { return nil }
        var labels: [PassengerRouteLabel] = []
        var frontier: [PassengerRouteState: [Int]] = [:]
        var active: [Bool] = []
        var open: [Int] = []

        func offer(_ label: PassengerRouteLabel) {
            let state = label.state
            let existing = frontier[state] ?? []
            if existing.contains(where: { labels[$0].total <= label.total && labels[$0].changes <= label.changes }) {
                return
            }
            var survivors: [Int] = []
            for index in existing {
                if label.total <= labels[index].total && label.changes <= labels[index].changes {
                    active[index] = false
                } else {
                    survivors.append(index)
                }
            }
            let index = labels.count
            labels.append(label)
            active.append(true)
            open.append(index)
            survivors.append(index)
            frontier[state] = survivors
        }

        for node in starts {
            let wait = max(1, passengerMinutesRoundingUp(paths[node.line].headway, by: 2)) * GameTime.secondsPerMinute
            offer(PassengerRouteLabel(state: PassengerRouteState(node: node, onboard: false),
                                      total: wait, ride: 0, wait: wait, transfer: 0,
                                      changes: 0, previous: nil, arrival: .board))
        }
        while !open.isEmpty {
            open.sort { a, b in
                let left = labels[a]
                let right = labels[b]
                let leftMinutes = passengerMinutesRoundingUp(left.total, by: GameTime.secondsPerMinute)
                let rightMinutes = passengerMinutesRoundingUp(right.total, by: GameTime.secondsPerMinute)
                if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }
                if left.changes != right.changes { return left.changes < right.changes }
                if left.total != right.total { return left.total < right.total }
                if left.state.node != right.state.node { return left.state.node < right.state.node }
                if left.state.onboard != right.state.onboard { return !left.state.onboard }
                return a < b
            }
            let index = open.removeFirst()
            guard active[index] else { continue }
            let label = labels[index]
            let node = label.state.node
            if station(node) == destination {
                return reconstruct(index, from: labels)
            }
            if let (next, edge, run) = nextRide(node), !forbidden.contains(edge) {
                // A passenger already aboard stays through this stop's
                // dwell. One boarding here has waited for departure already.
                let dwell = label.state.onboard ? ServiceLine.dwellMinutes * GameTime.secondsPerMinute : 0
                let seconds = run + dwell
                offer(PassengerRouteLabel(state: PassengerRouteState(node: next, onboard: true),
                                          total: label.total + seconds, ride: label.ride + seconds,
                                          wait: label.wait, transfer: label.transfer,
                                          changes: label.changes, previous: index,
                                          arrival: .ride(edge, seconds)))
            }
            let path = paths[node.line]
            if path.isRing && node.stop == path.stations.count - 1 {
                // The final call is the starting station, but it ends this
                // train's lap. Crossing to the next lap requires a new wait.
                let wait = max(1, passengerMinutesRoundingUp(path.headway, by: 2)) * GameTime.secondsPerMinute
                let first = PassengerRouteNode(line: node.line, stop: 0, direction: node.direction)
                offer(PassengerRouteLabel(state: PassengerRouteState(node: first, onboard: false),
                                          total: label.total + wait, ride: label.ride,
                                          wait: label.wait + wait, transfer: label.transfer,
                                          changes: label.changes, previous: index, arrival: .board))
            }
            for other in stopsAt[station(node)] ?? [] where other != node {
                guard other.line != node.line else { continue }
                let sameLine = paths[other.line].line == paths[node.line].line
                let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
                let transfer: Int64 = sameLine ? 0 : Self.sameStationTransferMinutes * GameTime.secondsPerMinute
                offer(PassengerRouteLabel(state: PassengerRouteState(node: other, onboard: false),
                                          total: label.total + wait + transfer,
                                          ride: label.ride, wait: label.wait + wait,
                                          transfer: label.transfer + transfer,
                                          changes: label.changes + (sameLine ? 0 : 1),
                                          previous: index, arrival: .board))
            }
        }
        return nil
    }

    private func reconstruct(_ endIndex: Int, from labels: [PassengerRouteLabel]) -> (PassengerRoute, [PassengerRideEdge]) {
        var chain: [PassengerRouteLabel] = []
        var current: Int? = endIndex
        while let index = current {
            let label = labels[index]
            chain.append(label)
            current = label.previous
        }
        var legs: [PassengerRouteLeg] = []
        var edges: [PassengerRideEdge] = []
        var newBoarding = true
        for label in chain.reversed() {
            guard case .ride(let edge, let seconds) = label.arrival else {
                newBoarding = true
                continue
            }
            edges.append(edge)
            let path = paths[edge.line]
            let from = path.stations[edge.from]
            let to = path.stations[edge.to]
            if !newBoarding, let last = legs.last, last.line == path.line && last.pattern == path.pattern &&
                last.direction == path.direction && last.to == from {
                legs[legs.count - 1] = PassengerRouteLeg(line: path.line, pattern: path.pattern,
                                                          direction: path.direction, from: last.from,
                                                          to: to, rideSeconds: last.rideSeconds + seconds)
            } else {
                legs.append(PassengerRouteLeg(line: path.line, pattern: path.pattern,
                                              direction: path.direction, from: from,
                                              to: to, rideSeconds: seconds))
            }
            newBoarding = false
        }
        return (PassengerRoute(legs: legs,
                               rideMinutes: passengerMinutesRoundingUp(labels[endIndex].ride, by: GameTime.secondsPerMinute),
                               waitMinutes: labels[endIndex].wait / GameTime.secondsPerMinute,
                               transferMinutes: labels[endIndex].transfer / GameTime.secondsPerMinute), edges)
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
            candidates.sort { passengerRoutePrecedes($0.route, $1.route) }
            chosen = candidates.removeFirst()
            selected.append(chosen.route)
        }
        return selected
    }
}
