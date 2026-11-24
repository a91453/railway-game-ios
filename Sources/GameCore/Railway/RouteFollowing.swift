// Route reservation (Phase 4.6 Stage T, ARCHITECTURE decision 32): following (Stage U2, decision 56).
// Moved from RouteReservation.swift unchanged (decision 910); the overview
// of route reservation is at the top of that file.

extension GameWorld {
    // MARK: - Following (Stage U2)

    /// How far short of the track the trains ahead hold a following train's
    /// authority ends (Stage U2): 25,600 units, 400 m, the Railway
    /// reference's `BLOCK_GAP_KM` (`index.html`), the distance it keeps a
    /// following train behind the one ahead on the same line.
    public static let followingGap: Int64 = 25_600

    /// The track `train` needs to go on `distance` along its route from
    /// where its head is (see ``routeStretches(of:)``): what it stands on,
    /// what its head passes over in that distance, and every junction all
    /// that comes close enough to foul. The whole route's is its route
    /// envelope (see ``routeEnvelope(of:)``).
    func authorityEnvelope(of train: Train, to distance: Int64) -> Set<TrackResource> {
        authorityEnvelope(authorityEnvelopes(of: train), to: distance)
    }

    /// ``authorityEnvelope(of:to:)`` of one train, to be asked at many
    /// distances: what does not depend on the distance is worked out once.
    /// The envelope to a distance is the base, the track of the stretches
    /// before the one it ends in whole (what each covers and the junctions
    /// it fouls), and that one as far as it goes.
    struct AuthorityEnvelopes {
        /// The train's route stretches (see ``routeStretches(of:)``).
        let stretches: [TrackStretch]
        /// How far from the head each stretch ends (saturating).
        let ends: [Int64]
        /// What the train stands on and the junctions its body fouls (a
        /// resource may be listed twice).
        let base: [TrackResource]

        /// The length of the route (see ``GameWorld/routeLength(of:)``).
        var length: Int64 { ends.last ?? 0 }
    }

    func authorityEnvelopes(of train: Train) -> AuthorityEnvelopes {
        authorityEnvelopes(of: train, along: routeStretches(of: train).stretches)
    }

    /// ``authorityEnvelopes(of:)`` with `train`'s route stretches already
    /// worked out.
    func authorityEnvelopes(of train: Train, along stretches: [TrackStretch]) -> AuthorityEnvelopes {
        let body = bodyStretches(of: train)
        let base = resources(covering: body) + foulingNodes(covering: body)
        var ends: [Int64] = []
        var end: Int64 = 0
        for stretch in stretches {
            let (sum, overflow) = end.addingReportingOverflow(stretch.to - stretch.from)
            end = overflow ? .max : sum
            ends.append(end)
        }
        return AuthorityEnvelopes(stretches: stretches, ends: ends, base: base)
    }

    /// The stretch the envelope to `distance` ends in (see
    /// ``authorityEnvelope(_:to:)``), its index, and how far into it the
    /// envelope goes: the first stretch always, even for no distance.
    /// - Precondition: `envelopes` has a stretch.
    func authorityEnd(_ envelopes: AuthorityEnvelopes, to distance: Int64) -> (index: Int, part: TrackStretch) {
        let index = envelopes.ends.firstIndex { distance <= $0 } ?? envelopes.stretches.count - 1
        let stretch = envelopes.stretches[index]
        let start = index == 0 ? 0 : envelopes.ends[index - 1]
        let length = min(stretch.to - stretch.from, max(distance - start, 0))
        return (index, TrackStretch(traversal: stretch.traversal, from: stretch.from, to: stretch.from + length))
    }

    /// ``authorityEnvelope(of:to:)`` from `envelopes`: the stretches before
    /// the one `distance` ends in whole, and that one as far as it goes
    /// (the first always, even for no distance).
    func authorityEnvelope(_ envelopes: AuthorityEnvelopes, to distance: Int64) -> Set<TrackResource> {
        var resources = Set(envelopes.base)
        guard !envelopes.stretches.isEmpty else { return resources }
        let end = authorityEnd(envelopes, to: distance)
        let stretches = Array(envelopes.stretches[..<end.index]) + [end.part]
        resources.formUnion(self.resources(covering: stretches))
        resources.formUnion(foulingNodes(covering: stretches))
        return resources
    }

