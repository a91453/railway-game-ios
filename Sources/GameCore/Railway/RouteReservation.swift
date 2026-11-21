// Route reservation (Phase 4.6 Stage T, ARCHITECTURE decision 32). Under
// traffic control a train takes the whole of a route before it starts
// along it: everything its whole length covers from where its tail is to
// where the route ends, as one atomic reservation, or nothing. No two trains
// ever hold the same track: what a train stands on, the junctions it is
// close enough to foul, and what it has reserved. A command that would give
// a train track another train holds is refused (trackReserved), and a
// service or a line whose route is held waits where it is and tries again
// at every step.
//
// The reservation is authoritative state kept on the train. Since Stage U
// (ARCHITECTURE decision 55) it is released behind the train as it goes:
// after every move it keeps only what the train still needs, so track the
// train's tail has left is free for others at once, and all of it is
// released when the route ends. Since Stage U2 (ARCHITECTURE decision 56) a
// service may follow a train ahead of it between calls: it takes the route
// as far as ``GameWorld/followingGap`` short of the track the train ahead
// holds, and the rest as it frees.
// Everything here reads topology and integer chainage only: traversals,
// spans, edge lengths, platforms and where paths end, never geometry.
//
// A leg of 30 to 180 km is thousands of spans, so the questions are asked
// without listing them (NEXT_PRIORITIES 2026-10-12 §2 item 6, every answer
// as before): a route envelope is kept as its stretches, by edge and
// chainage (TrackCover); who holds what is worked out once for the trains
// as they are and looked up by edge (TrackHolders), and kept, with each
// train's movement authority, in a memo for as long as the trains stay as
// they are.

/// A stretch of one edge that a train covers: along
/// `traversal`, from `from` to `to`, both measured the way it is travelled
/// from its start (`0 <= from <= to <=` its length).
struct TrackStretch: Hashable, Sendable {
    let traversal: TrackTraversal
    let from: Int64
    let to: Int64
}

/// A train waiting for its route under traffic control (Stage V4e,
/// decision 64; see ``GameWorld/routeWaits()``).
public struct RouteWait: Hashable, Sendable {
    public let train: TrainID
    /// The train holding its route (see ``GameWorld/trainHoldingRoute(of:)``).
    public let holder: TrainID
    /// The track where the two meet (see
    /// ``GameWorld/contestedResources(of:)``).
    public let contested: [TrackResource]
    /// Whether it is in a deadlock (see ``GameWorld/deadlockedTrains()``).
    public let isDeadlocked: Bool

    public init(train: TrainID, holder: TrainID, contested: [TrackResource], isDeadlocked: Bool) {
        self.train = train
        self.holder = holder
        self.contested = contested
        self.isDeadlocked = isDeadlocked
    }
}

extension GameWorld {
    // MARK: - Queries

    /// The track train `id` has reserved for its route under traffic
    /// control, in resource order (see ``Train/reservation``): everything
    /// its whole length covers from where its tail was when it took the
    /// route to where the route ends, with the junctions it fouls on the
    /// way. Empty when traffic control is off, for a train with no way left
    /// to go, and for an unplaced train or an unknown ID.
    public func reservedResources(of id: TrainID) -> [TrackResource] {
        train(id: id)?.reservation ?? []
    }

    /// The track train `id` holds under traffic control, in resource order:
    /// what it stands on (see ``occupiedResources(of:)``), each junction of
    /// the track network it is close enough to foul (within
    /// ``RailwayNetwork/junctionZone`` of the node, on an edge that meets
    /// another there without joining it), and its reservation. No other
    /// train can take any of it. Empty for an unplaced train or an unknown
    /// ID.
    public func heldResources(of id: TrainID) -> [TrackResource] {
        guard let train = train(id: id) else { return [] }
        return held(train).sorted()
    }

    /// The train that holds track on the route train `id` is waiting to
    /// take under traffic control, or `nil`: the lowest numbered such train.
    ///
    /// A service waits for its route at a stop where its departure is due
    /// (its doors have closed; Stage W2b): from where it would stand
    /// (turned round first where the stop says so), along the path to its
    /// next call. A line's train waits
    /// for its route when it has no service, stands at its service's first
    /// call ready to go, and the line is due to send a train out: along the
    /// first leg of its trip. A service stopped at a passing place (Stage
    /// V2, see ``deadlockedTrains()``) waits for its route on to its call.
    /// `nil` when traffic control is off, for a
    /// train not waiting for a route (not due, without a route, or with its
    /// route free), and for an unknown ID. Derived on every call, never
    /// saved.
    public func trainHoldingRoute(of id: TrainID) -> TrainID? {
        awaitedRoute(of: id)?.holder
    }

