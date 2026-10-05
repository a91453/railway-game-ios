import GameCore

/// Decision 58 (Stage V2), written a second time for ``ReferenceWorld``:
/// passing places and deadlocks. Written from the rules, not from GameCore,
/// and differently where it can be:
///
/// - the trains in a deadlock are found in rounds: each round keeps, of the
///   trains kept so far, those that could not go if only the others kept
///   then held their track, until a round keeps them all (GameCore takes
///   trains away one at a time in ID order; both find the largest such
///   set);
/// - whether a train waits, and whether a passing place lets another go,
///   is asked by choosing its route as a departure does
///   (`chosenRoute(from:to:)`) on the world as it is, or on a copy with the
///   train moved to the passing place;
/// - a passing place's way on to the call is checked run by run against
///   the forbidden runs, the run it stands on first.
extension ReferenceWorld {
    // MARK: - Passing places

    /// Whether train `train`'s service stands at a passing place: it
    /// travels, its path is spent, and it is not stopped at its call's
    /// station.
    func atPassingPlace(_ train: Train) -> Bool {
        guard let service = train.service, !service.waiting, isStanding(train) else { return false }
        return !networkStops(of: train).contains(train.timetable[service.stop].station)
    }

    /// The train at a passing place set off on its default way on to its
    /// call, its run as fast as it can; `nil` when not at one, or with no
    /// way.
    mutating func goingOn(_ train: Train) -> Train? {
        guard atPassingPlace(train), let service = train.service else { return nil }
        let start = standing(train)
        guard let path = defaultRoute(from: start, to: train.timetable[service.stop].station), path.distance > 0 else { return nil }
        var going = routed(start, path)
        going.service = service
        let fastest = run(going, length: path.distance, scheduled: nil)
        going.service?.run = fastest
        return going
    }

    /// Decision 58: train `i`'s service, standing at a passing place, goes
    /// on to its call when its route lets it, chosen as any departure's is,
    /// as fast as it can.
    mutating func goOn(_ i: Int) {
        let plan = routeMemo.scheduled ?? scheduledPlan()
        guard waitingScheduled(trains[i], plan: plan) == nil, let going = goingOn(trains[i]), let service = going.service else { return }
        let start = standing(going)
        let target = going.timetable[service.stop].station
        // Decision 59: on the scheduled way and run when it can be had
        // whole now; otherwise as decision 58 has it, as fast as it can.
        if trafficControl, let way = scheduledRoute(trains[i], target: target, plan: plan), case .success = admitted(routed(start, way.path)) {
            var off = routed(start, way.path)
            off.service = service
            let plannedRun = run(off, length: way.path.distance, scheduled: way.seconds)
            off.service?.run = plannedRun
            off.trafficVisits = scheduledDepartureHistory(trains[i])
            _ = admit(off, at: i)
            return
        }
        guard let path = chosenRoute(from: start, to: target) else { return }
        var off = routed(start, path)
        off.service = service
        let fastest = run(off, length: path.distance, scheduled: nil)
        off.service?.run = fastest
        off.trafficVisits = scheduledDepartureHistory(trains[i])
        _ = admit(off, at: i, following: true)
    }

    // MARK: - Waiting

    /// Whether `candidate`, a train as it would set off (or end its
    /// service, or arrive at once), could take what it needs now under
    /// traffic control.
    mutating func canSetOff(_ candidate: Train) -> Bool {
        guard trafficControl, let service = candidate.service, !service.waiting else { return true }
        let start = standing(candidate)
        guard let path = chosenRoute(from: start, to: candidate.timetable[service.stop].station) else { return false }
        if case .success = admitted(routed(start, path), following: true) { return true }
        return false
    }

    /// The departure train `train` is due to make now, as it would set off
    /// without traffic control: a service due to leave, a line's train the
    /// line is due to send out, or a service at a passing place.
    mutating func departureCandidate(_ train: Train) -> Train? {
        if waitingScheduled(train, plan: routeMemo.scheduled ?? scheduledPlan()) != nil { return nil }
        if let service = train.service {
            guard service.waiting else { return goingOn(train) }
            guard let closing = service.closing, Self.capped(closing, 9) <= clockSeconds else { return nil }
            return firstLeaving(train)
        }
        guard let (l, k) = lineService(of: train.id), let trip = readyTrip(of: train, line: l, service: k) else { return nil }
        var sent = train
        sent.timetable = trip
        sent.period = nil
        sent.service = Service(stop: 0, waiting: true, arrival: clockSeconds)
        return firstLeaving(sent)
    }

    /// Decision 58: what train `train` waits for, as it would set off, and
    /// whether it waits to set off (or, following, to go on).
    mutating func waitingFor(_ train: Train) -> (candidate: Train, departs: Bool)? {
        guard trafficControl, train.position != nil else { return nil }
        if following(train) {
            guard !canMove(train), holder(of: needs(train).resources, except: train.id) != nil else { return nil }
            return (train, false)
        }
        guard let candidate = departureCandidate(train), !canSetOff(candidate) else { return nil }
        return (candidate, true)
    }