    /// `reservation`, a following train's, with its envelope to `distance`
    /// (see ``authorityEnvelope(_:to:)``) added, in resource order without
    /// repeats: `Set(reservation).union(authorityEnvelope(envelopes, to:
    /// distance)).sorted()`. `held` is its authority (see
    /// ``authority(of:)``) and `envelopes` the envelopes it was found
    /// from: beyond 0 the reservation holds the envelope to `held` already,
    /// and the track of stretches is the track of their parts point by
    /// point (see ``resources(covering:)``), so only the base and the track
    /// from `held` on are gathered, and merged in beside the reservation.
    /// A reservation out of order is gathered whole, as before.
    func reservation(_ reservation: [TrackResource], extending envelopes: AuthorityEnvelopes, from held: Int64, to distance: Int64) -> [TrackResource] {
        let ordered = zip(reservation, reservation.dropFirst()).allSatisfy { $0 < $1 }
        guard ordered, !envelopes.stretches.isEmpty, envelopes.length < .max, held >= 0, held < distance else {
            return Set(reservation).union(authorityEnvelope(envelopes, to: distance)).sorted()
        }
        let first = authorityEnd(envelopes, to: held).index
        let end = authorityEnd(envelopes, to: distance)
        var pieces: [TrackStretch] = []
        for index in first...end.index {
            let stretch = index == end.index ? end.part : envelopes.stretches[index]
            let start = index == 0 ? 0 : envelopes.ends[index - 1]
            let from = min(stretch.from + max(0, held - start), stretch.to)
            pieces.append(TrackStretch(traversal: stretch.traversal, from: from, to: stretch.to))
        }
        let added = Set(envelopes.base + resources(covering: pieces) + foulingNodes(covering: pieces)).sorted()
        var merged: [TrackResource] = []
        merged.reserveCapacity(reservation.count + added.count)
        var (i, j) = (0, 0)
        while i < reservation.count, j < added.count {
            if reservation[i] < added[j] {
                merged.append(reservation[i])
                i += 1
            } else if added[j] < reservation[i] {
                merged.append(added[j])
                j += 1
            } else {
                merged.append(reservation[i])
                i += 1
                j += 1
            }
        }
        merged += reservation[i...]
        merged += added[j...]
        return merged
    }

    /// Whether the envelope to `distance` (see ``authorityEnvelope(_:to:)``)
    /// is clear, as ``longestAuthority(_:from:clearBase:clear:)`` asks it.
    func isAuthority(_ envelopes: AuthorityEnvelopes, to distance: Int64, clearBase: Bool, clear: (TrackStretch) -> Bool) -> Bool {
        guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
        let end = authorityEnd(envelopes, to: distance)
        return envelopes.stretches[..<end.index].allSatisfy(clear) && clear(end.part)
    }

    /// ``isAuthority(_:to:clearBase:clear:)``, knowing how many of the first
    /// stretches are clear whole.
    func isAuthority(
        _ envelopes: AuthorityEnvelopes, to distance: Int64, clear: (TrackStretch) -> Bool, clearBase: Bool, leading: Int
    ) -> Bool {
        guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
        let end = authorityEnd(envelopes, to: distance)
        guard end.index <= leading else { return false }
        return clear(end.part)
    }

