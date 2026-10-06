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

/// A route between stations, with whole-minute costs. Consecutive legs
/// meet at the same station, or a passenger walks from where one leg ends
/// to a station nearby where the next begins (Phase 5F, see
/// ``PassengerTransferTier``).
public struct PassengerRoute: Hashable, Sendable {
    public let legs: [PassengerRouteLeg]
    public let rideMinutes: Int64
    public let waitMinutes: Int64
    /// The transfer penalties, rounded up to whole minutes.
    public var transferMinutes: Int64 { passengerMinutesRoundingUp(transferSeconds, by: GameTime.secondsPerMinute) }
    /// The walks between stations, rounded up to whole minutes.
    public var walkMinutes: Int64 { passengerMinutesRoundingUp(walkSeconds, by: GameTime.secondsPerMinute) }
    let transferSeconds: Int64
    let walkSeconds: Int64

    public var totalMinutes: Int64 { rideMinutes + waitMinutes + transferMinutes + walkMinutes }
    fileprivate var totalSeconds: Int64 {
        legs.reduce(0) { $0 + $1.rideSeconds } + waitMinutes * GameTime.secondsPerMinute + transferSeconds + walkSeconds
    }
    public var transfers: Int {
        zip(legs, legs.dropFirst()).reduce(0) { $0 + ($1.0.line == $1.1.line ? 0 : 1) }
    }
}

/// One OD group's passengers assigned to a route. A zero count keeps the
/// route visible when the group is smaller than the number of choices.
public struct PassengerRouteAllocation: Hashable, Sendable {
    public let route: PassengerRoute
    public let count: Int64
}

struct PassengerRouteChoice: Sendable {
    let route: PassengerRoute
    let weight: Int64
}

private struct PassengerRouteOrderLeg: Equatable {
    let line: LineID
    let from: StationID
    let to: StationID
}

private func passengerRouteOrderPrecedes(_ lhs: [PassengerRouteOrderLeg], _ rhs: [PassengerRouteOrderLeg]) -> Bool {
    for (left, right) in zip(lhs, rhs) where left != right {
        if left.line.rawValue != right.line.rawValue { return left.line.rawValue < right.line.rawValue }
        if left.from.rawValue != right.from.rawValue { return left.from.rawValue < right.from.rawValue }
        return left.to.rawValue < right.to.rawValue
    }
    return lhs.count < rhs.count
}

private func passengerRoutePrecedes(_ lhs: PassengerRoute, _ rhs: PassengerRoute) -> Bool {
    if lhs.totalMinutes != rhs.totalMinutes { return lhs.totalMinutes < rhs.totalMinutes }
    if lhs.transfers != rhs.transfers { return lhs.transfers < rhs.transfers }
    if lhs.totalSeconds != rhs.totalSeconds { return lhs.totalSeconds < rhs.totalSeconds }
    let left = lhs.legs.map { PassengerRouteOrderLeg(line: $0.line, from: $0.from, to: $0.to) }
    let right = rhs.legs.map { PassengerRouteOrderLeg(line: $0.line, from: $0.from, to: $0.to) }
    return passengerRouteOrderPrecedes(left, right)
}

func passengerMinutesRoundingUp(_ value: Int64, by divisor: Int64) -> Int64 {
    guard value > 0 else { return 0 }
    return 1 + (value - 1) / divisor
}

struct PassengerRideEdge: Hashable {
    let line: Int
    let from: Int
    let to: Int
    let direction: Int
}

struct PassengerRouteNode: Hashable, Comparable, Sendable {
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

/// A binary min-heap of label indices under a caller's strict total order.
/// It replaces sorting the whole open list before every pop (quadratic in
/// the labels); with a total order the least element is unique, so the
/// order in which labels pop is the same.
private struct PassengerRouteHeap {
    private var items: [Int] = []

    mutating func push(_ item: Int, by precedes: (Int, Int) -> Bool) {
        var child = items.count
        items.append(item)
        while child > 0 {
            let parent = (child - 1) / 2
            guard precedes(items[child], items[parent]) else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop(by precedes: (Int, Int) -> Bool) -> Int? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        guard !items.isEmpty else { return first }
        items[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1
            guard left < items.count else { break }
            var least = left
            if left + 1 < items.count, precedes(items[left + 1], items[left]) { least = left + 1 }
            guard precedes(items[least], items[parent]) else { break }
            items.swapAt(least, parent)
            parent = least
        }
        return first
    }
}

private struct PassengerRouteLabel {
    enum Arrival {
        case board
        case ride(PassengerRideEdge, Int64)
    }

