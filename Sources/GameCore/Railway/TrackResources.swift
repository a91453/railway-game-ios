// Track resources (Phase 4.5 Stage S1). Before trains can share track, the
// track must be something they can occupy: every track tile (node) and
// every link between two joined tiles is a resource. What each train
// occupies, which trains occupy the same resource, how the network divides
// into sections between its branch points, and how many separate tracks
// join two stations are all derived from the map and the trains on every
// query, like connectivity and routes, and never stored. Nothing here moves
// a train or changes a rule: it is the ground the route reservation and
// movement authority of Phase 4.6 will stand on.

/// A piece of track a train can occupy: a node of the railway graph, or a
/// span of an edge (see ``TrackNodeID`` and ``TrackSpan``).
///
/// An edge is a connection with a length; the resources along it are its
/// spans, so a long edge is many resources and a train holds only the part
/// it is on (Stage S3A, ARCHITECTURE decision 29). On the grid, a track tile
/// is a node and the link between two joined tiles is one span; a level
/// crossing is one tile, so trains crossing it either way share it. On the
/// track network a node shared by two lines is a level crossing in the same
/// way, while edges that only cross in plan share nothing.
public enum TrackResource: Hashable, Comparable, Sendable {
    case node(TrackNodeID)
    case span(TrackSpan)

    /// The track tile at `position`.
    public static func tile(_ position: GridPosition) -> TrackResource {
        .node(.tile(position))
    }

    /// The grid link between `a` and `b`, in either order: its one span.
    public static func link(between a: GridPosition, and b: GridPosition) -> TrackResource {
        .span(TrackSpan(edge: .link(between: a, and: b), start: 0, end: TrainPosition.linkLength))
    }

    /// Nodes before spans; each kind in its own order (see ``TrackNodeID``
    /// and ``TrackSpan``): on the grid, tiles in row-major order and links
    /// by their first tile, then their second.
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
}

extension TrackResource: Codable {
    private enum CodingKeys: String, CodingKey {
        case tile, node, link, edge, start, end
    }

