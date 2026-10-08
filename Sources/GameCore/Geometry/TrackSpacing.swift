// The spacing between tracks side by side (Stage F2, ARCHITECTURE decision
// 52). Two edges at one level keep their centre lines at least
// RailwayNetwork.trackSpacing apart in plan; where one passes over the other
// with TrackStructure.clearance between them they may lie over each other,
// as at a grade-separated crossing (Stage S4). Closer than that is allowed
// only between points that are near each other along the track too, within
// RailwayNetwork.partingReach: there the two are one junction's tracks
// parting (a turnout, a ladder of turnouts, a crossing), not two tracks laid
// too close.
//
// Everything here is exact integer arithmetic on checkpoints along each
// edge, the other edge's sampled centre line and the lengths of the edges
// between them, worked out when an edge is built or a save is loaded, never
// while trains move.

/// A pair of edges, the lower numbered first: two edges closer than the
/// track spacing that were built before the spacing rule (see
/// ``RailwayNetwork/spacingExemptions``).
public struct TrackEdgePair: Hashable, Comparable, Sendable {
    public let first: TrackEdgeID
    public let second: TrackEdgeID

    /// The pair of `a` and `b`, in either order.
    ///
    /// - Precondition: `a != b`.
    public init(_ a: TrackEdgeID, _ b: TrackEdgeID) {
        precondition(a != b, "a pair of edges needs two different edges")
        (first, second) = a < b ? (a, b) : (b, a)
    }

    /// Whether `edge` is one of the two.
    public func contains(_ edge: TrackEdgeID) -> Bool {
        first == edge || second == edge
    }

    public static func < (lhs: TrackEdgePair, rhs: TrackEdgePair) -> Bool {
        (lhs.first, lhs.second) < (rhs.first, rhs.second)
    }
}

enum TrackSpacing {
    /// How far apart the checkpoints along an edge are: 64 units (1 m),
    /// the most a curve's samples are apart (see ``TrackGeometry``).
    static let checkpointStep: Int64 = 64

    /// Whether edges `a` and `b` keep the spacing: no checkpoint of either
    /// is close to a piece of the other (see ``closePieces(to:of:)``) at a
    /// point more than ``RailwayNetwork/partingReach`` from it along the
    /// track. `distance` gives the length of the shortest way along the
    /// track between two nodes, or `nil` when it is longer than the reach.
    static func isSpaced(_ a: ClearanceShape, _ b: ClearanceShape, distance: (TrackNodeID, TrackNodeID) -> Int64?) -> Bool {
        let w = RailwayNetwork.trackSpacing
        guard a.minimum.x - w < b.maximum.x, b.minimum.x - w < a.maximum.x, a.minimum.y - w < b.maximum.y, b.minimum.y - w < a.maximum.y else {
            return true
        }
        if a.lowest - b.highest >= TrackStructure.clearance || b.lowest - a.highest >= TrackStructure.clearance {
            return true
        }
        let ends = Ends(a, b, distance: distance)
        return keepsAway(a, from: b, ends: ends) && keepsAway(b, from: a, ends: ends.swapped)
    }

    /// The checkpoints along an edge `length` long: every
    /// ``checkpointStep`` from its `from` node, and its `to` node.
    static func checkpoints(along length: Int64) -> [Int64] {
        var checkpoints: [Int64] = []
        var at: Int64 = 0
        while at < length {
            checkpoints.append(at)
            at += checkpointStep
        }
        return checkpoints + [length]
    }

    /// The shortest ways along the track between the ends of two edges:
    /// `from` and `to` of the first by `from` and `to` of the second, `nil`
    /// where longer than the reach.
    struct Ends {
        let ways: [[Int64?]]

        init(_ a: ClearanceShape, _ b: ClearanceShape, distance: (TrackNodeID, TrackNodeID) -> Int64?) {
            ways = [a.from, a.to].map { x in [b.from, b.to].map { y in x == y ? 0 : distance(x, y) } }
        }

