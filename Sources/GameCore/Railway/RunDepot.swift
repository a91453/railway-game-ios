// Depots of lines with runs (ARCHITECTURE decision 221). A line with runs
// (decision 133) sends a train out at a run's times from where it stands,
// so its depots work by its runs, not its headway and window as decision
// 209's do: a train waiting where no run of its line leaves for a while
// runs empty to the depot it reaches soonest, and a train runs empty out of
// the depot nearest a stop in time for a run that would find none there.
// The rest is decision 209's: the empty run (decision 172), the sidings no
// service runs over, what a train in a depot pays.

extension GameWorld {
    /// How far ahead a line with runs looks for a run a waiting train could
    /// take before it sends the train to a depot (decision 221): two hours,
    /// as the high-speed demo's sets wait at an end for their next run
    /// (decision 197); a train that turns round within the hour stays.
    static let runDepotLookahead: Int64 = 2 * GameTime.secondsPerHour

    /// The first departures, in seconds, of `line`'s runs that leave from
    /// `station`, have not sent a train out on their day and may still:
    /// those of the days ``LineRun/latestDispatch`` behind to tomorrow (as
    /// ``ServiceLine/dueRuns(at:)`` looks), but those whose last moment
    /// to leave has passed.
    func pendingRunStarts(of line: ServiceLine, from station: StationID) -> [Int64] {
        let now = clock.now.seconds
        let today = GameTime.floorDivide(now, GameTime.secondsPerDay)
        var starts: [Int64] = []
        for (index, run) in line.runs.enumerated() where line.stops[run.from] == station {
            for day in (today - 2)...(today + 1) where day >= 0 && run.runs(onDay: day) && (line.runDays[index] ?? -1) < day && run.fits(onDay: day) {
                let start = run.start(onDay: day)
                if start + LineRun.latestDispatch >= now { starts.append(start) }
            }
        }
        return starts
    }

    /// `line`'s trains without a service waiting at `station`, in ID
    /// order: placed, with a rate above 0, stopped there.
    private func runTrainsWaiting(of line: ServiceLine, at station: StationID) -> [Int] {
        line.trains.compactMap { id in
            guard let index = trains.firstIndex(where: { $0.id == id }) else { return nil }
            let train = trains[index]
            guard train.execution == nil, train.placement != nil, train.movement.rate > 0, isStopped(train, at: station) else { return nil }
            return index
        }
    }

    /// When each of `line`'s trains for `station` can take a run there,
    /// earliest first: now for those waiting there, and for those on their
    /// way to end there, running a service or empty, their arrival. Under
    /// traffic control that arrival is put back by how late the train runs
    /// now (``lateness(of:)``): a train hours behind its timetable, held
    /// for its route, is not there for the run it would have taken, and a
    /// train out of the depot takes the run instead.
    private func runTrainsReady(of line: ServiceLine, at station: StationID) -> [Int64] {
        var times = runTrainsWaiting(of: line, at: station).map { _ in clock.now.seconds }
        for id in line.trains {
            guard let train = train(id: id), train.execution != nil, let last = train.timetable.last, last.station == station else { continue }
            var arrival = last.arrival.seconds
            if isTrafficControlEnabled, let late = lateness(of: id), late > 0 {
                arrival = arrival.addingReportingOverflow(late).overflow ? .max : arrival + late
            }
            times.append(arrival)
        }
        return times.sorted()
    }

    /// How many of the runs leaving at `starts` find no train of `ready`
    /// (when each can take one, earliest first) there by their first
    /// departure, each train taking the earliest run it can.
    static func runsWithoutTrains(_ starts: [Int64], ready: [Int64]) -> Int {
        var next = 0, missing = 0
        for start in starts.sorted() {
            if next < ready.count, ready[next] <= start {
                next += 1
            } else {
                missing += 1
            }
        }
        return missing
    }

    // MARK: - Into the depot

