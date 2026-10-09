// The railway network (Phase 4.5 Stage S3, ARCHITECTURE decision 29): the
// one record of all railway track in a world (S3A): numbered nodes at world
// coordinates and numbered edges between them (S3B). Until Stage F3c it also
// held the grid's track pieces, anchored to tiles; they went with the grid
// (decision 51).
//
// The railway is only here; the world itself is only its bounds
// (WorldBounds, Stage F3d). Nodes are points in the world; edges run between
// two of them along a TrackCurve, any length and any heading. Only a shared
// node joins two edges: edges that cross in plan without one never meet.
// Which edges a train may pass between at a node is derived once, when an
// edge is built or a save is loaded, from the way each edge leaves the node:
// two edge ends that leave in opposite directions (to within 1 in 16) join.
// That one rule gives plain track, turnouts (one end joining two or more),
// diamond crossings (two pairs that do not join each other) and slips. Routes,
// movement and occupancy read only the result, never the geometry.
//
// Stage S4 (ARCHITECTURE decision 30) gives nodes heights and edges a
// vertical profile and a structure. Joining is unchanged: it reads the way
// ends leave a node in plan. Where two edges meet in plan away from a node
// they share, their heights must differ by the clearance (see
// TrackClearance), so trains that share no node or edge never meet.

/// A node of the track network: a point where edges end and meet.
public struct TrackNode: Hashable, Sendable {
    public let id: TrackNodeID
    public let position: WorldCoordinate
    /// The edges that end here, in ascending order, each with the edges a
    /// train arriving along it may leave by. Derived from the edges, never
    /// saved.
    public internal(set) var ends: [TrackNodeEnd]

    init(id: TrackNodeID, position: WorldCoordinate, ends: [TrackNodeEnd] = []) {
        self.id = id
        self.position = position
        self.ends = ends
    }

    /// The end of `edge` at this node, if the edge ends here.
    public func end(of edge: TrackEdgeID) -> TrackNodeEnd? {
        ends.first { $0.edge == edge }
    }
}

/// An edge's end at a node, and where a train arriving along it may go on.
public struct TrackNodeEnd: Hashable, Sendable {
    public let edge: TrackEdgeID
    /// The way the edge leaves the node (its end tangent), not normalised.
    public let direction: PlanVector
    /// The edges a train arriving at the node along ``edge`` may leave by,
    /// in ascending order: those whose ends leave the node the opposite way
    /// to within 1 in 16. Never ``edge`` itself: a train does not turn
    /// straight back.
    public internal(set) var exits: [TrackEdgeID]
}

/// One edge to build with ``GameWorld/buildTrackEdges(_:)``: its end nodes,
/// its shape in plan and height, and what carries it.
public struct TrackEdgePlan: Hashable, Sendable {
    public let from: TrackNodeID
    public let to: TrackNodeID
    public let curve: TrackCurve
    public let profile: TrackProfile
    public let structure: TrackStructure

    public init(from: TrackNodeID, to: TrackNodeID, curve: TrackCurve = .straight, profile: TrackProfile = .uniform,
                structure: TrackStructure = .surface) {
        self.from = from
        self.to = to
        self.curve = curve
        self.profile = profile
        self.structure = structure
    }
}

/// An edge of the railway graph: a stretch of track between two nodes.
public struct TrackEdge: Hashable, Sendable {
    public let id: TrackEdgeID
    public let from: TrackNodeID
    public let to: TrackNodeID
    /// The shape in plan between the end nodes.
    public let curve: TrackCurve
    /// The distance a train travels along the edge, in world units (see
    /// ``TrackGeometry/length``): derived from the end nodes and the curve
    /// when the edge is built or loaded, never saved.
    public let length: Int64
    /// How the height changes between the end nodes (Stage S4).
    public let profile: TrackProfile
    /// What carries the track (Stage S4).
    public let structure: TrackStructure
    /// An automatic edge's sections (decision 124), from its `from` node,
    /// covering every pricing length once; empty for an explicit
    /// structure (see ``sectionSpans``).
    public let sections: [TrackSection]

