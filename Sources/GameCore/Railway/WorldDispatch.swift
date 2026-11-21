// The world in time (decision 910, cut 3): sending trains out: the dispatcher, lines' runs, services going on.
// Moved from GameWorld.swift unchanged.

extension GameWorld {
    /// Phase 0 of a basic step: each line, in ascending ID order, and on it
    /// each service, its own first and then its patterns in order, sends
    /// out at most one of its trains (see ``advance(ticks:)``). Its service
    /// starts at the first call as if it had just arrived there (Stage
    /// W2b): it dwells there, and leaves when its doors have closed.
    /// Returns whether any was sent out.
    ///
    /// Under traffic control (Stage T) the train is sent out only when it
    /// could take its route now (see ``readyTrain(of:_:memo:)``); it takes
    /// it when it leaves, and waits for it like any service if another
    /// train has taken some of it meanwhile.
    ///
    /// A ring (decision 49) sends its trains out each way on its own: each
    /// way is a stream (see ``ServiceLine/dispatchStreams``), the streams
    /// taken inner way first.
    mutating func dispatchTrains(memo: inout DispatchMemo) -> Bool {
        let now = clock.now
        var dispatched = false
        // Decision 878 (TICK-REAL): the holders the due runs' trains are
        // asked of, worked out at this second and changed as trains are
        // sent out, apart from the step's (see
        // ``DirectionMemo/exchangeHolders(with:)``).
        var runHolders = DirectionMemo.HolderStore()
        for index in lines.indices {
            // Decision 133: a line with runs sends its trains out at the
            // runs' times instead.
            if lines[index].hasRuns {
                memo.directions.exchangeHolders(with: &runHolders)
                let sent = dispatchRuns(ofLine: index, memo: &memo.directions)
                memo.directions.exchangeHolders(with: &runHolders)
                if sent { dispatched = true }
                // Decision 221: out of a depot in time for a run, or into
                // one when no run wants the train for a while.
                let line = lines[index]
                if let (ready, trip) = runTrainLeavingDepot(of: line, memo: &memo) ?? runTrainEnteringDepot(of: line, memo: &memo),
                   let timetable = trip.timetable(calling: line.stops, sentOutAt: now) {
                    trains[ready].trafficVisits = []
                    trains[ready].timetable = timetable
                    trains[ready].timetablePeriod = nil
                    trains[ready].execution = .waitingAtStop(0)
                    trains[ready].isDeadheading = true
                    trains[ready].isStandingAside = false
                    trains[ready].times = ServiceTimes(arrival: now)
                    logArrival(of: ready)
                    dispatched = true
                }
                continue
            }
            // Decision 309: a line keeping a clock at each end may send a
            // train out from each in the same step.
            let streams = lines[index].dispatchStreams.flatMap { stream in
                keepsEndClocks(lines[index], stream, at: now, memo: &memo) ? [stream, stream] : [stream]
            }
            for stream in streams where !lines[index].trains(of: stream).isEmpty {
                let line = lines[index]
                // Decision 172: a train that stands where the line does not
                // send trains out from runs empty to the nearer end; it
                // takes no headway slot.
                var sending: (index: Int, trip: LineTrip, deadhead: Bool)?
                if let (ready, trip) = dueTrain(of: line, stream, at: now, memo: &memo) {
                    sending = (ready, trip, false)
                } else if isDispatchDue(line, stream, at: now, deadhead: true, memo: &memo),
                          let (ready, trip) = readyTrain(of: line, stream, deadhead: true, memo: &memo) {
                    sending = (ready, trip, true)
                } else if let (ready, trip) = trainToFarEnd(of: line, stream, at: now, memo: &memo) {
                    // Decision 309: to the last stop, which sends its own
                    // trains out.
                    sending = (ready, trip, true)
                } else if let (ready, trip) = trainLeavingDepot(of: line, stream, memo: &memo) ?? trainEnteringDepot(of: line, stream, memo: &memo) {
                    // Decision 209: out of the depot in time for a trip, or
                    // into it when the line no longer needs the train.
                    sending = (ready, trip, true)
                }
                guard let (ready, trip, deadhead) = sending,
                      let timetable = trip.timetable(calling: line.stops, sentOutAt: now)
                else { continue }
                trains[ready].trafficVisits = []
                trains[ready].timetable = timetable
                trains[ready].timetablePeriod = nil
                trains[ready].execution = .waitingAtStop(0)
                trains[ready].isDeadheading = deadhead
                trains[ready].isStandingAside = false
                // Stage W2b: the train is sent out as if it had just
                // arrived at the first call; it dwells there first.
                trains[ready].times = ServiceTimes(arrival: now)
                logArrival(of: ready)
                if !deadhead { recordDispatch(ofLine: index, stream, from: trip.fromLastCall ? .last : .first, at: now, memo: &memo) }
                dispatched = true
            }
        }
        return dispatched
    }

