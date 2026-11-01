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

    /// A fixed order of edges, to break ties without the order of a set.
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        (lhs.line, lhs.from, lhs.to, lhs.direction) < (rhs.line, rhs.from, rhs.to, rhs.direction)
    }
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
    /// Its legs for exact ties: a node of its search's
    /// ``PassengerRouteSearch/orders``, -1 for none.
    let order: Int
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

    /// The graph of `world` at its clock's time, or at `time` (decision
    /// 470: the graph a call of ``GameWorld/advance(ticks:)`` will plan on
    /// when the service levels change during it).
    init(world: GameWorld, at time: GameTime? = nil) {
        var included: [ServicePath] = []
        var calls: [StationID: [PassengerRouteNode]] = [:]
        for line in world.lines where !line.isFreight {
            guard let level = world.serviceLevel(of: line.id, at: time ?? world.clock.now) else { continue }
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
    /// Where ``run(until:pausingBefore:)`` stopped.
    enum Stop {
        /// Label `index` is the first to arrive at the target station.
        case arrived(Int)
        case exhausted
        /// Paused before the first label at call `number` is expanded.
        case firstExpansion(Int)
    }

    /// When nothing has happened yet: the time of a label never popped or
    /// never put out of the frontier, or of a call never expanded.
    private static let never = Int32.max

    private let graph: PassengerRouteGraph
    /// The calls whose ride to the next call is banned, by number (see
    /// ``PassengerRouteGraph/Lookup/firstNode``).
    var banned: [Int] = []
    private var labels: [PassengerRouteLabel] = []
    /// The labels' leg orders, sharing their prefixes: each node is one
    /// leg after the node `parent` (-1: the first leg), `depth` legs in
    /// all. A label riding on changes only its last leg, so it is a new
    /// node beside the old one; a label boarding keeps its node (派工單
    /// PLANDAY: an array of legs for every label was an allocation each).
    private var orders: [OrderNode] = []
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
    /// A label popped and not expanded yet: the search paused before it.
    private var pending: Int?
    /// Its history, so that ``paused(before:)`` can give it as it was
    /// (派工單 PLANDAY). The time is how many labels it has popped and
    /// expanded (or paused before): a label made, popped or put out of the
    /// frontier while label `t` is being expanded has time `t`, one made
    /// before the first pop time 0.
    private var time: Int32 = 0
    /// When each label was made, popped and put out of the frontier.
    private var madeAt: [Int32] = []
    private var poppedAt: [Int32] = []
    private var droppedAt: [Int32] = []
    /// When the first label to arrive at each station slot was popped.
    private var arrivedAt: [Int32]
    /// When each call, by number, was first expanded (or paused before),
    /// and the label it was.
    private var expandedAt: [Int32]
    private var expandedLabel: [Int32]

    init(graph: PassengerRouteGraph, from origin: StationID, banning forbidden: Set<PassengerRideEdge>) {
        self.graph = graph
        let lookup = graph.lookup
        banned = Self.calls(banned: forbidden, on: graph)
        frontier = Array(repeating: [], count: 2 * lookup.nodeSlot.count)
        arrived = Array(repeating: -1, count: lookup.calls.count)
        arrivedAt = Array(repeating: Self.never, count: lookup.calls.count)
        expandedAt = Array(repeating: Self.never, count: lookup.nodeSlot.count)
        expandedLabel = Array(repeating: -1, count: lookup.nodeSlot.count)
        guard let slot = lookup.slot[origin], !lookup.closed[slot] else { return }
        for node in lookup.calls[slot] {
            let wait = max(1, passengerMinutesRoundingUp(graph.paths[node.line].headway, by: 2)) * GameTime.secondsPerMinute
            offer(PassengerRouteLabel(state: PassengerRouteState(node: node, onboard: false),
                                      total: wait, ride: 0, wait: wait, transfer: 0, walk: 0,
                                      changes: 0, order: -1, previous: nil, arrival: .board))
        }
    }

    /// One leg of a label's order (see ``orders``).
    private struct OrderNode {
        let leg: PassengerRouteOrderLeg
        let parent: Int32
        let depth: Int32
    }

    private func depth(_ order: Int) -> Int {
        order < 0 ? 0 : Int(orders[order].depth)
    }

    /// Whether the legs of order `lhs` come before those of `rhs`: what
    /// `passengerRouteOrderPrecedes` gives for their arrays (the first
    /// leg that differs decides, else the shorter comes first).
    private func orderPrecedes(_ lhs: Int, _ rhs: Int) -> Bool {
        var left = lhs, right = rhs
        let leftDepth = depth(lhs), rightDepth = depth(rhs)
        for _ in 0..<max(0, leftDepth - rightDepth) { left = Int(orders[left].parent) }
        for _ in 0..<max(0, rightDepth - leftDepth) { right = Int(orders[right].parent) }
        // Up from the last position both have: the highest leg that
        // differs is the first difference.
        var first: Bool?
        while left != right {
            let a = orders[left].leg, b = orders[right].leg
            if a != b {
                if a.line.rawValue != b.line.rawValue {
                    first = a.line.rawValue < b.line.rawValue
                } else if a.from.rawValue != b.from.rawValue {
                    first = a.from.rawValue < b.from.rawValue
                } else {
                    first = a.to.rawValue < b.to.rawValue
                }
            }
            left = Int(orders[left].parent)
            right = Int(orders[right].parent)
        }
        return first ?? (leftDepth < rightDepth)
    }

    /// The calls, by number, whose rides to the next call are the edges
    /// `forbidden` (see `PassengerRouteGraph.nextRide`); an edge no ride is
    /// bans nothing.
    static func calls(banned forbidden: Set<PassengerRideEdge>, on graph: PassengerRouteGraph) -> [Int] {
        forbidden.compactMap { call(banning: $0, on: graph) }
    }

    /// The call whose ride to the next call is `edge`, if it is one.
    static func call(banning edge: PassengerRideEdge, on graph: PassengerRouteGraph) -> Int? {
        guard graph.paths.indices.contains(edge.line), edge.to == edge.from + 1,
              graph.paths[edge.line].stations.indices.contains(edge.to),
              edge.direction == (graph.paths[edge.line].direction == .outbound ? 1 : -1) else { return nil }
        return graph.lookup.firstNode[edge.line] + edge.from
    }

    /// The cheapest route to `destination`, searching on from where the
    /// last question stopped if it has not been reached yet.
    mutating func route(to destination: StationID) -> (PassengerRoute, [PassengerRideEdge])? {
        guard let target = slot(of: destination) else { return nil }
        if arrived[target] >= 0 { return graph.reconstruct(arrived[target], from: labels) }
        guard case .arrived(let index) = run(until: target) else { return nil }
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

    /// Whether a label at call `number` has been expanded, or the search
    /// is paused before the first one.
    func hasExpanded(_ number: Int) -> Bool { expandedAt[number] != Self.never }

    /// When it first expanded a label at call `number` (or paused before
    /// it), by its time; `Int32.max` if it has not.
    func expansionTime(of number: Int) -> Int32 { expandedAt[number] }

    /// This search as it was paused before it first expanded a label at
    /// call `number`, or `nil` if it has not: what a search banning that
    /// call's ride, and the rides this one bans, has done by then (the
    /// ban changes nothing before), rebuilt from its history without
    /// searching again (派工單 PLANDAY).
    ///
    /// The labels made by then are the first ones (they are numbered as
    /// they are made); of those, the ones still in the frontier make it up
    /// in their order, and the ones not popped yet are the open ones. The
    /// heap's own arrangement is not kept: it pops by a strict total
    /// order, whatever its arrangement. Labels already put out of the
    /// frontier are left out of it, as popping them does nothing.
    func paused(before number: Int) -> PassengerRouteSearch? {
        let then = expandedAt[number]
        guard then != Self.never else { return nil }
        var search = self
        var count = madeAt.count
        while count > 0 && madeAt[count - 1] >= then { count -= 1 }
        search.labels.removeLast(labels.count - count)
        search.madeAt.removeLast(labels.count - count)
        search.poppedAt = poppedAt[..<count].map { $0 <= then ? $0 : Self.never }
        search.droppedAt = droppedAt[..<count].map { $0 < then ? $0 : Self.never }
        search.active = search.droppedAt.map { $0 == Self.never }
        search.frontier = Array(repeating: [], count: frontier.count)
        search.open = []
        for index in 0..<count where search.active[index] {
            search.frontier[state(labels[index].state)].append(index)
            if search.poppedAt[index] == Self.never { search.open.append(index) }
        }
        search.heapify()
        for slot in arrived.indices where arrivedAt[slot] > then {
            search.arrived[slot] = -1
            search.arrivedAt[slot] = Self.never
        }
        for call in expandedAt.indices where expandedAt[call] > then {
            search.expandedAt[call] = Self.never
            search.expandedLabel[call] = -1
        }
        search.pending = Int(expandedLabel[number])
        search.time = then
        return search
    }

    /// The first label to arrive at station slot `target`, if one has.
    func arrival(at target: Int) -> Int? {
        arrived[target] >= 0 ? arrived[target] : nil
    }

    /// Searches on until the first label arrives aboard at station slot
    /// `target` (-1: none), or until there is nothing left. It also stops
    /// before expanding call `pause` for the first time, holding that label
    /// for the next run.
    mutating func run(until target: Int, pausingBefore pause: Int = -1) -> Stop {
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
                time += 1
                poppedAt[index] = time
                // Only a ride arrives: a walk ends where another ride starts.
                let state = labels[index].state
                let number = lookup.firstNode[state.node.line] + state.node.stop
                if state.onboard {
                    let slot = lookup.nodeSlot[number]
                    if arrived[slot] < 0 {
                        arrived[slot] = index
                        arrivedAt[slot] = time
                    }
                }
                if expandedAt[number] == Self.never {
                    expandedAt[number] = time
                    expandedLabel[number] = Int32(index)
                    if number == pause {
                        pending = index
                        return .firstExpansion(number)
                    }
                }
            }
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
        let leftOrder = labels[a].order
        let rightOrder = labels[b].order
        if leftOrder != rightOrder {
            if orderPrecedes(leftOrder, rightOrder) { return true }
            if orderPrecedes(rightOrder, leftOrder) { return false }
        }
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

    /// Arranges `open` into a heap.
    private mutating func heapify() {
        for start in stride(from: open.count / 2 - 1, through: 0, by: -1) {
            siftDown(start)
        }
    }

    private mutating func siftDown(_ start: Int) {
        var parent = start
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

    private mutating func popFirst() -> Int? {
        guard let first = open.first else { return nil }
        let last = open.removeLast()
        if !open.isEmpty {
            open[0] = last
            siftDown(0)
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
        return reversed ? !orderPrecedes(labels[index].order, label.order)
            : !orderPrecedes(label.order, labels[index].order)
    }

    /// Keeps `label` unless a label at its state dominates it; whether
    /// it kept it.
    @discardableResult
    private mutating func offer(_ label: PassengerRouteLabel) -> Bool {
        let slot = state(label.state)
        if frontier[slot].contains(where: { dominates($0, label) }) { return false }
        // Kept in their order, the new one last, in place.
        var survivors = frontier[slot]
        frontier[slot] = []
        var kept = 0
        for index in survivors {
            if dominates(index, label, reversed: true) {
                active[index] = false
                droppedAt[index] = time
            } else {
                survivors[kept] = index
                kept += 1
            }
        }
        survivors.removeLast(survivors.count - kept)
        let index = labels.count
        labels.append(label)
        active.append(true)
        madeAt.append(time)
        poppedAt.append(Self.never)
        droppedAt.append(Self.never)
        push(index)
        survivors.append(index)
        frontier[slot] = survivors
        return true
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
            if label.state.onboard, label.order >= 0 {
                let last = orders[label.order]
                orders.append(OrderNode(leg: PassengerRouteOrderLeg(line: last.leg.line, from: last.leg.from, to: to),
                                        parent: last.parent, depth: last.depth))
            } else {
                orders.append(OrderNode(leg: PassengerRouteOrderLeg(line: ridePath.line,
                                                                    from: ridePath.stations[edge.from], to: to),
                                        parent: Int32(label.order), depth: Int32(depth(label.order) + 1)))
            }
            let order = orders.count - 1
            if !offer(PassengerRouteLabel(state: PassengerRouteState(node: next, onboard: true),
                                          total: label.total + seconds, ride: label.ride + seconds,
                                          wait: label.wait, transfer: label.transfer, walk: label.walk,
                                          changes: label.changes, order: order, previous: index,
                                          arrival: .ride(edge, seconds))) {
                // Dominated: no label holds the node.
                orders.removeLast()
            }
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
/// A search banning some rides is the one banning one ride fewer up to
/// the first time it would take that ride: a search banning one ride
/// starts from the unbanned search as it was paused before that ride's
/// call, and one banning two from the search banning the one of them the
/// unbanned search reaches first, as it was before the other's call
/// (``PassengerRouteSearch/paused(before:)``). Nothing differs from
/// starting it afresh but the work (派工單 AQ; 派工單 PLANDAY took the
/// second ban from the first's search, and the copies from the searches'
/// histories).
///
/// The banned searches asked most lately are kept, at most `searchLimit`
/// of them and `labelBudget` labels together (派工單 BB: 200 stations
/// took 1.4 GB). A dropped one starts again when asked.
struct PassengerRouteSearches {
    let graph: PassengerRouteGraph
    /// At most this many banned searches are kept.
    let searchLimit: Int
    /// The banned searches kept hold at most this many labels, but for
    /// the one asked last. 200,000 since 派工單 PLANDAY (400,000 before),
    /// as each label now also keeps its history and order node: about the
    /// memory the old budget took.
    let labelBudget: Int
    private var origin: StationID?
    private var unbanned: PassengerRouteSearch?
    /// The banned searches kept, each with when it was asked last.
    private var searches: [Set<PassengerRideEdge>: (search: PassengerRouteSearch, asked: Int)] = [:]
    /// The keys of `searches` by when they were asked last.
    private var asked: [Int: Set<PassengerRideEdge>] = [:]
    /// The next time a search is asked, and no time a search kept was
    /// asked last is before `oldest`.
    private var now = 0
    private var oldest = 0
    /// The labels of the banned searches kept.
    private var held = 0

    init(graph: PassengerRouteGraph, searchLimit: Int = 512, labelBudget: Int = 200_000) {
        self.graph = graph
        self.searchLimit = max(1, searchLimit)
        self.labelBudget = max(0, labelBudget)
    }

    /// How many whole searches are kept besides the unbanned one.
    var copies: Int { searches.count }

    /// How many banned searches are kept.
    var bannedSearches: Int { searches.count }

    /// The labels of the banned searches kept.
    var bannedLabels: Int { searches.values.reduce(0) { $0 + $1.search.size } }

    /// What ``PassengerRouteGraph/shortest(from:to:banning:)`` gives.
    mutating func shortest(from origin: StationID, to destination: StationID,
                           banning forbidden: Set<PassengerRideEdge>) -> (PassengerRoute, [PassengerRideEdge])? {
        if origin != self.origin {
            self.origin = origin
            unbanned = PassengerRouteSearch(graph: graph, from: origin, banning: [])
            searches = [:]
            asked = [:]
            oldest = now
            held = 0
        }
        guard !forbidden.isEmpty else {
            guard let target = unbanned!.slot(of: destination) else { return nil }
            if let index = unbanned!.arrival(at: target) { return unbanned!.route(ending: index) }
            guard case .arrived(let index) = unbanned!.run(until: target) else { return nil }
            return unbanned!.route(ending: index)
        }
        var search = take(forbidden)
        let found = search.route(to: destination)
        keep(search, banning: forbidden)
        while held > labelBudget && searches.count > 1 {
            dropOldest()
        }
        return found
    }

    /// The search banning `forbidden`, taken out of those kept, or started.
    private mutating func take(_ forbidden: Set<PassengerRideEdge>) -> PassengerRouteSearch {
        if let kept = searches.removeValue(forKey: forbidden) {
            asked[kept.asked] = nil
            held -= kept.search.size
            return kept.search
        }
        return start(banning: forbidden)
    }

    /// Keeps `search` as the one asked last, dropping the one asked
    /// longest ago when there are too many.
    private mutating func keep(_ search: PassengerRouteSearch, banning forbidden: Set<PassengerRideEdge>) {
        if searches.count >= searchLimit {
            dropOldest()
        }
        searches[forbidden] = (search, now)
        asked[now] = forbidden
        now += 1
        held += search.size
    }

    /// Drops the search asked longest ago.
    private mutating func dropOldest() {
        while asked[oldest] == nil { oldest += 1 }
        held -= searches.removeValue(forKey: asked.removeValue(forKey: oldest)!)!.search.size
    }

    /// A search banning `forbidden`, as far on as the one banning one ride
    /// fewer is the same.
    private mutating func start(banning forbidden: Set<PassengerRideEdge>) -> PassengerRouteSearch {
        let calls = PassengerRouteSearch.calls(banned: forbidden, on: graph)
        guard !calls.isEmpty else {
            // It bans nothing it could take.
            return unbanned!
        }
        // The ride the unbanned search reaches last, or never: banning it
        // changes the search banning the others latest.
        let last = forbidden.max { left, right in
            let (a, b) = (expansion(of: left), expansion(of: right))
            return a != b ? a < b : PassengerRideEdge.precedes(left, right)
        }!
        var fewer = forbidden
        fewer.remove(last)
        guard let call = PassengerRouteSearch.call(banning: last, on: graph) else {
            // Banning `last` bans nothing: the same as banning the others.
            var search = fewer.isEmpty ? unbanned! : take(fewer)
            if !fewer.isEmpty { keep(search, banning: fewer) }
            search.banned = calls
            return search
        }
        var search: PassengerRouteSearch
        if fewer.isEmpty {
            if !unbanned!.hasExpanded(call) {
                _ = unbanned!.run(until: -1, pausingBefore: call)
            }
            // It never takes the ride: the same search.
            search = unbanned!.paused(before: call) ?? unbanned!
        } else {
            var parent = take(fewer)
            if !parent.hasExpanded(call) {
                _ = parent.run(until: -1, pausingBefore: call)
            }
            search = parent.paused(before: call) ?? parent
            keep(parent, banning: fewer)
        }
        search.banned = calls
        return search
    }

    /// When the unbanned search first expanded the call of `edge`'s ride,
    /// if it has, by its time.
    private func expansion(of edge: PassengerRideEdge) -> Int32 {
        guard let call = PassengerRouteSearch.call(banning: edge, on: graph) else { return Int32.min }
        return unbanned!.expansionTime(of: call)
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

/// The route choices already worked out, by the connected part of the
/// derived graph their origin is in. Not game state: never saved, and two
/// worlds compare equal whatever it holds.
///
/// A search from a station reads only the part of the graph it can reach:
/// its paths (in the graph's order, which breaks exact ties), the walks
/// between its stations and which of them are closed; not the paths'
/// daily capacities, and not the other parts. So the choices from an
/// origin are a pure function of its part (a ``Component``), and keeping
/// them while that part is unchanged gives exactly what working them out
/// again would, however the rest of the graph changed (decision 470: a
/// line built far away, or a train bought, worked every route out again,
/// 5–14 s in 92.1's game of 81 stations). The parts of the last
/// ``generations`` graphs are kept, so a plan at night, when no line runs,
/// does not drop the day's (派工單 BK).
struct PassengerRouteMemo: Equatable, Sendable {
    struct Pair: Hashable, Sendable {
        let origin: StationID
        let destination: StationID
    }

    /// What a search reads of a ``PassengerRouteGraph/ServicePath``.
    struct Path: Hashable, Sendable {
        let line: LineID
        let pattern: Int?
        let direction: LineDirection
        let stations: [StationID]
        let runSeconds: [Int64]
        let headway: Int64
        let isRing: Bool
        let dwellSeconds: Int64

        init(_ path: PassengerRouteGraph.ServicePath) {
            line = path.line
            pattern = path.pattern
            direction = path.direction
            stations = path.stations
            runSeconds = path.runSeconds
            headway = path.headway
            isRing = path.isRing
            dwellSeconds = path.dwellSeconds
        }
    }

    /// A connected part of a graph, its stations joined by its paths and
    /// walks: everything a search from one of them reads.
    struct Component: Hashable, Sendable {
        let paths: [Path]
        let walks: [StationID: [PassengerWalk]]
        let closed: Set<StationID>
    }

    /// How many graphs back a part last used is kept.
    static let generations = 4

    private(set) var graph: PassengerRouteGraph?
    /// The parts of ``graph``, and the choices from origins in each.
    private var parts: [Component] = []
    private var choicesByPart: [[Pair: [PassengerRouteChoice]]] = []
    /// Each served station's part, by index in ``parts``.
    private var partOf: [StationID: Int] = [:]
    /// The choices from origins the graph does not serve: none, at once.
    private var unserved: [Pair: [PassengerRouteChoice]] = [:]
    /// The parts of earlier graphs, with the number of the last graph that
    /// had each.
    private var kept: [Component: (choices: [Pair: [PassengerRouteChoice]], generation: Int)] = [:]
    private var generation = 0

    static func == (_: Self, _: Self) -> Bool {
        true
    }

    /// The choices worked out between `pair`'s stations on the graph last
    /// used, if any.
    subscript(pair: Pair) -> [PassengerRouteChoice]? {
        get {
            if let part = partOf[pair.origin] { return choicesByPart[part][pair] }
            return unserved[pair]
        }
        set {
            if let part = partOf[pair.origin] {
                choicesByPart[part][pair] = newValue
            } else {
                unserved[pair] = newValue
            }
        }
    }

    /// Whether choices from `origin` are held for its part of the graph
    /// last used: then its part was worked out before.
    func hasChoices(from origin: StationID) -> Bool {
        guard let part = partOf[origin] else { return false }
        return choicesByPart[part].keys.contains { $0.origin == origin }
    }

    /// How many pairs' choices are held, for the current graph and kept.
    var count: Int {
        choicesByPart.reduce(unserved.count) { $0 + $1.count } + kept.values.reduce(0) { $0 + $1.choices.count }
    }

    /// Goes on to `graph`: keeps the choices of each of its parts that the
    /// current graph or one of the ``generations`` before had.
    mutating func use(_ graph: PassengerRouteGraph) {
        guard self.graph != graph else { return }
        stow()
        generation += 1
        self.graph = graph
        unserved = [:]
        partOf = [:]
        let found = Self.components(of: graph)
        parts = found.parts
        partOf = found.partOf
        choicesByPart = parts.map { kept.removeValue(forKey: $0)?.choices ?? [:] }
        kept = kept.filter { generation - $0.value.generation < Self.generations }
    }

    /// Takes in the choices `other` worked out: the same parts have the
    /// same choices, so it adds only the pairs this one has not.
    mutating func absorb(_ other: Self) {
        var other = other
        other.stow()
        for (part, entry) in other.kept {
            if let index = parts.firstIndex(of: part) {
                choicesByPart[index].merge(entry.choices) { mine, _ in mine }
            } else if kept[part] != nil {
                kept[part]!.choices.merge(entry.choices) { mine, _ in mine }
                kept[part]!.generation = max(kept[part]!.generation, generation)
            } else {
                kept[part] = (entry.choices, generation)
            }
        }
    }

    /// Moves the current graph's parts into ``kept``.
    private mutating func stow() {
        for (part, choices) in zip(parts, choicesByPart) {
            kept[part] = (choices, generation)
        }
        parts = []
        choicesByPart = []
    }

    /// The connected parts of `graph`, in the order of their first paths,
    /// and each served station's.
    static func components(of graph: PassengerRouteGraph) -> (parts: [Component], partOf: [StationID: Int]) {
        var parent: [StationID: StationID] = [:]
        func root(_ station: StationID) -> StationID {
            var current = station
            while let next = parent[current], next != current { current = next }
            var step = station
            while let next = parent[step], next != current {
                parent[step] = current
                step = next
            }
            return current
        }
        func join(_ a: StationID, _ b: StationID) {
            let (left, right) = (root(a), root(b))
            if left != right { parent[max(left, right)] = min(left, right) }
        }
        for path in graph.paths {
            for station in path.stations where parent[station] == nil { parent[station] = station }
            for (a, b) in zip(path.stations, path.stations.dropFirst()) { join(a, b) }
        }
        for (from, walks) in graph.walks {
            for walk in walks where parent[from] != nil && parent[walk.to] != nil { join(from, walk.to) }
        }
        var index: [StationID: Int] = [:]
        var paths: [[Path]] = []
        for path in graph.paths {
            let top = root(path.stations[0])
            if index[top] == nil {
                index[top] = paths.count
                paths.append([])
            }
            paths[index[top]!].append(Path(path))
        }
        var walks = Array(repeating: [StationID: [PassengerWalk]](), count: paths.count)
        var closed = Array(repeating: Set<StationID>(), count: paths.count)
        var partOf: [StationID: Int] = [:]
        for station in parent.keys {
            let part = index[root(station)]!
            partOf[station] = part
            if let list = graph.walks[station] { walks[part][station] = list }
            if graph.closed.contains(station) { closed[part].insert(station) }
        }
        let parts = paths.indices.map { Component(paths: paths[$0], walks: walks[$0], closed: closed[$0]) }
        return (parts, partOf)
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
    /// (`Railway/taiwan-rail-reference-clean/source/data/station_transfers.json`,
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
