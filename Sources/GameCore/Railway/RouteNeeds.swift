// Route reservation (Phase 4.6 Stage T, ARCHITECTURE decision 32): what a train needs.
// Moved from RouteReservation.swift unchanged (decision 910); the overview
// of route reservation is at the top of that file.

extension GameWorld {
    // MARK: - What a train needs

    /// `candidate`, a train about to be given a place or a route, with the
    /// reservation traffic control gives it, or the lowest numbered other
    /// train that holds track it needs. With traffic control off, the
    /// candidate as it is.
    enum Reserving {
        case granted(Train)
        case held(by: TrainID)
    }

    /// See ``Reserving``. A service's departure (`following`, Stage U2)
    /// whose route another train holds may instead follow the trains
    /// ahead, taking its route only part of the way (see
    /// ``followingAuthority(of:route:memo:)``).
    func reserving(_ candidate: Train, following: Bool = false) -> Reserving {
        var memo = DirectionMemo()
        return reserving(candidate, following: following, memo: &memo)
    }

    /// ``reserving(_:following:)`` with the trains' holders kept in `memo`.
    func reserving(_ candidate: Train, following: Bool = false, memo: inout DirectionMemo) -> Reserving {
        guard isTrafficControlEnabled else { return .granted(candidate) }
        // Its route envelope (see ``routeEnvelope(of:)``), asked a resource
        // at a time, and gathered only to be taken.
        let route = routeStretches(of: candidate)
        // Decision 562: with block sections, never onto a following train's
        // route ahead of it as a train it could never follow, whole or
        // following the trains ahead.
        if route.moves, blockSections, let follower = followerCutOff(by: candidate, memo: &memo) {
            return .held(by: follower)
        }
        // Decision 294: a long leg of a line with runs, only part of the way.
        if route.moves, blockSections, case .travellingToStop? = candidate.execution, followsRealTimetable(candidate) {
            let envelopes = authorityEnvelopes(of: candidate, along: route.stretches)
            if envelopes.length > Self.approachReach, let limit = approachLimit(of: candidate, envelopes) {
                return reservingApproach(candidate, envelopes: envelopes, limit: limit, following: following, memo: &memo)
            }
        }
        // Decision 968: PROBE.
        if route.moves, !blockSections, candidate.isDeadheading, case .travellingToStop? = candidate.execution {
            let envelopes = authorityEnvelopes(of: candidate, along: route.stretches)
            if Probe.on("dump") { dumpRoute(of: candidate, envelopes) }
            if Probe.on("dl"), !Probe.on("dlfree"), let limit = depotLimit(of: candidate, envelopes) {
                return reservingApproach(candidate, envelopes: envelopes, limit: limit, following: following, memo: &memo)
            }
        }
        let envelope = cover(of: bodyStretches(of: candidate) + route.stretches)
        if let holder = holder(of: envelope, except: candidate.id, holders: trackHolders(memo: &memo)) {
            if following, route.moves, let train = followingAuthority(of: candidate, route: envelope, memo: &memo) {
                return .granted(train)
            }
            return .held(by: holder)
        }
        var train = candidate
        train.reservation = route.moves ? Set(envelope.resources).sorted() : []
        // Decision 849: a service of a line with runs whose whole route is
        // free takes it only to its home signal while that is far (see
        // ``homeLimit(of:_:)``): without block sections, and with them on
        // a leg decision 294 leaves whole.
        if route.moves, case .travellingToStop? = candidate.execution, followsRealTimetable(candidate) {
            let envelopes = authorityEnvelopes(of: candidate, along: route.stretches)
            if let limit = approachLimit(of: candidate, envelopes) {
                train.reservation = authorityEnvelope(envelopes, to: limit).sorted()
            }
        }
        return .granted(train)
    }

    /// Decision 577: `candidate`, a departure, with its route taken whole
    /// as ``reserving(_:following:memo:)`` takes it, but where the track
    /// trains `followers` wait for (decision 56, point 6) does not keep it
    /// from that track: only what trains hold, foul, or other followers
    /// wait for does. For a deadlock only (see
    /// ``GameWorld/resolveDeadlock(memo:)``); never with block sections,
    /// where a following train waits for nothing it has not taken.
    func reserving(_ candidate: Train, ignoringClaimsOf followers: Set<TrainID>, memo: inout DirectionMemo) -> Reserving? {
        guard isTrafficControlEnabled, !blockSections else { return nil }
        let route = routeStretches(of: candidate)
        guard route.moves else { return nil }
        let envelope = cover(of: bodyStretches(of: candidate) + route.stretches)
        let holders = trackHolders(memo: &memo).ignoringClaims(of: followers)
        if let holder = holder(of: envelope, except: candidate.id, holders: holders) { return .held(by: holder) }
        var train = candidate
        train.reservation = Set(envelope.resources).sorted()
        return .granted(train)
    }

    /// Decision 562: with block sections a train following others holds
    /// only the track it has taken (decision 212), so a train could take
    /// the rest of its route ahead of it, standing where the follower must
    /// pass, and then never move again:
    ///
    /// - one that ends its service or turns round at the call it travels
    ///   to: a train turning back leaves the way it came, perhaps over the
    ///   track the follower stands on, and one whose service ends stands
    ///   (Taoyuan Airport MRT 18 and 29 at Airport Terminal 2, decision
    ///   556); the follower never follows either (see
    ///   ``isLeading(_:onto:for:)``);
    /// - one that comes along the follower's route the other way and goes
    ///   on along it, back past where the follower will wait short of it
    ///   (see ``followerWaitsInTheWay(_:of:going:memo:)``): each waits for
    ///   the other (the same line's 1, westbound into Kengkou, and 26, an
    ///   empty train out of Luzhu depot eastbound on that track).
    ///
    /// The lowest numbered such follower `candidate`, about to take its
    /// route, whole or following the trains ahead, would cut off, so it
    /// waits for it; `nil` when there is none. A train that stands on the
    /// follower's route already, or whose route passes over the follower,
    /// is not held: the follower waits for the one, and the other is behind
    /// it and can only follow it.
    func followerCutOff(by candidate: Train, memo: inout DirectionMemo) -> TrainID? {
        guard case .travellingToStop(let stop, let cycle)? = candidate.execution else { return nil }
        let next = candidate.timetable[stop].reverses ? nil : candidate.call(after: stop, cycle: cycle)
        let standing = occupied(candidate)
        let path = cover(of: routeStretches(of: candidate).stretches)
        var arrived: Train?
        for other in trains where other.id != candidate.id && other.position != nil {
            guard let (_, envelopes) = authority(of: other, memo: &memo) else { continue }
            let route = followingCover(of: other, envelopes, memo: &memo)
            guard !standing.contains(where: route.contains), !occupied(other).contains(where: path.contains),
                  stopsOn(route, candidate) else { continue }
            guard let next else { return other.id }
            if arrived == nil {
                var train = candidate
                train.reservation = []
                let end = travelling(train, distance: routeLength(of: candidate), memo: &memo)
                train.position = end.position
                train.movement.cursor = end.cursor
                arrived = train
            }
            if followerWaitsInTheWay(other, of: arrived!, going: candidate.timetable[next.stop].station, envelopes) { return other.id }
        }
        return nil
    }

    /// Whether `train`, standing on `follower`'s route facing against it,
    /// goes on toward `station` back along that route over where the
    /// follower will wait short of it: the last block boundary at least
    /// ``followingGap`` before its head (see ``blockBoundary(_:atOrBefore:)``),
    /// or the follower itself.
    func followerWaitsInTheWay(_ follower: Train, of train: Train, going station: StationID, _ envelopes: AuthorityEnvelopes) -> Bool {
        guard case .onEdge(let traversal, let offset)? = train.position,
              let length = network.edge(traversal.edge)?.length else { return false }
        // The follower's offset of the train's head, which faces it.
        let along = length - offset
        guard let index = envelopes.stretches.firstIndex(where: {
            $0.traversal == traversal.reversed && $0.from <= along && along <= $0.to
        }) else { return false }
        let start = { (index: Int) in index == 0 ? 0 : envelopes.ends[index - 1] }
        let head = start(index) + along - envelopes.stretches[index].from
        // Back along the follower's route as far as its way goes with it.
        var shared = index
        if let onward = path(from: .onEdge(traversal, offset: offset), toStation: station, length: train.length) {
            for step in onward.traversals {
                guard shared > 0, envelopes.stretches[shared - 1].traversal == step.reversed else { break }
                shared -= 1
            }
        }
        if shared == 0 { return true }
        return blockBoundary(envelopes, atOrBefore: head - Self.followingGap) > start(shared)
    }

    /// Decision 57: a service's departure takes its default route whole,
    /// or follows the trains ahead on it (Stage U2) where it may; failing
    /// both, it takes the shortest unblocked route to any berth of the same
    /// station whole (see ``alternativeRoute(of:to:avoiding:memo:)``);
    /// failing that, it waits. Manual commands keep using `reserving`
    /// directly. No route or reservation is committed until the final
    /// candidate has been admitted.
    func reservingDeparture(_ candidate: Train) -> Reserving {
        var memo = DirectionMemo()
        return reservingDeparture(candidate, memo: &memo)
    }

    func reservingDeparture(_ candidate: Train, memo: inout DirectionMemo) -> Reserving {
        let taken = takingDeparture(candidate, memo: &memo)
        // Decision 718: not ahead of a service that has waited longer for
        // the same track the other way.
        if case .granted(let granted) = taken, let first = turnOwed(by: granted, memo: &memo) { return .held(by: first) }
        return taken
    }