    /// Decodes a resource a train reserves (Phase 4.6 Stage T), in exactly
    /// one of four forms: a grid tile `{"tile": {"x", "y"}}`, a node of the
    /// track network `{"node": n}`, a grid link `{"link": [a, b]}` (its one
    /// span, the whole link; `a` before `b` in row-major order, the two
    /// tiles orthogonal neighbours) or a span of a network edge
    /// `{"edge": n, "start", "end"}` (`0 <= start < end`). Numbers start at
    /// 1. Rejects no tag or more than one, and any shape a resource cannot
    /// have, rather than repairing it; whether the resource exists in a
    /// world is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tags = [CodingKeys.tile, .node, .link, .edge].filter(container.contains)
        func corrupt(_ description: String) -> DecodingError {
            DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: description))
        }
        guard tags.count == 1 else { throw corrupt("A track resource is exactly one of a tile, a node, a link or an edge's span.") }
        switch tags[0] {
        case .tile:
            self = .tile(try container.decode(GridPosition.self, forKey: .tile))
        case .node:
            let number = try container.decode(Int.self, forKey: .node)
            guard number >= 1 else { throw corrupt("Track node numbers start at 1.") }
            self = .node(.node(number))
        case .link:
            let tiles = try container.decode([GridPosition].self, forKey: .link)
            guard tiles.count == 2, TrackEdgeID.precedes(tiles[0], tiles[1]), TrackDirection(from: tiles[0], to: tiles[1]) != nil else {
                throw corrupt("A link is two neighbouring tiles, the one further north or west first.")
            }
            self = .span(TrackSpan(edge: .link(tiles[0], tiles[1]), start: 0, end: TrainPosition.linkLength))
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
        case .node(.tile(let position)):
            try container.encode(position, forKey: .tile)
        case .node(.node(let number)):
            try container.encode(number, forKey: .node)
        case .span(let span):
            switch span.edge {
            case .link(let a, let b):
                try container.encode([a, b], forKey: .link)
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

/// A run of track between branch points: a chain of links whose inner
/// tiles are plain pieces joined to exactly two others.
public struct TrackSection: Hashable, Sendable {
    /// The tiles along the section in order, from one end to the other.
    /// Each end is a branch point (a tile joined to other than two tiles,
    /// or a turnout or crossing) and may belong to several sections; a
    /// lone tile joined to nothing is a section of one tile. For a loop,
    /// the first tile is not repeated at the end.
    public let nodes: [GridPosition]
    /// Whether the section closes on itself without a branch point: a ring
    /// of plain pieces.
    public let isLoop: Bool

    public init(nodes: [GridPosition], isLoop: Bool) {
        self.nodes = nodes
        self.isLoop = isLoop
    }

    /// The links of the section, in order along it.
    public var links: [TrackResource] {
        var links = zip(nodes, nodes.dropFirst()).map { TrackResource.link(between: $0, and: $1) }
        if isLoop, let first = nodes.first, let last = nodes.last, nodes.count > 2 {
            links.append(.link(between: last, and: first))
        }
        return links
    }
}

extension GameWorld {
    // MARK: - Occupancy

    /// The track train `id` occupies, in resource order: the tile its head
    /// stands on, or the link it is on, and for a train of several cars (Stage S2)
    /// every link its body lies over and every node it reaches or passes.
    /// Empty for an unplaced train or an unknown ID.
    ///
    /// On the track network (Stage S3) the same rule holds for any shape and
    /// length: every node the train's centre line reaches or passes, and
    /// every edge with part of the train strictly inside it (see
    /// ``networkResources(of:)``).
    public func occupiedResources(of id: TrainID) -> [TrackResource] {
        guard let train = train(id: id) else { return [] }
        return occupied(train)
    }

    /// The track `train` occupies (see ``occupiedResources(of:)``). Takes
    /// the train by value, so traffic control can ask about a train as a
    /// command would leave it.
    func occupied(_ train: Train) -> [TrackResource] {
        let head: [TrackResource]
        switch train.position {
        case nil:
            return []
        case .atNode(let tile, _)?:
            head = [.tile(tile)]
        case .onLink(let from, let to, _)?:
            head = [.link(between: from, and: to)]
        case .onEdge?:
            return Array(Set(networkResources(of: train))).sorted()
        }
        return Array(Set(head + bodyResources(of: train))).sorted()
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

    /// Whether the track at `position` ends sections: a turnout or crossing,
    /// or a plain piece joined to other than exactly two tiles.
    private func isBranchPoint(_ position: GridPosition) -> Bool {
        guard let track = track(at: position) else { return false }
        return track.layout != .open || connectedNeighbors(of: position).count != 2
    }

    /// Every section of the network (see ``TrackSection``), each once:
    /// sections from a branch point are listed from the end that comes
    /// first in row-major order (and of a section from a branch point back
    /// to itself, the way whose first step comes first north, east, south,
    /// west), in the order of those ends and their first steps; rings
    /// without a branch point follow, each from its first tile in row-major
    /// order, going the first way north, east, south, west.
    ///
    /// Every link of the network belongs to exactly one section. Pure, but
    /// scans the whole map: O(track tiles).
    public func trackSections() -> [TrackSection] {
        var sections: [TrackSection] = []
        var covered: Set<TrackResource> = []
        for track in tracks where isBranchPoint(track.position) {
            let start = track.position
            let neighbors = connectedNeighbors(of: start)
            if neighbors.isEmpty {
                sections.append(TrackSection(nodes: [start], isLoop: false))
                continue
            }
            for first in neighbors where !covered.contains(.link(between: start, and: first)) {
                var nodes = [start, first]
                while !isBranchPoint(nodes[nodes.count - 1]) {
                    let here = nodes[nodes.count - 1]
                    let back = nodes[nodes.count - 2]
                    nodes.append(connectedNeighbors(of: here).first { $0 != back }!)
                }
                let section = TrackSection(nodes: nodes, isLoop: false)
                covered.formUnion(section.links)
                sections.append(section)
            }
        }
        // Rings of plain pieces, which no branch point starts.
        for track in tracks {
            let start = track.position
            let neighbors = connectedNeighbors(of: start)
            guard !isBranchPoint(start), let first = neighbors.first, !covered.contains(.link(between: start, and: first)) else { continue }
            var nodes = [start, first]
            while nodes[nodes.count - 1] != start {
                let here = nodes[nodes.count - 1]
                let back = nodes[nodes.count - 2]
                nodes.append(connectedNeighbors(of: here).first { $0 != back }!)
            }
            nodes.removeLast()
            let section = TrackSection(nodes: nodes, isLoop: true)
            covered.formUnion(section.links)
            sections.append(section)
        }
        return sections
    }

    // MARK: - Parallel tracks

    /// How many separate tracks join stations `a` and `b`: the most paths
    /// from a platform of `a` to a platform of `b` that share no link. 0
    /// when the stations are not joined by track or one does not exist; 1
    /// is single track; 2 or more is double track or wider. Turning rules
    /// and trains are not considered: this counts the track laid, as a map
    /// shows it. A platform the two stations share is counted only as a
    /// platform of `a`.
    ///
    /// Pure. Explores the track reachable from `a`'s platforms once per path
    /// found (at most sixteen): O(reachable track tiles) each.
    public func parallelTracks(between a: StationID, and b: StationID) -> Int {
        let sources = Set(platforms(of: a))
        let sinks = Set(platforms(of: b)).subtracting(sources)
        guard !sources.isEmpty, !sinks.isEmpty else { return 0 }
        // Unit capacity each way on every link; the flow on a link from p to
        // q is +1 in flow[p→q] and −1 in flow[q→p].
        var flow: [Arc: Int] = [:]
        var paths = 0
        while true {
            // Breadth-first search for a path with room left, from any source.
            var previous: [GridPosition: GridPosition] = [:]
            var queue = sources.sorted { TrackEdgeID.precedes($0, $1) }
            var seen = Set(queue)
            var index = 0
            var reached: GridPosition?
            while index < queue.count, reached == nil {
                let here = queue[index]
                index += 1
                for next in connectedNeighbors(of: here) where !seen.contains(next) && flow[Arc(from: here, to: next), default: 0] < 1 {
                    seen.insert(next)
                    previous[next] = here
                    if sinks.contains(next) {
                        reached = next
                        break
                    }
                    queue.append(next)
                }
            }
            guard var node = reached else { return paths }
            while let back = previous[node] {
                flow[Arc(from: back, to: node), default: 0] += 1
                flow[Arc(from: node, to: back), default: 0] -= 1
                node = back
            }
            paths += 1
        }
    }

    /// The separate tracks between each pair of consecutive stops of line
    /// `id` (see ``parallelTracks(between:and:)``): element `i` is from stop
    /// `i` to stop `i + 1`. `nil` if the line does not exist.
    public func lineTrackCounts(_ id: LineID) -> [Int]? {
        guard let line = line(id: id) else { return nil }
        return zip(line.stops, line.stops.dropFirst()).map { parallelTracks(between: $0, and: $1) }
    }
}

/// One direction of a link, for the flow in ``GameWorld/parallelTracks(between:and:)``.
private struct Arc: Hashable {
    let from: GridPosition
    let to: GridPosition
}
