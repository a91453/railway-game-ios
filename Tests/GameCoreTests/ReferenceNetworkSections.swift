import GameCore

/// The track network's sections and parallel tracks (Stage F3c) written a
/// second time for ``ReferenceWorld``, from the documented rules rather than
/// from GameCore, and differently where it can be:
///
/// - which edges join at a node is worked out from the edges' ways on every
///   query, as everywhere in the reference;
/// - sections come from a union-find of the edges that meet at a plain
///   node (as the Railway reference's `trackGroups` floods its plain nodes),
///   then each is laid out from its first end and the list sorted;
/// - parallel tracks come from depth-first augmenting paths, over stretches
///   named by their edge and place along it, with the flow on every pair of
///   vertices kept in a dictionary (GameCore searches breadth first over
///   numbered vertices).
extension ReferenceWorld {
    /// The edges with an end at `node`, by number.
    private func edges(endingAt node: Int) -> [Int] {
        networkEdges.keys.sorted().filter { networkEdges[$0]!.from == node || networkEdges[$0]!.to == node }
    }

    /// Whether edges `a` and `b` join at `node`: both end there, leaving it
    /// opposite ways to within 1 in 16.
    private func join(_ a: Int, _ b: Int, at node: Int) -> Bool {
        guard a != b, let u = way(of: a, at: node), let v = way(of: b, at: node) else { return false }
        let dot = u.dx * v.dx + u.dy * v.dy
        let cross = u.dx * v.dy - u.dy * v.dx
        return dot < 0 && 16 * abs(cross) <= -dot
    }

    /// Exactly two edges end at `node`, and they join.
    private func isPlainNode(_ node: Int) -> Bool {
        let ending = edges(endingAt: node)
        return ending.count == 2 && join(ending[0], ending[1], at: node)
    }

    func networkSections() -> [NetworkSection] {
        let numbers = networkEdges.keys.sorted()
        var parent = Dictionary(uniqueKeysWithValues: numbers.map { ($0, $0) })
        func root(_ number: Int) -> Int {
            var number = number
            while parent[number]! != number { number = parent[number]! }
            return number
        }
        for node in networkNodes.keys where isPlainNode(node) {
            let pair = edges(endingAt: node)
            parent[root(pair[0])] = root(pair[1])
        }
        var groups: [Int: [Int]] = [:]
        for number in numbers { groups[root(number), default: []].append(number) }

        var chains: [(node: Int, edge: Int, section: NetworkSection)] = []
        var rings: [(edge: Int, section: NetworkSection)] = []
        for members in groups.values {
            // A chain starts at its end with the lowest node, then edge.
            let ends = members.flatMap { number in
                [networkEdges[number]!.from, networkEdges[number]!.to].filter { !isPlainNode($0) }.map { (node: $0, edge: number) }
            }
            if let start = ends.min(by: { ($0.node, $0.edge) < ($1.node, $1.edge) }) {
                chains.append((start.node, start.edge, layOut(from: start.node, along: start.edge)))
            } else {
                let lowest = members.min()!
                rings.append((lowest, layOut(from: networkEdges[lowest]!.from, along: lowest)))
            }
        }
        chains.sort { ($0.node, $0.edge) < ($1.node, $1.edge) }
        rings.sort { $0.edge < $1.edge }
        return chains.map(\.section) + rings.map(\.section)
    }

    /// The section from `start` along edge `first`, on through plain nodes.
    private func layOut(from start: Int, along first: Int) -> NetworkSection {
        var traversals: [TrackTraversal] = []
        var nodes: [TrackNodeID] = [.node(start)]
        var here = start
        var number = first
        while true {
            let edge = networkEdges[number]!
            let forward = edge.from == here
            traversals.append(TrackTraversal(edge: .edge(number), direction: forward ? .forward : .backward))
            here = forward ? edge.to : edge.from
            if here == start, isPlainNode(start) { break }
            nodes.append(.node(here))
            if here == start || !isPlainNode(here) { break }
            number = edges(endingAt: here).first { $0 != number }!
        }
        return NetworkSection(traversals: traversals, nodes: nodes, isLoop: isPlainNode(start))
    }

    /// A stretch of track for parallel tracks: piece `index` of edge `edge`,
    /// counting from its `from` node, between the platforms of the two
    /// stations on it.
    private struct Stretch: Hashable {
        var edge: Int
        var index: Int
    }

    private enum Vertex: Hashable {
        case source
        case sink
        case into(Stretch)
        case out(Stretch)
    }

    private struct Pair: Hashable {
        var from: Vertex
        var to: Vertex
    }

    func networkParallelTracks(between a: StationID, and b: StationID) -> Int {
        guard a != b,
              let first = stations.first(where: { $0.id == a.rawValue }), !first.trackPlatforms.isEmpty,
              let second = stations.first(where: { $0.id == b.rawValue }), !second.trackPlatforms.isEmpty
        else { return 0 }
        let cuts = first.trackPlatforms + second.trackPlatforms
        func cutsOn(_ number: Int) -> [TrackPlatform] {
            cuts.filter { $0.edge == .edge(number) }.sorted { $0.start < $1.start }
        }
        // Capacities: 1 through a stretch, unlimited elsewhere.
        let unlimited = 1 << 40
        var capacity: [Pair: Int] = [:]
        var neighbours: [Vertex: Set<Vertex>] = [:]
        func arc(_ from: Vertex, _ to: Vertex, _ room: Int) {
            capacity[Pair(from: from, to: to)] = room
            neighbours[from, default: []].insert(to)
            neighbours[to, default: []].insert(from)
        }
        for number in networkEdges.keys {
            let onEdge = cutsOn(number)
            for index in 0...onEdge.count {
                arc(.into(Stretch(edge: number, index: index)), .out(Stretch(edge: number, index: index)), 1)
            }
            for (index, platform) in onEdge.enumerated() {
                for side in [Stretch(edge: number, index: index), Stretch(edge: number, index: index + 1)] {
                    if platform.station == a {
                        arc(.source, .into(side), unlimited)
                    } else {
                        arc(.out(side), .sink, unlimited)
                    }
                }
            }
        }
        // The stretch of edge `number` at its end `node`.
        func stretch(_ number: Int, at node: Int) -> Stretch {
            Stretch(edge: number, index: networkEdges[number]!.from == node ? 0 : cutsOn(number).count)
        }
        for node in networkNodes.keys {
            let ending = edges(endingAt: node)
            for u in ending {
                for v in ending where join(u, v, at: node) {
                    arc(.out(stretch(u, at: node)), .into(stretch(v, at: node)), unlimited)
                }
            }
        }
        var flow: [Pair: Int] = [:]
        func room(_ from: Vertex, _ to: Vertex) -> Int {
            capacity[Pair(from: from, to: to), default: 0] - flow[Pair(from: from, to: to), default: 0]
        }
        func augment(_ here: Vertex, _ visited: inout Set<Vertex>) -> Bool {
            if here == .sink { return true }
            for next in neighbours[here, default: []] where !visited.contains(next) && room(here, next) > 0 {
                visited.insert(next)
                if augment(next, &visited) {
                    flow[Pair(from: here, to: next), default: 0] += 1
                    flow[Pair(from: next, to: here), default: 0] -= 1
                    return true
                }
            }
            return false
        }
        var count = 0
        while true {
            var visited: Set<Vertex> = [.source]
            guard augment(.source, &visited) else { return count }
            count += 1
        }
    }
}