    /// ``reservingDeparture(_:memo:)`` before the trains take turns
    /// (decision 718): whether the track lets `candidate` go.
    ///
    /// Decision 740: a leg with a list of platforms goes to the first of
    /// them it can take whole or, following the trains ahead, in part, and
    /// otherwise waits for the first (see ``takingAnyDeparture(_:memo:)``
    /// for the way without the list).
    func takingDeparture(_ candidate: Train, memo: inout DirectionMemo) -> Reserving {
        if let listed = listedDepartures(of: candidate, memo: &memo.paths) {
            var first: Reserving?
            for departure in listed {
                let taken = reserving(departure, following: true, memo: &memo)
                if case .granted = taken { return taken }
                if first == nil { first = taken }
            }
            return first!
        }
        return takingAnyDeparture(candidate, memo: &memo)
    }

    /// ``takingDeparture(_:memo:)`` to any platform of the station, as a
    /// leg without a list of platforms goes (decision 740): the default
    /// way whole or following, another platform's whole (decision 57), or
    /// past a standing train (decisions 571, 212).
    func takingAnyDeparture(_ candidate: Train, memo: inout DirectionMemo) -> Reserving {
        let planned = reserving(candidate, following: true, memo: &memo)
        guard isTrafficControlEnabled, case .held = planned,
              case .travellingToStop(let stop, let cycle)? = candidate.execution
        else { return planned }
        if let alternative = alternativeRoute(of: candidate, to: candidate.timetable[stop].station,
                                              avoiding: blockedTrack(except: candidate.id, holders: trackHolders(memo: &memo)), memo: &memo),
           goesOn(candidate, along: alternative, stop: stop, paths: &memo.paths),
           case .granted(let granted) = reserving(rerouted(candidate, along: alternative, stop: stop, cycle: cycle), memo: &memo) {
            return .granted(granted)
        }
        // Decision 571, continued again: without block sections, a free
        // berth against the planned way at once where the train in the
        // way would otherwise only be moved by the dispatcher's next look.
        if !blockSections, let granted = takingFreeBerthPastStandingTrain(candidate, stop: stop, cycle: cycle, memo: &memo) {
            return .granted(granted)
        }
        // With block sections (decision 212): when trains standing (those
        // it may never follow) keep it from its route, the shortest route to
        // a berth of the station that only they block, followed behind the
        // trains ahead on it.
        guard blockSections else { return planned }
        let standing = Set(trains.filter { train in
            guard case .travellingToStop? = train.execution, train.movement.rate > 0 else { return true }
            return false
        }.map(\.id))
        let standingBlocked = blockedTrack(except: candidate.id, among: standing, holders: trackHolders(memo: &memo))
        guard standingBlocked.blocks(envelopeCover(of: candidate), in: network),
              let alternative = alternativeRoute(of: candidate, to: candidate.timetable[stop].station, avoiding: standingBlocked, memo: &memo),
              goesOn(candidate, along: alternative, stop: stop, paths: &memo.paths),
              case .granted(let granted) = reserving(rerouted(candidate, along: alternative, stop: stop, cycle: cycle), following: true, memo: &memo)
        else { return planned }
        return .granted(granted)
    }

    /// Decision 885 (SHALUN-ONE-ISLAND): whether `candidate`, a service
    /// setting off for stop `stop` along `alternative` to another berth
    /// of the stop's station than its own (decision 57), can go on from
    /// there to its next call, as it stands there or turned round: a
    /// platform track that leads only onto another line's way (a branch
    /// that leaves past the station, from one of its platform tracks)
    /// would keep it there. True for its last call.
    func goesOn(_ candidate: Train, along alternative: TrainPath, stop: Int, paths: inout PathMemo) -> Bool {
        let next = stop + 1
        guard candidate.timetable.indices.contains(next), let position = candidate.position else { return true }
        let there = placement(TrainPlacement(position: position, trailEdges: candidate.trailEdges, length: candidate.length), after: alternative)
        let station = candidate.timetable[next].station
        return path(from: there.position, toStation: station, length: candidate.length, memo: &paths) != nil
            || path(from: turnedRound(there).position, toStation: station, length: candidate.length, memo: &paths) != nil
    }

    /// `candidate`, a service setting off for stop `stop` (of cycle
    /// `cycle`), along `alternative` instead, on a run for its time there.
    func rerouted(_ candidate: Train, along alternative: TrainPath, stop: Int, cycle: Int64) -> Train {
        var rerouted = candidate
        follow(alternative, &rerouted)
        let previousStop = stop == 0 ? candidate.timetable.count - 1 : stop - 1
        let previousCycle = stop == 0 ? cycle - 1 : cycle
        // As on its own way (decision 207): with realistic operation the
        // time left to the scheduled arrival, so a late train makes up its
        // margin.
        let timetabled = candidate.scheduledArrival(of: stop, cycle: cycle).seconds
            - candidate.scheduledDeparture(of: previousStop, cycle: previousCycle).seconds
        let scheduled = realisticOperation
            ? secondsToScheduledArrival(of: candidate, stop: stop, cycle: cycle)
            : timetabled
        let reroutedRun = run(of: rerouted, length: alternative.distance, scheduled: scheduled, timetabled: timetabled)
        rerouted.times?.run = reroutedRun
        return rerouted
    }

    /// How much longer than a service's default route an alternative
    /// route (decision 57) or a way through a passing place (Stage V2) may
    /// be: 25,600 units, 400 m, the Railway reference's `BLOCK_GAP_KM`.
    /// Going to another platform of a station, or into a passing loop,
    /// adds only the turnouts' few metres; a route that leaves the line for
    /// another adds kilometres, and is not taken.
    public static let detourAllowance: Int64 = 25_600

    /// Decision 57: the shortest route for `candidate`, a service about to
    /// set off along its default route (see
    /// ``path(from:toStation:length:)``), to a berth of `station` that
    /// avoids `blocked` (see ``path(from:toStation:length:avoiding:forbidden:)``),
    /// that never borrows track against another train's planned direction
    /// (see ``opposingServiceTraversals(for:memo:)``), and that is at most
    /// ``detourAllowance`` longer than the default route; or `nil`.
    func alternativeRoute(of candidate: Train, to station: StationID, avoiding blocked: BlockedTrack, memo: inout DirectionMemo) -> TrainPath? {
        guard let position = candidate.position else { return nil }
        let (limit, overflow) = routeLength(of: candidate).addingReportingOverflow(Self.detourAllowance)
        // Without the other trains' directions first: with them the
        // shortest way can only be as long or longer, or none, so where
        // there is no way short enough without them there is none with
        // them, and they need not be worked out.
        // Decision 278: with block sections the way into a terminus is run
        // both ways by every train there, so it is not forbidden.
        guard let free = path(from: position, toStation: station, length: candidate.length, avoiding: blocked),
              overflow || free.distance <= limit
        else { return nil }
        // The other trains' directions asked of a traversal at a time
        // (see ``opposingParts(for:memo:)``): the same as asking the set
        // of them, without gathering it.
        let parts = opposingParts(for: candidate, memo: &memo)
        // Decision 344: nor, at a line's first call, the way into a berth
        // only a train standing there sets off from.
        let exempt = terminusTraversals(along: free, to: station).union(firstCallTraversals(along: free, to: station, parts: parts))
        let forbids = { (traversal: TrackTraversal) -> Bool in
            !exempt.contains(traversal) && !parts.defaultWays.contains(traversal) && parts.directions.contains { $0.contains(traversal.reversed) }
        }
        // A free way that runs against none of them is the way the search
        // with them finds: the shortest, and of the shortest the first
        // (``TrainRoute/shortest(from:isDestination:next:)`` walks the
        // first step of each place that leads on at the shortest), which
        // leaving out steps the free way does not take changes neither.
        guard runsAlongAny(free, from: position, forbids) else { return free }
        guard let path = path(from: position, toStation: station, length: candidate.length, avoiding: blocked, forbids: forbids) else { return nil }
        return overflow || path.distance <= limit ? path : nil
    }

    /// Decision 571, continued: ``alternativeRoute(of:to:avoiding:memo:)``
    /// without decision 57's direction protection, for a service the
    /// dispatcher finds in a deadlock (see `resolveDeadlock(memo:)`): the
    /// shortest route to any berth of `station` that avoids `blocked`, at
    /// most ``detourAllowance`` longer than its default route; or `nil`.
    /// Run against the planned way only to clear a deadlock nothing else
    /// clears, and only taken whole, so no train meets it head on: a
    /// controller's wrong-line move into the free berth beside.
    func counterflowRoute(of candidate: Train, to station: StationID, avoiding blocked: BlockedTrack) -> TrainPath? {
        guard let position = candidate.position else { return nil }
        let (limit, overflow) = routeLength(of: candidate).addingReportingOverflow(Self.detourAllowance)
        guard let free = path(from: position, toStation: station, length: candidate.length, avoiding: blocked),
              overflow || free.distance <= limit
        else { return nil }
        return free
    }

