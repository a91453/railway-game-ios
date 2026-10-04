import GameCore

/// Decision 32 (Stage T), written a second time for ``ReferenceWorld``:
/// traffic control and route reservation, released behind a train as it
/// goes (decision 55, Stage U), and a service following the trains ahead
/// of it (decision 56, Stage U2). Written from the rules, not from
/// GameCore, and differently where it can be:
///
/// - what a train needs is read off one window of absolute distance along
///   the whole path it came by and will go by (its body and its route
///   joined end to end), not stretch by stretch;
/// - a fouling end is found by scanning every edge for those that end at
///   the node and testing each against the runs that leave it, on every
///   query;
/// - a holder is found by testing each resource against every other train
///   in turn; shared track when turning traffic control on is looked for
///   pair by pair;
/// - whether a line's train is ready, and what a departure would take, is
///   worked out by running the departure on a copy of the world;
/// - how far a following train may go, and how much of its route is free,
///   is found by walking the points where the track its window covers
///   changes, in order, not by bisection.
extension ReferenceWorld {
    static let junctionZone: Int64 = 1_024

    // MARK: - What a train needs

    /// Decision 32, points 3–5: the track `train` needs for the rest of its
    /// route (what it stands on, what its head still passes over and the
    /// junctions all that comes close enough to foul), and whether the route
    /// has any distance left.
    func needs(_ train: Train) -> (resources: Set<TrackResource>, moves: Bool) {
        guard let window = routeWindow(train) else { return ([], false) }
        return (track(along: window.path, from: window.head - Self.length(train), to: max(window.head, window.finish)), window.finish > window.head)
    }

    /// The runs `train` covers from its tail to as far along its route as
    /// it can go, its head's distance along them, and where its route ends.
    func routeWindow(_ train: Train) -> (path: [Run], head: Int64, finish: Int64)? {
        guard case .onEdge(let traversal, let offset)? = train.position else { return nil }
        var path = path(of: train)
        let head = spans(path)[path.count - 1].start + offset
        // The runs it will enter, as far as it can.
        var run = Run(traversal)!
        var index = train.cursor
        while index < train.edges.count, let next = runs(after: run).first(where: { $0.edge == train.edges[index] }) {
            path.append(next)
            run = next
            index += 1
        }
        let lastLength = networkEdges[run.edge]!.length
        let stop = index == train.edges.count ? (train.end ?? lastLength) : lastLength
        return (path, head, spans(path)[path.count - 1].start + stop)
    }

    /// What `train` holds under traffic control: what it stands on, the
    /// junctions its body fouls, and its reservation.
    func held(_ train: Train) -> Set<TrackResource> {
        var found = Set(occupied(train)).union(train.reservation)
        if case .onEdge(_, let offset)? = train.position {
            let path = path(of: train)
            let head = spans(path)[path.count - 1].start + offset
            found.formUnion(fouled(along: path, from: head - Self.length(train), to: head))
        }
        return found
    }

    /// Every node and span, and every fouled junction, of the stretch from
    /// `from` to `to` in absolute distance along `path`.
    private func track(along path: [Run], from: Int64, to: Int64) -> Set<TrackResource> {
        var found: Set<TrackResource> = []
        for (run, span) in zip(path, spans(path)) {
            if from <= span.start && span.start <= to { found.insert(.node(.node(startNode(run)))) }
            if from <= span.end && span.end <= to { found.insert(.node(.node(endNode(run)))) }
            for piece in resourceSpans(of: run.edge, length: span.end - span.start) {
                let (a, b) = run.forward ? (span.start + piece.start, span.start + piece.end) : (span.end - piece.end, span.end - piece.start)
                let low = max(from, a)
                let high = min(to, b)
                if low < high || (low == high && low > span.start && low < span.end) {
                    found.insert(.span(TrackSpan(edge: .edge(run.edge), start: piece.start, end: piece.end)))
                }
            }
        }
        return found.union(fouled(along: path, from: from, to: to))
    }

    /// The junctions the stretch from `from` to `to` along `path` fouls: a
    /// run's start or end node when part of the stretch on that run lies
    /// less than 1024 from it and the run's edge ends there as a fouling end.
    private func fouled(along path: [Run], from: Int64, to: Int64) -> Set<TrackResource> {
        var found: Set<TrackResource> = []
        for (run, span) in zip(path, spans(path)) {
            let low = max(from, span.start)
            let high = min(to, span.end)
            guard low <= high else { continue }
            if low - span.start < Self.junctionZone, fouls(run.edge, at: startNode(run)) { found.insert(.node(.node(startNode(run)))) }
            if span.end - high < Self.junctionZone, fouls(run.edge, at: endNode(run)) { found.insert(.node(.node(endNode(run)))) }
        }
        return found
    }