    /// The train of `line`, a line with runs and depots, to send into a
    /// depot now, with its empty run to the one it reaches soonest, or
    /// `nil` (decision 221). Of its trains without a service waiting at a
    /// station other than its depots: one where no run of the line leaves,
    /// or, where more wait than runs leave within
    /// ``runDepotLookahead``, the last in ID order. Under traffic control it
    /// must be able to take its route now, and a train that came out of a
    /// depot to the stop stays while a run from there is due (decision
    /// 296).
    func runTrainEnteringDepot(of line: ServiceLine, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard !line.depots.isEmpty, line.hasRuns, clock.now.seconds >= 0 else { return nil }
        var stations: [StationID] = []
        for id in line.trains {
            guard let train = train(id: id), train.execution == nil, train.placement != nil, train.movement.rate > 0,
                  !isInDepot(train, of: line), let station = stationsStoppedAt(by: id).first, !stations.contains(station)
            else { continue }
            stations.append(station)
        }
        let horizon = clock.now.seconds + Self.runDepotLookahead
        for station in stations {
            let waiting = runTrainsWaiting(of: line, at: station)
            let wanted = pendingRunStarts(of: line, from: station).count { $0 <= horizon }
            guard waiting.count > wanted else { continue }
            // Decision 296: a train out of a depot for a run due here is
            // not one too many until that run leaves or is dropped.
            let due = isTrafficControlEnabled && pendingRunStarts(of: line, from: station).contains { $0 - LineRun.earliestDispatch <= clock.now.seconds }
            for index in waiting.suffix(waiting.count - wanted).reversed() {
                if due, cameOutOfDepot(trains[index], to: station) { continue }
                guard let trip = emptyRun(of: line, for: trains[index], to: line.depots) else { continue }
                // Decision 280: under traffic control, only with a siding
                // for it; without one it stays where it waits.
                if isTrafficControlEnabled, let depot = trip.deadhead?.to, !depotHasRoom(depot, for: trains[index]) { continue }
                if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
                   case .held = reservingDeparture(leaving, memo: &memo.directions) {
                    continue
                }
                return (index, trip)
            }
        }
        return makingWay(of: line)
    }

    /// Decision 228: with traffic control off, a train of `line` waiting
    /// without a service at a station that another train is on its way to,
    /// to the platform it stands on, goes into the depot it reaches soonest
    /// when it would still stand there as that one arrives (see
    /// ``runLeaving(of:at:readyAt:)``): it makes way for it, and comes out
    /// again in time for its run. The first such train in ID order.
    private func makingWay(of line: ServiceLine) -> (index: Int, trip: LineTrip)? {
        guard !isTrafficControlEnabled else { return nil }
        let now = clock.now.seconds
        // Where the trains on their way to a call stop, and when the first
        // of them arrives there.
        var bound: [TrackEdgeID: (station: StationID, arrival: Int64)] = [:]
        for other in trains {
            guard case .travellingToStop(let stop, let cycle)? = other.execution else { continue }
            var last = other.movement.edges.last
            if last == nil, case .onEdge(let traversal, _)? = other.position { last = traversal.edge }
            guard let last else { continue }
            let at = other.scheduledArrival(of: stop, cycle: cycle).seconds
            if at < bound[last]?.arrival ?? .max { bound[last] = (other.timetable[stop].station, at) }
        }
        guard !bound.isEmpty else { return nil }
        for id in line.trains {
            guard let index = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[index]
            guard train.execution == nil, train.placement != nil, train.movement.rate > 0 else { continue }
            let edges = Set(bodyStretches(of: train).map(\.traversal.edge))
            guard let station = stationsStoppedAt(by: id).first, self.station(id: station)?.isDepot == false, !isInDepot(train, of: line),
                  let arrival = edges.compactMap({ edge in bound[edge].flatMap { $0.station == station ? $0.arrival : nil } }).min(),
                  (runLeaving(of: train, at: station, readyAt: now) ?? .max) > arrival - Self.platformClearance,
                  let trip = emptyRun(of: line, for: train, to: line.depots) else { continue }
            return (index, trip)
        }
        return nil
    }

    // MARK: - Out of the depot