    /// Decision 571, continued again: `candidate`, a service due to leave
    /// a station for stop `stop` (of cycle `cycle`), whose default route
    /// is held first by a train standing at a berth of that stop's
    /// station that will not clear it for `candidate`, granted the
    /// shortest way to a free berth there against the planned way (see
    /// ``counterflowRoute(of:to:avoiding:)``), taken whole; or `nil`.
    /// The train in the way is either a service waiting there bound for
    /// the station `candidate` stands at, whose own way out is held by
    /// `candidate` (the two would only wait for each other), or a train
    /// with no service of a line without runs, a spare (decision 58),
    /// which nothing else moves, or of a line with runs standing at an end
    /// of its line with no depot of the line to go into and no run from
    /// there before `candidate`, as late as it is, is due there
    /// (LAST-TRAIN-TERMINUS: the
    /// Sanying Line's trains that had ended their day there, the depot
    /// full, on the berths the night's last services were bound for).
    /// Decision 571's dispatcher sent such a
    /// train the same way, but only at its next look, once a minute: on a
    /// double track whose crossovers let each way into one berth at each
    /// end, every trip showed the two trains deadlocked for up to a
    /// minute. Not inlined: off the stack of every departure that runs.
    @inline(never)
    func takingFreeBerthPastStandingTrain(_ candidate: Train, stop: Int, cycle: Int64, memo: inout DirectionMemo) -> Train? {
        // A service leaving a stop: one standing aside at a passing place
        // (Stage V2) is left to the dispatcher, as before.
        guard case .travellingToStop = candidate.execution,
              case .waitingAtStop? = train(id: candidate.id)?.execution
        else { return nil }
        let call = candidate.timetable[stop].station
        let holders = trackHolders(memo: &memo)
        guard let id = holder(of: envelopeCover(of: candidate), except: candidate.id, holders: holders),
              let other = train(id: id), isStopped(other, at: call)
        else { return nil }
        switch other.execution {
        case nil:
            // LAST-TRAIN-TERMINUS: a line with runs moves such a train
            // only for a run from there or into a depot with room. At an
            // end of the line, where its trains stand for the night
            // (decision 816), with no depot of its line with room for it,
            // and with runs from there but none leaving before `candidate`
            // is due there, it stands there past that as a spare does.
            // Elsewhere (an empty run's end, making way; a station between,
            // where the Taoyuan Airport MRT's trains turned against the
            // line's way at Sanchong), while a depot has room (the train
            // at Taipei Main Station went in minutes later), and while a
            // run from there may take it first, it is left to wait.
            // `candidate` is due there as late as it leaves here
            // (EAL-LMC-PEAK-GAP): by its timetable alone a late train
            // counted one about to leave on its run as standing for the
            // night, as at Lok Ma Chau, which has no depot, where a train
            // five minutes late went round one whose run left four
            // minutes on, before it could have come.
            if let line = assignedLine(of: id, memo: &memo), line.hasRuns {
                guard !line.isRing, call == line.stops.first || call == line.stops.last,
                      !line.depots.contains(where: { depotHasRoom($0, for: other) })
                else { return nil }
                let starts = pendingRunStarts(of: line, from: call)
                var due = candidate.scheduledArrival(of: stop, cycle: cycle).seconds
                if case .waitingAtStop(let here, let hereCycle)? = train(id: candidate.id)?.execution {
                    due += max(0, clock.now.seconds - candidate.scheduledDeparture(of: here, cycle: hereCycle).seconds)
                }
                guard !starts.isEmpty, !starts.contains(where: { $0 <= due }) else { return nil }
            }
        case .waitingAtStop(let otherStop, let otherCycle)?:
            let here = stationsStoppedAt(by: candidate.id)
            guard other.timetable.count > 1, here.contains(other.timetable[(otherStop + 1) % other.timetable.count].station),
                  case .setsOff(let leaving, _) = leaving(other, stop: otherStop, cycle: otherCycle, memo: &memo.paths),
                  holder(of: envelopeCover(of: leaving), except: id, holders: holders) == candidate.id
            else { return nil }
        default:
            return nil
        }
        guard let way = counterflowRoute(of: candidate, to: call, avoiding: blockedTrack(except: candidate.id, holders: holders)),
              case .granted(let granted) = reserving(rerouted(candidate, along: way, stop: stop, cycle: cycle), memo: &memo)
        else { return nil }
        return granted
    }

    /// The lowest numbered train other than `id` that holds any of
    /// `resources` (see ``held(_:)``), or track that fouls any of them
    /// (Stage F2b, see ``RailwayNetwork/fouls(_:_:)``), or that follows
    /// another (Stage U2) and still needs some of them, unless train `id`
    /// already holds track that one needs (see ``claim(of:)``); or `nil`.
    func holder(of resources: Set<TrackResource>, except id: TrainID) -> TrainID? {
        var memo = DirectionMemo()
        return holder(of: resources, except: id, memo: &memo)
    }

    /// ``holder(of:except:)`` from the trains' holders kept in `memo` (see
    /// ``trackHolders(memo:)``).
    func holder(of resources: Set<TrackResource>, except id: TrainID, memo: inout DirectionMemo) -> TrainID? {
        holder(of: resources, except: id, holders: trackHolders(memo: &memo))
    }

    /// Everything the trains other than `id` keep it from, together (see
    /// ``holder(of:except:)``): track fouling any of it has a holder. For
    /// trying many stretches against the same trains.
    func blockedTrack(except id: TrainID) -> Set<TrackResource> {
        var memo = DirectionMemo()
        return blockedTrack(except: id, memo: &memo)
    }

    /// ``blockedTrack(except:)`` from the trains' holders kept in `memo`.
    func blockedTrack(except id: TrainID, memo: inout DirectionMemo) -> Set<TrackResource> {
        blockedTrack(except: id, holders: trackHolders(memo: &memo)).resources
    }

    /// A train's reservation (see ``Train/reservation``), to ask whether it
    /// holds a resource: by halving while it is in resource order, as the
    /// game keeps it, else through a set of it. A set of a reservation some
    /// hundreds long, built for every question, was much of the time
    /// traffic control took. In resource order the spans of each edge come
    /// together, in order along it, so they are found by their edge first.
    struct ReservedTrack {
        private let ordered: [TrackResource]
        private let unordered: Set<TrackResource>?
        /// In resource order: where the spans of each edge lie.
        let runs: EdgeTable<Range<Int>>
        /// In resource order: how many nodes come first.
        let nodeCount: Int
        /// The longest of its spans (0 without any).
        let longest: Int64

        init(_ reservation: [TrackResource]) {
            ordered = reservation
            var runs = EdgeTable<Range<Int>>()
            var nodeCount = 0
            var isOrdered = true
            var runStart = 0
            var runEdge: TrackEdgeID?
            var longest: Int64 = 0
            for index in reservation.indices {
                if index > 0, !(reservation[index - 1] < reservation[index]) {
                    isOrdered = false
                    break
                }
                switch reservation[index] {
                case .node:
                    nodeCount = index + 1
                case .span(let span):
                    longest = max(longest, span.length)
                    if span.edge != runEdge {
                        if let runEdge { runs.append(runEdge, runStart..<index) }
                        runEdge = span.edge
                        runStart = index
                    }
                }
            }
            if isOrdered, let runEdge { runs.append(runEdge, runStart..<reservation.count) }
            unordered = isOrdered ? nil : Set(reservation)
            self.runs = isOrdered ? runs : EdgeTable()
            self.nodeCount = isOrdered ? nodeCount : 0
            self.longest = longest
        }

