// Deadlocks (Phase 4.6 Stage V2, ARCHITECTURE decision 58). Under traffic
// control a train takes a whole route or nothing (Stage T), follows only
// trains that will leave its way (Stage U2), and goes to another platform
// only where that runs against nobody (Stage V1), so trains that wait for
// each other in a circle are the waits left: two trains facing each other
// across a single track, or more round a station with too few platforms.
// Each train in such a circle waits for track only the others hold, and
// none of them can go: a deadlock. Once a minute the dispatcher looks for
// one and, where it can, sends one of its services to a passing place: a
// berth of a station on the way where it stands aside, so that another can
// go, and from where it goes on to its call once its route is free.
//
// Everything here is derived from the world as it is, read-only: which
// trains wait, for whom, and whether a passing place would help. Only the
// passing place a service sets off for is ever committed, by
// `resolveDeadlock(memo:)` in GameWorld.swift.

extension GameWorld {
    // MARK: - Passing places

    /// Whether `train`'s service has stopped at a passing place on its way
    /// (Stage V2): it travels to a call, its path is spent, and it stands
    /// at a berth of another station than the call's.
    func isAtPassingPlace(_ train: Train) -> Bool {
        guard case .travellingToStop(let stop, _)? = train.execution, standingPoint(of: train) != nil else { return false }
        return !isStopped(train, at: train.timetable[stop].station)
    }

    /// The station of the passing place where train `id`'s service stands
    /// aside (Stage V2, see ``deadlockedTrains()``), or `nil` when it
    /// stands at none. From there it goes on to its call once its route is
    /// free (see ``trainHoldingRoute(of:)``).
    public func passingPlace(of id: TrainID) -> StationID? {
        guard let train = train(id: id), isAtPassingPlace(train) else { return nil }
        return stationsStoppedAt(by: id).first
    }

    /// `train`, stopped at a passing place, as it would go on to its call:
    /// along the route services take from where it stands (see
    /// ``path(from:toStation:length:)``), as fast as it can (it is off its
    /// timetable). `nil` when it is not at a passing place, or there is no
    /// such route.
    func goingOn(_ train: Train) -> Train? {
        guard isAtPassingPlace(train), case .travellingToStop(let stop, _)? = train.execution, let placement = train.placement,
              let path = path(from: placement.position, toStation: train.timetable[stop].station, length: train.length),
              path.distance > 0
        else { return nil }
        var going = train
        follow(path, &going)
        let fastest = run(of: going, length: path.distance)
        going.times?.run = fastest
        return going
    }

    // MARK: - Who waits for whom

    /// The route `train` waits for under traffic control, as the train
    /// would take it, or `nil` when it waits for none: a service due to
    /// leave a stop, a line's train the line is due to send out, or a
    /// service going on from a passing place (Stage V2), whose departure
    /// cannot take its route in any way (see
    /// ``reservingDeparture(_:)``); or a train following others (Stage
    /// U2) that has come as far as its reservation holds and cannot take
    /// more. `departs` is whether it waits to set off (as opposed to
    /// following). A train that can still move is not waiting: moving on
    /// changes what it holds.
    func waitingRoute(of train: Train, memo: inout DirectionMemo) -> (candidate: Train, departs: Bool)? {
        guard isTrafficControlEnabled, train.position != nil else { return nil }
        if isFollowing(train) {
            let step = travelling(train, distance: 1)
            guard step.position == train.position, step.cursor == train.movement.cursor,
                  holder(of: routeEnvelope(of: train).resources, except: train.id) != nil
            else { return nil }
            return (train, false)
        }
        guard let candidate = departureRequest(of: train), case .held = reservingDeparture(candidate, memo: &memo, traffic: trafficPlan()) else { return nil }
        return (candidate, true)
    }