    init(
        id: TrackEdgeID, from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, length: Int64,
        profile: TrackProfile = .uniform, structure: TrackStructure = .surface, sections: [TrackSection] = []
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.curve = curve
        self.length = length
        self.profile = profile
        self.structure = structure
        self.sections = sections
    }

    /// The node a traversal of this edge ends at.
    public func end(of direction: TrackEdgeDirection) -> TrackNodeID {
        direction == .forward ? to : from
    }

    /// The node a traversal of this edge starts from.
    public func start(of direction: TrackEdgeDirection) -> TrackNodeID {
        direction == .forward ? from : to
    }

    /// The traversal of this edge that leaves `node`, if the edge ends
    /// there.
    public func traversal(leaving node: TrackNodeID) -> TrackTraversal? {
        if node == from { return TrackTraversal(edge: id, direction: .forward) }
        if node == to { return TrackTraversal(edge: id, direction: .backward) }
        return nil
    }
}

/// The railway of a world (Stage S3A): the network's nodes and edges, each
/// in ascending ID order, and its platforms (Stage S4). Changed only by
/// ``GameWorld``'s commands.
public struct RailwayNetwork: Hashable, Sendable {
    /// The network's nodes and edges, in ascending ID order.
    public private(set) var nodes: [TrackNode]
    public private(set) var edges: [TrackEdge]
    /// The next node and edge number to hand out; every number in use is
    /// below it, and numbers are never reused.
    private(set) var nextNodeNumber: Int
    private(set) var nextEdgeNumber: Int
    /// The stations' platforms on the continuous network (Stage S4), in
    /// order along the track (see ``TrackPlatform``). None overlap.
    public private(set) var platforms: [TrackPlatform]
    /// The pairs of edges too close (closer than ``trackSpacing`` at points
    /// farther apart than ``partingReach`` along the track) that were built
    /// before Stage F2 made that a rule (ARCHITECTURE decision 52), in
    /// order: exactly the pairs too close, and only in a world first loaded
    /// from a save made before it. They stay as they were built; removing
    /// either edge removes the pair, a new edge that joins them within the
    /// reach removes it too, and no new edge may come too close to either.
    public private(set) var spacingExemptions: [TrackEdgePair]
    /// For every span that fouls spans of other edges, those spans (Stage
    /// F2b, ARCHITECTURE decision 53): spans of two edges at one level less
    /// than ``trackSpacing`` apart in plan at points more than
    /// ``foulingLength`` apart along the track, where trains on both would
    /// touch. Worked out again whenever an edge or a platform changes, never
    /// saved.
    private(set) var foulingSpans: [TrackSpan: Set<TrackSpan>]
    /// The spans of every edge (see ``spans(of:length:)``), worked out
    /// again whenever an edge or a platform changes, never saved.
    private var edgeSpans: [TrackEdgeID: [TrackSpan]]

    /// An empty network, handing out numbers from 1.
    public init() {
        nodes = []
        edges = []
        nextNodeNumber = 1
        nextEdgeNumber = 1
        platforms = []
        spacingExemptions = []
        foulingSpans = [:]
        edgeSpans = [:]
    }

    /// The heights a node may stand at in a world (Stage S4): 4096 units
    /// (64 m) above or below the ground.
    public static let heightRange: ClosedRange<Int64> = -4_096...4_096

    /// How far from a node two edges that end there may meet in plan at
    /// any height (Stage S4): 1024 units, 16 m. Branches of a turnout
    /// leave a node side by side, so this stretch is the turnout and the
    /// space it needs, not a crossing (see ``TrackClearance``).
    public static let junctionZone: Int64 = 1_024