        /// Whether it holds every span of `spans` (an edge's, in order
        /// along it) that shares a point with chainage `low` to `high` of an
        /// edge `length` long (see ``TrackCover``): walked along beside its
        /// own spans of the edge, and found by halving where they part.
        func containsAll(_ spans: [TrackSpan], from low: Int64, to high: Int64, length: Int64) -> Bool {
            // The edge's spans are in order and end in order.
            var (lower, upper) = (0, spans.count)
            while lower < upper {
                let middle = (lower + upper) / 2
                if spans[middle].end < low {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            var next: Int?
            for span in spans[lower...] {
                guard span.start <= high else { break }
                guard TrackCover.covers(low, high, span, length: length) else { continue }
                if let index = next, index < ordered.count, ordered[index] == .span(span) {
                    next = index + 1
                    continue
                }
                guard let index = index(of: .span(span)) else { return false }
                next = index + 1
            }
            return true
        }

        /// Where `resource` is in it, or `nil`; out of order, the end
        /// index if it holds it.
        private func index(of resource: TrackResource) -> Int? {
            if let unordered { return unordered.contains(resource) ? ordered.count : nil }
            let range: Range<Int>
            switch resource {
            case .node: range = 0..<nodeCount
            case .span(let span):
                guard let run = runs[span.edge] else { return nil }
                range = run
            }
            var (low, high) = (range.lowerBound, range.upperBound)
            while low < high {
                let middle = (low + high) / 2
                if ordered[middle] < resource {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low < range.upperBound && ordered[low] == resource ? low : nil
        }

        /// The spans of edge `edge`, in order, that may share a point with
        /// chainage `low` to `high` of it (the rest cannot): in resource
        /// order, from the first that starts no more than its longest span
        /// before `low`, to the last that starts at `high` or before; `nil`
        /// out of order.
        func spans(of edge: TrackEdgeID, from low: Int64, to high: Int64) -> ArraySlice<TrackResource>? {
            guard isOrdered else { return nil }
            guard let run = runs[edge] else { return [] }
            func first(startingAfter limit: Int64, orAt: Bool) -> Int {
                var (lower, upper) = (run.lowerBound, run.upperBound)
                while lower < upper {
                    let middle = (lower + upper) / 2
                    guard case .span(let span) = ordered[middle] else { preconditionFailure("a run holds spans") }
                    if span.start < limit || (orAt && span.start == limit) {
                        lower = middle + 1
                    } else {
                        upper = middle
                    }
                }
                return lower
            }
            let from = first(startingAfter: low - longest, orAt: false)
            let to = first(startingAfter: high, orAt: true)
            return from < to ? ordered[from..<to] : []
        }

        /// Whether the reservation is in resource order, without repeats.
        var isOrdered: Bool { unordered == nil }

        func contains(_ resource: TrackResource) -> Bool {
            index(of: resource) != nil
        }
    }

    /// The track a train holds (see ``held(_:)``), to ask a resource at a
    /// time.
    struct HeldTrack {
        /// What it stands on and the junctions its body fouls.
        let body: Set<TrackResource>
        let reservation: [TrackResource]
        let reserved: ReservedTrack

        func contains(_ resource: TrackResource) -> Bool {
            body.contains(resource) || reserved.contains(resource)
        }

        /// All of it, some perhaps twice.
        var resources: [TrackResource] { Array(body) + reservation }
    }

    func heldTrack(_ train: Train) -> HeldTrack {
        heldTrack(train, reserved: ReservedTrack(train.reservation))
    }

    /// ``heldTrack(_:)`` knowing its reservation as a ``ReservedTrack``.
    func heldTrack(_ train: Train, reserved: ReservedTrack) -> HeldTrack {
        let body = bodyStretches(of: train)
        var standing = Set(resources(covering: body))
        standing.formUnion(foulingNodes(covering: body))
        return HeldTrack(body: standing, reservation: train.reservation, reserved: reserved)
    }

    /// `train`'s reservation as a ``ReservedTrack``, kept in `memo` while
    /// the reservation stays the same: as a train moves on, it often
    /// releases nothing.
    func reservedTrack(of train: Train, memo: inout DirectionMemo) -> ReservedTrack {
        if let known = memo.reserved[train.id], known.reservation == train.reservation { return known.reserved }
        let reserved = ReservedTrack(train.reservation)
        memo.reserved[train.id] = (train.reservation, reserved)
        return reserved
    }

    /// The route envelope of `train`, which follows another, from the
    /// envelopes its authority was found from (see ``authority(of:memo:)``):
    /// `cover(of: bodyStretches(of: train) + envelopes.stretches)`, kept in
    /// `memo` by the train as it is (a few of its last values).
    func followingCover(of train: Train, _ envelopes: AuthorityEnvelopes, memo: inout DirectionMemo) -> TrackCover {
        if let known = memo.followingCovers[train.id]?.first(where: { $0.train == train }) { return known.cover }
        let cover = cover(of: bodyStretches(of: train) + envelopes.stretches)
        var known = memo.followingCovers[train.id] ?? []
        known.insert((train, cover), at: 0)
        if known.count > 4 { known.removeLast() }
        memo.followingCovers[train.id] = known
        return cover
    }

    /// ``heldTrack(_:)`` kept in `memo`, by the train as it is: it depends
    /// on nothing else but the network (see ``authority(of:memo:)``).
    func heldTrack(_ train: Train, memo: inout DirectionMemo) -> HeldTrack {
        if let known = memo.heldTracks[train.id]?.first(where: { $0.train == train }) { return known.held }
        let held = heldTrack(train, reserved: reservedTrack(of: train, memo: &memo))
        var known = memo.heldTracks[train.id] ?? []
        known.insert((train, held), at: 0)
        if known.count > 4 { known.removeLast() }
        memo.heldTracks[train.id] = known
        return held
    }

    /// What following a train ahead claims (see ``claim(of:)``): its whole
    /// route envelope, and of that what no other train holds, which it
    /// waits for (see ``TrackHolders/waits(_:for:)``). The route is kept as
    /// its stretches (see ``TrackCover``), rather than all the thousands of
    /// spans of a long leg gathered into a set.
    struct Claim {
        /// The train that follows.
        let train: TrainID
        /// Its route envelope.
        let cover: TrackCover
        /// The spans it waits for that foul spans of other edges (see
        /// ``RailwayNetwork/foulingSpans``).
        var foulingWaiting: [TrackSpan] = []
        /// Decision 808: the track it comes to rest on (and fouls there)
        /// when the call it travels to is the last of its timetable, an
        /// empty run's or a service's; empty for any other train.
        var rest: [TrackResource] = []

        /// Whether `resource` is on its route.
        func routeContains(_ resource: TrackResource) -> Bool {
            cover.contains(resource)
        }

        /// Every resource of its route, gathered.
        var route: Set<TrackResource> {
            Set(cover.resources)
        }
    }

    /// Places of trains in ``TrackHolders``, in order, the first kept
    /// without an array: most track has one holder, and an array for each
    /// was much of the time the holders took to work out.
    struct Places: Sequence {
        private var first: Int?
        private var more: [Int] = []

        var isEmpty: Bool { first == nil }

        /// Adds `place`, keeping the places in order: after any it has
        /// that are the same.
        mutating func insert(_ place: Int) {
            guard let first else {
                first = place
                return
            }
            if place < first {
                more.insert(first, at: 0)
                self.first = place
                return
            }
            var index = more.count
            while index > 0, more[index - 1] > place { index -= 1 }
            more.insert(place, at: index)
        }

        /// Takes `place` out, however often it has it.
        mutating func remove(_ place: Int) {
            more.removeAll { $0 == place }
            if first == place {
                first = more.first
                if !more.isEmpty { more.removeFirst() }
            }
        }

        struct Iterator: IteratorProtocol {
            let places: Places
            var index = -1

            mutating func next() -> Int? {
                defer { index += 1 }
                return index < 0 ? places.first : index < places.more.count ? places.more[index] : nil
            }
        }

        func makeIterator() -> Iterator {
            Iterator(places: self)
        }
    }

    /// What every train holds (see ``held(_:)``) and, following another,
    /// claims (see ``claim(of:)``), worked out once to ask
    /// ``holder(of:except:holders:)`` and
    /// ``blockedTrack(except:holders:)`` of many trains of one world:
    /// who holds each resource is found from where it is, not by asking
    /// every train.
    struct TrackHolders {
        /// The trains' IDs, in the world's order.
        let ids: [TrainID]
        fileprivate(set) var held: [TrainID: HeldTrack]
        fileprivate(set) var claims: [TrainID: Claim]
        /// By a train's place in ``ids``: what it holds, and, when it is
        /// placed, the spans of that which foul others.
        var tracks: [HeldTrack?]
        var fouling: [[TrackSpan]]
        /// The placed trains holding each resource of their bodies, and
        /// each node, and each resource of a reservation out of order, by
        /// place, in order (perhaps twice).
        var owners: [TrackResource: Places]
        /// The placed trains whose reservation, in order, holds spans of
        /// each edge, by place, in order.
        var runs: [TrackEdgeID: [Int]]
        /// The spans of each edge that foul spans of others, in order.
        let foulingByEdge: [TrackEdgeID: [TrackSpan]]
        /// The spans of each edge the placed trains stand on, with their
        /// places.
        var bodies: [TrackEdgeID: [(place: Int, span: TrackSpan)]]
        /// The places of placed trains whose reservation is out of order.
        var unordered: [Int]
        /// By a following train: the trains its claim does not bind (see
        /// ``binds(_:_:)``), because they hold or foul the track a train
        /// it follows needs.
        fileprivate(set) var released: [TrainID: Set<TrainID>] = [:]
        /// Decision 877: whether whom the claims do not bind was read from
        /// the time as well as the trains (decisions 836 and 850: whether
        /// a departure is due). Such holders are the world's only at the
        /// time they were settled for (see ``GameWorld/trackHolders(memo:)``).
        var readsTheTime = false

        /// TICK-L1 (`docs/research/TICK_L1_2026-11-13.md`): the train at
        /// `place` now holds `track` (`placed`: whether it is on the track
        /// at all), the other trains what they
        /// did. Only what that train held and holds is touched, and every
        /// list stays as working all of it out again would leave it. The
        /// claims are not: see ``GameWorld/settleClaims(_:covers:)``.
        mutating func replace(_ place: Int, with track: HeldTrack, placed: Bool, in network: RailwayNetwork) {
            if let old = tracks[place] { remove(old, at: place) }
            held[ids[place]] = track
            tracks[place] = placed ? track : nil
            fouling[place] = placed ? add(track, at: place, in: network) : []
        }

        /// Adds what the placed train at `place` holds, `track`, after what
        /// the trains before it hold and before what the trains after it
        /// do, and returns the spans of it that foul others.
        mutating func add(_ track: HeldTrack, at place: Int, in network: RailwayNetwork) -> [TrackSpan] {
            for resource in track.body {
                owners[resource, default: Places()].insert(place)
                if case .span(let span) = resource {
                    var index = bodies[span.edge]?.count ?? 0
                    while index > 0, bodies[span.edge]![index - 1].place > place { index -= 1 }
                    bodies[span.edge, default: []].insert((place, span), at: index)
                }
            }
            var foulingHeld = track.body.compactMap { resource -> TrackSpan? in
                guard case .span(let span) = resource, network.foulingSpans[span] != nil else { return nil }
                return span
            }
            if track.reserved.isOrdered {
                for resource in track.reservation[..<track.reserved.nodeCount] {
                    owners[resource, default: Places()].insert(place)
                }
                for edge in track.reserved.runs.edges {
                    Self.insert(place, into: &runs[edge, default: []])
                    for span in foulingByEdge[edge] ?? [] where track.reserved.contains(.span(span)) {
                        foulingHeld.append(span)
                    }
                }
            } else {
                Self.insert(place, into: &unordered)
                for resource in Set(track.reservation) {
                    owners[resource, default: Places()].insert(place)
                    if case .span(let span) = resource, network.foulingSpans[span] != nil { foulingHeld.append(span) }
                }
            }
            return foulingHeld
        }

        /// Takes out what the train at `place` held, `track` (see
        /// ``add(_:at:in:)``).
        private mutating func remove(_ track: HeldTrack, at place: Int) {
            func disown(_ resource: TrackResource) {
                guard let index = owners.index(forKey: resource) else { return }
                owners.values[index].remove(place)
                if owners.values[index].isEmpty { owners.remove(at: index) }
            }
            for resource in track.body {
                disown(resource)
                if case .span(let span) = resource, let index = bodies.index(forKey: span.edge) {
                    bodies.values[index].removeAll { $0.place == place }
                    if bodies.values[index].isEmpty { bodies.remove(at: index) }
                }
            }
            if track.reserved.isOrdered {
                for resource in track.reservation[..<track.reserved.nodeCount] {
                    disown(resource)
                }
                for edge in track.reserved.runs.edges {
                    guard let index = runs.index(forKey: edge) else { continue }
                    runs.values[index].removeAll { $0 == place }
                    if runs.values[index].isEmpty { runs.remove(at: index) }
                }
            } else {
                unordered.removeAll { $0 == place }
                for resource in track.reservation {
                    disown(resource)
                }
            }
        }

        /// Adds `place` to `places`, kept in order, after any that are the
        /// same.
        private static func insert(_ place: Int, into places: inout [Int]) {
            var index = places.count
            while index > 0, places[index - 1] > place { index -= 1 }
            places.insert(place, at: index)
        }

        /// Whether these are the holders `other` is, to check
        /// ``replace(_:with:placed:in:)`` against working them all out
        /// (tests only): the same lists in the same order, but for the
        /// order a set gave the track of one train.
        func matches(_ other: TrackHolders) -> Bool {
            func same(_ a: HeldTrack?, _ b: HeldTrack?) -> Bool {
                guard let a, let b else { return a == nil && b == nil }
                return a.body == b.body && a.reservation == b.reservation
            }
            func same(_ a: TrackCover, _ b: TrackCover) -> Bool {
                a.matches(b)
            }
            guard ids == other.ids, unordered == other.unordered, runs == other.runs, released == other.released,
                  held.count == other.held.count, held.allSatisfy({ same($0.value, other.held[$0.key]) }),
                  zip(tracks, other.tracks).allSatisfy({ same($0, $1) }),
                  zip(fouling, other.fouling).allSatisfy({ $0.sorted() == $1.sorted() }),
                  owners.count == other.owners.count,
                  owners.allSatisfy({ entry in other.owners[entry.key].map { Array($0) == Array(entry.value) } ?? false }),
                  bodies.count == other.bodies.count, claims.count == other.claims.count
            else { return false }
            for (edge, standing) in bodies {
                guard let others = other.bodies[edge], standing.count == others.count else { return false }
                let order: ((place: Int, span: TrackSpan), (place: Int, span: TrackSpan)) -> Bool = { ($0.place, $0.span) < ($1.place, $1.span) }
                guard zip(standing.sorted(by: order), others.sorted(by: order)).allSatisfy({ $0.place == $1.place && $0.span == $1.span }),
                      standing.map(\.place) == others.map(\.place)
                else { return false }
            }
            return claims.allSatisfy { id, claim in
                other.claims[id].map { $0.train == claim.train && $0.foulingWaiting == claim.foulingWaiting && same($0.cover, claim.cover) } ?? false
            }
        }

        /// Whether the train at `place` is placed, is not `id` and, given
        /// `among`, is one of those.
        private func isOther(_ place: Int, _ id: TrainID, _ among: Set<TrainID>?) -> Bool {
            tracks[place] != nil && ids[place] != id && among?.contains(ids[place]) != false
        }

        /// The first place of a placed train other than `id` (of `among`,
        /// given) that holds track `cover` covers (see ``TrackCover``), or
        /// holds track fouling it, if `fouling`.
        func firstHolding(_ cover: TrackCover, except id: TrainID, among: Set<TrainID>?, fouling: Bool, in network: RailwayNetwork) -> Int? {
            var first = ids.count
            for node in cover.nodes {
                for place in owners[node] ?? Places() where place < first && isOther(place, id, among) {
                    first = place
                }
            }
            // A reservation out of order.
            for place in unordered where place < first && isOther(place, id, among) {
                if tracks[place]!.reservation.contains(where: cover.contains) {
                    first = place
                    break
                }
            }
            // What they stand on, and reservations in order, by the edges
            // the cover lies on.
            for edge in cover.edges {
                for body in bodies[edge] ?? [] where body.place < first && isOther(body.place, id, among) && cover.contains(.span(body.span)) {
                    first = body.place
                }
                guard let holding = runs[edge], let bounds = cover.bounds(on: edge) else { continue }
                for place in holding where place < first && isOther(place, id, among) {
                    if tracks[place]!.reserved.spans(of: edge, from: bounds.low, to: bounds.high)!.contains(where: cover.contains) {
                        first = place
                        break
                    }
                }
            }
            if fouling {
                for place in 0..<first where isOther(place, id, among) {
                    if self.fouling[place].contains(where: { network.foulingSpans[$0]!.contains { cover.contains(.span($0)) } }) {
                        first = place
                        break
                    }
                }
            }
            return first < ids.count ? first : nil
        }

        /// By place: whether a placed train other than `id` holds track
        /// `cover` covers, or holds track fouling it, if `fouling`. Each is
        /// asked as ``firstHolding(_:except:among:fouling:in:)`` asks it of
        /// that train alone, all in one pass.
        func holding(_ cover: TrackCover, except id: TrainID, fouling: Bool, in network: RailwayNetwork) -> [Bool] {
            var holding = tracks.indices.map { _ in false }
            for node in cover.nodes {
                for place in owners[node] ?? Places() where isOther(place, id, nil) {
                    holding[place] = true
                }
            }
            for place in unordered where !holding[place] && isOther(place, id, nil) {
                if tracks[place]!.reservation.contains(where: cover.contains) { holding[place] = true }
            }
            for edge in cover.edges {
                for body in bodies[edge] ?? [] where !holding[body.place] && isOther(body.place, id, nil) && cover.contains(.span(body.span)) {
                    holding[body.place] = true
                }
                guard let held = runs[edge], let bounds = cover.bounds(on: edge) else { continue }
                for place in held where !holding[place] && isOther(place, id, nil) {
                    if tracks[place]!.reserved.spans(of: edge, from: bounds.low, to: bounds.high)!.contains(where: cover.contains) {
                        holding[place] = true
                    }
                }
            }
            if fouling {
                for place in tracks.indices where !holding[place] && isOther(place, id, nil) {
                    if self.fouling[place].contains(where: { network.foulingSpans[$0]!.contains { cover.contains(.span($0)) } }) {
                        holding[place] = true
                    }
                }
            }
            return holding
        }

        /// Whether `claim`'s train waits for track `cover` covers.
        func waits(_ claim: Claim, forAnyIn cover: TrackCover) -> Bool {
            if cover.nodes.contains(where: { waits(claim, for: $0) }) { return true }
            for edge in cover.edges {
                guard let ours = cover.bounds(on: edge), let theirs = claim.cover.bounds(on: edge) else { continue }
                // A span both cover starts by the lower of their ends and
                // ends by the higher of their starts.
                let (low, high) = (max(ours.low, theirs.low), min(ours.high, theirs.high))
                // ``isHeld(_:except:among:)`` of each span, in order: the
                // other trains' reservations in order on the edge are walked
                // beside them, rather than each span found by halving.
                var reserved: [(spans: ArraySlice<TrackResource>, next: Int)] = []
                for place in runs[edge] ?? [] where ids[place] != claim.train {
                    let spans = tracks[place]!.reserved.spans(of: edge, from: low, to: high)!
                    reserved.append((spans, spans.startIndex))
                }
                if cover.anySpan(of: edge, from: low, to: high, where: { span in
                    let resource = TrackResource.span(span)
                    guard claim.routeContains(resource) else { return false }
                    if owners[resource]?.contains(where: { ids[$0] != claim.train }) == true { return false }
                    for index in reserved.indices {
                        while reserved[index].next < reserved[index].spans.endIndex, reserved[index].spans[reserved[index].next] < resource {
                            reserved[index].next += 1
                        }
                        if reserved[index].next < reserved[index].spans.endIndex, reserved[index].spans[reserved[index].next] == resource { return false }
                    }
                    return true
                }) {
                    return true
                }
            }
            return false
        }

        /// The first train other than `id` holding, fouling or waiting for
        /// track `cover` covers, as ``holder(of:except:holders:)`` asks.
        func firstHolder(of cover: TrackCover, except id: TrainID, in network: RailwayNetwork) -> TrainID? {
            var first = firstHolding(cover, except: id, among: nil, fouling: true, in: network) ?? ids.count
            for place in 0..<first where isOther(place, id, nil) {
                guard let claim = claims[ids[place]], binds(claim, id) else { continue }
                if waits(claim, forAnyIn: cover)
                    || claim.foulingWaiting.contains(where: { network.foulingSpans[$0]!.contains { cover.contains(.span($0)) } }) {
                    first = place
                    break
                }
            }
            return first < ids.count ? ids[first] : nil
        }

        /// Whether train `id` holds any of `claim`'s route, which keeps it
        /// from waiting for that claim (see ``holder(of:except:)``).
        func holdsAny(of claim: Claim, _ id: TrainID) -> Bool {
            guard let own = held[id] else { return false }
            if own.body.contains(where: claim.routeContains) { return true }
            guard own.reserved.isOrdered else { return own.reservation.contains(where: claim.routeContains) }
            // In order: its nodes, and of its spans those of the edges the
            // route lies on that may share a point with it (the rest
            // cannot).
            if own.reservation[..<own.reserved.nodeCount].contains(where: claim.routeContains) { return true }
            for edge in claim.cover.edges where own.reserved.runs[edge] != nil {
                guard let bounds = claim.cover.bounds(on: edge) else { continue }
                if own.reserved.spans(of: edge, from: bounds.low, to: bounds.high)!.contains(where: claim.routeContains) { return true }
            }
            return false
        }

        /// Whether `claim`, the track a following train waits for, keeps
        /// train `id` from it (decision 56, point 6): unless `id` holds any
        /// of its route (it is the train ahead), or `id` follows a train
        /// too and goes first (see ``goesFirst(_:before:)``). Two
        /// following trains whose routes meet would otherwise each wait
        /// for the track the other waits for, and neither ever go on. Nor
        /// (decision 308) when `id` holds or fouls track a train it
        /// follows needs (one holding some of its route): the train
        /// ahead waits for `id`, so `id` must go on first.
        func binds(_ claim: Claim, _ id: TrainID) -> Bool {
            !holdsAny(of: claim, id) && !goesFirst(id, before: claim) && released[claim.train]?.contains(id) != true
        }

        /// Whether train `id`, following a train too, goes before
        /// `claim`'s train where their routes meet. Decision 808: of the
        /// two, one whose timetable ends where it comes to rest on the
        /// other's route (an empty run, or a service at its last call)
        /// goes after one that does not end on its route: it would stand
        /// there, in the way of a train that only calls and goes on.
        /// When neither does, or both do, the lower ID goes first, as
        /// before.
        private func goesFirst(_ id: TrainID, before claim: Claim) -> Bool {
            guard let own = claims[id] else { return false }
            let ends = own.rest.contains(where: claim.routeContains)
            if ends != claim.rest.contains(where: own.routeContains) { return !ends }
            return id < claim.train
        }

        /// These holders but for the claims of `followers` (decision 577):
        /// the track those trains wait for no longer keeps any train from
        /// it. What every train holds stays as it was.
        func ignoringClaims(of followers: Set<TrainID>) -> TrackHolders {
            var holders = TrackHolders(
                ids: ids, held: held, claims: claims.filter { !followers.contains($0.key) }, tracks: tracks, fouling: fouling, owners: owners,
                runs: runs, foulingByEdge: foulingByEdge, bodies: bodies, unordered: unordered
            )
            holders.released = released
            return holders
        }

        /// Whether `claim`'s train waits for `resource`: it is on its route
        /// and no other placed train holds it.
        func waits(_ claim: Claim, for resource: TrackResource) -> Bool {
            claim.routeContains(resource) && !isHeld(resource, except: claim.train, among: nil)
        }

        /// What train `id`, following another, waits for (see ``claim(of:)``),
        /// gathered; `nil` when it follows no train.
        func waiting(of id: TrainID) -> Set<TrackResource>? {
            claims[id].map { claim in claim.route.filter { !isHeld($0, except: id, among: nil) } }
        }

        /// Whether track `claim`'s train waits for is any of `resources`, or
        /// fouls any of them (see ``RailwayNetwork/fouls(_:_:)``).
        func waits(_ claim: Claim, forAnyOf resources: Set<TrackResource>, in network: RailwayNetwork) -> Bool {
            if resources.contains(where: { waits(claim, for: $0) }) { return true }
            return claim.foulingWaiting.contains { network.foulingSpans[$0]!.contains { resources.contains(.span($0)) } }
        }

        /// Whether a placed train other than `id` (and, given `among`, one
        /// of those) holds `resource`.
        func isHeld(_ resource: TrackResource, except id: TrainID, among: Set<TrainID>?) -> Bool {
            func other(_ place: Int) -> Bool {
                ids[place] != id && among?.contains(ids[place]) != false
            }
            if owners[resource]?.contains(where: other) == true { return true }
            guard case .span(let span) = resource, let holding = runs[span.edge] else { return false }
            return holding.contains { other($0) && tracks[$0]!.reserved.contains(resource) }
        }

        /// The first place, below `limit`, of a placed train other than
        /// `id` holding `resource`.
        func firstHolder(of resource: TrackResource, except id: TrainID, below limit: Int) -> Int? {
            var first: Int?
            for place in owners[resource] ?? Places() where place < (first ?? limit) && ids[place] != id {
                first = place
            }
            if case .span(let span) = resource, let holding = runs[span.edge] {
                for place in holding where place < (first ?? limit) && ids[place] != id && tracks[place]!.reserved.contains(resource) {
                    first = place
                    break
                }
            }
            return first
        }
    }

    func trackHolders() -> TrackHolders {
        trackHolders(authorities: trains.map(authority))
    }

    /// The world's track holders (see ``trackHolders()``), kept in `memo`
    /// for as long as the trains stay as they are. Within one memo the
    /// network and traffic control do not change (a memo lives for one
    /// ``advance(ticks:)`` or one question), and a train's holding depends
    /// on nothing else. When a few trains are not the same, the last
    /// holders are changed for those trains alone (see
    /// ``trackHolders(changedAt:memo:)``); when many are, they are worked
    /// out again from every train, and the last two sets of trains asked
    /// about are kept.
    func trackHolders(memo: inout DirectionMemo) -> TrackHolders {
        // TICK-L1 (`docs/research/TICK_L1_2026-11-13.md`): when a few
        // trains are not as the last holders had them (one set off, one
        // was given more of its route), only what
        // those hold is worked out again.
        if !memo.holders.isEmpty, memo.holders[0].trains.count == trains.count {
            let limit = max(1, trains.count / 4)
            var changed: [Int] = []
            for place in trains.indices where memo.holders[0].trains[place] != trains[place] {
                changed.append(place)
                if changed.count > limit { break }
            }
            if changed.isEmpty { return keptHolders(memo: &memo) }
            if changed.count <= limit, changed.allSatisfy({ memo.holders[0].trains[$0].id == trains[$0].id }) {
                return trackHolders(changedAt: changed, memo: &memo)
            }
        }
        if let index = memo.holders.indices.dropFirst().first(where: { memo.holders[$0].trains == trains }) {
            memo.holders.insert(memo.holders.remove(at: index), at: 0)
            memo.holderChanges += 1
            return keptHolders(memo: &memo)
        }
        let worked = workedOutHolders(memo: &memo)
        memo.holders.insert((trains, worked.covers, worked.holders, clock.now), at: 0)
        if memo.holders.count > 2 { memo.holders.removeLast() }
        memo.holderChanges += 1
        Self.holderAudit?.rebuilds += 1
        return worked.holders
    }

    /// Decision 877: the first holders kept in `memo`, whose trains are
    /// the world's, as the world's holders now. Whom a claim does not bind
    /// can depend on the time as well as on the trains (decisions 836 and
    /// 850: an empty run's claim does not bind a train whose departure is
    /// due), and a memo lives through many seconds of one
    /// ``advance(ticks:)``: holders settled a second before a departure
    /// fell due, as a step ended, were given again at the start of the
    /// next, the trains being the same, and the train due stayed bound.
    /// With every other train standing too (a line at night) nothing
    /// changed the trains again, so it stayed bound for the rest of the
    /// call: ten minutes at the top speed, where a call a minute settled
    /// them again at the next minute, and a batch no longer ended where
    /// its minutes do. So holders that read the time are settled again
    /// when it is no longer the time they were settled for.
    func keptHolders(memo: inout DirectionMemo) -> TrackHolders {
        guard memo.holders[0].holders.readsTheTime, memo.holders[0].at != clock.now, Self.holderAudit?.keepsStaleClaims != true else {
            return memo.holders[0].holders
        }
        var entry = memo.holders.removeFirst()
        let before = Self.holderAudit == nil ? nil : entry.holders.released
        settleClaims(&entry.holders, covers: entry.covers)
        entry.at = clock.now
        memo.holders.insert(entry, at: 0)
        memo.holderChanges += 1
        if let audit = Self.holderAudit, let before {
            audit.settledAgain += 1
            if before != entry.holders.released { audit.staleClaims.append(clock.now) }
        }
        return entry.holders
    }

    /// The world's track holders worked out from every train, each train's
    /// part kept in `memo` by the train as it is, with the route envelope
    /// of every train that follows another, by place.
    func workedOutHolders(memo: inout DirectionMemo) -> (covers: [TrackCover?], holders: TrackHolders) {
        var authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?] = []
        var tracks: [HeldTrack] = []
        var covers: [TrackCover?] = []
        for train in trains {
            let authority = authority(of: train, memo: &memo)
            authorities.append(authority)
            tracks.append(heldTrack(train, memo: &memo))
            // With block sections a following train claims nothing more
            // than it holds (decision 212), so its route envelope is not
            // read.
            covers.append(blockSections ? nil : authority.flatMap { authority in
                claimCover(of: train, authority) { followingCover(of: train, authority.envelopes, memo: &memo) }
            })
        }
        if memo.foulingByEdge == nil { memo.foulingByEdge = network.foulingSpans.isEmpty ? [:] : foulingSpansByEdge() }
        return (covers, trackHolders(authorities: authorities, tracks: tracks, covers: covers, foulingByEdge: memo.foulingByEdge!))
    }

    /// ``trackHolders(memo:)`` from the last holders in `memo`, whose
    /// trains are the world's but for those at `changed` (TICK-L1,
    /// `docs/research/TICK_L1_2026-11-13.md`):
    /// what those held is taken out and what they hold now put in, and the
    /// claims, which depend on every train, worked out again. The last
    /// holders are changed in place and not kept as they were: what is
    /// kept changes no answer, only how long one takes.
    func trackHolders(changedAt changed: [Int], memo: inout DirectionMemo) -> TrackHolders {
        var entry = memo.holders.removeFirst()
        for place in changed {
            let train = trains[place]
            let authority = authority(of: train, memo: &memo)
            let track = heldTrack(train, memo: &memo)
            entry.covers[place] = blockSections ? nil : authority.flatMap { authority in
                claimCover(of: train, authority) { followingCover(of: train, authority.envelopes, memo: &memo) }
            }
            entry.holders.replace(place, with: track, placed: train.position != nil, in: network)
            entry.trains[place] = train
        }
        if !blockSections { settleClaims(&entry.holders, covers: entry.covers) }
        entry.at = clock.now
        memo.holders.insert(entry, at: 0)
        memo.holderChanges += 1
        if let audit = Self.holderAudit {
            audit.updates += 1
            precondition(audit.countsOnly || entry.holders.matches(workedOutHolders(memo: &memo).holders), "the holders changed in place are not the holders worked out again")
        }
        return entry.holders
    }

    /// Tests only (TICK-L1, `docs/research/TICK_L1_2026-11-13.md`): counts
    /// how ``trackHolders(memo:)`` came
    /// by its answers, and has every answer changed in place checked
    /// against the holders worked out from every train. `nil` in the game.
    final class HolderAudit: @unchecked Sendable {
        var updates = 0
        var rebuilds = 0
        /// Decision 877: how often holders kept for the same trains were
        /// settled again for another time (see ``keptHolders(memo:)``),
        /// and the times at which that changed whom a claim binds.
        var settledAgain = 0
        var staleClaims: [GameTime] = []
        /// Decision 877: keeps such holders as they were settled, as the
        /// game did before it, to tell what settling them again changes.
        var keepsStaleClaims = false
        /// Only counts, without checking each answer changed in place
        /// against one worked out again: for whole days of a large game,
        /// where that check is most of the time.
        var countsOnly = false
    }

    @TaskLocal static var holderAudit: HolderAudit?

    /// The spans of each edge that foul spans of others (see
    /// ``RailwayNetwork/foulingSpans``), in order.
    func foulingSpansByEdge() -> [TrackEdgeID: [TrackSpan]] {
        var byEdge: [TrackEdgeID: [TrackSpan]] = [:]
        for span in network.foulingSpans.keys {
            byEdge[span.edge, default: []].append(span)
        }
        return byEdge.mapValues { $0.sorted() }
    }

    /// ``trackHolders()`` knowing ``authority(of:)`` of every train, in
    /// order.
    func trackHolders(authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?]) -> TrackHolders {
        trackHolders(authorities: authorities, tracks: trains.map(heldTrack),
                     covers: zip(trains, authorities).map { train, authority in
                         authority.flatMap { authority in claimCover(of: train, authority) { cover(of: bodyStretches(of: train) + authority.envelopes.stretches) } }
                     },
                     foulingByEdge: network.foulingSpans.isEmpty ? [:] : foulingSpansByEdge())
    }

    /// ``trackHolders(authorities:)`` knowing ``heldTrack(_:)`` of every
    /// train, in order, the route envelope of every train that follows
    /// another (see ``followingCover(of:_:memo:)``), and
    /// ``foulingSpansByEdge()``.
    func trackHolders(authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?], tracks heldTracks: [HeldTrack],
                              covers: [TrackCover?], foulingByEdge: [TrackEdgeID: [TrackSpan]]) -> TrackHolders {
        // Room for every body's track at once: growing them was much of
        // the time.
        let standing = heldTracks.reduce(0) { $0 + $1.body.count }
        var holders = TrackHolders(
            ids: trains.map(\.id), held: [:], claims: [:], tracks: [], fouling: [], owners: [:], runs: [:], foulingByEdge: foulingByEdge,
            bodies: [:], unordered: []
        )
        holders.held.reserveCapacity(trains.count)
        holders.tracks.reserveCapacity(trains.count)
        holders.fouling.reserveCapacity(trains.count)
        holders.owners.reserveCapacity(standing)
        holders.bodies.reserveCapacity(standing)
        for (place, train) in trains.enumerated() {
            let track = heldTracks[place]
            holders.held[train.id] = track
            guard train.position != nil else {
                holders.tracks.append(nil)
                holders.fouling.append([])
                continue
            }
            holders.tracks.append(track)
            holders.fouling.append(holders.add(track, at: place, in: network))
        }
        // With block sections (decision 212) a following train holds only
        // what it has taken, and waits for nothing more.
        if !blockSections { settleClaims(&holders, covers: covers) }
        return holders
    }

