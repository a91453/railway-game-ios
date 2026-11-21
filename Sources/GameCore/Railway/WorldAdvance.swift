// The world in time (decision 910, cut 3): time: pausing, the speed, and each step of `advance`.
// Moved from GameWorld.swift unchanged.

extension GameWorld {
    // MARK: - Time

    public mutating func pause() {
        clock.pause()
    }

    public mutating func resume() {
        clock.resume()
    }

    public mutating func setSpeed(_ speed: GameSpeed) {
        clock.setSpeed(speed)
    }

    /// How many destinations each origin sends passengers to in the plan
    /// of the day that ends at midnight `now`: `release`'s, worked out at
    /// `time`, unless that is `now` itself (a call that starts at
    /// midnight, or a service level that changes there, works out the new
    /// day's plan first). Then the plan is the one as at the day's last
    /// second, as a call across midnight has it, so a day's
    /// growth does not depend on where calls of ``advance(ticks:)`` end.
    func reachedStations(endingDayAt now: GameTime, release: PassengerRelease?, workedOutAt time: GameTime, ended: PassengerPlanCache) -> [StationID: Int] {
        guard townGrowth != nil, accounts.mode == .management else { return [:] }
        guard time >= now, now.seconds > Int64.min else { return release.map(Self.reachedStations) ?? [:] }
        var day = self
        day.clock = GameClock(now: GameTime(seconds: now.seconds - 1))
        // Decision 379: a network plan, `ended` (the one before the plan
        // was last worked out again) or the current one, whose key is the
        // same at the day's last second is that plan
        // (`PassengerPlanKeyTests`), not worked out again.
        day.passengerPlan = PassengerPlanCache()
        if passengerRoutingMode == .network {
            let key = day.passengerPlanKey()
            if let plan = [ended, passengerPlan].first(where: { $0.plan != nil && $0.key == key }) {
                day.passengerPlan = plan
            }
        }
        return day.passengerRelease().map(Self.reachedStations) ?? [:]
    }