    /// What the trains `among` (not `id`) keep train `id` from.
    func blocked(for id: Int, among: Set<Int>) -> Set<TrackResource> {
        trains.filter { $0.id != id && $0.position != nil && among.contains($0.id) }.reduce(into: []) { $0.formUnion(blocking($1, for: id)) }
    }

    /// Whether `request` could go with only the trains `among` holding
    /// their track: all it needs free of theirs, or, setting off, an
    /// alternative way that is.
    mutating func couldGo(_ request: (candidate: Train, departs: Bool), among: Set<Int>) -> Bool {
        let candidate = request.candidate
        let blocked = blocked(for: candidate.id, among: among)
        if !foul(needs(candidate).resources, blocked) { return true }
        guard request.departs, let service = candidate.service, !service.waiting else { return false }
        let start = standing(candidate)
        let target = candidate.timetable[service.stop].station
        guard let path = defaultRoute(from: start, to: target),
              let other = alternative(from: start, to: target, default: path, avoiding: blocked)
        else { return false }
        return !foul(needs(routed(start, other)).resources, blocked)
    }

    /// Decision 58: the trains in a deadlock, each with what it waits for.
    mutating func deadlock() -> [Int: (candidate: Train, departs: Bool)] {
        var kept: [Int: (candidate: Train, departs: Bool)] = [:]
        for train in trains {
            if let request = waitingFor(train) { kept[train.id] = request }
        }
        while true {
            let ids = Set(kept.keys)
            var next = kept
            for (id, request) in kept where couldGo(request, among: ids.subtracting([id])) {
                next[id] = nil
            }
            if next.count == kept.count { return kept }
            kept = next
        }
    }

    mutating func deadlockedTrains() -> [TrainID] {
        let found = deadlock().keys.sorted()
        return found.map(TrainID.init(rawValue:))
    }

    // MARK: - The way out

    /// Decision 58: the passing place for `candidate` (setting off, in
    /// deadlock `stuck`): the way there and the whole way's length through
    /// it to the call.
    mutating func passingWay(for candidate: Train, stuck: [Int: (candidate: Train, departs: Bool)]) -> (path: TrainPath, distance: Int64)? {
        guard let service = candidate.service, !service.waiting else { return nil }
        let start = standing(candidate)
        let call = candidate.timetable[service.stop].station
        guard let planned = defaultRoute(from: start, to: call) else { return nil }
        let forbidden = contraryRuns(for: routed(start, planned))
        let blocked = blocked(for: candidate.id)
        var best: (path: TrainPath, distance: Int64)?
        for station in stations.sorted(by: { $0.id < $1.id }) where station.id != call.rawValue {
            guard let way = networkPathToStation(from: start.position!, station: StationID(rawValue: station.id), length: Self.length(start),
                                                 blocked: blocked, forbidden: forbidden),
                  way.distance > 0
            else { continue }
            let there = standing(followed(start, along: way))
            guard !isAtBerth(there, of: call), let onward = defaultRoute(from: there, to: call),
                  case .onEdge(let traversal, let offset)? = there.position
            else { continue }
            var runs = onward.traversals.map { Run($0)! }
            if offset < networkEdges[Run(traversal)!.edge]!.length { runs.insert(Run(traversal)!, at: 0) }
            guard runs.allSatisfy({ !forbidden.contains($0) }) else { continue }
            let total = way.distance + onward.distance
            guard total - planned.distance <= 25_600, total < best?.distance ?? .max else { continue }
            guard case .success = admitted(routed(start, way)) else { continue }
            // Standing there, another train of the deadlock could go.
            var trial = self
            var aside = there
            aside.service = service
            aside.reservation = []
            trial.trains[trial.trains.firstIndex { $0.id == candidate.id }!] = aside
            var frees = false
            for (id, request) in stuck.sorted(by: { $0.key < $1.key }) where id != candidate.id {
                if request.departs ? trial.canSetOff(request.candidate) : trial.holder(of: trial.needs(request.candidate).resources, except: id) == nil {
                    frees = true
                    break
                }
            }
            guard frees else { continue }
            best = (way, total)
        }
        return best
    }

    /// Decision 58: at a whole minute after the services, the first train
    /// of a deadlock, by ID, whose service is due to leave or stands at a
    /// passing place and has a passing place, sets off for it whole, as
    /// fast as it can; leaving a stop, it counts as a departure.
    mutating func resolveDeadlock() {
        guard trafficControl else { return }
        let stuck = deadlock()
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let i = trains.firstIndex(where: { $0.id == id }),
                  let before = trains[i].service, let way = passingWay(for: request.candidate, stuck: stuck)
            else { continue }
            var aside = routed(standing(request.candidate), way.path)
            aside.service = request.candidate.service
            let fastest = run(aside, length: way.path.distance, scheduled: nil)
            aside.service?.run = fastest
            guard case .success(let granted) = admitted(aside) else { continue }
            trains[i] = granted
            if before.waiting {
                refuseLeftBehind(i, stop: before.stop)
                countDeparture(i, distance: way.distance)
            }
            return
        }
    }
}