        private init(ways: [[Int64?]]) {
            self.ways = ways
        }

        /// The same ways seen from the second edge.
        var swapped: Ends {
            Ends(ways: [[ways[0][0], ways[1][0]], [ways[0][1], ways[1][1]]])
        }

        /// Whether the point `s` along the first edge (`length` long) is
        /// within `limit` along the track of the point `t` along the second
        /// (`otherLength` long): out through an end of the first, along the
        /// shortest way to an end of the second, and along it to `t`.
        /// `limit` is at most the reach the ways were found within.
        func isWithin(_ limit: Int64, _ s: Int64, of length: Int64, _ t: Int64, of otherLength: Int64) -> Bool {
            for (i, out) in [s, length - s].enumerated() {
                for (j, back) in [t, otherLength - t].enumerated() {
                    if let between = ways[i][j], out + between + back <= limit { return true }
                }
            }
            return false
        }
    }

    /// Whether no checkpoint of `a` is close to a piece of `b` at a point
    /// beyond the reach along the track.
    private static func keepsAway(_ a: ClearanceShape, from b: ClearanceShape, ends: Ends) -> Bool {
        let pieces = Pieces(b, near: a)
        guard !pieces.indices.isEmpty else { return true }
        let length = a.geometry.length
        let otherLength = b.geometry.length
        for s in checkpoints(along: length) {
            for t in closePieces(to: a.geometry.location(at: s).position, of: pieces)
            where !ends.isWithin(RailwayNetwork.partingReach, s, of: length, t, of: otherLength) {
                return false
            }
        }
        return true
    }

    /// The pieces of an edge's sampled centre line that come within the
    /// track spacing of another edge's box, filed by the cells of
    /// ``cellSize`` their boxes widened by the spacing touch: every piece
    /// less than the spacing from a point is filed under the point's cell,
    /// so a point is only tried against the pieces there. Only a way to find
    /// them faster; which pieces are close does not depend on it.
    struct Pieces {
        static let cellSize: Int64 = 1_024

        let shape: ClearanceShape
        let indices: [Int]
        private let cells: [Cell: [Int]]

        struct Cell: Hashable {
            let x: Int64
            let y: Int64

            init(_ x: Int64, _ y: Int64) {
                self.x = x
                self.y = y
            }

            /// The cell `point` lies in.
            init(of point: PlanPoint) {
                self.init(Self.cell(point.x), Self.cell(point.y))
            }

            /// `⌊v ÷ cellSize⌋`.
            static func cell(_ v: Int64) -> Int64 {
                v >= 0 ? v / Pieces.cellSize : -((-v + Pieces.cellSize - 1) / Pieces.cellSize)
            }
        }

        init(_ shape: ClearanceShape, near other: ClearanceShape) {
            self.shape = shape
            let w = RailwayNetwork.trackSpacing
            let points = shape.geometry.points
            indices = points.indices.dropLast().filter { i in
                let (p, q) = (points[i].plan, points[i + 1].plan)
                return min(p.x, q.x) - w < other.maximum.x && other.minimum.x - w < max(p.x, q.x)
                    && min(p.y, q.y) - w < other.maximum.y && other.minimum.y - w < max(p.y, q.y)
            }
            // Each piece is filed column by column of cells (decision 88):
            // under a column, only the cells beside the part of the piece a
            // point there can be less than the spacing from, so a long
            // slanting piece files cells as its length, not as its box's
            // area (some 10^9 cells for a straight edge across Taiwan).
            let size = Pieces.cellSize
            var cells: [Cell: [Int]] = [:]
            for i in indices {
                let (p, q) = (points[i].plan, points[i + 1].plan)
                let (left, right) = p.x <= q.x ? (p, q) : (q, p)
                for x in Cell.cell(left.x - w)...Cell.cell(right.x + w) {
                    // A point in this column less than the spacing from the
                    // piece is nearest a point of it within the spacing of
                    // the column, between `from` and `to`; the piece's
                    // heights there, a unit wider either way for the
                    // division's rounding.
                    let from = max(left.x, x * size - w), to = min(right.x, (x + 1) * size - 1 + w)
                    var low = min(p.y, q.y), high = max(p.y, q.y)
                    if left.x != right.x {
                        let a = left.y + (from - left.x) * (right.y - left.y) / (right.x - left.x)
                        let b = left.y + (to - left.x) * (right.y - left.y) / (right.x - left.x)
                        low = max(low, min(a, b) - 1)
                        high = min(high, max(a, b) + 1)
                    }
                    for y in Cell.cell(low - w)...Cell.cell(high + w) {
                        cells[Cell(x, y), default: []].append(i)
                    }
                }
            }
            self.cells = cells
        }