    /// Works out the claims of `holders` again, and whom each does not
    /// bind, from what the trains hold in it and the route envelope of
    /// every train that follows another, `covers`, by place.
    func settleClaims(_ holders: inout TrackHolders, covers: [TrackCover?]) {
        holders.claims = [:]
        holders.released = [:]
        // Decision 877: whether any of what follows asked the time.
        var readsTheTime = false
        var claims: [TrainID: Claim] = [:]
        for (train, route) in zip(trains, covers) {
            // A following train's route envelope (see ``routeEnvelope(of:)``)
            // is the base and the track of every stretch; it waits for
            // the track of its route no other placed train holds.
            guard let route else { continue }
            var claim = Claim(train: train.id, cover: route)
            if case .travellingToStop(let stop, let cycle)? = train.execution, train.call(after: stop, cycle: cycle) == nil {
                let arrived = arrived(train)
                claim.rest = occupied(arrived) + foulingNodes(covering: bodyStretches(of: arrived))
            }
            if !network.foulingSpans.isEmpty {
                for edge in claim.cover.edges {
                    for span in holders.foulingByEdge[edge] ?? [] where holders.waits(claim, for: .span(span)) {
                        claim.foulingWaiting.append(span)
                    }
                }
            }
            claims[train.id] = claim
        }
        holders.claims = claims
        var released: [TrainID: Set<TrainID>] = [:]
        var paths = PathMemo()
        for (place, train) in trains.enumerated() {
            guard let claim = claims[train.id] else { continue }
            // TYMC-REBUILT-DEADLOCK: nor a train holding track that fouls
            // the claim's route: it is ahead as surely as one holding the
            // route itself (``TrackHolders/holdsAny(of:_:)``), and bound,
            // could not leave the track the claim's train waits for it to
            // leave.
            for (other, spans) in holders.fouling.enumerated() where other != place && !spans.isEmpty {
                if spans.contains(where: { network.foulingSpans[$0]!.contains { claim.routeContains(.span($0)) } }) {
                    released[train.id, default: []].insert(trains[other].id)
                }
            }
            // Decision 881, later (SANYING-0632): an empty run's claim
            // does not bind a train standing at an end of a line where the
            // empty run ends, its departure due: leaving, it frees a
            // platform the empty run comes to.
            if train.isDeadheading, let bound = destinationStation(of: train), isLineEnd(bound), arrivesLater(train) {
                readsTheTime = true
                for other in trains where other.id != train.id && isDueToLeave(other) {
                    if case .waitingAtStop(let stop, _)? = other.execution, other.timetable[stop].station == bound {
                        released[train.id, default: []].insert(other.id)
                    }
                }
            }
            for (ahead, isAhead) in holders.holding(claim.cover, except: train.id, fouling: false, in: network).enumerated() where isAhead {
                let leader = trains[ahead]
                let cover = claims[leader.id]?.cover ?? envelopeCover(of: leader)
                for (other, blocks) in holders.holding(cover, except: leader.id, fouling: true, in: network).enumerated() where blocks && other != place {
                    released[train.id, default: []].insert(trains[other].id)
                }
                // Decision 836: an empty run's claim does not bind a train
                // without a service standing where the service it follows
                // is due to go. Decision 850: nor a train standing there
                // whose own departure is due. Decision 886: a service's
                // claim does not bind a service standing there whose own
                // departure is due either (on the Taoyuan Airport MRT
                // rebuilt, an express behind a stopping train at Hengshan
                // claimed the points out of Linghang, past the train late
                // at Linghang the stopping train waited for); a train with
                // no service, or an empty run, it still binds.
                guard claims[leader.id] == nil else { continue }
                readsTheTime = true
                if let leaving = leavingCover(of: leader, memo: &paths) {
                    for (other, blocks) in holders.holding(leaving, except: leader.id, fouling: true, in: network).enumerated() where blocks && other != place {
                        let standing = trains[other]
                        let freed = train.isDeadheading
                            ? standing.execution == nil || isDueToLeave(standing)
                            : !standing.isDeadheading && isDueToLeave(standing)
                        if freed { released[train.id, default: []].insert(standing.id) }
                    }
                }
            }
        }
        holders.released = released
        holders.readsTheTime = readsTheTime
    }

