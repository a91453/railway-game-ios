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
// (ARCHITECTURE decision 54) it is released behind the train as it goes:
// after every move it keeps only what the train still needs, so track the
// train's tail has left is free for others at once, and all of it is
// released when the route ends.
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
    /// first leg of its trip. `nil` when traffic control is off, for a
    /// train not waiting for a route (not due, without a route, or with its
    /// route free), and for an unknown ID. Derived on every call, never
    /// saved.
    public func trainHoldingRoute(of id: TrainID) -> TrainID? {
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil else { return nil }
        let departing: Train?
        if case .waitingAtStop(let stop, let cycle)? = train.execution {
            guard let due = departureDue(of: train), due <= clock.now else { return nil }
            departing = leaving(train, stop: stop, cycle: cycle).train
        } else if train.execution == nil, let line = lines.first(where: { assignedLine(of: id) == $0.id }),
                  let stream = line.dispatchStream(of: id) {
            var memo = DispatchMemo()
            guard isDispatchDue(line, stream, at: clock.now, memo: &memo),
                  let trip = readyTrip(of: train, on: line, stream.service, memo: &memo)
            else { return nil }
            departing = firstDeparture(of: train, on: trip, calling: line.stops)
        } else {
            return nil
        }
        guard let departing else { return nil }
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

    func reserving(_ candidate: Train) -> Reserving {
        guard isTrafficControlEnabled else { return .granted(candidate) }
        let envelope = routeEnvelope(of: candidate)
        if let holder = holder(of: envelope.resources, except: candidate.id) { return .held(by: holder, needs: envelope.resources) }
        var train = candidate
        train.reservation = envelope.moves ? envelope.resources.sorted() : []
        return .granted(train)
    }

    /// The lowest numbered train other than `id` that holds any of
    /// `resources` (see ``held(_:)``), or track that fouls any of them
    /// (Stage F2b, see ``RailwayNetwork/fouls(_:_:)``), or `nil`.
    func holder(of resources: Set<TrackResource>, except id: TrainID) -> TrainID? {
        trains.first { $0.id != id && $0.position != nil && network.fouls(held($0), resources) }?.id
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
