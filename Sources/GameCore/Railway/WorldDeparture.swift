// The world in time (decision 910, cut 3): when and how a service leaves a stop.
// Moved from GameWorld.swift unchanged.

extension GameWorld {
    /// When the doors of `train`, waiting at timetable entry `stop` of
    /// `cycle` with `times`, start closing (Stage W2b): the latest of the
    /// end of its exchange, its least dwell (see
    /// ``ServiceDwell/minimumDwell(isTerminal:)``) less the time the doors
    /// take to close, and its scheduled departure less that time. `nil`
    /// while the doors are still opening. A ring's train (decision 49) has
    /// no terminal: it dwells at the first stop of its lap as at any other,
    /// unless it turns round there (the reference's ring dwell).
    func closingStart(of train: Train, stop: Int, cycle: Int64, times: ServiceTimes) -> GameTime? {
        guard times.exchangeEnd != nil else { return nil }
        return closingStart(of: train, stop: stop, cycle: cycle, times: times, onRing: lines.contains { $0.isRing && $0.trains.contains(train.id) })
    }

    /// ``closingStart(of:stop:cycle:times:)``, whether the train is a
    /// ring's looked up in `known` (decision 703), not searched for in
    /// every line for every train that stands at a stop.
    func closingStart(of train: Train, stop: Int, cycle: Int64, times: ServiceTimes, known: inout TrainLineIndex) -> GameTime? {
        guard times.exchangeEnd != nil else { return nil }
        return closingStart(of: train, stop: stop, cycle: cycle, times: times, onRing: known.isOnRing(train.id, in: lines))
    }

    private func closingStart(of train: Train, stop: Int, cycle: Int64, times: ServiceTimes, onRing: Bool) -> GameTime? {
        guard let exchangeEnd = times.exchangeEnd else { return nil }
        let entry = train.timetable[stop]
        let isTerminal = entry.reverses || (!onRing && (stop == 0 || stop == train.timetable.count - 1))
        let leastDwell = Self.saturating(times.arrival, plus: ServiceDwell.minimumDwell(isTerminal: isTerminal) - ServiceDwell.doorClosing)
        // Scheduled times are never negative, so this cannot overflow.
        let scheduled = GameTime(seconds: train.scheduledDeparture(of: stop, cycle: cycle).seconds - ServiceDwell.doorClosing)
        return max(exchangeEnd, leastDwell, scheduled)
    }

    /// When the service of `train`, waiting at a stop with its doors
    /// closing, may leave: once they have closed. `nil` while it is not
    /// waiting, or its doors are open.
    func departureDue(of train: Train) -> GameTime? {
        guard case .waitingAtStop? = train.execution, let closing = train.times?.closing else { return nil }
        return Self.saturating(closing, plus: ServiceDwell.doorClosing)
    }

    /// `time` plus `seconds`, or the largest time when that does not fit.
    static func saturating(_ time: GameTime, plus seconds: Int64) -> GameTime {
        let (sum, overflow) = time.seconds.addingReportingOverflow(seconds)
        return GameTime(seconds: overflow ? (seconds < 0 ? .min : .max) : sum)
    }