    /// Decision 836: the track `train`, a service standing at a call whose
    /// departure is due, would cover leaving it along its default way (see
    /// ``leaving(_:stop:cycle:memo:)``), as ``settleClaims(_:covers:)``
    /// reads the route of a train any other follows (decision 886); `nil` for any other
    /// train, or with no way on. A train standing in the way of that
    /// departure (the leader waits for it) without a service of its own is
    /// not bound by the empty run's claim (only an empty run's, and only a
    /// train without a service: released for every following train, or
    /// every train in the way, the Taoyuan Airport MRT rebuilt line
    /// deadlocked 13 and 9 trains; decision 886: a service's claim, only
    /// for a service due to leave, as a train due binds none of an empty
    /// run's under decision 850): on Hong Kong's Tung Chung Line under the simple rules with
    /// traffic control an empty run to Siu Ho Wan, following a service
    /// waiting at Sunny Bay for the Tung Chung platform, claimed the
    /// crossover into the depot ten minutes ahead of itself, and the train
    /// on that platform waited for the crossover to leave it.
    func leavingCover(of train: Train, memo: inout PathMemo) -> TrackCover? {
        guard case .waitingAtStop(let stop, let cycle)? = train.execution, let due = departureDue(of: train), due <= clock.now,
              case .setsOff(let moved, _) = leaving(train, stop: stop, cycle: cycle, memo: &memo)
        else { return nil }
        return envelopeCover(of: moved)
    }