    let state: PassengerRouteState
    let total: Int64
    /// `total` rounded up to whole minutes: the first key of the open list.
    var minutes: Int64 { passengerMinutesRoundingUp(total, by: GameTime.secondsPerMinute) }
    let ride: Int64
    let wait: Int64
    let transfer: Int64
    let walk: Int64
    let changes: Int
    /// The label's full-route order (the legs ridden so far, as lines and
    /// stations): the last of its legs in the search's shared order tree,
    /// or -1 before the first ride. Kept as a tree so a label costs no
    /// array copy; the arrays are built only to break an exact tie.
    let order: Int
    let previous: Int?
    let arrival: Arrival
}

struct PassengerRouteGraph: Sendable {
    /// A walk from a station to another nearby (see
    /// ``walk(from:to:in:)``).
    struct Walk: Sendable {
        let to: StationID
        let seconds: Int64
        let tier: PassengerTransferTier
    }

    struct ServicePath: Sendable {
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
    /// Each served station's walks to the other served stations nearby, by
    /// ascending station.
    let walks: [StationID: [Walk]]
    /// Served stations where nobody boards, alights or changes: trains run
    /// through them.
    let closed: Set<StationID>
    /// The index of each path's first call among all calls, in path order:
    /// a node's index is its path's offset plus its stop, so indices order
    /// nodes as ``PassengerRouteNode/<`` does.
    let offsets: [Int]
    let nodeCount: Int

    private static func offsets(of paths: [ServicePath]) -> [Int] {
        var offsets: [Int] = []
        var next = 0
        for path in paths {
            offsets.append(next)
            next += path.stations.count
        }
        return offsets + [next]
    }

    init(paths: [ServicePath], walks: [StationID: [Walk]] = [:], closed: Set<StationID> = []) {
        var included: [ServicePath] = []
        var calls: [StationID: [PassengerRouteNode]] = [:]
        for path in paths {
            Self.add(path, to: &included, calls: &calls)
        }
        self.paths = included
        stopsAt = calls
        self.walks = walks
        self.closed = closed
        let offsets = Self.offsets(of: included)
        self.offsets = Array(offsets.dropLast())
        nodeCount = offsets.last!
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
        // Stations are by ascending ID, so each station's walks are too.
        let served = world.stations.filter { calls[$0.id] != nil }
        closed = Set(served.filter { !$0.operationMode.allowsService }.map(\.id))
        var walks: [StationID: [Walk]] = [:]
        for from in served {
            let nearby = served.compactMap { to in Self.walk(from: from, to: to) }
            if !nearby.isEmpty { walks[from.id] = nearby }
        }
        self.walks = walks
        let offsets = Self.offsets(of: included)
        self.offsets = Array(offsets.dropLast())
        nodeCount = offsets.last!
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
    /// to whole minutes can favor a later arrival with fewer changes. Exact
    /// metric ties keep the lower full-route line/stop order.
    func shortest(from origin: StationID, to destination: StationID, banning forbidden: Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])? {
        guard stopsAt[destination] != nil, !closed.contains(destination) else { return nil }
        return search(from: origin, to: destination, banning: forbidden)[destination]
    }