    /// Train `index`'s service leaves the stop it waits at if its departure
    /// is due (see ``departureDue(of:)``); see ``leaving(_:stop:cycle:)``.
    /// Returns whether the service changed.
    ///
    /// Under traffic control the departure tries the default route whole,
    /// an unblocked route to the same station whole (V1), then following
    /// on the default route (U2). If none can be taken, nothing changes:
    /// the train is not turned round
    /// either, and it tries again at the next step; the route it waits for
    /// joins `held`. Unlike a departure without a route, this is not
    /// remembered for the rest of the call: trains move and free track
    /// within one.
    @discardableResult
    mutating func departService(_ index: Int, at now: GameTime, unroutable: inout Set<TrainID>, held: inout [HeldRoute], memo: inout DispatchMemo) -> Bool {
        guard case .waitingAtStop(let stop, let cycle)? = trains[index].execution,
              let due = departureDue(of: trains[index]), due <= now,
              !unroutable.contains(trains[index].id),
              trains[index].placement != nil
        else { return false }
        // Decision 379: the train as a local, not `trains[index]` as an
        // argument, which copied the whole world for each call.
        let waiting = trains[index]
        // Stage V3 (decision 59): a scheduled wait keeps it here.
        let plan = trafficPlan(memo: &memo.directions)
        guard currentTrafficWait(waiting, plan: plan, memo: &memo.directions) == nil else { return false }
        let departure = leaving(waiting, stop: stop, cycle: cycle, memo: &memo.directions.paths)
        guard let moved = departure.train else {
            // Nothing changes: the train is not turned round either.
            unroutable.insert(waiting.id)
            return false
        }
        // Stage V3: the scheduled path, on the scheduled run, when the train
        // can take it whole now; then the line's preferred path (decision
        // 61); otherwise the departure as without a plan. The whole routes
        // tried first and held end a step when one frees, as the default
        // one does (decision 55).
        var granted: Train?
        // Decision 718: the candidate it was granted as.
        var asked: Train?
        var whole: [Train] = []
        // With block sections (decision 212) it may follow the trains ahead
        // on them too.
        var scheduledFollowing: Train?
        if case .setsOff = departure,
           case .setsOff(let scheduled, _)? = scheduledLeaving(waiting, stop: stop, cycle: cycle, plan: plan, memo: &memo.directions.paths) {
            if case .granted(let train) = reserving(scheduled, following: blockSections, memo: &memo.directions) { (granted, asked) = (train, scheduled) } else {
                whole.append(scheduled)
                scheduledFollowing = scheduled
            }
        }
        if granted == nil, case .setsOff(let preferred, _)? = preferredLeaving(waiting, stop: stop, cycle: cycle, memo: &memo.directions.paths) {
            if case .granted(let train) = reserving(preferred, following: blockSections, memo: &memo.directions) { (granted, asked) = (train, preferred) } else { whole.append(preferred) }
        }
        // Decision 526: before the default way, the scheduled one followed
        // behind the trains ahead on it, as the default may be: a train
        // passing a station where another waits for it keeps to the way
        // the plan leaves it, not the one keeping left takes.
        if granted == nil, let scheduled = scheduledFollowing, !blockSections, scheduled.movement.edges != moved.movement.edges,
           case .granted(let train) = reserving(scheduled, following: true, memo: &memo.directions) {
            (granted, asked) = (train, scheduled)
        }
        let train: Train
        if let granted {
            // Decision 718: not ahead of a service that has waited longer
            // for the same track the other way.
            if turnOwed(by: granted, memo: &memo.directions) != nil {
                held.append(HeldRoute(candidate: moved, whole: whole + [asked ?? moved]))
                return false
            }
            train = granted
        } else {
            switch reservingDeparture(moved, memo: &memo.directions) {
            case .granted(let granted):
                train = granted
            case .held:
                held.append(HeldRoute(candidate: moved, whole: whole))
                return false
            }
        }
        // Decision 228: not yet, while the platform it is bound for is
        // still taken when it would arrive.
        if waitsForPlatform(train) { return false }
        setOff(index, as: train)
        // Counted the way the train went: a preferred platform can take it
        // on from a berth where the default way would arrive at once.
        var setsOff = false
        if case .travellingToStop? = train.execution { setsOff = true }
        serve(departureOf: train.id, from: stop, distance: departure.distance.map { _ in setsOff ? routeLength(of: train) : 0 })
        return true
    }