    /// Records that line `index`'s `stream` sent a train out from `end` at
    /// `now`: the stream's dispatch, or under
    /// ``DispatchPattern/fromBothEnds`` the end's; staggered, whether it
    /// opened a pair (it does unless the pair is open and the second train
    /// leaves within two headways of the first).
    mutating func recordDispatch(ofLine index: Int, _ stream: DispatchStream, from end: DispatchEnd, at now: GameTime, memo: inout DispatchMemo) {
        let line = lines[index]
        let pattern = plannedService(of: line, stream.service, at: now, memo: &memo).map { planned in
            (dispatchPattern(of: line, stream, planned: planned), planned.headway)
        }
        switch pattern {
        case (.fromBothEnds, _)? where end == .last:
            lines[index].endLastDispatch = now
        case (.staggered, let headway)?:
            let closes = line.opensPair && line.lastDispatch.flatMap { Self.time($0, plusMinutes: 2 * headway) }.map { now < $0 } == true
            lines[index].opensPair = !closes
            lines[index].recordDispatch(of: stream, at: now)
        default:
            lines[index].recordDispatch(of: stream, at: now)
        }
    }

    /// Sends out a train for each run of line `index` due now that has one
    /// ready (decision 133), earliest first. Returns whether any was sent.
    mutating func dispatchRuns(ofLine index: Int) -> Bool {
        var memo = DirectionMemo()
        return dispatchRuns(ofLine: index, memo: &memo)
    }

    /// ``dispatchRuns(ofLine:)`` with what the runs' trains are asked kept
    /// in `memo` (decision 878, see ``readyRunTrain(of:_:day:memo:)``),
    /// whose holders are of this second.
    mutating func dispatchRuns(ofLine index: Int, memo: inout DirectionMemo) -> Bool {
        var dispatched = false
        for (run, day) in lines[index].dueRuns(at: clock.now) {
            guard let (ready, timetable) = readyRunTrain(of: lines[index], lines[index].runs[run], day: day, memo: &memo) else { continue }
            trains[ready].trafficVisits = []
            trains[ready].timetable = timetable
            trains[ready].timetablePeriod = nil
            trains[ready].execution = .waitingAtStop(0)
            trains[ready].isStandingAside = false
            trains[ready].times = ServiceTimes(arrival: clock.now)
            logArrival(of: ready)
            lines[index].runDays[run] = day
            dispatched = true
        }
        return dispatched
    }

    /// Whether `line`'s `stream` sends a train out at `now` if one is
    /// ready: not before second 0; the line's window is open and the
    /// stream's service runs trains then (see
    /// ``plannedService(of:_:at:memo:)``); a headway of that level has
    /// passed since the stream's last dispatch; and fewer of its trains
    /// run a service than it runs then: on a ring each way runs half the
    /// trains (decision 49), at the ring's headway, which is each way's.
    ///
    /// With `deadhead` (decision 172) it asks only whether the stream has
    /// room for one more train now, as an empty run to an end takes no
    /// headway slot.
    ///
    /// Decision 309: the line's dispatch pattern decides when its next
    /// train is due, for a train sent out from `end` (see
    /// ``nextDispatch(of:_:from:planned:)``); even, as every line before
    /// it, the end does not matter.
    func isDispatchDue(_ line: ServiceLine, _ stream: DispatchStream, at now: GameTime, deadhead: Bool = false, from end: DispatchEnd = .first, memo: inout DispatchMemo) -> Bool {
        guard now.seconds >= 0, !line.hasRuns, let planned = plannedService(of: line, stream.service, at: now, memo: &memo) else { return false }
        if !deadhead, let due = nextDispatch(of: line, stream, from: end, planned: planned) {
            guard due <= now else { return false }
        }
        // Decision 209: a train running empty to the depot is out of
        // service.
        return runningTrains(of: line, stream) < (stream.direction == nil ? planned.trains : planned.trains / 2)
    }

    /// The train of `line`'s `stream` to send out on a trip now, with that
    /// trip, or `nil`: the first ready (see ``readyTrain(of:_:deadhead:from:memo:)``)
    /// once the stream is due (see ``isDispatchDue(_:_:at:deadhead:from:memo:)``).
    /// Decision 309: a line keeping a clock at each end sends the first
    /// ready at an end that is due.
    private func dueTrain(of line: ServiceLine, _ stream: DispatchStream, at now: GameTime, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard keepsEndClocks(line, stream, at: now, memo: &memo) else {
            guard isDispatchDue(line, stream, at: now, memo: &memo) else { return nil }
            return readyTrain(of: line, stream, memo: &memo)
        }
        for end in [DispatchEnd.first, .last] where isDispatchDue(line, stream, at: now, from: end, memo: &memo) {
            if let ready = readyTrain(of: line, stream, from: end, memo: &memo) { return ready }
        }
        return nil
    }

