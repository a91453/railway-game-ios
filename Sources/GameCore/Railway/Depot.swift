// Depots, level 1 (ARCHITECTURE decision 209). A depot is a station flagged
// as one (not an operation mode, which the player switches on the station
// panel): no line calls at it, and no line's service runs over its
// sidings (the reference's `topology.js` finds a passenger route with
// `allowYard=false`). A line given a depot sends a train there empty when
// it no longer needs it (its window closed, or fewer trains at a quieter
// time of day) and out of it empty in time for the trip it is wanted for,
// with or without flexible dispatch (decision 172), whose empty run it
// uses. A train standing in its depot pays its upkeep, not its energy or
// crew, and the depot costs a fee a siding a day. A line without a depot,
// as every line before, keeps its trains where their trips end, and a
// train bought and not placed still waits unseen as before (the beginner's
// "invisible depot").

extension GameWorld {
    // MARK: - Where trains stand

    /// Whether `train`, without a service, stands at one of `line`'s
    /// depots.
    func isInDepot(_ train: Train, of line: ServiceLine) -> Bool {
        guard !line.depots.isEmpty, train.execution == nil else { return false }
        return line.depots.contains { isStopped(train, at: $0) }
    }

    /// Whether `train`, without a service, stands at any depot (decision
    /// 209).
    func standsInADepot(_ train: Train) -> Bool {
        guard train.execution == nil, stations.contains(where: \.isDepot) else { return false }
        return stationsStoppedAt(by: train.id).contains { station(id: $0)?.isDepot == true }
    }

    /// Whether `train` runs empty to one of `line`'s depots.
    func isPullingIn(_ train: Train, of line: ServiceLine) -> Bool {
        guard !line.depots.isEmpty, train.isDeadheading, let end = train.timetable.last?.station else { return false }
        return line.depots.contains(end)
    }

    /// The berths of depot `station` that `train` fits and no other train
    /// stands on or runs to the end of (decision 221), or `nil` when the
    /// station is not a depot or every berth is taken: a train running
    /// into a depot takes a free siding, not the one where the trains
    /// before it stand.
    func freeDepotBerths(_ station: StationID, for train: Train) -> Set<Berth>? {
        guard self.station(id: station)?.isDepot == true else { return nil }
        var taken: Set<TrackEdgeID> = []
        for other in trains where other.id != train.id {
            if case .onEdge(let traversal, _)? = other.position { taken.insert(traversal.edge) }
            if other.execution != nil, other.timetable.last?.station == station, let last = other.movement.edges.last { taken.insert(last) }
        }
        let free = berths(of: station, length: train.length).filter { !taken.contains($0.traversal.edge) }
        return free.isEmpty ? nil : Set(free)
    }

    /// The way from `start` into one of depot `station`'s free sidings for
    /// `train` (decision 221), keeping left as any other way does
    /// (decision 202); `nil` when `station` is not a depot, none is free
    /// or none is reached.
    func pathIntoDepot(_ station: StationID, from start: TrainPosition, for train: Train, memo: inout PathMemo) -> TrainPath? {
        guard let free = freeDepotBerths(station, for: train) else { return nil }
        return path(from: start, toStation: station, length: train.length, eligible: free, keepingLeft: true, memo: &memo)
    }

    /// The edges with a platform of a depot, its sidings (decision 209),
    /// but those of a depot with a platform on `edge`, where a train
    /// starts: no way to another station runs over them.
    func sidings(except edge: TrackEdgeID) -> Set<TrackEdgeID> {
        guard stations.contains(where: \.isDepot) else { return [] }
        let depots = network.platforms.filter { station(id: $0.station)?.isDepot == true }
        let starting = Set(depots.filter { $0.edge == edge }.map(\.station))
        return Set(depots.filter { !starting.contains($0.station) }.map(\.edge))
    }

