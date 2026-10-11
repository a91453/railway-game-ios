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
                    for direction in [RingDirection.inner, .outer] {
                        guard let lap = direction == .inner ? journey : world.journey(of: line, service: service, direction: .outer) else { continue }
                        let stationIDs = line.ringCalls(direction).map { line.stops[$0] }
                        let path = ServicePath(line: line.id, pattern: nil,
                                               direction: direction == .inner ? .outbound : .inbound,
                                               stations: stationIDs, runSeconds: lap.legs.map(\.seconds),
                                               headway: headway, isRing: true, dailyCapacity: capacity)
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
                                             headway: headway, isRing: false, dailyCapacity: capacity),
                                 to: &included, calls: &calls)
                    }
                    for stretch in line.runStretches(outbound: false) {
                        // Back from the stretch's last stop to its first:
                        // the legs back are in the reversed order.
                        Self.add(ServicePath(line: line.id, pattern: nil, direction: .inbound,
                                             stations: stretch.reversed().map { line.stops[$0] },
                                             runSeconds: Array(back[(count - 1 - stretch.upperBound)..<(count - 1 - stretch.lowerBound)]),
                                             headway: headway, isRing: false, dailyCapacity: capacity),
                                 to: &included, calls: &calls)
                    }
                } else {
                    let callIndices = line.calls(ofService: service)
                    let half = callIndices.count - 1
                    let forward = ServicePath(line: line.id, pattern: pattern, direction: .outbound,
                                              stations: callIndices.map { line.stops[$0] },
                                              runSeconds: Array(journey.legs.prefix(half).map(\.seconds)),
                                              headway: headway, isRing: false, dailyCapacity: capacity)
                    let backward = ServicePath(line: line.id, pattern: pattern, direction: .inbound,
                                               stations: callIndices.reversed().map { line.stops[$0] },
                                               runSeconds: Array(journey.legs.suffix(half).map(\.seconds)),
                                               headway: headway, isRing: false, dailyCapacity: capacity)
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
        guard let starts = stopsAt[origin], stopsAt[destination] != nil,
              !closed.contains(origin), !closed.contains(destination) else { return nil }
        var labels: [PassengerRouteLabel] = []
        var frontier: [PassengerRouteState: [Int]] = [:]
        var active: [Bool] = []
        // A binary heap of open labels under one strict total order, so it
        // pops exactly the label a full sort would put first.
        var open: [Int] = []

        func precedes(_ a: Int, _ b: Int) -> Bool {
            let left = labels[a]
            let right = labels[b]
            let leftMinutes = passengerMinutesRoundingUp(left.total, by: GameTime.secondsPerMinute)
            let rightMinutes = passengerMinutesRoundingUp(right.total, by: GameTime.secondsPerMinute)
            if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }
            if left.changes != right.changes { return left.changes < right.changes }
            if left.total != right.total { return left.total < right.total }
            if passengerRouteOrderPrecedes(left.order, right.order) { return true }
            if passengerRouteOrderPrecedes(right.order, left.order) { return false }
            if left.state.node != right.state.node { return left.state.node < right.state.node }
            if left.state.onboard != right.state.onboard { return !left.state.onboard }
            return a < b
        }

        func push(_ index: Int) {
            open.append(index)
            var child = open.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard precedes(open[child], open[parent]) else { break }
                open.swapAt(child, parent)
                child = parent
            }
        }

        func popFirst() -> Int? {
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

        func dominates(_ lhs: PassengerRouteLabel, _ rhs: PassengerRouteLabel) -> Bool {
            guard lhs.total <= rhs.total, lhs.changes <= rhs.changes else { return false }
            if lhs.total < rhs.total || lhs.changes < rhs.changes { return true }
            return !passengerRouteOrderPrecedes(rhs.order, lhs.order)
        }

        func offer(_ label: PassengerRouteLabel) {
            let state = label.state
            let existing = frontier[state] ?? []
            if existing.contains(where: { dominates(labels[$0], label) }) { return }
            var survivors: [Int] = []
            for index in existing {
                if dominates(label, labels[index]) {
                    active[index] = false
                } else {
                    survivors.append(index)
                }
            }
            let index = labels.count
            labels.append(label)
            active.append(true)
            push(index)
            survivors.append(index)
            frontier[state] = survivors
        }

        for node in starts {
            let wait = max(1, passengerMinutesRoundingUp(paths[node.line].headway, by: 2)) * GameTime.secondsPerMinute
            offer(PassengerRouteLabel(state: PassengerRouteState(node: node, onboard: false),
                                      total: wait, ride: 0, wait: wait, transfer: 0, walk: 0,
                                      changes: 0, order: [], previous: nil, arrival: .board))
        }
        while let index = popFirst() {
            guard active[index] else { continue }
            let label = labels[index]
            let node = label.state.node
            // Only a ride arrives: a walk ends where another ride starts.
            if label.state.onboard && station(node) == destination {
                return reconstruct(index, from: labels)
            }
            if let (next, edge, run) = nextRide(node), !forbidden.contains(edge) {
                // A passenger already aboard stays through this stop's
                // dwell. One boarding here has waited for departure already.
                let dwell = label.state.onboard ? ServiceLine.dwellMinutes * GameTime.secondsPerMinute : 0
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
            guard !closed.contains(station(node)) else { continue }
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
            guard label.state.onboard else { continue }
            for walk in walks[station(node)] ?? [] {
                for other in stopsAt[walk.to] ?? [] {
                    let wait = max(1, passengerMinutesRoundingUp(paths[other.line].headway, by: 2)) * GameTime.secondsPerMinute
                    let transfer = walk.tier.penaltySeconds
                    offer(PassengerRouteLabel(state: PassengerRouteState(node: other, onboard: false),
                                              total: label.total + wait + transfer + walk.seconds,
                                              ride: label.ride, wait: label.wait + wait,
                                              transfer: label.transfer + transfer, walk: label.walk + walk.seconds,
                                              changes: label.changes + 1,
                                              order: label.order, previous: index, arrival: .board))
                }
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
                               transferSeconds: labels[endIndex].transfer,
                               walkSeconds: labels[endIndex].walk), edges)
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
        let graph = shared ?? PassengerRouteGraph(world: self)
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
        let routes = passengerRoutes(from: origin, to: destination, graph: graph)
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