    /// What leaving stop `stop` (of cycle `cycle`) does to `train`, whose
    /// service waits there: one pass of phase 1, worked out without
    /// changing the world.
    enum Leaving {
        /// The service is complete: the train stands where it is.
        case completes(Train)
        /// It is already stopped at the next call's station, and waits
        /// there at once.
        case arrives(Train)
        /// It sets off along the path to the next call, `distance` world
        /// units long.
        case setsOff(Train, distance: Int64)
        /// There is no path to the next call: nothing changes.
        case noRoute

        /// The train as the departure leaves it; `nil` without a route.
        var train: Train? {
            switch self {
            case .completes(let train), .arrives(let train), .setsOff(let train, _): train
            case .noRoute: nil
            }
        }

        /// How far the departure takes the train to its next call (G1c):
        /// `nil` when the service ends instead.
        var distance: Int64? {
            switch self {
            case .arrives: 0
            case .setsOff(_, let distance): distance
            case .completes, .noRoute: nil
            }
        }
    }

    /// See ``Leaving``. A waiting train is stopped with its path spent, so
    /// turning it round (at a stop marked to) needs nothing else; a train
    /// of several cars turns round with its head where its tail was (see
    /// ``turnedRound(_:)``). A train turned round stands there: its path
    /// ends where its head is.
    /// Without a path, the train is not turned round either.
    func leaving(_ train: Train, stop: Int, cycle: Int64) -> Leaving {
        var memo = PathMemo()
        return leaving(train, stop: stop, cycle: cycle, memo: &memo)
    }

    /// ``leaving(_:stop:cycle:)``, with the path kept in `memo`.
    func leaving(_ train: Train, stop: Int, cycle: Int64, memo: inout PathMemo) -> Leaving {
        leaving(train, stop: stop, cycle: cycle) { start, call in
            defaultPath(for: train, leaving: stop, cycle: cycle, from: start, to: call, lookingOn: true, memo: &memo)
        } ?? .noRoute
    }

    /// The way ``leaving(_:stop:cycle:memo:)`` takes `train` from `start`
    /// to `call`, the station of the call after stop `stop` (of cycle
    /// `cycle`), or `nil` when there is none. `lookingOn` is decision
    /// 735's look one call further (see ``wayOn(from:for:after:cycle:memo:)``);
    /// that look asks this again without it, and then only whether there is
    /// a way at all, so it never looks further than one call.
    private func defaultPath(for train: Train, leaving stop: Int, cycle: Int64, from start: TrainPosition, to call: StationID,
                             lookingOn: Bool, memo: inout PathMemo) -> (path: TrainPath, seconds: Int64?)? {
        // Decision 221: into a depot, a free siding first.
        if let path = pathIntoDepot(call, from: start, for: train, memo: &memo) {
            return (path, nil)
        }
        // Decision 535: out of a depot to a stop of a ring with runs, a
        // berth facing the way of the run it is for; under traffic
        // control a free one of those first (decision 290).
        if let facing = ringPullOutBerths(of: train, leaving: stop, to: call) {
            let free = pullOutBerths(of: train, leaving: stop, to: call).map { $0.intersection(facing) } ?? []
            for eligible in [free, facing] where !eligible.isEmpty {
                if let path = path(from: start, toStation: call, length: train.length, eligible: eligible, keepingLeft: true, memo: &memo) {
                    return (path, nil)
                }
            }
        }
        // Decision 290: out of a depot under traffic control, a free
        // berth of the stop.
        if let free = pullOutBerths(of: train, leaving: stop, to: call),
           let path = path(from: start, toStation: call, length: train.length, eligible: free, keepingLeft: true, memo: &memo) {
            return (path, nil)
        }
        guard var nearest = path(from: start, toStation: call, length: train.length, memo: &memo) else { return nil }
        // Decision 735: asked only whether there is a way, there is.
        guard lookingOn else { return (nearest, nil) }
        // Decision 735: not into a berth with no way on from it to the
        // call after (the Western Trunk Line train that went into the
        // Yilan Line's track at Badu and stood there for 37 hours), when
        // another berth of the call has one.
        if let next = train.call(after: stop, cycle: cycle), train.call(after: next.stop, cycle: next.cycle) != nil,
           nearest.distance > 0, case .onEdge(let first, _) = start,
           let stopsAt = berth(endingAt: nearest, from: first),
           !wayOn(from: stopsAt, for: train, after: next.stop, cycle: next.cycle, memo: &memo) {
            let leading = berths(of: call, length: train.length).filter { wayOn(from: $0, for: train, after: next.stop, cycle: next.cycle, memo: &memo) }
            if !leading.isEmpty, let kept = path(from: start, toStation: call, length: train.length, eligible: Set(leading), keepingLeft: true, memo: &memo) {
                nearest = kept
            }
        }
        // Decision 547: out of a depot with traffic control off, off the
        // track where other trains stand, as decision 228 has it in.
        var standing: Set<TrackEdgeID> = []
        if let kept = pathOutOfDepot(train.timetable[stop].station, to: call, from: start, for: train, nearest: nearest) { (nearest, standing) = kept }
        // Decision 527: an empty run keeps off track its line takes
        // only the other way; decision 547 (L6-4): and, out of a
        // depot, still off the track where other trains stand.
        let against = lineAgainst(for: train, memo: &memo)
        if let against, let kept = lineDirectionPath(nearest, from: start, toStation: call, for: train, against: against, avoiding: standing) { nearest = kept }
        // Decision 228: with traffic control off, a free platform first;
        // decision 527: not one only that track reaches.
        if let next = train.call(after: stop, cycle: cycle),
           let free = freePlatformPath(nearest, from: start, toStation: call, for: train, next: next, memo: &memo),
           !(against.map { against in free.traversals.contains(where: against.contains) && !nearest.traversals.contains(where: against.contains) } ?? false) {
            return (free, nil)
        }
        return (nearest, nil)
    }

