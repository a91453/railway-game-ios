// Keeping the trains of real runs apart without traffic control
// (ARCHITECTURE decision 228). With traffic control off a train runs along
// its path whatever stands or runs on it. A train of a line with real runs
// (decision 133) instead stops short of a train ahead of it going the same
// way; waits short of track it shares with a train coming the other way;
// leaving a station, lets a faster train behind it pass first; goes to a
// free platform where it can (see also `Depot.swift`); and, held up, goes
// on at its pace later rather than from a stand. Every other train runs as
// before, so worlds without such lines are unchanged.

/// The traversals of a train's way, in order, where each begins from its
/// head, those its body is on, and their edges (``GameWorld/way(of:)``).
typealias SpacingWay = (order: [TrackTraversal], starts: [TrackTraversal: Int64], body: Set<TrackTraversal>, edges: Set<TrackEdgeID>)

/// Decision 248: how far a train of a line with real runs may still go on
/// before the minute ends (``GameWorld/assessSpacing(from:memo:)``), given
/// while it is bound for the call `stop` of `cycle`; `Int64.max` when
/// nothing holds it.
public struct SpacingAllowance: Hashable, Sendable {
    public internal(set) var left: Int64
    public let stop: Int
    public let cycle: Int64

    /// Well formed: nothing negative.
    var isValid: Bool { left >= 0 && stop >= 0 && cycle >= 0 }
}

/// A saved ``SpacingAllowance`` and its train (`"left"` left out when
/// nothing holds it).
struct SavedSpacingAllowance: Codable {
    let train: TrainID
    let left: Int64?
    let stop: Int
    let cycle: Int64

    init(train: TrainID, _ allowance: SpacingAllowance) {
        self.train = train
        left = allowance.left == .max ? nil : allowance.left
        stop = allowance.stop
        cycle = allowance.cycle
    }

    var allowance: SpacingAllowance { SpacingAllowance(left: left ?? .max, stop: stop, cycle: cycle) }
}

extension GameWorld {
    /// How far along their ways trains are looked at for one coming the
    /// other way (decision 228): as many edges as that, and on until
    /// ``oncomingReach`` (see ``lookahead(of:)``).
    static let oncomingLookahead = 32

    /// Decision 283: how far along its way, at least, a train is looked at
    /// for one coming the other way: 20 km, twice the high-speed demo's
    /// longest track run both ways (Nangang to Taipei). Thirty-two edges
    /// reached about that far on the demo laid flat, but its track laid
    /// over the ground has three times as many edges, so a set leaving
    /// Taipei did not see one leaving Nangang towards it until both were
    /// on the track between them.
    static let oncomingReach: Int64 = 20_000 * WorldCoordinate.unitsPerMetre

    /// The edges of `train`'s path ahead it is looked at along for one
    /// coming the other way (decision 228): ``oncomingLookahead`` of them,
    /// and on until they reach ``oncomingReach`` (decision 283).
    func lookahead(of train: Train) -> ArraySlice<TrackEdgeID> {
        let edges = train.movement.remainingEdges
        guard edges.count > Self.oncomingLookahead else { return edges }
        var reach: Int64 = 0
        var count = 0
        for edge in edges {
            if count >= Self.oncomingLookahead, reach >= Self.oncomingReach { break }
            reach += network.edge(edge)?.length ?? 0
            count += 1
        }
        return edges.prefix(count)
    }

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
    /// train coming the other way that is on it already, or that is nearer
    /// it (of two as near, the one with the lower ID goes first; before
    /// decision 283 only while it is still leaving the platform of its last
    /// call); or, while it is still leaving that platform, where it joins
    /// the way of a faster train that would catch it before its next call
    /// (``catches(_:at:by:from:)``). `nil` when
    /// nothing is that near, or the rule does not apply: under traffic
    /// control (its movement authority keeps trains apart), and for a
    /// train of a line without real runs (``followsRealTimetable(_:)``),
    /// which runs through as before. A train on the shared track already
    /// goes on, and of two not on it the farther waits: so two trains never
    /// wait for each other.
    func clearAhead(of train: Train, within distance: Int64, near index: [TrackEdgeID: [TrainID]]? = nil) -> Int64? {
        heldUp(train, within: distance, near: index)?.clear
    }

