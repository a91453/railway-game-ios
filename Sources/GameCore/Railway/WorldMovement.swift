// The world in time (decision 910, cut 3): trains moving, their runs and their movement authorities.
// Moved from GameWorld.swift unchanged.

extension GameWorld {
    /// Phase 4 of a basic step: every travelling service whose train is now
    /// stopped at the station of the stop it travels to waits at that stop.
    /// Returns whether any service arrived.
    mutating func recordArrivals() -> Bool {
        var arrived = false
        for index in trains.indices {
            guard case .travellingToStop(let stop, let cycle)? = trains[index].execution else { continue }
            // Decision 379: the train as a local, not `trains[index]` as an
            // argument, which copied the whole world for each call.
            let train = trains[index]
            guard isStopped(train, at: train.timetable[stop].station) else { continue }
            trains[index].execution = .waitingAtStop(stop, cycle: cycle)
            trains[index].times = ServiceTimes(arrival: clock.now, departure: trains[index].times?.departure)
            arrived = true
            logArrival(of: index)
            // Decision 207: a trip at its last call counts towards its
            // line's punctuality, as the reference counts a train's final
            // delay once a day.
            if realisticOperation, stop == train.timetable.count - 1, !train.isDeadheading,
               let line = assignedLine(of: train.id), self.line(id: line)?.isFreight == false {
                let scheduled = trains[index].scheduledArrival(of: stop, cycle: cycle)
                countLineTrip(on: line, late: Self.gap(from: scheduled, to: clock.now))
            }
        }
        return arrived
    }

    /// The first second after `now` at which some service's dwell moves on
    /// by itself (Stage W2b), or `nil` if none does: a train's doors finish
    /// opening, its doors start closing, or its departure comes; or (Stage
    /// W2c) a travelling train's run comes to its end, after which a train
    /// held up on the way sets off again (see ``resumeRun(_:at:)``). A
    /// departure that has come and could not be made (no route, or its
    /// route held) is not an event: it is tried again at every step, and
    /// can only succeed once something else has changed; nor is a held-up
    /// train that cannot move yet. Boarding at whole minutes needs no
    /// event: every whole minute ends a step anyway.
    func nextServiceEvent(after now: GameTime) -> GameTime? {
        var known = TrainLineIndex()
        return nextServiceEvent(after: now, known: &known)
    }

    /// ``nextServiceEvent(after:)``, the rings' trains looked up in `known`
    /// (decision 703).
    func nextServiceEvent(after now: GameTime, known: inout TrainLineIndex) -> GameTime? {
        var soonest: GameTime?
        for train in trains {
            guard let execution = train.execution, let times = train.times else { continue }
            let event: GameTime?
            if case .waitingAtStop(let stop, let cycle) = execution {
                if times.exchangeEnd == nil {
                    event = Self.saturating(times.arrival, plus: ServiceDwell.doorOpening)
                } else if times.closing == nil {
                    event = closingStart(of: train, stop: stop, cycle: cycle, times: times, known: &known)
                } else {
                    event = departureDue(of: train)
                }
            } else {
                event = times.run?.end
            }
            if let event, event > now, event < soonest ?? .init(seconds: .max) {
                soonest = event
            }
        }
        return soonest
    }

    /// The whole minutes from now, the start of a minute, that an idle step
    /// may skip before the next service event at or after now (see
    /// ``nextServiceEvent(after:)``) or the next second in which a run takes
    /// a train on (see ``nextRunMove(from:)``), or `nil` if there is
    /// neither. The step just taken ended at now, so an event at now has not
    /// been seen yet. None at all while a train waits with its doors open
    /// and passengers may come at a whole minute and get on: those released
    /// (`passengersWaiting`), or those changing trains who become ready now
    /// or later (Phase 5F, ``WaitingGroup/readyAt``), with or without a
    /// release.
    func wholeMinutesUntilNextServiceEvent(passengersWaiting: Bool) -> Int64? {
        let now = clock.now
        if trains.contains(where: { train in
            if case .waitingAtStop? = train.execution, train.times?.closing == nil { return true }
            return false
        }), passengersWaiting || passengers.contains(where: { $0.waiting.contains { $0.readyAt.map { $0 >= now } ?? false } }) {
            return 0
        }
        guard let event = [nextServiceEvent(after: Self.saturating(now, plus: -1)), nextRunMove(from: now)].compactMap({ $0 }).min() else {
            return nil
        }
        let (gap, overflow) = event.seconds.subtractingReportingOverflow(now.seconds)
        return overflow ? .max : gap / GameTime.secondsPerMinute
    }

