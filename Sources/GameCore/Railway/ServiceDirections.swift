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
        /// A travelling service's traversals but the stretch it is on:
        /// what is left of its route as it goes along it, where that ends,
        /// and the call it is bound for.
        struct Travel: Hashable {
            let plan: Plan
            let moving: [TrackTraversal]
            let end: TrainPlacement
            let call: Int
        }
        var plans: [Plan: Set<TrackTraversal>] = [:]
        var walks: [Walk: Set<TrackTraversal>] = [:]
        /// Travelling services' traversals (see ``Travel``).
        var travels: [Travel: Set<TrackTraversal>] = [:]
        /// V3 (decision 59): the last scheduled-traffic plan worked out,
        /// with what it was derived from, and the plan an advance's step
        /// keeps for all its decisions.
        var traffic: (key: TrafficPlanKey, plan: TrafficPlan)?
        var stepTraffic: TrafficPlan?
        /// What working out a traffic plan reads that changes only by a
        /// command, kept from one plan to the next.
        var trafficParts = TrafficParts()
        /// The track the trains hold (see ``trackHolders(memo:)``), for the
        /// last sets of trains asked about.
        var holders: [(trains: [Train], holders: TrackHolders)] = []
        /// Each train's movement authority (see ``authority(of:memo:)``),
        /// for its last values asked about.
        var authorities: [TrainID: [(train: Train, authority: (left: Int64, envelopes: AuthorityEnvelopes)?)]] = [:]
        /// Each train's held track (see ``heldTrack(_:memo:)``), for its last
        /// values asked about.
        var heldTracks: [TrainID: [(train: Train, held: HeldTrack)]] = [:]
        /// Each following train's route envelope (see
        /// ``followingCover(of:_:memo:)``), for its last values asked about.
        var followingCovers: [TrainID: [(train: Train, cover: TrackCover)]] = [:]
        /// ``foulingSpansByEdge()``, once worked out.
        var foulingByEdge: [TrackEdgeID: [TrackSpan]]?
        /// The paths searched for (see ``PathMemo``).
        var paths = PathMemo()
        /// The runs' curves (see ``curve(of:for:memo:)``), by what they are
        /// built from.
        struct CurveQuery: Hashable {
            let length: Int64
            let seconds: Int64
            let performance: TrainPerformance
            /// Decision 217.
            let limits: [TrackSpeedLimit]
        }
        var curves: [CurveQuery: RunCurve?] = [:]
        /// Each train's reservation in a ``ReservedTrack`` (see
        /// ``reservedTrack(of:memo:)``), for its last reservation asked about.
        var reserved: [TrainID: (reservation: [TrackResource], reserved: ReservedTrack)] = [:]
        /// Each running service's traversals (see
        /// ``serviceDirections(of:memo:)``), for its last values asked about.
        var serviceDirections: [TrainID: [(train: Train, directions: Set<TrackTraversal>)]] = [:]
        /// Each candidate's ``opposingServiceTraversals(for:memo:)``, for
        /// the last trains and candidate asked about.
        var opposing: [TrainID: (trains: [Train], candidate: Train, traversals: Set<TrackTraversal>)] = [:]
        /// Each candidate's ``opposingParts(for:memo:)``, for the last
        /// trains and candidate asked about.
        var opposingParts: [TrainID: (trains: [Train], candidate: Train, parts: (directions: [Set<TrackTraversal>], defaultWays: Set<TrackTraversal>))] = [:]
        /// Each train as its last releases of the track it has passed left
        /// it (see ``releasePassedTrack(_:before:distance:memo:)``): its
        /// reservation then held nothing outside its route envelope. A few
        /// are kept: the steps of an advance try the trains moved on by
        /// different seconds from the same start.
        var released: [TrainID: [Train]] = [:]

        /// Keeps `train` in ``released``.
        mutating func release(_ train: Train) {
            var known = released[train.id] ?? []
            guard !known.contains(train) else { return }
            known.insert(train, at: 0)
            if known.count > 4 { known.removeLast() }
            released[train.id] = known
        }
    }

    /// What a ``DirectionMemo`` works out from the network, the lines, the
    /// stations, flexible dispatch and keeping left (decision 202) alone:
    /// the traffic plan's parts (see
    /// ``TrafficParts``), the paths searched for and the runs' curves. It
    /// is kept from a call of ``advance(ticks:)`` that changed none of
    /// those, and lent to the next call's memo only while all of them are
    /// still as they were. Not game state: never saved, and equal to any
    /// other.
    struct RouteMemo: Equatable, Sendable {
        struct Key: Equatable, Sendable {
            let network: RailwayNetwork
            let lines: [ServiceLine]
            let stations: [StationID]
            /// Decision 209: no line's path runs over a depot's sidings.
            let depots: [StationID]
            let flexDispatch: Bool
            let keepLeft: Bool
            /// Decision 207: the legs' planned seconds.
            let realisticOperation: Bool
            /// Decision 217: the legs' planned seconds.
            let curveSpeedLimits: Bool

            init(_ world: GameWorld) {
                network = world.network
                lines = world.lines
                stations = world.stations.map(\.id)
                depots = world.stations.filter(\.isDepot).map(\.id)
                flexDispatch = world.flexDispatch
                keepLeft = world.keepLeft
                realisticOperation = world.realisticOperation
                curveSpeedLimits = world.curveSpeedLimits
            }
        }
        /// What each service's journey, capacity and timetable are worked
        /// out from: the network, the lines but for when they last sent
        /// trains out, the stations, the settings the journeys read, the
        /// service day and the trains' lengths.
        struct ServiceKey: Equatable, Sendable {
            let network: RailwayNetwork
            let lines: [ServiceLine]
            let stations: [StationID]
            let depots: [StationID]
            let flexDispatch: Bool
            let keepLeft: Bool
            let realisticOperation: Bool
            let curveSpeedLimits: Bool
            let trafficControl: Bool
            let serviceDay: ServiceDay
            let trains: [TrainID]
            let trainLengths: [Int64]

            init(_ world: GameWorld) {
                network = world.network
                lines = world.lines.map(\.withoutDispatchTimes)
                stations = world.stations.map(\.id)
                depots = world.stations.filter(\.isDepot).map(\.id)
                flexDispatch = world.flexDispatch
                keepLeft = world.keepLeft
                realisticOperation = world.realisticOperation
                curveSpeedLimits = world.curveSpeedLimits
                trafficControl = world.isTrafficControlEnabled
                serviceDay = world.serviceDay
                trains = world.trains.map(\.id)
                trainLengths = world.trains.map(\.length)
            }
        }
        /// The most of each it keeps: beyond it, it starts again.
        static let limit = 20_000
        private var key: Key?
        private var serviceKey: ServiceKey?
        private var journeys: [LineID: [Int: LineJourney?]] = [:]
        private var capacityLayouts: [LineID: LineCapacityLayout] = [:]
        private var capacities: [LineID: [Int: ServiceCapacityProfile?]] = [:]
        private var outerCapacityJourneys: [LineID: LineJourney?] = [:]
        private var scheduledServices: [ScheduledService: Bool] = [:]
        private var runDepotTrips: [RunDepotQuery: LineTrip?] = [:]
        private var trafficParts = TrafficParts()
        private var paths = PathMemo()
        private var curves: [DirectionMemo.CurveQuery: RunCurve?] = [:]

        static func == (_: Self, _: Self) -> Bool {
            true
        }

        /// Whether it keeps nothing.
        var isEmpty: Bool {
            key == nil
        }

        /// Whether it keeps the services' journeys, capacities and whether
        /// they run.
        var keepsServices: Bool {
            serviceKey != nil
        }

        /// Gives `memo`, a new one, what it kept, when it was kept for the
        /// same network, lines, stations and dispatch (`key`).
        func lend(to memo: inout DirectionMemo, for key: Key) {
            guard self.key == key else { return }
            memo.paths = paths
            memo.curves = curves
        }

        /// Gives `memo`, a new one, the services' journeys, capacities and
        /// whether they run, and the empty runs out of depots (each for
        /// where its train stood), when they were kept for `key`: a
        /// departure changes none of them (the dispatcher's
        /// ``ServiceLine/withoutDispatchTimes``).
        func lend(to memo: inout DispatchMemo, for key: ServiceKey) {
            guard serviceKey == key else { return }
            memo.journeys = journeys
            memo.capacityLayouts = capacityLayouts
            memo.capacities = capacities
            memo.outerCapacityJourneys = outerCapacityJourneys
            memo.scheduledServices = scheduledServices
            memo.runDepotTrips = runDepotTrips
            // The traffic plan's parts read the lines' runs and routes,
            // never when they last sent trains out: kept across departures.
            memo.directions.trafficParts = trafficParts
        }

        /// Keeps what `memo` worked out of the services and the runs out of
        /// depots over a call of ``advance(ticks:)`` that left all of `key`
        /// as it was.
        mutating func keep(_ memo: DispatchMemo, for key: ServiceKey) {
            serviceKey = key
            journeys = memo.journeys
            capacityLayouts = memo.capacityLayouts
            capacities = memo.capacities
            outerCapacityJourneys = memo.outerCapacityJourneys
            scheduledServices = memo.scheduledServices
            runDepotTrips = memo.runDepotTrips.count > Self.limit ? [:] : memo.runDepotTrips
            let parts = memo.directions.trafficParts
            trafficParts = parts.points.count > Self.limit || parts.nominal.count > Self.limit ? TrafficParts() : parts
        }

        /// The curve kept for `query`, if one was: a curve depends on its
        /// query alone, whatever the key (decision 217: a run under limits
        /// is worth not building again).
        func curve(for query: DirectionMemo.CurveQuery) -> RunCurve?? {
            curves[query]
        }

        /// Keeps what `memo` worked out over a call of
        /// ``advance(ticks:)`` that left all of `key` as it was.
        mutating func keep(_ memo: DirectionMemo, for key: Key) {
            self.key = key
            paths = memo.paths.found.count > Self.limit ? PathMemo() : memo.paths
            curves = memo.curves.count > Self.limit ? [:] : memo.curves
        }
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
        // Kept by the train as it is: it depends on nothing else but the
        // network and the lines, which do not change within one memo. A
        // few of each train's last values are kept (the steps of an advance
        // ask of the trains as they would have moved on, between questions
        // of the trains as they are).
        if let known = memo.serviceDirections[train.id]?.first(where: { $0.train == train }) { return known.directions }
        let directions = workedOutServiceDirections(of: train, memo: &memo)
        var known = memo.serviceDirections[train.id] ?? []
        known.insert((train, directions), at: 0)
        if known.count > 4 { known.removeLast() }
        memo.serviceDirections[train.id] = known
        return directions
    }

    /// ``serviceDirections(of:memo:)``, worked out.
    private func workedOutServiceDirections(of train: Train, memo: inout DirectionMemo) -> Set<TrackTraversal> {
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
            let moving = routeStretches(of: train).stretches.filter { $0.to > $0.from }.map(\.traversal)
            directions.formUnion(moving)
            let ahead = pathAhead(of: train)
            let end = ahead.count == train.movement.remainingEdges.count ? train.movement.end : nil
            start = placement(start, after: TrainPath(traversals: ahead, end: end, distance: 0))
            // The same for as long as its route and where it ends are: as
            // it goes along the edge it is on.
            let travel = DirectionMemo.Travel(plan: plan, moving: moving, end: start, call: next)
            if let known = memo.travels[travel] { return known }
            let ordinary = path(from: start.position, toStation: plan.calls[next].station, length: plan.length)
            let continuation = ordinary.map { (start: start, path: $0) }
                ?? passingContinuation(from: start, to: plan.calls[next].station)
            guard let continuation else {
                memo.travels[travel] = directions
                return directions
            }
            directions.formUnion(self.directions(of: continuation.path, from: continuation.start))
            start = placement(continuation.start, after: continuation.path)
            let walk = DirectionMemo.Walk(plan: plan, start: start, stop: next)
            let walked = memo.walks[walk] ?? walkedDirections(plan, from: start, stop: next)
            memo.walks[walk] = walked
            let all = directions.union(walked)
            memo.travels[travel] = all
            return all
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
        // Kept for the trains and the candidate as they are: a departure
        // asks it twice (decision 57, and with block sections decision
        // 212's way past standing trains), and again at every second a
        // step tries.
        if let known = memo.opposing[candidate.id], known.candidate == candidate, known.trains == trains { return known.traversals }
        let traversals = workedOutOpposingServiceTraversals(for: candidate, memo: &memo)
        memo.opposing[candidate.id] = (trains, candidate, traversals)
        return traversals
    }

    /// ``opposingServiceTraversals(for:memo:)``, worked out.
    private func workedOutOpposingServiceTraversals(for candidate: Train, memo: inout DirectionMemo) -> Set<TrackTraversal> {
        let parts = opposingParts(for: candidate, memo: &memo)
        var directions: Set<TrackTraversal> = []
        for part in parts.directions {
            directions.formUnion(part)
        }
        return Set(directions.map(\.reversed)).subtracting(parts.defaultWays)
    }

    /// What ``opposingServiceTraversals(for:memo:)`` is made of: the
    /// traversals the other trains and the lines are planned along, each
    /// running service's and line plan's apart, which turned round it
    /// forbids, but for `candidate`'s own default ways. Asking these of a
    /// few traversals is quicker than gathering them all.
    func opposingParts(for candidate: Train, memo: inout DirectionMemo) -> (directions: [Set<TrackTraversal>], defaultWays: Set<TrackTraversal>) {
        if let known = memo.opposingParts[candidate.id], known.candidate == candidate, known.trains == trains { return known.parts }
        let parts = workedOutOpposingParts(for: candidate, memo: &memo)
        memo.opposingParts[candidate.id] = (trains, candidate, parts)
        return parts
    }

    /// ``opposingParts(for:memo:)``, worked out.
    private func workedOutOpposingParts(for candidate: Train, memo: inout DirectionMemo) -> (directions: [Set<TrackTraversal>], defaultWays: Set<TrackTraversal>) {
        var directions: [Set<TrackTraversal>] = []
        for train in trains where train.id != candidate.id && train.position != nil {
            directions.append(serviceDirections(of: train, memo: &memo))
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
                        directions.append(plannedDirections(.init(calls: calls, length: length, repeats: true, routes: line.routes(ofService: service).isEmpty ? [] : zip(order, order.dropFirst()).map { pair in line.routes(ofService: service).first { $0.from == pair.0 && $0.to == pair.1 } } + [nil], intermediateTurnbacks: isTrafficControlEnabled && !line.isRing), memo: &memo))
                    }
                }
            }
        }
        // Default corridors may be shared in both directions (single track).
        // Only additional track borrowed by an alternative is restricted.
        let defaultWays = Set(routeStretches(of: candidate).stretches.filter { $0.to > $0.from }.map(\.traversal))
        return (directions, defaultWays)
    }
}
