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

    /// Whether `train`, without a service, stands at `line`'s depot.
    func isInDepot(_ train: Train, of line: ServiceLine) -> Bool {
        guard let depot = line.depot, train.execution == nil else { return false }
        return isStopped(train, at: depot)
    }

    /// Whether `train`, without a service, stands at any depot (decision
    /// 209).
    func standsInADepot(_ train: Train) -> Bool {
        guard train.execution == nil, stations.contains(where: \.isDepot) else { return false }
        return stationsStoppedAt(by: train.id).contains { station(id: $0)?.isDepot == true }
    }

    /// Whether `train` runs empty to `line`'s depot.
    func isPullingIn(_ train: Train, of line: ServiceLine) -> Bool {
        guard let depot = line.depot else { return false }
        return train.isDeadheading && train.timetable.last?.station == depot
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
                    guard let least = plannedSeconds(length: path.distance, line: line) else { continue }
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

    /// The whole minutes before its trip a train out of the depot leaves:
    /// its least dwell and the run's seconds, rounded up, and a minute
    /// more, so that it stands at the end, its run over, when the trip is
    /// due.
    private static func lead(of run: LineTrip.DeadheadRun) -> Int64 {
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
    /// order standing in the depot whose run is due (see
    /// ``isPullOutDue(_:_:lead:memo:)``) and, under traffic control, can
    /// take its route now.
    func trainLeavingDepot(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard line.depot != nil, !line.hasRuns, clock.now.seconds >= 0, !hasTrainOnItsWay(line, stream, memo: &memo) else { return nil }
        for id in line.trains(of: stream) {
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
    /// empty run, or `nil` (decision 209). Of its trains without a service
    /// standing at a station other than the depot: one that cannot be sent
    /// out from where it stands, or, while more of the stream's trains run
    /// or wait to be sent out than it runs now (none once its window has
    /// closed), the last in ID order of those that wait. Under traffic
    /// control it must be able to take its route now.
    func trainEnteringDepot(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard let depot = line.depot, !line.hasRuns, clock.now.seconds >= 0 else { return nil }
        var waiting: [Int] = [], stranded: [Int] = []
        for id in line.trains(of: stream) {
            guard let index = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[index]
            guard train.execution == nil, train.placement != nil, train.movement.rate > 0, !isInDepot(train, of: line),
                  !stationsStoppedAt(by: id).isEmpty
            else { continue }
            if readyTrip(of: train, on: line, stream.service, memo: &memo) != nil { waiting.append(index) } else { stranded.append(index) }
        }
        let wanted = wanted(line, stream, at: clock.now, memo: &memo)?.trains ?? 0
        let surplus = runningTrains(of: line, stream) + waiting.count > wanted
        for index in stranded + (surplus ? waiting.reversed() : []) {
            guard let trip = emptyRun(of: line, for: trains[index], to: [depot]) else { continue }
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
    /// line's window or level changes, and for each train in the depot the
    /// first minute at which, its lead later, the window or level changes
    /// or a headway since the last dispatch has passed. Nothing else that
    /// decides these changes without a train changing, so this is exact.
    func minutesUntilDepotMove(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> Int64? {
        guard line.depot != nil, !line.hasRuns else { return nil }
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
        if waits { wake(at: line.nextChange(after: now, in: serviceDay)) }
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
