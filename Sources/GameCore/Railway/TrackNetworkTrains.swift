// Trains and the railway graph (Phase 4.5 Stage S3, ARCHITECTURE decision
// 29): the grid seen as a graph (the legacy adapter), the rules a train on
// the track network follows (entering edges, its body, turning round, the
// track it occupies), and read-only queries in world coordinates for
// renderers. Nothing here reads geometry while a train moves: movement and
// routes use only edge lengths and the transitions worked out when each
// edge was built.

extension GameWorld {
    // MARK: - The graph, grid and network alike

    /// The node `id` of the railway graph, or `nil` if there is none: a
    /// node of the track network, or a track tile of the grid seen as a node
    /// (at its centre, with an end for each joined neighbour in north, east,
    /// south, west order, each with the tiles a train arriving along it may
    /// go on to; see ``exits(from:facing:)``).
    public func trackNode(_ id: TrackNodeID) -> TrackNode? {
        switch id {
        case .node:
            return network.node(id)
        case .tile(let tile):
            guard track(at: tile) != nil else { return nil }
            let centre = WorldCoordinate(centreOf: tile)
            let ends = connectedNeighbors(of: tile).map { neighbor in
                let arrival = TrackDirection(from: neighbor, to: tile)!
                return TrackNodeEnd(
                    edge: .link(between: tile, and: neighbor),
                    direction: WorldCoordinate(centreOf: neighbor).plan.vector(from: centre.plan),
                    exits: exits(from: tile, facing: arrival).map { .link(between: tile, and: $0) }
                )
            }
            return TrackNode(id: id, position: centre, ends: ends)
        }
    }

    /// The edge `id` of the railway graph, or `nil` if there is none: an
    /// edge of the track network, or the link between two joined track tiles
    /// of the grid seen as an edge (straight, ``TrainPosition/linkLength``
    /// long, from its first tile to its second). A link must be written in
    /// order (see ``TrackEdgeID/link(between:and:)``).
    public func trackEdge(_ id: TrackEdgeID) -> TrackEdge? {
        switch id {
        case .edge:
            return network.edge(id)
        case .link(let a, let b):
            guard TrackEdgeID.precedes(a, b), isConnected(a, to: b) else { return nil }
            return TrackEdge(id: id, from: .tile(a), to: .tile(b), curve: .straight, length: TrainPosition.linkLength)
        }
    }

    /// The centre line of edge `id` (see ``TrackGeometry``), or `nil` if
    /// there is no such edge. Worked out on each call from the edge's
    /// integers: an edge never changes and its ID is never reused, so a
    /// renderer can keep the result for as long as the edge exists.
    public func trackGeometry(of id: TrackEdgeID) -> TrackGeometry? {
        guard let edge = trackEdge(id), let from = trackNodePosition(edge.from), let to = trackNodePosition(edge.to) else { return nil }
        return TrackGeometry(from: from, to: to, curve: edge.curve)
    }

    /// Where node `id` stands, or `nil` if there is no such node.
    func trackNodePosition(_ id: TrackNodeID) -> WorldCoordinate? {
        switch id {
        case .node: network.node(id)?.position
        case .tile(let tile): track(at: tile) != nil ? WorldCoordinate(centreOf: tile) : nil
        }
    }

    /// The traversals a train may go on to after `traversal`, at the node
    /// it ends at, in that node's order: on the grid the tiles
    /// ``exits(from:facing:)`` gives, north, east, south, west; on the
    /// network the edges joining the end it arrives by, in ascending order.
    /// Never back along the same edge. Empty for an edge that does not
    /// exist. This is the transitions hook routes and traffic control use:
    /// it reads only topology.
    public func transitions(after traversal: TrackTraversal) -> [TrackTraversal] {
        switch traversal.edge {
        case .link(let a, let b):
            guard trackEdge(traversal.edge) != nil else { return [] }
            let (from, to) = traversal.direction == .forward ? (a, b) : (b, a)
            return exits(from: to, facing: TrackDirection(from: from, to: to)!).map { TrackTraversal.link(from: to, to: $0) }
        case .edge:
            guard let edge = network.edge(traversal.edge), let node = network.node(edge.end(of: traversal.direction)),
                  let end = node.end(of: edge.id)
            else { return [] }
            return end.exits.compactMap { network.edge($0)?.traversal(leaving: node.id) }
        }
    }

    // MARK: - Trains on the network

    /// The traversal of network edge `next` that a train arriving by
    /// `arrival` may enter at the node `arrival` ends at, and its length, or
    /// `nil` if `next` does not exist or does not join the edge the train
    /// arrives by there. The movement kernel's only view of the network.
    func networkEntry(after arrival: TrackTraversal, into next: TrackEdgeID) -> (traversal: TrackTraversal, length: Int64)? {
        guard let edge = network.edge(arrival.edge), let node = network.node(edge.end(of: arrival.direction)),
              node.end(of: arrival.edge)?.exits.contains(next) == true,
              let entered = network.edge(next), let traversal = entered.traversal(leaving: node.id)
        else { return nil }
        return (traversal, entered.length)
    }