    /// Decision 881, later (SANYING-0632): the station of the last call
    /// `train` travels to, the end of its run; `nil` while it travels to
    /// any other call, or does not travel.
    func destinationStation(of train: Train) -> StationID? {
        guard case .travellingToStop(let stop, let cycle)? = train.execution, train.call(after: stop, cycle: cycle) == nil else { return nil }
        return train.timetable[stop].station
    }

    /// Decision 881, later: whether `train`, an empty run, is timetabled
    /// to reach the end of its run more than two minutes from now. Released
    /// for one due sooner, Hong Kong's Airport Express, Tung Chung and
    /// Disneyland Resort lines bought together ran 67 runs late instead of
    /// 62 under a new game's rules (a train at Hong Kong left a minute
    /// before the empty run came in behind the one it followed); held for
    /// one due within seven minutes, the Sanying Line's train at Yingtao
    /// Fude still waited.
    func arrivesLater(_ train: Train) -> Bool {
        guard case .travellingToStop(let stop, let cycle)? = train.execution else { return false }
        return train.scheduledArrival(of: stop, cycle: cycle).seconds > clock.now.seconds + 120
    }

    /// Decision 881, later: whether `station` is the first or last stop of
    /// a line with runs that is not a ring. Released at any station an
    /// empty run ends, a train without a service there too, the Taoyuan
    /// Airport MRT under a new game's rules deadlocked up to 28 trains;
    /// at the ends of lines, with a train without a service, 26.
    func isLineEnd(_ station: StationID) -> Bool {
        lines.contains { $0.hasRuns && !$0.isRing && ($0.stops.first == station || $0.stops.last == station) }
    }