    /// By edge, the trains whose body is on it or whose way leads over it
    /// within ``lookahead(of:)`` (decision 228): where they can be
    /// as they move on, for ``clearAhead(of:within:near:)`` to look at only
    /// those near a train. Empty under traffic control, or without a line of
    /// real runs.
    func spacingIndex() -> [TrackEdgeID: [TrainID]] {
        guard spacingApplies else { return [:] }
        var index: [TrackEdgeID: [TrainID]] = [:]
        for train in trains where train.position != nil {
            var edges = Set(lookahead(of: train))
            if case .onEdge(let traversal, _)? = train.position { edges.insert(traversal.edge) }
            edges.formUnion(train.trailEdges)
            for edge in edges { index[edge, default: []].append(train.id) }
        }
        return index
    }

    /// Whether decision 228 keeps trains apart: traffic control off, and a
    /// line with real runs.
    var spacingApplies: Bool {
        !isTrafficControlEnabled && lines.contains { !$0.runs.isEmpty }
    }

    /// Decision 248 (decision 228 with decision 37): how far each train of
    /// a line with real runs may go on, at most, until the minute ends.
    /// At every whole minute, from where the trains are then: as far as
    /// ``heldUp(_:within:near:)`` lets it, and, taking the trains in ID
    /// order, short of track that one taken before it, or a train of
    /// another line, may reach in the same minute coming the other way
    /// (short of all the track its way shares with that one's), or onto
    /// which that one may come from another way. A train that sets off (or
    /// goes on for its next call) within the minute is given its allowance
    /// then, after those that have one. Each train then moves by itself,
    /// so moving the trains a whole minute at once leaves them where moving
    /// them one second at a time would; and two trains coming towards each
    /// other never both go onto a single track in a minute.
    mutating func assessSpacing(from start: GameTime, memo: inout DirectionMemo) {
        guard spacingApplies else {
            if !spacingAllowances.isEmpty { spacingAllowances = [:] }
            return
        }
        let minuteEnd = Int64(GameTime.secondsPerMinute) - start.secondOfMinute
        var real: [Train] = []
        var others: [Train] = []
        for train in trains where train.position != nil && train.movement.rate > 0 {
            if case .travellingToStop = train.execution, followsRealTimetable(train) { real.append(train) } else { others.append(train) }
        }
        // An allowance holds while its train goes on for the same call.
        for (id, allowance) in spacingAllowances {
            guard let train = real.first(where: { $0.id == id }), case .travellingToStop(let stop, let cycle)? = train.execution,
                  stop == allowance.stop, cycle == allowance.cycle else {
                spacingAllowances[id] = nil
                continue
            }
        }
        let candidates = real.filter { spacingAllowances[$0.id] == nil }
        guard !candidates.isEmpty else { return }
        let index = spacingIndex()
        var ways: [TrainID: SpacingWay] = [:]
        func way(of train: Train) -> SpacingWay {
            if let known = ways[train.id] { return known }
            let found = self.way(of: train)
            ways[train.id] = found
            return found
        }
        // Where each train may be in the rest of the minute: the traversals
        // its body is on, and those ahead of it it may reach.
        var sweeps: [(train: Train, traversals: Set<TrackTraversal>)] = []
        func sweep(of train: Train, left: Int64) -> Set<TrackTraversal> {
            let mine = way(of: train)
            let reach = min(left, travelShare(of: train, from: start, memo: &memo)(minuteEnd))
            var swept = mine.body
            for traversal in mine.order where !mine.body.contains(traversal) {
                guard let at = mine.starts[traversal], at < reach else { break }
                swept.insert(traversal)
            }
            return swept
        }
        for train in others { sweeps.append((train, sweep(of: train, left: .max))) }
        for train in real {
            if let allowance = spacingAllowances[train.id] { sweeps.append((train, sweep(of: train, left: allowance.left))) }
        }
        for train in candidates.sorted(by: { $0.id < $1.id }) {
            guard case .travellingToStop(let stop, let cycle)? = train.execution else { continue }
            let reach = travelShare(of: train, from: start, memo: &memo)(minuteEnd)
            var left = reach > 0 ? heldUp(train, within: reach, near: index, ways: &ways)?.clear ?? .max : .max
            let mine = way(of: train)
            ahead: for traversal in mine.order where !mine.body.contains(traversal) {
                guard let at = mine.starts[traversal], at < min(reach, left) else { break }
                for other in sweeps {
                    if other.traversals.contains(traversal.reversed) {
                        // Short of all the track its way shares with that
                        // one's, the other way round.
                        let theirs = way(of: other.train)
                        let shared = mine.order.first { theirs.starts[$0.reversed] != nil }
                        let near = shared.flatMap { mine.body.contains($0) ? nil : mine.starts[$0] } ?? at
                        left = min(left, max(0, near))
                        break ahead
                    }
                    // Ahead of it on its way, it stops short of that one's
                    // tail (``heldUp(_:within:near:)``); from another way,
                    // that one may get there first.
                    if other.traversals.contains(traversal), way(of: other.train).body.isDisjoint(with: mine.order) {
                        left = min(left, max(0, at))
                        break ahead
                    }
                }
            }
            spacingAllowances[train.id] = SpacingAllowance(left: left, stop: stop, cycle: cycle)
            sweeps.append((train, sweep(of: train, left: left)))
        }
    }