    /// Advances the simulation by `ticks` ticks at the current speed.
    ///
    /// A basic step is one game second (Stage W2a). A tick runs the speed's
    /// tenths of a second (see ``GameSpeed/tenthsPerTick``): none while
    /// paused, a second every 10 ticks at ``GameSpeed/x1`` (the tenths that
    /// make no whole second yet wait in ``GameClock/pendingTenths``), a
    /// minute at ``GameSpeed/normal``.
    ///
    /// Trains move every second (phase 2 below), each second its share of
    /// its rate per minute: second `s` of a minute (from 0) takes a train
    /// `⌊rate·(s + 1)/60⌋ − ⌊rate·s/60⌋` units, so a whole minute takes it
    /// its rate. Services run on the second too (Stage W2b): a train dwells
    /// at each call (see ``ServiceTimes``) and leaves at whichever second
    /// its doors have closed; between calls it follows its run's running
    /// curve instead of its rate (Stage W2c, see ``ServiceRun``). The
    /// accounts, passengers and dispatch stay on whole minutes. So each
    /// step from second `t` to `t + 1` has these phases, each taking the
    /// lines in ascending ``LineID`` order and the trains in ascending
    /// ``TrainID`` order:
    ///
    /// - **At a whole minute `T`** only: the accounts settle (G1c), then
    ///   **passengers** (G1a): every pair of stations with trips (see
    ///   ``hourlyDemand(from:to:)``), by ascending origin and then
    ///   destination, releases its share of minute `T` at the origin, where
    ///   the passengers wait for their trip (see
    ///   ``passengerTrip(from:to:)``) or, when the station is full, leave at
    ///   once (see ``StationPassengers/capacity``). A pair's share of a
    ///   minute is its trips of the hour, and of the next hour, weighted by
    ///   how far into the hour the minute is: `((60 − m)·R_h + m·R_{h+1}) /
    ///   3600` at minute `m` of hour `h`, with the fraction kept for the next
    ///   minute. So a pair releases exactly its daily trips over any 1440
    ///   minutes in a row. This reads no train and changes none.
    /// 0. **Dispatch at `T`**, only at a whole minute: each line sends out
    ///    at most one of its trains on a round trip (see below). Its service
    ///    starts as if it had just arrived at the first call, where it
    ///    dwells before it leaves.
    /// 1. **Services at `t`.** Every train whose service waits at a stop
    ///    moves its dwell on, and then leaves if it is due:
    ///
    ///    - **Doors open.** ``ServiceDwell/doorOpening`` after the train
    ///      arrived, those riding it to the stop's station get off (at a
    ///      stop where it turns round or its service ends, everyone does),
    ///      and, before its last stop, a train on a line takes on the
    ///      passengers waiting there for its line and direction whose
    ///      destination it calls at before it next turns round, the
    ///      farthest first, up to its ``Train/capacity`` (G1b; see
    ///      ``riders(of:)`` and ``PassengerLedger``). Both use the doors at
    ///      once, so the exchange lasts the larger number's
    ///      ``Train/exchangeSeconds(_:crowd:)``.
    ///    - **Doors held open.** At each whole minute while they are open,
    ///      newly released passengers board too, and the exchange runs on.
    ///    - **Doors closing.** They start closing at the first second when
    ///      the exchange is over and, once they have closed, the train will
    ///      have dwelt its least (``ServiceDwell/minimumDwell(isTerminal:)``)
    ///      and reached its scheduled departure: an early train holds for
    ///      its timetable, a late one leaves as soon as it can.
    ///    - **Departure**, ``ServiceDwell/doorClosing`` later (see below).
    ///      Departures are those of the service's cycle: the timetable's
    ///      times shifted by whole periods. A full train counts those it
    ///      could not take as refused, and a line's train counts the
    ///      departure (G1c). The train sets off on a run (Stage W2c, see
    ///      ``run(of:length:scheduled:)``): in the seconds from the
    ///      scheduled departure to the scheduled arrival when its
    ///      performance builds a curve for them, otherwise as fast as it
    ///      can.
    ///
    ///    A travelling train held up on its run (see phase 2) sets off on a
    ///    new one from a stand over the way left, as fast as it can, once
    ///    it has a rate and can move (see ``resumeRun(_:at:)``). A service
    ///    stopped at a passing place (Stage V2) goes on to its call once it
    ///    can take the route there, as fast as it can (see ``goOn(_:held:memo:)``).
    /// 1b. **The dispatcher at `T`** (Stage V2), only at a whole minute,
    ///    under traffic control: of the trains in a deadlock (see
    ///    ``deadlockedTrains()``), the first whose service is due to leave
    ///    or stands at a passing place, and has a passing place that lets
    ///    another of them go, sets off for it (see ``resolveDeadlock(memo:)``).
    /// 2. **Movement.** Every train with a rate above 0 travels its share
    ///    for second `t`: along its service's run, the curve's distance at
    ///    `t + 1` less at `t`; otherwise its share of its rate (see
    ///    ``TrainMovement``). A travelling train that could not keep to its
    ///    run (a rate of 0, or track ahead removed) drops it (see
    ///    ``dropRunsHeldUp(endingAt:memo:)``).
    /// 3. The clock moves on to `t + 1`.
    /// 4. **Arrivals.** Every train whose service is travelling to a stop
    ///    and that is now stopped at that stop's station (see
    ///    ``stationsStoppedAt(by:)``) waits at that stop, arriving at
    ///    `t + 1`; its dwell starts in phase 1 of the next step.
    ///
    /// Without traffic control trains do not interact, so the order only
    /// fixes when each is updated. Between the seconds at which something
    /// happens (a whole minute, a dwell moving on, a run's end, a train
    /// coming to the end of its route, and under traffic control the track
    /// a waiting departure needs coming free) only movement does, and it depends
    /// on the map and the clock alone, so those seconds are taken together:
    /// they move every train exactly as far as one second at a time would. Whenever the clock can
    /// hold the whole batch, `advance(ticks: n)` is the same as `n` calls
    /// of `advance(ticks: 1)`, and one tick at a speed the same as ticks at
    /// slower speeds that run the same seconds, apart from the speed
    /// itself. (Near the clock's limit a batch is rejected whole, while
    /// single ticks may still fit one at a time.)
    ///
    /// A train that cannot enter the next edge of its path (the edge was
    /// removed after the path was set) waits at the end of its edge; edge
    /// IDs are never reused, so it waits until it is given a new path.
    /// Distance a train cannot use is dropped, so a train never catches up.
    ///
    /// **Services** (see ``startTrainService(_:)``). A service never leaves a
    /// stop before its scheduled departure, and never before its dwell
    /// there is over (phase 1). Starting a service counts as arriving at
    /// its first stop. Leaving stop `i`:
    ///
    /// - A stop marked ``ScheduledStop/reverses`` first turns the train
    ///   round where it stands, as ``reverseTrain(_:)`` would, and the rest
    ///   of the departure starts from there.
    /// - At the last stop of a timetable that runs once, or of the last
    ///   cycle whose times fit, the service is complete: it ends, and the
    ///   train stays where it is, keeping its timetable and rate.
    /// - Otherwise the service gives the train the path
    ///   ``path(from:toStation:length:)`` finds to where it stops for the
    ///   station of the next call (a berth of one of the station's platforms
    ///   that the train fits; Stage S5), and the train travels there. The next call is stop `i + 1`; after the last
    ///   stop of a repeating timetable it is stop 0 of the next cycle. The
    ///   service never turns the train except at a stop marked to, and never
    ///   sets the rate: a train with rate 0 gets its path and stays where it
    ///   is.
    /// - A path of no distance means the train is already stopped at the
    ///   next call's station (a repeated station, a platform both share, or
    ///   a repeating timetable that ends where it starts). It arrives there
    ///   at once, and dwells there as at any call.
    /// - A train the service turns round, or leaves at its last stop, stands
    ///   where it is: its path now ends there (see ``TrainMovement/end``), so
    ///   it does not run on along its edge.
    /// - Without a route the train waits at its stop, not turned round, and
    ///   later steps try again, turning it first again: after a command
    ///   changes the map, a route may appear. Within one call the map cannot
    ///   change, so the route is looked up at most once per call.
    ///
    /// A travelling train follows its path like any other; if track ahead is
    /// removed it waits at the end of its edge, and no new route is looked
    /// up. Since Stage W2c the timetable's arrival times set how long each
    /// run takes, so a train that leaves on time arrives on time and one
    /// that leaves late arrives as late; they are not a limit (a train that
    /// cannot keep to its run arrives later).
    ///
    /// **Traffic control** (Stage T, see ``setTrafficControl(_:)``). A
    /// departure takes its whole route to the next call at once, turned
    /// round first where the stop says so (see ``reservedResources(of:)``);
    /// where another train holds some of it, nothing changes (the train is
    /// not turned round either) and the service tries again at the next
    /// step. A line's train is ready only if its first departure could take
    /// its route when it is sent out; one that cannot is not sent out, and
    /// the line's last dispatch stays as it was. Earlier departures in a
    /// step take their routes first, in train ID order. Trains move as they
    /// always have: the whole route was theirs before they set off. As a
    /// train moves on in phase 2, its reservation keeps only what it still
    /// needs (Stage U, see ``reservedResources(of:)``): track its tail has
    /// left is free for other trains from the next step on, and all of it
    /// is once it comes to the end of its route.
    ///
    /// **Dispatch** (see ``assignTrain(_:to:pattern:)``). Each service of a
    /// line (its own, then its patterns in order) sends a train out at `T`
    /// when all of these hold:
    ///
    /// - `T` is minute 0 or later, the line's window is open, the
    ///   service's journey can be driven (see ``lineJourney(_:pattern:)``),
    ///   and at the level of `T` it runs trains beside the services before
    ///   it (see ``lineTrainsInService(_:at:pattern:)``);
    /// - that headway (see ``lineHeadway(_:at:pattern:)``) has passed since
    ///   the service last sent a train out;
    /// - fewer of its trains run a service than it runs then; and
    /// - one of its trains is ready: without a service, placed, with a rate
    ///   above 0, stopped at the first call's station (see
    ///   ``stationsStoppedAt(by:)``), and able to drive the whole round trip
    ///   from there as it faces or turned round, whichever is shorter (as it
    ///   faces when they are equal).
    ///
    /// The first ready train in ID order gets a timetable for one round trip
    /// sent out at `T`, and its service starts at the first call, where it
    /// dwells (phase 1): the timetable has it leave
    /// ``ServiceDwell/terminalMinimum`` after `T`. The times come from that
    /// trip at the line's rate, with the dwells of ``ServiceLine``: out to
    /// the last call, where it turns round, and back to the first, where it
    /// turns round and the service ends; stops a pattern does not call at
    /// are not in the timetable. The train then waits there until its service
    /// sends it out again. So a service never runs more trains than it runs
    /// at its level: when it runs fewer, the trains coming back wait at the
    /// first call; when it runs more, only trains waiting there can go. A
    /// train late back makes the next one leave late, never early.
    ///
    /// When a whole minute changes no train (no train moves, no service's
    /// dwell moves on, no service leaves, arrives or ends, and no line
    /// sends a train out), no later minute of this call can change anything
    /// before the minute of the next second at which a service's dwell
    /// moves on by itself (see ``nextServiceEvent(after:)``), or a slow run
    /// takes its train on (see ``nextRunMove(from:)``), or the next
    /// minute at which a line's service with a ready train might send it
    /// out (the map and every train's inputs stay the same until the next
    /// command, a departure that found no route finds none later in the
    /// call, one whose route is held finds it held until some train moves,
    /// and a line's window, level and headways change only at known
    /// minutes), so the clock moves on at once to that minute, or to the
    /// end of the batch, releasing each skipped minute's passengers on the
    /// way. While passengers are released and a train waits with its doors
    /// open, minutes are not skipped: those released may board. This is an
    /// exact shortcut, not an approximation.
    ///
    /// - Throws: ``GameError/clockOverflow`` if game time would pass the
    ///   largest second the clock can hold. This is checked before any train
    ///   or the clock changes, so a rejected call changes nothing.
    /// - Precondition: `ticks >= 0`.
    public mutating func advance(ticks: Int) throws(GameError) {
        let steps = try clock.basicSteps(forTicks: ticks)
        clock.keep(pendingTenths: steps.pendingTenths)
        var remaining = steps.seconds
        // Services whose departure found no route in this call. Nothing can
        // change the map or move a waiting train before the call ends, so
        // looking again would give the same answer.
        var unroutable: Set<TrainID> = []
        var memo = DispatchMemo()
        // What the memo is lent and keeps is for the world as the call
        // finds it.
        let routeKey = remaining > 0 ? RouteMemo.Key(self) : nil
        if let routeKey {
            routeMemo.lend(to: &memo.directions, for: routeKey)
        }
        let serviceKey = remaining > 0 ? RouteMemo.ServiceKey(self) : nil
        if let serviceKey {
            routeMemo.lend(to: &memo, for: serviceKey)
        }
        // Departures due now whose routes other trains hold (Stage T), each
        // with the track it waits for: tried again at the next step.
        var held: [HeldRoute] = []
        // Worked out only when the call steps at all: a paused game's calls
        // cost nothing.
        // A network plan kept from an earlier call is used only while all
        // it was worked out from is unchanged, the service level included.
        // The plan before it was last worked out again, which midnight's
        // growth may still read (decision 379).
        var endedPlan = passengerPlan
        if remaining > 0 && passengerRoutingMode == .network, passengerPlan.plan != nil,
           passengerPlan.key != passengerPlanKey() {
            passengerPlan = PassengerPlanCache()
        }
        var release = remaining > 0 ? passengerRelease() : nil
        // When `release` was worked out: midnight's growth reads the plan
        // of the day that ended.
        var releasedFrom = clock.now
        var passengerLevels = serviceLevels(at: clock.now)
        let minute = GameTime.secondsPerMinute
        while remaining > 0 {
            // Decision 716, continued: track being closed that the trains
            // have left is closed, before anything is decided. From here
            // the step is as a new call would find it: what was kept for
            // the network as it was is worked out again.
            if !network.closingEdges.isEmpty, closeTrackTrainsHaveLeft() {
                if let release { keepRemainders(of: release) }
                unroutable = []
                memo = DispatchMemo()
                endedPlan = passengerPlan
                release = passengerRelease()
                releasedFrom = clock.now
                passengerLevels = serviceLevels(at: clock.now)
            }
            let start = clock.now
            var changed = false
            // Stage U2: trains following others take what has freed ahead of
            // them first, before any train sets off.
            if extendAuthorities(memo: &memo.directions) {
                changed = true
            }
            if start.isWholeMinute {
                if passengerRoutingMode == .network {
                    let levels = serviceLevels(at: start)
                    if levels != passengerLevels {
                        if let release { keepRemainders(of: release) }
                        endedPlan = passengerPlan
                        passengerPlan = PassengerPlanCache()
                        release = passengerRelease()
                        releasedFrom = start
                        passengerLevels = levels
                    }
                }
                // Items 4 and 5: towns grow from the day that ended, and
                // events start and end, at midnight.
                let midnight = (demandEvents != nil || townGrowth != nil || tourism != nil || !airports.isEmpty || !airRoutes.isEmpty || !coachStops.isEmpty) && start.seconds % GameTime.secondsPerDay == 0
                // Decision 400: the roads grow at the midnight that begins
                // each month.
                if roads != nil, start.seconds % GameTime.secondsPerDay == 0 {
                    let day = dayIndex(of: start)
                    if day > 0, day % RoadGrid.growthDays == 0 { growRoads() }
                }
                if midnight {
                    growTowns(reached: reachedStations(endingDayAt: start, release: release, workedOutAt: releasedFrom, ended: endedPlan))
                    startDemandEventDay(dayIndex(of: start))
                    closeTourismDay(dayIndex(of: start) - 1)
                    closeAirportDay(dayIndex(of: start) - 1, at: start)
                    closeCoachDay(dayIndex(of: start) - 1)
                }
                // Weekly demand and events: each day releases its own day's
                // trips.
                if midnight || demandDay != nil && passengerPlan.day != demandDay {
                    if let release { keepRemainders(of: release) }
                    endedPlan = passengerPlan
                    passengerPlan = PassengerPlanCache()
                    release = passengerRelease()
                    releasedFrom = start
                }
                tickFreight(at: start)
                settleAccounts(at: start, memo: &memo)
                sendWaitingPassengersHome(at: start)
                sendImpatientPassengersAway(at: start)
                if release != nil {
                    releasePassengers(at: start, &release!)
                }
                if dispatchTrains(memo: &memo) {
                    changed = true
                }
            }
            // Stage W2b: every service's dwell, and the departures due now.
            held = []
            // V3 (decision 59): the plan from the world as the step finds
            // it, kept for every decision the step makes.
            memo.directions.stepTraffic = nil
            let traffic = trafficPlan(memo: &memo.directions)
            let trafficKey = memo.directions.traffic?.key
            memo.directions.stepTraffic = traffic
            recordTrafficVisits(traffic, before: nil)
            // Decision 542: whether a train turning aside on its way for
            // an overtake found the track it needs held.
            var turningAside = false
            if runServices(at: start, unroutable: &unroutable, held: &held, turningAside: &turningAside, memo: &memo) {
                changed = true
            }
            // Stage V2: once a minute, the dispatcher sends a service of a
            // deadlock to a passing place; failing that (decision 278), a
            // train following others onto a berth a train without a
            // service stands on goes to another berth.
            // Decision 666: failing that, a train between runs in the way
            // of a train waiting for its route, its own way into a depot
            // held, steps aside.
            if start.isWholeMinute, let resolved = resolveDeadlock(memo: &memo) ?? changeBerth(memo: &memo) ?? makeWayForDepot(memo: &memo) {
                held.removeAll { $0.candidate.id == resolved }
                changed = true
            }
            // The seconds to the end of this minute, or of the batch, or to
            // the next second at which a service's dwell moves on or a
            // train comes to the end of its route: they move the trains
            // exactly as far as one second at a time would, and nothing
            // else happens in them.
            let second = start.secondOfMinute
            var span = min(remaining, minute - second)
            solveRuns()
            // Decision 248: how far the trains of real runs may go on in
            // the rest of the minute.
            assessSpacing(from: start, memo: &memo.directions)
            if let event = nextServiceEvent(after: start, known: &memo.directions.paths.trainLines) {
                let (gap, overflow) = event.seconds.subtractingReportingOverflow(start.seconds)
                span = overflow ? span : min(span, gap)
            }
            if let end = secondsUntilARouteEnds(from: start, within: span, memo: &memo.directions) {
                span = end
            }
            // Stage U: or to the second at which trains moving on have
            // released enough track behind them for a departure that waits
            // for its route, which then tries again, or (Stage U2) for a
            // train following them to take more of its route. `moves` keeps
            // the trains as each span tried leaves them, for the move below.
            var moves: [Int64: (trains: [Train], spacing: [TrainID: SpacingAllowance], lies: [TrackNodeID: SwitchLie], moved: Bool)] = [:]
            if span > 1, !held.isEmpty || trains.contains(where: { isFollowing($0, memo: &memo.directions) }),
               let freed = secondsUntilARouteFrees(held, from: start, within: span, moves: &moves, memo: &memo) {
                span = freed
            }
            // Decision 542: a train turning aside on its way tries again
            // at the next second, as it would stepping a second at a time.
            if turningAside { span = 1 }
            if !traffic.waits.isEmpty {
                // Decision 59: a plan that schedules a wait is worked out
                // again at the next second when this step changed what it
                // is derived from, and otherwise holds until a wait may let
                // its train go or a visit it needs is made (see
                // ``secondsUntilTrafficChanges(_:from:within:memo:)``).
                if trafficPlanKey() != trafficKey {
                    span = 1
                } else if span > 1, let changes = secondsUntilTrafficChanges(traffic, from: start, within: span, memo: &memo.directions) {
                    span = changes
                }
            } else if span > 1, trafficPlanKey() != trafficKey {
                // A departure or a visit in this step changed what the plan
                // is derived from: when the plan it gives schedules a wait,
                // the next second works it out again, as a step every second
                // would (decision 59, point 13).
                memo.directions.stepTraffic = nil
                if !trafficPlan(memo: &memo.directions).waits.isEmpty { span = 1 }
                memo.directions.stepTraffic = traffic
            }
            let beforeTraffic = traffic.waits.isEmpty ? nil : trains
            // Nothing has changed a train since the spans were tried.
            if let move = moves[span] {
                trains = move.trains
                spacingAllowances = move.spacing
                switchLies = move.lies
                if move.moved {
                    changed = true
                }
                if dropRunsHeldUp(endingAt: Self.saturating(start, plus: span), memo: &memo.directions) {
                    changed = true
                }
            } else {
                if moveTrains(from: start, for: span, memo: &memo.directions) {
                    changed = true
                }
                if dropRunsHeldUp(endingAt: Self.saturating(start, plus: span), memo: &memo.directions) {
                    changed = true
                }
            }
            clock.advance(basicSteps: span)
            remaining -= span
            // Decision 248: the minute's allowances are spent as it ends.
            if clock.now.isWholeMinute, !spacingAllowances.isEmpty { spacingAllowances = [:] }
            recordTrafficVisits(traffic, before: beforeTraffic)
            memo.directions.stepTraffic = nil
            if recordArrivals() {
                changed = true
            }
            if !changed, span == minute, traffic.waits.isEmpty {
                // A closed network may have no release plan and no ready
                // train. It must still wake when passenger service opens.
                let passengerWake: Int64?
                if passengerRoutingMode == .network {
                    let levels = serviceLevels(at: clock.now)
                    passengerWake = levels != passengerLevels ? 0 : lines.compactMap {
                        $0.nextChange(after: clock.now, in: serviceDay)
                    }.min().map { Self.minutes(from: clock.now, until: $0) }
                } else {
                    passengerWake = nil
                }
                // Weekly demand, events and town growth: the next day
                // releases its own trips; and roads (decision 400) grow at
                // a midnight; and the air routes (decision 758) settle
                // at one. The second of the day, without
                // multiplying back (a save's clock may be near the end of
                // time). At midnight itself that is 0: the next step handles
                // it, and skipping it would lose the day's growth and events.
                let day = GameTime.secondsPerDay
                let dayWake: Int64? = demandDay != nil || townGrowth != nil || roads != nil || !airRoutes.isEmpty ? {
                    let intoDay = (clock.now.seconds % day + day) % day
                    let left = (day - intoDay) % day
                    return (left + GameTime.secondsPerMinute - 1) / GameTime.secondsPerMinute
                }() : nil
                let wake = [
                    wholeMinutesUntilNextServiceEvent(passengersWaiting: release != nil), minutesUntilNextDispatch(memo: &memo),
                    minutesUntilLineWaitsChange(memo: &memo), passengerWake, dayWake,
                ].compactMap { $0 }.min()
                let idle = min(remaining / minute, wake ?? remaining / minute)
                if release != nil || accounts.mode == .management || freight != nil {
                    // Releasing passengers (G1a) and settling the accounts
                    // (G1c) change no train, so the minutes skipped still do
                    // theirs, minute by minute.
                    for step in 0..<idle {
                        let time = GameTime(seconds: clock.now.seconds + step * minute)
                        tickFreight(at: time)
                        settleAccounts(at: time, memo: &memo)
                        sendWaitingPassengersHome(at: time)
                        sendImpatientPassengersAway(at: time)
                        if release != nil {
                            releasePassengers(at: time, &release!)
                        }
                    }
                } else if passengers.contains(where: { !$0.waiting.isEmpty }) {
                    // Decision 504: those still waiting go home at 04:00
                    // in the minutes skipped too.
                    for step in 0..<idle {
                        let time = GameTime(seconds: clock.now.seconds + step * minute)
                        sendWaitingPassengersHome(at: time)
                        // Decision 731: and those who wait too long give up.
                        sendImpatientPassengersAway(at: time)
                    }
                }
                clock.advance(basicSteps: idle * minute)
                remaining -= idle * minute
            }
        }
        if let release {
            keepRemainders(of: release)
        }
        if let routeKey {
            // Kept only when the call changed none of what it is for.
            if RouteMemo.Key(self) == routeKey {
                routeMemo.keep(memo.directions, for: routeKey)
            } else {
                routeMemo = RouteMemo()
            }
        }
        if let serviceKey, RouteMemo.ServiceKey(self) == serviceKey {
            routeMemo.keep(memo, for: serviceKey)
        }
        // Decision 716, continued: and as the call ends, so that a batch
        // and its steps leave the same track closed.
        if steps.seconds > 0, !network.closingEdges.isEmpty {
            closeTrackTrainsHaveLeft()
        }
    }