    /// The empty run to `station` of the train that leaves first of those
    /// of `line` standing in its depots: the first in ID order of the
    /// depot whose first has the shortest run (then the depot listed
    /// first), with its index. Kept in `memo` for where the train stands.
    private func runPullOut(of line: ServiceLine, to station: StationID, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        var best: (index: Int, trip: LineTrip, seconds: Int64)?
        for depot in line.depots {
            guard let index = line.trains.lazy.compactMap({ id in self.trains.firstIndex { $0.id == id } }).first(where: { index in
                let train = self.trains[index]
                return train.execution == nil && train.movement.rate > 0 && self.isStopped(train, at: depot)
            }), let placement = trains[index].placement else { continue }
            let trip: LineTrip?
            let query = RunDepotQuery(train: trains[index].id, from: placement, to: station)
            if let known = memo.runDepotTrips[query] {
                trip = known
            } else {
                trip = emptyRun(of: line, for: trains[index], to: [station])
                memo.runDepotTrips[query] = .some(trip)
            }
            guard let trip, let run = trip.deadhead, best.map({ run.seconds < $0.seconds }) ?? true else { continue }
            best = (index, trip, run.seconds)
        }
        return best.map { ($0.index, $0.trip) }
    }

    /// The train of `line`, a line with runs and depots, to send out of a
    /// depot now, with its empty run, or `nil` (decision 221). For each
    /// stop in turn: when some run due by the time a train out of the
    /// depot would stand there finds no train there by its first departure
    /// (of those waiting there, and those on their way that arrive by
    /// then, see ``runsWithoutTrains(_:ready:)``), the train out of the
    /// nearest depot (see ``runPullOut(of:to:memo:)``). A run is due by
    /// then when its first departure, less ``LineRun/earliestDispatch`` and
    /// the run out's lead (decision 209's: the least dwell and the run's
    /// seconds, in whole minutes, and a minute more), has come. Under
    /// traffic control the stop must have a berth for the train (see
    /// ``endHasRoom(_:for:)``, decision 290), the train must be able to
    /// take its route now, and only the runs it can stand at before their
    /// last moment to leave count (decision 296).
    func runTrainLeavingDepot(of line: ServiceLine, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard !line.depots.isEmpty, line.hasRuns, clock.now.seconds >= 0 else { return nil }
        let now = clock.now.seconds
        var seen: Set<StationID> = []
        for station in line.stops where seen.insert(station).inserted {
            let starts = pendingRunStarts(of: line, from: station)
            // Nothing is due within the look ahead: no run out takes longer.
            let soon = starts.filter { $0 - LineRun.earliestDispatch - Self.runDepotLookahead <= now }
            let ready = runTrainsReady(of: line, at: station)
            guard Self.runsWithoutTrains(soon, ready: ready) > 0, let (index, trip) = runPullOut(of: line, to: station, memo: &memo),
                  let run = trip.deadhead
            else { continue }
            let lead = Self.lead(of: run) * GameTime.secondsPerMinute
            // Decision 296: under traffic control, only the runs it can
            // stand at in time for: a run out that arrives after a run's
            // last moment to leave does not take it.
            let reachable = soon.filter { !isTrafficControlEnabled || $0 + LineRun.latestDispatch >= now + lead }
            guard Self.runsWithoutTrains(reachable.filter { $0 - LineRun.earliestDispatch - lead <= now }, ready: ready) > 0 else { continue }
            // Decision 290: under traffic control, only with a berth there
            // for it; without one it stays in the depot.
            if isTrafficControlEnabled, !endHasRoom(station, for: trains[index]) { continue }
            if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
               case .held = reservingDeparture(leaving, memo: &memo.directions) {
                continue
            }
            return (index, trip)
        }
        return nil
    }

    /// Decision 296: whether `train`, standing without a service at
    /// `station`, last ran there empty out of a depot (its timetable, kept
    /// once the run ends, starts at a depot and ends there).
    func cameOutOfDepot(_ train: Train, to station: StationID) -> Bool {
        guard let first = train.timetable.first, let last = train.timetable.last, last.station == station else { return false }
        return self.station(id: first.station)?.isDepot == true
    }

    // MARK: - Room at the end

