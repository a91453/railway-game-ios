// Clearance between tracks (Phase 4.5 Stage S4, ARCHITECTURE decision 30).
// Only a shared node joins two edges (Stage S3). So wherever the centre lines
// of two edges meet in plan anywhere else, one must pass over the other with
// at least TrackStructure.clearance between them: a grade-separated crossing,
// where trains share no track and cannot meet. A crossing at one height must
// be a node the edges share, a level crossing whose node both directions
// occupy (Stage S1). Edges that share a node leave it side by side, so they
// are not checked within RailwayNetwork.junctionZone of it.
//
// Everything here is exact integer arithmetic on the sampled centre lines,
// worked out when an edge is built or a save is loaded, never while trains
// move.

/// An edge's shape as the clearance rules see it: its end nodes, the box
/// its centre line stays within, and its geometry.
struct ClearanceShape {
    let from: TrackNodeID
    let to: TrackNodeID
    /// The smallest box in plan holding the end nodes and the control
    /// points. A curve lies within the hull of its control points, and
    /// rounding a point inside the box keeps it inside, so every sample is
    /// in the box.
    let minimum: PlanPoint
    let maximum: PlanPoint
    let geometry: TrackGeometry

    init(from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, geometry: TrackGeometry) {
        self.from = from
        self.to = to
        self.geometry = geometry
        let corners = [geometry.points[0].plan, geometry.points[geometry.points.count - 1].plan] + curve.controlPoints
        minimum = PlanPoint(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!)
        maximum = PlanPoint(x: corners.map(\.x).max()!, y: corners.map(\.y).max()!)
    }

    /// The lowest and highest the edge runs: its ends, as its height never
    /// turns back (see ``TrackGeometry/height(at:)``).
    var lowest: Int64 { min(geometry.startHeight, geometry.endHeight) }
    var highest: Int64 { max(geometry.startHeight, geometry.endHeight) }
}

enum TrackClearance {
    /// Whether edges `a` and `b` are clear of each other: wherever their
    /// centre lines meet in plan, one is at least
    /// ``TrackStructure/clearance`` above the other.
    ///
    /// Within ``RailwayNetwork/junctionZone`` of a node both end at, they are
    /// not checked. The rest of each centre line (see
    /// ``TrackGeometry/stretch(from:to:)``) is checked piece against piece.
    /// Where two pieces meet, at a single point or, lying on one line,
    /// along a stretch between two of their ends, the chainage of each
    /// meeting point along each edge is interpolated along its piece and
    /// rounded (halves up), and the height there read from the edge's
    /// profile. The pieces are clear when the lowest of one edge's heights
    /// at those points is at least the clearance above the highest of the
    /// other's. Heights never turn back along an edge, so that holds along
    /// the whole meeting.
    static func isClear(_ a: ClearanceShape, _ b: ClearanceShape) -> Bool {
        guard a.minimum.x <= b.maximum.x, b.minimum.x <= a.maximum.x, a.minimum.y <= b.maximum.y, b.minimum.y <= a.maximum.y else {
            return true
        }
        if a.lowest - b.highest >= TrackStructure.clearance || b.lowest - a.highest >= TrackStructure.clearance {
            return true
        }
        let shared: Set<TrackNodeID> = Set([a.from, a.to]).intersection([b.from, b.to])
        guard let first = stretch(of: a, sharing: shared), let second = stretch(of: b, sharing: shared) else { return true }
        // Only pieces within the other edge's box can meet it.
        let firstPieces = pieces(of: first.points, within: b.minimum, b.maximum)
        let secondPieces = pieces(of: second.points, within: a.minimum, a.maximum)
        for i in firstPieces {
            let p = first.points[i]
            let q = first.points[i + 1]
            for j in secondPieces {
                let r = second.points[j]
                let s = second.points[j + 1]
                guard min(p.x, q.x) <= max(r.x, s.x), min(r.x, s.x) <= max(p.x, q.x),
                      min(p.y, q.y) <= max(r.y, s.y), min(r.y, s.y) <= max(p.y, q.y)
                else { continue }
                let meetings = meetingPoints(
                    p, q, along: (first.distances[i], first.distances[i + 1]),
                    r, s, along: (second.distances[j], second.distances[j + 1])
                )
                guard !meetings.isEmpty else { continue }
                let heightsA = meetings.map { a.geometry.height(at: $0.a) }
                let heightsB = meetings.map { b.geometry.height(at: $0.b) }
                guard heightsA.min()! - heightsB.max()! >= TrackStructure.clearance
                    || heightsB.min()! - heightsA.max()! >= TrackStructure.clearance
                else { return false }
            }
        }
        return true
    }

    /// The index of the first point of every piece of `points` whose box
    /// meets the box from `minimum` to `maximum`.
    private static func pieces(of points: [PlanPoint], within minimum: PlanPoint, _ maximum: PlanPoint) -> [Int] {
        points.indices.dropLast().filter { i in
            let (p, q) = (points[i], points[i + 1])
            return min(p.x, q.x) <= maximum.x && minimum.x <= max(p.x, q.x) && min(p.y, q.y) <= maximum.y && minimum.y <= max(p.y, q.y)
        }
    }