    /// The least distance in plan between the centre lines of two edges at
    /// one level (Stage F2, ARCHITECTURE decision 52): 256 units (4 m),
    /// the widest train of the references (3.38 m) with room to spare.
    /// Closer points must be within ``partingReach`` of each other along the
    /// track (see ``TrackSpacing``).
    public static let trackSpacing: Int64 = 256

    /// How far apart along the track two points closer than
    /// ``trackSpacing`` may be (Stage F2): 32768 units (512 m).
    /// Within it they are one junction's tracks parting, a turnout's
    /// branches or a ladder of turnouts, which leave each other gently; a
    /// branch 1 in 64 off the line is 4 m away after 256 m along each, 512 m
    /// apart along the track. Points farther apart along the track, or not
    /// joined by track at all, belong to tracks laid too close.
    public static let partingReach: Int64 = 32_768

    /// Whether the network has no nodes and has never handed out a number,
    /// so a world saves it by leaving it out. (A platform needs an edge.)
    var isPristine: Bool {
        nodes.isEmpty && edges.isEmpty && nextNodeNumber == 1 && nextEdgeNumber == 1
    }

    // MARK: - Spans (Stage S3A)

    /// The longest a span of an edge is: 1024 units, 16 m, the length a
    /// train holds track in (Stage S3A; it was a tile's width then, and is
    /// the railway's own measure since Stage F3d).
    public static let spanLength: Int64 = 1_024

    /// The spans of edge `edge`, `length` long, from its `from` node: the
    /// fewest equal parts no longer than ``spanLength``. With
    /// `n = ⌈length ÷ 1024⌉` parts, the `k`-th boundary is at
    /// `⌊k × length ÷ n⌋`. An edge of 2 km is 125.
    /// Worked out from the integer length alone, never from the samples.
    ///
    /// - Precondition: `length > 0`.
    public static func spans(of edge: TrackEdgeID, length: Int64) -> [TrackSpan] {
        precondition(length > 0, "spans(of:length:) needs a length")
        let count = (length + spanLength - 1) / spanLength
        return (0..<count).map { k in
            TrackSpan(edge: edge, start: k * length / count, end: (k + 1) * length / count)
        }
    }

    /// The spans of edge `id`, `length` long (Stage S4): its equal parts
    /// (see ``spans(of:length:)``), cut again at the ends of every platform
    /// on it, so a platform is a whole number of spans.
    func spans(of id: TrackEdgeID, length: Int64) -> [TrackSpan] {
        if let spans = edgeSpans[id], spans.last?.end == length { return spans }
        return cutSpans(of: id, length: length)
    }

    /// Works out ``spans(of:length:)`` from the edge's length and platforms.
    private func cutSpans(of id: TrackEdgeID, length: Int64) -> [TrackSpan] {
        let equal = Self.spans(of: id, length: length)
        let cuts = platforms(on: id).flatMap { [$0.start, $0.end] }
        guard !cuts.isEmpty else { return equal }
        // Both lists of boundaries are in order (platforms are kept in order
        // along the edge and never overlap), so they are merged as they are.
        var boundaries: [Int64] = []
        boundaries.reserveCapacity(equal.count + cuts.count + 1)
        var next = cuts.startIndex
        for boundary in equal.map(\.start) + [length] {
            while next < cuts.endIndex, cuts[next] <= boundary {
                if boundaries.last != cuts[next] { boundaries.append(cuts[next]) }
                next += 1
            }
            if boundaries.last != boundary { boundaries.append(boundary) }
        }
        return zip(boundaries, boundaries.dropFirst()).map { TrackSpan(edge: id, start: $0, end: $1) }
    }

    // MARK: - Platforms (Stage S4)

    /// The platforms on edge `id`, in order along it.
    public func platforms(on id: TrackEdgeID) -> [TrackPlatform] {
        platforms.filter { $0.edge == id }
    }

    /// The platforms of station `id`, in order along the track.
    public func platforms(of id: StationID) -> [TrackPlatform] {
        platforms.filter { $0.station == id }
    }