    /// ``clearAhead(of:within:near:)``, and the train it stops short of.
    func heldUp(_ train: Train, within distance: Int64, near index: [TrackEdgeID: [TrainID]]? = nil) -> (clear: Int64, by: TrainID)? {
        var ways: [TrainID: SpacingWay] = [:]
        return heldUp(train, within: distance, near: index, ways: &ways)
    }

    /// ``heldUp(_:within:near:)`` with the trains' ways (``way(of:)``) kept
    /// in `ways` by train: a way depends on its train alone, so one worked
    /// out stays right until that train moves, and the caller drops it then.
    func heldUp(
        _ train: Train, within distance: Int64, near index: [TrackEdgeID: [TrainID]]?, ways: inout [TrainID: SpacingWay]
    ) -> (clear: Int64, by: TrainID)? {
        func way(of train: Train) -> SpacingWay {
            if let known = ways[train.id] { return known }
            let found = self.way(of: train)
            ways[train.id] = found
            return found
        }
        guard !isTrafficControlEnabled, distance > 0, case .onEdge(let traversal, let offset)? = train.position,
              network.edge(traversal.edge) != nil, followsRealTimetable(train) else { return nil }
        // Nothing to do when no other train is near its way.
        if let index {
            let others = { (edge: TrackEdgeID) in index[edge]?.contains { $0 != train.id } == true }
            guard others(traversal.edge) || train.trailEdges.contains(where: others)
                    || lookahead(of: train).contains(where: others) else { return nil }
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
                    || lookahead(of: other).contains(where: mine.edges.contains)
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
            // The rest needs its way where it meets this one's within
            // `distance` (the body and the traversals ahead of it closer
            // than that, the first in `mine.order`): none of those edges on
            // its way, nothing below can apply.
            let reach = mine.order.prefix { (starts[$0] ?? .max) < distance }.map(\.edge)
            if !reach.isEmpty {
                var theirEdges = Set(other.trailEdges)
                theirEdges.insert(head.edge)
                theirEdges.formUnion(lookahead(of: other))
                for part in bodyStretches(of: other) { theirEdges.insert(part.traversal.edge) }
                guard reach.contains(where: theirEdges.contains) else { continue }
            } else {
                continue
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
                // Not on it yet: it lets one nearer go first. Decision 283:
                // on its way too, not only still leaving its platform. A
                // set let off its platform by another hold went on, and
                // neither it nor the one coming waited for the other until
                // both were on the track between them (the high-speed
                // demo between Nangang and Taipei).
                guard let far = meeting.compactMap({ theirs.starts[$0] }).min(), far < near || (far == near && other.id < train.id) else { continue }
            }
            if near < clear?.clear ?? .max { clear = (near, other.id) }
        }
        return clear
    }