    /// Decision 735: the berth `path`, starting along `first`, ends at;
    /// `nil` when its edge is not on the network.
    private func berth(endingAt path: TrainPath, from first: TrackTraversal) -> Berth? {
        let last = path.traversals.last ?? first
        guard let edge = network.edge(last.edge) else { return nil }
        return Berth(traversal: last, offset: path.end ?? edge.length)
    }

    /// Decision 735: whether `train`, stopped at `berth` for its call
    /// `stop` (of cycle `cycle`), would have a way on from there to the
    /// call after: the way ``leaving(_:stop:cycle:memo:)`` looks for,
    /// turned round first where the timetable turns it round there, but
    /// no further than that call.
    private func wayOn(from berth: Berth, for train: Train, after stop: Int, cycle: Int64, memo: inout PathMemo) -> Bool {
        guard let next = train.call(after: stop, cycle: cycle) else { return true }
        var standing = train
        stand(&standing, at: TrainPlacement(position: .onEdge(berth.traversal, offset: berth.offset), trailEdges: [], length: train.length))
        standing.execution = .waitingAtStop(stop, cycle: cycle)
        guard let placement = standing.placement else { return true }
        let start = standing.timetable[stop].reverses ? turnedRound(placement) : placement
        return defaultPath(for: standing, leaving: stop, cycle: cycle, from: start.position, to: standing.timetable[next.stop].station,
                           lookingOn: false, memo: &memo) != nil
    }