    /// The departure train `train` is due to make now, as it would leave,
    /// whether or not its route is free: a service due to leave a stop (see
    /// ``departureDue(of:)``), a line's train the line is due to send out
    /// (along the first leg of its trip), or a service going on from a
    /// passing place (Stage V2, see ``goingOn(_:)``). `nil` for any other
    /// train.
    func departureRequest(of train: Train) -> Train? {
        let plan = trafficPlan()
        if currentTrafficWait(train, plan: plan) != nil { return nil }
        switch train.execution {
        case .waitingAtStop(let stop, let cycle)?:
            guard let due = departureDue(of: train), due <= clock.now else { return nil }
            return leaving(train, stop: stop, cycle: cycle, traffic: plan).train
        case .travellingToStop?:
            guard var going = goingOn(train) else { return nil }
            if let chosen = scheduledPath(for: train, from: train.position!, to: train.timetable[train.execution!.stop].station, plan: plan) {
                follow(chosen.path, &going)
                let plannedRun = run(of: going, length: chosen.path.distance, scheduled: chosen.seconds)
                going.times?.run = plannedRun
            }
            return going
        case nil:
            guard let line = lines.first(where: { assignedLine(of: train.id) == $0.id }),
                  let stream = line.dispatchStream(of: train.id)
            else { return nil }
            var memo = DispatchMemo()
            guard isDispatchDue(line, stream, at: clock.now, memo: &memo),
                  let trip = readyTrip(of: train, on: line, stream.service, memo: &memo)
            else { return nil }
            return firstDeparture(of: train, on: trip, calling: line.stops, traffic: plan)
        }
    }

    /// Everything the trains `among` (other than `id`) keep train `id`
    /// from, as ``blockedTrack(except:)`` does for all of them.
    func blockedTrack(except id: TrainID, among ids: Set<TrainID>) -> Set<TrackResource> {
        let own = train(id: id).map(held) ?? []
        var blocked: Set<TrackResource> = []
        for other in trains where other.id != id && other.position != nil && ids.contains(other.id) {
            blocked.formUnion(held(other))
            if let claim = claim(of: other), own.isDisjoint(with: claim.route) {
                blocked.formUnion(claim.waiting)
            }
        }
        return blocked
    }

    /// Whether `request` (see ``waitingRoute(of:memo:)``) could go if, of all
    /// the trains, only those `among` kept their track: its route is free
    /// of theirs, or, for a departure, an alternative route (decision 57)
    /// is. Following them is never possible: they all wait.
    private func couldGo(_ request: (candidate: Train, departs: Bool), among ids: Set<TrainID>, memo: inout DirectionMemo) -> Bool {
        let candidate = request.candidate
        let blocked = blockedTrack(except: candidate.id, among: ids)
        if !network.fouls(routeEnvelope(of: candidate).resources, blocked) { return true }
        guard request.departs, case .travellingToStop(let stop, _)? = candidate.execution,
              let alternative = alternativeRoute(of: candidate, to: reservationDestination(candidate, call: candidate.timetable[stop].station, traffic: trafficPlan()), avoiding: blocked, memo: &memo)
        else { return false }
        var rerouted = candidate
        follow(alternative, &rerouted)
        return !network.fouls(routeEnvelope(of: rerouted).resources, blocked)
    }

    /// The trains in a deadlock under traffic control (Stage V2), with the
    /// route each waits for (see ``waitingRoute(of:memo:)``): of the trains that
    /// wait, those that could not go even if every other train, but those
    /// that wait with them, gave up all its track. Found as a deadlock is
    /// classically found: start from all the trains that wait, and take
    /// away, again and again in ID order, any that could go with only those
    /// left keeping their track, until none can. A train that waits for a
    /// moving train, or for one that will set off later, is never in one:
    /// that one will leave. Empty when there is none, and when traffic
    /// control is off.
    func deadlock(memo: inout DirectionMemo) -> [TrainID: (candidate: Train, departs: Bool)] {
        var waiting: [TrainID: (candidate: Train, departs: Bool)] = [:]
        for train in trains {
            if let request = waitingRoute(of: train, memo: &memo) { waiting[train.id] = request }
        }
        var changed = true
        while changed {
            changed = false
            for id in waiting.keys.sorted() {
                let others = Set(waiting.keys).subtracting([id])
                if couldGo(waiting[id]!, among: others, memo: &memo) {
                    waiting[id] = nil
                    changed = true
                }
            }
        }
        return waiting
    }

