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
        guard isTrafficControlEnabled else { return [] }
        var memo = DirectionMemo()
        let deadlocked = Set(deadlock(memo: &memo).keys)
        return trains.sorted { $0.id < $1.id }.compactMap { train in
            guard let wait = awaitedRoute(of: train.id, memo: &memo) else { return nil }
            return RouteWait(train: train.id, holder: wait.holder, contested: contested(wait, for: train.id), isDeadlocked: deadlocked.contains(train.id))
        }
    }

    /// See ``contestedResources(of:)``.
    private func contested(_ wait: (holder: TrainID, needs: Set<TrackResource>?), for id: TrainID) -> [TrackResource] {
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
    private func awaitedRoute(of id: TrainID) -> (holder: TrainID, needs: Set<TrackResource>?)? {
        var memo = DirectionMemo()
        return awaitedRoute(of: id, memo: &memo)
    }

    private func awaitedRoute(of id: TrainID, memo: inout DirectionMemo) -> (holder: TrainID, needs: Set<TrackResource>?)? {
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil else { return nil }
        if let wait = currentTrafficWait(train, plan: trafficPlan(memo: &memo), memo: &memo) { return (wait.other, nil) }
        if isFollowing(train) {
            // Stage U2: a train following others waits for the rest of its
            // route.
            let needs = routeEnvelope(of: train).resources
            return holder(of: needs, except: id).map { ($0, needs) }
        }
        guard let departing = departureRequest(of: train, memo: &memo) else { return nil }
        if case .granted(let granted) = reservingDeparture(departing), !isFollowing(granted) { return nil }
        let needs = routeEnvelope(of: departing).resources
        return holder(of: needs, except: id).map { ($0, needs) }
    }

    // MARK: - What a train needs

    /// `candidate`, a train about to be given a place or a route, with the
    /// reservation traffic control gives it, or the lowest numbered other
    /// train that holds track it needs, with all the track it needs. With
    /// traffic control off, the candidate as it is.
    enum Reserving {
        case granted(Train)
        case held(by: TrainID, needs: Set<TrackResource>)
    }

    /// See ``Reserving``. A service's departure (`following`, Stage U2)
    /// whose route another train holds may instead follow the trains
    /// ahead, taking its route only part of the way (see
    /// ``followingAuthority(of:route:)``).
    func reserving(_ candidate: Train, following: Bool = false) -> Reserving {
        guard isTrafficControlEnabled else { return .granted(candidate) }
        let envelope = routeEnvelope(of: candidate)
        if let holder = holder(of: envelope.resources, except: candidate.id) {
            if following, envelope.moves, let train = followingAuthority(of: candidate, route: envelope.resources) {
                return .granted(train)
            }
            return .held(by: holder, needs: envelope.resources)
        }
        var train = candidate
        train.reservation = envelope.moves ? envelope.resources.sorted() : []
        return .granted(train)
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
        let planned = reserving(candidate, following: true)
        guard isTrafficControlEnabled, case .held = planned,
              case .travellingToStop(let stop, let cycle)? = candidate.execution,
              let alternative = alternativeRoute(of: candidate, to: candidate.timetable[stop].station,
                                                 avoiding: blockedTrack(except: candidate.id), memo: &memo)
        else { return planned }
        var rerouted = candidate
        follow(alternative, &rerouted)
        let previousStop = stop == 0 ? candidate.timetable.count - 1 : stop - 1
        let previousCycle = stop == 0 ? cycle - 1 : cycle
        let scheduled = candidate.scheduledArrival(of: stop, cycle: cycle).seconds
            - candidate.scheduledDeparture(of: previousStop, cycle: previousCycle).seconds
        let reroutedRun = run(of: rerouted, length: alternative.distance, scheduled: scheduled)
        rerouted.times?.run = reroutedRun
        if case .granted(let granted) = reserving(rerouted) { return .granted(granted) }
        return planned
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
    func alternativeRoute(of candidate: Train, to station: StationID, avoiding blocked: Set<TrackResource>, memo: inout DirectionMemo) -> TrainPath? {
        guard let position = candidate.position,
              let path = path(from: position, toStation: station, length: candidate.length,
                              avoiding: blocked, forbidden: opposingServiceTraversals(for: candidate, memo: &memo))
        else { return nil }
        let (limit, overflow) = routeLength(of: candidate).addingReportingOverflow(Self.detourAllowance)
        return overflow || path.distance <= limit ? path : nil
    }

    /// The lowest numbered train other than `id` that holds any of
    /// `resources` (see ``held(_:)``), or track that fouls any of them
    /// (Stage F2b, see ``RailwayNetwork/fouls(_:_:)``), or that follows
    /// another (Stage U2) and still needs some of them, unless train `id`
    /// already holds track that one needs (see ``claim(of:)``); or `nil`.
    func holder(of resources: Set<TrackResource>, except id: TrainID) -> TrainID? {
        let own = train(id: id).map(held) ?? []
        return trains.first { other in
            guard other.id != id, other.position != nil else { return false }
            if network.fouls(held(other), resources) { return true }
            guard let claim = claim(of: other), own.isDisjoint(with: claim.route) else { return false }
            return network.fouls(claim.waiting, resources)
        }?.id
    }

    /// Everything the trains other than `id` keep it from, together (see
    /// ``holder(of:except:)``): track fouling any of it has a holder. For
    /// trying many stretches against the same trains.
    func blockedTrack(except id: TrainID) -> Set<TrackResource> {
        let own = train(id: id).map(held) ?? []
        var blocked: Set<TrackResource> = []
        for other in trains where other.id != id && other.position != nil {
            blocked.formUnion(held(other))
            if let claim = claim(of: other), own.isDisjoint(with: claim.route) {
                blocked.formUnion(claim.waiting)
            }
        }
        return blocked
    }

    /// A train's reservation (see ``Train/reservation``), to ask whether it
    /// holds a resource: by halving while it is in resource order, as the
    /// game keeps it, else through a set of it. A set of a reservation some
    /// hundreds long, built for every question, was much of the time
    /// traffic control took.
    struct ReservedTrack {
        private let ordered: [TrackResource]
        private let unordered: Set<TrackResource>?

        init(_ reservation: [TrackResource]) {
            ordered = reservation
            unordered = zip(reservation, reservation.dropFirst()).allSatisfy { $0 < $1 } ? nil : Set(reservation)
        }

        func contains(_ resource: TrackResource) -> Bool {
            if let unordered { return unordered.contains(resource) }
            var (low, high) = (0, ordered.count)
            while low < high {
                let middle = (low + high) / 2
                if ordered[middle] < resource {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low < ordered.count && ordered[low] == resource
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
        let body = bodyStretches(of: train)
        var standing = Set(resources(covering: body))
        standing.formUnion(foulingNodes(covering: body))
        return HeldTrack(body: standing, reservation: train.reservation, reserved: ReservedTrack(train.reservation))
    }

    /// What every train holds (see ``held(_:)``) and, following another,
    /// claims (see ``claim(of:)``), worked out once to ask
    /// ``holder(of:except:holders:)`` and
    /// ``blockedTrack(except:holders:)`` of many trains of one world.
    struct TrackHolders {
        let held: [TrainID: HeldTrack]
        let claims: [TrainID: (route: Set<TrackResource>, waiting: Set<TrackResource>)]

        /// Whether train `id` holds any of `claim`'s route, which keeps it
        /// from waiting for that claim (see ``holder(of:except:)``).
        func holdsAny(of claim: (route: Set<TrackResource>, waiting: Set<TrackResource>), _ id: TrainID) -> Bool {
            guard let own = held[id] else { return false }
            return claim.route.contains(where: own.contains)
        }
    }

    func trackHolders() -> TrackHolders {
        trackHolders(authorities: trains.map(authority))
    }

    /// ``trackHolders()`` knowing ``authority(of:)`` of every train, in
    /// order.
    func trackHolders(authorities: [(left: Int64, envelopes: AuthorityEnvelopes)?]) -> TrackHolders {
        var held: [TrainID: HeldTrack] = [:]
        for train in trains {
            held[train.id] = heldTrack(train)
        }
        var claims: [TrainID: (route: Set<TrackResource>, waiting: Set<TrackResource>)] = [:]
        for (train, authority) in zip(trains, authorities) {
            // A following train's route envelope (see ``routeEnvelope(of:)``)
            // is the base and every piece of its envelopes.
            guard let envelopes = authority?.envelopes else { continue }
            let route = routeResources(envelopes)
            let others = trains.filter { $0.id != train.id && $0.position != nil }.map { held[$0.id]! }
            claims[train.id] = (route, route.filter { resource in !others.contains { $0.contains(resource) } })
        }
        return TrackHolders(held: held, claims: claims)
    }

    /// ``holder(of:except:)`` from `holders`, the world's (see
    /// ``trackHolders()``).
    func holder(of resources: Set<TrackResource>, except id: TrainID, holders: TrackHolders) -> TrainID? {
        trains.first { other in
            guard other.id != id, other.position != nil else { return false }
            if network.fouls(holders.held[other.id]!.resources, resources.contains) { return true }
            guard let claim = holders.claims[other.id], !holders.holdsAny(of: claim, id) else { return false }
            return network.fouls(claim.waiting, resources)
        }?.id
    }

    /// ``blockedTrack(except:)``, to ask a resource at a time.
    struct BlockedTrack {
        let held: [HeldTrack]
        let waiting: [Set<TrackResource>]

        func contains(_ resource: TrackResource) -> Bool {
            held.contains { $0.contains(resource) } || waiting.contains { $0.contains(resource) }
        }
    }

    /// ``blockedTrack(except:)`` from `holders`, the world's (see
    /// ``trackHolders()``).
    func blockedTrack(except id: TrainID, holders: TrackHolders) -> BlockedTrack {
        var held: [HeldTrack] = []
        var waiting: [Set<TrackResource>] = []
        for other in trains where other.id != id && other.position != nil {
            held.append(holders.held[other.id]!)
            if let claim = holders.claims[other.id], !holders.holdsAny(of: claim, id) {
                waiting.append(claim.waiting)
            }
        }
        return BlockedTrack(held: held, waiting: waiting)
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
            guard let length = network.edge(traversal.edge)?.length else { return ([], false) }
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
                stretches.append(TrackStretch(traversal: next, from: 0, to: network.edge(next.edge)!.length))
            }
            stretches.append(TrackStretch(traversal: last, from: 0, to: lastStop(network.edge(last.edge)!.length)))
            return (stretches, true)
        }
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
    struct AuthorityEnvelopes {
        /// The train's route stretches (see ``routeStretches(of:)``).
        let stretches: [TrackStretch]
        /// How far from the head each stretch ends (saturating).
        let ends: [Int64]
        /// What the train stands on and the junctions its body fouls (a
        /// resource may be listed twice).
        let base: [TrackResource]
        /// For each stretch, its track whole: what it covers and the
        /// junctions it fouls. The envelope to a distance is the base, the
        /// pieces of the stretches before the one it ends in, and that one
        /// as far as it goes.
        let pieces: [[TrackResource]]

        /// The length of the route (see ``GameWorld/routeLength(of:)``).
        var length: Int64 { ends.last ?? 0 }
    }

    func authorityEnvelopes(of train: Train) -> AuthorityEnvelopes {
        authorityEnvelopes(of: train, along: routeStretches(of: train).stretches)
    }

    /// ``authorityEnvelopes(of:)`` with `train`'s route stretches already
    /// worked out.
    private func authorityEnvelopes(of train: Train, along stretches: [TrackStretch]) -> AuthorityEnvelopes {
        let body = bodyStretches(of: train)
        let base = resources(covering: body) + foulingNodes(covering: body)
        var ends: [Int64] = []
        var pieces: [[TrackResource]] = []
        var end: Int64 = 0
        for stretch in stretches {
            let (sum, overflow) = end.addingReportingOverflow(stretch.to - stretch.from)
            end = overflow ? .max : sum
            ends.append(end)
            pieces.append(resources(covering: [stretch]) + foulingNodes(covering: [stretch]))
        }
        return AuthorityEnvelopes(stretches: stretches, ends: ends, base: base, pieces: pieces)
    }

    /// The track of the whole route (see ``routeEnvelope(of:)``): the base
    /// and every piece.
    func routeResources(_ envelopes: AuthorityEnvelopes) -> Set<TrackResource> {
        var resources = Set(envelopes.base)
        for piece in envelopes.pieces {
            resources.formUnion(piece)
        }
        return resources
    }

    /// The stretch the envelope to `distance` ends in (see
    /// ``authorityEnvelope(_:to:)``), its index, and how far into it the
    /// envelope goes: the first stretch always, even for no distance.
    /// - Precondition: `envelopes` has a stretch.
    private func authorityEnd(_ envelopes: AuthorityEnvelopes, to distance: Int64) -> (index: Int, part: TrackStretch) {
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
        for piece in envelopes.pieces[..<end.index] {
            resources.formUnion(piece)
        }
        resources.formUnion(self.resources(covering: [end.part]))
        resources.formUnion(foulingNodes(covering: [end.part]))
        return resources
    }

    /// Whether the envelope to `distance` (see ``authorityEnvelope(_:to:)``)
    /// is `clear`, as ``longestAuthority(_:from:clear:)`` asks it.
    func isAuthority(_ envelopes: AuthorityEnvelopes, to distance: Int64, clear: ([TrackResource]) -> Bool) -> Bool {
        let clearBase = clear(envelopes.base)
        guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
        let end = authorityEnd(envelopes, to: distance)
        return envelopes.pieces[..<end.index].allSatisfy(clear) && clear(resources(covering: [end.part]) + foulingNodes(covering: [end.part]))
    }

    /// ``isAuthority(_:to:clear:)``, knowing whether the base is clear and
    /// how many of the first stretches are clear whole.
    private func isAuthority(
        _ envelopes: AuthorityEnvelopes, to distance: Int64, clear: ([TrackResource]) -> Bool, clearBase: Bool, leading: Int
    ) -> Bool {
        guard clearBase, !envelopes.stretches.isEmpty else { return clearBase }
        let end = authorityEnd(envelopes, to: distance)
        guard end.index <= leading else { return false }
        return clear(resources(covering: [end.part]) + foulingNodes(covering: [end.part]))
    }

    /// The longest distance from `low` to the end of the route whose
    /// envelope (see ``authorityEnvelope(_:to:)``) is `clear`, found by
    /// halving: `low` when no longer one is. `clear` must hold of a set of
    /// track exactly when it holds of each part of it (as "held by the
    /// reservation" and "fouling nothing blocked" do), so each envelope is
    /// tried a part at a time (the base, the whole stretches before its
    /// end, and the part of the last), and never gathered.
    func longestAuthority(_ envelopes: AuthorityEnvelopes, from low: Int64, clear: ([TrackResource]) -> Bool) -> Int64 {
        let clearBase = clear(envelopes.base)
        // The stretches from the first that are clear whole.
        var leading = 0
        while clearBase, leading < envelopes.pieces.count, clear(envelopes.pieces[leading]) {
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
        let reservation = ReservedTrack(train.reservation)
        let route = routeStretches(of: train)
        // A reservation that holds where the route ends holds all of it: a
        // following train's ends at least ``followingGap`` short of that.
        guard let last = route.stretches.last,
              !resources(covering: [TrackStretch(traversal: last.traversal, from: last.to, to: last.to)]).allSatisfy(reservation.contains),
              route.moves
        else { return nil }
        // Its route envelope (see ``routeEnvelope(of:)``) is the base and
        // every piece together: a reservation holding all of them holds
        // the whole route.
        let envelopes = authorityEnvelopes(of: train, along: route.stretches)
        let holds = { (piece: [TrackResource]) in piece.allSatisfy(reservation.contains) }
        guard !holds(envelopes.base) || !envelopes.pieces.allSatisfy(holds) else { return nil }
        // The longest distance whose track the reservation holds.
        return (longestAuthority(envelopes, from: 0, clear: holds), envelopes)
    }

    /// Whether `train` follows another (Stage U2): under traffic control
    /// its reservation holds its route only part of the way. Only a
    /// service's departure takes a route part of the way, but a train
    /// whose service is stopped on the way keeps its path and its
    /// reservation, and so goes on following.
    func isFollowing(_ train: Train) -> Bool {
        authorityLeft(of: train) != nil
    }

    /// What following `train` (Stage U2) still needs and does not hold:
    /// `route` is its whole route envelope, `waiting` the part of it no
    /// train holds (see ``held(_:)``). No other train may take track it
    /// waits for, unless that train holds track of its route itself: one
    /// of the trains ahead, which it follows. `nil` for a train that does
    /// not follow another.
    func claim(of train: Train) -> (route: Set<TrackResource>, waiting: Set<TrackResource>)? {
        guard isFollowing(train) else { return nil }
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
    func followingAuthority(of candidate: Train, route: Set<TrackResource>) -> Train? {
        for other in trains where other.id != candidate.id && other.position != nil {
            guard holder(of: route, except: candidate.id, among: other) else { continue }
            guard isLeading(other, onto: route, for: candidate) else { return nil }
        }
        // The longest distance whose track no other train holds.
        let blocked = blockedTrack(except: candidate.id)
        let envelopes = authorityEnvelopes(of: candidate)
        let free = longestAuthority(envelopes, from: 0) { !network.fouls($0, blocked.contains) }
        let authority = free - Self.followingGap
        guard authority >= 1 else { return nil }
        var train = candidate
        train.reservation = authorityEnvelope(envelopes, to: authority).sorted()
        return train
    }

    /// Whether train `other` holds, fouls or waits for any of `resources`,
    /// as ``holder(of:except:)`` asks of each train for train `id`.
    private func holder(of resources: Set<TrackResource>, except id: TrainID, among other: Train) -> Bool {
        if network.fouls(held(other), resources) { return true }
        let own = train(id: id).map(held) ?? []
        guard let claim = claim(of: other), own.isDisjoint(with: claim.route) else { return false }
        return network.fouls(claim.waiting, resources)
    }

    /// Whether `train` leads the way along `route`, the route envelope of
    /// `follower`, a train that would follow it (see
    /// ``followingAuthority(of:route:)``). A train that runs along any edge
    /// of the follower's way the other way round comes towards it and is
    /// never followed.
    private func isLeading(_ train: Train, onto route: Set<TrackResource>, for follower: Train) -> Bool {
        guard case .travellingToStop(let stop, let cycle)? = train.execution, train.movement.rate > 0,
              routeEnvelope(of: train).moves, !isFollowing(train)
        else { return false }
        let ways = Set((bodyStretches(of: follower) + routeStretches(of: follower).stretches).map(\.traversal))
        for stretch in bodyStretches(of: train) + routeStretches(of: train).stretches where ways.contains(stretch.traversal.reversed) {
            return false
        }
        // Where it stops for its call.
        var arrived = train
        let end = travelling(arrived, distance: routeLength(of: train))
        arrived.position = end.position
        arrived.movement.cursor = end.cursor
        var standing = Set(occupied(arrived))
        standing.formUnion(foulingNodes(covering: bodyStretches(of: arrived)))
        guard standing.isDisjoint(with: route) else {
            return !train.timetable[stop].reverses && train.call(after: stop, cycle: cycle) != nil
        }
        return true
    }

    // MARK: - The resources of a stretch

    /// The end nodes, length and resource spans of edge `id`, from its
    /// `from` node, or `nil` if it does not exist.
    private func stretchFacts(of id: TrackEdgeID) -> (from: TrackNodeID, to: TrackNodeID, length: Int64, spans: [TrackSpan])? {
        guard let edge = network.edge(id) else { return nil }
        return (edge.from, edge.to, edge.length, network.spans(of: id, length: edge.length))
    }

    /// The track `stretches` cover, the one rule for occupancy and
    /// reservation alike (Stage S3A; ARCHITECTURE decision 32): every node a
    /// stretch reaches, and every span that shares a point with a stretch
    /// lying strictly between the edge's ends, so a train touching the
    /// boundary between two spans holds both. The rule is point by point,
    /// so the track of two stretches that meet is the track of the two
    /// together.
    func resources(covering stretches: [TrackStretch]) -> [TrackResource] {
        var resources: [TrackResource] = []
        for stretch in stretches {
            guard let edge = stretchFacts(of: stretch.traversal.edge) else { continue }
            let forward = stretch.traversal.direction == .forward
            if stretch.from == 0 { resources.append(.node(forward ? edge.from : edge.to)) }
            if stretch.to == edge.length { resources.append(.node(forward ? edge.to : edge.from)) }
            // The stretch in the edge's own chainage, from its `from` node.
            let (low, high) = forward ? (stretch.from, stretch.to) : (edge.length - stretch.to, edge.length - stretch.from)
            for span in edge.spans {
                let a = max(low, span.start)
                let b = min(high, span.end)
                // Some point of both, strictly between the edge's ends.
                if a < b || (a == b && a > 0 && a < edge.length) { resources.append(.span(span)) }
            }
        }
        return resources
    }

    /// The junctions of the track network `stretches` come close enough to
    /// foul (ARCHITECTURE decision 32, point 5): the node at an end of a
    /// stretch's edge when some point of the stretch lies less than
    /// ``RailwayNetwork/junctionZone`` from it along the edge, and the
    /// edge's end there is a fouling end (see ``isFoulingEnd(of:at:)``).
    /// Within that distance of a node two edges that end there may lie side
    /// by side (Stage S4 does not check their clearance there), so a train
    /// there takes the node as well.
    func foulingNodes(covering stretches: [TrackStretch]) -> [TrackResource] {
        var nodes: [TrackResource] = []
        for stretch in stretches {
            guard let edge = network.edge(stretch.traversal.edge) else { continue }
            let (low, high) = stretch.traversal.direction == .forward
                ? (stretch.from, stretch.to)
                : (edge.length - stretch.to, edge.length - stretch.from)
            if low < RailwayNetwork.junctionZone, isFoulingEnd(of: edge.id, at: edge.from) { nodes.append(.node(edge.from)) }
            if edge.length - high < RailwayNetwork.junctionZone, isFoulingEnd(of: edge.id, at: edge.to) { nodes.append(.node(edge.to)) }
        }
        return nodes
    }

    /// Whether a train holding `resource` holds track at or within
    /// ``RailwayNetwork/junctionZone`` of node `node` of the track network:
    /// the node itself, or a span of an edge ending there that reaches
    /// closer to it than that. Such track is where a new edge at the node
    /// could change who fouls the junction.
    func isWithinJunctionZone(_ resource: TrackResource, of node: TrackNodeID) -> Bool {
        switch resource {
        case .node(let held):
            return held == node
        case .span(let span):
            guard let edge = network.edge(span.edge) else { return false }
            return (edge.from == node && span.start < RailwayNetwork.junctionZone)
                || (edge.to == node && edge.length - span.end < RailwayNetwork.junctionZone)
        }
    }

    /// Whether edge `edge`'s end at node `node` is a fouling end: another
    /// edge ends there that it does not join (they do not leave the node in
    /// opposite directions), as a turnout's branches, a crossing's lines or
    /// two edges meeting at an angle do. A plain node, a dead end and a
    /// turnout's stem are not.
    func isFoulingEnd(of edge: TrackEdgeID, at node: TrackNodeID) -> Bool {
        guard let junction = network.node(node), let end = junction.end(of: edge) else { return false }
        return junction.ends.contains { $0.edge != edge && !end.exits.contains($0.edge) }
    }
}

extension TrackResource {
    /// Whether this is a span of edge `edge`.
    func isSpan(of edge: TrackEdgeID) -> Bool {
        if case .span(let span) = self { span.edge == edge } else { false }
    }
}