    /// The longest distance from `low` to the end of the route whose
    /// envelope (see ``authorityEnvelope(_:to:)``) is clear, found by
    /// halving: `low` when no longer one is. `clearBase` is whether the
    /// base is clear, and `clear` whether the track of a stretch is (what
    /// it covers and the junctions it fouls). Being clear must hold of a set
    /// of track exactly when it holds of each part of it (as "held by the
    /// reservation" and "fouling nothing blocked" do), so each envelope is
    /// tried a part at a time (the base, the whole stretches before its
    /// end, and the part of the last), and never gathered.
    func longestAuthority(_ envelopes: AuthorityEnvelopes, from low: Int64, clearBase: Bool, clear: (TrackStretch) -> Bool) -> Int64 {
        // The stretches from the first that are clear whole.
        var leading = 0
        while clearBase, leading < envelopes.stretches.count, clear(envelopes.stretches[leading]) {
            leading += 1
        }
        var (low, high) = (low, envelopes.length)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if isAuthority(envelopes, to: middle, clear: clear, clearBase: clearBase, leading: leading) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// Whether `reservation` holds all the track of `stretch` (see
    /// ``resources(covering:)`` and ``foulingNodes(covering:)``), asked of
    /// the stretch on its edge rather than of each of its spans listed.
    func reserves(_ reservation: ReservedTrack, all stretch: TrackStretch) -> Bool {
        guard let edge = stretchFacts(of: stretch.traversal.edge) else { return true }
        let forward = stretch.traversal.direction == .forward
        if stretch.from == 0, !reservation.contains(.node(forward ? edge.from : edge.to)) { return false }
        if stretch.to == edge.length, !reservation.contains(.node(forward ? edge.to : edge.from)) { return false }
        guard foulingNodes(covering: [stretch]).allSatisfy(reservation.contains) else { return false }
        let (low, high) = forward ? (stretch.from, stretch.to) : (edge.length - stretch.to, edge.length - stretch.from)
        return reservation.containsAll(edge.spans, from: low, to: high, length: edge.length)
    }

    /// The reservation-held test of a stretch for a following train (see
    /// ``authority(of:)``) and the blocked test for one that would take
    /// more (see ``blockedTrack(except:)``): each asks a stretch whole.
    func clearOfBlocked(_ blocked: BlockedTrack) -> (base: ([TrackResource]) -> Bool, stretch: (TrackStretch) -> Bool) {
        // Decision 379: the first captures the network alone, not the
        // whole world, which each closure copied.
        let network = network
        return ({ !network.fouls($0, blocked.contains) }, { !blocked.blocks(cover(of: [$0]), in: network) })
    }

    /// How far along its route `train` has world units of its route
    /// envelope's length (see ``routeStretches(of:)``).
    func routeLength(of train: Train) -> Int64 {
        var left: Int64 = 0
        for stretch in routeStretches(of: train).stretches {
            let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
            left = overflow ? .max : sum
        }
        return left
    }

    /// How far `train`'s head may go on along its route under traffic
    /// control (its movement authority, Stage U2), or `nil` when it may go
    /// all the way: its reservation holds its whole route envelope, or
    /// traffic control is off, or it has no route. A train that follows
    /// another holds its route only part of the way: as far as the track
    /// its reservation holds it to (see ``authorityEnvelope(of:to:)``).
    /// Derived from the reservation, never saved.
    func authorityLeft(of train: Train) -> Int64? {
        authority(of: train)?.left
    }

    /// ``authorityLeft(of:)`` of a train that follows another, with the
    /// envelopes it was found from (see ``authorityEnvelopes(of:)``); `nil`
    /// for any other train.
    func authority(of train: Train) -> (left: Int64, envelopes: AuthorityEnvelopes)? {
        guard isTrafficControlEnabled, !train.reservation.isEmpty else { return nil }
        return authority(of: train, reserved: ReservedTrack(train.reservation))
    }

    /// ``authority(of:)`` knowing its reservation as a ``ReservedTrack``.
    func authority(of train: Train, reserved reservation: ReservedTrack) -> (left: Int64, envelopes: AuthorityEnvelopes)? {
        let route = routeStretches(of: train)
        // A reservation that holds where the route ends holds all of it: a
        // following train's ends at least ``followingGap`` short of that.
        guard let last = route.stretches.last,
              !resources(covering: [TrackStretch(traversal: last.traversal, from: last.to, to: last.to)]).allSatisfy(reservation.contains),
              route.moves
        else { return nil }
        // Its route envelope (see ``routeEnvelope(of:)``) is the base and
        // the track of every stretch together: a reservation holding all of
        // them holds the whole route.
        let envelopes = authorityEnvelopes(of: train, along: route.stretches)
        let holdsBase = envelopes.base.allSatisfy(reservation.contains)
        let holds = { (stretch: TrackStretch) in reserves(reservation, all: stretch) }
        guard !holdsBase || !envelopes.stretches.allSatisfy(holds) else { return nil }
        // The longest distance whose track the reservation holds.
        return (longestAuthority(envelopes, from: 0, clearBase: holdsBase, clear: holds), envelopes)
    }

    /// Whether `train` follows another (Stage U2): under traffic control
    /// its reservation holds its route only part of the way. Only a
    /// service's departure takes a route part of the way, but a train
    /// whose service is stopped on the way keeps its path and its
    /// reservation, and so goes on following.
    func isFollowing(_ train: Train) -> Bool {
        authorityLeft(of: train) != nil
    }

    /// ``authority(of:)`` kept in `memo`, by the train as it is: it depends
    /// on nothing else but the network and traffic control, which do not
    /// change within one memo. A few of each train's last values are kept
    /// (the steps of an advance ask of the trains as they would have moved
    /// on, between questions of the trains as they are).
    func authority(of train: Train, memo: inout DirectionMemo) -> (left: Int64, envelopes: AuthorityEnvelopes)? {
        guard isTrafficControlEnabled, !train.reservation.isEmpty else { return nil }
        if let known = memo.authorities[train.id]?.first(where: { $0.train == train }) { return known.authority }
        let authority = authority(of: train, reserved: reservedTrack(of: train, memo: &memo))
        var known = memo.authorities[train.id] ?? []
        known.insert((train, authority), at: 0)
        if known.count > 4 { known.removeLast() }
        memo.authorities[train.id] = known
        return authority
    }

    /// ``isFollowing(_:)`` kept in `memo` (see ``authority(of:memo:)``).
    func isFollowing(_ train: Train, memo: inout DirectionMemo) -> Bool {
        authority(of: train, memo: &memo) != nil
    }

    /// What following `train` (Stage U2) still needs and does not hold:
    /// `route` is its whole route envelope, `waiting` the part of it no
    /// train holds (see ``held(_:)``). No other train may take track it
    /// waits for, unless that train holds track of its route itself: one
    /// of the trains ahead, which it follows. `nil` for a train that does
    /// not follow another.
    func claim(of train: Train) -> (route: Set<TrackResource>, waiting: Set<TrackResource>)? {
        guard !blockSections, isFollowing(train) else { return nil }
        let route = routeEnvelope(of: train).resources
        var waiting = route
        for other in trains where other.id != train.id && other.position != nil {
            waiting.subtract(held(other))
        }
        return (route, waiting)
    }

    /// `candidate`, a service about to set off along a route other trains
    /// hold some of, following them (Stage U2): with a reservation of its
    /// route as far as ``followingGap`` short of the first track another
    /// train holds (see ``holder(of:except:)``), or `nil` if it may not
    /// follow them, or that leaves it no way to go.
    ///
    /// It may follow only trains it can be sure leave its route, or go on
    /// from it without turning back: every train that holds track of its
    /// `route` (or fouls it, or waits for it) must be a service travelling
    /// to a call with its whole route held (it waits for nobody), and the
    /// call it travels to is off `route`, or it goes on from there to a
    /// call after it without turning round. A train standing, turning
    /// round, ending its service or following another itself, it waits for
    /// whole, as before.
    ///
    /// `route` is asked a resource at a time (see ``TrackCover``), and
    /// `memo` keeps the trains' holders.
    /// With `limit` (decision 294) it never reaches beyond that. Decision
    /// 636: it is `nil` too when the train would stand on track its line
    /// runs only the other way where the reservation ends
    /// (``standsAgainstTheLine(_:_:authority:memo:)``).
    func followingAuthority(of candidate: Train, route: TrackCover, limit: Int64 = .max, memo: inout DirectionMemo) -> Train? {
        let holders = trackHolders(memo: &memo)
        let holding = holders.holding(route, except: candidate.id, fouling: true, in: network)
        for (place, other) in trains.enumerated() where other.id != candidate.id && other.position != nil {
            guard holding[place] || holder(of: route, except: candidate.id, waitedForBy: other, holders: holders) else { continue }
            guard isLeading(other, onto: route, for: candidate) else { return nil }
        }
        // The longest distance whose track no other train holds.
        let blocked = blockedTrack(except: candidate.id, holders: holders)
        let envelopes = authorityEnvelopes(of: candidate)
        let clear = clearOfBlocked(blocked)
        let free = longestAuthority(envelopes, from: 0, clearBase: clear.base(envelopes.base), clear: clear.stretch)
        let authority = min(followingAuthority(envelopes, free: free), limit)
        guard authority >= 1 else { return nil }
        // Decision 636: never left standing on track its line runs only
        // the other way.
        if !blockSections, standsAgainstTheLine(candidate, envelopes, authority: authority, memo: &memo) { return nil }
        var train = candidate
        train.reservation = authorityEnvelope(envelopes, to: authority).sorted()
        return train
    }

    /// Decision 636: whether `candidate`, its head stopped `authority`
    /// along its route short of its end, would stand on track its line
    /// runs only the other way (decision 527's
    /// ``oneWayAgainst(_:length:)``). Never when it stands on such track
    /// already. A train following another (Stage U2) could be left there,
    /// head on with the line's own trains, when the one ahead stops short:
    /// an empty run out of the Qingpu depot of the Taoyuan Airport MRT,
    /// whose track joins only the eastbound line, met an eastbound service
    /// at THSR Taoyuan, and neither moved again (TYMC-REBUILD-4). It may
    /// still stop short of such track, or reach its end there.
    func standsAgainstTheLine(_ candidate: Train, _ envelopes: AuthorityEnvelopes, authority: Int64, memo: inout DirectionMemo) -> Bool {
        guard authority < envelopes.length,
              let line = lines.first(where: { $0.hasRuns && $0.trains.contains(candidate.id) }) else { return false }
        let key = PathMemo.LineAgainst(line: line.id, length: candidate.length)
        let against: Set<TrackTraversal>
        if let known = memo.paths.against[key] { against = known } else {
            against = oneWayAgainst(line, length: candidate.length)
            memo.paths.against[key] = against
        }
        guard !against.isEmpty, !bodyStretches(of: candidate).contains(where: { against.contains($0.traversal) }) else { return false }
        // Its body, from `tail` to its head, along its route.
        let tail = authority - candidate.length
        var start: Int64 = 0
        for (stretch, end) in zip(envelopes.stretches, envelopes.ends) {
            defer { start = end }
            guard start < authority else { break }
            if end > tail, end > start, against.contains(stretch.traversal) { return true }
        }
        return false
    }

    /// Whether train `other`, following a train, waits for any of
    /// `route`, as ``holder(of:except:)`` asks of each train for train
    /// `id`; what it holds or fouls is asked of all the trains at once (see
    /// ``TrackHolders/holding(_:except:fouling:in:)``).
    func holder(of route: TrackCover, except id: TrainID, waitedForBy other: Train, holders: TrackHolders) -> Bool {
        guard let claim = holders.claims[other.id], holders.binds(claim, id) else { return false }
        return holders.waits(claim, forAnyIn: route)
            || claim.foulingWaiting.contains { network.foulingSpans[$0]!.contains { route.contains(.span($0)) } }
    }

    /// Whether `train` leads the way along `route`, the route envelope of
    /// `follower`, a train that would follow it (see
    /// ``followingAuthority(of:route:memo:)``). A train that runs along any edge
    /// of the follower's way the other way round comes towards it and is
    /// never followed.
    func isLeading(_ train: Train, onto route: TrackCover, for follower: Train) -> Bool {
        guard case .travellingToStop(let stop, let cycle)? = train.execution, train.movement.rate > 0,
              routeStretches(of: train).moves, blockSections || !isFollowing(train) || holdsToItsApproach(train)
        else { return false }
        let ways = Set((bodyStretches(of: follower) + routeStretches(of: follower).stretches).map(\.traversal))
        for stretch in bodyStretches(of: train) + routeStretches(of: train).stretches where ways.contains(stretch.traversal.reversed) {
            return false
        }
        guard !stopsOn(route, train) else {
            return !train.timetable[stop].reverses && train.call(after: stop, cycle: cycle) != nil
        }
        return true
    }

    /// Whether `train`, travelling to a call, stops for it on track `route`
    /// covers (or, if `fouling`, fouls it there): for a train following
    /// another (decision 212), where it stops for its call, not where its
    /// authority ends.
    func stopsOn(_ route: TrackCover, _ train: Train, fouling: Bool = true) -> Bool {
        let arrived = arrived(train)
        return occupied(arrived).contains(where: route.contains)
            || fouling && foulingNodes(covering: bodyStretches(of: arrived)).contains(where: route.contains)
    }

    /// `train` where the route it travels ends, holding nothing.
    func arrived(_ train: Train) -> Train {
        var arrived = train
        arrived.reservation = []
        let end = travelling(arrived, distance: routeLength(of: train))
        arrived.position = end.position
        arrived.movement.cursor = end.cursor
        return arrived
    }
}
