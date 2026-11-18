// Decision 57: direction protection for newly borrowed alternative track.
// Derived from what can still run: each running service from where it is,
// and each line with a train placed to run it, over its whole plan. The
// memo belongs to one advance/query; it is never world or save state.

extension GameWorld {
    /// A memo for one question asked of the world as it is, lent what the
    /// last advances kept for its network, lines and settings (see
    /// ``RouteMemo/lend(toQuestion:of:)``): the same answers as a new
    /// one, worked out with less.
    func questionMemo() -> DirectionMemo {
        var memo = DirectionMemo()
        routeMemo.lend(toQuestion: &memo, of: self)
        return memo
    }

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
        /// A line plan's traversals (see ``plannedDirections(_:memo:)``).
        struct Planned: Hashable, Sendable {
            var directions: Set<TrackTraversal> = []
            /// Decision 344: those only a train standing at one berth of
            /// the first call sets off along, from there.
            var departures: Set<TrackTraversal> = []
        }
        var plans: [Plan: Planned] = [:]
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
        /// last sets of trains asked about, each with the time its claims
        /// were settled for (decision 877).
        var holders: [(trains: [Train], covers: [TrackCover?], holders: TrackHolders, at: GameTime)] = []
        /// Decision 878: how often ``holders`` has been changed, so that
        /// what was worked out from them (see ``WorldAnswers``) is known
        /// to be of them still.
        var holderChanges = 0
        /// Decision 878: the holders of another moment set aside (see
        /// ``exchangeHolders(with:)``).
        struct HolderStore {
            var holders: [(trains: [Train], covers: [TrackCover?], holders: TrackHolders, at: GameTime)] = []
            var changes = 0
            var answers = WorldAnswers()
        }

        /// Puts ``holders``, with ``holderChanges`` and what was worked
        /// out from them, into `store` and takes what `store` held: the
        /// holders are kept by the trains alone, though whom a claim binds
        /// reads the clock too (decisions 836, 850), so a question that
        /// has always been asked of holders worked out at its own second
        /// (the dispatcher's of a due run's train, see
        /// ``GameWorld/readyRunTrain(of:_:day:memo:)``) keeps its own, and
        /// leaves the step's as it found them.
        mutating func exchangeHolders(with store: inout HolderStore) {
            swap(&holders, &store.holders)
            swap(&holderChanges, &store.changes)
            swap(&answers, &store.answers)
        }
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
        var opposingParts: [TrainID: (trains: [Train], candidate: Train, parts: OpposingParts)] = [:]
        /// Each train as its last releases of the track it has passed left
        /// it (see ``releasePassedTrack(_:before:distance:memo:)``): its
        /// reservation then held nothing outside its route envelope. A few
        /// are kept: the steps of an advance try the trains moved on by
        /// different seconds from the same start.
        var released: [TrainID: [Train]] = [:]
        /// Decision 878 (TICK-REAL): the trips trains would make for runs
        /// (see ``GameWorld/runTrip(of:_:for:memo:)``), by all a trip is
        /// worked out from but what no memo outlives.
        struct RunTripQuery: Hashable, Sendable {
            let line: LineID
            /// The stops the run calls at (``ServiceLine/calls(of:)``).
            let calls: [Int]
            let from: Int
            let way: RingDirection?
            let placement: TrainPlacement
        }
        var runTrips: [RunTripQuery: RunTrip?] = [:]
        /// Decision 878: each line service's plans for a train's length,
        /// in the plans' order: what each is planned along (see
        /// ``GameWorld/plannedDirections(_:memo:)``) and its first call.
        /// A plan is its calls and every leg's route, and was put together
        /// and hashed again for every line each time a departure asked.
        struct LinePlanQuery: Hashable, Sendable {
            let line: LineID
            let service: Int
            let length: Int64
        }
        var linePlans: [LinePlanQuery: [(planned: Planned, first: StationID?)]] = [:]
        /// Decision 878: what was asked of the whole world at one moment
        /// of one step, for as long as the world stays as it was asked
        /// (see ``WorldAnswers``).
        var answers = WorldAnswers()

