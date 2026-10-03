import GameCore

/// Decision 32 (Stage T), written a second time for ``ReferenceWorld``:
/// traffic control and route reservation. Written from the rules, not from
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
///   worked out by running the departure on a copy of the world.
extension ReferenceWorld {
    static let junctionZone: Int64 = 1_024

    // MARK: - What a train needs

    /// Decision 32, points 3–5: the track `train` needs for the rest of its
    /// route (what it stands on, what its head still passes over and the
    /// junctions all that comes close enough to foul), and whether the route
    /// has any distance left.
    func needs(_ train: Train) -> (resources: Set<TrackResource>, moves: Bool) {
        guard case .onEdge(let traversal, let offset)? = train.position else { return ([], false) }
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
        let finish = spans(path)[path.count - 1].start + stop
        let window = (head - Self.length(train), max(head, finish))
        return (track(along: path, from: window.0, to: window.1), finish > head)
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
            let theirs = held(other)
            if resources.contains(where: theirs.contains) { return other.id }
        }
        return nil
    }

    /// `candidate` with the reservation its route needs, or the train that
    /// holds some of it; without traffic control, as it is.
    func admitted(_ candidate: Train) -> Result<Train, GameError> {
        guard trafficControl else { return .success(candidate) }
        let need = needs(candidate)
        if let other = holder(of: need.resources, except: candidate.id) { return .failure(.trackReserved(TrainID(rawValue: other))) }
        var train = candidate
        train.reservation = need.moves ? need.resources.sorted() : []
        return .success(train)
    }

    /// Commits `candidate` as train `i` if it is admitted.
    mutating func admit(_ candidate: Train, at i: Int) -> GameError? {
        switch admitted(candidate) {
        case .success(let train):
            trains[i] = train
            return nil
        case .failure(let error):
            return error
        }
    }

    /// After a step: a train whose route has no distance left drops its
    /// reservation.
    mutating func releaseIfArrived(_ i: Int) {
        if !trains[i].reservation.isEmpty, !needs(trains[i]).moves { trains[i].reservation = [] }
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
            for earlier in 0..<later where !wanted[earlier].resources.isDisjoint(with: wanted[later].resources) {
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
        var leaving: Train?
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
            leaving = firstLeaving(sent)
        }
        guard let leaving else { return nil }
        return holder(of: needs(leaving).resources, except: train.id).map(TrainID.init(rawValue:))
    }

    /// One departure of `train` from its waiting stop, on a copy of the
    /// world without traffic control: the train as it would leave, or `nil`
    /// if it cannot.
    func firstLeaving(_ train: Train) -> Train? {
        var trial = self
        trial.trafficControl = false
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