    /// Whether edge `number` ends at `node` beside another edge it does not
    /// join there.
    func fouls(_ number: Int, at node: Int) -> Bool {
        guard let edge = networkEdges[number] else { return false }
        let arriving = Run(edge: number, forward: edge.to == node)
        let joined = Set(runs(after: arriving).map(\.edge))
        return networkEdges.contains { other in
            other.key != number && (other.value.from == node || other.value.to == node) && !joined.contains(other.key)
        }
    }

    // MARK: - Taking track

    /// Under traffic control, the lowest numbered other train holding any
    /// of `resources`.
    func holder(of resources: Set<TrackResource>, except id: Int) -> Int? {
        for other in trains.sorted(by: { $0.id < $1.id }) where other.id != id && other.position != nil {
            if blocks(other, resources, for: id) { return other.id }
        }
        return nil
    }

    /// Whether `other` keeps train `id` from `resources`: it holds or
    /// fouls some of them, or (decision 56) it follows a train ahead and
    /// still waits for some of them, while train `id` holds none of its
    /// route.
    func blocks(_ other: Train, _ resources: Set<TrackResource>, for id: Int) -> Bool {
        foul(resources, blocking(other, for: id))
    }

    /// The track `other` keeps train `id` from: all it holds and, while it
    /// follows a train ahead and train `id` holds none of its route, the
    /// rest of that route nobody holds.
    private func blocking(_ other: Train, for id: Int) -> Set<TrackResource> {
        let own = held(other)
        guard following(other) else { return own }
        let route = needs(other).resources
        if let train = trains.first(where: { $0.id == id }), !held(train).isDisjoint(with: route) { return own }
        var waiting = route
        for train in trains where train.id != other.id && train.position != nil {
            waiting.subtract(held(train))
        }
        return own.union(waiting)
    }

    /// Everything the other trains keep train `id` from, together.
    func blocked(for id: Int) -> Set<TrackResource> {
        trains.filter { $0.id != id && $0.position != nil }.reduce(into: []) { $0.formUnion(blocking($1, for: id)) }
    }

    /// Decision 57: test a single run interval using the reference's
    /// absolute-distance resource window, including junction fouling.
    func unblocked(_ run: Run, from: Int64, to: Int64, by blocked: Set<TrackResource>) -> Bool {
        blocked.isEmpty || !foul(track(along: [run], from: from, to: to), blocked)
    }

    /// `candidate` with the reservation its route needs, or the train that
    /// holds some of it; without traffic control, as it is.
    func admitted(_ candidate: Train, following: Bool = false) -> Result<Train, GameError> {
        guard trafficControl else { return .success(candidate) }
        let need = needs(candidate)
        if let other = holder(of: need.resources, except: candidate.id) {
            if following, need.moves, let train = followed(candidate) { return .success(train) }
            return .failure(.trackReserved(TrainID(rawValue: other)))
        }
        var train = candidate
        train.reservation = need.moves ? need.resources.sorted() : []
        return .success(train)
    }

    /// Commits `candidate` as train `i` if it is admitted.
    mutating func admit(_ candidate: Train, at i: Int, following: Bool = false) -> GameError? {
        switch admitted(candidate, following: following) {
        case .success(let train):
            trains[i] = train
            return nil
        case .failure(let error):
            return error
        }
    }

    /// After a train's move in a second (decision 55, Stage U): its
    /// reservation keeps only what it needs from where it is now, so the
    /// track behind its tail goes, and a train whose route has no distance
    /// left drops it all (decision 32). This takes nothing: a following
    /// train (decision 56) holds only part of what it needs.
    mutating func releaseBehind(_ i: Int) {
        guard !trains[i].reservation.isEmpty else { return }
        let need = needs(trains[i])
        trains[i].reservation = need.moves ? Set(trains[i].reservation).intersection(need.resources).sorted() : []
    }

    // MARK: - Following (decision 56)

    static let followingGap: Int64 = 25_600

    /// Whether `train` follows a train ahead: under traffic control its
    /// reservation does not hold all it needs (a service set off so, or
    /// one stopped since, keeping its path).
    func following(_ train: Train) -> Bool {
        guard trafficControl, !train.reservation.isEmpty else { return false }
        return !needs(train).resources.isSubset(of: Set(train.reservation))
    }

