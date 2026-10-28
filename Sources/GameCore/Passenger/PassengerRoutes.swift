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

/// A route between stations, with whole-minute costs. Consecutive legs meet
/// at the same station, or the next leg starts at a station a short walk
/// away (see ``GameWorld/walkingTransfer(from:to:)`` and
/// ``PassengerTransferTier``).
public struct PassengerRoute: Hashable, Sendable {
    public let legs: [PassengerRouteLeg]
    public let rideMinutes: Int64
    public let waitMinutes: Int64
    /// The changes' transfer penalties (see
    /// ``PassengerTransferTier/penaltySeconds``), rounded up to whole
    /// minutes.
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
        zip(legs, legs.dropFirst()).reduce(0) { $0 + ($1.0.line == $1.1.line && $1.0.to == $1.1.from ? 0 : 1) }
    }
}

/// One OD group's passengers assigned to a route. A zero count keeps the
/// route visible when the group is smaller than the number of choices.
public struct PassengerRouteAllocation: Hashable, Sendable {
    public let route: PassengerRoute
    public let count: Int64
}

struct PassengerRouteChoice: Equatable {
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

func passengerRoutePrecedes(_ lhs: PassengerRoute, _ rhs: PassengerRoute) -> Bool {
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
    let walk: Int64
    let changes: Int
    let order: [PassengerRouteOrderLeg]
    let previous: Int?
    let arrival: Arrival
}

struct PassengerRouteGraph: Equatable {
    struct ServicePath: Equatable {
        let line: LineID
        let pattern: Int?
        let direction: LineDirection
        let stations: [StationID]
        let runSeconds: [Int64]
        let headway: Int64
        let isRing: Bool
        /// Passengers its trains carry a day each way (see
        /// ``PassengerCrowding``); 0 for a hand-built graph.
        var dailyCapacity: Int64 = 0
        /// Seconds its trains stay at a call between its ends (decision
        /// 207, ``LineJourney/dwellSeconds``).
        var dwellSeconds: Int64 = GameWorld.defaultDwellSeconds
    }

    typealias Walk = PassengerWalk

    let paths: [ServicePath]
    let stopsAt: [StationID: [PassengerRouteNode]]
    /// From each open served station, the other open served stations a walk
    /// away, by ascending station.
    let walks: [StationID: [Walk]]
    /// Served stations where nobody boards, alights or changes (see
    /// ``StationOperationMode/closed``): trains run through them.
    let closed: Set<StationID>
    /// The same, in arrays for ``PassengerRouteSearch``.
    let lookup: Lookup

    /// The graph's served stations numbered from 0 in the order the paths
    /// first call at them, and what a search asks of each: its calls, its
    /// walks and whether it is closed; and each call's station.
    struct Lookup {
        struct Walk {
            let seconds: Int64
            let penalty: Int64
            let slot: Int
        }

        var slot: [StationID: Int] = [:]
        /// The number of each path's first call; a call's number is its
        /// path's plus its stop.
        var firstNode: [Int] = []
        var nodeSlot: [Int] = []
        var calls: [[PassengerRouteNode]] = []
        var walks: [[Walk]] = []
        var closed: [Bool] = []

        init(paths: [ServicePath], stopsAt: [StationID: [PassengerRouteNode]],
             walks: [StationID: [PassengerWalk]], closed: Set<StationID>) {
            var stations: [StationID] = []
            for path in paths {
                firstNode.append(nodeSlot.count)
                for station in path.stations {
                    if slot[station] == nil {
                        slot[station] = stations.count
                        stations.append(station)
                    }
                    nodeSlot.append(slot[station]!)
                }
            }
            calls = stations.map { stopsAt[$0] ?? [] }
            self.closed = stations.map { closed.contains($0) }
            self.walks = stations.map { station in
                (walks[station] ?? []).compactMap { walk in
                    slot[walk.to].map { Walk(seconds: walk.seconds, penalty: walk.tier.penaltySeconds, slot: $0) }
                }
            }
        }
    }

    /// The calls are derived from the paths.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.paths == rhs.paths && lhs.walks == rhs.walks && lhs.closed == rhs.closed
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
        lookup = Lookup(paths: included, stopsAt: calls, walks: walks, closed: closed)
    }