    /// The trains `line`'s service `service` runs at `now` and the headway
    /// between them, beside the services before it (see
    /// ``ServiceLine/services(at:roundTrips:)``), or `nil` when the line's
    /// window is closed, or the service runs none then or its journey
    /// cannot be driven.
    func plannedService(of line: ServiceLine, _ service: Int, at now: GameTime, memo: inout DispatchMemo) -> (trains: Int, headway: Int64)? {
        guard line.window.contains(minuteOfDay: now.minuteOfDay) else { return nil }
        var roundTrips: [Int64?] = []
        var capacities: [ServiceCapacityProfile?] = []
        let layout: LineCapacityLayout
        if let known = memo.capacityLayouts[line.id] { layout = known }
        else {
            layout = capacityLayout(of: line)
            memo.capacityLayouts[line.id] = layout
        }
        for earlier in 0...service {
            let journey: LineJourney?
            if let known = memo.journeys[line.id]?[earlier] {
                journey = known
            } else {
                journey = self.journey(of: line, service: earlier)
                memo.journeys[line.id, default: [:]][earlier] = journey
            }
            roundTrips.append(journey?.roundTripMinutes)
            if let known = memo.capacities[line.id]?[earlier] { capacities.append(known) }
            else {
                var outer: LineJourney?
                if line.isRing, !layout.blocks.isEmpty {
                    if let known = memo.outerCapacityJourneys[line.id] { outer = known }
                    else {
                        outer = self.journey(of: line, service: earlier, direction: .outer)
                        memo.outerCapacityJourneys[line.id] = .some(outer)
                    }
                }
                let profile = layout.blocks.isEmpty ? nil : journey.map {
                    capacityProfile(of: line, service: earlier, journey: $0, layout: layout, outer: outer)
                }
                memo.capacities[line.id, default: [:]][earlier] = .some(profile)
                capacities.append(profile)
            }
        }
        guard roundTrips[service] != nil else { return nil }
        return line.services(at: serviceDay.level(atMinuteOfDay: now.minuteOfDay), roundTrips: roundTrips, capacities: capacities).plans[service]
    }

    /// The first of the trains of `line`'s service `service`, in ID order,
    /// that it can send out: one without a service, placed, with a rate
    /// above 0, stopped at the first call's station, and able to drive the
    /// whole round trip from there (see ``trip(of:service:for:)``); with
    /// its index and that trip. Under traffic control (Stage T) it must
    /// also be able to take the route of its first departure now; one whose
    /// default and alternative routes cannot be taken is not ready, and
    /// tries again at the next step.
    ///
    /// With `end` (decision 309) only a train sent out from that end counts.
    private func readyTrain(of line: ServiceLine, _ stream: DispatchStream, deadhead: Bool = false, from end: DispatchEnd? = nil, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        for id in line.trains(of: stream) {
            guard let index = trains.firstIndex(where: { $0.id == id }),
                  let trip = readyTrip(of: trains[index], on: line, stream.service, memo: &memo),
                  (trip.deadhead != nil) == deadhead, end.map({ ($0 == .last) == trip.fromLastCall }) ?? true
            else { continue }
            if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
               case .held = reservingDeparture(leaving, memo: &memo.directions) {
                continue
            }
            return (index, trip)
        }
        return nil
    }

