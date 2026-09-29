// Track resources (Phase 4.5 Stage S1). Before trains can share track, the
// track must be something they can occupy: every track tile (node) and
// every link between two joined tiles is a resource. What each train
// occupies, which trains occupy the same resource, how the network divides
// into sections between its branch points, and how many separate tracks
// join two stations are all derived from the map and the trains on every
// query, like connectivity and routes, and never stored. Nothing here moves
// a train or changes a rule: it is the ground the route reservation and
// movement authority of Phase 4.6 will stand on.

/// A piece of track a train can occupy.
public enum TrackResource: Hashable, Comparable, Sendable {
    /// A track tile. A crossing is one tile, so trains crossing it either
    /// way share it.
    case node(GridPosition)
    /// The link between two joined track tiles, the one further north (or,
    /// in the same row, further west) first.
    case link(GridPosition, GridPosition)

    /// The link between `a` and `b`, in either order.
    public static func link(between a: GridPosition, and b: GridPosition) -> TrackResource {
        precedes(a, b) ? .link(a, b) : .link(b, a)
    }

    /// Row-major order: north before south, then west before east.
    static func precedes(_ a: GridPosition, _ b: GridPosition) -> Bool {
        (a.y, a.x) < (b.y, b.x)
    }

    /// Nodes before links; nodes in row-major order; links by their first
    /// tile, then their second.
    public static func < (lhs: TrackResource, rhs: TrackResource) -> Bool {
        switch (lhs, rhs) {
        case (.node(let a), .node(let b)):
            precedes(a, b)
        case (.node, .link):
            true
        case (.link, .node):
            false
        case (.link(let a, let b), .link(let c, let d)):
            a == c ? precedes(b, d) : precedes(a, c)
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

    /// The track train `id` occupies: the tile it stands on, or the link it
    /// is on. Empty for an unplaced train or an unknown ID. Trains have no
    /// length yet (Stage S2), so a train occupies exactly one resource.
    public func occupiedResources(of id: TrainID) -> [TrackResource] {
        switch train(id: id)?.position {
        case nil:
            return []
        case .atNode(let tile, _)?:
            return [.node(tile)]
        case .onLink(let from, let to, _)?:
            return [.link(between: from, and: to)]
        }
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
            var queue = sources.sorted { TrackResource.precedes($0, $1) }
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
