// Approach locking (ARCHITECTURE decision 294). With traffic control and
// block sections on, a service of a line with runs (decision 133) set off
// on a long leg took its whole route at once when it was free: a train
// leaving Taichung for Zuoying held Zuoying's turnouts for the 50 minutes
// it took to get there, and no set standing at Zuoying could leave north
// through them, so the runs they were for were dropped. A real railway sets
// the route into a station only as the train comes near it.
//
// So such a train holds its route only as far as the last block boundary
// ``approachHold`` short of its stop until it comes within
// ``approachReach`` of the stop; from there it takes the rest as any train
// takes more of its route (decision 212), as a block falls free. What it
// holds before is plain line it holds whole as before, so no train can
// come at it there; what it leaves is the end of its way, which a train
// can only use without the line it holds. Derived from the train and the
// network, never saved; with traffic control or block sections off, and
// for any other train, nothing changes.

extension GameWorld {
    /// How near its stop a service of a line with runs comes before it
    /// takes the rest of its route (decision 294): 896,000 units, 14 km,
    /// the ``approachHold`` it leaves, the 8.3 km a high-speed set needs to
    /// stop from 300 km/h, and a block more.
    static let approachReach: Int64 = 896_000

    /// How much of its route at least such a service leaves untaken while
    /// it is farther than ``approachReach`` from its stop: 256,000 units,
    /// 4 km, more than a station's turnouts and platforms.
    static let approachHold: Int64 = 256_000

    /// How far along its route (see ``AuthorityEnvelopes``) `train` may
    /// hold now (decision 294), or `nil` when it may hold all of it: with
    /// traffic control and block sections on, a service of a line with runs
    /// travelling to a stop more than ``approachReach`` away holds it only
    /// to the last block boundary ``approachHold`` or more short of the
    /// stop. `nil` also when there is no such boundary beyond its head.
    ///
    /// Decision 849: without block sections, the home signal instead (see
    /// ``homeLimit(of:_:)``); and, its later part, with them too once the
    /// stop is within ``approachReach``, where decision 294 held all.
    func approachLimit(of train: Train, _ envelopes: AuthorityEnvelopes) -> Int64? {
        guard isTrafficControlEnabled, case .travellingToStop? = train.execution, envelopes.length < .max else { return nil }
        guard blockSections else { return homeLimit(of: train, envelopes) }
        guard followsRealTimetable(train) else { return nil }
        guard envelopes.length > Self.approachReach else { return homeLimit(of: train, envelopes) }
        let limit = blockBoundary(envelopes, atOrBefore: envelopes.length - Self.approachHold)
        return limit >= 1 ? limit : nil
    }

    /// The approach limit (see ``approachLimit(of:_:)``) of `train`,
    /// holding `held` of its route along `envelopes`, that keeps it now:
    /// with block sections and its stop more than ``approachReach`` away
    /// any (decision 294); a home signal's (decision 849) only one it
    /// holds as far as already, as a train given its route that far at
    /// once with the rest free holds it (see ``reserving(_:following:memo:)``).
    /// A train following others short of it takes its route as before.
    func approachLimit(of train: Train, holding held: Int64, _ envelopes: AuthorityEnvelopes) -> Int64? {
        guard let limit = approachLimit(of: train, envelopes) else { return nil }
        return (blockSections && envelopes.length > Self.approachReach) || held >= limit ? limit : nil
    }

    /// Decision 294: `candidate`, about to set off, with its route held
    /// only to `limit` along `envelopes` (see ``approachLimit(of:_:)``),
    /// or, `following`, as far as the trains ahead leave it short of that
    /// (Stage U2), or the lowest numbered other train holding track it
    /// needs that far.
    func reservingApproach(_ candidate: Train, envelopes: AuthorityEnvelopes, limit: Int64, following: Bool,
                           memo: inout DirectionMemo) -> Reserving {
        let needs = authorityEnvelope(envelopes, to: limit)
        let holders = trackHolders(memo: &memo)
        guard let holder = holder(of: needs, except: candidate.id, holders: holders) else {
            var train = candidate
            train.reservation = needs.sorted()
            return .granted(train)
        }
        if following, let train = followingAuthority(of: candidate, route: cover(of: approachStretches(of: candidate, envelopes, to: limit)),
                                                     limit: limit, memo: &memo) {
            return .granted(train)
        }
        return .held(by: holder)
    }

    /// What `train` covers from its tail to `distance` along `envelopes`:
    /// its body, then its route as far as that.
    func approachStretches(of train: Train, _ envelopes: AuthorityEnvelopes, to distance: Int64) -> [TrackStretch] {
        guard !envelopes.stretches.isEmpty else { return bodyStretches(of: train) }
        let end = authorityEnd(envelopes, to: distance)
        return bodyStretches(of: train) + Array(envelopes.stretches[..<end.index]) + [end.part]
    }

    // MARK: - The home signal (decision 849)

    /// Decision 849: how near the first junction before its stop a service
    /// of a line with runs comes, without block sections, before it takes
    /// the rest of its route: 64,000 units, 1 km, where a home signal's
    /// distant signal stands on a metro.
    static let homeReach: Int64 = 64_000

    /// Decision 849: how far before its stop a junction on its route counts
    /// as the station's throat: 64,000 units, 1 km, more than a metro or
    /// a branch line's platforms and turnouts.
    static let throatReach: Int64 = 64_000

