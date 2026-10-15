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

    /// Decision 228: how long before and after another train's time at a
    /// platform this one keeps off it: three minutes, a high-speed line's
    /// least headway.
    static let platformClearance: Int64 = 3 * GameTime.secondsPerMinute

    /// When `train` is at the station of its timetable entry `stop` (of
    /// `cycle`), as its timetable has it: from its arrival to its
    /// departure; when the service ends there, until it leaves again (see
    /// ``runLeaving(of:at:readyAt:)``), or with no end (decision 228).
    func platformTimes(of train: Train, stop: Int, cycle: Int64) -> (from: Int64, until: Int64) {
        let arrival = train.scheduledArrival(of: stop, cycle: cycle).seconds
        guard train.call(after: stop, cycle: cycle) == nil else { return (arrival, train.scheduledDeparture(of: stop, cycle: cycle).seconds) }
        return (arrival, runLeaving(of: train, at: train.timetable[stop].station, readyAt: arrival) ?? .max)
    }

    /// Decision 228: when `train`, of a line with runs, standing at
    /// `station` without a service from `ready` on, leaves it, as decision
    /// 221 sends its line's trains on (``runTrainEnteringDepot(of:memo:)``,
    /// ``readyRunTrain(of:_:day:)``): of the trains waiting there, those
    /// beyond the runs leaving within ``runDepotLookahead`` go into a depot
    /// at once, the last in ID order first; each run takes the first in ID
    /// order of those standing there by its first departure, the trains
    /// ending a service there joining them as they arrive; a train no run
    /// takes goes into a depot when it is ready. `nil` for a train of no
    /// line with runs, or one no run takes and with no depot to go to: it
    /// stands there until it is moved.
    func runLeaving(of train: Train, at station: StationID, readyAt ready: Int64) -> Int64? {
        guard let line = lines.first(where: { $0.hasRuns && $0.trains.contains(train.id) }) else { return nil }
        let now = clock.now.seconds
        let starts = pendingRunStarts(of: line, from: station).sorted()
        let wanted = starts.count { $0 <= now + Self.runDepotLookahead }
        // Those waiting now, in ID order, and those arriving, by arrival.
        var waiting: [(order: Int, id: TrainID)] = []
        var arriving: [(time: Int64, order: Int, id: TrainID)] = []
        for (order, id) in line.trains.enumerated() {
            guard let other = id == train.id ? train : self.train(id: id), other.placement != nil, other.movement.rate > 0 else { continue }
            if id == train.id {
                if ready <= now, other.execution == nil { waiting.append((order, id)) } else { arriving.append((ready, order, id)) }
            } else if other.execution == nil, isStopped(other, at: station) {
                waiting.append((order, id))
            } else if other.execution != nil, let last = other.timetable.last, last.station == station {
                arriving.append((last.arrival.seconds, order, id))
            }
        }
        if !line.depots.isEmpty, let index = waiting.firstIndex(where: { $0.id == train.id }), index >= wanted { return now + Self.depotLeaving }
        var pool = line.depots.isEmpty ? waiting : Array(waiting.prefix(wanted))
        arriving.sort { ($0.time, $0.order) < ($1.time, $1.order) }
        var next = 0
        for start in starts {
            while next < arriving.count, arriving[next].time <= start {
                pool.append((arriving[next].order, arriving[next].id))
                next += 1
            }
            guard let first = pool.indices.min(by: { pool[$0].order < pool[$1].order }) else { continue }
            if pool[first].id == train.id {
                return start <= now + Self.runDepotLookahead || line.depots.isEmpty ? start : ready + Self.depotLeaving
            }
            pool.remove(at: first)
        }
        return line.depots.isEmpty ? nil : ready + Self.depotLeaving
    }

    /// How long a train bound for a depot stands where it is ready before
    /// it has left (decision 228): five minutes, its least dwell, its
    /// empty run sent out and the way off the platform.
    static let depotLeaving: Int64 = 5 * GameTime.secondsPerMinute

    /// Decision 228: with traffic control off, until when another train is
    /// due on each platform of station `station` (not a depot) that
    /// `train`, due there over `times`, fits, by the platform's edge: 0
    /// where none is meanwhile; 1 where one stands now but is due to leave
    /// in time (so an empty platform comes first); otherwise the latest any
    /// such train leaves, ``platformClearance`` after it, or `Int64.max` for
    /// one with no end there. A train is due on a platform while it stands
    /// there until it leaves (see ``platformTimes(of:stop:cycle:)`` and
    /// ``runLeaving(of:at:readyAt:)``), or runs there for its own time
    /// there; each is kept ``platformClearance`` apart from `train`'s.
    /// `nil` when traffic control is on (it keeps trains apart itself), for
    /// a train of a line without real runs (``followsRealTimetable(_:)``:
    /// it goes where it always did), when the station is a depot (see
    /// ``freeDepotBerths(_:for:)``), or the train fits fewer than two of
    /// its platforms.
    func platformWaits(_ station: StationID, for train: Train, over times: (from: Int64, until: Int64)) -> [TrackEdgeID: Int64]? {
        guard !isTrafficControlEnabled, let stop = self.station(id: station), !stop.isDepot, followsRealTimetable(train) else { return nil }
        let edges = Set(berths(of: station, length: train.length).map(\.traversal.edge))
        guard edges.count > 1 else { return nil }
        let clearance = Self.platformClearance
        func plus(_ time: Int64) -> Int64 {
            let (sum, overflow) = time.addingReportingOverflow(clearance)
            return overflow ? .max : sum
        }
        var waits = Dictionary(uniqueKeysWithValues: edges.map { ($0, Int64(0)) })
        func due(_ edge: TrackEdgeID, _ other: (from: Int64, until: Int64), standing: Bool = false) {
            guard edges.contains(edge) else { return }
            guard other.from < plus(times.until), times.from - clearance < other.until else {
                // One standing there now and due to leave in time: free,
                // but after any empty platform.
                if standing { waits[edge] = max(waits[edge] ?? 0, 1) }
                return
            }
            waits[edge] = max(waits[edge] ?? 0, plus(other.until))
        }
        for other in trains where other.id != train.id {
            switch other.execution {
            case .waitingAtStop(let at, let cycle)? where other.timetable[at].station == station:
                let until = platformTimes(of: other, stop: at, cycle: cycle).until
                for stretch in bodyStretches(of: other) { due(stretch.traversal.edge, (clock.now.seconds, until), standing: true) }
            case .travellingToStop(let next, let cycle)? where other.timetable[next].station == station:
                if let last = other.movement.edges.last { due(last, platformTimes(of: other, stop: next, cycle: cycle)) }
                else if case .onEdge(let traversal, _)? = other.position { due(traversal.edge, platformTimes(of: other, stop: next, cycle: cycle)) }
            case nil:
                let parts = bodyStretches(of: other).filter { edges.contains($0.traversal.edge) }
                guard !parts.isEmpty else { break }
                let until = runLeaving(of: other, at: station, readyAt: clock.now.seconds) ?? .max
                for stretch in parts { due(stretch.traversal.edge, (clock.now.seconds, until), standing: true) }
            default:
                break
            }
        }
        return waits
    }

    /// The way from `start` into one of depot `station`'s free sidings for
    /// `train` (decision 221), keeping left as any other way does
    /// (decision 202); `nil` when `station` is not a depot, none is free
    /// or none is reached.
    func pathIntoDepot(_ station: StationID, from start: TrainPosition, for train: Train, memo: inout PathMemo) -> TrainPath? {
        guard let free = freeDepotBerths(station, for: train) else { return nil }
        // Decision 228: with traffic control off, a train of real runs
        // keeps off the track where other trains stand on its way, as a
        // depot beyond a station's platforms is reached through one of them.
        if !isTrafficControlEnabled, followsRealTimetable(train) {
            let standing = Set(trains.filter { $0.id != train.id && !isMoving($0) }.flatMap { bodyStretches(of: $0).map(\.traversal.edge) })
            if !standing.isEmpty { return path(from: start, toStation: station, length: train.length, eligible: free, keepingLeft: true, avoiding: standing) }
        }
        return path(from: start, toStation: station, length: train.length, eligible: free, keepingLeft: true, memo: &memo)
    }

    /// Whether `train` is on its way: travelling to a stop of its service.
    private func isMoving(_ train: Train) -> Bool {
        if case .travellingToStop? = train.execution { return true }
        return false
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
        let needed = max(
            wanted(line, stream, at: clock.now, memo: &memo)?.trains ?? 0,
            soon.flatMap { wanted(line, stream, at: $0, memo: &memo)?.trains } ?? 0
        )
        let surplus = runningTrains(of: line, stream) + waiting.count > needed
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