    /// The shortest route from `origin` to `destination`, or with no
    /// destination to every station it reaches but itself. Which label pops
    /// next never depends on the destination, so the first label popped at
    /// a station is the same whether the search stops there or goes on.
    private func search(from origin: StationID, to destination: StationID?,
                        banning forbidden: Set<PassengerRideEdge>) -> [StationID: (PassengerRoute, [PassengerRideEdge])] {
        guard let starts = stopsAt[origin], !closed.contains(origin) else { return [:] }
        var firstAt: [StationID: Int] = [:]
        // The banned rides, by the index of the node they leave.
        var banned = Array(repeating: false, count: nodeCount)
        for edge in forbidden where edge.line < paths.count && edge.to == edge.from + 1
            && edge.direction == (paths[edge.line].direction == .outbound ? 1 : -1)
            && (0..<paths[edge.line].stations.count - 1).contains(edge.from) {
            banned[offsets[edge.line] + edge.from] = true
        }
        var orderLegs: [PassengerRouteOrderLeg] = []
        var orderParents: [Int] = []
        func orderArray(_ tail: Int) -> [PassengerRouteOrderLeg] {
            var legs: [PassengerRouteOrderLeg] = []
            var node = tail
            while node >= 0 {
                legs.append(orderLegs[node])
                node = orderParents[node]
            }
            return legs.reversed()
        }
        func orderPrecedes(_ lhs: Int, _ rhs: Int) -> Bool {
            lhs != rhs && passengerRouteOrderPrecedes(orderArray(lhs), orderArray(rhs))
        }
        var labels: [PassengerRouteLabel] = []
        // Each label's keys, kept apart so ordering the open list reads
        // plain integers. A state's index is its node's index, twice, plus
        // 1 on board.
        var totals: [Int64] = []
        var minutes: [Int64] = []
        var changes: [Int] = []
        var states: [Int] = []
        var frontier = Array(repeating: [Int](), count: nodeCount * 2)
        var active: [Bool] = []
        // The open list is a binary heap ordered by `pops`, a strict total
        // order (its last key is the label index), so popping its least
        // element takes exactly the label that sorting the whole list and
        // taking the first did before.
        var open = PassengerRouteHeap()

        func pops(_ a: Int, before b: Int) -> Bool {
            if minutes[a] != minutes[b] { return minutes[a] < minutes[b] }
            if changes[a] != changes[b] { return changes[a] < changes[b] }
            if totals[a] != totals[b] { return totals[a] < totals[b] }
            if orderPrecedes(labels[a].order, labels[b].order) { return true }
            if orderPrecedes(labels[b].order, labels[a].order) { return false }
            // Node order, then waiting before on board.
            if states[a] != states[b] { return states[a] < states[b] }
            return a < b
        }

        func dominates(_ lhs: Int, _ rhs: PassengerRouteLabel) -> Bool {
            guard totals[lhs] <= rhs.total, changes[lhs] <= rhs.changes else { return false }
            if totals[lhs] < rhs.total || changes[lhs] < rhs.changes { return true }
            return !orderPrecedes(rhs.order, labels[lhs].order)
        }

        func dominates(_ lhs: PassengerRouteLabel, _ rhs: Int) -> Bool {
            guard lhs.total <= totals[rhs], lhs.changes <= changes[rhs] else { return false }
            if lhs.total < totals[rhs] || lhs.changes < changes[rhs] { return true }
            return !orderPrecedes(labels[rhs].order, lhs.order)
        }

        func offer(_ label: PassengerRouteLabel) {
            let state = 2 * (offsets[label.state.node.line] + label.state.node.stop) + (label.state.onboard ? 1 : 0)
            let existing = frontier[state]
            if existing.contains(where: { dominates($0, label) }) { return }
            var survivors: [Int] = []
            for index in existing {
                if dominates(label, index) {
                    active[index] = false
                } else {
                    survivors.append(index)
                }
            }
            let index = labels.count
            labels.append(label)
            totals.append(label.total)
            minutes.append(label.minutes)
            changes.append(label.changes)
            states.append(state)
            active.append(true)
            open.push(index, by: pops)
            survivors.append(index)
            frontier[state] = survivors
        }

        for node in starts {
            let wait = max(1, passengerMinutesRoundingUp(paths[node.line].headway, by: 2)) * GameTime.secondsPerMinute
            offer(PassengerRouteLabel(state: PassengerRouteState(node: node, onboard: false),
                                      total: wait, ride: 0, wait: wait, transfer: 0, walk: 0,
                                      changes: 0, order: -1, previous: nil, arrival: .board))
        }
        while let index = open.pop(by: pops) {
            guard active[index] else { continue }
            let label = labels[index]
            let node = label.state.node
            let here = station(node)
            let isOpen = !closed.contains(here)
            // A route ends getting off a train at an open station: a
            // passenger who walked or changed there arrived on board first.
            if here == destination, label.state.onboard, isOpen {
                return [here: reconstruct(index, from: labels)]
            }
            if destination == nil, label.state.onboard, isOpen, here != origin, firstAt[here] == nil {
                firstAt[here] = index
            }
            if let (next, edge, run) = nextRide(node), !banned[offsets[node.line] + node.stop] {
                // A passenger already aboard stays through this stop's
                // dwell. One boarding here has waited for departure already.
                let dwell = label.state.onboard ? ServiceLine.dwellMinutes * GameTime.secondsPerMinute : 0
                let seconds = run + dwell
                let ridePath = paths[edge.line]
                let to = ridePath.stations[edge.to]
                let order = orderLegs.count
                if label.state.onboard, label.order >= 0 {
                    let last = orderLegs[label.order]
                    orderLegs.append(PassengerRouteOrderLeg(line: last.line, from: last.from, to: to))
                    orderParents.append(orderParents[label.order])
                } else {
                    orderLegs.append(PassengerRouteOrderLeg(line: ridePath.line,
                                                            from: ridePath.stations[edge.from], to: to))
                    orderParents.append(label.order)
                }
                offer(PassengerRouteLabel(state: PassengerRouteState(node: next, onboard: true),
                                          total: label.total + seconds, ride: label.ride + seconds,
                                          wait: label.wait, transfer: label.transfer, walk: label.walk,
                                          changes: label.changes, order: order, previous: index,
                                          arrival: .ride(edge, seconds)))
            }
            // Nobody gets off, changes or walks at a closed station.
            guard isOpen else { continue }
            let path = paths[node.line]
            if path.isRing && node.stop == path.stations.count - 1 {
                // The final call is the starting station, but it ends this
                // train's lap. Crossing to the next lap requires a new wait.
                let wait = max(1, passengerMinutesRoundingUp(path.headway, by: 2)) * GameTime.secondsPerMinute
                let first = PassengerRouteNode(line: node.line, stop: 0, direction: node.direction)
                offer(PassengerRouteLabel(state: PassengerRouteState(node: first, onboard: false),
                                          total: label.total + wait, ride: label.ride,
                                          wait: label.wait + wait, transfer: label.transfer, walk: label.walk,
                                          changes: label.changes, order: label.order,
                                          previous: index, arrival: .board))
            }
            for other in stopsAt[station(node)] ?? [] where other != node {
                guard other.line != node.line else { continue }
                let sameLine = paths[other.line].line == paths[node.line].line
                let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
                // A change of line within a station: the reference's
                // default transfer type for a shared station.
                let transfer: Int64 = sameLine ? 0 : PassengerTransferTier.samePlatform.penaltySeconds
                offer(PassengerRouteLabel(state: PassengerRouteState(node: other, onboard: false),
                                          total: label.total + wait + transfer,
                                          ride: label.ride, wait: label.wait + wait,
                                          transfer: label.transfer + transfer, walk: label.walk,
                                          changes: label.changes + (sameLine ? 0 : 1),
                                          order: label.order, previous: index, arrival: .board))
            }
            // Off the train, a walk to a station nearby and a change there:
            // the walk's time and its tier's transfer penalty (the
            // reference's transfer link, `isXfer`).
            guard label.state.onboard else { continue }
            for walk in walks[here] ?? [] {
                for other in stopsAt[walk.to] ?? [] {
                    let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
                    let transfer = walk.tier.penaltySeconds
                    offer(PassengerRouteLabel(state: PassengerRouteState(node: other, onboard: false),
                                              total: label.total + walk.seconds + transfer + wait,
                                              ride: label.ride, wait: label.wait + wait,
                                              transfer: label.transfer + transfer, walk: label.walk + walk.seconds,
                                              changes: label.changes + 1,
                                              order: label.order, previous: index, arrival: .board))
                }
            }
        }
        return firstAt.mapValues { reconstruct($0, from: labels) }
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
                               transferSeconds: labels[endIndex].transfer,
                               walkSeconds: labels[endIndex].walk), edges)
    }
}

extension GameWorld {
    /// Up to three distinct service paths between two stations, in ascending
    /// whole-minute cost. Ties prefer fewer transfers, then lower unrounded
    /// seconds, then the line and stop order. The graph uses lines with service
    /// planned at the current
    /// minute; it is derived anew when queried. Network passenger demand
    /// stores its chosen route as a journey; legacy direct demand continues
    /// to use `passengerTrip`.
    public func passengerRoutes(from origin: StationID, to destination: StationID, limit: Int = 3) -> [PassengerRoute] {
        guard origin != destination, station(id: origin) != nil, station(id: destination) != nil,
              limit > 0 else { return [] }
        return PassengerRouteGraph(world: self).routes(from: origin, to: destination, limit: limit)
    }

