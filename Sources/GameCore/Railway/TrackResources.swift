// Track resources (Phase 4.5 Stage S1). Before trains can share track, the
// track must be something they can occupy: every node and every span of an
// edge is a resource (Stage S3A). What each train occupies, which trains
// occupy the same resource, how the network divides into sections between
// its branch points, and how many separate tracks join two stations are all
// derived from the network and the trains on every query, like routes, and
// never stored. Nothing here moves
// a train or changes a rule: it is the ground the route reservation and
// movement authority of Phase 4.6 will stand on.

/// A piece of track a train can occupy: a node of the railway graph, or a
/// span of an edge (see ``TrackNodeID`` and ``TrackSpan``).
///
/// An edge is a connection with a length; the resources along it are its
/// spans, so a long edge is many resources and a train holds only the part
/// it is on (Stage S3A, ARCHITECTURE decision 29). A node shared by two lines
/// is a level crossing, so trains crossing it either way share it, while
/// edges that only cross in plan share nothing.
public enum TrackResource: Hashable, Comparable, Sendable {
    case node(TrackNodeID)
    case span(TrackSpan)

    /// Nodes before spans; each kind in its own order (see ``TrackNodeID``
    /// and ``TrackSpan``).
    public static func < (lhs: TrackResource, rhs: TrackResource) -> Bool {
        switch (lhs, rhs) {
        case (.node(let a), .node(let b)):
            a < b
        case (.node, .span):
            true
        case (.span, .node):
            false
        case (.span(let a), .span(let b)):
            a < b
        }
    }

    /// One word for a node and for a span alike (see
    /// ``TrackSpan/hash(into:)``): sets of track are built at every step
    /// of traffic control. Equal resources still hash equally.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .node(.node(let number)): hasher.combine(number)
        case .span(let span): hasher.combine(span.hashWord)
        }
    }
}

extension TrackResource: Codable {
    private enum CodingKeys: String, CodingKey {
        case tile, node, link, edge, start, end
    }

    /// Decodes a resource a train reserves (Phase 4.6 Stage T), in exactly
    /// one of two forms: a node `{"node": n}` or a span of an edge
    /// `{"edge": n, "start", "end"}` (`0 <= start < end`). Numbers start at
    /// 1. Rejects no tag or more than one, and any shape a resource cannot
    /// have, rather than repairing it; whether the resource exists in a
    /// world is checked by the ``GameWorld`` decoder.
    ///
    /// A grid tile (`"tile"`) or link (`"link"`), which only a save made by
    /// hand could hold, is refused with that reason: the grid went in Stage
    /// F3c (ARCHITECTURE decision 51).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tags = [CodingKeys.tile, .node, .link, .edge].filter(container.contains)
        func corrupt(_ description: String) -> DecodingError {
            DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: description))
        }
        guard tags.count == 1 else { throw corrupt("A track resource is exactly one of a node or an edge's span.") }
        switch tags[0] {
        case .tile, .link:
            throw corrupt("Track on the grid (\"\(tags[0].stringValue)\") is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold it.")
        case .node:
            let number = try container.decode(Int.self, forKey: .node)
            guard number >= 1 else { throw corrupt("Track node numbers start at 1.") }
            self = .node(.node(number))
        default:
            let number = try container.decode(Int.self, forKey: .edge)
            let start = try container.decode(Int64.self, forKey: .start)
            let end = try container.decode(Int64.self, forKey: .end)
            guard number >= 1, start >= 0, start < end else { throw corrupt("A span lies along an edge numbered from 1, from 0 or more to further on.") }
            self = .span(TrackSpan(edge: .edge(number), start: start, end: end))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .node(.node(let number)):
            try container.encode(number, forKey: .node)
        case .span(let span):
            switch span.edge {
            case .edge(let number):
                try container.encode(number, forKey: .edge)
                try container.encode(span.start, forKey: .start)
                try container.encode(span.end, forKey: .end)
            }
        }
    }
}

