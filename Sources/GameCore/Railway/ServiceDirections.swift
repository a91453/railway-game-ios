// Decision 57: direction protection for newly borrowed alternative track.
// Derived from what can still run: each running service from where it is,
// and each line with a train placed to run it, over its whole plan. The
// memo belongs to one advance/query; it is never world or save state.

extension GameWorld {
    struct DirectionMemo {
        struct Call: Hashable {
            let station: StationID
            let reverses: Bool
        }
        struct Plan: Hashable {
            let calls: [Call]
            let length: Int64
            let repeats: Bool
            var routes: [LineRoutePreference?] = []
            var intermediateTurnbacks = false
        }
        /// A running service's way on through its plan: the call it is at
        /// (or bound for) and where it stands for it.
        struct Walk: Hashable {
            let plan: Plan
            let start: TrainPlacement
            let stop: Int
        }
        var plans: [Plan: Set<TrackTraversal>] = [:]
        var walks: [Walk: Set<TrackTraversal>] = [:]
        /// V3 (decision 59): the last scheduled-traffic plan worked out,
        /// with what it was derived from, and the plan an advance's step
        /// keeps for all its decisions.
        var traffic: (key: TrafficPlanKey, plan: TrafficPlan)?
        var stepTraffic: TrafficPlan?
        /// What working out a traffic plan reads that changes only by a
        /// command, kept from one plan to the next.
        var trafficParts = TrafficParts()
    }

    private struct DirectionState: Hashable {
        let placement: TrainPlacement
        let stop: Int
    }

    /// The traversals the head of a train at `start` enters along `path`,
    /// with the one it is on if it moves on along it; nothing for no
    /// distance.
    private func directions(of path: TrainPath, from start: TrainPlacement) -> Set<TrackTraversal> {
        guard path.distance > 0, case .onEdge(let run, let offset) = start.position else { return [] }
        var directions = Set(path.traversals)
        let end = path.traversals.isEmpty ? path.end ?? network.edge(run.edge)!.length : network.edge(run.edge)!.length
        if end > offset { directions.insert(run) }
        return directions
    }

    /// All positive-distance default traversals of `plan` from a train at
    /// `start` standing for call `stop`: walk the order on, including
    /// reversals and repeat seams, until the placement/order state repeats
    /// or is unroutable. No time, occupancy or fixed lookahead enters it.
    private func walkedDirections(_ plan: DirectionMemo.Plan, from start: TrainPlacement, stop: Int) -> Set<TrackTraversal> {
        var directions: Set<TrackTraversal> = []
        var place = start
        var stop = stop
        var visited: Set<DirectionState> = []
        while visited.insert(DirectionState(placement: place, stop: stop)).inserted {
            let next = stop + 1 == plan.calls.count ? 0 : stop + 1
            if next == 0 && !plan.repeats { break }
            var from = plan.calls[stop].reverses ? turnedRound(place) : place
            let preference = plan.routes.indices.contains(stop) ? plan.routes[stop] : nil
            var chosen = preference.flatMap { preferredPath(from: from.position, preference: $0, length: plan.length) }
                ?? path(from: from.position, toStation: plan.calls[next].station, length: plan.length)
            if chosen == nil, plan.intermediateTurnbacks, stop > 0, stop < plan.calls.count - 1, !plan.calls[stop].reverses {
                from = turnedRound(from)
                chosen = preference.flatMap { preferredPath(from: from.position, preference: $0, length: plan.length) }
                    ?? path(from: from.position, toStation: plan.calls[next].station, length: plan.length)
            }
            guard let path = chosen else { break }
            directions.formUnion(self.directions(of: path, from: from))
            place = placement(from, after: path)
            stop = next
        }
        return directions
    }

    /// A line's plan from every fitting berth of its first call: a line
    /// sends its trains out from wherever they stand there.
    private func plannedDirections(_ plan: DirectionMemo.Plan, memo: inout DirectionMemo) -> Set<TrackTraversal> {
        if let known = memo.plans[plan] { return known }
        var directions: Set<TrackTraversal> = []
        if let first = plan.calls.first {
            for berth in berths(of: first.station, length: plan.length) {
                let place = TrainPlacement(position: .onEdge(berth.traversal, offset: berth.offset), trailEdges: [], length: plan.length)
                directions.formUnion(walkedDirections(plan, from: place, stop: 0))
            }
        }
        memo.plans[plan] = directions
        return directions
    }