    /// The traversals of `train`'s way, in order, and where each begins
    /// from its head (those its body is on behind it, at 0 or less), up to
    /// its ``lookahead(of:)``; those its body is on; and their
    /// edges.
    private func way(of train: Train) -> SpacingWay {
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
        for edge in lookahead(of: train) {
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
    /// Decision 283: its own is taken, too, while another train comes out
    /// along its track towards `train` (``trainLeavingTowards(_:along:)``),
    /// and no platform is gone to that one is coming out of. `nil` when
    /// `path` may stay as it is, or no better platform is reached that way.
    func freePlatformPath(_ path: TrainPath, from start: TrainPosition, toStation id: StationID, for train: Train, next: (stop: Int, cycle: Int64), memo: inout PathMemo) -> TrainPath? {
        guard case .onEdge(let first, let offset) = start,
              var waits = platformWaits(id, for: train, over: platformTimes(of: train, stop: next.stop, cycle: next.cycle)) else { return nil }
        let target = (path.traversals.last ?? first).edge
        // Decision 283: taken while another train comes out along its track
        // towards this one, until a while after now: it is late, so when it
        // will have gone is not known.
        if trainLeavingTowards(train, along: [first] + path.traversals) != nil {
            let (until, overflow) = clock.now.seconds.addingReportingOverflow(Self.platformClearance)
            waits[target] = max(waits[target] ?? 0, overflow ? .max : until)
        }
        guard let own = waits[target], own > 0 else { return nil }
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
            var eligible = Set(all.filter { (waits[$0.traversal.edge] ?? .max) <= limit })
            // Decision 283: nor one another train is coming out of towards it.
            while !eligible.isEmpty {
                let found: TrainPath
                if let cut, let length = network.edge(cut.traversal.edge)?.length {
                    guard let rest = self.path(from: .onEdge(cut.traversal, offset: length), toStation: id, length: train.length, eligible: eligible, keepingLeft: true, memo: &memo) else { break }
                    found = TrainPath(traversals: Array(path.traversals.prefix(cut.index + 1)) + rest.traversals, end: rest.end, distance: cut.distance + rest.distance)
                } else {
                    guard let whole = self.path(from: start, toStation: id, length: train.length, eligible: eligible, keepingLeft: true, memo: &memo) else { break }
                    found = whole
                }
                let reached = (found.traversals.last ?? first).edge
                guard trainLeavingTowards(train, along: [first] + found.traversals) != nil else { return found }
                eligible = eligible.filter { $0.traversal.edge != reached }
            }
        }
        return nil
    }
}

extension GameWorld {
    /// The edges trains stand on, or are on without travelling to a call
    /// (decision 228): where ``freePlatformOnTheWay(of:standing:moving:memo:)``
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

    /// The edges trains travelling to a call are on (decision 283): where
    /// ``freePlatformOnTheWay(of:standing:moving:memo:)`` looks for one
    /// coming out of a platform's track. Empty under traffic control, or
    /// without a line of real runs.
    func movingEdges() -> Set<TrackEdgeID> {
        guard !isTrafficControlEnabled, lines.contains(where: { !$0.runs.isEmpty }) else { return [] }
        var edges: Set<TrackEdgeID> = []
        for train in trains {
            guard case .travellingToStop? = train.execution else { continue }
            for part in bodyStretches(of: train) { edges.insert(part.traversal.edge) }
        }
        return edges
    }