    /// `time` plus `minutes` whole minutes, or `nil` if that does not fit in
    /// a ``GameTime``.
    static func time(_ time: GameTime, plusMinutes minutes: Int64) -> GameTime? {
        let (seconds, long) = minutes.multipliedReportingOverflow(by: GameTime.secondsPerMinute)
        let (sum, overflow) = time.seconds.addingReportingOverflow(seconds)
        return long || overflow ? nil : GameTime(seconds: sum)
    }

    /// The whole minutes from `now`, the start of a minute, until the start
    /// of the first minute at or after `time`, which is not before `now`;
    /// `Int64.max` if that is more than an `Int64` holds.
    static func minutes(from now: GameTime, until time: GameTime) -> Int64 {
        let (gap, overflow) = time.seconds.subtractingReportingOverflow(now.seconds)
        guard !overflow else { return .max }
        let minute = GameTime.secondsPerMinute
        return gap / minute + (gap % minute == 0 ? 0 : 1)
    }

    /// What dispatching works out once per call of ``advance(ticks:)``:
    /// no command can come within a call, so the map, the lines' stops,
    /// patterns and rates and an idle train's position stay the same, and
    /// so do these.
    struct DispatchMemo {
        /// Each service's journey (see ``lineJourney(_:pattern:)``), by line
        /// and service (see ``ServiceLine/serviceCount``), once looked up.
        var journeys: [LineID: [Int: LineJourney?]] = [:]
        var capacityLayouts: [LineID: LineCapacityLayout] = [:]
        var capacities: [LineID: [Int: ServiceCapacityProfile?]] = [:]
        var outerCapacityJourneys: [LineID: LineJourney?] = [:]
        /// V1 complete direction plans, local to this advance.
        var directions = DirectionMemo()
        /// Each train's round trip from where it stood idle (its position
        /// and body) when it was looked up, or
        /// `nil` if it had none.
        var trips: [TrainID: (from: TrainPlacement, trip: LineTrip?)] = [:]
        /// Decision 209: each train's empty run out of its line's depot from
        /// where it stood when it was looked up, or `nil` if it had none.
        var depotTrips: [TrainID: (from: TrainPlacement, trip: LineTrip?)] = [:]
        /// Decision 221: each train's empty run out of its line's depot to a
        /// stop of a line with runs, by where it stood and the stop when it
        /// was looked up, or `nil` if it had none.
        var runDepotTrips: [RunDepotQuery: LineTrip?] = [:]
        /// Whether each line's service, by line and pattern, has a journey
        /// and runs trains at some level of its window (see
        /// ``GameWorld/isServed(_:memo:)``), once worked out.
        var scheduledServices: [ScheduledService: Bool] = [:]
    }

    struct ScheduledService: Hashable {
        var line: LineID
        var pattern: Int?
    }

    /// A train's empty run out of a depot to a stop (decision 221), as
    /// ``DispatchMemo/runDepotTrips`` keeps it.
    struct RunDepotQuery: Hashable {
        let train: TrainID
        let from: TrainPlacement
        let to: StationID
        /// Decision 535: the way round a ring the run out is for.
        var way: RingDirection? = nil
    }
}