    init(world: GameWorld) {
        var included: [ServicePath] = []
        var calls: [StationID: [PassengerRouteNode]] = [:]
        for line in world.lines where !line.isFreight {
            guard let level = world.serviceLevel(of: line.id, at: world.clock.now) else { continue }
            // What `lineHeadway` and `lineJourney` give for each service,
            // driving each service once: a service's plan depends on its
            // own and the earlier services' round trips and capacities.
            let journeys = (0..<line.serviceCount).map { world.journey(of: line, service: $0) }
            let capacities = world.capacityProfiles(of: line, journeys: journeys)
            for service in 0..<line.serviceCount {
                let pattern = service == 0 ? nil : service - 1
                let plans = line.services(at: level, roundTrips: journeys.prefix(service + 1).map { $0?.roundTripMinutes },
                                          capacities: Array(capacities.prefix(service + 1))).plans
                guard let headway = plans[service]?.headway, let journey = journeys[service] else { continue }
                let assigned = line.trains(ofService: service).compactMap { world.train(id: $0)?.capacity }.max()
                let anyTrain = (line.trains + line.patterns.flatMap(\.trains)).compactMap { world.train(id: $0)?.capacity }.max()
                let capacity = PassengerCrowding.dailyCapacity(
                    window: line.window, day: world.serviceDay,
                    capacity: assigned ?? anyTrain ?? PassengerCrowding.defaultTrainCapacity
                ) { level in
                    line.services(at: level, roundTrips: journeys.prefix(service + 1).map { $0?.roundTripMinutes },
                                  capacities: Array(capacities.prefix(service + 1))).plans[service]?.headway
                }
                if line.isRing {
                    for direction in [RingDirection.inner, .outer] where line.ringWayRuns(direction) {
                        guard let lap = direction == .inner ? journey : world.journey(of: line, service: service, direction: .outer) else { continue }
                        let stationIDs = line.ringCalls(direction).map { line.stops[$0] }
                        let path = ServicePath(line: line.id, pattern: nil,
                                               direction: direction == .inner ? .outbound : .inbound,
                                               stations: stationIDs, runSeconds: lap.legs.map(\.seconds),
                                               headway: headway, isRing: true, dailyCapacity: capacity, dwellSeconds: lap.dwellSeconds)
                        Self.add(path, to: &included, calls: &calls)
                    }
                } else if line.hasRuns {
                    // Decision 149: a line with runs (its own service only,
                    // calling at every stop) rides only the stretches its
                    // runs go, each way.
                    let count = line.stops.count
                    let out = Array(journey.legs.prefix(count - 1).map(\.seconds))
                    let back = Array(journey.legs.suffix(count - 1).map(\.seconds))
                    // A leg between each pair of stops each way.
                    guard out.count == count - 1, back.count == count - 1 else { continue }
                    for stretch in line.runStretches(outbound: true) {
                        Self.add(ServicePath(line: line.id, pattern: nil, direction: .outbound,
                                             stations: stretch.map { line.stops[$0] },
                                             runSeconds: Array(out[stretch.lowerBound..<stretch.upperBound]),
                                             headway: headway, isRing: false, dailyCapacity: capacity, dwellSeconds: journey.dwellSeconds),
                                 to: &included, calls: &calls)
                    }
                    for stretch in line.runStretches(outbound: false) {
                        // Back from the stretch's last stop to its first:
                        // the legs back are in the reversed order.
                        Self.add(ServicePath(line: line.id, pattern: nil, direction: .inbound,
                                             stations: stretch.reversed().map { line.stops[$0] },
                                             runSeconds: Array(back[(count - 1 - stretch.upperBound)..<(count - 1 - stretch.lowerBound)]),
                                             headway: headway, isRing: false, dailyCapacity: capacity, dwellSeconds: journey.dwellSeconds),
                                 to: &included, calls: &calls)
                    }
                } else {
                    let callIndices = line.calls(ofService: service)
                    let half = callIndices.count - 1
                    let forward = ServicePath(line: line.id, pattern: pattern, direction: .outbound,
                                              stations: callIndices.map { line.stops[$0] },
                                              runSeconds: Array(journey.legs.prefix(half).map(\.seconds)),
                                              headway: headway, isRing: false, dailyCapacity: capacity, dwellSeconds: journey.dwellSeconds)
                    let backward = ServicePath(line: line.id, pattern: pattern, direction: .inbound,
                                               stations: callIndices.reversed().map { line.stops[$0] },
                                               runSeconds: Array(journey.legs.suffix(half).map(\.seconds)),
                                               headway: headway, isRing: false, dailyCapacity: capacity, dwellSeconds: journey.dwellSeconds)
                    Self.add(forward, to: &included, calls: &calls)
                    Self.add(backward, to: &included, calls: &calls)
                }
            }
        }
        paths = included
        stopsAt = calls
        var walks: [StationID: [Walk]] = [:]
        let served = world.stations.filter { calls[$0.id] != nil }.sorted { $0.id < $1.id }
        closed = Set(served.filter { !$0.operationMode.allowsService }.map(\.id))
        let open = served.filter(\.operationMode.allowsService)
        for from in open {
            for to in open where to.id != from.id {
                if let walk = PassengerWalk(from: from.point, to: to.point, station: to.id,
                                            linked: world.areLinkedForTransfer(from.id, to.id)) {
                    walks[from.id, default: []].append(walk)
                }
            }
        }
        self.walks = walks
        lookup = Lookup(paths: included, stopsAt: calls, walks: walks, closed: closed)
    }

    private static func add(_ path: ServicePath, to paths: inout [ServicePath], calls: inout [StationID: [PassengerRouteNode]]) {
        let index = paths.count
        paths.append(path)
        for (stop, station) in path.stations.enumerated() {
            calls[station, default: []].append(PassengerRouteNode(line: index, stop: stop,
                                                                    direction: path.direction == .outbound ? 1 : -1))
        }
    }

    fileprivate func station(_ node: PassengerRouteNode) -> StationID {
        paths[node.line].stations[node.stop]
    }

    fileprivate func nextRide(_ node: PassengerRouteNode) -> (PassengerRouteNode, PassengerRideEdge, Int64)? {
        let path = paths[node.line]
        let next = node.stop + 1
        guard next < path.stations.count else { return nil }
        let edge = PassengerRideEdge(line: node.line, from: node.stop, to: next, direction: node.direction)
        return (PassengerRouteNode(line: node.line, stop: next, direction: node.direction), edge,
                path.runSeconds[node.stop])
    }