    /// Adds `platform`, which the caller has checked fits its edge and
    /// overlaps no other.
    mutating func addPlatform(_ platform: TrackPlatform) {
        platforms.insert(platform, at: platforms.firstIndex { platform < $0 } ?? platforms.count)
        recutSpans(of: platform.edge)
        foulingSpans = foulingAfterChange(to: [platform.edge])
    }

    /// Removes the platform at `index` of ``platforms``.
    mutating func removePlatform(at index: Int) {
        let platform = platforms.remove(at: index)
        recutSpans(of: platform.edge)
        foulingSpans = foulingAfterChange(to: [platform.edge])
    }

    /// Works out the spans of edge `id` again, or forgets them once it is
    /// gone.
    private mutating func recutSpans(of id: TrackEdgeID) {
        edgeSpans[id] = edge(id).map { cutSpans(of: id, length: $0.length) }
    }

    // MARK: - The continuous network

    /// The node with `id`, or `nil`. Binary search: O(log n).
    public func node(_ id: TrackNodeID) -> TrackNode? {
        nodeIndex(id).map { nodes[$0] }
    }

    /// The edge with `id`, or `nil`. Binary search: O(log n).
    public func edge(_ id: TrackEdgeID) -> TrackEdge? {
        edgeIndex(id).map { edges[$0] }
    }

    /// The index of node `id`, or `nil`.
    func nodeIndex(_ id: TrackNodeID) -> Int? {
        id.networkNumber.flatMap { number in Self.index(of: number, count: nodes.count) { nodes[$0].id.networkNumber ?? 0 } }
    }

    /// The index of edge `id`, or `nil`.
    func edgeIndex(_ id: TrackEdgeID) -> Int? {
        id.networkNumber.flatMap { number in Self.index(of: number, count: edges.count) { edges[$0].id.networkNumber ?? 0 } }
    }

