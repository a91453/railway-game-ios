import GameCore

// Support for the track network tests (Stage S3, ARCHITECTURE decision 29):
// reading IDs, the network's invariants from the public state, and
// generated networks built through the public commands.

extension TrackNodeID {
    /// The number of a network node. Only for network nodes.
    var number: Int {
        guard case .node(let number) = self else { preconditionFailure("\(self) is not a node of the track network") }
        return number
    }
}

extension TrackEdgeID {
    /// The number of a network edge. Only for network edges.
    var number: Int {
        guard case .edge(let number) = self else { preconditionFailure("\(self) is not an edge of the track network") }
        return number
    }

    /// The number written in fixtures: a network edge's number.
    var networkNumberForFixture: Int {
        number
    }
}

extension TrackResource {
    /// The one span of grid link `link`, the whole of it.
    static func wholeLink(_ link: TrackEdgeID) -> TrackResource {
        .span(TrackSpan(edge: link, start: 0, end: TrainPosition.linkLength))
    }
}

enum NetworkInvariants {
    /// Every documented invariant of the network a world reachable through
    /// commands keeps (decision 29), from its public state only.
    static func violations(in world: GameWorld) -> [String] {
        var problems: [String] = []
        let network = world.network
        let nodeNumbers = network.nodes.map(\.id.number)
        if nodeNumbers != nodeNumbers.sorted() || Set(nodeNumbers).count != nodeNumbers.count || nodeNumbers.contains(where: { $0 < 1 }) {
            problems.append("track node IDs not unique, positive and ascending: \(nodeNumbers)")
        }
        let edgeNumbers = network.edges.map(\.id.number)
        if edgeNumbers != edgeNumbers.sorted() || Set(edgeNumbers).count != edgeNumbers.count || edgeNumbers.contains(where: { $0 < 1 }) {
            problems.append("track edge IDs not unique, positive and ascending: \(edgeNumbers)")
        }
        let limitX = Int64(world.map.width) * 1024
        let limitY = Int64(world.map.height) * 1024
        func overMap(_ x: Int64, _ y: Int64) -> Bool { x >= 0 && y >= 0 && x < limitX && y < limitY }
        if Set(network.nodes.map(\.position)).count != network.nodes.count { problems.append("two track nodes at one point") }
        for node in network.nodes {
            if node.position.z != 0 || !overMap(node.position.x, node.position.y) {
                problems.append("track node \(node.id.number) at \(node.position) is off the map or the ground")
            }
        }
        for edge in network.edges {
            // Stage S3A: the spans cover the edge end to end, none longer
            // than a tile, as few as that allows.
            let spans = world.trackSpans(of: edge.id)
            if spans.first?.start != 0 || spans.last?.end != edge.length || zip(spans, spans.dropFirst()).contains(where: { $0.end != $1.start })
                || spans.contains(where: { $0.edge != edge.id || $0.length <= 0 || $0.length > 1_024 }) || Int64(spans.count) != (edge.length + 1_023) / 1_024 {
                problems.append("track edge \(edge.id.number)'s spans do not cover it: \(spans.map { ($0.start, $0.end) })")
            }
            guard let from = network.node(edge.from), let to = network.node(edge.to), edge.from != edge.to else {
                problems.append("track edge \(edge.id.number) does not join two nodes")
                continue
            }
            if case .cubic(let c1, let c2) = edge.curve, !overMap(c1.x, c1.y) || !overMap(c2.x, c2.y) {
                problems.append("track edge \(edge.id.number)'s curve leaves the map")
            }
            if TrackGeometry(from: from.position, to: to.position, curve: edge.curve)?.length != edge.length {
                problems.append("track edge \(edge.id.number)'s length is not its centre line's")
            }
        }
        // Each node's ends are the edges ending there, in ascending order,
        // and an end joins exactly the ends leaving the opposite way.
        for node in network.nodes {
            let ending = network.edges.filter { $0.from == node.id || $0.to == node.id }.map(\.id)
            if node.ends.map(\.edge) != ending { problems.append("track node \(node.id.number) ends \(node.ends.map(\.edge)), edges \(ending)") }
            for end in node.ends {
                let joined = node.ends.filter { other in
                    guard other.edge != end.edge else { return false }
                    let dot = end.direction.dx * other.direction.dx + end.direction.dy * other.direction.dy
                    let cross = end.direction.dx * other.direction.dy - end.direction.dy * other.direction.dx
                    return dot < 0 && 16 * abs(cross) <= -dot
                }.map(\.edge)
                if end.exits != joined { problems.append("track node \(node.id.number) end \(end.edge) exits \(end.exits), expected \(joined)") }
            }
        }
        return problems
    }

    /// Decision 29 for a train on the network: on an edge, within it; a
    /// body at offset 0 only for a train of one car; no grid trail, grid
    /// continuation or service; the body edges joined as a train could
    /// have come, just reaching the tail; its continuation's edges built
    /// once (below the next number, even if removed since).
    static func trainViolations(of train: Train, in world: GameWorld) -> [String] {
        guard case .onEdge(let traversal, let offset)? = train.position else { return [] }
        let id = train.id.rawValue
        var problems: [String] = []
        guard let edge = world.trackEdge(traversal.edge), case .edge = traversal.edge else { return ["train \(id) is on an edge that does not exist"] }
        if offset < 0 || offset > edge.length { problems.append("train \(id) offset \(offset) on an edge \(edge.length) long") }
        let length = Int64(train.cars - 1) * 1024
        if length > 0, offset == 0 { problems.append("train \(id) with a body stands at offset 0") }
        if !train.trail.isEmpty { problems.append("train \(id) on the network has a grid trail") }
        if !train.movement.continuation.isEmpty { problems.append("train \(id) on the network has a grid continuation") }
        if train.execution != nil { problems.append("train \(id) on the network runs a service") }
        if train.movement.rate < 0 { problems.append("train \(id) negative rate") }
        let count = train.movement.edges.count
        if !(count == 0 && train.movement.cursor == 0) && !(0..<count).contains(train.movement.cursor) {
            problems.append("train \(id) cursor \(train.movement.cursor) of \(count) edges")
        } else if train.movement.cursor >= 1, train.movement.edges[train.movement.cursor - 1] != traversal.edge {
            problems.append("train \(id)'s last entered edge is not the one it is on")
        }
        // The body: each edge ends where the one before it starts and joins
        // it; every edge but the last is short of the tail, the last reaches
        // it.
        var ahead = traversal
        var covered = offset
        for behind in train.trailEdges {
            guard let behindEdge = world.trackEdge(behind), let aheadEdge = world.trackEdge(ahead.edge) else {
                problems.append("train \(id)'s body lies on an edge that does not exist")
                return problems
            }
            let node = ahead.direction == .forward ? aheadEdge.from : aheadEdge.to
            guard behindEdge.from == node || behindEdge.to == node else {
                problems.append("train \(id)'s body is not joined at \(node)")
                return problems
            }
            let run = TrackTraversal(edge: behind, direction: behindEdge.to == node ? .forward : .backward)
            if !world.transitions(after: run).contains(ahead) { problems.append("train \(id)'s body turns where no train may") }
            if covered >= length { problems.append("train \(id)'s body has an edge beyond its tail") }
            covered += behindEdge.length
            ahead = run
        }
        if covered < length { problems.append("train \(id)'s body does not reach its tail") }
        return problems
    }
}
