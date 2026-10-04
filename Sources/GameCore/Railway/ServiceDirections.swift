// Decision 57: direction protection for newly borrowed alternative track.
// Derived from complete plans, independent of departure times and progress.
// The memo belongs to one advance/query; it is never world or save state.

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
        }
        var plans: [Plan: Set<TrackTraversal>] = [:]
    }

    private struct DirectionState: Hashable {
        let placement: TrainPlacement
        let stop: Int
    }

    /// All positive-distance default traversals, from every fitting berth
    /// of the first call. Walk the complete order, including reversals and
    /// repeat seams, until the placement/order state repeats or is unroutable.
    /// No time, occupancy, execution or fixed lookahead enters this search.
    private func plannedDirections(_ plan: DirectionMemo.Plan, memo: inout DirectionMemo) -> Set<TrackTraversal> {
        if let known = memo.plans[plan] { return known }
        var directions: Set<TrackTraversal> = []
        if let first = plan.calls.first {
            for berth in berths(of: first.station, length: plan.length) {
                var place = TrainPlacement(position: .onEdge(berth.traversal, offset: berth.offset), trailEdges: [], length: plan.length)
                var stop = 0
                var visited: Set<DirectionState> = []
                while visited.insert(DirectionState(placement: place, stop: stop)).inserted {
                    let next = stop + 1 == plan.calls.count ? 0 : stop + 1
                    if next == 0 && !plan.repeats { break }
                    let start = plan.calls[stop].reverses ? turnedRound(place) : place
                    guard let path = path(from: start.position, toStation: plan.calls[next].station, length: plan.length) else { break }
                    if path.distance > 0, case .onEdge(let run, let offset) = start.position {
                        let end = path.traversals.isEmpty ? path.end ?? network.edge(run.edge)!.length : network.edge(run.edge)!.length
                        if end > offset { directions.insert(run) }
                        directions.formUnion(path.traversals)
                    }
                    place = placement(start, after: path)
                    stop = next
                }
            }
        }
        memo.plans[plan] = directions
        return directions
    }

    /// Protect every timetable and every line/pattern/lap, even idle,
    /// unassigned or outside its operating window. A line is planned for
    /// one car and each assigned train length. Times are omitted from keys:
    /// dispatching another instance cannot invalidate its direction plan.
    func opposingServiceTraversals(for candidate: Train, memo: inout DirectionMemo) -> Set<TrackTraversal> {
        var directions: Set<TrackTraversal> = []
        for train in trains where train.id != candidate.id {
            let calls = train.timetable.map { DirectionMemo.Call(station: $0.station, reverses: $0.reverses) }
            if !calls.isEmpty {
                directions.formUnion(plannedDirections(.init(calls: calls, length: train.length, repeats: train.timetablePeriod != nil), memo: &memo))
            }
            // Also respect a route already chosen by another service.
            if case .travellingToStop? = train.execution {
                directions.formUnion(routeStretches(of: train).stretches.filter { $0.to > $0.from }.map(\.traversal))
            }
        }
        for line in lines {
            for service in 0..<line.serviceCount {
                let lengths = Set([Int64(0)] + line.trains(ofService: service).compactMap { train(id: $0)?.length })
                let orders = line.isRing ? RingDirection.allCases.map { line.ringCalls($0) }
                    : [line.calls(ofService: service) + line.calls(ofService: service).dropLast().reversed()]
                for order in orders {
                    let calls = order.enumerated().map { index, station in
                        DirectionMemo.Call(station: line.stops[station], reverses: !line.isRing && (index == order.count / 2 || index == order.count - 1))
                    }
                    for length in lengths {
                        directions.formUnion(plannedDirections(.init(calls: calls, length: length, repeats: true), memo: &memo))
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