        /// The pieces that may be less than the spacing from `point`, in
        /// order along the edge.
        func near(_ point: PlanPoint) -> [Int] {
            cells[Cell(of: point)] ?? []
        }
    }

    /// Where `point` is close to the edge whose `pieces` these are: for each
    /// piece less than ``RailwayNetwork/trackSpacing`` from it in plan where
    /// the edge is less than ``TrackStructure/clearance`` above or below it,
    /// the chainage along the edge of the point of the piece nearest it.
    ///
    /// The nearest point is an end of the piece, or, when the point lies
    /// beside the piece, its foot on the piece; that foot's chainage is
    /// interpolated along the piece and rounded, halves up. The squared
    /// distance beside a piece is compared as `cross² < w² · |piece|²` in
    /// 128 bits (``WideInteger``), so nothing overflows.
    static func closePieces(to point: WorldCoordinate, of pieces: Pieces) -> [Int64] {
        let w = RailwayNetwork.trackSpacing
        let geometry = pieces.shape.geometry
        let p = point.plan
        var found: [Int64] = []
        for i in pieces.near(p) {
            let (r, s) = (geometry.points[i].plan, geometry.points[i + 1].plan)
            guard min(r.x, s.x) - w < p.x, p.x < max(r.x, s.x) + w, min(r.y, s.y) - w < p.y, p.y < max(r.y, s.y) + w else { continue }
            let way = s.vector(from: r)
            let offset = p.vector(from: r)
            let along = offset.dot(way)
            let squared = way.dot(way)
            let chainage: Int64
            if along <= 0 {
                guard offset.dot(offset) < w * w else { continue }
                chainage = geometry.distances[i]
            } else if along >= squared {
                let beyond = p.vector(from: s)
                guard beyond.dot(beyond) < w * w else { continue }
                chainage = geometry.distances[i + 1]
            } else {
                let cross = way.cross(offset).magnitude
                guard WideInteger.product(cross, cross) < WideInteger.product(w * w, squared) else { continue }
                chainage = geometry.distances[i] + FixedPoint.roundedProduct(along, times: geometry.distances[i + 1] - geometry.distances[i], over: squared)
            }
            if abs(point.z - geometry.height(at: chainage)) < TrackStructure.clearance { found.append(chainage) }
        }
        return found
    }
}

extension RailwayNetwork {
    /// The length of the shortest way along the track from node `start` to
    /// every node at most `reach` from it, by edges in either direction
    /// whatever they join (Dijkstra's algorithm on exact integer lengths).
    func trackDistances(from start: TrackNodeID, within reach: Int64) -> [TrackNodeID: Int64] {
        var settled: [TrackNodeID: Int64] = [:]
        var frontier: [TrackNodeID: Int64] = [start: 0]
        while let (node, distance) = frontier.min(by: { ($0.value, $0.key) < ($1.value, $1.key) }) {
            frontier[node] = nil
            settled[node] = distance
            for end in self.node(node)?.ends ?? [] {
                guard let edge = edge(end.edge) else { continue }
                let other = edge.from == node ? edge.to : edge.from
                let next = distance + edge.length
                guard settled[other] == nil, next <= reach, next < frontier[other] ?? Int64.max else { continue }
                frontier[other] = next
            }
        }
        return settled
    }