/// A stretch of an edge's chainage, from `start` to `end` (measured from the
/// edge's `from` node): the unit of track a train occupies along an edge
/// and, from Stage T, reserves (Stage S3A).
///
/// An edge's spans cover it end to end without overlapping (see
/// ``GameWorld/trackSpans(of:)``). They are worked out from the edge's
/// integer length, never from its drawn shape, so occupancy and reservation
/// never depend on how the track is sampled or rendered.
public struct TrackSpan: Hashable, Comparable, Sendable {
    public let edge: TrackEdgeID
    public let start: Int64
    public let end: Int64

    public init(edge: TrackEdgeID, start: Int64, end: Int64) {
        self.edge = edge
        self.start = start
        self.end = end
    }

    /// How long the span is.
    public var length: Int64 {
        end - start
    }

    /// By edge, then along it.
    public static func < (lhs: TrackSpan, rhs: TrackSpan) -> Bool {
        (lhs.edge, lhs.start, lhs.end) < (rhs.edge, rhs.start, rhs.end)
    }

    /// Its edge and ends mixed into one word, hashed once rather than
    /// field by field: hashing was much of the time traffic control spent
    /// on sets of track. Equal spans still hash equally.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashWord)
    }

    /// See ``hash(into:)``.
    /// 64 bits on every platform (`Int` is 32 on wasm32).
    var hashWord: UInt64 {
        switch edge {
        case .edge(let number):
            (UInt64(truncatingIfNeeded: number) &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(bitPattern: start) &* 0xC2B2_AE3D_27D4_EB4F)
                ^ UInt64(bitPattern: end)
        }
    }
}

/// A resource that two trains or more occupy at once.
public struct TrackConflict: Hashable, Sendable {
    public let resource: TrackResource
    /// The trains occupying it, in ascending ID order.
    public let trains: [TrainID]

    public init(resource: TrackResource, trains: [TrainID]) {
        self.resource = resource
        self.trains = trains
    }
}

/// A run of the track network between branch points (Stage F3c; the
/// Railway reference's track groups): a chain of edges whose inner nodes are
/// plain, where exactly two edges end and they join, so trains run straight
/// through. (It replaced the grid's `TrackSection`.)
public struct NetworkSection: Hashable, Sendable {
    /// The edges along the section in order, each the way the section runs.
    public let traversals: [TrackTraversal]
    /// The nodes along the section in order: where each traversal starts,
    /// then where the last one ends, except on a loop. Each end is a branch
    /// point (a node where one edge ends, or more than two, or two that do
    /// not join) and may end several sections; a section from a branch
    /// point back to itself has it at both ends.
    public let nodes: [TrackNodeID]
    /// Whether the section closes on itself without a branch point: a ring
    /// of plain nodes.
    public let isLoop: Bool

    public init(traversals: [TrackTraversal], nodes: [TrackNodeID], isLoop: Bool) {
        self.traversals = traversals
        self.nodes = nodes
        self.isLoop = isLoop
    }
}

extension GameWorld {
    // MARK: - Occupancy

    /// The track train `id` occupies, in resource order (Stage S3): every
    /// node the train's centre line reaches or passes, from head to tail
    /// (Stage S2), and every span with part of the train strictly inside it
    /// (see ``networkResources(of:)``). Empty for an unplaced train or an
    /// unknown ID.
    public func occupiedResources(of id: TrainID) -> [TrackResource] {
        guard let train = train(id: id) else { return [] }
        return occupied(train)
    }

    /// The track `train` occupies (see ``occupiedResources(of:)``). Takes
    /// the train by value, so traffic control can ask about a train as a
    /// command would leave it.
    func occupied(_ train: Train) -> [TrackResource] {
        guard train.position != nil else { return [] }
        return Array(Set(networkResources(of: train))).sorted()
    }

    /// Every resource two trains or more occupy, in resource order, each
    /// with its trains in ID order. Empty when no two trains share track.
    ///
    /// Scans every train once; no occupancy index is kept.
    public func occupancyConflicts() -> [TrackConflict] {
        var occupants: [TrackResource: [TrainID]] = [:]
        for train in trains {
            for resource in occupiedResources(of: train.id) {
                occupants[resource, default: []].append(train.id)
            }
        }
        return occupants
            .filter { $0.value.count > 1 }
            .map { TrackConflict(resource: $0.key, trains: $0.value.sorted()) }
            .sorted { $0.resource < $1.resource }
    }

    // MARK: - Sections