    /// Decision 850: whether `train`, a service or an empty run, stands at
    /// a call with its departure due. An empty run's claim does not bind
    /// one standing where the service the empty run follows is due to go
    /// (see ``settleClaims(_:covers:)``): on Hong Kong's Tung Chung Line
    /// under the simple rules with traffic control an empty run from Hong
    /// Kong to Siu Ho Wan claimed the crossover into the depot from 25 km
    /// away; the train at Tung Chung, due for Hong Kong (or itself for the
    /// depot) over that crossover, waited for it, the service at Sunny Bay
    /// for its platform, and the empty run, through the trains between,
    /// for that one. Released for every due service wherever it stands,
    /// the Taoyuan Airport MRT sent out none of a day's 333 runs; for due
    /// services alone, an empty run due out of Tung Chung still stood.
    func isDueToLeave(_ train: Train) -> Bool {
        guard case .waitingAtStop? = train.execution, let due = departureDue(of: train) else { return false }
        return due <= clock.now
    }

    /// ``holder(of:except:)`` of the track `cover` covers (see
    /// ``TrackCover``), from `holders`, the world's.
    func holder(of cover: TrackCover, except id: TrainID, holders: TrackHolders) -> TrainID? {
        holders.firstHolder(of: cover, except: id, in: network)
    }

    /// ``holder(of:except:)`` from `holders`, the world's (see
    /// ``trackHolders()``): of the trains that hold any of `resources`,
    /// foul them or wait for them, the first.
    func holder(of resources: Set<TrackResource>, except id: TrainID, holders: TrackHolders) -> TrainID? {
        var first = holders.ids.count
        for resource in resources {
            if let place = holders.firstHolder(of: resource, except: id, below: first) { first = place }
        }
        // Track a placed train holds that fouls any of them.
        for place in 0..<first where holders.ids[place] != id && holders.tracks[place] != nil {
            if holders.fouling[place].contains(where: { network.foulingSpans[$0]!.contains { resources.contains(.span($0)) } }) {
                first = place
                break
            }
        }
        // Track a following train waits for.
        for place in 0..<first where holders.ids[place] != id && holders.tracks[place] != nil {
            guard let claim = holders.claims[holders.ids[place]], holders.binds(claim, id) else { continue }
            if holders.waits(claim, forAnyOf: resources, in: network) {
                first = place
                break
            }
        }
        return first < holders.ids.count ? holders.ids[first] : nil
    }

    /// ``blockedTrack(except:)``, to ask a resource at a time: what the
    /// placed trains other than `id` (of `among`, if given) hold, and what
    /// those that follow trains ahead wait for, unless train `id` holds
    /// track of their route.
    struct BlockedTrack {
        let holders: TrackHolders
        let id: TrainID
        let among: Set<TrainID>?
        let waiting: [Claim]

        func contains(_ resource: TrackResource) -> Bool {
            holders.isHeld(resource, except: id, among: among) || waiting.contains { holders.waits($0, for: resource) }
        }

        /// Whether no train keeps it from anything (asking nothing then is
        /// only quicker: every answer would be no).
        var isEmpty: Bool {
            waiting.isEmpty && !holders.ids.indices.contains { place in
                holders.tracks[place] != nil && holders.ids[place] != id && among?.contains(holders.ids[place]) != false
            }
        }

        /// Whether any of the track `cover` covers is blocked, or fouls
        /// track that is (see ``RailwayNetwork/fouls(_:_:)``).
        func blocks(_ cover: TrackCover, in network: RailwayNetwork) -> Bool {
            if holders.firstHolding(cover, except: id, among: among, fouling: false, in: network) != nil { return true }
            if waiting.contains(where: { holders.waits($0, forAnyIn: cover) }) { return true }
            // Its spans that foul others'.
            for edge in cover.edges {
                for span in holders.foulingByEdge[edge] ?? [] where cover.contains(.span(span)) {
                    if network.foulingSpans[span]!.contains(where: { contains(.span($0)) }) { return true }
                }
            }
            return false
        }

        /// All of it, gathered (see ``blockedTrack(except:)``).
        var resources: Set<TrackResource> {
            var resources: Set<TrackResource> = []
            for place in holders.ids.indices where holders.ids[place] != id && among?.contains(holders.ids[place]) != false {
                guard let track = holders.tracks[place] else { continue }
                resources.formUnion(track.body)
                resources.formUnion(track.reservation)
            }
            for claim in waiting {
                resources.formUnion(holders.waiting(of: claim.train)!)
            }
            return resources
        }
    }

    /// ``blockedTrack(except:)`` from `holders`, the world's (see
    /// ``trackHolders()``), of the trains `among` when given.
    func blockedTrack(except id: TrainID, among: Set<TrainID>? = nil, holders: TrackHolders) -> BlockedTrack {
        var waiting: [Claim] = []
        for (place, other) in holders.ids.enumerated() where other != id && holders.tracks[place] != nil && among?.contains(other) != false {
            if let claim = holders.claims[other], holders.binds(claim, id) {
                waiting.append(claim)
            }
        }
        return BlockedTrack(holders: holders, id: id, among: among, waiting: waiting)
    }

    /// The track `train` holds: what it stands on, the junctions its body
    /// fouls, and its reservation.
    func held(_ train: Train) -> Set<TrackResource> {
        // What it stands on (see ``occupied(_:)``) is what its body covers.
        let body = bodyStretches(of: train)
        var resources = Set(self.resources(covering: body))
        resources.formUnion(foulingNodes(covering: body))
        resources.formUnion(train.reservation)
        return resources
    }

    /// The track `train` needs for the rest of its route: everything its
    /// whole length covers from where its tail is now to where the route
    /// ends (what it stands on, and what its head passes over on the way;
    /// see ``routeStretches(of:)``), and every junction that stretch comes
    /// close enough to foul. `moves` is whether the route has any distance
    /// left, so that the train needs a reservation at all; a train that
    /// stands needs only its place. The resources are those of every moment
    /// of the journey together, by the same rule as occupancy.
    func routeEnvelope(of train: Train) -> (resources: Set<TrackResource>, moves: Bool) {
        guard train.position != nil else { return ([], false) }
        let body = bodyStretches(of: train)
        let route = routeStretches(of: train)
        var resources = Set(self.resources(covering: body))
        resources.formUnion(self.resources(covering: route.stretches))
        resources.formUnion(foulingNodes(covering: body + route.stretches))
        return (resources, route.moves)
    }

    /// The stretches `train`'s head still covers by itself, in order, and
    /// whether there is any distance in them: its route (see
    /// ``pathAhead(of:)``) as far as it can ever follow it: the rest of its
    /// edge, then the edges ahead it can enter, the last up to where the path
    /// ends (``TrainMovement/end``) or, with no path, or a path broken by a
    /// removed edge, to the end of the last edge it reaches: an edge that was
    /// removed never comes back.
    func routeStretches(of train: Train) -> (stretches: [TrackStretch], moves: Bool) {
        guard let position = train.position else { return ([], false) }
        let ahead = pathAhead(of: train)
        switch position {
        case .onEdge(let traversal, let offset):
            guard let length = network.length(ofEdge: traversal.edge) else { return ([], false) }
            // The path's own end holds only when the train can follow the
            // path to its last edge.
            let followed = ahead.count == train.movement.remainingEdges.count
            let lastStop = { (edgeLength: Int64) in followed ? (train.movement.end ?? edgeLength) : edgeLength }
            guard let last = ahead.last else {
                let stop = lastStop(length)
                return ([TrackStretch(traversal: traversal, from: offset, to: max(offset, stop))], stop > offset)
            }
            var stretches = [TrackStretch(traversal: traversal, from: offset, to: length)]
            for next in ahead.dropLast() {
                stretches.append(TrackStretch(traversal: next, from: 0, to: network.length(ofEdge: next.edge)!))
            }
            stretches.append(TrackStretch(traversal: last, from: 0, to: lastStop(network.length(ofEdge: last.edge)!)))
            return (stretches, true)
        }
    }

    /// Whether ``bodyStretches(of:)`` of `train` can have a stretch on
    /// any of `edges`: its stretches lie only on its head's edge and its
    /// trail edges. A check that works nothing out, before the stretches
    /// are (PERF-DEVICE 3: asked of every train for every travelling one).
    func bodyMayTouch(_ edges: Set<TrackEdgeID>, of train: Train) -> Bool {
        guard case .onEdge(let traversal, _)? = train.position else { return false }
        return edges.contains(traversal.edge) || train.trailEdges.contains { edges.contains($0) }
    }

    /// The stretches a train covers from its head back to its tail: the
    /// head's edge, then its body's, nearest first. Empty for an unplaced
    /// train.
    func bodyStretches(of train: Train) -> [TrackStretch] {
        guard case .onEdge(let traversal, let offset)? = train.position, network.edge(traversal.edge) != nil else { return [] }
        var stretches = [TrackStretch(traversal: traversal, from: max(0, offset - train.length), to: offset)]
        var remaining = train.length - offset
        for behind in trailTraversals(behind: traversal, trail: train.trailEdges) ?? [] where remaining > 0 {
            let length = network.edge(behind.edge)!.length
            stretches.append(TrackStretch(traversal: behind, from: max(0, length - remaining), to: length))
            remaining -= length
        }
        return stretches
    }
}