    /// Decision 61: a physical preference is taken only as a whole. The
    /// paths it searches for are kept in `memo`.
    func preferredLeaving(_ train: Train, stop: Int, cycle: Int64, memo: inout PathMemo) -> Leaving? {
        guard let next = train.call(after: stop, cycle: cycle),
              let preference = routePreference(for: train, from: stop, to: next.stop, known: &memo.trainLines) else { return nil }
        return leaving(train, stop: stop, cycle: cycle) { start, _ in
            var preferred = preferredPath(from: start, preference: preference, length: train.length, memo: &memo)
            // Decision 228: with traffic control off, a train of real runs
            // off its walk joins it where its own way meets it.
            if preferred == nil, !isTrafficControlEnabled, followsRealTimetable(train),
               let nearest = path(from: start, toStation: preference.platform.station, length: train.length, memo: &memo) {
                preferred = joiningPreferredPath(from: start, preference: preference, length: train.length, along: nearest)
            }
            // Decision 755 (REVIEW-L21 P3-1): with traffic control off, a
            // leg's list goes on to its next platform the train reaches and
            // fits when its first does not, as under traffic control
            // (decision 740); only when none does is the leg's way automatic.
            if preferred == nil, !isTrafficControlEnabled, let list = preference.platformList {
                for platform in list.dropFirst() {
                    let leg = LineRoutePreference(from: preference.from, to: preference.to, platform: platform)
                    if let path = preferredPath(from: start, preference: leg, length: train.length, memo: &memo) {
                        preferred = path
                        break
                    }
                }
            }
            guard let preferred else { return nil }
            // Decision 228: with traffic control off, its way to a free
            // platform when another train is due on the one it names.
            // Decision 740: only to another platform of the leg's list,
            // when it names one.
            let listed = preference.platformList.map { Set($0.map(\.edge)) }
            return (freePlatformPath(preferred, from: start, toStation: preference.platform.station, for: train, next: next, among: listed, memo: &memo) ?? preferred, nil)
        }
    }

    /// Stage V3 (decision 59): `train` leaving stop `stop` along its
    /// scheduled path, on the scheduled run (see
    /// ``scheduledPath(for:from:to:plan:memo:)``); `nil` when the plan
    /// gives it none.
    func scheduledLeaving(_ train: Train, stop: Int, cycle: Int64, plan: TrafficPlan, memo: inout PathMemo) -> Leaving? {
        leaving(train, stop: stop, cycle: cycle) { start, call in
            scheduledPath(for: train, from: start, to: call, plan: plan, memo: &memo)
        }
    }

    /// See ``leaving(_:stop:cycle:)``, along the path (and in the seconds,
    /// if any) `route` gives from where the train would stand to the next
    /// call's station; `nil` when it gives none.
    private func leaving(_ train: Train, stop: Int, cycle: Int64, route: (TrainPosition, StationID) -> (path: TrainPath, seconds: Int64?)?) -> Leaving? {
        guard let placement = train.placement else { return .noRoute }
        let start = train.timetable[stop].reverses ? turnedRound(placement) : placement
        var moved = train
        guard let next = train.call(after: stop, cycle: cycle) else {
            // The last stop's departure: the service is complete.
            stand(&moved, at: start)
            moved.execution = nil
            moved.isDeadheading = false
            moved.times = nil
            return .completes(moved)
        }
        guard let chosen = route(start.position, train.timetable[next.stop].station) else { return nil }
        let path = chosen.path
        stand(&moved, at: start)
        let now = clock.now
        if path.distance == 0 {
            // Already stopped at the next call's station: it arrives there
            // now, and dwells there as at any call (Stage W2b).
            moved.execution = .waitingAtStop(next.stop, cycle: next.cycle)
            moved.times = ServiceTimes(arrival: now, departure: now)
            return .arrives(moved)
        }
        follow(path, &moved)
        moved.execution = .travellingToStop(next.stop, cycle: next.cycle)
        // Stage W2c: the run takes the time the timetable gives it, from the
        // scheduled departure to the scheduled arrival (never negative).
        // Decision 207: with realistic operation, the time left to the
        // scheduled arrival, so a late train makes up its margin.
        // Decision 228: so does a train of real runs with traffic control
        // off, which another train held up on its way. Decision 306: and
        // with traffic control on and block sections, as the app's new
        // games have it; never above what the train and the curves allow.
        // Decision 308: without block sections too.
        let timetabled = train.scheduledArrival(of: next.stop, cycle: next.cycle).seconds - train.scheduledDeparture(of: stop, cycle: cycle).seconds
        let scheduled = realisticOperation || followsRealTimetable(train)
            ? secondsToScheduledArrival(of: train, stop: next.stop, cycle: next.cycle)
            : timetabled
        moved.times = ServiceTimes(
            arrival: train.times?.arrival ?? now, departure: now,
            run: run(of: moved, length: path.distance, scheduled: chosen.seconds ?? scheduled, timetabled: chosen.seconds ?? timetabled)
        )
        return .setsOff(moved, distance: path.distance)
    }

