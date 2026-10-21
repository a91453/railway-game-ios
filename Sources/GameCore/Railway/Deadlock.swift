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
// A line's spare train (a later fix to decision 58) has no service, so
// nothing else ever moves it: it keeps its track as a waiting train does,
// and where no service can step aside the dispatcher moves the spare out
// of the way instead. Where there is neither, a service that would come
// back through the station it waits at turns back there short (decision
// 255), leaving out the calls it cannot reach past the other train.
//
// Everything here is derived from the world as it is, read-only: which
// trains wait, for whom, and whether a passing place would help. Only the
// passing place a service (or a spare) sets off for is ever committed, by
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
              let onward = passingContinuation(from: placement, to: train.timetable[stop].station)
        else { return nil }
        var going = train
        going.position = onward.start.position
        going.trailEdges = onward.start.trailEdges
        let path = onward.path
        follow(path, &going)
        let fastest = run(of: going, length: path.distance)
        going.times?.run = fastest
        return going
    }

    /// A dead-end passing berth needs the same whole-body reversal as a
    /// timetable turnback. The ordinary facing always wins when reachable.
    /// The candidate is committed only after its departure is reserved.
    func passingContinuation(from place: TrainPlacement, to call: StationID) -> (start: TrainPlacement, path: TrainPath)? {
        for start in [place, turnedRound(place)] {
            if let path = path(from: start.position, toStation: call, length: start.length), path.distance > 0 {
                return (start, path)
            }
        }
        return nil
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
        if isFollowing(train, memo: &memo) {
            let step = travelling(train, distance: 1, memo: &memo)
            guard step.position == train.position, step.cursor == train.movement.cursor,
                  holder(of: envelopeCover(of: train), except: train.id, holders: trackHolders(memo: &memo)) != nil
            else { return nil }
            return (train, false)
        }
        guard let candidate = departureRequest(of: train, memo: &memo), case .held = reservingDeparture(candidate, memo: &memo) else { return nil }
        return (candidate, true)
    }

    /// The departure train `train` is due to make now, as it would leave,
    /// whether or not its route is free: a service due to leave a stop (see
    /// ``departureDue(of:)``), a line's train the line is due to send out
    /// (along the first leg of its trip), or a service going on from a
    /// passing place (Stage V2, see ``goingOn(_:)``). `nil` for any other
    /// train.
    func departureRequest(of train: Train, memo: inout DirectionMemo) -> Train? {
        if currentTrafficWait(train, plan: trafficPlan(memo: &memo), memo: &memo) != nil { return nil }
        switch train.execution {
        case .waitingAtStop(let stop, let cycle)?:
            guard let due = departureDue(of: train), due <= clock.now else { return nil }
            if let preferred = preferredLeaving(train, stop: stop, cycle: cycle, memo: &memo.paths)?.train,
               case .granted = reserving(preferred, memo: &memo) { return preferred }
            return leaving(train, stop: stop, cycle: cycle, memo: &memo.paths).train
        case .travellingToStop?:
            if let preferred = preferredGoingOn(train), case .granted = reserving(preferred, memo: &memo) { return preferred }
            return goingOn(train)
        case nil:
            guard let line = lines.first(where: { assignedLine(of: train.id) == $0.id }) else { return nil }
            // Decision 133: a train a due run would send out.
            if line.hasRuns { return dueRunDeparture(of: train, on: line) }
            guard let stream = line.dispatchStream(of: train.id) else { return nil }
            var memo = DispatchMemo()
            guard let trip = readyTrip(of: train, on: line, stream.service, memo: &memo),
                  isDispatchDue(line, stream, at: clock.now, deadhead: trip.deadhead != nil, from: trip.fromLastCall ? .last : .first, memo: &memo)
            else { return nil }
            return firstDeparture(of: train, on: trip, calling: line.stops)
        }
    }

    /// Whether `train` is a spare of its line (decision 58, a later fix):
    /// assigned to a line that sends its trains out by headway (not by
    /// runs, decision 133), without a service, standing where its path
    /// ends with a rate above 0, while the line's window is open and it
    /// already runs as many trains as it plans (see
    /// ``isDispatchDue(_:_:at:deadhead:memo:)``).
    /// Until the line wants another train nothing sends it anywhere, so a
    /// train waiting for its track waits as long as for a train of a
    /// deadlock (see ``deadlock(memo:)``).
    ///
    /// With block sections (decision 212), a train of a line that sends
    /// its trains out by runs is a spare too between them: without a
    /// service, standing where its path ends with a rate above 0, while no
    /// run of its line is due for it. It may stand aside only at the
    /// station it stands at (see ``spareStandingAside(in:memo:)``), where
    /// its next run starts.
    func isSpare(_ train: Train) -> Bool {
        guard train.execution == nil, train.movement.rate > 0, standingPoint(of: train) != nil,
              let line = lines.first(where: { assignedLine(of: train.id) == $0.id })
        else { return false }
        if line.hasRuns {
            return blockSections && dueRunDeparture(of: train, on: line) == nil
        }
        guard line.window.contains(minuteOfDay: clock.now.minuteOfDay),
              let stream = line.dispatchStream(of: train.id)
        else { return false }
        var memo = DispatchMemo()
        return !isDispatchDue(line, stream, at: clock.now, deadhead: true, memo: &memo)
    }

    /// Where a spare may stand aside (see ``spareStandingAside(in:memo:)``):
    /// the nearest berth of any station, or, for a train of a line that
    /// sends its trains out by runs, each berth of the stations it stands
    /// at, where its next run starts (decision 212): the nearest berth of
    /// those is where it stands.
    private func standingAsideTargets(for spare: Train) -> [(station: StationID, berth: Berth?)] {
        guard lines.first(where: { assignedLine(of: spare.id) == $0.id })?.hasRuns == true else { return stations.map { ($0.id, nil) } }
        let here = Set(stationsStoppedAt(by: spare.id))
        return stations.filter { here.contains($0.id) }.flatMap { station in
            berths(of: station.id, length: spare.length).map { (station.id, Optional($0)) }
        }
    }

    /// Everything the trains `among` (other than `id`) keep train `id`
    /// from, as ``blockedTrack(except:)`` does for all of them.
    func blockedTrack(except id: TrainID, among ids: Set<TrainID>) -> Set<TrackResource> {
        var memo = DirectionMemo()
        return blockedTrack(except: id, among: ids, memo: &memo)
    }

    /// ``blockedTrack(except:among:)`` from the trains' holders kept in
    /// `memo` (see ``trackHolders(memo:)``).
    func blockedTrack(except id: TrainID, among ids: Set<TrainID>, memo: inout DirectionMemo) -> Set<TrackResource> {
        blockedTrack(except: id, among: ids, holders: trackHolders(memo: &memo)).resources
    }

    /// Whether `request` (see ``waitingRoute(of:memo:)``) could go if, of all
    /// the trains, only those `among` kept their track: its route is free
    /// of theirs, or, for a departure, an alternative route (decision 57)
    /// is. Following them is never possible: they all wait.
    private func couldGo(_ request: (candidate: Train, departs: Bool), among ids: Set<TrainID>, memo: inout DirectionMemo) -> Bool {
        let candidate = request.candidate
        let blocked = blockedTrack(except: candidate.id, among: ids, holders: trackHolders(memo: &memo))
        if !blocked.blocks(envelopeCover(of: candidate), in: network) { return true }
        guard request.departs, case .travellingToStop(let stop, _)? = candidate.execution,
              let alternative = alternativeRoute(of: candidate, to: candidate.timetable[stop].station, avoiding: blocked, memo: &memo)
        else { return false }
        var rerouted = candidate
        follow(alternative, &rerouted)
        return !blocked.blocks(envelopeCover(of: rerouted), in: network)
    }

    /// The trains in a deadlock under traffic control (Stage V2), with the
    /// route each waits for (see ``waitingRoute(of:memo:)``): of the trains that
    /// wait, those that could not go even if every other train, but those
    /// that wait with them, gave up all its track. Found as a deadlock is
    /// classically found: start from all the trains that wait, and take
    /// away, again and again in ID order, any that could go with only those
    /// left keeping their track, until none can. A train that waits for a
    /// moving train, or for one that will set off later, is never in one:
    /// that one will leave. A line's spare (see ``isSpare(_:)``) always
    /// keeps its track, as the trains left do, but is not in the deadlock
    /// itself: it waits for nothing. Empty when there is none, and when
    /// traffic control is off.
    func deadlock(memo: inout DirectionMemo) -> [TrainID: (candidate: Train, departs: Bool)] {
        var waiting: [TrainID: (candidate: Train, departs: Bool)] = [:]
        for train in trains {
            if let request = waitingRoute(of: train, memo: &memo) { waiting[train.id] = request }
        }
        let spares = waiting.isEmpty ? [] : Set(trains.lazy.filter { waiting[$0.id] == nil && self.isSpare($0) }.map(\.id))
        var changed = true
        while changed {
            changed = false
            for id in waiting.keys.sorted() {
                let others = Set(waiting.keys).union(spares).subtracting([id])
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
    /// only trains waiting with it, or a line's spares, hold, so none of
    /// them can ever go by itself. Once a minute the dispatcher sends one
    /// of their services to a passing place where that lets another go, or
    /// else moves a spare out of the way, or else turns a service back
    /// short (decision 255, see ``shortTurn(of:in:)``); a deadlock with
    /// none of them stays until the player changes something (more
    /// platforms, a passing loop, fewer trains). Derived on every call,
    /// never saved.
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
    func passingPlace(for candidate: Train, in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DirectionMemo) -> (path: TrainPath, distance: Int64, reverses: Bool)? {
        // Preserve V2's ordinary passing-place selection before considering
        // a backing move. A reversal is possible only from a full berth.
        let forbidden = opposingServiceTraversals(for: candidate, memo: &memo)
        let length = routeLength(of: candidate)
        if let way = passingPlace(for: candidate, in: stuck, forbidden: forbidden, defaultLength: length, memo: &memo) {
            return (way.path, way.distance, false)
        }
        guard isTrafficControlEnabled, !stationsBesideWholeTrain(candidate.id).isEmpty,
              let place = candidate.placement else { return nil }
        let reverse = turnedRound(place)
        var backing = candidate
        backing.position = reverse.position
        backing.trailEdges = reverse.trailEdges
        guard let way = passingPlace(for: backing, in: stuck, forbidden: forbidden, defaultLength: length, allBerths: true, memo: &memo) else { return nil }
        return (way.path, way.distance, true)
    }

    private func passingPlace(for candidate: Train, in stuck: [TrainID: (candidate: Train, departs: Bool)], forbidden: Set<TrackTraversal>, defaultLength: Int64, allBerths: Bool = false, memo: inout DirectionMemo) -> (path: TrainPath, distance: Int64)? {
        guard case .travellingToStop(let stop, _)? = candidate.execution, let start = candidate.placement else { return nil }
        let call = candidate.timetable[stop].station
        let blocked = blockedTrack(except: candidate.id, holders: trackHolders(memo: &memo))
        let (limit, overflow) = defaultLength.addingReportingOverflow(Self.detourAllowance)
        var best: (path: TrainPath, distance: Int64)?
        for station in stations where station.id != call {
            // Keep the original forward choice. Only the reverse fallback
            // enumerates berths: the nearest main berth may block the peer
            // while a slightly farther siding releases it.
            let targets: [Berth?] = allBerths ? berths(of: station.id, length: candidate.length).map { $0 } : [nil]
            for target in targets {
                guard let way = path(from: start.position, toStation: station.id, length: candidate.length, avoiding: blocked, forbidden: forbidden, only: target),
                      way.distance > 0
                else { continue }
                let there = placement(start, after: way)
                guard let next = passingContinuation(from: there, to: call),
                      next.path.traversals.allSatisfy({ !forbidden.contains($0) })
                else { continue }
                let onward = next.path
                if case .onEdge(let traversal, let offset) = next.start.position, offset < network.edge(traversal.edge)!.length,
                   forbidden.contains(traversal) {
                    continue
                }
                let (distance, long) = way.distance.addingReportingOverflow(onward.distance)
                guard !long, overflow || distance <= limit, distance < best?.distance ?? .max else { continue }
                var routed = candidate
                follow(way, &routed)
                guard case .granted = reserving(routed, memo: &memo) else { continue }
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
                        if case .granted = aside.reservingDeparture(request.candidate, memo: &memo) { freed = true }
                    } else if aside.holder(of: aside.envelopeCover(of: request.candidate), except: id, holders: aside.trackHolders(memo: &memo)) == nil {
                        freed = true
                    }
                    if freed { break }
                }
                guard freed else { continue }
                best = (way, distance)
            }
        }
        return best
    }

    // MARK: - A spare out of the way

    /// A line's spare (see ``isSpare(_:)``) moved out of the way of deadlock
    /// `stuck` (decision 58, a later fix), as it sets off, or `nil`: of the
    /// spares in ascending ID order, the first that holds track a train of
    /// the deadlock waits for, and has a way to a berth where, standing,
    /// it lets one of those trains go. Of the stations in ascending ID
    /// order, each one's nearest berth (see
    /// ``path(from:toStation:length:avoiding:forbidden:only:)``) that the
    /// spare can take the way to now, from where it stands or, beside a
    /// platform its whole length, turned round; the shortest way, the first
    /// found on a tie. The spare keeps no service: it stays where it stops
    /// until its line sends it out.
    func spareStandingAside(in stuck: [TrainID: (candidate: Train, departs: Bool)], memo: inout DirectionMemo) -> Train? {
        guard isTrafficControlEnabled, !stuck.isEmpty else { return nil }
        for spare in trains where isSpare(spare) {
            guard let place = spare.placement else { continue }
            let own = held(spare)
            let waiting = stuck.keys.sorted().filter { network.fouls(own, routeEnvelope(of: stuck[$0]!.candidate).resources) }
            guard !waiting.isEmpty else { continue }
            let blocked = blockedTrack(except: spare.id, holders: trackHolders(memo: &memo))
            let starts = stationsBesideWholeTrain(spare.id).isEmpty ? [place] : [place, turnedRound(place)]
            var best: (train: Train, distance: Int64)?
            let targets = standingAsideTargets(for: spare)
            for start in starts {
                for target in targets {
                    guard let way = path(from: start.position, toStation: target.station, length: spare.length, avoiding: blocked, only: target.berth),
                          way.distance > 0, way.distance < best?.distance ?? .max
                    else { continue }
                    var moving = spare
                    moving.position = start.position
                    moving.trailEdges = start.trailEdges
                    follow(way, &moving)
                    guard case .granted(let granted) = reserving(moving, memo: &memo) else { continue }
                    // Standing there, it must let a train it held up go.
                    let there = placement(start, after: way)
                    var standing = spare
                    standing.position = there.position
                    standing.trailEdges = there.trailEdges
                    standing.movement.edges = []
                    standing.movement.cursor = 0
                    standing.movement.end = way.end
                    standing.reservation = []
                    let aside = replacing(standing)
                    let frees = waiting.contains { id in
                        let request = stuck[id]!
                        guard request.departs else {
                            return aside.holder(of: aside.envelopeCover(of: request.candidate), except: id, holders: aside.trackHolders(memo: &memo)) == nil
                        }
                        if case .granted = aside.reservingDeparture(request.candidate, memo: &memo) { return true }
                        return false
                    }
                    guard frees else { continue }
                    best = (granted, way.distance)
                }
            }
            if let best { return best.train }
        }
        return nil
    }

    // MARK: - Another berth

    /// Decision 278: a train following others (Stage U2) that can go no
    /// further, because a train without a service stands on the berth its
    /// route ends at, or on the way into it, as it arrives: the same train
    /// setting off along the shortest way to another berth of the same
    /// station, as a dispatcher sets the points for an empty platform; or
    /// `nil`. Of the trains following others in ascending ID order, the
    /// first with such a way: one that avoids what the trains without a
    /// service hold, ends at a berth no other train travelling to that
    /// station is bound for, borrows no track against another train's
    /// planned direction (decision 57, ``opposingServiceTraversals(for:memo:)``,
    /// but into a terminus, see ``terminusTraversals(along:to:)``), is at
    /// most ``detourAllowance`` longer than its route, and that it can take
    /// now, whole or following the trains ahead on it. The
    /// shortest such way, the berth first in the station's order on a tie.
    ///
    /// A train without a service stays until its line sends it out, so a
    /// train following another onto its berth would wait for it as long:
    /// in the high-speed demo with traffic control and block sections,
    /// seven sets ran out of Zuoying's depot towards the berth the first of
    /// them stopped on, and none of the eight ever moved again.
    func berthChange(memo: inout DirectionMemo) -> Train? {
        guard isTrafficControlEnabled else { return nil }
        let idle = Set(trains.lazy.filter { $0.execution == nil && $0.position != nil }.map(\.id))
        guard !idle.isEmpty else { return nil }
        for train in trains.sorted(by: { $0.id < $1.id }) {
            guard case .travellingToStop(let stop, let cycle)? = train.execution, train.movement.rate > 0,
                  let position = train.position, isFollowing(train, memo: &memo)
            else { continue }
            let step = travelling(train, distance: 1, memo: &memo)
            guard step.position == train.position, step.cursor == train.movement.cursor else { continue }
            let blocking = blockedTrack(except: train.id, among: idle, holders: trackHolders(memo: &memo))
            guard blocking.blocks(envelopeCover(of: train), in: network) else { continue }
            let station = train.timetable[stop].station
            // The berths the other trains on their way there will stand at.
            var taken: Set<TrackEdgeID> = []
            for other in trains where other.id != train.id {
                guard case .travellingToStop(let call, _)? = other.execution, other.timetable[call].station == station else { continue }
                if let last = other.movement.edges.last {
                    taken.insert(last)
                } else if case .onEdge(let traversal, _)? = other.position {
                    taken.insert(traversal.edge)
                }
            }
            let forbidden = opposingServiceTraversals(for: train, memo: &memo)
            let (limit, overflow) = routeLength(of: train).addingReportingOverflow(Self.detourAllowance)
            var best: (train: Train, distance: Int64)?
            for berth in berths(of: station, length: train.length) where !taken.contains(berth.traversal.edge) {
                guard let free = path(from: position, toStation: station, length: train.length, avoiding: blocking, only: berth),
                      let way = path(from: position, toStation: station, length: train.length, avoiding: blocking,
                                     forbidden: forbidden.subtracting(terminusTraversals(along: free, to: station)), only: berth),
                      way.distance > 0, overflow || way.distance <= limit, way.distance < best?.distance ?? .max,
                      case .granted(let granted) = reserving(rerouted(train, along: way, stop: stop, cycle: cycle), following: true, memo: &memo)
                else { continue }
                best = (granted, way.distance)
            }
            if let best { return best.train }
        }
        return nil
    }

    // MARK: - Turning back short

    /// `train`, a service of deadlock `stuck` (see ``deadlock(memo:)``)
    /// waiting at a stop, turned back short there (decision 255), or `nil`.
    /// Two lines sharing a single track with no passing place, one running
    /// on beyond the other's end: neither train can ever pass the other,
    /// so a service whose next calls lie past the other train can never
    /// make them. As a dispatcher turns such a train back where it is, it
    /// turns round there and waits at the next entry of its timetable for
    /// the same station, as if it had come back already, leaving out the
    /// calls between. Only a train standing beside that station's platform
    /// its whole length (as at a terminus), part way along its timetable,
    /// which comes back through the station after turning round on the
    /// way and calls somewhere after that, and only where
    /// it can then leave from there now and leaving lets another train of
    /// the deadlock go.
    func shortTurn(of train: Train, in stuck: [TrainID: (candidate: Train, departs: Bool)]) -> Train? {
        guard isTrafficControlEnabled, case .waitingAtStop(let stop, let cycle)? = train.execution,
              let place = train.placement
        else { return nil }
        let station = train.timetable[stop].station
        // Only part way along: turning at its first call for its last
        // would give up the whole trip, not leave out the calls it cannot
        // make.
        guard stop > 0, stationsBesideWholeTrain(train.id).contains(station),
              let back = train.timetable.indices.dropFirst(stop + 1).first(where: { train.timetable[$0].station == station }),
              back < train.timetable.count - 1,
              (stop + 1..<back).contains(where: { train.timetable[$0].reverses })
        else { return nil }
        var turned = train
        stand(&turned, at: turnedRound(place))
        turned.reservation = []
        turned.execution = .waitingAtStop(back, cycle: cycle)
        turned.times = ServiceTimes(arrival: clock.now, departure: clock.now)
        // Decision 288 (TestFlight 74.1): the calls left out take no time,
        // so the rest of the trip comes forward by the time they would
        // have taken; it leaves after its usual dwell, not standing there,
        // in the way, until the time it would have come back. The calls
        // left out are due now (its departure here is already past, so the
        // timetable stays in order). Never later, and only on a trip of its
        // own (a repeating timetable keeps its times).
        let now = clock.now
        let early = train.timetable[back].arrival.seconds - now.seconds
        if train.timetablePeriod == nil, early > 0 {
            for index in stop + 1..<turned.timetable.count {
                let call = turned.timetable[index]
                let left = index < back
                turned.timetable[index] = ScheduledStop(
                    station: call.station,
                    arrival: left ? now : GameTime(seconds: call.arrival.seconds - early),
                    departure: left ? now : GameTime(seconds: call.departure.seconds - early),
                    reverses: call.reverses
                )
            }
        }
        // Leaving from there now must let another train of the deadlock
        // go: the way it leaves by is free, and with it gone the others
        // are no longer stuck.
        let there = replacing(turned)
        var memo = DirectionMemo()
        guard let leaving = there.leaving(turned, stop: back, cycle: cycle).train, case .travellingToStop? = leaving.execution,
              case .granted(let granted) = there.reservingDeparture(leaving, memo: &memo)
        else { return nil }
        // Moving, it is waited for by nobody in a deadlock.
        let gone = there.replacing(granted)
        var after = DirectionMemo()
        let left = gone.deadlock(memo: &after)
        guard stuck.keys.contains(where: { $0 != train.id && left[$0] == nil }) else { return nil }
        return turned
    }
}