    /// The round trip `line`'s service `service` would send `train` on now,
    /// without traffic control: `nil` unless the train has no service, is
    /// placed, has a rate above 0, is stopped at the service's first call
    /// and can drive the whole round trip from there (see
    /// ``trip(of:service:for:)``). Each trip is looked up once per call of
    /// ``advance(ticks:)`` for where the train stands.
    func readyTrip(of train: Train, on line: ServiceLine, _ service: Int, memo: inout DispatchMemo) -> LineTrip? {
        guard train.execution == nil, let placement = train.placement, train.movement.rate > 0 else { return nil }
        if let known = memo.trips[train.id], known.from == placement { return known.trip }
        let calls = line.calls(ofService: service)
        // Decision 172: a train goes out from either end of the service, on
        // a ring from any of its stops; one stopped anywhere else runs
        // empty to the nearer end first (see ``LineTrip/deadhead``).
        let trip: LineTrip?
        if isInDepot(train, of: line) {
            // Decision 209: the line sends it out of its depot in time for
            // a trip (``trainLeavingDepot(of:_:memo:)``).
            trip = nil
        } else if isStopped(train, at: line.stops[calls[0]]) {
            trip = self.trip(of: line, service: service, for: train)
        } else if !flexDispatch {
            // Decision 58, a later fix (decision 209): without flexible
            // dispatch, a train moved out of the way of a deadlock
            // (``spareStandingAside(in:memo:)``) runs empty back to the
            // first call once the line has room for it.
            // Decision 209: so does a train left in a depot not its line's.
            trip = train.isStandingAside || standsInADepot(train) ? deadheadTrip(of: line, service: service, for: train, toFirstCallOnly: true) : nil
        } else if line.isRing, let stop = line.stops.indices.first(where: { isStopped(train, at: line.stops[$0]) }) {
            trip = self.trip(of: line, service: service, for: train, from: .ringStop(stop))
        } else if !line.isRing, isStopped(train, at: line.stops[calls[calls.count - 1]]) {
            trip = self.trip(of: line, service: service, for: train, from: .last).map { trip in
                var fromLast = trip
                fromLast.fromLastCall = true
                return fromLast
            }
        } else {
            trip = deadheadTrip(of: line, service: service, for: train)
        }
        memo.trips[train.id] = (placement, trip)
        return trip
    }

    /// Adds `distance` world units to the empty running of the line train
    /// `id` is assigned to (decision 172).
    mutating func countDeadhead(_ distance: Int64, of id: TrainID) {
        guard let line = lines.firstIndex(where: { $0.assignedTrains.contains(id) }) else { return }
        let (total, overflow) = lines[line].deadheadDistance.addingReportingOverflow(distance)
        lines[line].deadheadDistance = overflow ? .max : total
        countLineDeadhead(distance, on: lines[line].id)
    }

    /// `train` sent out now on `trip` (calling at the line's `stops`), as
    /// it would be once it has left the first call: turned round first if
    /// the trip says so, on its way along the first leg. `nil` if the
    /// trip's times would not fit.
    func firstDeparture(of train: Train, on trip: LineTrip, calling stops: [StationID]) -> Train? {
        guard let timetable = trip.timetable(calling: stops, sentOutAt: clock.now) else { return nil }
        var sent = train
        sent.timetable = timetable
        sent.timetablePeriod = nil
        sent.execution = .waitingAtStop(0)
        sent.times = ServiceTimes(arrival: clock.now)
        return leaving(sent, stop: 0, cycle: 0).train
    }