    /// The lowest numbered edge that an edge from `from` to `to` shaped by
    /// `curve` into `geometry` would come closer to than the track spacing
    /// beyond the reach along the track (see
    /// ``TrackSpacing/isSpaced(_:_:distance:)``), or `nil`. Pairs that
    /// ``spacingExemptions`` lists do not help a new edge. The ways along
    /// the track are this network's, without the new edge: a way through it
    /// is never shorter than one leaving the point along it.
    func firstTooClose(from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, geometry: TrackGeometry) -> TrackEdgeID? {
        let shape = ClearanceShape(from: from, to: to, curve: curve, geometry: geometry)
        let box = PlanBox(shape)
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        for edge in edges {
            guard let near = planBox(of: edge), near.mayComeClose(to: box), let other = clearanceShape(of: edge.id) else { continue }
            let spaced = TrackSpacing.isSpaced(shape, other) { a, b in
                if reach[a] == nil { reach[a] = trackDistances(from: a, within: Self.partingReach) }
                return reach[a]?[b]
            }
            if !spaced { return edge.id }
        }
        return nil
    }

    /// The lowest numbered edge other than `id` and those in `besides`
    /// that edge `id` of this network comes closer to than the track
    /// spacing beyond the reach, along this network's ways (with `id` in
    /// it), or `nil`: for the parts of a split edge, which only together
    /// part from the track the edge parted from.
    func firstTooClose(existing id: TrackEdgeID, besides: Set<TrackEdgeID>) -> TrackEdgeID? {
        guard let shape = clearanceShape(of: id), let edge = edge(id), let box = planBox(of: edge) else { return nil }
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        for edge in edges where edge.id != id && !besides.contains(edge.id) {
            guard let near = planBox(of: edge), near.mayComeClose(to: box), let other = clearanceShape(of: edge.id) else { continue }
            let spaced = TrackSpacing.isSpaced(shape, other) { a, b in
                if reach[a] == nil { reach[a] = trackDistances(from: a, within: Self.partingReach) }
                return reach[a]?[b]
            }
            if !spaced { return edge.id }
        }
        return nil
    }

    /// Every pair of edges closer than the track spacing beyond the reach,
    /// in order: what the ``GameWorld`` decoder compares with
    /// ``spacingExemptions``. `geometries` are the edges' geometries in ID
    /// order, worked out once by the caller.
    func tooClosePairs(geometries: [TrackGeometry]) -> [TrackEdgePair] {
        let shapes = zip(edges, geometries).map { edge, geometry in
            (edge.id, ClearanceShape(from: edge.from, to: edge.to, curve: edge.curve, geometry: geometry))
        }
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        var pairs: [TrackEdgePair] = []
        for i in shapes.indices {
            for j in shapes.indices where j > i {
                let spaced = TrackSpacing.isSpaced(shapes[i].1, shapes[j].1) { a, b in
                    if reach[a] == nil { reach[a] = trackDistances(from: a, within: Self.partingReach) }
                    return reach[a]?[b]
                }
                if !spaced { pairs.append(TrackEdgePair(shapes[i].0, shapes[j].0)) }
            }
        }
        return pairs
    }