    /// Whether trains run straight through `node`: exactly two edges end
    /// there, and they join.
    private func isPlain(_ node: TrackNode) -> Bool {
        node.ends.count == 2 && node.ends[0].exits.contains(node.ends[1].edge)
    }

    /// Every section of the track network (see ``NetworkSection``), each
    /// once: sections from a branch point first, each from the end whose
    /// node, then edge, has the lowest number, in that order; then rings of
    /// plain nodes, each from the `from` node of its lowest numbered edge,
    /// along that edge, in the order of those edges. A node no edge ends at
    /// is in no section.
    ///
    /// Every edge of the network belongs to exactly one section. The
    /// Railway reference groups the plain nodes between branch points the
    /// same way (`topology.js`, `trackGroups`); here the chain also lists
    /// its edges and the branch points at its ends. Pure, but walks the
    /// whole network: O(edges log edges).
    public func networkSections() -> [NetworkSection] {
        var sections: [NetworkSection] = []
        var covered: Set<TrackEdgeID> = []
        // Along `first` from `start`, through plain nodes, until a branch
        // point or, round a ring, `start` again.
        func walk(from start: TrackNode, along first: TrackTraversal) {
            var traversals = [first]
            var nodes = [start.id]
            while let edge = network.edge(traversals[traversals.count - 1].edge),
                  let here = network.node(edge.end(of: traversals[traversals.count - 1].direction)) {
                let isEnd = here.id == start.id || !isPlain(here)
                if !isEnd || !isPlain(start) { nodes.append(here.id) }
                guard !isEnd,
                      let next = here.ends.first(where: { $0.edge != edge.id }),
                      let step = network.edge(next.edge)?.traversal(leaving: here.id) else { break }
                traversals.append(step)
            }
            covered.formUnion(traversals.map(\.edge))
            sections.append(NetworkSection(traversals: traversals, nodes: nodes, isLoop: isPlain(start)))
        }
        for node in network.nodes where !isPlain(node) {
            for end in node.ends where !covered.contains(end.edge) {
                guard let first = network.edge(end.edge)?.traversal(leaving: node.id) else { continue }
                walk(from: node, along: first)
            }
        }
        // Rings of plain nodes, which no branch point starts.
        for edge in network.edges where !covered.contains(edge.id) {
            guard let start = network.node(edge.from) else { continue }
            walk(from: start, along: TrackTraversal(edge: edge.id, direction: .forward))
        }
        return sections
    }

    // MARK: - Parallel tracks

    /// How many separate tracks join stations `a` and `b`: the most paths
    /// from a platform of `a` to a platform of `b` that share no track. 0
    /// when the stations are not joined by track or one does not exist; 1
    /// is single track; 2 or more is double track or wider. Turning rules
    /// and trains are not considered: this counts the track laid, as a map
    /// shows it.
    ///
    /// Paths share no stretch of track (Stage F3c): an edge, cut where a
    /// platform of `a` or `b` lies on it. A path passes from one edge to
    /// another only where they join at a node, may turn back along the way,
    /// and starts and ends at a platform, either way along its edge. (Until
    /// Stage F3c the grid's paths, which shared no link, were counted too.)
    ///
    /// Pure. Explores the track reachable from `a`'s platforms once per path
    /// found: O(edges, platforms and the joins between edges) each.
    public func parallelTracks(between a: StationID, and b: StationID) -> Int {
        networkParallelTracks(between: a, and: b)
    }