    /// The traversals behind a train whose head travels `head`, for its
    /// trail edges `trail` in order: each ends at the node the one before it
    /// (or `head`) starts from. `nil` if an edge does not exist or does not
    /// end at that node.
    func trailTraversals(behind head: TrackTraversal, trail: [TrackEdgeID]) -> [TrackTraversal]? {
        guard let headEdge = network.edge(head.edge) else { return nil }
        var node = headEdge.start(of: head.direction)
        var traversals: [TrackTraversal] = []
        for id in trail {
            guard let edge = network.edge(id), let leaving = edge.traversal(leaving: node) else { return nil }
            let traversal = leaving.reversed
            traversals.append(traversal)
            node = edge.start(of: traversal.direction)
        }
        return traversals
    }

    /// Whether `traversal` at `offset` lies on the track network: the edge
    /// exists and `0 <= offset <=` its length.
    func isOnNetwork(_ traversal: TrackTraversal, offset: Int64) -> Bool {
        guard let edge = network.edge(traversal.edge) else { return false }
        return offset >= 0 && offset <= edge.length
    }

    /// The trail edges a train `length` long with its head on `traversal`
    /// at `offset` would have if placed there: walking back from the start
    /// of its edge the way a train could have come, taking the lowest
    /// numbered edge that joins where the track branches, until the body
    /// reaches its tail. `nil` when the track behind ends first.
    func networkTrailBehind(_ traversal: TrackTraversal, offset: Int64, length: Int64) -> [TrackEdgeID]? {
        var covered = offset
        var trail: [TrackEdgeID] = []
        var ahead = traversal
        while covered < length {
            guard let edge = network.edge(ahead.edge), let node = network.node(edge.start(of: ahead.direction)),
                  let back = node.ends.first(where: { $0.exits.contains(ahead.edge) }),
                  let behind = network.edge(back.edge), let leaving = behind.traversal(leaving: node.id)
            else { return nil }
            trail.append(behind.id)
            covered += behind.length
            ahead = leaving.reversed
        }
        return trail
    }

    /// Whether `trail` is the body of a train `length` long with its head on
    /// `traversal` at `offset`: just enough edges to reach its tail (every
    /// edge but the last short of it), each ending where the one before it
    /// starts and joining it there, as a train could have come.
    func isNetworkTrail(_ trail: [TrackEdgeID], behind traversal: TrackTraversal, offset: Int64, length: Int64) -> Bool {
        guard let traversals = trailTraversals(behind: traversal, trail: trail) else { return false }
        var covered = offset
        var ahead = traversal
        for behind in traversals {
            guard covered < length, transitions(after: behind).contains(ahead) else { return false }
            covered += network.edge(behind.edge)!.length
            ahead = behind
        }
        return covered >= length
    }

    /// The trail after the head moved from edge `old` (with trail `trail`)
    /// to `new` at `offset`, entering `entered` on the way: the edges it
    /// now has behind it, nearest first, cut to what its length needs.
    func networkTrail(after old: TrackEdgeID, trail: [TrackEdgeID], entered: ArraySlice<TrackEdgeID>, offset: Int64, length: Int64) -> [TrackEdgeID] {
        guard length > 0 else { return [] }
        // The edges from far behind to the head's edge.
        var history = Array(trail.reversed())
        history.append(old)
        history.append(contentsOf: entered)
        // The last one is the edge the head is on.
        history.removeLast()
        var covered = offset
        var result: [TrackEdgeID] = []
        for edge in history.reversed() where covered < length {
            result.append(edge)
            covered += network.edge(edge)!.length
        }
        return result
    }

    /// The position and trail of a train `length` long on the network at
    /// `traversal` and `offset`, with trail `trail`, after it turns round
    /// where it stands: its head goes to where its tail was, facing away
    /// from where its head was, and its body lies back over the same track
    /// toward where its head was. Reversing twice gives back the original.
    ///
    /// - Precondition: `trail` is the train's body (see
    ///   ``isNetworkTrail(_:behind:offset:length:)``) and, for a train with a
    ///   body, `offset > 0`.
    func reversedOnNetwork(_ traversal: TrackTraversal, offset: Int64, trail: [TrackEdgeID], length: Int64) -> (position: TrainPosition, trail: [TrackEdgeID]) {
        let edgeLength = network.edge(traversal.edge)!.length
        guard length > 0 else { return (.onEdge(traversal.reversed, offset: edgeLength - offset), []) }
        guard let tailEdge = trailTraversals(behind: traversal, trail: trail)?.last else {
            // The whole body is on the head's edge.
            return (.onEdge(traversal.reversed, offset: edgeLength - offset + length), [])
        }
        // The distance from the head back to where the tail's edge ends
        // (toward the head); the tail lies further back on that edge.
        let before = offset + trail.dropLast().reduce(0) { $0 + network.edge($1)!.length }
        return (.onEdge(tailEdge.reversed, offset: length - before), Array(trail.dropLast().reversed()) + [traversal.edge])
    }