    /// The cheapest route from `origin` to `destination` with the rides in
    /// `forbidden` banned: a ``PassengerRouteSearch`` asked once.
    func shortest(from origin: StationID, to destination: StationID, banning forbidden: Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])? {
        var search = PassengerRouteSearch(graph: self, from: origin, banning: forbidden)
        return search.route(to: destination)
    }

    fileprivate func reconstruct(_ endIndex: Int, from labels: [PassengerRouteLabel]) -> (PassengerRoute, [PassengerRideEdge]) {
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

/// Dijkstra over service calls and boarding state, from one origin with
/// some rides banned. Each state keeps the nondominated (elapsed seconds,
/// line changes) labels, since rounding to whole minutes can favor a later
/// arrival with fewer changes. Exact metric ties keep the lower full-route
/// line/stop order.
///
/// Nothing in the search but where it stops depends on the destination: a
/// route to a station is the first label that arrives there aboard. So one
/// search answers every destination, in the order it reaches them, and is
/// resumed where it stopped for the next one; each answer is exactly the
/// one a search for that destination alone finds (派工單 AQ: a day's plan
/// asked tens of thousands of searches that were the same but for their
/// destination).
struct PassengerRouteSearch {
    /// Where ``run(until:pausing:)`` stopped.
    enum Stop {
        /// Label `index` is the first to arrive at the target station.
        case arrived(Int)
        case exhausted
        /// Paused before the first label at call `number` is expanded.
        case firstExpansion(Int)
    }

    private let graph: PassengerRouteGraph
    /// The calls whose ride to the next call is banned, by number (see
    /// ``PassengerRouteGraph/Lookup/firstNode``).
    var banned: [Int] = []
    private var labels: [PassengerRouteLabel] = []
    /// Each state's labels no other label dominates: a state is its call's
    /// number, twice, plus one aboard.
    private var frontier: [[Int]]
    private var active: [Bool] = []
    /// A binary heap of open labels under one strict total order, so it
    /// pops exactly the label a full sort would put first.
    private var open: [Int] = []
    /// The first label to arrive at each station aboard, by station slot;
    /// -1 before one has.
    private var arrived: [Int]
    /// Whether a label at each call, by number, has been expanded.
    private var expanded: [Bool]
    /// A label popped and not expanded yet: the search paused before it.
    private var pending: Int?

    init(graph: PassengerRouteGraph, from origin: StationID, banning forbidden: Set<PassengerRideEdge>) {
        self.graph = graph
        let lookup = graph.lookup
        banned = Self.calls(banned: forbidden, on: graph)
        frontier = Array(repeating: [], count: 2 * lookup.nodeSlot.count)
        arrived = Array(repeating: -1, count: lookup.calls.count)
        expanded = Array(repeating: false, count: lookup.nodeSlot.count)
        guard let slot = lookup.slot[origin], !lookup.closed[slot] else { return }
        for node in lookup.calls[slot] {
            let wait = max(1, passengerMinutesRoundingUp(graph.paths[node.line].headway, by: 2)) * GameTime.secondsPerMinute
            offer(PassengerRouteLabel(state: PassengerRouteState(node: node, onboard: false),
                                      total: wait, ride: 0, wait: wait, transfer: 0, walk: 0,
                                      changes: 0, order: [], previous: nil, arrival: .board))
        }
    }

    /// The calls, by number, whose rides to the next call are the edges
    /// `forbidden` (see `PassengerRouteGraph.nextRide`); an edge no ride is
    /// bans nothing.
    static func calls(banned forbidden: Set<PassengerRideEdge>, on graph: PassengerRouteGraph) -> [Int] {
        forbidden.compactMap { edge in
            guard graph.paths.indices.contains(edge.line), edge.to == edge.from + 1,
                  graph.paths[edge.line].stations.indices.contains(edge.to),
                  edge.direction == (graph.paths[edge.line].direction == .outbound ? 1 : -1) else { return nil }
            return graph.lookup.firstNode[edge.line] + edge.from
        }
    }

    /// The cheapest route to `destination`, searching on from where the
    /// last question stopped if it has not been reached yet.
    mutating func route(to destination: StationID) -> (PassengerRoute, [PassengerRideEdge])? {
        guard let target = slot(of: destination) else { return nil }
        if arrived[target] >= 0 { return graph.reconstruct(arrived[target], from: labels) }
        guard case .arrived(let index) = run(until: target, pausing: false) else { return nil }
        return graph.reconstruct(index, from: labels)
    }

    /// The station slot of `destination`, or `nil` if no route can end
    /// there.
    func slot(of destination: StationID) -> Int? {
        guard let target = graph.lookup.slot[destination], !graph.lookup.closed[target] else { return nil }
        return target
    }

    /// The route ending with label `index`.
    func route(ending index: Int) -> (PassengerRoute, [PassengerRideEdge]) {
        graph.reconstruct(index, from: labels)
    }

    /// How many labels it holds: what a copy of it costs.
    var size: Int { labels.count }

    /// The first label to arrive at station slot `target`, if one has.
    func arrival(at target: Int) -> Int? {
        arrived[target] >= 0 ? arrived[target] : nil
    }

    /// Searches on until the first label arrives aboard at station slot
    /// `target` (-1: none), or until there is nothing left. When `pausing`,
    /// it also stops before expanding a call for the first time, holding
    /// that label for the next run: a search banning that call's ride is
    /// this one up to here.
    mutating func run(until target: Int, pausing: Bool) -> Stop {
        let lookup = graph.lookup
        while true {
            let index: Int
            if let held = pending {
                index = held
                pending = nil
            } else {
                guard let next = popFirst() else { return .exhausted }
                guard active[next] else { continue }
                index = next
                // Only a ride arrives: a walk ends where another ride starts.
                let state = labels[index].state
                if state.onboard {
                    let slot = lookup.nodeSlot[lookup.firstNode[state.node.line] + state.node.stop]
                    if arrived[slot] < 0 { arrived[slot] = index }
                }
            }
            let node = labels[index].state.node
            let number = lookup.firstNode[node.line] + node.stop
            if pausing && !expanded[number] {
                expanded[number] = true
                pending = index
                return .firstExpansion(number)
            }
            expanded[number] = true
            // A search for this destination alone stops here, after
            // arriving; another goes on from this label.
            expand(index)
            if target >= 0 && arrived[target] == index { return .arrived(index) }
        }
    }

    private func state(_ state: PassengerRouteState) -> Int {
        2 * (graph.lookup.firstNode[state.node.line] + state.node.stop) + (state.onboard ? 1 : 0)
    }

    private func precedes(_ a: Int, _ b: Int) -> Bool {
        // Field by field: a copy of a whole label would retain its order.
        let leftTotal = labels[a].total
        let rightTotal = labels[b].total
        let leftMinutes = passengerMinutesRoundingUp(leftTotal, by: GameTime.secondsPerMinute)
        let rightMinutes = passengerMinutesRoundingUp(rightTotal, by: GameTime.secondsPerMinute)
        if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }
        let leftChanges = labels[a].changes
        let rightChanges = labels[b].changes
        if leftChanges != rightChanges { return leftChanges < rightChanges }
        if leftTotal != rightTotal { return leftTotal < rightTotal }
        if passengerRouteOrderPrecedes(labels[a].order, labels[b].order) { return true }
        if passengerRouteOrderPrecedes(labels[b].order, labels[a].order) { return false }
        let left = labels[a].state
        let right = labels[b].state
        if left.node != right.node { return left.node < right.node }
        if left.onboard != right.onboard { return !left.onboard }
        return a < b
    }

    private mutating func push(_ index: Int) {
        open.append(index)
        var child = open.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard precedes(open[child], open[parent]) else { break }
            open.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func popFirst() -> Int? {
        guard let first = open.first else { return nil }
        let last = open.removeLast()
        if !open.isEmpty {
            open[0] = last
            var parent = 0
            while true {
                let left = 2 * parent + 1
                guard left < open.count else { break }
                var best = left
                if left + 1 < open.count, precedes(open[left + 1], open[left]) { best = left + 1 }
                guard precedes(open[best], open[parent]) else { break }
                open.swapAt(best, parent)
                parent = best
            }
        }
        return first
    }

    /// Whether label `index` dominates `label`, or (`reversed`) `label`
    /// dominates it.
    private func dominates(_ index: Int, _ label: PassengerRouteLabel, reversed: Bool = false) -> Bool {
        let (lhsTotal, rhsTotal) = reversed ? (label.total, labels[index].total) : (labels[index].total, label.total)
        let (lhsChanges, rhsChanges) = reversed ? (label.changes, labels[index].changes) : (labels[index].changes, label.changes)
        guard lhsTotal <= rhsTotal, lhsChanges <= rhsChanges else { return false }
        if lhsTotal < rhsTotal || lhsChanges < rhsChanges { return true }
        return reversed ? !passengerRouteOrderPrecedes(labels[index].order, label.order)
            : !passengerRouteOrderPrecedes(label.order, labels[index].order)
    }

    private mutating func offer(_ label: PassengerRouteLabel) {
        let slot = state(label.state)
        if frontier[slot].contains(where: { dominates($0, label) }) { return }
        // Kept in their order, the new one last, in place.
        var survivors = frontier[slot]
        frontier[slot] = []
        var kept = 0
        for index in survivors {
            if dominates(index, label, reversed: true) {
                active[index] = false
            } else {
                survivors[kept] = index
                kept += 1
            }
        }
        survivors.removeLast(survivors.count - kept)
        let index = labels.count
        labels.append(label)
        active.append(true)
        push(index)
        survivors.append(index)
        frontier[slot] = survivors
    }

    /// Offers every label one step on from label `index`.
    private mutating func expand(_ index: Int) {
        let label = labels[index]
        let node = label.state.node
        let paths = graph.paths
        let lookup = graph.lookup
        let number = lookup.firstNode[node.line] + node.stop
        if let (next, edge, run) = graph.nextRide(node), !banned.contains(number) {
            // A passenger already aboard stays through this stop's
            // dwell. One boarding here has waited for departure already.
            let dwell = label.state.onboard ? paths[edge.line].dwellSeconds : 0
            let seconds = run + dwell
            let ridePath = paths[edge.line]
            let to = ridePath.stations[edge.to]
            var order = label.order
            if label.state.onboard, let last = order.last {
                order[order.count - 1] = PassengerRouteOrderLeg(line: last.line, from: last.from, to: to)
            } else {
                order.append(PassengerRouteOrderLeg(line: ridePath.line,
                                                    from: ridePath.stations[edge.from], to: to))
            }
            offer(PassengerRouteLabel(state: PassengerRouteState(node: next, onboard: true),
                                      total: label.total + seconds, ride: label.ride + seconds,
                                      wait: label.wait, transfer: label.transfer, walk: label.walk,
                                      changes: label.changes, order: order, previous: index,
                                      arrival: .ride(edge, seconds)))
        }
        // Nobody gets off, changes or walks at a closed station: trains
        // run through it (the reference's
        // `metroStationAllowsTrainServiceAtStation`,
        // `metroStationAllowsTransfer`).
        let station = lookup.nodeSlot[number]
        guard !lookup.closed[station] else { return }
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
        for other in lookup.calls[station] where other != node {
            guard other.line != node.line else { continue }
            let sameLine = paths[other.line].line == paths[node.line].line
            let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
            // A change of line within a station: the reference's
            // default transfer type for one station, same-platform.
            let transfer: Int64 = sameLine ? 0 : PassengerTransferTier.samePlatform.penaltySeconds
            offer(PassengerRouteLabel(state: PassengerRouteState(node: other, onboard: false),
                                      total: label.total + wait + transfer,
                                      ride: label.ride, wait: label.wait + wait,
                                      transfer: label.transfer + transfer, walk: label.walk,
                                      changes: label.changes + (sameLine ? 0 : 1),
                                      order: label.order, previous: index, arrival: .board))
        }
        // A passenger who has just got off may walk to a station near
        // by and wait there for another ride: never at the start of a
        // journey, nor twice in a row. The walk costs its time and its
        // tier's transfer penalty (the reference's transfer link,
        // `isXfer`).
        guard label.state.onboard else { return }
        for walk in lookup.walks[station] {
            for other in lookup.calls[walk.slot] {
                let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
                offer(PassengerRouteLabel(state: PassengerRouteState(node: other, onboard: false),
                                          total: label.total + wait + walk.penalty + walk.seconds,
                                          ride: label.ride, wait: label.wait + wait,
                                          transfer: label.transfer + walk.penalty, walk: label.walk + walk.seconds,
                                          changes: label.changes + 1,
                                          order: label.order, previous: index, arrival: .board))
            }
        }
    }
}

/// The searches of one plan, kept for the origin last asked: the routes
/// from it with each set of rides banned (see
/// ``GameWorld/passengerRoutes(from:to:limit:searches:)``). A plan asks
/// its pairs origin by origin, so a new origin drops the last one's.
///
/// A search banning some rides is the one banning none up to the first
/// time it would take one of them: the unbanned search keeps a copy of
/// itself paused before some calls' first expansions, and a banned one
/// starts from the latest copy before the earliest banned call, run on
/// to that call. Nothing differs from starting it afresh but the work.
///
/// Each copy is a whole search, so they are held to a number (派工單 BB:
/// a copy at every call took a game of 200 stations past 1.4 GB): copies
/// every `spacing` calls, the spacing doubling when they would pass
/// `checkpointLimit`, and the banned searches asked most lately, at most
/// `searchLimit` of them and `labelBudget` labels together. A dropped
/// one starts again when asked.
struct PassengerRouteSearches {
    let graph: PassengerRouteGraph
    /// At most this many copies of the unbanned search are kept.
    let checkpointLimit: Int
    /// At most this many banned searches are kept.
    let searchLimit: Int
    /// The banned searches kept hold at most this many labels, but for
    /// the one asked last.
    let labelBudget: Int
    private var origin: StationID?
    private var unbanned: PassengerRouteSearch?
    /// The order in which the unbanned search first reached each call, by
    /// number; -1 before it has.
    private var reached: [Int] = []
    /// How many calls the unbanned search has reached.
    private var reachedCount = 0
    /// The unbanned search paused before the first expansion of its call
    /// `order`, every `spacing` calls, in order.
    private var checkpoints: [(order: Int, search: PassengerRouteSearch)] = []
    private var spacing = 1
    private var searches: [Set<PassengerRideEdge>: PassengerRouteSearch] = [:]
    /// The keys of `searches`, the one asked longest ago first.
    private var searchOrder: [Set<PassengerRideEdge>] = []

    init(graph: PassengerRouteGraph, checkpointLimit: Int = 16, searchLimit: Int = 512,
         labelBudget: Int = 400_000) {
        self.graph = graph
        self.checkpointLimit = max(1, checkpointLimit)
        self.searchLimit = max(1, searchLimit)
        self.labelBudget = max(0, labelBudget)
    }

    /// How many whole searches are kept besides the unbanned one.
    var copies: Int { checkpoints.count + searches.count }

    /// How many banned searches are kept.
    var bannedSearches: Int { searches.count }

    /// The labels of the banned searches kept.
    var bannedLabels: Int { searches.values.reduce(0) { $0 + $1.size } }

    /// What ``PassengerRouteGraph/shortest(from:to:banning:)`` gives.
    mutating func shortest(from origin: StationID, to destination: StationID,
                           banning forbidden: Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])? {
        if origin != self.origin {
            self.origin = origin
            unbanned = PassengerRouteSearch(graph: graph, from: origin, banning: [])
            reached = Array(repeating: -1, count: graph.lookup.nodeSlot.count)
            reachedCount = 0
            checkpoints = []
            spacing = 1
            searches = [:]
            searchOrder = []
        }
        guard !forbidden.isEmpty else {
            guard let target = unbanned!.slot(of: destination) else { return nil }
            if let index = unbanned!.arrival(at: target) { return unbanned!.route(ending: index) }
            guard case .arrived(let index) = runUnbanned(until: target, orBefore: []) else { return nil }
            return unbanned!.route(ending: index)
        }
        if searches[forbidden] == nil {
            if searches.count >= searchLimit {
                searches[searchOrder.removeFirst()] = nil
            }
            searches[forbidden] = start(banning: forbidden)
        } else {
            searchOrder.remove(at: searchOrder.firstIndex(of: forbidden)!)
        }
        searchOrder.append(forbidden)
        let found = searches[forbidden]!.route(to: destination)
        var held = bannedLabels
        while held > labelBudget && searchOrder.count > 1 {
            held -= searches.removeValue(forKey: searchOrder.removeFirst())!.size
        }
        return found
    }

    /// Runs the unbanned search on, noting each call's first expansion,
    /// until it arrives at slot `target` or reaches one of the calls
    /// `calls` for the first time.
    private mutating func runUnbanned(until target: Int, orBefore calls: [Int]) -> PassengerRouteSearch.Stop {
        while true {
            let stop = unbanned!.run(until: target, pausing: true)
            guard case .firstExpansion(let number) = stop else { return stop }
            let order = reachedCount
            reached[number] = order
            reachedCount += 1
            if order % spacing == 0 {
                checkpoints.append((order, unbanned!))
                if checkpoints.count > checkpointLimit {
                    spacing *= 2
                    checkpoints.removeAll { $0.order % spacing != 0 }
                }
            }
            if calls.contains(number) { return stop }
        }
    }

    /// The unbanned search paused before the first expansion of its call
    /// `order`: the latest copy before it, run on to it.
    private func paused(at order: Int) -> PassengerRouteSearch {
        let checkpoint = checkpoints.last { $0.order <= order }!
        var search = checkpoint.search
        for _ in checkpoint.order..<order {
            guard case .firstExpansion = search.run(until: -1, pausing: true) else {
                preconditionFailure("the unbanned search reached call \(order) before")
            }
        }
        return search
    }

    /// A search banning `forbidden`, as far on as the unbanned one is the
    /// same.
    private mutating func start(banning forbidden: Set<PassengerRideEdge>) -> PassengerRouteSearch {
        let calls = PassengerRouteSearch.calls(banned: forbidden, on: graph)
        func earliest() -> PassengerRouteSearch? {
            calls.map { reached[$0] }.filter { $0 >= 0 }.min().map(paused(at:))
        }
        var search: PassengerRouteSearch
        if calls.isEmpty {
            search = unbanned!
        } else if let known = earliest() {
            search = known
        } else if case .exhausted = runUnbanned(until: -1, orBefore: calls) {
            // It never takes a banned ride.
            search = unbanned!
        } else {
            // Paused before the first banned call it reaches.
            search = unbanned!
        }
        search.banned = calls
        return search
    }
}