    /// Decision 290: the berths of `station` that `train` fits and that
    /// are free for it: no part of another train stands on their track,
    /// and no train on its way to the station is bound for it (its route
    /// ends there).
    func freeEndBerths(_ station: StationID, for train: Train) -> [Berth] {
        var taken: Set<TrackEdgeID> = []
        for other in trains where other.id != train.id {
            for stretch in bodyStretches(of: other) { taken.insert(stretch.traversal.edge) }
            if case .travellingToStop(let call, _)? = other.execution, other.timetable[call].station == station,
               let last = other.movement.edges.last {
                taken.insert(last)
            }
        }
        return berths(of: station, length: train.length).filter { !taken.contains($0.traversal.edge) }
    }

    /// Decision 290: whether `station` has a berth for `train`, about to
    /// be sent out of a depot to it, beyond those the trains already sent
    /// out of a depot to it and not yet on their way will take: more of
    /// its tracks have a free berth (see ``freeEndBerths(_:for:)``) than
    /// there are such trains. Asked under traffic control: a set sent out
    /// to a terminus with every track taken stood on the depot's single
    /// lead waiting for one, and the sets there could not go in past it.
    func endHasRoom(_ station: StationID, for train: Train) -> Bool {
        let free = Set(freeEndBerths(station, for: train).map(\.traversal.edge))
        let coming = trains.count { other in
            guard other.id != train.id, other.isDeadheading, case .waitingAtStop(0, _)? = other.execution,
                  other.timetable.count > 1, other.timetable.last?.station == station
            else { return false }
            return self.station(id: other.timetable[0].station)?.isDepot == true
        }
        return free.count > coming
    }

    /// Decision 290: the free berths (see ``freeEndBerths(_:for:)``) a
    /// train of a line with runs, sent out of a depot under traffic control
    /// and leaving it from stop `stop`, runs to at `call`; `nil` for any
    /// other departure, or when none is free (it then takes the nearest,
    /// as before).
    func pullOutBerths(of train: Train, leaving stop: Int, to call: StationID) -> Set<Berth>? {
        guard isTrafficControlEnabled, train.isDeadheading, station(id: train.timetable[stop].station)?.isDepot == true,
              station(id: call)?.isDepot == false, followsRealTimetable(train)
        else { return nil }
        let free = freeEndBerths(call, for: train)
        return free.isEmpty ? nil : Set(free)
    }

    // MARK: - Waking

    /// The whole minutes from now until the first minute at which `line`,
    /// a line with runs and depots, may send a train into or out of a
    /// depot (decision 221), or `nil` if none can before something
    /// changes: now if one can now; else the first of the moments at which
    /// what decides it changes without a train changing: for each run
    /// still to leave a stop, when it comes within the look ahead (into the
    /// depot), within the look ahead of its earliest dispatch and within
    /// the lead of the run out to it (out of the depot), when its first
    /// departure passes (a train waiting for it then counts as too late
    /// for it, decision 296) and when its last moment to leave passes. So
    /// this is exact.
    func minutesUntilRunDepotMove(of line: ServiceLine, memo: inout DispatchMemo) -> Int64? {
        guard !line.depots.isEmpty, line.hasRuns else { return nil }
        let now = clock.now
        guard now.seconds >= 0 else { return Self.minutes(from: now, until: .zero) }
        if runTrainEnteringDepot(of: line, memo: &memo) != nil || runTrainLeavingDepot(of: line, memo: &memo) != nil { return 0 }
        var soonest: Int64?
        func wake(at seconds: Int64) {
            guard seconds > now.seconds else { return }
            soonest = min(soonest ?? .max, Self.minutes(from: now, until: GameTime(seconds: seconds)))
        }
        var seen: Set<StationID> = []
        for station in line.stops where seen.insert(station).inserted {
            let starts = pendingRunStarts(of: line, from: station)
            guard !starts.isEmpty else { continue }
            let lead = runPullOut(of: line, to: station, memo: &memo)?.trip.deadhead.map { Self.lead(of: $0) * GameTime.secondsPerMinute }
            for start in starts {
                wake(at: start - Self.runDepotLookahead)
                wake(at: start - LineRun.earliestDispatch - Self.runDepotLookahead)
                if let lead { wake(at: start - LineRun.earliestDispatch - lead) }
                // Decision 296: once its first departure has passed, a
                // train waiting for it counts as too late for it.
                wake(at: start + 1)
                wake(at: start + LineRun.latestDispatch + 1)
            }
        }
        return soonest
    }
}