    /// Stage V4e (decision 64): where train `id` and the train holding its
    /// route (see ``trainHoldingRoute(of:)``) meet, in resource order: the
    /// track of the route it waits to take that the holder holds or fouls
    /// (see ``RailwayNetwork/fouls(_:_:)``), or, following trains ahead
    /// (Stage U2), still waits for. For a map to show what keeps it. Empty
    /// when it waits for no route, and for a scheduled wait (decision 59),
    /// which keeps it at a station for a train by plan, not for track. Derived
    /// on every call, never saved.
    public func contestedResources(of id: TrainID) -> [TrackResource] {
        awaitedRoute(of: id).map { contested($0, for: id) } ?? []
    }

    /// Every train waiting for its route under traffic control, in
    /// ascending ID order (Stage V4e, decision 64): what
    /// ``trainHoldingRoute(of:)``, ``contestedResources(of:)`` and
    /// ``deadlockedTrains()`` tell of each, worked out together for a map
    /// to draw at once. Empty with traffic control off. Derived on every
    /// call, never saved.
    public func routeWaits() -> [RouteWait] {
        guard isTrafficControlEnabled else {
            // Decision 805: the trains standing for good in or behind a
            // ring, each with the train that holds it.
            return spacingDeadlock().sorted { $0.key < $1.key }.map { RouteWait(train: $0.key, holder: $0.value, contested: [], isDeadlocked: true) }
        }
        var memo = questionMemo()
        let deadlocked = Set(deadlock(memo: &memo).keys)
        return trains.sorted { $0.id < $1.id }.compactMap { train in
            guard let wait = awaitedRoute(of: train.id, memo: &memo) else { return nil }
            return RouteWait(train: train.id, holder: wait.holder, contested: contested(wait, for: train.id), isDeadlocked: deadlocked.contains(train.id))
        }
    }

    /// See ``contestedResources(of:)``.
    func contested(_ wait: (holder: TrainID, needs: Set<TrackResource>?), for id: TrainID) -> [TrackResource] {
        guard let needs = wait.needs, let holder = train(id: wait.holder) else { return [] }
        var blocking = held(holder)
        if let claim = claim(of: holder), (train(id: id).map(held) ?? []).isDisjoint(with: claim.route) {
            blocking.formUnion(claim.waiting)
        }
        return needs.filter { network.fouls([$0], blocking) }.sorted()
    }

    /// The train holding the route train `id` waits for (see
    /// ``trainHoldingRoute(of:)``), with the track that route needs; `nil`
    /// track for a scheduled wait.
    func awaitedRoute(of id: TrainID) -> (holder: TrainID, needs: Set<TrackResource>?)? {
        var memo = questionMemo()
        return awaitedRoute(of: id, memo: &memo)
    }

    func awaitedRoute(of id: TrainID, memo: inout DirectionMemo) -> (holder: TrainID, needs: Set<TrackResource>?)? {
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil else { return nil }
        if let wait = currentTrafficWait(train, plan: trafficPlan(memo: &memo), memo: &memo) { return (wait.other, nil) }
        if isFollowing(train, memo: &memo) {
            // Stage U2: a train following others waits for the rest of its
            // route.
            let needs = routeEnvelope(of: train).resources
            return holder(of: needs, except: id, memo: &memo).map { ($0, needs) }
        }
        guard let departing = departureRequest(of: train, memo: &memo) else { return nil }
        // Decision 718: the track lets it go, and it gives its turn to a
        // service that has waited longer. As a scheduled wait, it is kept
        // for a train, not for track.
        if case .granted(let granted) = takingDeparture(departing, memo: &memo), let first = turnOwed(by: granted, memo: &memo) {
            return (first, nil)
        }
        if case .granted(let granted) = reservingDeparture(departing, memo: &memo), !isFollowing(granted, memo: &memo) { return nil }
        let needs = routeEnvelope(of: departing).resources
        if let holder = holder(of: needs, except: id, memo: &memo) { return (holder, needs) }
        // Decision 740: its default way is free, but the platforms of its
        // list are taken: it waits for the train on the first.
        if listedDepartures(of: departing, memo: &memo.paths) != nil, case .held(let first) = reservingDeparture(departing, memo: &memo) {
            return (first, nil)
        }
        return nil
    }
}