extension GameWorld {
    /// How far apart two stations may stand, at most, for passengers to walk
    /// between them to change trains (strictly less):
    /// ``PassengerTransferRules/maximumWalkMetres``.
    public static var walkingTransferMetres: Int64 { PassengerTransferRules.maximumWalkMetres }

    /// The walk from station `origin` to `destination`, another station
    /// less than ``walkingTransferMetres`` away or in its transfer group
    /// (decision 81): its time at the reference's 5 km/h and its transfer
    /// tier (see ``PassengerWalk``). `nil` for the same station, a station
    /// that does not exist, or one too far away and not in its group. The stations' operation modes are not read: the route
    /// graph walks only between open stations, and a journey's walk to or
    /// from a closed one is ended where it is served.
    public func walkingTransfer(from origin: StationID, to destination: StationID) -> PassengerWalk? {
        guard origin != destination, let from = station(id: origin), let to = station(id: destination) else { return nil }
        return PassengerWalk(from: from.point, to: to.point, station: destination,
                             linked: areLinkedForTransfer(origin, destination))
    }

    /// Whether a journey may go on from `previous` to `next`: from the same
    /// station, or by a walk to a station near by.
    func connects(_ previous: PassengerJourneyLeg, to next: PassengerJourneyLeg) -> Bool {
        previous.to == next.from || walkingTransfer(from: previous.to, to: next.from) != nil
    }