        /// Keeps `train` in ``released``.
        mutating func release(_ train: Train) {
            var known = released[train.id] ?? []
            guard !known.contains(train) else { return }
            known.insert(train, at: 0)
            if known.count > 4 { known.removeLast() }
            released[train.id] = known
        }
    }

    /// Decision 878 (TICK-REAL): the trains in the way (see
    /// ``trainsInTheWay(memo:)``) and the due runs that cannot leave (see
    /// ``heldRunDepartures(memo:)``), as they were last worked out, with
    /// what they were worked out from. Each line with a depot asks both of
    /// the whole world as the dispatcher goes through the lines, and again
    /// as a deadlock is looked for: on Hong Kong with every line bought
    /// they were a tenth of a day's ticks, nearly all of it the same
    /// answer worked out again for the next line.
    ///
    /// An answer is given again only to the world it was worked out from:
    /// the same trains and lines at the same second, with the step's
    /// traffic plan set or not as it was, and the memo's holders (see
    /// ``trackHolders(memo:)``) untouched since, which are dropped with
    /// what was kept here whenever they change. Within one second of one
    /// step nothing else these read changes without a train changing: a
    /// dispatch, an arrival and a departure each change their train.
    struct WorldAnswers {
        struct Key {
            let trains: [Train]
            let lines: [ServiceLine]
            let now: GameTime
            let hasStepTraffic: Bool
        }
        var key: Key?
        /// The memo's ``DirectionMemo/holderChanges`` when they were kept.
        var stamp = 0
        var inTheWay: Set<TrainID>?
        var heldRuns: [(train: TrainID, needs: Set<TrackResource>)]?
    }

    /// Whether `memo`'s ``WorldAnswers`` are of the world as it is and of
    /// the memo's holders as they are.
    func answersHold(_ memo: DirectionMemo) -> Bool {
        guard let key = memo.answers.key else { return false }
        return memo.answers.stamp == memo.holderChanges && key.now == clock.now && key.hasStepTraffic == (memo.stepTraffic != nil)
            && key.trains == trains && key.lines == lines
    }

    /// Has `memo`'s ``WorldAnswers`` be of the world as it is and of the
    /// memo's holders as they are, an answer just worked out about to be
    /// kept: those of any other are dropped. Working an answer out asks
    /// the holders only of the world's own trains, so they change at most
    /// once in it, the first time they are asked, and the answer is of the
    /// holders as it leaves them.
    func settleAnswers(_ memo: inout DirectionMemo) {
        guard !answersHold(memo) else { return }
        memo.answers = WorldAnswers(key: WorldAnswers.Key(trains: trains, lines: lines, now: clock.now, hasStepTraffic: memo.stepTraffic != nil),
                                    stamp: memo.holderChanges)
    }

    /// Tests and reports only (decision 878): has every answer given
    /// again from a memo (a run's trip, a line's plans, the trains in the
    /// way, the due runs that cannot leave) checked against the answer
    /// worked out again. `nil` in the game.
    final class AnswerAudit: @unchecked Sendable {
        var checked = 0
    }

    @TaskLocal static var answerAudit: AnswerAudit?

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
            /// Decision 878 (TICK-REAL): the lines but for when they last
            /// sent trains out (``ServiceLine/withoutDispatchTimes``), as
            /// ``ServiceKey`` has them. A path, a line's planned
            /// directions and a curve read the lines' stops, routes and
            /// sides, never a departure; with the lines whole, every
            /// minute a line with runs sent a train out threw away every
            /// path searched for, and the next minute searched for them
            /// all again.
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
                lines = world.lines.map(\.withoutDispatchTimes)
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
        /// Decision 878: the runs' trips and the lines' plans, kept with
        /// the services (they read whether traffic control is on).
        private var runTrips: [DirectionMemo.RunTripQuery: RunTrip?] = [:]
        private var linePlans: [DirectionMemo.LinePlanQuery: [(planned: DirectionMemo.Planned, first: StationID?)]] = [:]

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

        /// Decision 138 (continued, TRAFFIC-READ): gives `memo`, a new one
        /// for a question asked of `world` (not an advance), what an
        /// ``advance(ticks:)`` would be lent were it to start now: the paths
        /// and curves while `world`'s ``Key`` is the one they were kept
        /// for, and the traffic plan's parts while its ``ServiceKey`` is.
        /// The game loop's traffic reading (``routeWaits()``) worked out
        /// every running train's ``trafficPoints(of:cycle:)`` again at
        /// every tick, some 1 s a reading on the bought Kaohsiung Circular
        /// Light Rail on an iPhone 17 Pro. A question never keeps what it
        /// works out: the world is not changed by asking it.
        func lend(toQuestion memo: inout DirectionMemo, of world: GameWorld) {
            if key != nil, key == Key(world) {
                memo.paths = paths
                memo.curves = curves
            }
            if serviceKey != nil, serviceKey == ServiceKey(world) {
                memo.trafficParts = trafficParts
                memo.runTrips = runTrips
                memo.linePlans = linePlans
            }
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
            memo.directions.runTrips = runTrips
            memo.directions.linePlans = linePlans
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
            runTrips = memo.directions.runTrips.count > Self.limit ? [:] : memo.directions.runTrips
            linePlans = memo.directions.linePlans
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
    private func walkedDirections(_ plan: DirectionMemo.Plan, from start: TrainPlacement, stop: Int, paths: inout PathMemo) -> Set<TrackTraversal> {
        var directions: Set<TrackTraversal> = []
        var place = start
        var stop = stop
        var visited: Set<DirectionState> = []
        while visited.insert(DirectionState(placement: place, stop: stop)).inserted {
            guard let leg = leg(of: plan, from: place, stop: stop, paths: &paths) else { break }
            directions.formUnion(leg.directions)
            place = leg.place
            stop = leg.stop
        }
        return directions
    }

    /// The traversals of `plan`'s leg from a train at `start` standing for
    /// call `stop` (see ``walkedDirections(_:from:stop:)``), where it ends
    /// and the call it ends at; `nil` at the end of a plan that does not
    /// repeat, or where there is no way on. Decision 622: the searches are
    /// kept in `paths` (they read only the network, ``PathMemo``), so a
    /// departure tried again at every step does not search every line's
    /// plan afresh.
    private func leg(of plan: DirectionMemo.Plan, from start: TrainPlacement, stop: Int, paths: inout PathMemo) -> (directions: Set<TrackTraversal>, place: TrainPlacement, stop: Int)? {
        let next = stop + 1 == plan.calls.count ? 0 : stop + 1
        if next == 0 && !plan.repeats { return nil }
        var from = plan.calls[stop].reverses ? turnedRound(start) : start
        let preference = plan.routes.indices.contains(stop) ? plan.routes[stop] : nil
        var chosen = preference.flatMap { preferredPath(from: from.position, preference: $0, length: plan.length, memo: &paths) }
            ?? path(from: from.position, toStation: plan.calls[next].station, length: plan.length, memo: &paths)
        if chosen == nil, plan.intermediateTurnbacks, stop > 0, stop < plan.calls.count - 1, !plan.calls[stop].reverses {
            from = turnedRound(from)
            chosen = preference.flatMap { preferredPath(from: from.position, preference: $0, length: plan.length, memo: &paths) }
                ?? path(from: from.position, toStation: plan.calls[next].station, length: plan.length, memo: &paths)
        }
        guard let path = chosen else { return nil }
        return (directions(of: path, from: from), placement(from, after: path), next)
    }

    /// A line's plan from every fitting berth of its first call: a line
    /// sends its trains out from wherever they stand there. Decision 344:
    /// with the traversals of the first leg that no other berth's first
    /// leg and nothing after it takes, which only a train standing at
    /// that berth sets off along.
    private func plannedDirections(_ plan: DirectionMemo.Plan, memo: inout DirectionMemo) -> DirectionMemo.Planned {
        if let known = memo.plans[plan] { return known }
        var planned = DirectionMemo.Planned()
        if let first = plan.calls.first {
            var firstLegs: [Set<TrackTraversal>] = []
            var later: Set<TrackTraversal> = []
            for berth in berths(of: first.station, length: plan.length) {
                let place = TrainPlacement(position: .onEdge(berth.traversal, offset: berth.offset), trailEdges: [], length: plan.length)
                guard let leg = leg(of: plan, from: place, stop: 0, paths: &memo.paths) else { continue }
                firstLegs.append(leg.directions)
                later.formUnion(walkedDirections(plan, from: leg.place, stop: leg.stop, paths: &memo.paths))
            }
            var legsTaking: [TrackTraversal: Int] = [:]
            for firstLeg in firstLegs {
                for traversal in firstLeg { legsTaking[traversal, default: 0] += 1 }
            }
            planned.directions = later.union(legsTaking.keys)
            planned.departures = Set(legsTaking.filter { $0.value == 1 && !later.contains($0.key) }.keys)
        }
        memo.plans[plan] = planned
        return planned
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
        // Decision 703: the train's line looked up once.
        let line = assignedLine(of: train.id, memo: &memo)
        let routes = line.map { line in
            hasRoutePreferences(train, on: line) ? train.timetable.indices.map { routePreference(for: train, on: line, from: $0, to: ($0 + 1) % train.timetable.count) } : []
        } ?? []
        let plan = DirectionMemo.Plan(calls: train.timetable.map { DirectionMemo.Call(station: $0.station, reverses: $0.reverses) },
                                      length: train.length, repeats: train.timetablePeriod != nil, routes: routes)
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
            let ordinary = path(from: start.position, toStation: plan.calls[next].station, length: plan.length, memo: &memo.paths)
            let continuation = ordinary.map { (start: start, path: $0) }
                ?? passingContinuation(from: start, to: plan.calls[next].station)
            guard let continuation else {
                memo.travels[travel] = directions
                return directions
            }
            directions.formUnion(self.directions(of: continuation.path, from: continuation.start))
            start = placement(continuation.start, after: continuation.path)
            let walk = DirectionMemo.Walk(plan: plan, start: start, stop: next)
            let walked = memo.walks[walk] ?? walkedDirections(plan, from: start, stop: next, paths: &memo.paths)
            memo.walks[walk] = walked
            let all = directions.union(walked)
            memo.travels[travel] = all
            return all
        }
        let walk = DirectionMemo.Walk(plan: plan, start: start, stop: stop)
        if let known = memo.walks[walk] { return directions.union(known) }
        let walked = walkedDirections(plan, from: start, stop: stop, paths: &memo.paths)
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
    func opposingParts(for candidate: Train, memo: inout DirectionMemo) -> OpposingParts {
        if let known = memo.opposingParts[candidate.id], known.candidate == candidate, known.trains == trains { return known.parts }
        let parts = workedOutOpposingParts(for: candidate, memo: &memo)
        memo.opposingParts[candidate.id] = (trains, candidate, parts)
        return parts
    }

    /// ``opposingParts(for:memo:)``, worked out.
    private func workedOutOpposingParts(for candidate: Train, memo: inout DirectionMemo) -> OpposingParts {
        var directions: [Set<TrackTraversal>] = []
        var departures: [Int: (station: StationID, traversals: Set<TrackTraversal>)] = [:]
        for train in trains where train.id != candidate.id && train.position != nil {
            directions.append(serviceDirections(of: train, memo: &memo))
        }
        for line in lines {
            for service in 0..<line.serviceCount {
                // Another placed train will run the plan: the candidate
                // itself is never protected from its own line.
                let lengths = Set(line.trains(ofService: service).filter { $0 != candidate.id }.compactMap { train(id: $0) }.filter { $0.position != nil }.map(\.length))
                guard !lengths.isEmpty else { continue }
                // Decision 878: each length's plans kept by the line, in
                // the order they were gone through before: every plan,
                // and for each every length.
                let planned = lengths.map { linePlans(of: line, service: service, length: $0, memo: &memo) }
                for plan in 0..<(planned.first?.count ?? 0) {
                    for plans in planned {
                        if !plans[plan].planned.departures.isEmpty, let first = plans[plan].first {
                            departures[directions.count] = (first, plans[plan].planned.departures)
                        }
                        directions.append(plans[plan].planned.directions)
                    }
                }
            }
        }
        // Default corridors may be shared in both directions (single track).
        // Only additional track borrowed by an alternative is restricted.
        let defaultWays = Set(routeStretches(of: candidate).stretches.filter { $0.to > $0.from }.map(\.traversal))
        return OpposingParts(directions: directions, defaultWays: defaultWays, departures: departures)
    }

    /// Decision 878 (TICK-REAL): what each plan of `line`'s service
    /// `service` (see ``plans(of:service:)``) is planned along for a train
    /// `length` long, and its first call, in the plans' order, kept in
    /// `memo` by the line: they read the line's stops and routes, the
    /// network and whether traffic control is on, none of which changes
    /// within one memo.
    private func linePlans(of line: ServiceLine, service: Int, length: Int64, memo: inout DirectionMemo) -> [(planned: DirectionMemo.Planned, first: StationID?)] {
        let query = DirectionMemo.LinePlanQuery(line: line.id, service: service, length: length)
        if let known = memo.linePlans[query] {
            if let audit = Self.answerAudit {
                audit.checked += 1
                let again = plans(of: line, service: service).map { plan in (plannedDirections(plan(length), memo: &memo), plan(length).calls.first?.station) }
                precondition(again.count == known.count && zip(again, known).allSatisfy { $0.0 == $1.planned && $0.1 == $1.first },
                             "a line's plans kept are not the plans worked out again")
            }
            return known
        }
        let worked = plans(of: line, service: service).map { plan -> (planned: DirectionMemo.Planned, first: StationID?) in
            let plan = plan(length)
            return (plannedDirections(plan, memo: &memo), plan.calls.first?.station)
        }
        memo.linePlans[query] = worked
        return worked
    }

    /// The plans of `line`'s service `service` (a ring's both ways round,
    /// or out and back), for a train of the length given.
    private func plans(of line: ServiceLine, service: Int) -> [(Int64) -> DirectionMemo.Plan] {
        let orders = line.isRing ? RingDirection.allCases.map { line.ringCalls($0) }
            : [line.calls(ofService: service) + line.calls(ofService: service).dropLast().reversed()]
        let routes = line.routes(ofService: service)
        let turnbacks = isTrafficControlEnabled && !line.isRing
        return orders.map { order in
            let calls = order.enumerated().map { index, station in
                DirectionMemo.Call(station: line.stops[station], reverses: !line.isRing && (index == order.count / 2 || index == order.count - 1))
            }
            let preferences = routes.isEmpty ? [] : zip(order, order.dropFirst()).map { pair in routes.first { $0.from == pair.0 && $0.to == pair.1 } } + [nil]
            return { length in DirectionMemo.Plan(calls: calls, length: length, repeats: true, routes: preferences, intermediateTurnbacks: turnbacks) }
        }
    }

    /// Decision 527: the traversals `line`'s plans run along one way only,
    /// turned round: track its trains of `length` take only the other way.
    func oneWayAgainst(_ line: ServiceLine, length: Int64) -> Set<TrackTraversal> {
        var memo = DirectionMemo()
        var planned: Set<TrackTraversal> = []
        for service in 0..<line.serviceCount {
            for plan in plans(of: line, service: service) { planned.formUnion(plannedDirections(plan(length), memo: &memo).directions) }
        }
        return Set(planned.filter { !planned.contains($0.reversed) }.map(\.reversed))
    }

    /// Decision 527: for an empty run of a line with real runs (`train`),
    /// with traffic control off, the traversals its line takes only the
    /// other way, which its way keeps off (kept in `memo`); `nil` when the
    /// rule does not apply. Decision 228 keeps trains apart then and no
    /// deadlock is undone: one out of a depot that crossed onto the other
    /// way's track met the line's trains head on, and each waited for the
    /// other for good (the Sanying line).
    func lineAgainst(for train: Train, memo: inout PathMemo) -> Set<TrackTraversal>? {
        guard train.isDeadheading, !isTrafficControlEnabled, followsRealTimetable(train),
              let line = lines.first(where: { $0.trains.contains(train.id) }) else { return nil }
        let key = PathMemo.LineAgainst(line: line.id, length: train.length)
        if let known = memo.against[key] { return known }
        let against = oneWayAgainst(line, length: train.length)
        memo.against[key] = against
        return against
    }

    /// Decision 527: `path`, the way `train` would go from `start` to
    /// station `id`, changed to keep off `against` (``lineAgainst(for:memo:)``);
    /// `nil` when it keeps off it already, or no way does. Decision 547
    /// (L6-4): keeping off the edges of `standing` too where another way
    /// serves, as the way out of a depot it changes did
    /// (``pathOutOfDepot(_:to:from:for:nearest:)``).
    func lineDirectionPath(_ path: TrainPath, from start: TrainPosition, toStation id: StationID, for train: Train, against: Set<TrackTraversal>, avoiding standing: Set<TrackEdgeID> = []) -> TrainPath? {
        guard path.traversals.contains(where: against.contains) else { return nil }
        guard standing.isEmpty else { return self.path(from: start, toStation: id, length: train.length, forbidden: against, avoiding: standing) }
        return self.path(from: start, toStation: id, length: train.length, avoiding: Set<TrackResource>(), forbidden: against)
    }

    /// Decision 344: the traversals of `path` into station `id` that only
    /// lines with `id` as their first call are planned the other way
    /// along, and only by the departures of one berth there (see
    /// ``plannedDirections(_:memo:)``): those the direction protection of
    /// decision 57 does not forbid on a way to `id`. A train sets off from
    /// a berth only from standing at it, and a way to a berth is taken
    /// only while it is free and then held, so the two never meet; as
    /// into a terminus (decision 278), but without block sections too,
    /// where such a way is taken whole.
    func firstCallTraversals(along path: TrainPath, to id: StationID, parts: OpposingParts) -> Set<TrackTraversal> {
        let departures = parts.departures.filter { $0.value.station == id }
        guard !departures.isEmpty else { return [] }
        return Set(path.traversals.filter { traversal in
            let opposite = traversal.reversed
            guard departures.values.contains(where: { $0.traversals.contains(opposite) }) else { return false }
            return !parts.directions.indices.contains { index in
                parts.directions[index].contains(opposite) && departures[index]?.traversals.contains(opposite) != true
            }
        })
    }
}

extension GameWorld {
    /// What ``GameWorld/opposingServiceTraversals(for:memo:)`` is made of
    /// (see ``GameWorld/opposingParts(for:memo:)``).
    struct OpposingParts {
        /// Each running service's and line plan's traversals.
        let directions: [Set<TrackTraversal>]
        /// The candidate's own default ways.
        let defaultWays: Set<TrackTraversal>
        /// Decision 344: of the line plans among ``directions``, by index,
        /// their first call and the departures from one of its berths.
        let departures: [Int: (station: StationID, traversals: Set<TrackTraversal>)]
    }
}