    /// Splits one day's OD demand among the usable route options. Choices
    /// more than five minutes or half the fastest route's cost slower than
    /// the fastest one are omitted. Remaining choices receive inverse-cost
    /// integer weights; largest remainders get the leftover passengers, in
    /// route order. This native policy replaces the reference backend's
    /// unavailable `choiceProb` planner. The result is derived from current
    /// service and is not saved.
    ///
    /// `count` is one day's OD demand, at most the largest daily station demand.
    /// An invalid count or an unreachable pair returns no allocations.
    public func passengerRouteAllocations(
        from origin: StationID, to destination: StationID, count: Int64
    ) -> [PassengerRouteAllocation] {
        guard (1...StationDemand.maximumDailyTrips).contains(count) else { return [] }
        let choices = passengerRouteChoices(from: origin, to: destination)
        let shares = Self.apportion(count, by: choices.map(\.weight))
        return zip(choices, shares).map { PassengerRouteAllocation(route: $0.0.route, count: $0.1) }
    }

    func passengerRouteChoices(from origin: StationID, to destination: StationID) -> [PassengerRouteChoice] {
        guard origin != destination, station(id: origin) != nil, station(id: destination) != nil else { return [] }
        return PassengerRouteGraph(world: self).choices(from: origin, to: destination)
    }
}

extension PassengerRouteGraph {
    /// Up to three distinct service paths (see
    /// ``GameWorld/passengerRoutes(from:to:limit:)``), on this graph. The
    /// stations exist; none between a station and itself.
    func routes(from origin: StationID, to destination: StationID, limit: Int) -> [PassengerRoute] {
        routes(from: origin, to: destination, limit: limit) { shortest(from: origin, to: destination, banning: $0) }
    }

