// Route reservation (Phase 4.6 Stage T, ARCHITECTURE decision 32): the resources of a stretch.
// Moved from RouteReservation.swift unchanged (decision 910); the overview
// of route reservation is at the top of that file.

extension GameWorld {
    // MARK: - The resources of a stretch

    /// The end nodes, length and resource spans of edge `id`, from its
    /// `from` node, or `nil` if it does not exist.
    func stretchFacts(of id: TrackEdgeID) -> (from: TrackNodeID, to: TrackNodeID, length: Int64, spans: [TrackSpan])? {
        guard let edge = network.ends(ofEdge: id) else { return nil }
        return (edge.from, edge.to, edge.length, network.spans(of: id, length: edge.length))
    }

    /// The track `stretches` cover (see ``resources(covering:)`` and
    /// ``foulingNodes(covering:)``), kept as the stretches are: by edge,
    /// the parts of its chainage they cover. Whether a resource is of it is
    /// asked of the stretches on its edge by the same rule, and never by
    /// listing the spans: a stretch of a long leg covers thousands.
    struct TrackCover {
        /// The nodes it covers: where stretches reach an end of their edge,
        /// and the junctions they foul.
        let nodes: Set<TrackResource>
        /// For each edge a stretch lies on: its length, its spans, and the
        /// stretches in its own chainage, from its `from` node.
        let parts: EdgeTable<(length: Int64, spans: [TrackSpan], windows: [(low: Int64, high: Int64)])>

        /// The edges it lies on, in order.
        var edges: [TrackEdgeID] {
            parts.edges
        }

        /// Whether it covers what `other` does, kept the same way.
        func matches(_ other: TrackCover) -> Bool {
            nodes == other.nodes && edges == other.edges && edges.allSatisfy { edge in
                let (a, b) = (parts[edge]!, other.parts[edge]!)
                return a.length == b.length && a.spans == b.spans && a.windows.count == b.windows.count
                    && zip(a.windows, b.windows).allSatisfy { $0.low == $1.low && $0.high == $1.high }
            }
        }

        /// Whether a span shares a point with a stretch from `low` to
        /// `high` lying strictly between the edge's ends (the rule of
        /// ``resources(covering:)``).
        static func covers(_ low: Int64, _ high: Int64, _ span: TrackSpan, length: Int64) -> Bool {
            let a = max(low, span.start)
            let b = min(high, span.end)
            return a < b || (a == b && a > 0 && a < length)
        }