    /// The fastest empty run that takes `train`, stopped at a station, to
    /// one of `targets` by the time `line`'s performance takes over the
    /// path, as it stands or turned round (the first target, then as it
    /// stands, among equals); `nil` for a train not stopped at a station,
    /// or when none can be reached (decisions 172 and 209).
    func emptyRun(of line: ServiceLine, for train: Train, to targets: [StationID]) -> LineTrip? {
        guard let placement = train.placement, let here = stationsStoppedAt(by: train.id).first else { return nil }
        var best: (seconds: Int64, turns: Bool, end: StationID)?
        for end in targets {
            for turns in [false, true] {
                let from = turns ? turnedRound(placement) : placement
                guard let path = path(from: from.position, toStation: end, length: train.length) else { continue }
                var seconds: Int64 = 0
                if path.distance > 0 {
                    guard let least = plannedSeconds(length: path.distance, line: line, limits: speedLimits(from: from, along: path, below: line.performance.topSpeed)) else { continue }
                    seconds = least
                }
                if best == nil || seconds < best!.seconds { best = (seconds, turns, end) }
            }
        }
        guard let best else { return nil }
        return LineTrip(
            turnsFirst: best.turns,
            journey: LineJourney(start: placement.position, legs: [], roundTripSeconds: 0),
            deadhead: LineTrip.DeadheadRun(from: here, to: best.end, seconds: best.seconds)
        )
    }

    /// Where a train out of `line`'s depot runs to for service `service`:
    /// the first call; with flexible dispatch (decision 172) also the last
    /// call, or on a ring any stop, as a train is sent out from any of
    /// them.
    private func pullOutTargets(of line: ServiceLine, service: Int) -> [StationID] {
        let calls = line.calls(ofService: service)
        guard flexDispatch else { return [line.stops[calls[0]]] }
        if line.isRing { return line.stops }
        return [line.stops[calls[0]], line.stops[calls[calls.count - 1]]]
    }

    /// The empty run out of `line`'s depot for `train`, kept in `memo` for
    /// where the train stands.
    private func pullOutTrip(of train: Train, on line: ServiceLine, _ service: Int, memo: inout DispatchMemo) -> LineTrip? {
        guard let placement = train.placement else { return nil }
        if let known = memo.depotTrips[train.id], known.from == placement { return known.trip }
        let trip = emptyRun(of: line, for: train, to: pullOutTargets(of: line, service: service))
        memo.depotTrips[train.id] = (placement, trip)
        return trip
    }

    /// The most whole minutes a train out of the depot stands at its end
    /// before its trip: ``lead(of:)`` rounds the run up and adds a minute.
    static let waitingLead: Int64 = 2

    /// The whole minutes before its trip a train out of the depot leaves:
    /// its least dwell and the run's seconds, rounded up, and a minute
    /// more, so that it stands at the end, its run over, when the trip is
    /// due.
    static func lead(of run: LineTrip.DeadheadRun) -> Int64 {
        let seconds = ServiceDwell.terminalMinimum + run.seconds
        return seconds / GameTime.secondsPerMinute + (seconds % GameTime.secondsPerMinute == 0 ? 0 : 1) + 1
    }

    /// How many trains `line`'s `stream` runs at `time` and its headway
    /// then, or `nil` when it runs none (its window closed).
    private func wanted(_ line: ServiceLine, _ stream: DispatchStream, at time: GameTime, memo: inout DispatchMemo) -> (trains: Int, headway: Int64)? {
        guard let planned = plannedService(of: line, stream.service, at: time, memo: &memo) else { return nil }
        return (stream.direction == nil ? planned.trains : planned.trains / 2, planned.headway)
    }

    /// The trains of `line`'s `stream` that run a service, but those
    /// running empty to the depot. One pass over the trains, not a lookup
    /// of each: it is asked every minute for every stream.
    func runningTrains(of line: ServiceLine, _ stream: DispatchStream) -> Int {
        let ids = Set(line.trains(of: stream))
        return trains.count { train in
            ids.contains(train.id) && train.execution != nil && !isPullingIn(train, of: line)
        }
    }

    // MARK: - Out of the depot