    /// Decision 228: the way to another of its call's platforms for
    /// `train`, of a line with real runs, on its way to a call with traffic
    /// control off, when another train stands on the one it is bound for
    /// and a better one is free (see ``freePlatformPath(_:from:toStation:for:next:memo:)``):
    /// a train that was due to leave it in time may not have. Decision 283:
    /// or when another train, late out of it, is coming along its track
    /// towards this one (see ``trainLeavingTowards(_:along:)``). `standing`
    /// and `moving` are where trains stand and travel as the services'
    /// phase begins (``standingEdges()``, ``movingEdges()``). `nil` when it
    /// keeps its way.
    func freePlatformOnTheWay(of train: Train, standing: Set<TrackEdgeID>, moving: Set<TrackEdgeID>, memo: inout PathMemo) -> TrainPath? {
        guard !isTrafficControlEnabled, case .travellingToStop(let stop, let cycle)? = train.execution,
              let position = train.position, case .onEdge(let traversal, let offset) = position else { return nil }
        let target = train.movement.remainingEdges.last ?? traversal.edge
        guard let length = network.edge(traversal.edge)?.length, followsRealTimetable(train) else { return nil }
        let standsThere = standing.contains(target) && trains.contains(where: { other in
            guard other.id != train.id else { return false }
            if case .travellingToStop? = other.execution { return false }
            return bodyStretches(of: other).contains { $0.traversal.edge == target }
        })
        guard standsThere || !moving.isDisjoint(with: platformTrack(of: target)) else { return nil }
        // Its way as it stands.
        let ahead = pathAhead(of: train)
        guard ahead.count == train.movement.remainingEdges.count else { return nil }
        if !standsThere, trainLeavingTowards(train, along: [traversal] + ahead) == nil { return nil }
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

extension GameWorld {
    /// Decision 283: the edges of the track a platform on `edge` lies on:
    /// `edge`, and on from it either way every edge up to the first node
    /// where more than two meet (a turnout) or a dead end. At a terminus,
    /// the track a train comes in by and goes out by, turned round.
    func platformTrack(of edge: TrackEdgeID) -> Set<TrackEdgeID> {
        var track: Set<TrackEdgeID> = [edge]
        guard let first = network.edge(edge) else { return track }
        for start in [first.from, first.to] {
            var node = start
            var from = edge
            while let ends = network.node(node)?.ends, ends.count == 2,
                  let next = ends.first(where: { $0.edge != from })?.edge, track.insert(next).inserted,
                  let nextEdge = network.edge(next) {
                node = nextEdge.from == node ? nextEdge.to : nextEdge.from
                from = next
            }
        }
        return track
    }

    /// Decision 283: another train, travelling to a call, whose body is on
    /// the track of the platform `way` ends at (``platformTrack(of:)``),
    /// running along it the other way round to `way`: coming out of that
    /// platform's track towards `train`, which runs `way` into it. `nil`
    /// when there is none.
    ///
    /// A platform a train is due to have left is free for the next one
    /// (decision 228), but a train late out of a terminus may still be on
    /// its track, waiting for the throat; the one bound for that track
    /// would stop short of it in the throat, and each would wait for the
    /// other.
    func trainLeavingTowards(_ train: Train, along way: [TrackTraversal]) -> TrainID? {
        guard let last = way.last else { return nil }
        let track = platformTrack(of: last.edge)
        let into = Set(way.filter { track.contains($0.edge) })
        for other in trains where other.id != train.id {
            guard case .travellingToStop? = other.execution else { continue }
            if bodyStretches(of: other).contains(where: { into.contains($0.traversal.reversed) }) { return other.id }
        }
        return nil
    }
}