    /// The first pair of edges, in order, that removing edge `id` would
    /// leave closer than the track spacing beyond the reach, and that
    /// ``spacingExemptions`` does not list; `nil` when there is none (or no
    /// such edge).
    ///
    /// Removing an edge only makes ways along the track longer, and only
    /// ways through it, which run within the reach of its ends: so only
    /// pairs of edges ending within the reach of them are checked, along
    /// the network without it.
    func firstPairLeftTooClose(removing id: TrackEdgeID) -> TrackEdgePair? {
        guard let removed = edge(id) else { return nil }
        let near = Set(trackDistances(from: removed.from, within: Self.partingReach).keys)
            .union(trackDistances(from: removed.to, within: Self.partingReach).keys)
        var after = self
        after.removeEdge(id, updatingFouling: false)
        let candidates = after.edges.filter { near.contains($0.from) || near.contains($0.to) }
        let boxes = candidates.map { after.planBox(of: $0) }
        var shapes: [TrackEdgeID: ClearanceShape] = [:]
        func shape(_ edge: TrackEdge) -> ClearanceShape? {
            if shapes[edge.id] == nil { shapes[edge.id] = after.clearanceShape(of: edge.id) }
            return shapes[edge.id]
        }
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                let pair = TrackEdgePair(candidates[i].id, candidates[j].id)
                guard !spacingExemptions.contains(pair), let a = boxes[i], let b = boxes[j], a.mayComeClose(to: b),
                      let first = shape(candidates[i]), let second = shape(candidates[j])
                else { continue }
                let spaced = TrackSpacing.isSpaced(first, second) { a, b in
                    if reach[a] == nil { reach[a] = after.trackDistances(from: a, within: Self.partingReach) }
                    return reach[a]?[b]
                }
                if !spaced { return pair }
            }
        }
        return nil
    }

    /// Drops the spacing exemptions whose edges keep the spacing now: a new
    /// edge may join them within the reach. Building only makes ways along
    /// the track shorter, so no pair becomes too close.
    mutating func dropSpacedExemptions() {
        guard !spacingExemptions.isEmpty else { return }
        var reach: [TrackNodeID: [TrackNodeID: Int64]] = [:]
        let kept = spacingExemptions.filter { pair in
            guard let a = clearanceShape(of: pair.first), let b = clearanceShape(of: pair.second) else { return false }
            return !TrackSpacing.isSpaced(a, b) { x, y in
                if reach[x] == nil { reach[x] = trackDistances(from: x, within: Self.partingReach) }
                return reach[x]?[y]
            }
        }
        exemptFromSpacing(kept)
    }

    /// The box in plan an edge's centre line stays within, from its end
    /// nodes and control points (a curve lies within the hull of its
    /// control points), and the lowest and highest it runs (its ends):
    /// the same box ``ClearanceShape`` has, without sampling the curve.
    func planBox(of edge: TrackEdge) -> PlanBox? {
        guard let from = node(edge.from), let to = node(edge.to) else { return nil }
        let corners = [from.position.plan, to.position.plan] + edge.curve.controlPoints
        return PlanBox(
            minimum: PlanPoint(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!),
            maximum: PlanPoint(x: corners.map(\.x).max()!, y: corners.map(\.y).max()!),
            lowest: min(from.position.z, to.position.z), highest: max(from.position.z, to.position.z)
        )
    }
}

/// An edge's box in plan and the heights it runs between, to pass over
/// pairs of edges that can have no points close before sampling them.
struct PlanBox {
    let minimum: PlanPoint
    let maximum: PlanPoint
    let lowest: Int64
    let highest: Int64

    init(minimum: PlanPoint, maximum: PlanPoint, lowest: Int64, highest: Int64) {
        self.minimum = minimum
        self.maximum = maximum
        self.lowest = lowest
        self.highest = highest
    }

    init(_ shape: ClearanceShape) {
        self.init(minimum: shape.minimum, maximum: shape.maximum, lowest: shape.lowest, highest: shape.highest)
    }

    /// Whether some point of the one edge can be less than the track
    /// spacing in plan and less than the clearance in height from some
    /// point of the other: the test ``TrackSpacing`` makes first.
    func mayComeClose(to other: PlanBox) -> Bool {
        let w = RailwayNetwork.trackSpacing
        return minimum.x - w < other.maximum.x && other.minimum.x - w < maximum.x
            && minimum.y - w < other.maximum.y && other.minimum.y - w < maximum.y
            && lowest - other.highest < TrackStructure.clearance && other.lowest - highest < TrackStructure.clearance
    }
}