        func contains(_ resource: TrackResource) -> Bool {
            switch resource {
            case .node:
                return nodes.contains(resource)
            case .span(let span):
                guard let part = parts[span.edge],
                      part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) })
                else { return false }
                // One of the edge's own spans, found by halving.
                var (low, high) = (0, part.spans.count)
                while low < high {
                    let middle = (low + high) / 2
                    if part.spans[middle] < span {
                        low = middle + 1
                    } else {
                        high = middle
                    }
                }
                return low < part.spans.count && part.spans[low] == span
            }
        }

        /// The least and most chainage of edge `edge` it covers, or `nil`.
        func bounds(on edge: TrackEdgeID) -> (low: Int64, high: Int64)? {
            guard let part = parts[edge] else { return nil }
            var (low, high) = (Int64.max, Int64.min)
            for window in part.windows {
                low = min(low, window.low)
                high = max(high, window.high)
            }
            return (low, high)
        }

        /// Calls `each` with every span of edge `edge` it covers, in order,
        /// that starts at `high` or before and ends at `low` or after, until
        /// it returns `true`; returns whether it did.
        func anySpan(of edge: TrackEdgeID, from low: Int64, to high: Int64, where each: (TrackSpan) -> Bool) -> Bool {
            guard let part = parts[edge] else { return false }
            // The edge's spans are in order and end in order.
            var (lower, upper) = (0, part.spans.count)
            while lower < upper {
                let middle = (lower + upper) / 2
                if part.spans[middle].end < low {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            for span in part.spans[lower...] {
                guard span.start <= high else { break }
                if part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) }), each(span) { return true }
            }
            return false
        }

        /// The resources of `reservation` it covers, in their order: a
        /// reservation in resource order (see ``ReservedTrack``) is walked
        /// beside each edge's spans rather than each span found by halving.
        func kept(of reservation: [TrackResource]) -> [TrackResource] {
            var kept: [TrackResource] = []
            kept.reserveCapacity(reservation.count)
            var edge: TrackEdgeID?
            var part: (length: Int64, spans: [TrackSpan], windows: [(low: Int64, high: Int64)])?
            var next = 0
            for index in reservation.indices {
                let resource = reservation[index]
                if index > 0, !(reservation[index - 1] < resource) { return reservation.filter(contains) }
                switch resource {
                case .node:
                    if nodes.contains(resource) { kept.append(resource) }
                case .span(let span):
                    if span.edge != edge {
                        edge = span.edge
                        part = parts[span.edge]
                        next = 0
                    }
                    guard let part, part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) }) else { continue }
                    // In order, where it would be among the edge's own
                    // spans only moves on.
                    while next < part.spans.count, part.spans[next] < span {
                        next += 1
                    }
                    if next < part.spans.count, part.spans[next] == span { kept.append(resource) }
                }
            }
            // All of it kept: the reservation itself, so that what is kept
            // of it for being the same (see ``reservedTrack(of:memo:)``) is
            // found the same at once.
            return kept.count == reservation.count ? reservation : kept
        }

        /// Everything it covers, listed (as ``resources(covering:)`` and
        /// ``foulingNodes(covering:)`` list it, some perhaps twice).
        var resources: [TrackResource] {
            var resources = Array(nodes)
            for part in parts.allValues {
                for span in part.spans where part.windows.contains(where: { Self.covers($0.low, $0.high, span, length: part.length) }) {
                    resources.append(.span(span))
                }
            }
            return resources
        }
    }

    /// `train`'s route envelope (see ``routeEnvelope(of:)``), asked a
    /// resource at a time.
    func envelopeCover(of train: Train) -> TrackCover {
        cover(of: bodyStretches(of: train) + routeStretches(of: train).stretches)
    }

    /// See ``TrackCover``.
    func cover(of stretches: [TrackStretch]) -> TrackCover {
        var nodes = Set(foulingNodes(covering: stretches))
        var parts: [TrackEdgeID: (length: Int64, spans: [TrackSpan], windows: [(low: Int64, high: Int64)])] = [:]
        for stretch in stretches {
            guard let edge = stretchFacts(of: stretch.traversal.edge) else { continue }
            let forward = stretch.traversal.direction == .forward
            if stretch.from == 0 { nodes.insert(.node(forward ? edge.from : edge.to)) }
            if stretch.to == edge.length { nodes.insert(.node(forward ? edge.to : edge.from)) }
            let window = forward ? (low: stretch.from, high: stretch.to) : (low: edge.length - stretch.to, high: edge.length - stretch.from)
            if parts[stretch.traversal.edge] == nil {
                parts[stretch.traversal.edge] = (edge.length, edge.spans, [window])
            } else {
                parts[stretch.traversal.edge]!.windows.append(window)
            }
        }
        return TrackCover(nodes: nodes, parts: EdgeTable(parts))
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
            let id = stretch.traversal.edge
            guard let edge = network.ends(ofEdge: id) else { continue }
            let (low, high) = stretch.traversal.direction == .forward
                ? (stretch.from, stretch.to)
                : (edge.length - stretch.to, edge.length - stretch.from)
            if low < RailwayNetwork.junctionZone, isFoulingEnd(of: id, at: edge.from) { nodes.append(.node(edge.from)) }
            if edge.length - high < RailwayNetwork.junctionZone, isFoulingEnd(of: id, at: edge.to) { nodes.append(.node(edge.to)) }
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
        // Read in place, as ``RailwayNetwork/length(ofEdge:)`` is.
        guard let index = network.nodeIndex(node) else { return false }
        let ends = network.nodes[index].ends
        guard let end = ends.firstIndex(where: { $0.edge == edge }) else { return false }
        let exits = ends[end].exits
        return ends.contains { $0.edge != edge && !exits.contains($0.edge) }
    }
}

/// A few values by edge, in edge order, found by halving: asked of every
/// resource of a route, where hashing the edge took much of the time.
struct EdgeTable<Value> {
    /// The edges, in order.
    private(set) var edges: [TrackEdgeID] = []
    var values: [Value] = []

    init() {}

    init(_ dictionary: [TrackEdgeID: Value]) {
        edges = dictionary.keys.sorted()
        values = edges.map { dictionary[$0]! }
    }

    /// Adds `value` for `edge`, which comes after every edge it has.
    mutating func append(_ edge: TrackEdgeID, _ value: Value) {
        precondition(edges.last.map { $0 < edge } ?? true, "edges are added in order")
        edges.append(edge)
        values.append(value)
    }

    subscript(edge: TrackEdgeID) -> Value? {
        var (low, high) = (0, edges.count)
        while low < high {
            let middle = (low + high) / 2
            if edges[middle] < edge {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < edges.count && edges[low] == edge ? values[low] : nil
    }

    /// Every value, in edge order.
    var allValues: [Value] { values }
}

extension TrackResource {
    /// Whether this is a span of edge `edge`.
    func isSpan(of edge: TrackEdgeID) -> Bool {
        if case .span(let span) = self { span.edge == edge } else { false }
    }
}

extension RailwayNetwork {
    /// ``fouls(_:_:)`` with `b` asked a resource at a time.
    func fouls(_ a: Set<TrackResource>, _ b: (TrackResource) -> Bool) -> Bool {
        for resource in a {
            if b(resource) { return true }
            guard case .span(let x) = resource, let partners = foulingSpans[x] else { continue }
            if partners.contains(where: { b(.span($0)) }) { return true }
        }
        return false
    }
}