    /// The track a train on the network occupies (see
    /// ``occupiedResources(of:)``): every node its centre line reaches or
    /// passes, from head to tail, and every edge with part of the train
    /// strictly inside it. A train of one car occupies the node it stands
    /// at, or the edge it stands on.
    func networkResources(of train: Train) -> [TrackResource] {
        guard case .onEdge(let traversal, let offset)? = train.position, let edge = network.edge(traversal.edge) else { return [] }
        let length = train.length
        var resources: [TrackResource] = []
        if offset == edge.length { resources.append(.node(edge.end(of: traversal.direction))) }
        if offset == 0 { resources.append(.node(edge.start(of: traversal.direction))) }
        if (offset > 0 && offset < edge.length) || (length > 0 && offset > 0) { resources.append(.edge(edge.id)) }
        guard length > 0 else { return resources }
        var covered = offset
        if covered <= length, offset > 0 { resources.append(.node(edge.start(of: traversal.direction))) }
        for behind in trailTraversals(behind: traversal, trail: train.trailEdges) ?? [] {
            let behindEdge = network.edge(behind.edge)!
            resources.append(.edge(behindEdge.id))
            covered += behindEdge.length
            if covered <= length { resources.append(.node(behindEdge.start(of: behind.direction))) }
        }
        return resources
    }

    // MARK: - World coordinates, for renderers

    /// Where a train at `position` is in the world and the way it faces:
    /// the centre of its tile facing its heading, a point on its link, or a
    /// point on its network edge (see ``TrackGeometry/location(at:going:)``).
    /// `nil` when the position is not on this world's track. Display data:
    /// renderers convert it and never write it back.
    public func location(of position: TrainPosition) -> TrackLocation? {
        guard isOnTrack(position) else { return nil }
        switch position {
        case .atNode(let tile, let heading):
            return TrackLocation(position: WorldCoordinate(centreOf: tile), direction: Self.vector(of: heading))
        case .onLink(let from, let to, let offset):
            let start = WorldCoordinate(centreOf: from)
            let end = WorldCoordinate(centreOf: to)
            let way = end.plan.vector(from: start.plan)
            let point = WorldCoordinate(
                x: start.x + way.dx * offset / TrainPosition.linkLength,
                y: start.y + way.dy * offset / TrainPosition.linkLength,
                z: start.z
            )
            return TrackLocation(position: point, direction: way)
        case .onEdge(let traversal, let offset):
            return trackGeometry(of: traversal.edge)?.location(at: offset, going: traversal.direction)
        }
    }

    /// The unit plan vector of a grid direction (y grows south).
    static func vector(of direction: TrackDirection) -> PlanVector {
        switch direction {
        case .north: PlanVector(dx: 0, dy: -1)
        case .east: PlanVector(dx: 1, dy: 0)
        case .south: PlanVector(dx: 0, dy: 1)
        case .west: PlanVector(dx: -1, dy: 0)
        }
    }

    /// The centre line train `id`'s cars stand along, in world coordinates,
    /// from its head to its tail (see ``Train/length``): the head's
    /// location, every sampled point of the track between, and the tail.
    /// Just the head for a train of one car; empty for an unplaced train or
    /// an unknown ID. Display data, like ``location(of:)``.
    public func bodyPath(of id: TrainID) -> [WorldCoordinate] {
        guard let train = train(id: id), let position = train.position, let head = location(of: position) else { return [] }
        var points = [head.position]
        var remaining = train.length
        func follow(_ traversal: TrackTraversal, from start: Int64) {
            guard remaining > 0, let geometry = trackGeometry(of: traversal.edge) else { return }
            let end = max(0, start - remaining)
            // Along the traversal from `start` back to `end`: every sample
            // strictly between, then the end point.
            let distances = geometry.distances
            let (from, to) = traversal.direction == .forward ? (start, end) : (geometry.length - start, geometry.length - end)
            let between = distances.indices.filter { index in
                from < to ? (distances[index] > from && distances[index] < to) : (distances[index] < from && distances[index] > to)
            }
            for index in (from < to ? between : between.reversed()) {
                points.append(geometry.points[index])
            }
            points.append(geometry.location(at: to).position)
            remaining -= start - end
        }
        switch position {
        case .atNode(let tile, _):
            var ahead = tile
            for node in train.trail where remaining > 0 {
                follow(TrackTraversal.link(from: node, to: ahead), from: TrainPosition.linkLength)
                ahead = node
            }
        case .onLink(let from, let to, let offset):
            follow(TrackTraversal.link(from: from, to: to), from: offset)
            var ahead = from
            for node in train.trail.dropFirst() where remaining > 0 {
                follow(TrackTraversal.link(from: node, to: ahead), from: TrainPosition.linkLength)
                ahead = node
            }
        case .onEdge(let traversal, let offset):
            follow(traversal, from: offset)
            for behind in trailTraversals(behind: traversal, trail: train.trailEdges) ?? [] where remaining > 0 {
                follow(behind, from: network.edge(behind.edge)!.length)
            }
        }
        return points
    }
}