    /// Up to three distinct service paths between two stations, in ascending
    /// whole-minute cost. Ties prefer fewer transfers, then lower unrounded
    /// seconds, then the line and stop order. The graph uses lines with service
    /// planned at the current
    /// minute; it is derived anew when queried. Network passenger demand
    /// stores its chosen route as a journey; legacy direct demand continues
    /// to use `passengerTrip`.
    public func passengerRoutes(from origin: StationID, to destination: StationID, limit: Int = 3) -> [PassengerRoute] {
        passengerRoutes(from: origin, to: destination, limit: limit, graph: nil)
    }

    /// The same, on `graph` when given: a graph derived from this world at
    /// this minute, shared by every pair of one passenger plan.
    func passengerRoutes(from origin: StationID, to destination: StationID, limit: Int = 3,
                         graph shared: PassengerRouteGraph?) -> [PassengerRoute] {
        guard origin != destination, station(id: origin) != nil, station(id: destination) != nil,
              limit > 0 else { return [] }
        var searches = PassengerRouteSearches(graph: shared ?? PassengerRouteGraph(world: self))
        return passengerRoutes(from: origin, to: destination, limit: limit, searches: &searches)
    }

    /// The same, on the graph of `searches`, asking it for the searches
    /// from `origin`: it keeps them for the next destination.
    func passengerRoutes(from origin: StationID, to destination: StationID, limit: Int = 3,
                         searches: inout PassengerRouteSearches) -> [PassengerRoute] {
        guard origin != destination, station(id: origin) != nil, station(id: destination) != nil,
              limit > 0 else { return [] }
        guard let first = searches.shortest(from: origin, to: destination, banning: []) else { return [] }
        var selected = [first.0]
        var candidates: [(route: PassengerRoute, edges: [PassengerRideEdge], bans: Set<PassengerRideEdge>)] = []
        var chosen = (route: first.0, edges: first.1, bans: Set<PassengerRideEdge>())
        var tried: Set<Set<PassengerRideEdge>> = [[]]
        while selected.count < min(limit, 3) {
            for edge in chosen.edges {
                var bans = chosen.bans
                bans.insert(edge)
                guard tried.insert(bans).inserted,
                      let found = searches.shortest(from: origin, to: destination, banning: bans),
                      !selected.contains(found.0), !candidates.contains(where: { $0.route == found.0 })
                else { continue }
                candidates.append((found.0, found.1, bans))
            }
            guard !candidates.isEmpty else { break }
            candidates.sort { passengerRoutePrecedes($0.route, $1.route) }
            chosen = candidates.removeFirst()
            selected.append(chosen.route)
        }
        // The search ranks by the whole minutes of the total seconds; a
        // route's cost rounds each part up (a walk, or a penalty that is
        // not whole minutes), which can put a later route first.
        return selected.sorted(by: passengerRoutePrecedes)
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

    func passengerRouteChoices(from origin: StationID, to destination: StationID,
                               graph: PassengerRouteGraph? = nil) -> [PassengerRouteChoice] {
        var searches = PassengerRouteSearches(graph: graph ?? PassengerRouteGraph(world: self))
        return passengerRouteChoices(from: origin, to: destination, searches: &searches)
    }

    /// The same, keeping the searches from `origin` in `searches` for the
    /// next destination.
    func passengerRouteChoices(from origin: StationID, to destination: StationID,
                               searches: inout PassengerRouteSearches) -> [PassengerRouteChoice] {
        let routes = passengerRoutes(from: origin, to: destination, searches: &searches)
        guard let fastest = routes.first?.totalMinutes else { return [] }
        let allowance = max(5, fastest / 2)
        return routes.filter { $0.totalMinutes - fastest <= allowance && $0.legs.count <= 32 }
            .map { PassengerRouteChoice(route: $0, weight: max(1, 10_000 / max(1, $0.totalMinutes))) }
    }
}

/// The route choices already worked out on one derived graph. Not game
/// state: never saved, and two worlds compare equal whatever it holds. The
/// choices are a pure function of the graph, so keeping them while the
/// graph is unchanged gives exactly what working them out again would.
struct PassengerRouteMemo: Equatable, Sendable {
    struct Pair: Hashable, Sendable {
        let origin: StationID
        let destination: StationID
    }