    /// The trains in a deadlock under traffic control (Stage V2, see
    /// ``deadlock(memo:)``), in ascending ID order: each waits for a route that
    /// only trains waiting with it hold, so none of them can ever go by
    /// itself. Once a minute the dispatcher sends one of their services to
    /// a passing place where that lets another go; a deadlock with no such
    /// place stays until the player changes something (more platforms, a
    /// passing loop, fewer trains). Derived on every call, never saved.
    public func deadlockedTrains() -> [TrainID] {
        var memo = DirectionMemo()
        return deadlock(memo: &memo).keys.sorted()
    }

    // MARK: - The way out

    /// The way for `candidate`, a service in deadlock `stuck` (see
    /// ``deadlock(memo:)``) about to set off for its call, through a passing
    /// place (Stage V2): the path to the berth where it stands aside, and
    /// the whole way's length through it to the call. Of the stations
    /// other than the call's, in ascending ID order, each one's nearest
    /// berth (see ``path(from:toStation:length:avoiding:forbidden:)``)
    /// that the train can take the way to now, that borrows no track
    /// against another train's planned direction (decision 57, see
    /// ``opposingServiceTraversals(for:memo:)``) on the way there or on from
    /// there to the call, that keeps the whole way within
    /// ``detourAllowance`` of the default route, and where its standing
    /// lets another train of the deadlock go; the shortest whole way, the
    /// first station on a tie. `nil` if there is none.
    func passingPlace(for candidate: Train, in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DirectionMemo) -> (path: TrainPath, distance: Int64)? {
        guard case .travellingToStop(let stop, _)? = candidate.execution, let start = candidate.placement else { return nil }
        let call = candidate.timetable[stop].station
        let forbidden = opposingServiceTraversals(for: candidate, memo: &memo)
        let blocked = blockedTrack(except: candidate.id)
        let (limit, overflow) = routeLength(of: candidate).addingReportingOverflow(Self.detourAllowance)
        var best: (path: TrainPath, distance: Int64)?
        for station in stations where station.id != call {
            guard let way = path(from: start.position, toStation: station.id, length: candidate.length, avoiding: blocked, forbidden: forbidden),
                  way.distance > 0
            else { continue }
            let there = placement(start, after: way)
            guard let onward = path(from: there.position, toStation: call, length: candidate.length), onward.distance > 0,
                  onward.traversals.allSatisfy({ !forbidden.contains($0) })
            else { continue }
            if case .onEdge(let traversal, let offset) = there.position, offset < network.edge(traversal.edge)!.length,
               forbidden.contains(traversal) {
                continue
            }
            let (distance, long) = way.distance.addingReportingOverflow(onward.distance)
            guard !long, overflow || distance <= limit, distance < best?.distance ?? .max else { continue }
            var routed = candidate
            follow(way, &routed)
            guard case .granted = reserving(routed) else { continue }
            // Standing there, it must let another train of the deadlock go.
            var standing = candidate
            standing.position = there.position
            standing.trailEdges = there.trailEdges
            standing.movement.edges = []
            standing.movement.cursor = 0
            standing.movement.end = way.end
            standing.reservation = []
            let aside = replacing(standing)
            var freed = false
            for (id, request) in stuck where id != candidate.id {
                if request.departs {
                    if case .granted = aside.reservingDeparture(request.candidate, memo: &memo, traffic: aside.trafficPlan()) { freed = true }
                } else if aside.holder(of: aside.routeEnvelope(of: request.candidate).resources, except: id) == nil {
                    freed = true
                }
                if freed { break }
            }
            guard freed else { continue }
            best = (way, distance)
        }
        return best
    }
}