    /// The track network's separate tracks (see
    /// ``parallelTracks(between:and:)``): a maximum flow by breadth-first
    /// augmenting paths. Each stretch of track (an edge, cut at the
    /// platforms of `a` and `b` on it) is two vertices joined by an arc of
    /// capacity 1, entered by one and left by the other, so one path at
    /// most uses it; the stretches either side of a platform of `a` are
    /// where paths start, those either side of a platform of `b` where they
    /// end, and a stretch at a node leads to every stretch at that node
    /// whose edge joins its edge.
    private func networkParallelTracks(between a: StationID, and b: StationID) -> Int {
        guard a != b else { return 0 }
        let platforms = network.platforms.filter { $0.station == a || $0.station == b }
        guard platforms.contains(where: { $0.station == a }), platforms.contains(where: { $0.station == b }) else { return 0 }
        var graph = UnitFlow()
        // The stretches of each edge in order along it, from its `from` node:
        // one more than the platforms of `a` and `b` on it.
        var first: [TrackEdgeID: Int] = [:]
        var stretches = 0
        for edge in network.edges {
            let cuts = platforms.filter { $0.edge == edge.id }
            first[edge.id] = stretches
            for (index, platform) in cuts.enumerated() {
                for stretch in [stretches + index, stretches + index + 1] {
                    if platform.station == a {
                        graph.add(from: UnitFlow.source, to: UnitFlow.entry(stretch), capacity: UnitFlow.unlimited)
                    } else {
                        graph.add(from: UnitFlow.exit(stretch), to: UnitFlow.sink, capacity: UnitFlow.unlimited)
                    }
                }
            }
            stretches += cuts.count + 1
        }
        for stretch in 0..<stretches {
            graph.add(from: UnitFlow.entry(stretch), to: UnitFlow.exit(stretch), capacity: 1)
        }
        // The stretch of `edge` that reaches `node`.
        func stretch(of edge: TrackEdgeID, at node: TrackNodeID) -> Int? {
            guard let start = first[edge], let track = network.edge(edge) else { return nil }
            return track.from == node ? start : start + platforms.count { $0.edge == edge }
        }
        for node in network.nodes {
            for end in node.ends {
                guard let from = stretch(of: end.edge, at: node.id) else { continue }
                for exit in end.exits {
                    guard let to = stretch(of: exit, at: node.id) else { continue }
                    graph.add(from: UnitFlow.exit(from), to: UnitFlow.entry(to), capacity: UnitFlow.unlimited)
                }
            }
        }
        return graph.maximumFlow()
    }

    /// The separate tracks between each pair of consecutive stops of line
    /// `id` (see ``parallelTracks(between:and:)``): element `i` is from stop
    /// `i` to stop `i + 1`. `nil` if the line does not exist.
    public func lineTrackCounts(_ id: LineID) -> [Int]? {
        guard let line = line(id: id) else { return nil }
        return zip(line.stops, line.stops.dropFirst()).map { parallelTracks(between: $0, and: $1) }
    }
}

/// The flow network of the track network's parallel tracks: vertices by
/// number (the source, the sink, and each stretch of track's entry and
/// exit), and arcs with the room left on them, each stored beside its
/// reverse.
private struct UnitFlow {
    static let source = 0
    static let sink = 1
    /// More room than any flow here can use: every path passes a stretch.
    static let unlimited = Int.max / 2

    static func entry(_ stretch: Int) -> Int {
        2 + 2 * stretch
    }

    static func exit(_ stretch: Int) -> Int {
        3 + 2 * stretch
    }

    /// Arc `i` runs to `targets[i]` with `room[i]` left; arc `i ^ 1` is
    /// its reverse.
    private var targets: [Int] = []
    private var room: [Int] = []
    /// The arcs leaving each vertex.
    private var arcs: [[Int]] = [[], []]

    mutating func add(from: Int, to: Int, capacity: Int) {
        while arcs.count <= max(from, to) { arcs.append([]) }
        arcs[from].append(targets.count)
        targets.append(to)
        room.append(capacity)
        arcs[to].append(targets.count)
        targets.append(from)
        room.append(0)
    }

    /// The most flow from the source to the sink, found one unit at a time
    /// along the shortest path with room left.
    mutating func maximumFlow() -> Int {
        var flow = 0
        while true {
            var arrivedBy = [Int?](repeating: nil, count: arcs.count)
            var seen = [Bool](repeating: false, count: arcs.count)
            seen[Self.source] = true
            var queue = [Self.source]
            var index = 0
            while index < queue.count, !seen[Self.sink] {
                let here = queue[index]
                index += 1
                for arc in arcs[here] where room[arc] > 0 && !seen[targets[arc]] {
                    seen[targets[arc]] = true
                    arrivedBy[targets[arc]] = arc
                    queue.append(targets[arc])
                }
            }
            guard seen[Self.sink] else { return flow }
            var vertex = Self.sink
            while let arc = arrivedBy[vertex] {
                room[arc] -= 1
                room[arc ^ 1] += 1
                vertex = targets[arc ^ 1]
            }
            flow += 1
        }
    }
}