    var graph: PassengerRouteGraph?
    var choices: [Pair: [PassengerRouteChoice]] = [:]

    static func == (_: Self, _: Self) -> Bool {
        true
    }

    /// Keeps the choices only if `graph` is the one they were worked out on.
    mutating func use(_ graph: PassengerRouteGraph) {
        guard self.graph != graph else { return }
        self.graph = graph
        choices = [:]
    }
}

/// Every constant of changing trains (Phase 5F), in one place so that a
/// balance change is a one-line edit. Each is ported from the owner's `Ci/`
/// reference (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`) or
/// the `Railway/` site, cited where it is defined.
///
/// Two different things are made from them:
///
/// - The **perceived cost** of a change in route choice: the transfer
///   penalty of its tier (``PassengerTransferTier/penaltySeconds``, 12
///   minutes for a change of line at one station) plus, for a change
///   between stations, the walk. Passengers weigh routes by it; it never
///   delays anyone.
/// - The **actual delay** before a passenger who changed may board:
///   ``minimumChangeSeconds`` or the walk, whichever is longer (none for
///   another train of the same line at the same station).
public enum PassengerTransferRules {
    /// The transfer base the tier factors multiply: 15 minutes (`换乘基准`,
    /// `r = 15` in `metroDebugCompareCentralToAirportTimings`, "the same as
    /// the flow service's default").
    public static let baseSeconds: Int64 = 900