    /// Decision 849: how far along its route `train`, a service of a line
    /// with runs travelling to a stop with traffic control on (and block
    /// sections off, or the stop within ``approachReach``), may hold now,
    /// or `nil` when it may hold all of it:
    /// short of the first junction or crossing its route reaches within
    /// ``throatReach`` of the stop (the station's throat), while that is
    /// more than ``homeReach`` away. Only a service (not an empty run)
    /// turning back or ending at the stop, on a line whose runs all run
    /// its whole length and call at every stop: at a through station, or
    /// on a line with expresses or short runs (the Taoyuan Airport MRT),
    /// trains queued worse with it. On Hong Kong's
    /// South Island Line a train leaving Ocean Park held Admiralty's
    /// crossovers for the four minutes it took to get there, and the
    /// trains due out of Admiralty waited behind it; a real railway sets
    /// the route into a station only as the train nears its home signal.
    /// With block sections (the later part) the same: the Lok Ma Chau
    /// spur's 7 km leg has one throat at each end, and a train leaving one
    /// end held the other's for the ten minutes it took to get there, so
    /// the two ends took turns as on a single line.
    func homeLimit(of train: Train, _ envelopes: AuthorityEnvelopes) -> Int64? {
        let length = envelopes.length
        guard length > Self.homeReach + RailwayNetwork.junctionZone, !train.isDeadheading, case .travellingToStop(let stop, let cycle)? = train.execution,
              train.timetable[stop].reverses || train.call(after: stop, cycle: cycle) == nil,
              let line = lines.first(where: { $0.hasRuns && $0.trains.contains(train.id) }), line.runs.allSatisfy({ $0.passes.isEmpty && min($0.from, $0.to) == 0 && max($0.from, $0.to) == line.stops.count - 1 })
        else { return nil }
        let window = length - Self.throatReach
        guard let first = envelopes.ends.firstIndex(where: { $0 > window }) else { return nil }
        var start = first == 0 ? 0 : envelopes.ends[first - 1]
        var limit: Int64?
        for index in first..<envelopes.stretches.count {
            defer { start = envelopes.ends[index] }
            let stretch = envelopes.stretches[index]
            if let along = throatPoint(on: stretch, then: index + 1 < envelopes.stretches.count ? envelopes.stretches[index + 1] : nil) {
                let at = start + along
                if at >= window, at < length { limit = at }
                if limit != nil { break }
            }
        }
        guard let limit, limit > Self.homeReach else { return nil }
        return limit
    }

    /// The farthest a train may go along `stretch` (from its start, the way
    /// it is travelled) without fouling a junction or crossing on it: short
    /// of the first span of it that fouls another edge's (see
    /// ``RailwayNetwork/foulingSpans``), or ``RailwayNetwork/junctionZone``
    /// short of its end where that is a node it fouls, its edge's or
    /// `next`'s fouling end (see ``isFoulingEnd(of:at:)``); `nil` when it
    /// fouls neither.
    private func throatPoint(on stretch: TrackStretch, then next: TrackStretch?) -> Int64? {
        guard let edge = network.ends(ofEdge: stretch.traversal.edge) else { return nil }
        let forward = stretch.traversal.direction == .forward
        var point: Int64?
        if !network.foulingSpans.isEmpty {
            for span in network.spans(of: stretch.traversal.edge, length: edge.length) where network.foulingSpans[span] != nil {
                // The span the way the train travels it.
                let (low, high) = forward ? (span.start, span.end) : (edge.length - span.end, edge.length - span.start)
                guard high > stretch.from, low <= stretch.to else { continue }
                let along = max(low, stretch.from) - stretch.from - 1
                point = min(point ?? .max, along)
            }
        }
        if stretch.to == edge.length {
            let node = forward ? edge.to : edge.from
            if isFoulingEnd(of: stretch.traversal.edge, at: node) || next.map({ isFoulingEnd(of: $0.traversal.edge, at: node) }) == true {
                point = min(point ?? .max, stretch.to - stretch.from - RailwayNetwork.junctionZone)
            }
        }
        return point
    }

    /// Decision 849: whether `train` holds its route as far as its approach
    /// limit lets it (see ``approachLimit(of:_:)``) and so waits for
    /// nothing but its nearing its stop: a train another may follow, as
    /// it would one holding its whole route.
    func holdsToItsApproach(_ train: Train) -> Bool {
        guard !blockSections, let (left, envelopes) = authority(of: train) else { return false }
        return approachLimit(of: train, holding: left, envelopes) != nil
    }

    /// Decision 849: what `train`, holding `authority` short of its route's
    /// end, claims without block sections (decision 56, point 6): its route
    /// envelope (`whole`); a train held at its home signal (see
    /// ``homeLimit(of:_:)``) only its route as far as that and the berth
    /// it will stand at, so the trains leaving the station may cross the
    /// throat ahead of it but not take its berth.
    func claimCover(of train: Train, _ authority: (left: Int64, envelopes: AuthorityEnvelopes), whole: () -> TrackCover) -> TrackCover? {
        guard let limit = approachLimit(of: train, holding: authority.left, authority.envelopes) else { return whole() }
        return cover(of: approachStretches(of: train, authority.envelopes, to: limit) + bodyStretches(of: arrived(train)))
    }
}