    /// The run `train`, a service's, sets off on now over `length` world
    /// units to its next call (Stage W2c; see ``ServiceRun``): in the
    /// `scheduled` seconds its timetable gives the run when its performance
    /// builds a curve for them, as the Railway reference fits a run's curve
    /// to the timetable; otherwise (it cannot keep that time, or there is
    /// none) in the least whole second it builds one for, running as fast
    /// as it can. `nil` when it builds none at all (see
    /// ``RunningCurve/leastSeconds(length:performance:)``): the train then
    /// goes at its rate. With ``curveSpeedLimits`` on (decision 217) it
    /// keeps to the limits ahead of it on its path (see
    /// ``speedLimitsAhead(of:distance:)``), but on a line of real runs
    /// never at the cost of its real time: only when `timetabled`, the
    /// seconds the timetable itself gives the run (`scheduled` when not
    /// given), does not fit under them. A late train's `scheduled`, the
    /// time left to its arrival, never drops them (A6 of the #873–#910
    /// review; decision 306).
    ///
    /// - Precondition: `length >= 1`.
    func run(of train: Train, length: Int64, scheduled: Int64? = nil, timetabled: Int64? = nil) -> ServiceRun? {
        var limits = speedLimitsAhead(of: train, distance: length)
        // A real timetable (decision 133) is kept as well as without the
        // limits: where its time does not fit under them, the real line's
        // curves are gentler than the drawn ones (or the real trains faster
        // than the game's), and the run does without.
        if let timetabled = timetabled ?? scheduled, (1...RunningCurve.maximumSeconds).contains(timetabled),
           !limits.isEmpty, followsRealTimetable(train),
           !RunCurve.fits(length: length, duration: timetabled * 1000, performance: train.performance, limits: limits) {
            limits = []
        }
        if let scheduled, (1...RunningCurve.maximumSeconds).contains(scheduled) {
            let duration = scheduled * 1000
            if RunCurve.fits(length: length, duration: duration, performance: train.performance, limits: limits) {
                return ServiceRun(start: clock.now, length: length, seconds: scheduled, limits: limits)
            }
        }
        return RunCurve.leastSeconds(length: length, performance: train.performance, limits: limits)
            .map { ServiceRun(start: clock.now, length: length, seconds: $0, limits: limits) }
    }

    // The service adapters that change a train (Stage S5; the others are in
    // ServicePath.swift).

    /// Gives `train` `path` as its path, from the start: its edges and
    /// where it stops. The rest of its movement stays.
    func follow(_ path: TrainPath, _ train: inout Train) {
        train.movement.edges = path.traversals.map(\.edge)
        train.movement.end = path.end
        train.movement.cursor = 0
    }

    /// Puts `train` where `placement` says and leaves it standing there: its
    /// path now ends where its head is (see ``TrainMovement/end``), so it
    /// stays until it is given a path.
    func stand(_ train: inout Train, at placement: TrainPlacement) {
        train.position = placement.position
        train.trailEdges = placement.trailEdges
        switch placement.position {
        case .onEdge(let traversal, let offset):
            train.movement.edges = []
            train.movement.cursor = 0
            train.movement.end = offset < network.edge(traversal.edge)!.length ? offset : nil
        }
    }
}