    /// The distances along `window`'s path, beyond its head and up to its
    /// finish, at which the track of the window from its tail grows: inside
    /// an edge, where a span starts; an edge's end, where the next node is
    /// reached; and 1023 short of an edge's end, where a fouled junction is
    /// first within 1024. Between two of them the window holds the same
    /// track as at the first.
    private func breakpoints(_ window: (path: [Run], head: Int64, finish: Int64)) -> [Int64] {
        var points: Set<Int64> = []
        for (run, span) in zip(window.path, spans(window.path)) {
            points.insert(span.end)
            points.insert(span.end - Self.junctionZone + 1)
            for piece in resourceSpans(of: run.edge, length: span.end - span.start) {
                points.insert(run.forward ? span.start + piece.start : span.end - piece.end)
            }
        }
        return points.filter { $0 > window.head && $0 <= window.finish }.sorted()
    }

    /// How far `train`'s head may go before the window from its tail would
    /// cover track `allowed` rejects: the first breakpoint whose track is
    /// rejected, less one, or the finish. The window only grows along the
    /// breakpoints, so the first rejected one is found by halving them.
    private func reach(_ train: Train, allowed: (Set<TrackResource>) -> Bool) -> Int64 {
        guard let window = routeWindow(train) else { return 0 }
        let tail = window.head - Self.length(train)
        let points = breakpoints(window)
        var (low, high) = (0, points.count)
        while low < high {
            let middle = (low + high) / 2
            if allowed(track(along: window.path, from: tail, to: points[middle])) { low = middle + 1 } else { high = middle }
        }
        return low < points.count ? points[low] - 1 - window.head : window.finish - window.head
    }

    /// How far a following train may go: as far as its reservation holds
    /// the track; `nil` for one that does not follow.
    func authority(_ train: Train) -> Int64? {
        guard following(train) else { return nil }
        let reservation = Set(train.reservation)
        return reach(train) { $0.isSubset(of: reservation) }
    }

    /// The track `train` needs to go `distance` on from where its head is.
    private func needs(_ train: Train, upTo distance: Int64) -> Set<TrackResource> {
        guard let window = routeWindow(train) else { return [] }
        return track(along: window.path, from: window.head - Self.length(train), to: window.head + distance)
    }

    /// Whether `other` leads the way for `candidate`, whose route needs
    /// `route`: a travelling service with all it needs reserved and a rate,
    /// never on a run of the candidate's way the other way round, whose
    /// stop is off that route, or which goes on from its stop to a later
    /// call without turning round.
    private func leads(_ other: Train, onto route: Set<TrackResource>, for candidate: Train) -> Bool {
        guard trafficControl, let service = other.service, !service.waiting, other.rate > 0 else { return false }
        let need = needs(other)
        guard need.moves, need.resources.isSubset(of: Set(other.reservation)), let window = routeWindow(other) else { return false }
        let ways = Set(routeWindow(candidate)?.path ?? [])
        if window.path.contains(where: { ways.contains(Run(edge: $0.edge, forward: !$0.forward)) }) { return false }
        let standing = track(along: window.path, from: window.finish - Self.length(other), to: window.finish)
        if standing.isDisjoint(with: route) { return true }
        let stop = other.timetable[service.stop]
        let hasNext = service.stop + 1 < other.timetable.count || (other.period != nil && Self.fits(other, cycle: service.cycle + 1))
        return !stop.reverses && hasNext
    }

    /// `candidate`, a service setting off, following the trains that hold
    /// its route: every one of them leads the way, and it holds its route
    /// as far as 400 m short of the first track another holds, to the end
    /// of the span there; `nil` if it may not, or would not get anywhere.
    private func followed(_ candidate: Train) -> Train? {
        let route = needs(candidate).resources
        for other in trains.sorted(by: { $0.id < $1.id }) where other.id != candidate.id && other.position != nil {
            if blocks(other, route, for: candidate.id), !leads(other, onto: route, for: candidate) { return nil }
        }
        let blocked = blocked(for: candidate.id)
        let free = reach(candidate) { !foul($0, blocked) }
        guard free - Self.followingGap >= 1 else { return nil }
        var train = candidate
        train.reservation = needs(candidate, upTo: free - Self.followingGap).sorted()
        return train
    }

    /// Before anything sets off in a second: each following train in ID
    /// order takes all it needs when nobody holds any of it, or else as
    /// far as 400 m short of the first track another holds, when that is
    /// farther than its reservation holds it.
    mutating func extendFollowing() {
        for i in trains.indices.sorted(by: { trains[$0].id < trains[$1].id }) {
            guard let held = authority(trains[i]) else { continue }
            let need = needs(trains[i])
            if holder(of: need.resources, except: trains[i].id) == nil {
                trains[i].reservation = need.resources.sorted()
                continue
            }
            let blocked = blocked(for: trains[i].id)
            let free = reach(trains[i]) { !foul($0, blocked) }
            guard free - Self.followingGap > held else { continue }
            trains[i].reservation = Set(trains[i].reservation).union(needs(trains[i], upTo: free - Self.followingGap)).sorted()
        }
    }

