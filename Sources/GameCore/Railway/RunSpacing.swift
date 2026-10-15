// Keeping the trains of real runs apart without traffic control
// (ARCHITECTURE decision 228). With traffic control off a train runs along
// its path whatever stands or runs on it. A train of a line with real runs
// (decision 133) instead stops short of a train ahead of it going the same
// way; waits short of track it shares with a train coming the other way;
// leaving a station, lets a faster train behind it pass first; goes to a
// free platform where it can (see also `Depot.swift`); and, held up, goes
// on at its pace later rather than from a stand. Every other train runs as
// before, so worlds without such lines are unchanged.

extension GameWorld {
    /// How far along their ways trains are looked at for one coming the
    /// other way (decision 228): as many edges as that.
    static let oncomingLookahead = 32

    /// How far behind where a train leaving its platform joins its way on
    /// another train may be at most for it to wait for that one to pass
    /// first (decision 228): 60 km.
    static let overtakeReach: Int64 = 60_000 * WorldCoordinate.unitsPerMetre

    /// Decision 228: whether `other`, `far` behind where `train`, leaving
    /// its platform, joins its way `near` ahead of its head, would come up
    /// with it before its next call: at its run's average speed over the
    /// way from there to that call, against `train`'s share of its run's
    /// time for what is left of it (or, held before it has one, its time
    /// to its scheduled arrival), and a minute. Within ``overtakeReach``
    /// only.
    func catches(_ train: Train, at near: Int64, by other: Train, from far: Int64) -> Bool {
        guard far <= Self.overtakeReach, case .travellingToStop(let stop, let cycle)? = train.execution,
              let theirs = other.times?.run, theirs.length > 0, theirs.seconds > 0 else { return false }
        let left = Double(routeLength(of: train))
        // Held at its platform, it has no run: the time left to its call.
        var myTime = Double(secondsToScheduledArrival(of: train, stop: stop, cycle: cycle))
        if let mine = train.times?.run, mine.length > 0 { myTime = Double(mine.seconds) * left / Double(mine.length) }
        let theirTime = (Double(far) + left - Double(near)) * Double(theirs.seconds) / Double(theirs.length)
        return theirTime < myTime + Double(GameTime.secondsPerMinute)
    }

    /// Decision 228: how far `train` may go on, up to `distance`, before
    /// its head reaches the tail of another train ahead of it on its way
    /// and going the same way along it, or the track it shares with a
    /// train coming the other way that is on it already; or, while it is
    /// still leaving the platform of its last call, that is nearer it (of
    /// two as near, the one with the lower ID goes first), or where it
    /// joins the way of a faster train that would catch it before its next
    /// call (``catches(_:at:by:from:)``). `nil` when
    /// nothing is that near, or the rule does not apply: under traffic
    /// control (its movement authority keeps trains apart), and for a
    /// train of a line without real runs (``followsRealTimetable(_:)``),
    /// which runs through as before. A train on the shared track already
    /// goes on, and a train on its way waits only for one on it: so two
    /// trains never wait for each other.
    func clearAhead(of train: Train, within distance: Int64, near index: [TrackEdgeID: [TrainID]]? = nil) -> Int64? {
        heldUp(train, within: distance, near: index)?.clear
    }

    /// By edge, the trains whose body is on it or whose way leads over it
    /// within ``oncomingLookahead`` edges (decision 228): where they can be
    /// as they move on, for ``clearAhead(of:within:near:)`` to look at only
    /// those near a train. Empty under traffic control, or without a line of
    /// real runs.
    func spacingIndex() -> [TrackEdgeID: [TrainID]] {
        guard !isTrafficControlEnabled, lines.contains(where: { !$0.runs.isEmpty }) else { return [:] }
        var index: [TrackEdgeID: [TrainID]] = [:]
        for train in trains where train.position != nil {
            var edges = Set(train.movement.remainingEdges.prefix(Self.oncomingLookahead))
            if case .onEdge(let traversal, _)? = train.position { edges.insert(traversal.edge) }
            edges.formUnion(train.trailEdges)
            for edge in edges { index[edge, default: []].append(train.id) }
        }
        return index
    }