    /// The tier factors, in tenths of ``baseSeconds``: the reference's
    /// `{overlap: .8, "same-platform": .8, passage: 1.2, virtual: 1.7}`
    /// (`metroDebugCompareCentralToAirportTimings`).
    public static let overlapFactorTenths: Int64 = 8
    public static let samePlatformFactorTenths: Int64 = 8
    public static let passageFactorTenths: Int64 = 12
    public static let virtualFactorTenths: Int64 = 17

    /// The tiers' distance limits, inclusive: `MOVE_TRANSFER_OVERLAP_MAX_M`
    /// = 20, `MOVE_TRANSFER_SAME_PLATFORM_MAX_M` = 50 and
    /// `MOVE_TRANSFER_PASSAGE_MAX_M` = 250 (`_classifyMoveTransferDistance`);
    /// farther is `virtual`.
    public static let overlapMaximumMetres: Int64 = 20
    public static let samePlatformMaximumMetres: Int64 = 50
    public static let passageMaximumMetres: Int64 = 250

    /// Stations strictly closer than this walk to each other: 450 m, the
    /// `Railway/` site's transfer rule
    /// (`Railway/site_archive_clean/data/station_transfers.json`,
    /// `criteria.maxDistanceM`, `haversine_meters < maxDistanceM`), here on
    /// the world's plane. (The `Ci/` reference links stations beyond a
    /// passage only through a transfer group the player sets up; game
    /// stations have none.)
    public static let maximumWalkMetres: Int64 = 450