    // MARK: - Commands and queries

    mutating func setTrafficControl(_ enabled: Bool) -> GameError? {
        guard enabled else {
            trafficControl = false
            for i in trains.indices { trains[i].reservation = [] }
            return nil
        }
        guard !trafficControl else { return nil }
        let placed = trains.filter { $0.position != nil }.sorted { $0.id < $1.id }
        let wanted = placed.map { needs($0) }
        for later in placed.indices {
            for earlier in 0..<later where foul(wanted[earlier].resources, wanted[later].resources) {
                return .trainsShareTrack(TrainID(rawValue: placed[earlier].id), TrainID(rawValue: placed[later].id))
            }
        }
        trafficControl = true
        for (train, need) in zip(placed, wanted) where need.moves {
            trains[trains.firstIndex { $0.id == train.id }!].reservation = need.resources.sorted()
        }
        return nil
    }

    func reservedResources(of id: TrainID) -> [TrackResource] {
        trains.first { $0.id == id.rawValue }?.reservation ?? []
    }

    func heldResources(of id: TrainID) -> [TrackResource] {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return [] }
        return held(train).sorted()
    }

    /// Decision 32, point 11: the service due to leave, or the line's train
    /// the line is due to send out, whose route another train holds.
    func trainHoldingRoute(of id: TrainID) -> TrainID? {
        guard trafficControl, let i = trains.firstIndex(where: { $0.id == id.rawValue }), trains[i].position != nil else { return nil }
        let train = trains[i]
        if following(train) {
            return holder(of: needs(train).resources, except: train.id).map(TrainID.init(rawValue:))
        }
        var leaving: Train?
        var requesting = train
        if let service = train.service {
            // Stage W2b: due once its doors have closed.
            guard service.waiting, let closing = service.closing, Self.capped(closing, 9) <= clockSeconds else { return nil }
            leaving = firstLeaving(train)
        } else {
            guard let (l, k) = lineService(of: id.rawValue), let trip = readyTrip(of: train, line: l, service: k) else { return nil }
            var sent = train
            sent.timetable = trip
            sent.period = nil
            sent.service = Service(stop: 0, waiting: true, arrival: clockSeconds)
            requesting = sent
            leaving = firstLeaving(sent)
        }
        guard let leaving else { return nil }
        if let available = firstLeaving(requesting, withTrafficControl: true), !following(available) { return nil }
        return holder(of: needs(leaving).resources, except: train.id).map(TrainID.init(rawValue:))
    }

    /// One departure of `train` from its waiting stop, on a copy of the
    /// world: without traffic control by default for the planned route,
    /// or with it for dispatch readiness and waiting queries (V1). Returns
    /// the train as it would leave, or `nil` if it cannot.
    func firstLeaving(_ train: Train, withTrafficControl: Bool = false) -> Train? {
        var trial = self
        trial.trafficControl = withTrafficControl && trafficControl
        guard let i = trial.trains.firstIndex(where: { $0.id == train.id }) else { return nil }
        trial.trains[i] = train
        let before = trial.trains[i]
        _ = trial.departOnce(i)
        return trial.trains[i] == before ? nil : trial.trains[i]
    }

    /// The line and service (0 for the line's own) train `id` is assigned to.
    func lineService(of id: Int) -> (Int, Int)? {
        for (l, line) in lines.enumerated() {
            if line.roster.contains(id) { return (l, 0) }
            if let k = line.patterns.firstIndex(where: { $0.roster.contains(id) }) { return (l, k + 1) }
        }
        return nil
    }

    /// Whether `resource` is at node `node` or within 1024 of it on an edge
    /// that ends there.
    func nearJunction(_ resource: TrackResource, _ node: Int) -> Bool {
        switch resource {
        case .node(let held):
            return held == .node(node)
        case .span(let span):
            guard case .edge(let number) = span.edge, let edge = networkEdges[number] else { return false }
            return (edge.from == node && span.start < Self.junctionZone) || (edge.to == node && edge.length - span.end < Self.junctionZone)
        }
    }

    /// The lowest numbered train holding a span of `edge`, for platform
    /// changes under traffic control.
    func holderOfSpans(on edge: TrackEdgeID) -> Int? {
        guard trafficControl else { return nil }
        return trains.sorted { $0.id < $1.id }.first { train in
            held(train).contains { if case .span(let span) = $0 { span.edge == edge } else { false } }
        }?.id
    }
}