    /// Decision 228 with decision 37: whether a train would be held up
    /// (``heldUp(_:within:near:)``) within the `span` seconds from `start`
    /// that the step is about to move the trains in one go. Where none is,
    /// the span moves them as far as one second at a time would; where one
    /// is, how far it gets depends on where the others are each second.
    func spacingMayHold(from start: GameTime, within span: Int64, memo: inout DirectionMemo) -> Bool {
        let index = spacingIndex()
        guard !index.isEmpty else { return false }
        // How far each train goes in the span; another may come that far
        // toward it meanwhile, so it looks as far again as the farthest.
        var travel: [(train: Train, distance: Int64)] = []
        for train in trains where train.position != nil && train.movement.rate > 0 {
            travel.append((train, travelShare(of: train, from: start, memo: &memo)(span)))
        }
        let farthest = travel.map(\.distance).max() ?? 0
        return travel.contains { heldUp($0.train, within: (Int64.max / 4) + 0 * farthest, near: index) != nil }
    }

    /// ``clearAhead(of:within:near:)``, and the train it stops short of.
    func heldUp(_ train: Train, within distance: Int64, near index: [TrackEdgeID: [TrainID]]? = nil) -> (clear: Int64, by: TrainID)? {
        guard !isTrafficControlEnabled, distance > 0, case .onEdge(let traversal, let offset)? = train.position,
              network.edge(traversal.edge) != nil, followsRealTimetable(train) else { return nil }
        // Nothing to do when no other train is near its way.
        if let index {
            let others = { (edge: TrackEdgeID) in index[edge]?.contains { $0 != train.id } == true }
            guard others(traversal.edge) || train.trailEdges.contains(where: others)
                    || train.movement.remainingEdges.prefix(Self.oncomingLookahead).contains(where: others) else { return nil }
        }
        let mine = way(of: train)
        let starts = mine.starts
        // Whether it is still leaving the platform of its last call.
        var leaving = false
        if case .travellingToStop(let stop, let cycle)? = train.execution, let previous = train.call(before: stop, cycle: cycle) {
            let platforms = Set(network.platforms(of: train.timetable[previous.stop].station).map(\.edge))
            leaving = mine.body.contains { platforms.contains($0.edge) }
        }
        var clear: (clear: Int64, by: TrainID)?
        let near = index.map { index in Set(mine.edges.flatMap { index[$0] ?? [] }) }
        for other in trains where other.id != train.id && near?.contains(other.id) != false {
            // Only a train on or bound for one of its edges.
            guard case .onEdge(let head, _)? = other.position,
                  mine.edges.contains(head.edge) || other.trailEdges.contains(where: mine.edges.contains)
                    || other.movement.remainingEdges.prefix(Self.oncomingLookahead).contains(where: mine.edges.contains)
            else { continue }
            // Behind a train going the same way.
            for part in bodyStretches(of: other) {
                // Ahead of its head: on its own traversal, only what reaches
                // beyond it; not on the track its body is on behind it.
                guard let start = starts[part.traversal], part.traversal == traversal || !mine.body.contains(part.traversal) else { continue }
                if part.traversal == traversal, part.to <= offset { continue }
                let gap = max(0, start + part.from)
                if gap < distance, gap < clear?.clear ?? .max { clear = (gap, other.id) }
            }
            let theirs = way(of: other)
            // Still leaving its platform: short of where it joins the way of
            // a train coming up behind it on its way on, but not through the
            // track it stands on, to let it pass first, as a set waits in a
            // station's loop for the faster one.
            if leaving, case .travellingToStop? = other.execution, other.movement.rate > 0,
               !mine.body.contains(where: { theirs.starts[$0] != nil }),
               let joins = mine.order.first(where: { !mine.body.contains($0) && (theirs.starts[$0] ?? -1) > 0 }),
               let near = starts[joins], let far = theirs.starts[joins], near < distance,
               catches(train, at: near, by: other, from: far) {
                if near < clear?.clear ?? .max { clear = (near, other.id) }
                continue
            }
            // Short of the track it shares with a train coming towards it,
            // unless it is on that track already. Not for a train standing
            // without a service, which would never clear it (on a single
            // track, as before decision 228, they pass through).
            guard other.execution != nil, let shared = mine.order.first(where: { theirs.starts[$0.reversed] != nil }), !mine.body.contains(shared),
                  let near = starts[shared], near < distance else { continue }
            let meeting = theirs.order.filter { starts[$0.reversed] != nil }
            if !meeting.contains(where: theirs.body.contains) {
                // Not on it yet: only a train still leaving its platform
                // lets one nearer go first.
                guard leaving, let far = meeting.compactMap({ theirs.starts[$0] }).min(), far < near || (far == near && other.id < train.id) else { continue }
            }
            if near < clear?.clear ?? .max { clear = (near, other.id) }
        }
        return clear
    }