    /// Whether a train of `line`'s `stream` waits to be sent out or is on
    /// its way to an end to be (decision 209): then no other leaves the
    /// depot, so that trains go out one at a time and none waits at an end
    /// for a trip.
    private func hasTrainOnItsWay(_ line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> Bool {
        for id in line.trains(of: stream) {
            guard let train = train(id: id) else { continue }
            if train.execution != nil {
                if train.isDeadheading, !isPullingIn(train, of: line) { return true }
                continue
            }
            if !isInDepot(train, of: line), readyTrip(of: train, on: line, stream.service, memo: &memo) != nil { return true }
        }
        return false
    }

    /// Whether the run out of the depot that takes `lead` minutes is due
    /// now for `line`'s `stream` (decision 209): `lead` minutes from now
    /// the stream runs trains, more than run now (but those running empty
    /// to the depot), and a headway since its last dispatch has passed by
    /// then.
    private func isPullOutDue(_ line: ServiceLine, _ stream: DispatchStream, lead: Int64, memo: inout DispatchMemo) -> Bool {
        guard let time = Self.time(clock.now, plusMinutes: lead), let wanted = wanted(line, stream, at: time, memo: &memo),
              runningTrains(of: line, stream) < wanted.trains
        else { return false }
        if let last = line.lastDispatch(of: stream) {
            guard let due = Self.time(last, plusMinutes: wanted.headway), due <= time else { return false }
        }
        return true
    }

    /// The train of `line`'s `stream` to send out of the depot now, with
    /// its empty run, or `nil` (decision 209): while no other of its
    /// trains waits at an end or is on its way to one, the first in ID
    /// order standing in a depot of the line whose run is due (see
    /// ``isPullOutDue(_:_:lead:memo:)``) and, under traffic control, can
    /// take its route now. A line with several depots (decision 221) tries
    /// first the train with the shortest run out.
    func trainLeavingDepot(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard !line.depots.isEmpty, !line.hasRuns, clock.now.seconds >= 0, !hasTrainOnItsWay(line, stream, memo: &memo) else { return nil }
        var ids = line.trains(of: stream)
        if line.depots.count > 1 {
            var seconds: [TrainID: Int64] = [:]
            for id in ids {
                guard let train = train(id: id), isInDepot(train, of: line) else { continue }
                seconds[id] = pullOutTrip(of: train, on: line, stream.service, memo: &memo)?.deadhead?.seconds
            }
            ids.sort { (seconds[$0] ?? .max, $0) < (seconds[$1] ?? .max, $1) }
        }
        for id in ids {
            guard let index = trains.firstIndex(where: { $0.id == id }), trains[index].movement.rate > 0, isInDepot(trains[index], of: line),
                  let trip = pullOutTrip(of: trains[index], on: line, stream.service, memo: &memo), let run = trip.deadhead,
                  isPullOutDue(line, stream, lead: Self.lead(of: run), memo: &memo)
            else { continue }
            if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
               case .held = reservingDeparture(leaving, memo: &memo.directions) {
                continue
            }
            return (index, trip)
        }
        return nil
    }

    // MARK: - Into the depot

    /// The train of `line`'s `stream` to send into the depot now, with its
    /// empty run to the depot of the line it reaches soonest, or `nil`
    /// (decisions 209 and 221). Of its trains without a service
    /// standing at a station other than the depot: one that cannot be sent
    /// out from where it stands, or, while more of the stream's trains run
    /// or wait to be sent out than it runs now and ``waitingLead`` minutes
    /// from now (none once its window has closed), the last in ID order of
    /// those that wait. Under traffic
    /// control it must be able to take its route now.
    func trainEnteringDepot(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard !line.depots.isEmpty, !line.hasRuns, clock.now.seconds >= 0 else { return nil }
        var waiting: [Int] = [], stranded: [Int] = []
        for id in line.trains(of: stream) {
            guard let index = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[index]
            guard train.execution == nil, train.placement != nil, train.movement.rate > 0, !isInDepot(train, of: line),
                  !stationsStoppedAt(by: id).isEmpty
            else { continue }
            if readyTrip(of: train, on: line, stream.service, memo: &memo) != nil { waiting.append(index) } else { stranded.append(index) }
        }
        // A train sent out for a trip reaches its end up to
        // ``waitingLead`` minutes before it: it is not surplus meanwhile.
        let soon = Self.time(clock.now, plusMinutes: Self.waitingLead)
        let wanted = max(
            wanted(line, stream, at: clock.now, memo: &memo)?.trains ?? 0,
            soon.flatMap { wanted(line, stream, at: $0, memo: &memo)?.trains } ?? 0
        )
        let surplus = runningTrains(of: line, stream) + waiting.count > wanted
        for index in stranded + (surplus ? waiting.reversed() : []) {
            guard let trip = emptyRun(of: line, for: trains[index], to: line.depots) else { continue }
            if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
               case .held = reservingDeparture(leaving, memo: &memo.directions) {
                continue
            }
            return (index, trip)
        }
        return nil
    }

    // MARK: - Waking

    /// The whole minutes from now until the first minute at which `line`'s
    /// `stream` may send a train into or out of its depot (decision 209),
    /// or `nil` if none can before something changes: now if one can now;
    /// else, for a train that waits at a station, the next minute the
    /// line's window or level changes, now or ``waitingLead`` minutes
    /// later, and for each train in the depot the
    /// first minute at which, its lead later, the window or level changes
    /// or a headway since the last dispatch has passed. Nothing else that
    /// decides these changes without a train changing, so this is exact.
    func minutesUntilDepotMove(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> Int64? {
        guard !line.depots.isEmpty, !line.hasRuns else { return nil }
        let now = clock.now
        guard now.seconds >= 0 else { return Self.minutes(from: now, until: .zero) }
        if trainEnteringDepot(of: line, stream, memo: &memo) != nil || trainLeavingDepot(of: line, stream, memo: &memo) != nil { return 0 }
        var soonest: Int64?
        func wake(at time: GameTime?) {
            guard let time, time > now else { return }
            soonest = min(soonest ?? .max, Self.minutes(from: now, until: time))
        }
        let waits = line.trains(of: stream).contains { id in
            guard let train = train(id: id) else { return false }
            return train.execution == nil && !isInDepot(train, of: line) && !stationsStoppedAt(by: id).isEmpty
        }
        if waits {
            wake(at: line.nextChange(after: now, in: serviceDay))
            if let soon = Self.time(now, plusMinutes: Self.waitingLead) {
                wake(at: line.nextChange(after: soon, in: serviceDay).flatMap { Self.time($0, plusMinutes: -Self.waitingLead) })
            }
        }
        guard !hasTrainOnItsWay(line, stream, memo: &memo) else { return soonest }
        for id in line.trains(of: stream) {
            guard let train = train(id: id), train.movement.rate > 0, isInDepot(train, of: line),
                  let run = pullOutTrip(of: train, on: line, stream.service, memo: &memo)?.deadhead
            else { continue }
            let lead = Self.lead(of: run)
            guard let time = Self.time(now, plusMinutes: lead) else { continue }
            wake(at: line.nextChange(after: time, in: serviceDay).flatMap { Self.time($0, plusMinutes: -lead) })
            if let last = line.lastDispatch(of: stream), let wanted = wanted(line, stream, at: time, memo: &memo),
               let due = Self.time(last, plusMinutes: wanted.headway) {
                wake(at: Self.time(due, plusMinutes: -lead))
            }
        }
        return soonest
    }

    // MARK: - Costs

    /// What a depot costs a day for each of its sidings (decision 209), in
    /// cents: $400, about half what a train's energy and crew cost a day.
    public static let depotSidingDailyFee = Money(40_000)

    /// The sidings of the depots, one a platform (decision 209).
    func depotSidingCount() -> Int64 {
        Int64(network.platforms.count { station(id: $0.station)?.isDepot == true })
    }
}