    /// The first second, at or after `now`, in which the run of some
    /// travelling service's train takes it farther along its curve than it
    /// had come by `now`, or `nil` if none has a run (Stage W2c): the second
    /// that ends when it has. A slow run can leave its train where it is for
    /// whole minutes, and then take it on: that is a change an idle minute
    /// does not foresee (or, when the train cannot go on, its run is dropped
    /// then; see ``dropRunsHeldUp(endingAt:memo:)``). Never after the run's last
    /// second. Only the shortcut over idle minutes needs it: a step that
    /// moves a train is not idle.
    private func nextRunMove(from now: GameTime) -> GameTime? {
        var soonest: GameTime?
        for train in trains {
            guard case .travellingToStop? = train.execution, let run = train.times?.run, run.end > now,
                  let curve = runCurve(of: run, for: train.performance)
            else { continue }
            let covered = run.distance(on: curve, from: run.start, to: now)
            // The least second in (now, end] by which the curve has come
            // farther: at the end it has come all the way.
            var (low, high) = (Self.saturating(now, plus: 1).seconds, run.end.seconds)
            while low < high {
                let middle = low + (high - low) / 2
                if run.distance(on: curve, from: run.start, to: GameTime(seconds: middle)) > covered {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            // The second that ends at `low`; `low > now`, so it is not
            // before now.
            if low - 1 < soonest?.seconds ?? .max {
                soonest = GameTime(seconds: low - 1)
            }
        }
        return soonest
    }

    /// The seconds, from `start` and at most `span`, in which the first
    /// placed train with a rate comes to the end of the way it can go (see
    /// ``routeStretches(of:)``), or `nil` if none does within `span` (Stage
    /// W2b): its service arrives then, or its route is released, so the
    /// step ends there.
    ///
    /// - Precondition: `start.secondOfMinute + span <= 60`.
    func secondsUntilARouteEnds(from start: GameTime, within span: Int64, memo: inout DirectionMemo) -> Int64? {
        var soonest: Int64?
        for train in trains where train.movement.rate > 0 && train.position != nil {
            let route = routeStretches(of: train)
            guard route.moves else { continue }
            var left: Int64 = 0
            for stretch in route.stretches {
                let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
                left = overflow ? .max : sum
            }
            let limit = soonest.map { $0 - 1 } ?? span
            let share = travelShare(of: train, from: start, memo: &memo)
            guard limit >= 1, share(limit) >= left else { continue }
            // Where the travel ends decides: a train held up on the way never
            // comes to its end, however far it may go.
            let end = travelling(train, distance: left)
            var arrived = train
            arrived.position = end.position
            arrived.movement.cursor = end.cursor
            guard !routeStretches(of: arrived).moves else { continue }
            // The least `k` whose distance covers what is left.
            var (low, high) = (Int64(1), limit)
            while low < high {
                let middle = (low + high) / 2
                if share(middle) >= left {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            soonest = low
        }
        return soonest
    }

    /// The travel of `span` basic steps from `start`, for every placed train
    /// with a rate, in ascending ID order: each train's share for those
    /// seconds (see ``travelShare(of:from:memo:)``), in one move. The moves of
    /// the seconds one at a time add up to it, since a move depends on the
    /// map alone. Returns whether any train changed.
    /// `memo` keeps the trains' movement authorities (see
    /// ``authority(of:memo:)``).
    mutating func moveTrains(from start: GameTime, for span: Int64, memo: inout DirectionMemo) -> Bool {
        var moved = false
        for index in trains.indices {
            let movement = trains[index].movement
            guard let position = trains[index].position, movement.rate > 0 else { continue }
            // Decision 379: `before`, not `trains[index]`, as the argument,
            // which copied the whole world for each call.
            let before = trains[index]
            let distance = travelShare(of: before, from: start, memo: &memo)(span)
            guard distance > 0 else { continue }
            let travel = travelling(before, distance: distance, memo: &memo)
            // Decision 248: what it has gone of its allowance.
            if let allowance = spacingAllowances[trains[index].id], allowance.left != .max {
                spacingAllowances[trains[index].id]?.left = allowance.left - min(distance, allowance.left)
            }
            guard travel.position != position || travel.cursor != movement.cursor else { continue }
            switch (position, travel.position) {
            case (.onEdge(let traversal, _), .onEdge(_, let reached)):
                trains[index].trailEdges = networkTrail(
                    after: traversal.edge, trail: before.trailEdges,
                    entered: movement.edges[movement.cursor..<travel.cursor], offset: reached, length: before.length
                )
                // Decision 756: the switches it went through lie its way.
                if switchInterlocking { noteSwitches(from: traversal, entering: movement.edges[movement.cursor..<travel.cursor]) }
            }
            trains[index].position = travel.position
            if travel.cursor == movement.edges.count {
                // Every edge has been entered: the path is spent. Where the
                // path ends (Stage S5) is now on the train's own edge, and
                // stays.
                trains[index].movement.edges = []
                trains[index].movement.cursor = 0
            } else {
                trains[index].movement.cursor = travel.cursor
            }
            releasePassedTrack(index, before: before, distance: distance, memo: &memo)
            moved = true
        }
        return moved
    }

    /// Stage W2c: every travelling service's train that could not follow its
    /// run (see ``ServiceRun``) up to `end`, the end of a step, drops it:
    /// held by a rate of 0, or by track ahead that was removed, it has
    /// more way left than its curve has left to go. Its curve no longer says
    /// where it is; it sets off again from a stand once it can (see
    /// ``resumeRun(_:at:)``). Within a step the map and the rates cannot
    /// change, so a train held up at one second of it is held up at its
    /// end. Returns whether any run was dropped.
    mutating func dropRunsHeldUp(endingAt end: GameTime, memo: inout DirectionMemo) -> Bool {
        var dropped = false
        for index in trains.indices {
            guard case .travellingToStop? = trains[index].execution, let run = trains[index].times?.run else { continue }
            // Decision 379: the train as a local, not `trains[index]` as an
            // argument, which copied the whole world for each call.
            let train = trains[index]
            guard let curve = curve(of: run, for: train.performance, memo: &memo) else { continue }
            var left: Int64 = 0
            for stretch in routeStretches(of: train).stretches {
                let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
                left = overflow ? .max : sum
            }
            guard left > run.length - run.distance(on: curve, from: run.start, to: end) else { continue }
            // Decision 228: a train of real runs, held up by the train ahead
            // with traffic control off, keeps its run, later by the time it
            // lost: it goes on at its pace once it can. Decision 248: as the
            // minute ends, as its allowances run (so the same however the
            // minute's seconds are stepped).
            let spaced = !isTrafficControlEnabled && followsRealTimetable(train)
            if spaced, !end.isWholeMinute { continue }
            if spaced, let late = runDelay(run, curve: curve, covered: run.length - left, at: end) {
                trains[index].times?.run = run.delayed(by: late)
                dropped = true
                continue
            }
            trains[index].times?.run = nil
            dropped = true
        }
        return dropped
    }

    /// How far placed train `train`, with a rate, may travel in the first
    /// `k` seconds from `start`, for `k` from 0 to the end of `start`'s
    /// minute: along its service's run (Stage W2c, see ``ServiceRun``) how
    /// much farther its curve has come by then, and otherwise its share of
    /// its rate (see ``TrainMovement/distance(at:fromSecond:toSecond:)``).
    /// Never less for a larger `k`. The curve is built once, for all of
    /// them.
    func travelShare(of train: Train, from start: GameTime, memo: inout DirectionMemo) -> (Int64) -> Int64 {
        if case .travellingToStop? = train.execution, let run = train.times?.run {
            guard let curve = curve(of: run, for: train.performance, memo: &memo) else { return { _ in 0 } }
            return { k in run.distance(on: curve, from: start, to: Self.saturating(start, plus: k)) }
        }
        let rate = train.movement.rate
        let second = start.secondOfMinute
        return { k in TrainMovement.distance(at: rate, fromSecond: second, toSecond: second + k) }
    }

    /// Works out and keeps the curve of each run under curve limits that
    /// has none yet (decision 217, ``ServiceRun/solving(for:)``): once, as
    /// a step begins, rather than for every run a train is offered and
    /// then not given.
    mutating func solveRuns() {
        for index in trains.indices {
            guard let run = trains[index].times?.run, !run.limits.isEmpty else { continue }
            let solved = run.solving(for: trains[index].performance)
            trains[index].times?.run = solved
        }
    }

    /// `run`'s curve for `performance` (see ``ServiceRun/curve(for:)``), as
    /// the last call of ``advance(ticks:)`` kept it when it did (decision
    /// 217: a run under curve limits takes a while to build).
    public func runCurve(of run: ServiceRun, for performance: TrainPerformance) -> RunCurve? {
        let query = DirectionMemo.CurveQuery(length: run.length, seconds: run.seconds, performance: performance, limits: run.limits)
        if let known = routeMemo.curve(for: query) { return known }
        return run.curve(for: performance)
    }

    /// `run`'s curve for `performance` (see ``ServiceRun/curve(for:)``),
    /// kept in `memo`: a run's curve is asked of at every second it runs.
    func curve(of run: ServiceRun, for performance: TrainPerformance, memo: inout DirectionMemo) -> RunCurve? {
        let query = DirectionMemo.CurveQuery(length: run.length, seconds: run.seconds, performance: performance, limits: run.limits)
        if let known = memo.curves[query] { return known }
        let curve = run.curve(for: performance)
        memo.curves[query] = .some(curve)
        return curve
    }

    /// Where placed train `train` ends up after travelling up to `distance`
    /// units, and its cursor: each edge as long as it is (Stage S3), up to
    /// where its path ends, and under traffic control no farther than its
    /// movement authority (Stage U2, see ``authorityLeft(of:)``). It depends
    /// on the network and the train's reservation alone.
    func travelling(_ train: Train, distance: Int64) -> (position: TrainPosition, cursor: Int) {
        var memo = DirectionMemo()
        return travelling(train, distance: distance, memo: &memo)
    }

    /// ``travelling(_:distance:)`` with the train's movement authority kept
    /// in `memo` (see ``authority(of:memo:)``).
    func travelling(_ train: Train, distance: Int64, memo: inout DirectionMemo) -> (position: TrainPosition, cursor: Int) {
        var distance = authority(of: train, memo: &memo).map { min(distance, $0.left) } ?? distance
        // Decision 248: without traffic control, a train of real runs goes
        // no farther in a minute than its allowance (decision 228).
        if let allowance = spacingAllowances[train.id], allowance.left < distance { distance = max(0, allowance.left) }
        let movement = train.movement
        switch train.position! {
        case .onEdge(let traversal, let offset):
            return TrainMovement.travel(
                along: traversal, offset: offset, length: network.edge(traversal.edge)!.length,
                distance: distance, edges: movement.edges, cursor: movement.cursor, end: movement.end,
                enter: { networkEntry(after: $0, into: $1) }
            )
        }
    }

    /// Stage U (ARCHITECTURE decision 55): once train `index` has moved,
    /// its reservation keeps only the track it still needs (see
    /// ``routeEnvelope(of:)``): what it stands on, what its head has still
    /// to pass over and the junctions all that fouls. Track its tail has
    /// left behind is released at once, and once it has come to the end of
    /// its route (it stands, with no distance left to go) all of it is
    /// (Stage T). What it stands on stays held as long as it stands there.
    /// A train only ever goes on along its route, so what it needs only
    /// ever shrinks: nothing is taken here, and nothing the train will
    /// still use is released.
    private mutating func releasePassedTrack(_ index: Int, before: Train, distance: Int64, memo: inout DirectionMemo) {
        // Decision 379: the train as a local, not `trains[index]` as an
        // argument, which copied the whole world for each call.
        let train = trains[index]
        guard !train.reservation.isEmpty else { return }
        // Nothing to release when its reservation held nothing outside its
        // route envelope as it was (as its last release left it, the train
        // unchanged since), it went no further than its length, and its
        // body covers all its body covered: the envelope it had is then
        // what its body covered and what its envelope covers now, its head
        // having gone only over track its body now covers.
        if memo.released[before.id]?.contains(before) == true, distance <= before.length, routeStretches(of: train).moves {
            let now = cover(of: bodyStretches(of: train))
            let was = bodyStretches(of: before)
            if resources(covering: was).allSatisfy(now.contains), foulingNodes(covering: was).allSatisfy(now.contains) {
                memo.release(train)
                return
            }
        }
        defer { memo.release(trains[index]) }
        // Its route envelope (see ``routeEnvelope(of:)``), asked a resource
        // at a time (see ``TrackCover``).
        let route = routeStretches(of: train)
        guard route.moves else {
            trains[index].reservation = []
            return
        }
        let envelope = cover(of: bodyStretches(of: train) + route.stretches)
        trains[index].reservation = envelope.kept(of: train.reservation)
    }

    /// Stage U2: every train that follows another, in ascending ID order,
    /// takes more of its route if it can: all of it once no other train
    /// holds any of it (it no longer follows), or else as far as
    /// ``followingGap`` short of the first track another holds, if that is
    /// farther than it holds now. Comes first in each step, before any
    /// train sets off: trains already on the way go on first. Returns
    /// whether any reservation changed.
    mutating func extendAuthorities() -> Bool {
        var memo = DirectionMemo()
        return extendAuthorities(memo: &memo)
    }

    /// ``extendAuthorities()`` with the trains' holders and authorities kept
    /// in `memo` (see ``trackHolders(memo:)``).
    mutating func extendAuthorities(memo: inout DirectionMemo) -> Bool {
        var extended = false
        // Worked out again once a reservation changes.
        var holders: TrackHolders?
        for index in trains.indices {
            // Decision 379: the train as a local, not `trains[index]` as an
            // argument, which copied the whole world for each call.
            let train = trains[index]
            guard let (held, envelopes) = authority(of: train, memo: &memo) else { continue }
            // Decision 294: a long leg of a line with runs, no farther than
            // its approach allows yet.
            let limit = approachLimit(of: train, holding: held, envelopes)
            if let limit, held >= limit { continue }
            // Its route envelope (see ``routeEnvelope(of:)``): the base and
            // the track of every stretch, asked a resource at a time.
            let route = followingCover(of: train, envelopes, memo: &memo)
            if holders == nil { holders = trackHolders(memo: &memo) }
            if limit == nil, holder(of: route, except: train.id, holders: holders!) == nil {
                trains[index].reservation = Set(route.resources).sorted()
                extended = true
                holders = nil
                continue
            }
            if approachesStandingTrain(train, along: route, holders: holders!) { continue }
            let clear = clearOfBlocked(blockedTrack(except: train.id, holders: holders!))
            let free = longestAuthority(envelopes, from: held, clearBase: clear.base(envelopes.base), clear: clear.stretch)
            let authority = min(followingAuthority(envelopes, free: free), limit ?? .max)
            guard authority > held else { continue }
            trains[index].reservation = reservation(train.reservation, extending: envelopes, from: held, to: authority)
            extended = true
            holders = nil
        }
        return extended
    }

    /// Whether ``extendAuthorities()`` would give any train more of its
    /// route now: some following train's track as far as just beyond
    /// ``followingGap`` past its authority is free. One train taking more
    /// only ever leaves the others less, so the first that could is the
    /// first that does.
    private func canExtendAnyAuthority(memo: inout DirectionMemo) -> Bool {
        var authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?] = []
        for train in trains {
            authorities.append(authority(of: train, memo: &memo))
        }
        guard authorities.contains(where: { $0 != nil }) else { return false }
        let holders = trackHolders(memo: &memo)
        return zip(trains, authorities).contains { train, authority in
            guard let (held, envelopes) = authority else { return false }
            if let limit = approachLimit(of: train, holding: held, envelopes), held >= limit { return false }
            let reach = reachToExtend(envelopes, beyond: held) ?? .max
            let clear = clearOfBlocked(blockedTrack(except: train.id, holders: holders))
            return isAuthority(envelopes, to: reach, clearBase: clear.base(envelopes.base), clear: clear.stretch)
                && !approachesStandingTrain(train, along: followingCover(of: train, envelopes, memo: &memo), holders: holders)
        }
    }

    /// Decision 308: whether `train`, following others along `route` (its
    /// route envelope) without block sections, would go on towards a
    /// line's train that ends its service or turns round on that route,
    /// not beside it: standing without a service where its path ends,
    /// standing for such a call, or travelling to one it stops for there
    /// (see ``stopsOn(_:_:fouling:)``). Such a train is no train to follow
    /// (see ``isLeading(_:onto:for:)``): it comes no nearer until that
    /// train has gone, or it could stand on the only way that train has
    /// out, as THSR 31 did in Zuoying's throat behind THSR 19.
    func approachesStandingTrain(_ train: Train, along route: TrackCover, holders: TrackHolders) -> Bool {
        guard !blockSections else { return false }
        let holding = holders.holding(route, except: train.id, fouling: false, in: network)
        return zip(trains, holding).contains { other, holds in
            guard holds, assignedLine(of: other.id) != nil else { return false }
            switch other.execution {
            case nil:
                return !routeStretches(of: other).moves
            case .waitingAtStop(let stop, let cycle)?:
                return other.timetable[stop].reverses || other.call(after: stop, cycle: cycle) == nil
            case .travellingToStop(let stop, let cycle)?:
                return (other.timetable[stop].reverses || other.call(after: stop, cycle: cycle) == nil) && stopsOn(route, other, fouling: false)
            }
        }
    }

    /// A departure due at the start of a step whose route another train
    /// holds (Stage T): the train as it would set off, and as it would set
    /// off on the whole routes it tries first (its scheduled path, decision
    /// 59, and its line's preferred one, decision 61), which with block
    /// sections it may also follow the trains ahead on (decision 212).
    struct HeldRoute {
        let candidate: Train
        var whole: [Train] = []
    }

    /// The seconds, from `start` and at most `span`, after which one of
    /// `held` could set off (wholly, or following the trains ahead, Stage
    /// U2), or a train following others could take more of its route, or
    /// `nil` if that does not happen within `span` (Stage U): trains moving
    /// on release the track behind them (see ``releasePassedTrack(_:before:distance:memo:)``),
    /// so the step ends there and the departure or the following train
    /// tries again at the next, as it would one second at a time. Every
    /// train only moves on in the step, and what it holds only shrinks as it
    /// does, so once free the track stays free, up to the step's last
    /// second: `span` ends where a train comes to the end of its route
    /// (``secondsUntilARouteEnds(from:within:memo:)``), and there it no longer
    /// leads a train that would follow it, so only the seconds before
    /// `span` are asked.
    ///
    /// `moves` gets the trains as each span tried leaves them (see
    /// ``moveTrains(from:for:memo:)``), and whether any moved.
    ///
    /// - Precondition: `start.secondOfMinute + span <= 60`.
    func secondsUntilARouteFrees(
        _ held: [HeldRoute], from start: GameTime, within span: Int64, moves: inout [Int64: (trains: [Train], spacing: [TrainID: SpacingAllowance], lies: [TrackNodeID: SwitchLie], moved: Bool)],
        memo: inout DispatchMemo
    ) -> Int64? {
        func frees(after seconds: Int64) -> Bool {
            var moved = self
            let any = moved.moveTrains(from: start, for: seconds, memo: &memo.directions)
            moves[seconds] = (moved.trains, moved.spacingAllowances, moved.switchLies, any)
            // The cheaper question first: either answer frees.
            if moved.canExtendAnyAuthority(memo: &memo.directions) {
                return true
            }
            return held.contains { route in
                for train in route.whole {
                    // Decision 718: and it is its turn.
                    if case .granted(let granted) = moved.reserving(train, following: blockSections, memo: &memo.directions),
                       moved.turnOwed(by: granted, memo: &memo.directions) == nil { return true }
                }
                if case .granted = moved.reservingDeparture(route.candidate, memo: &memo.directions) { return true }
                return false
            }
        }
        // The least `k` after which one is free. A train following another
        // moving on takes more of its route almost every second, so then
        // the first second is tried first.
        var low: Int64 = 1
        if trains.contains(where: { isFollowing($0, memo: &memo.directions) }) {
            if frees(after: 1) { return 1 }
            low = 2
        }
        // The step ends after `span` anyway, so only the seconds before it
        // are asked. After `span` a train may have come to the end of its
        // route (see ``secondsUntilARouteEnds(from:within:memo:)``), and one
        // that has no longer leads the way (see
        // ``isLeading(_:onto:for:)``): a departure that could follow it a
        // second earlier may not then.
        let last = span - 1
        guard last >= 1, frees(after: last) else { return nil }
        // Once free, free at every second after (see above), so the least
        // `k` is found by trying the seconds just ahead first, a widening
        // stretch of them at a time (the next track to free is most often
        // a second or two away), then halving the stretch it lies in.
        var high = last
        var width: Int64 = 1
        while low < high {
            let probe = min(low + width - 1, high - 1)
            if frees(after: probe) {
                high = probe
                break
            }
            low = probe + 1
            width *= 2
        }
        while low < high {
            let middle = (low + high) / 2
            if frees(after: middle) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    /// The seconds, from `start` and at most `span`, after which a step
    /// under `plan`, a traffic plan with waits (decision 59), must end so
    /// that it does what a step every second would, or `nil` if it need
    /// not end before `span`: the second a wait's train may leave (the
    /// wait's departure, or its release, see ``trafficReleased(_:)``), or
    /// the second a train's head reaches the berth of a point a wait needs,
    /// where ``recordTrafficVisits(_:before:)`` records the visit at that
    /// second. A train only goes on along its route in a step, and the plan
    /// and every train's service stay as they are until a step ends (a
    /// changed plan, an arrival and a departure each end one), so nothing
    /// else a wait reads changes within it.
    ///
    /// - Precondition: `start.secondOfMinute + span <= 60`.
    func secondsUntilTrafficChanges(_ plan: TrafficPlan, from start: GameTime, within span: Int64, memo: inout DirectionMemo) -> Int64? {
        var soonest: Int64?
        func note(_ seconds: Int64) {
            if seconds >= 1, seconds < (soonest ?? span) { soonest = seconds }
        }
        for wait in plan.waits {
            let holdEnd = train(id: wait.train).flatMap { trafficHoldEnd(wait, of: $0) }
            for time in [wait.departure, trafficReleased(wait), holdEnd].compactMap({ $0 }) where time > start {
                let (gap, overflow) = time.seconds.subtractingReportingOverflow(start.seconds)
                if !overflow { note(gap) }
            }
        }
        for train in trains where train.movement.rate > 0 && train.position != nil {
            guard let execution = train.execution, let service = plan.services.first(where: { $0.train.id == train.id }) else { continue }
            let needed = service.points.filter { p in
                execution.cycle == p.cycle && (execution.stop == p.stop || (p.calls && execution.stop + 1 == p.stop))
                    && plan.waits.contains { w in
                        w.station == p.station && ((w.train == train.id && w.stop == p.stop && w.cycle == p.cycle)
                                                  || (w.other == train.id && w.otherStop == p.stop && w.otherCycle == p.cycle))
                    }
            }
            guard !needed.isEmpty else { continue }
            let share = travelShare(of: train, from: start, memo: &memo)
            var distance: Int64 = 0
            for stretch in routeStretches(of: train).stretches {
                for point in needed {
                    for berth in berths(of: point.station, length: train.length) where berth.traversal == stretch.traversal {
                        let reach = distance + berth.offset - stretch.from
                        guard berth.offset >= stretch.from, berth.offset <= stretch.to, reach > 0 else { continue }
                        let limit = soonest.map { $0 - 1 } ?? span
                        guard limit >= 1, share(limit) >= reach else { continue }
                        // The least `k` whose distance reaches the berth.
                        var (low, high) = (Int64(1), limit)
                        while low < high {
                            let middle = (low + high) / 2
                            if share(middle) >= reach {
                                high = middle
                            } else {
                                low = middle + 1
                            }
                        }
                        note(low)
                    }
                }
                distance += stretch.to - stretch.from
            }
        }
        return soonest
    }
}