    /// The traversals of `train`'s way, in order, and where each begins
    /// from its head (those its body is on behind it, at 0 or less), up to
    /// ``oncomingLookahead`` edges ahead; those its body is on; and their
    /// edges.
    private func way(of train: Train) -> (order: [TrackTraversal], starts: [TrackTraversal: Int64], body: Set<TrackTraversal>, edges: Set<TrackEdgeID>) {
        var order: [TrackTraversal] = []
        var starts: [TrackTraversal: Int64] = [:]
        for part in bodyStretches(of: train) where starts[part.traversal] == nil {
            starts[part.traversal] = part.from - part.to
            order.append(part.traversal)
        }
        let body = Set(order)
        guard case .onEdge(let traversal, let offset)? = train.position, let length = network.edge(traversal.edge)?.length else { return ([], [:], [], []) }
        starts[traversal] = -offset
        var arrival = traversal
        var reach = length - offset
        for edge in train.movement.remainingEdges.prefix(Self.oncomingLookahead) {
            guard let entry = networkEntry(after: arrival, into: edge)?.traversal, let next = network.edge(entry.edge) else { break }
            if starts[entry] == nil {
                starts[entry] = reach
                order.append(entry)
            }
            reach += next.length
            arrival = entry
        }
        return (order, starts, body, Set(starts.keys.map(\.edge)))
    }
}

extension GameWorld {
    /// Decision 228: how far short of the platform it would stop at a
    /// train keeps to its way before it may turn off it for a free one: a
    /// kilometre, more than a station's loops reach out, so it never takes
    /// a turnout onto the other way's track further back.
    static let platformApproach: Int64 = 1_000 * WorldCoordinate.unitsPerMetre

    /// Decision 228: `path`, the way `train` (leaving for timetable entry
    /// `next` at station `id`) would go from `start`, changed to end at
    /// another of the station's platforms when another train is due on its
    /// own while `train` is there (see ``platformWaits(_:for:over:)``):
    /// along `path` up to ``platformApproach`` short of its end, and from
    /// there the shortest way to a free platform; when none is reached
    /// that way, to the one that is free soonest, if sooner than its own.
    /// `nil` when `path` may stay as it is, or no better platform is
    /// reached that way.
    func freePlatformPath(_ path: TrainPath, from start: TrainPosition, toStation id: StationID, for train: Train, next: (stop: Int, cycle: Int64), memo: inout PathMemo) -> TrainPath? {
        guard case .onEdge(let first, let offset) = start,
              let waits = platformWaits(id, for: train, over: platformTimes(of: train, stop: next.stop, cycle: next.cycle)),
              let own = waits[(path.traversals.last ?? first).edge], own > 0 else { return nil }
        // The last node of `path` at least `platformApproach` short of
        // its end: after the edge it starts on, or one of its traversals.
        var reached = (network.edge(first.edge)?.length ?? 0) - offset
        var cut: (index: Int, traversal: TrackTraversal, distance: Int64)?
        if path.distance - reached >= Self.platformApproach { cut = (-1, first, reached) }
        for (index, traversal) in path.traversals.enumerated().dropLast() {
            guard let length = network.edge(traversal.edge)?.length else { return nil }
            reached += length
            guard path.distance - reached >= Self.platformApproach else { break }
            cut = (index, traversal, reached)
        }
        let all = berths(of: id, length: train.length)
        for limit in Set(waits.values).sorted() where limit < own {
            let eligible = Set(all.filter { (waits[$0.traversal.edge] ?? .max) <= limit })
            guard let cut, let length = network.edge(cut.traversal.edge)?.length else {
                if let found = self.path(from: start, toStation: id, length: train.length, eligible: eligible, keepingLeft: true, memo: &memo) { return found }
                continue
            }
            guard let rest = self.path(from: .onEdge(cut.traversal, offset: length), toStation: id, length: train.length, eligible: eligible, keepingLeft: true, memo: &memo) else { continue }
            return TrainPath(traversals: Array(path.traversals.prefix(cut.index + 1)) + rest.traversals, end: rest.end, distance: cut.distance + rest.distance)
        }
        return nil
    }
}