    /// The part of `shape`'s centre line that is checked against an edge
    /// sharing the nodes `shared` with it: all of it, less
    /// ``RailwayNetwork/junctionZone`` at each shared end. `nil` when nothing
    /// is left.
    private static func stretch(of shape: ClearanceShape, sharing shared: Set<TrackNodeID>) -> (points: [PlanPoint], distances: [Int64])? {
        let length = shape.geometry.length
        let start = shared.contains(shape.from) ? RailwayNetwork.junctionZone : 0
        let end = shared.contains(shape.to) ? length - RailwayNetwork.junctionZone : length
        guard start < end else { return nil }
        let stretch = shape.geometry.stretch(from: start, to: end)
        return (stretch.points.map(\.plan), stretch.distances)
    }

    /// Where piece `p`–`q` of one edge (at chainages `a.start` to `a.end`
    /// along it) meets piece `r`–`s` of another (at `b.start` to `b.end`):
    /// the chainage of each meeting point along each edge. Empty when the
    /// pieces do not meet. A crossing gives one point; otherwise every end
    /// of one piece that lies on the other is a meeting point.
    static func meetingPoints(
        _ p: PlanPoint, _ q: PlanPoint, along a: (start: Int64, end: Int64),
        _ r: PlanPoint, _ s: PlanPoint, along b: (start: Int64, end: Int64)
    ) -> [(a: Int64, b: Int64)] {
        let d1 = orientation(p, q, r)
        let d2 = orientation(p, q, s)
        let d3 = orientation(r, s, p)
        let d4 = orientation(r, s, q)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            // A crossing: p + t(q − p) with t = |d3| / (|d3| + |d4|), and
            // likewise along r–s.
            return [(
                a.start + FixedPoint.roundedProduct(abs(d3), times: a.end - a.start, over: abs(d3) + abs(d4)),
                b.start + FixedPoint.roundedProduct(abs(d1), times: b.end - b.start, over: abs(d1) + abs(d2))
            )]
        }
        var meetings: [(a: Int64, b: Int64)] = []
        if d1 == 0, lies(r, within: p, q) { meetings.append((chainage(of: r, from: p, to: q, along: a), b.start)) }
        if d2 == 0, lies(s, within: p, q) { meetings.append((chainage(of: s, from: p, to: q, along: a), b.end)) }
        if d3 == 0, lies(p, within: r, s) { meetings.append((a.start, chainage(of: p, from: r, to: s, along: b))) }
        if d4 == 0, lies(q, within: r, s) { meetings.append((a.end, chainage(of: q, from: r, to: s, along: b))) }
        return meetings
    }

    /// Which side of the line from `p` through `q` the point `r` lies: the
    /// cross product of `q − p` and `r − p`, positive, negative, or 0 on the
    /// line.
    private static func orientation(_ p: PlanPoint, _ q: PlanPoint, _ r: PlanPoint) -> Int64 {
        q.vector(from: p).cross(r.vector(from: p))
    }

    /// Whether `x`, on the line through `p` and `q`, lies between them.
    private static func lies(_ x: PlanPoint, within p: PlanPoint, _ q: PlanPoint) -> Bool {
        min(p.x, q.x) <= x.x && x.x <= max(p.x, q.x) && min(p.y, q.y) <= x.y && x.y <= max(p.y, q.y)
    }

    /// The chainage of `x`, which lies on the piece from `p` to `q`: the
    /// piece's chainages interpolated by `t = (x − p)·(q − p) / |q − p|²`
    /// and rounded, halves up.
    private static func chainage(of x: PlanPoint, from p: PlanPoint, to q: PlanPoint, along piece: (start: Int64, end: Int64)) -> Int64 {
        let way = q.vector(from: p)
        return piece.start + FixedPoint.roundedProduct(x.vector(from: p).dot(way), times: piece.end - piece.start, over: way.dot(way))
    }
}

extension RailwayNetwork {
    /// The shape of edge `id` for the clearance rules, or `nil` if there is
    /// no such edge.
    func clearanceShape(of id: TrackEdgeID) -> ClearanceShape? {
        guard let edge = edge(id), let geometry = geometry(of: id) else { return nil }
        return ClearanceShape(from: edge.from, to: edge.to, curve: edge.curve, geometry: geometry)
    }

    /// The lowest numbered edge that an edge from `from` to `to` shaped by
    /// `curve` into `geometry` would meet without clearance (see
    /// ``TrackClearance/isClear(_:_:)``), or `nil`. Only edges whose boxes
    /// meet the new edge's are sampled.
    func firstConflict(from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, geometry: TrackGeometry) -> TrackEdgeID? {
        let shape = ClearanceShape(from: from, to: to, curve: curve, geometry: geometry)
        for edge in edges {
            guard let other = clearanceShape(of: edge.id) else { continue }
            if !TrackClearance.isClear(shape, other) { return edge.id }
        }
        return nil
    }

    /// The first two edges, in ID order, that meet without clearance, or
    /// `nil`: what the ``GameWorld`` decoder rejects. `geometries` are the
    /// edges' geometries in ID order, worked out once by the caller.
    func firstConflictingPair(geometries: [TrackGeometry]) -> (TrackEdgeID, TrackEdgeID)? {
        let shapes = zip(edges, geometries).map { edge, geometry in
            (edge.id, ClearanceShape(from: edge.from, to: edge.to, curve: edge.curve, geometry: geometry))
        }
        for i in shapes.indices {
            for j in shapes.indices where j > i {
                if !TrackClearance.isClear(shapes[i].1, shapes[j].1) { return (shapes[i].0, shapes[j].0) }
            }
        }
        return nil
    }
}