    /// Binary search for `number` among `count` elements whose numbers,
    /// read by `numberAt`, ascend.
    private static func index(of number: Int, count: Int, numberAt: (Int) -> Int) -> Int? {
        var low = 0
        var high = count - 1
        while low <= high {
            let middle = low + (high - low) / 2
            let candidate = numberAt(middle)
            if candidate == number { return middle }
            if candidate < number {
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return nil
    }

    /// Whether a node stands at exactly `position`.
    func hasNode(at position: WorldCoordinate) -> Bool {
        nodes.contains { $0.position == position }
    }

    /// Whether node `id` is a tunnel portal (Stage S4): a tunnel edge and
    /// an edge that is not a tunnel both end there, so trains pass between
    /// underground and the open there. Derived from the edges, never saved.
    /// Since decision 124 it reads what carries each edge at the node: an
    /// automatic edge's first or last section. A portal inside an automatic
    /// edge is where its sections change (``TrackEdge/sectionSpans``).
    public func isTunnelPortal(_ id: TrackNodeID) -> Bool {
        guard let node = node(id) else { return false }
        let kinds = node.ends.compactMap { edge($0.edge)?.kind(at: id) }
        return kinds.contains(.tunnel) && kinds.contains { $0 != .tunnel }
    }

    /// The centre line of edge `id` (see ``TrackGeometry``), or `nil` if
    /// there is no such edge.
    func geometry(of id: TrackEdgeID) -> TrackGeometry? {
        guard let edge = edge(id), let from = node(edge.from), let to = node(edge.to) else { return nil }
        return TrackGeometry(from: from.position, to: to.position, curve: edge.curve, profile: edge.profile)
    }

    // MARK: - Changes

    /// Adds a node at `position` with the next number, which the caller
    /// has checked can be handed out (see `GameWorld.allocateID(from:)`).
    mutating func addNode(at position: WorldCoordinate, next: Int) -> TrackNodeID {
        let id = TrackNodeID.node(nextNodeNumber)
        nodes.append(TrackNode(id: id, position: position))
        nextNodeNumber = next
        return id
    }

    /// Adds an edge with the next number between two existing nodes, with
    /// `geometry` already worked out from them, `curve` and `profile`; the
    /// caller has checked the number can be handed out. Updates the ends of
    /// both nodes.
    mutating func addEdge(
        from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, profile: TrackProfile, structure: TrackStructure, sections: [TrackSection] = [],
        geometry: TrackGeometry, next: Int
    ) -> TrackEdgeID {
        let id = TrackEdgeID.edge(nextEdgeNumber)
        edges.append(TrackEdge(
            id: id, from: from, to: to, curve: curve, length: geometry.length, profile: profile, structure: structure, sections: sections
        ))
        nextEdgeNumber = next
        attach(id, direction: geometry.startDirection, at: from)
        attach(id, direction: geometry.endDirection, at: to)
        recutSpans(of: id)
        // Ways along the track through the new edge are shorter now.
        foulingSpans = foulingAfterChange(to: edgesNear(from, to).union([id]))
        return id
    }

    /// Removes the edge `id`, which exists, its ends at its nodes, and the
    /// spacing exemptions it is in.
    mutating func removeEdge(_ id: TrackEdgeID, updatingFouling: Bool = true) {
        guard let index = edgeIndex(id) else { preconditionFailure("removeEdge(_:) needs an edge of the network") }
        // Ways along the track through it get longer.
        let changed = updatingFouling ? edgesNear(edges[index].from, edges[index].to) : []
        let edge = edges.remove(at: index)
        recutSpans(of: id)
        spacingExemptions.removeAll { $0.contains(id) }
        for node in [edge.from, edge.to] {
            guard let nodeIndex = nodeIndex(node) else { continue }
            nodes[nodeIndex].ends.removeAll { $0.edge == id }
            Self.join(&nodes[nodeIndex].ends)
        }
        if updatingFouling {
            foulingSpans = foulingAfterChange(to: changed)
        }
    }

    /// Sets the spacing exemptions to `pairs`: the pairs of edges too close
    /// in a world loaded from a save made before Stage F2.
    mutating func exemptFromSpacing(_ pairs: [TrackEdgePair]) {
        spacingExemptions = pairs
    }

    /// Removes the node `id`, which exists and has no edges.
    mutating func removeNode(_ id: TrackNodeID) {
        guard let index = nodeIndex(id) else { preconditionFailure("removeNode(_:) needs a node of the network") }
        nodes.remove(at: index)
    }

    private mutating func attach(_ edge: TrackEdgeID, direction: PlanVector, at node: TrackNodeID) {
        guard let index = nodeIndex(node) else { preconditionFailure("an edge ends at nodes of the network") }
        var ends = nodes[index].ends
        let end = TrackNodeEnd(edge: edge, direction: direction, exits: [])
        ends.insert(end, at: ends.firstIndex { $0.edge > edge } ?? ends.count)
        Self.join(&ends)
        nodes[index].ends = ends
    }

    /// Works out which ends at one node join: every pair whose directions
    /// are opposite to within 1 in 16 (see
    /// ``PlanVector/isOpposite(to:)``). `ends` are in ascending edge order,
    /// so each list of exits is too.
    private static func join(_ ends: inout [TrackNodeEnd]) {
        for index in ends.indices {
            ends[index].exits = ends.indices.compactMap { other in
                other != index && ends[index].direction.isOpposite(to: ends[other].direction) ? ends[other].edge : nil
            }
        }
    }
}

// MARK: - Codable

extension RailwayNetwork: Codable {
    private enum CodingKeys: String, CodingKey {
        case nodes, edges, nextNodeID, nextEdgeID, platforms, spacingExemptions
    }

    private enum NodeKeys: String, CodingKey {
        case id, x, y, z
    }

    private enum EdgeKeys: String, CodingKey {
        case id, from, to, curve, profile, structure, sections
    }

    /// Decodes `{"nodes", "edges", "nextNodeID", "nextEdgeID"}`: nodes as
    /// `{"id", "x", "y", "z"}` and edges as `{"id", "from", "to", "curve"}`
    /// with, since Stage S4, `"profile"` when it has transitions and
    /// `"structure"` when it is not surface track (a Stage S3 edge has
    /// neither and reads as uniform surface track). Both lists are in
    /// ascending ID order, IDs from 1 and below the next ID. Every derived
    /// value (each edge's length, each node's ends) is worked out again, not
    /// read. Rejects, rather than repairing: an ID out of order, repeated or
    /// not below the next one; a coordinate beyond
    /// ``WorldCoordinate/limit``; two nodes at one point; an edge whose end
    /// nodes do not exist or are the same node; a curve or profile that does
    /// not make an edge between its nodes (see
    /// ``TrackGeometry/init(from:to:curve:profile:)``); an unknown
    /// structure; and an explicit `null`. Since Stage S4 also `"platforms"`,
    /// when there are any: `{"station", "edge", "start", "end"}` in order
    /// along the track, on edges of the network. Since Stage F2 also
    /// `"spacingExemptions"`, when there are any: pairs of edge numbers
    /// `[a, b]` with `a < b`, in order, on edges of the network. The world's
    /// rules (the map, heights, grades, structures, clearance, spacing, and
    /// platforms that fit their edges and stations that exist) are checked by
    /// the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func corrupt(_ description: String) -> DecodingError {
            DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: description))
        }
        self.init()
        nextNodeNumber = try container.decode(Int.self, forKey: .nextNodeID)
        nextEdgeNumber = try container.decode(Int.self, forKey: .nextEdgeID)
        var positions: Set<WorldCoordinate> = []
        var list = try container.nestedUnkeyedContainer(forKey: .nodes)
        while !list.isAtEnd {
            let node = try list.nestedContainer(keyedBy: NodeKeys.self)
            let number = try node.decode(Int.self, forKey: .id)
            let position = WorldCoordinate(
                x: try node.decode(Int64.self, forKey: .x), y: try node.decode(Int64.self, forKey: .y), z: try node.decode(Int64.self, forKey: .z)
            )
            guard number >= 1, number < nextNodeNumber, number > nodes.last?.id.networkNumber ?? 0 else {
                throw corrupt("Track node IDs must be ascending, from 1 and below nextNodeID.")
            }
            guard position.isWithinLimits else { throw corrupt("Track node \(number) lies beyond \(WorldCoordinate.limit).") }
            guard positions.insert(position).inserted else { throw corrupt("Two track nodes stand at one point.") }
            nodes.append(TrackNode(id: .node(number), position: position))
        }
        list = try container.nestedUnkeyedContainer(forKey: .edges)
        var lastEdge = 0
        while !list.isAtEnd {
            let edge = try list.nestedContainer(keyedBy: EdgeKeys.self)
            let number = try edge.decode(Int.self, forKey: .id)
            let from = TrackNodeID.node(try edge.decode(Int.self, forKey: .from))
            let to = TrackNodeID.node(try edge.decode(Int.self, forKey: .to))
            let curve = try edge.decode(TrackCurve.self, forKey: .curve)
            let profile = edge.contains(.profile) ? try edge.decode(TrackProfile.self, forKey: .profile) : .uniform
            let structure = edge.contains(.structure) ? try edge.decode(TrackStructure.self, forKey: .structure) : .surface
            // Decision 124: an automatic edge's sections, and only its.
            let sections = edge.contains(.sections) ? try edge.decode([TrackSection].self, forKey: .sections) : []
            guard number >= 1, number < nextEdgeNumber, number > lastEdge else {
                throw corrupt("Track edge IDs must be ascending, from 1 and below nextEdgeID.")
            }
            lastEdge = number
            guard let start = node(from), let end = node(to), from != to else {
                throw corrupt("Track edge \(number) does not join two different nodes of the network.")
            }
            guard let geometry = TrackGeometry(from: start.position, to: end.position, curve: curve, profile: profile) else {
                throw corrupt("Track edge \(number)'s curve or profile does not make an edge between its nodes.")
            }
            let priced = ConstructionCosts.trackPricingLength
            guard (structure == .automatic) == !sections.isEmpty, sections.allSatisfy({ $0.lengths > 0 }),
                  zip(sections, sections.dropFirst()).allSatisfy({ $0.kind != $1.kind }),
                  sections.isEmpty || sections.reduce(0, { $0 + Int64($1.lengths) }) == max(1, (geometry.length + priced - 1) / priced)
            else {
                throw corrupt("Track edge \(number)'s sections must cover an automatic edge's every length once, runs apart, and only an automatic edge has them.")
            }
            let id = TrackEdgeID.edge(number)
            edges.append(TrackEdge(
                id: id, from: from, to: to, curve: curve, length: geometry.length, profile: profile, structure: structure, sections: sections
            ))
            attach(id, direction: geometry.startDirection, at: from)
            attach(id, direction: geometry.endDirection, at: to)
        }
        platforms = container.contains(.platforms) ? try container.decode([TrackPlatform].self, forKey: .platforms) : []
        guard zip(platforms, platforms.dropFirst()).allSatisfy({ $0 < $1 && !$0.overlaps($1) }) else {
            throw corrupt("Platforms must be in order along the track and must not overlap.")
        }
        guard platforms.allSatisfy({ edge($0.edge) != nil }) else { throw corrupt("A platform lies on an edge that does not exist.") }
        for edge in edges {
            recutSpans(of: edge.id)
        }
        let exempted = container.contains(.spacingExemptions) ? try container.decode([[Int]].self, forKey: .spacingExemptions) : []
        for pair in exempted {
            guard pair.count == 2, pair[0] < pair[1], edge(.edge(pair[0])) != nil, edge(.edge(pair[1])) != nil else {
                throw corrupt("A spacing exemption must be two edges of the network, the lower numbered first.")
            }
            let next = TrackEdgePair(.edge(pair[0]), .edge(pair[1]))
            guard spacingExemptions.last.map({ $0 < next }) ?? true else {
                throw corrupt("Spacing exemptions must be in order, each once.")
            }
            spacingExemptions.append(next)
        }
        foulingSpans = workOutFouling()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var list = container.nestedUnkeyedContainer(forKey: .nodes)
        for node in nodes {
            var entry = list.nestedContainer(keyedBy: NodeKeys.self)
            try entry.encode(node.id.networkNumber, forKey: .id)
            try entry.encode(node.position.x, forKey: .x)
            try entry.encode(node.position.y, forKey: .y)
            try entry.encode(node.position.z, forKey: .z)
        }
        list = container.nestedUnkeyedContainer(forKey: .edges)
        for edge in edges {
            var entry = list.nestedContainer(keyedBy: EdgeKeys.self)
            try entry.encode(edge.id.networkNumber, forKey: .id)
            try entry.encode(edge.from.networkNumber, forKey: .from)
            try entry.encode(edge.to.networkNumber, forKey: .to)
            try entry.encode(edge.curve, forKey: .curve)
            if edge.profile != .uniform {
                try entry.encode(edge.profile, forKey: .profile)
            }
            if edge.structure != .surface {
                try entry.encode(edge.structure, forKey: .structure)
            }
            if !edge.sections.isEmpty {
                try entry.encode(edge.sections, forKey: .sections)
            }
        }
        try container.encode(nextNodeNumber, forKey: .nextNodeID)
        try container.encode(nextEdgeNumber, forKey: .nextEdgeID)
        if !platforms.isEmpty {
            try container.encode(platforms, forKey: .platforms)
        }
        if !spacingExemptions.isEmpty {
            try container.encode(spacingExemptions.map { [$0.first.networkNumber, $0.second.networkNumber] }, forKey: .spacingExemptions)
        }
    }
}