extension GameWorld {
    /// The edges trains stand on, or are on without travelling to a call
    /// (decision 228): where ``freePlatformOnTheWay(of:standing:memo:)``
    /// looks. Empty under traffic control, or without a line of real runs.
    func standingEdges() -> Set<TrackEdgeID> {
        guard !isTrafficControlEnabled, lines.contains(where: { !$0.runs.isEmpty }) else { return [] }
        var edges: Set<TrackEdgeID> = []
        for train in trains {
            if case .travellingToStop? = train.execution { continue }
            for part in bodyStretches(of: train) { edges.insert(part.traversal.edge) }
        }
        return edges
    }

    /// Decision 228: the way to another of its call's platforms for
    /// `train`, of a line with real runs, on its way to a call with traffic
    /// control off, when another train stands on the one it is bound for
    /// and a better one is free (see ``freePlatformPath(_:from:toStation:for:next:memo:)``):
    /// a train that was due to leave it in time may not have. `nil` when it
    /// keeps its way.
    func freePlatformOnTheWay(of train: Train, standing: Set<TrackEdgeID>, memo: inout PathMemo) -> TrainPath? {
        guard !isTrafficControlEnabled, case .travellingToStop(let stop, let cycle)? = train.execution,
              let position = train.position, case .onEdge(let traversal, let offset) = position else { return nil }
        let target = train.movement.remainingEdges.last ?? traversal.edge
        guard standing.contains(target), let length = network.edge(traversal.edge)?.length, followsRealTimetable(train),
              trains.contains(where: { other in
                  guard other.id != train.id else { return false }
                  if case .travellingToStop? = other.execution { return false }
                  return bodyStretches(of: other).contains { $0.traversal.edge == target }
              }) else { return nil }
        // Its way as it stands.
        let ahead = pathAhead(of: train)
        guard ahead.count == train.movement.remainingEdges.count else { return nil }
        var distance: Int64
        if let last = ahead.last, let lastLength = network.edge(last.edge)?.length {
            distance = length - offset
            for part in ahead.dropLast() { distance += network.edge(part.edge)?.length ?? 0 }
            distance += train.movement.end ?? lastLength
        } else {
            distance = (train.movement.end ?? length) - offset
        }
        guard distance > 0 else { return nil }
        return freePlatformPath(TrainPath(traversals: ahead, end: train.movement.end, distance: distance), from: position,
                                toStation: train.timetable[stop].station, for: train, next: (stop, cycle), memo: &memo)
    }
}

extension GameWorld {
    /// How long a departure waits at most for the platform it is bound for
    /// to come free (decision 228): fifteen minutes. A platform taken for
    /// longer is gone to anyway, as before.
    static let platformHold: Int64 = 15 * GameTime.secondsPerMinute

    /// Decision 228: whether `train`, of a line with real runs, just set off
    /// along its path for its next call with traffic control off, should
    /// wait where it is instead: every platform of the call it could take
    /// is taken over its time there (see ``platformWaits(_:for:over:)``),
    /// the one it is bound for by a train that stands there or is due
    /// first and leaves within ``platformHold``. Arriving behind a train
    /// that turns back out the way it came, it would meet it.
    func waitsForPlatform(_ train: Train) -> Bool {
        guard !isTrafficControlEnabled, case .travellingToStop(let stop, let cycle)? = train.execution,
              case .onEdge(let traversal, _)? = train.position else { return false }
        let target = train.movement.remainingEdges.last ?? traversal.edge
        guard let waits = platformWaits(train.timetable[stop].station, for: train, over: platformTimes(of: train, stop: stop, cycle: cycle)),
              let wait = waits[target] else { return false }
        return wait > 1 && wait != .max && wait - clock.now.seconds <= Self.platformHold
    }
}

extension GameWorld {
    /// Decision 228: how much later `run` (with `curve`) would have to have
    /// set off for a train that has covered `covered` of it to be where its
    /// curve has it at `end`: the seconds from when the curve came that far
    /// to `end`. `nil` when it never comes that far before `end`.
    func runDelay(_ run: ServiceRun, curve: RunCurve, covered: Int64, at end: GameTime) -> Int64? {
        guard end > run.start else { return nil }
        // The latest second by which the curve has come no farther.
        var (low, high) = (run.start.seconds, min(end.seconds, run.end.seconds))
        guard run.distance(on: curve, from: run.start, to: GameTime(seconds: low)) <= covered else { return nil }
        while low < high {
            let middle = low + (high - low + 1) / 2
            if run.distance(on: curve, from: run.start, to: GameTime(seconds: middle)) <= covered { low = middle } else { high = middle - 1 }
        }
        let late = end.seconds - low
        return late > 0 ? late : nil
    }
}
