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
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil else { return nil }
        if isFollowing(train) {
            // Stage U2: a train following others waits for the rest of its
            // route.
            return holder(of: routeEnvelope(of: train).resources, except: id)
        }
        guard let departing = departureRequest(of: train) else { return nil }
        if case .granted(let granted) = reservingDeparture(departing), !isFollowing(granted) { return nil }
        return holder(of: routeEnvelope(of: departing).resources, except: id)
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

    /// The track `train` holds: what it stands on, the junctions its body
    /// fouls, and its reservation.
    func held(_ train: Train) -> Set<TrackResource> {
        var resources = Set(occupied(train))
        resources.formUnion(foulingNodes(covering: bodyStretches(of: train)))
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
        var resources = Set(occupied(train))
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
        /// For each stretch, everything before it: what the train stands
        /// on, the junctions its body fouls, and the track of every earlier
        /// stretch whole. One more than the stretches: the last is all of
        /// it.
        let before: [Set<TrackResource>]

        /// The length of the route (see ``GameWorld/routeLength(of:)``).
        var length: Int64 { ends.last ?? 0 }
    }

    func authorityEnvelopes(of train: Train) -> AuthorityEnvelopes {
        let stretches = routeStretches(of: train).stretches
        var resources = Set(occupied(train))
        resources.formUnion(foulingNodes(covering: bodyStretches(of: train)))
        var before = [resources]
        var ends: [Int64] = []
        var end: Int64 = 0
        for stretch in stretches {
            let (sum, overflow) = end.addingReportingOverflow(stretch.to - stretch.from)
            end = overflow ? .max : sum
            ends.append(end)
            resources.formUnion(self.resources(covering: [stretch]))
            resources.formUnion(foulingNodes(covering: [stretch]))
            before.append(resources)
        }
        return AuthorityEnvelopes(stretches: stretches, ends: ends, before: before)
    }

    /// ``authorityEnvelope(of:to:)`` from `envelopes`: the stretches before
    /// the one `distance` ends in whole, and that one as far as it goes
    /// (the first always, even for no distance).
    func authorityEnvelope(_ envelopes: AuthorityEnvelopes, to distance: Int64) -> Set<TrackResource> {
        guard !envelopes.stretches.isEmpty else { return envelopes.before[0] }
        let index = envelopes.ends.firstIndex { distance <= $0 } ?? envelopes.stretches.count - 1
        let stretch = envelopes.stretches[index]
        let start = index == 0 ? 0 : envelopes.ends[index - 1]
        let length = min(stretch.to - stretch.from, max(distance - start, 0))
        let part = [TrackStretch(traversal: stretch.traversal, from: stretch.from, to: stretch.from + length)]
        var resources = envelopes.before[index]
        resources.formUnion(self.resources(covering: part))
        resources.formUnion(foulingNodes(covering: part))
        return resources
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
        guard isTrafficControlEnabled, !train.reservation.isEmpty else { return nil }
        let reservation = Set(train.reservation)
        let route = routeStretches(of: train)
        // A reservation that holds where the route ends holds all of it: a
        // following train's ends at least ``followingGap`` short of that.
        guard let last = route.stretches.last,
              !resources(covering: [TrackStretch(traversal: last.traversal, from: last.to, to: last.to)]).allSatisfy(reservation.contains)
        else { return nil }
        let envelope = routeEnvelope(of: train)
        guard envelope.moves, !envelope.resources.isSubset(of: reservation) else { return nil }
        // The longest distance whose track the reservation holds.
        let envelopes = authorityEnvelopes(of: train)
        var (low, high) = (Int64(0), envelopes.length)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if authorityEnvelope(envelopes, to: middle).isSubset(of: reservation) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
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
        var (low, high) = (Int64(0), envelopes.length)
        while low < high {
            let middle = low + (high - low + 1) / 2
            if !network.fouls(authorityEnvelope(envelopes, to: middle), blocked) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        let authority = low - Self.followingGap
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