    /// ``routes(from:to:limit:)`` with `shortest` giving the shortest route
    /// to the destination under a set of banned rides.
    private func routes(from origin: StationID, to destination: StationID, limit: Int,
                        shortest: (Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])?) -> [PassengerRoute] {
        guard origin != destination, limit > 0,
              let first = shortest([]) else { return [] }
        var selected = [first.0]
        var candidates: [(route: PassengerRoute, edges: [PassengerRideEdge], bans: Set<PassengerRideEdge>)] = []
        var chosen = (route: first.0, edges: first.1, bans: Set<PassengerRideEdge>())
        var tried: Set<Set<PassengerRideEdge>> = [[]]
        while selected.count < min(limit, 3) {
            for edge in chosen.edges {
                var bans = chosen.bans
                bans.insert(edge)
                guard tried.insert(bans).inserted,
                      let found = shortest(bans),
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

    /// The route choices of an OD pair (see
    /// ``GameWorld/passengerRouteAllocations(from:to:count:)``) on this graph.
    func choices(from origin: StationID, to destination: StationID) -> [PassengerRouteChoice] {
        Self.choices(among: routes(from: origin, to: destination, limit: 3))
    }

    /// Every station's route choices from `origin` (see
    /// ``choices(from:to:)``, which each equals), by station. One search
    /// to every station serves each set of banned rides that any
    /// destination asks for.
    func choices(from origin: StationID, to destinations: [StationID]) -> [StationID: [PassengerRouteChoice]] {
        var searches: [Set<PassengerRideEdge>: [StationID: (PassengerRoute, [PassengerRideEdge])]] = [:]
        var result: [StationID: [PassengerRouteChoice]] = [:]
        for destination in destinations {
            let routes = routes(from: origin, to: destination, limit: 3) { bans in
                if let found = searches[bans] { return found[destination] }
                let found = search(from: origin, to: nil, banning: bans)
                searches[bans] = found
                return found[destination]
            }
            result[destination] = Self.choices(among: routes)
        }
        return result
    }

    private static func choices(among routes: [PassengerRoute]) -> [PassengerRouteChoice] {
        guard let fastest = routes.first?.totalMinutes else { return [] }
        let allowance = max(5, fastest / 2)
        return routes.filter { $0.totalMinutes - fastest <= allowance && $0.legs.count <= 32 }
            .map { PassengerRouteChoice(route: $0, weight: max(1, 10_000 / max(1, $0.totalMinutes))) }
    }
}

/// How a passenger changes trains between two stations (Phase 5F), ported
/// from the owner's `Ci/` reference
/// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`). The tiers are
/// its transfer types by distance (`_classifyMoveTransferDistance` and the
/// classifier in `metroDebugCompareCentralToAirportTimings`): up to
/// `MOVE_TRANSFER_OVERLAP_MAX_M` = 20 m apart ``overlap``, up to
/// `MOVE_TRANSFER_SAME_PLATFORM_MAX_M` = 50 m ``samePlatform``, up to
/// `MOVE_TRANSFER_PASSAGE_MAX_M` = 250 m ``passage``, farther ``virtual``. A
/// change between lines at one station is the reference's default type for
/// a shared station, ``samePlatform``.
///
/// The reference links stations farther than a passage only through a
/// transfer group the player sets up; game stations have none, so walks
/// reach as far as the owner's station transfer data
/// (`Railway/site_archive_clean/data/station_transfers.json`, `criteria`:
/// `haversine_meters < maxDistanceM`, 450 m), measured between the
/// stations' points.
public enum PassengerTransferTier: String, CaseIterable, Sendable {
    case overlap
    case samePlatform
    case passage
    case virtual

    /// The reference's transfer base, 15 minutes (its flow service's
    /// default, `换乘基准` in `metroDebugCompareCentralToAirportTimings`).
    static let baseSeconds: Int64 = 900

    /// The tier's transfer penalty: the base times the reference's factor
    /// (`{overlap: .8, "same-platform": .8, passage: 1.2, virtual: 1.7}`),
    /// exactly in seconds: 720, 720, 1080 and 1530.
    public var penaltySeconds: Int64 {
        switch self {
        case .overlap, .samePlatform: Self.baseSeconds * 8 / 10
        case .passage: Self.baseSeconds * 12 / 10
        case .virtual: Self.baseSeconds * 17 / 10
        }
    }

    /// The tier of stations `squaredDistance` world units² apart, or `nil`
    /// when they are too far apart to walk (450 m or more).
    static func of(squaredDistance: Int64) -> PassengerTransferTier? {
        func within(_ metres: Int64) -> Bool {
            let units = metres * WorldCoordinate.unitsPerMetre
            return squaredDistance <= units * units
        }
        let farthest = maximumWalkMetres * WorldCoordinate.unitsPerMetre
        guard squaredDistance < farthest * farthest else { return nil }
        if within(20) { return .overlap }
        if within(50) { return .samePlatform }
        if within(250) { return .passage }
        return .virtual
    }

    /// Stations closer than this walk to each other (`station_transfers.json`).
    static let maximumWalkMetres: Int64 = 450

    /// The reference walks at 5 km/h between transfer stations
    /// (`metroNavigationTransfers`: metres / (5000 / 3600); its flow
    /// service's `xferWalkSpeedKmh` default): 0.72 s a metre, so 9/800 s a
    /// world unit (64 to the metre). Whole seconds, rounded up.
    static func walkSeconds(squaredDistance: Int64) -> Int64 {
        var units = FixedPoint.squareRoot(squaredDistance)
        if units * units < squaredDistance { units += 1 }
        return (units * 9 + 799) / 800
    }

    /// The least time between getting off one train and boarding the next,
    /// walk included: the reference's `METRO_NAVIGATION_MIN_TRANSFER_SEC`.
    static let minimumChangeSeconds: Int64 = 120
}

extension PassengerRouteGraph {
    /// The walk from station `from` to station `to` in `world`, or `nil`
    /// unless both exist, differ, are open and stand less than 450 m apart.
    static func walk(from: StationID, to: StationID, in world: GameWorld) -> Walk? {
        guard let start = world.station(id: from), let end = world.station(id: to) else { return nil }
        return walk(from: start, to: end)
    }

    private static func walk(from: Station, to: Station) -> Walk? {
        guard from.id != to.id, from.operationMode.allowsService, to.operationMode.allowsService else { return nil }
        let dx = from.point.x - to.point.x
        let dy = from.point.y - to.point.y
        let squared = dx * dx + dy * dy
        guard let tier = PassengerTransferTier.of(squaredDistance: squared) else { return nil }
        return Walk(to: to.id, seconds: PassengerTransferTier.walkSeconds(squaredDistance: squared), tier: tier)
    }
}