    /// The whole minutes from now, the start of a minute, until the first
    /// minute, at or after now, at which some service might send a train
    /// out, or `nil` if none can in this call.
    ///
    /// Only a service with a train ready counts: a train becomes ready only
    /// by arriving or finishing a service, which is a change, so after a
    /// step that changed nothing no other service can send one out before
    /// the next command. For such a service the answer is now if it is due
    /// now; otherwise the first of minute 0, the minute a headway since its
    /// last dispatch has passed, and the next minute its line's window
    /// opens or closes or the day's level changes. Until then nothing that
    /// decides whether it is due can change (what the services before it
    /// run changes only at those same minutes), so this is exact. A gap too
    /// large for an `Int64` is given as `Int64.max`.
    func minutesUntilNextDispatch(memo: inout DispatchMemo) -> Int64? {
        let now = clock.now
        var soonest: Int64?
        for line in lines {
            // Decision 133: now if a run is due with a train ready, else
            // when a run next starts or stops being due (a train becomes
            // ready only by a change, as below).
            if line.hasRuns {
                guard !line.trains.isEmpty else { continue }
                let wake = hasReadyRun(line) ? now : line.nextRunChange(after: now)
                if let wake { soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake)) }
                // Decision 556, continued (TYMCLIST7): a train held from a
                // due run joins a deadlock once the run starts (decision
                // 570), which the dispatcher may then put it on its run to
                // clear (see ``runTrainPutOnItsRun(in:memo:)``).
                if let start = heldRunStart(of: line) { soonest = min(soonest ?? .max, Self.minutes(from: now, until: start)) }
                // Decision 221: a train into or out of a depot.
                if let minutes = minutesUntilRunDepotMove(of: line, memo: &memo) {
                    soonest = min(soonest ?? .max, minutes)
                }
                continue
            }
            for stream in line.dispatchStreams where !line.trains(of: stream).isEmpty {
                // Decision 209: a train into or out of the depot.
                if let minutes = minutesUntilDepotMove(of: line, stream, memo: &memo) {
                    soonest = min(soonest ?? .max, minutes)
                }
                // Decision 172: a train that runs empty to an end goes as
                // soon as the stream has room for it.
                if readyTrain(of: line, stream, deadhead: true, memo: &memo) != nil {
                    let wake = now.seconds < 0 ? GameTime.zero
                        : isDispatchDue(line, stream, at: now, deadhead: true, memo: &memo) ? now
                        : line.nextChange(after: now, in: serviceDay)
                    if let wake { soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake)) }
                }
                // Decision 309: a train to the last stop, which sends its
                // own trains out, goes as soon as the stream has room.
                if trainToFarEnd(of: line, stream, at: now, memo: &memo) != nil {
                    soonest = min(soonest ?? .max, 0)
                }
                // Decision 309: each end that keeps its own clock is woken
                // for on its own.
                let ends: [DispatchEnd?] = keepsEndClocks(line, stream, at: now, memo: &memo) ? [.first, .last] : [nil]
                for end in ends {
                    guard readyTrain(of: line, stream, from: end, memo: &memo) != nil else { continue }
                    var wake: GameTime?
                    if now.seconds < 0 {
                        wake = .zero
                    } else if isDispatchDue(line, stream, at: now, from: end ?? .first, memo: &memo) {
                        wake = now
                    } else {
                        wake = line.nextChange(after: now, in: serviceDay)
                        if let planned = plannedService(of: line, stream.service, at: now, memo: &memo),
                           let due = nextDispatch(of: line, stream, from: end ?? .first, planned: planned), due > now {
                            wake = min(wake ?? due, due)
                        }
                    }
                    guard let wake else { continue }
                    soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake))
                }
            }
        }
        return soonest
    }

    /// Stage V2: the whole minutes from now, the start of a minute, until
    /// the first minute at or after now at which a line's service with a
    /// train that only its route keeps from being ready (see
    /// ``readyTrain(of:_:memo:)``) starts or stops being due to send it out,
    /// or `nil` if there is none. Such a train waits for its route while
    /// the line is due (see ``trainHoldingRoute(of:)``), so it may complete
    /// a deadlock, and the dispatcher looks only at whole minutes: an idle
    /// stretch must not skip the minute it starts or stops waiting. The
    /// minutes are those of ``minutesUntilNextDispatch(memo:)``.
    func minutesUntilLineWaitsChange(memo: inout DispatchMemo) -> Int64? {
        guard isTrafficControlEnabled else { return nil }
        let now = clock.now
        var soonest: Int64?
        for line in lines {
            // Decision 133: a run's train waits for its route while the run
            // is due.
            if line.hasRuns {
                if hasRunWaitingForRoute(line), let wake = line.nextRunChange(after: now) {
                    soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake))
                }
                continue
            }
            for stream in line.dispatchStreams where !line.trains(of: stream).isEmpty {
                let waits = line.trains(of: stream).contains { id in
                    guard let train = train(id: id) else { return false }
                    return readyTrip(of: train, on: line, stream.service, memo: &memo).map { $0.deadhead == nil } ?? false
                }
                guard waits, readyTrain(of: line, stream, memo: &memo) == nil else { continue }
                var wake: GameTime?
                if now.seconds < 0 {
                    wake = .zero
                } else {
                    wake = line.nextChange(after: now, in: serviceDay)
                    // Decision 309: each end's clock, under a pattern that
                    // keeps one at each.
                    let ends: [DispatchEnd] = keepsEndClocks(line, stream, at: now, memo: &memo) ? [.first, .last] : [.first]
                    for end in ends {
                        if !isDispatchDue(line, stream, at: now, from: end, memo: &memo),
                           let planned = plannedService(of: line, stream.service, at: now, memo: &memo),
                           let due = nextDispatch(of: line, stream, from: end, planned: planned), due > now {
                            wake = min(wake ?? due, due)
                        }
                    }
                }
                guard let wake else { continue }
                soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake))
            }
        }
        return soonest
    }

    /// The services' phase of a basic step (Stage W2b): every train whose
    /// service waits at a stop, in ascending ID order, moves its dwell on
    /// (see ``stepDwell(_:at:memo:)``) and then leaves if its departure is due
    /// (see ``departService(_:at:unroutable:held:)``); every train whose service
    /// travels and was held up on its run sets off again if it can (Stage
    /// W2c, see ``resumeRun(_:at:)``). Returns whether any service changed.
    mutating func runServices(at now: GameTime, unroutable: inout Set<TrainID>, held: inout [HeldRoute], turningAside: inout Bool,
                                      memo: inout DispatchMemo) -> Bool {
        var changed = false
        // Decision 228: where trains stand as the phase begins (a train only
        // leaves them in it).
        let standing = standingEdges()
        // Decision 283: and where trains travel.
        let moving = movingEdges()
        for index in trains.indices where trains[index].execution != nil {
            if stepDwell(index, at: now, memo: &memo) {
                changed = true
            }
            if departService(index, at: now, unroutable: &unroutable, held: &held, memo: &memo) {
                changed = true
            }
            // Decision 228: to a free platform, when a train stands on its
            // own (decision 283: or comes out along its track towards it).
            // Its run is kept: a longer way ends with a short run from a
            // stand.
            // Decision 379: the train as a local, not `trains[index]` as an
            // argument, which copied the whole world for each call.
            let train = trains[index]
            if let path = freePlatformOnTheWay(of: train, standing: standing, moving: moving, memo: &memo.directions.paths) {
                follow(path, &trains[index])
                changed = true
            }
            // Decision 542: into a siding of a station ahead, for an
            // overtake planned after it set off; or, past a train standing
            // aside for it there, onto the straight track. Its run is kept,
            // as above. The train as it is now, on the way it may just
            // have been given.
            let plan = trafficPlan(memo: &memo.directions)
            let current = trains[index]
            switch standingAsideOnTheWay(current, plan: plan, memo: &memo.directions) ?? keepingStraightOnTheWay(current, plan: plan, memo: &memo.directions) {
            case .granted(let turned)?:
                trains[index] = turned
                changed = true
            case .held?:
                turningAside = true
            case nil:
                break
            }
            if resumeRun(index, at: now) {
                changed = true
            }
            if goOn(index, held: &held, memo: &memo) {
                changed = true
            }
        }
        return changed
    }

    /// Stage V2 (ARCHITECTURE decision 58): train `index`'s service,
    /// stopped at a passing place on its way (see ``isAtPassingPlace(_:)``),
    /// sets off again for its call once it can take the route there as a
    /// departure does (see ``reservingDeparture(_:)``): whole, following
    /// the trains ahead, or to another berth of the call's station. It is
    /// off its timetable, so it runs as fast as it can. Otherwise it waits
    /// there, and the route it waits for joins `held`. Without traffic
    /// control it always can. Returns whether the service changed.
    ///
    /// Stage V3 (decision 59): a train held by a scheduled wait stays; one
    /// whose scheduled way on (see ``scheduledPath(for:from:to:plan:memo:)``)
    /// it can take whole now takes it, on the scheduled run. Otherwise it
    /// goes on exactly as above.
    private mutating func goOn(_ index: Int, held: inout [HeldRoute], memo: inout DispatchMemo) -> Bool {
        let plan = trafficPlan(memo: &memo.directions)
        // Decision 379: the train as a local, not `trains[index]` as an
        // argument, which copied the whole world for each call.
        let train = trains[index]
        guard currentTrafficWait(train, plan: plan, memo: &memo.directions) == nil,
              let going = goingOn(train) else { return false }
        // The whole routes tried before the default one and held: a step
        // ends when one frees, as for the default one (decision 55).
        var whole: [Train] = []
        if let chosen = scheduledPath(for: train, from: train.position!, to: train.timetable[train.execution!.stop].station, plan: plan, memo: &memo.directions.paths) {
            var scheduled = going
            follow(chosen.path, &scheduled)
            let plannedRun = run(of: scheduled, length: chosen.path.distance, scheduled: chosen.seconds)
            scheduled.times?.run = plannedRun
            if case .granted(let granted) = reserving(scheduled, following: blockSections, memo: &memo.directions) {
                setOff(index, as: granted)
                return true
            }
            whole.append(scheduled)
        }
        if let preferred = preferredGoingOn(train) {
            if case .granted(let granted) = reserving(preferred, following: blockSections, memo: &memo.directions) {
                setOff(index, as: granted)
                return true
            }
            whole.append(preferred)
        }
        switch reservingDeparture(going, memo: &memo.directions) {
        case .granted(var granted):
            let fastest = run(of: granted, length: routeLength(of: granted))
            granted.times?.run = fastest
            setOff(index, as: granted)
            return true
        case .held:
            held.append(HeldRoute(candidate: going, whole: whole))
            return false
        }
    }

    /// Train `index` set off as `train`, its traffic visits (decision 59)
    /// kept, with its departure from where it stands.
    mutating func setOff(_ index: Int, as train: Train) {
        recordTrafficDeparture(index)
        let left: Int? = if case .waitingAtStop(let stop, _)? = trains[index].execution { stop } else { nil }
        var departed = train
        departed.trafficVisits = trains[index].trafficVisits
        trains[index] = departed
        // Decision 756: not before the switches of its route lie its way.
        if let thrown = runAfterThrowingSwitches(of: trains[index]) { trains[index].times?.run = thrown }
        // Decision 223: the trip log notes the departure, and the call it
        // makes at once when it was already at the next one's station.
        if let left {
            logDeparture(of: train.id, from: train.timetable[left].station)
            if case .waitingAtStop? = train.execution { logArrival(of: index) }
        }
    }

    /// Decision 278: once a minute, after the dispatcher's deadlock phase
    /// has done nothing, a train following others that a train without a
    /// service keeps from its berth changes to another berth of the same
    /// station (see ``berthChange(memo:)``). Returns the train's ID, or
    /// `nil`.
    mutating func changeBerth(memo: inout DispatchMemo) -> TrainID? {
        guard let changed = berthChange(memo: &memo), let index = trains.firstIndex(where: { $0.id == changed.id }) else { return nil }
        trains[index] = changed
        return changed.id
    }

    /// Decision 666: once a minute, after the dispatcher's deadlock phase
    /// and decision 278's change of berth have done nothing, a train of a
    /// line with runs, between them, that its line would send into a depot
    /// but for its way there, and that stands in the way of a train waiting
    /// for its route, steps aside (see ``depotBoundMakingWay(memo:)``). On
    /// the Taoyuan Airport MRT under the simple rules with traffic
    /// control, a train out of Luzhu depot came to the National Taiwan
    /// Sport University too late for its run and stood on the platform
    /// towards Taipei, facing it: its way back to the depot went on to
    /// Taipei and back, never free at once, and the services behind it
    /// bound for that platform waited for it all day. It goes as an empty
    /// run of its line does (decision 172), as fast as it can, not at the
    /// crawl of a train without a service: a long way held at a crawl held
    /// up the services behind it. Returns the train's ID, or `nil`.
    mutating func makeWayForDepot(memo: inout DispatchMemo) -> TrainID? {
        guard let (aside, station, distance) = depotBoundMakingWay(memo: &memo),
              let index = trains.firstIndex(where: { $0.id == aside.id }),
              let here = stationsStoppedAt(by: aside.id).first
        else { return nil }
        let now = clock.now
        var moved = aside
        let run = run(of: moved, length: distance)
        let seconds = run?.seconds ?? 0
        moved.trafficVisits = []
        moved.timetable = [
            ScheduledStop(station: here, arrival: now, departure: now),
            ScheduledStop(station: station, arrival: GameTime(seconds: now.seconds + seconds), departure: GameTime(seconds: now.seconds + seconds)),
        ]
        moved.timetablePeriod = nil
        moved.execution = .travellingToStop(1, cycle: 0)
        moved.isDeadheading = true
        moved.isStandingAside = false
        moved.times = ServiceTimes(arrival: now, departure: now, run: run)
        trains[index] = moved
        countDeadhead(distance, of: aside.id)
        return aside.id
    }

    /// Whether a train without a service may be due to be sent out by its
    /// line now: a due run would send it (decision 133), or its stream has
    /// room for one more train (``isDispatchDue(_:_:at:deadhead:memo:)``
    /// asked as for an empty run, which a headway does not hold back). A
    /// cheap first look: ``departureRequest(of:memo:)`` says for sure.
    ///
    /// Each train's line (the first that has it, as
    /// ``assignedLine(of:)``) and stream are looked up once, and each
    /// stream asked once: the world does not change while asked, and a
    /// stream's trains all get the same answer.
    func anyTrainMayBeSentOut(memo: inout DispatchMemo) -> Bool {
        var lineOf: [TrainID: Int] = [:]
        for (index, line) in lines.enumerated() {
            for service in 0..<line.serviceCount {
                for id in line.trains(ofService: service) where lineOf[id] == nil {
                    lineOf[id] = index
                }
            }
        }
        var streams: [Int: [TrainID: DispatchStream]] = [:]
        var due: [Int: [DispatchStream: Bool]] = [:]
        for train in trains where train.execution == nil {
            guard let index = lineOf[train.id] else { continue }
            let line = lines[index]
            if line.hasRuns {
                if dueRunDeparture(of: train, on: line, memo: &memo.directions) != nil { return true }
                continue
            }
            if streams[index] == nil {
                var of: [TrainID: DispatchStream] = [:]
                for stream in line.dispatchStreams {
                    for id in line.trains(of: stream) where of[id] == nil {
                        of[id] = stream
                    }
                }
                streams[index] = of
            }
            guard let stream = streams[index]?[train.id] else { continue }
            if due[index]?[stream] == nil {
                due[index, default: [:]][stream] = isDispatchDue(line, stream, at: clock.now, deadhead: true, memo: &memo)
            }
            if due[index]?[stream] == true { return true }
        }
        return false
    }

    /// This world with `train` in place of the train of its ID: for asking
    /// what would follow from it (Stage V2), never committed.
    func replacing(_ train: Train) -> GameWorld {
        var world = self
        if let index = world.trains.firstIndex(where: { $0.id == train.id }) {
            world.trains[index] = train
        }
        return world
    }

    /// Moves on the dwell of train `index`, if its service waits at a stop
    /// (see ``ServiceTimes``), and returns whether it changed:
    ///
    /// - once its doors have opened, the passengers for that stop get off
    ///   and those waiting for the train get on (see
    ///   ``exchangePassengers(_:at:memo:)``), taking as long as the larger
    ///   number does (see ``Train/exchangeSeconds(_:crowd:)``), and longer in
    ///   a crowd at its doors when door crowding is on (decision 169, see
    ///   ``DoorCrowding``), the crowd taken when the doors have opened;
    /// - while its doors stay open, at each whole minute, when new
    ///   passengers have come, they get on too, after those still getting
    ///   on;
    /// - its doors start closing once the exchange is over, its least dwell
    ///   will be over when they have closed, and (when it is early) they
    ///   close for its scheduled departure: at the latest of
    ///   ``closingStart(of:stop:cycle:)``.
    private mutating func stepDwell(_ index: Int, at now: GameTime, memo: inout DispatchMemo) -> Bool {
        guard case .waitingAtStop(let stop, let cycle)? = trains[index].execution, var times = trains[index].times else { return false }
        var changed = false
        if let end = times.exchangeEnd {
            if times.closing == nil, now.isWholeMinute {
                // Decision 169: the crowd is taken before those who come
                // get on.
                // Decision 379: locals, not `trains[index]` as arguments,
                // which copied the whole world for each call.
                let train = trains[index]
                let crowd = doorCrowd(of: train.id, at: train.timetable[stop].station)
                let boarded = boardPassengers(trains[index], at: stop)
                if boarded > 0 {
                    times.exchangeEnd = Self.saturating(max(end, now), plus: trains[index].exchangeSeconds(boarded, crowd: crowd))
                    changed = true
                }
            }
        } else {
            guard now >= Self.saturating(times.arrival, plus: ServiceDwell.doorOpening) else { return false }
            // Decision 169: the crowd at the doors as they have opened,
            // before anyone gets off or on.
            let train = trains[index]
            let crowd = doorCrowd(of: train.id, at: train.timetable[stop].station)
            let busy = exchangePassengers(index, at: stop, memo: &memo)
            times.exchangeEnd = Self.saturating(now, plus: trains[index].exchangeSeconds(busy, crowd: crowd))
            changed = true
        }
        if times.closing == nil, let start = closingStart(of: trains[index], stop: stop, cycle: cycle, times: times, known: &memo.directions.paths.trainLines), now >= start {
            times.closing = now
            changed = true
        }
        trains[index].times = times
        return changed
    }

    /// Train `index`'s service, travelling to a stop, after it was held up
    /// on its run (Stage W2c; see ``dropRunsHeldUp(endingAt:memo:)``): a train
    /// without a run sets off on a new one (see
    /// ``run(of:length:scheduled:)``), in the least whole second its
    /// performance builds a curve for, over the way left to the end of its
    /// route, when all of these hold:
    ///
    /// - its rate is above 0 (a rate of 0 holds it);
    /// - it has way left (see ``routeStretches(of:)``); and
    /// - it can move now: the track lets it go on at least one unit.
    ///
    /// It was stopped, so it starts again from a stand, as fast as it can
    /// (the references only sample timetables and have no rule for this).
    /// A run that is over before the train arrived (which only a train held
    /// up has, and it drops it at once) is dropped first. Returns whether
    /// the service changed.
    private mutating func resumeRun(_ index: Int, at now: GameTime) -> Bool {
        guard case .travellingToStop? = trains[index].execution, var times = trains[index].times else { return false }
        var changed = false
        if let run = times.run {
            guard run.end <= now else { return false }
            times.run = nil
            changed = true
        }
        let train = trains[index]
        let route = routeStretches(of: train)
        if train.movement.rate > 0, route.moves {
            let step = travelling(train, distance: 1)
            if step.position != train.position || step.cursor != train.movement.cursor {
                var left: Int64 = 0
                for stretch in route.stretches {
                    let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
                    left = overflow ? .max : sum
                }
                // Decision 207: with realistic operation, fitted to the time
                // left to its scheduled arrival; otherwise as fast as it can.
                var scheduled: Int64?
                if realisticOperation, case .travellingToStop(let stop, let cycle)? = train.execution {
                    scheduled = secondsToScheduledArrival(of: train, stop: stop, cycle: cycle)
                }
                if let run = run(of: train, length: left, scheduled: scheduled) {
                    times.run = run
                    changed = true
                }
            }
        }
        trains[index].times = times
        return changed
    }
}