    /// Walking speed between stations: 5 km/h (`metroNavigationTransfers`,
    /// `haversine / (5e3 / 3600)`; `n = 5` in
    /// `metroDebugCompareCentralToAirportTimings`, "the same as the flow
    /// service's default").
    public static let walkingMetresPerHour: Int64 = 5_000

    /// The least time between getting off one train and boarding another
    /// line's, walk included: `METRO_NAVIGATION_MIN_TRANSFER_SEC` = 120.
    /// The actual delay; never part of the perceived cost.
    public static let minimumChangeSeconds: Int64 = 120
}

/// A change of trains' transfer type by distance (Phase 5F, see
/// ``PassengerTransferRules``): `_classifyMoveTransferDistance` and the
/// classifier of `metroDebugCompareCentralToAirportTimings`. A change
/// between lines at one station is the reference's default type for one
/// station, ``samePlatform``.
public enum PassengerTransferTier: String, CaseIterable, Sendable {
    case overlap
    case samePlatform
    case passage
    case virtual

    /// The tier's transfer penalty, a perceived route-choice cost only:
    /// ``PassengerTransferRules/baseSeconds`` times the tier's factor,
    /// exactly in seconds (720, 720, 1080 and 1530 with the reference's
    /// values).
    public var penaltySeconds: Int64 {
        let tenths = switch self {
        case .overlap: PassengerTransferRules.overlapFactorTenths
        case .samePlatform: PassengerTransferRules.samePlatformFactorTenths
        case .passage: PassengerTransferRules.passageFactorTenths
        case .virtual: PassengerTransferRules.virtualFactorTenths
        }
        return PassengerTransferRules.baseSeconds * tenths / 10
    }

    /// The tier of stations `squaredDistance` world units² apart, or `nil`
    /// when they are too far apart to walk
    /// (``PassengerTransferRules/maximumWalkMetres`` or more).
    static func of(squaredDistance: Int64) -> PassengerTransferTier? {
        func within(_ metres: Int64) -> Bool {
            let units = metres * WorldCoordinate.unitsPerMetre
            return squaredDistance <= units * units
        }
        let farthest = PassengerTransferRules.maximumWalkMetres * WorldCoordinate.unitsPerMetre
        guard squaredDistance < farthest * farthest else { return nil }
        if within(PassengerTransferRules.overlapMaximumMetres) { return .overlap }
        if within(PassengerTransferRules.samePlatformMaximumMetres) { return .samePlatform }
        if within(PassengerTransferRules.passageMaximumMetres) { return .passage }
        return .virtual
    }

    /// The walk across `squaredDistance` world units² at
    /// ``PassengerTransferRules/walkingMetresPerHour``, in whole seconds
    /// rounded up (5 km/h: 0.72 s a metre, 9/800 s a world unit).
    static func walkSeconds(squaredDistance: Int64) -> Int64 {
        var units = FixedPoint.squareRoot(squaredDistance)
        if units * units < squaredDistance { units += 1 }
        let perHour = PassengerTransferRules.walkingMetresPerHour * WorldCoordinate.unitsPerMetre
        let numerator = units * GameTime.secondsPerHour
        return (numerator + perHour - 1) / perHour
    }
}

/// A walk from a station to another one nearby, to change trains there
/// (Phase 5F): how long it takes and its transfer tier. Derived from the
/// stations' points; never saved.
public struct PassengerWalk: Hashable, Sendable {
    /// The station walked to.
    public let to: StationID
    /// The walk at ``PassengerTransferRules/walkingMetresPerHour``, in
    /// whole seconds rounded up.
    public let seconds: Int64
    public let tier: PassengerTransferTier

    /// The walk from `origin` to `destination`, the point of station
    /// `station`, or `nil` if they stand ``GameWorld/walkingTransferMetres``
    /// or more apart, unless they are `linked` in a transfer group
    /// (decision 81): then any distance walks, ``PassengerTransferTier/virtual``
    /// beyond the limit. Exact on the squared distance.
    init?(from origin: PlanPoint, to destination: PlanPoint, station: StationID, linked: Bool = false) {
        let dx = origin.x - destination.x
        let dy = origin.y - destination.y
        let squared = dx * dx + dy * dy
        guard let tier = PassengerTransferTier.of(squaredDistance: squared) ?? (linked ? .virtual : nil) else { return nil }
        to = station
        seconds = PassengerTransferTier.walkSeconds(squaredDistance: squared)
        self.tier = tier
    }
}