    /// A running service's traversals from where the train is: the rest of
    /// its route, the way on to its call from where that ends (a passing
    /// place's, Stage V2), and its timetable on from that call. The legs
    /// it has run already, and the berths it does not stand at, are not in
    /// it.
    private func serviceDirections(of train: Train, memo: inout DirectionMemo) -> Set<TrackTraversal> {
        guard let execution = train.execution, var start = train.placement else { return [] }
        let plan = DirectionMemo.Plan(calls: train.timetable.map { DirectionMemo.Call(station: $0.station, reverses: $0.reverses) },
                                      length: train.length, repeats: train.timetablePeriod != nil,
                                      routes: hasRoutePreferences(train) ? train.timetable.indices.map { routePreference(for: train, from: $0, to: ($0 + 1) % train.timetable.count) } : [])
        var directions: Set<TrackTraversal> = []
        let stop: Int
        switch execution {
        case .waitingAtStop(let waiting, _):
            stop = waiting
        case .travellingToStop(let next, _):
            directions.formUnion(routeStretches(of: train).stretches.filter { $0.to > $0.from }.map(\.traversal))
            let ahead = pathAhead(of: train)
            let end = ahead.count == train.movement.remainingEdges.count ? train.movement.end : nil
            start = placement(start, after: TrainPath(traversals: ahead, end: end, distance: 0))
            let ordinary = path(from: start.position, toStation: plan.calls[next].station, length: plan.length)
            let continuation = ordinary.map { (start: start, path: $0) }
                ?? passingContinuation(from: start, to: plan.calls[next].station)
            guard let continuation else { return directions }
            directions.formUnion(self.directions(of: continuation.path, from: continuation.start))
            start = placement(continuation.start, after: continuation.path)
            stop = next
        }
        let walk = DirectionMemo.Walk(plan: plan, start: start, stop: stop)
        if let known = memo.walks[walk] { return directions.union(known) }
        let walked = walkedDirections(plan, from: start, stop: stop)
        memo.walks[walk] = walked
        return directions.union(walked)
    }

    /// Protect what can still run: every placed train's running service
    /// from where it is, and every line service with a placed train, over
    /// its whole plan (round trip, or each lap of a ring), whatever its
    /// operating window or dispatch time. A line is planned for each
    /// placed train's length. Times are omitted from keys: dispatching
    /// another instance cannot invalidate its direction plan. A timetable
    /// that is not running (finished, stopped or never started), a line
    /// with no placed train and an unplaced train protect nothing: when
    /// they start, their departure takes its route whole like any other.
    func opposingServiceTraversals(for candidate: Train, memo: inout DirectionMemo) -> Set<TrackTraversal> {
        var directions: Set<TrackTraversal> = []
        for train in trains where train.id != candidate.id && train.position != nil {
            directions.formUnion(serviceDirections(of: train, memo: &memo))
        }
        for line in lines {
            for service in 0..<line.serviceCount {
                // Another placed train will run the plan: the candidate
                // itself is never protected from its own line.
                let lengths = Set(line.trains(ofService: service).filter { $0 != candidate.id }.compactMap { train(id: $0) }.filter { $0.position != nil }.map(\.length))
                guard !lengths.isEmpty else { continue }
                let orders = line.isRing ? RingDirection.allCases.map { line.ringCalls($0) }
                    : [line.calls(ofService: service) + line.calls(ofService: service).dropLast().reversed()]
                for order in orders {
                    let calls = order.enumerated().map { index, station in
                        DirectionMemo.Call(station: line.stops[station], reverses: !line.isRing && (index == order.count / 2 || index == order.count - 1))
                    }
                    for length in lengths {
                        directions.formUnion(plannedDirections(.init(calls: calls, length: length, repeats: true, routes: line.routes(ofService: service).isEmpty ? [] : zip(order, order.dropFirst()).map { pair in line.routes(ofService: service).first { $0.from == pair.0 && $0.to == pair.1 } } + [nil], intermediateTurnbacks: isTrafficControlEnabled && !line.isRing), memo: &memo))
                    }
                }
            }
        }
        // Default corridors may be shared in both directions (single track).
        // Only additional track borrowed by an alternative is restricted.
        let defaultWays = Set(routeStretches(of: candidate).stretches.filter { $0.to > $0.from }.map(\.traversal))
        return Set(directions.map(\.reversed)).subtracting(defaultWays)
    }
}
