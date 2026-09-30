import GameCore

/// The vertical railway of Stage S4 (ARCHITECTURE decision 30) written a
/// second time, straight from the documented rules, for differential
/// testing. Written differently from GameCore on purpose:
///
/// - a height is read as the rise times the area under the grade's shape up
///   to that point (a ramp up, a flat top, a ramp down) over the whole area,
///   with a piece's closed ends taken the other way round from GameCore;
/// - grades are reduced by a subtractive greatest common divisor;
/// - where two pieces of centre line meet is found by solving for both
///   parameters at once (not by orientation tests), and pieces on one line
///   are compared along their longer axis;
/// - clearance is checked on every pair of pieces whose own boxes meet,
///   after the boxes of the checked lines themselves (not boxes from the
///   control points), and never skipped by height;
/// - platforms are found by scanning every station.
extension ReferenceWorld {
    // MARK: - Heights and grades

    /// Decision 30: the height `s` along an edge from its `from` node. The
    /// grade's shape rises evenly over the first transition, stays flat and
    /// falls evenly over the last, so twice the area under it up to `s` is
    /// `s²/T₀`, `2s − T₀` or `D − (L − s)²/T₁`, and twice the whole area is
    /// `D = 2L − T₀ − T₁`; the height above the `from` node is the rise times
    /// the one over the other, rounded halves up.
    static func height(of edge: NetworkEdge, at s: Int64) -> Int64 {
        let rise = edge.endHeight - edge.startHeight
        guard rise != 0 else { return edge.startHeight }
        let length = edge.length
        let (t0, t1) = (edge.startTransition, edge.endTransition)
        let whole = 2 * length - t0 - t1
        if t0 > 0, s <= t0 {
            return edge.startHeight + nearestQuotient(rise * s * s, t0 * whole)
        }
        if t1 > 0, s >= length - t1 {
            let back = length - s
            return edge.startHeight + nearestQuotient(rise * (whole * t1 - back * back), t1 * whole)
        }
        return edge.startHeight + nearestQuotient(rise * (2 * s - t0), whole)
    }

    /// Decision 30: the grade `s` along an edge toward its `to` node, in
    /// lowest terms with a positive run: twice the rise times the grade's
    /// shape there over `D`.
    static func slope(of edge: NetworkEdge, at s: Int64) -> (rise: Int64, run: Int64) {
        let rise = edge.endHeight - edge.startHeight
        guard rise != 0 else { return (0, 1) }
        let length = edge.length
        let (t0, t1) = (edge.startTransition, edge.endTransition)
        let whole = 2 * length - t0 - t1
        if t0 > 0, s <= t0 { return reduced(2 * rise * s, t0 * whole) }
        if t1 > 0, s >= length - t1 { return reduced(2 * rise * (length - s), t1 * whole) }
        return reduced(2 * rise, whole)
    }

    /// `rise / run` in lowest terms, by repeated subtraction of the smaller
    /// magnitude (a remainder at a time).
    static func reduced(_ rise: Int64, _ run: Int64) -> (rise: Int64, run: Int64) {
        guard rise != 0 else { return (0, 1) }
        var (a, b) = (abs(rise), run)
        while a != b {
            if a > b {
                a -= b * max(1, (a - b) / b)
            } else {
                b -= a * max(1, (b - a) / a)
            }
        }
        return (rise / a, run / a)
    }

    /// Decision 30: whether `structure` can carry track at `height`.
    static func carries(_ structure: TrackStructure, _ height: Int64) -> Bool {
        switch structure {
        case .surface: abs(height) <= 128
        case .elevated, .bridge: height >= 0
        case .tunnel: height <= 0
        }
    }

    /// Decision 30: the stretches of an edge's profile from its `from` node.
    static func profileSegments(of edge: NetworkEdge) -> [TrackProfileSegment] {
        let rise = edge.endHeight - edge.startHeight
        let length = edge.length
        if rise == 0 { return [TrackProfileSegment(kind: .level, start: 0, end: length)] }
        let (t0, t1) = (edge.startTransition, edge.endTransition)
        let pieces: [TrackProfileSegment] = [
            TrackProfileSegment(kind: .transition, start: 0, end: t0),
            TrackProfileSegment(kind: rise > 0 ? .up : .down, start: t0, end: length - t1),
            TrackProfileSegment(kind: .transition, start: length - t1, end: length),
        ]
        return pieces.filter { $0.end > $0.start }
    }

    // MARK: - Clearance

    /// Decision 30: whether two edges are clear of each other. Within 1024
    /// of a node they both end at nothing is checked; elsewhere, wherever a
    /// piece of one meets a piece of the other, the lowest height of one
    /// edge at the meeting points must be at least 512 above the highest of
    /// the other.
    static func clear(_ a: NetworkEdge, _ b: NetworkEdge) -> Bool {
        let shared = Set([a.from, a.to]).intersection([b.from, b.to])
        guard let first = checkedLine(of: a, sharing: shared), let second = checkedLine(of: b, sharing: shared) else { return true }
        var boxA = (first[0].point.x, first[0].point.x, first[0].point.y, first[0].point.y)
        for mark in first {
            boxA = (min(boxA.0, mark.point.x), max(boxA.1, mark.point.x), min(boxA.2, mark.point.y), max(boxA.3, mark.point.y))
        }
        var boxB = (second[0].point.x, second[0].point.x, second[0].point.y, second[0].point.y)
        for mark in second {
            boxB = (min(boxB.0, mark.point.x), max(boxB.1, mark.point.x), min(boxB.2, mark.point.y), max(boxB.3, mark.point.y))
        }
        if boxA.1 < boxB.0 || boxB.1 < boxA.0 || boxA.3 < boxB.2 || boxB.3 < boxA.2 { return true }
        // Pieces of one line outside the other line's box meet nothing.
        func near(_ marks: [Mark], _ box: (Int64, Int64, Int64, Int64)) -> [Int] {
            (0..<(marks.count - 1)).filter { k in
                let (u, v) = (marks[k].point, marks[k + 1].point)
                return !(max(u.x, v.x) < box.0 || box.1 < min(u.x, v.x) || max(u.y, v.y) < box.2 || box.3 < min(u.y, v.y))
            }
        }
        let nearB = near(second, boxA)
        for i in near(first, boxB) {
            let (p, q) = (first[i].point, first[i + 1].point)
            for j in nearB {
                let (r, s) = (second[j].point, second[j + 1].point)
                // The two pieces' boxes must meet.
                if max(p.x, q.x) < min(r.x, s.x) || max(r.x, s.x) < min(p.x, q.x) || max(p.y, q.y) < min(r.y, s.y) || max(r.y, s.y) < min(p.y, q.y) {
                    continue
                }
                let meetings = Self.meetings(first[i], first[i + 1], second[j], second[j + 1])
                guard !meetings.isEmpty else { continue }
                let heightsA = meetings.map { Self.height(of: a, at: $0.0) }
                let heightsB = meetings.map { Self.height(of: b, at: $0.1) }
                let aboveB = heightsA.min()! - heightsB.max()!
                let aboveA = heightsB.min()! - heightsA.max()!
                if aboveB < 512, aboveA < 512 { return false }
            }
        }
        return true
    }

    /// A point of a checked line and its chainage along the edge.
    typealias Mark = (point: PlanPoint, at: Int64)

    /// The part of an edge's line that is checked against an edge sharing
    /// the nodes `shared`: from 1024 in at a shared `from` node to 1024 in
    /// at a shared `to` node, the point at each end found by interpolation,
    /// with every sample between; a point on the one before it is left out.
    static func checkedLine(of edge: NetworkEdge, sharing shared: Set<Int>) -> [Mark]? {
        let first: Int64 = shared.contains(edge.from) ? 1_024 : 0
        let last: Int64 = shared.contains(edge.to) ? edge.length - 1_024 : edge.length
        guard first < last else { return nil }
        func point(at s: Int64) -> PlanPoint {
            var k = 0
            while k + 2 < edge.points.count, edge.distances[k + 1] <= s {
                k += 1
            }
            let (p, q) = (edge.points[k], edge.points[k + 1])
            let piece = edge.distances[k + 1] - edge.distances[k]
            return PlanPoint(x: p.x + nearestQuotient((q.x - p.x) * (s - edge.distances[k]), piece), y: p.y + nearestQuotient((q.y - p.y) * (s - edge.distances[k]), piece))
        }
        var marks: [Mark] = [(point(at: first), first)]
        for (sample, s) in zip(edge.points, edge.distances) where s > first && s < last {
            if marks.last!.point != sample { marks.append((sample, s)) }
        }
        let end = point(at: last)
        if marks.last!.point != end { marks.append((end, last)) }
        return marks
    }

    /// Where the piece `p`–`q` meets the piece `r`–`s`, as the chainage of
    /// each meeting point along each edge. Crossing lines meet at the one
    /// point `p + t(q − p) = r + u(s − r)` with both parameters in [0, 1];
    /// pieces on one line meet along the overlap of their spans on the
    /// longer axis, at its two ends.
    static func meetings(_ p: Mark, _ q: Mark, _ r: Mark, _ s: Mark) -> [(Int64, Int64)] {
        let (ax, ay) = (q.point.x - p.point.x, q.point.y - p.point.y)
        let (bx, by) = (s.point.x - r.point.x, s.point.y - r.point.y)
        let (wx, wy) = (r.point.x - p.point.x, r.point.y - p.point.y)
        var denominator = ax * by - ay * bx
        var tNumerator = wx * by - wy * bx
        var uNumerator = wx * ay - wy * ax
        if denominator != 0 {
            if denominator < 0 {
                denominator = -denominator
                tNumerator = -tNumerator
                uNumerator = -uNumerator
            }
            guard tNumerator >= 0, tNumerator <= denominator, uNumerator >= 0, uNumerator <= denominator else { return [] }
            return [(
                p.at + scaled(tNumerator, q.at - p.at, denominator),
                r.at + scaled(uNumerator, s.at - r.at, denominator)
            )]
        }
        // Parallel: they meet only if they lie on one line.
        guard wx * ay - wy * ax == 0 else { return [] }
        let useX = abs(ax) >= abs(ay)
        func coordinate(_ point: PlanPoint) -> Int64 { useX ? point.x : point.y }
        let low = max(min(coordinate(p.point), coordinate(q.point)), min(coordinate(r.point), coordinate(s.point)))
        let high = min(max(coordinate(p.point), coordinate(q.point)), max(coordinate(r.point), coordinate(s.point)))
        guard low <= high else { return [] }
        // The chainage at `c` along a piece from `from` to `to` on that axis.
        func along(_ from: Mark, _ to: Mark, _ c: Int64) -> Int64 {
            var span = coordinate(to.point) - coordinate(from.point)
            var into = c - coordinate(from.point)
            if span < 0 {
                span = -span
                into = -into
            }
            return from.at + scaled(into, to.at - from.at, span)
        }
        return [low, high].map { (along(p, q, $0), along(r, s, $0)) }
    }

    /// `a × b / c` rounded, halves up, for non-negative `a` and `b` and a
    /// positive `c`, with `a <= c`: the whole part of `a / c` times `b` plus
    /// the rest worked out from the remainder, so nothing overflows for the
    /// small maps the reference is used on.
    static func scaled(_ a: Int64, _ b: Int64, _ c: Int64) -> Int64 {
        let whole = a / c
        let rest = a % c
        return whole * b + nearestQuotient(rest * b, c)
    }

    // MARK: - Portals and platforms

    /// Decision 30: the nodes where a tunnel edge and another edge both end.
    var tunnelPortals: [Int] {
        networkNodes.keys.sorted().filter { node in
            let structures = networkEdges.values.filter { $0.from == node || $0.to == node }.map(\.structure)
            return structures.contains(.tunnel) && structures.contains { $0 != .tunnel }
        }
    }

    /// Decision 30: whether a platform fits its edge: within it and level.
    func fits(_ platform: TrackPlatform) -> Bool {
        guard case .edge(let number) = platform.edge, let edge = networkEdges[number] else { return false }
        guard platform.start >= 0, platform.end > platform.start, platform.end <= edge.length else { return false }
        return Self.height(of: edge, at: platform.start) == Self.height(of: edge, at: platform.end)
    }

    mutating func addTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64, to end: Int64) -> GameError? {
        guard let i = stations.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownStation(id) }
        guard case .edge(let number) = edge, networkEdges[number] != nil else { return .unknownTrackEdge(edge) }
        let platform = TrackPlatform(station: id, edge: edge, start: start, end: end)
        let overlapping = stations.flatMap(\.trackPlatforms).contains { $0.edge == edge && max($0.start, start) < min($0.end, end) }
        guard fits(platform), !overlapping else { return .invalidPlatform }
        // Decision 32: no new cut in spans a train holds.
        if let holder = holderOfSpans(on: edge) { return .trackReserved(TrainID(rawValue: holder)) }
        stations[i].trackPlatforms.append(platform)
        stations[i].trackPlatforms.sort { ($0.edge, $0.start) < ($1.edge, $1.start) }
        return nil
    }

    mutating func removeTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64) -> GameError? {
        guard let i = stations.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownStation(id) }
        guard let platform = stations[i].trackPlatforms.first(where: { $0.edge == edge && $0.start == start }) else { return .invalidPlatform }
        // Decision 31: not while a service needs it.
        if let train = serviceNeeding(platform) { return .trainServiceActive(train) }
        if let holder = holderOfSpans(on: edge) { return .trackReserved(TrainID(rawValue: holder)) }
        stations[i].trackPlatforms.removeAll { $0 == platform }
        return nil
    }

    /// Decision 30: every station's platforms, by edge and then along it.
    var allTrackPlatforms: [TrackPlatform] {
        stations.flatMap(\.trackPlatforms).sorted { ($0.edge, $0.start) < ($1.edge, $1.start) }
    }

    /// Decision 30: the platforms a whole train stands along: its head and
    /// its whole body on the platform's edge, between its ends; by where
    /// they start.
    func trackPlatformsAlong(_ id: TrainID) -> [TrackPlatform] {
        guard let train = trains.first(where: { $0.id == id.rawValue }), case .onEdge(let traversal, let offset)? = train.position,
              case .edge(let number) = traversal.edge, let edge = networkEdges[number]
        else { return [] }
        let length = Self.length(train)
        // The body must not reach back beyond the start of the head's edge.
        guard offset >= length else { return [] }
        let head = traversal.direction == .forward ? offset : edge.length - offset
        let tail = traversal.direction == .forward ? offset - length : edge.length - offset + length
        var found: [TrackPlatform] = []
        for station in stations {
            for platform in station.trackPlatforms where platform.edge == traversal.edge {
                if platform.start <= min(head, tail), max(head, tail) <= platform.end {
                    found.append(platform)
                }
            }
        }
        return found.sorted { $0.start < $1.start }
    }

    /// Decision 30: each platform of a station with the height and structure
    /// of its edge there.
    func platformLevels(of id: StationID) -> [(TrackPlatform, Int64, TrackStructure)] {
        guard let station = stations.first(where: { $0.id == id.rawValue }) else { return [] }
        return station.trackPlatforms.map { platform in
            let edge = networkEdges[platform.edge.number]!
            return (platform, Self.height(of: edge, at: platform.start), edge.structure)
        }
    }
}

extension ReferenceWorld {
    /// Decision 30: what the alignment of an edge reports: its structure,
    /// its profile's stretches and its steepest grade toward its `to` node.
    func alignment(of edge: NetworkEdge) -> (structure: TrackStructure, segments: [TrackProfileSegment], steepest: TrackGrade) {
        let rise = edge.endHeight - edge.startHeight
        let steepest = Self.reduced(2 * rise, 2 * edge.length - edge.startTransition - edge.endTransition)
        return (edge.structure, Self.profileSegments(of: edge), TrackGrade(rise: steepest.rise, run: steepest.run))
    }
}

extension AlignmentSummary {
    init(_ parts: (structure: TrackStructure, segments: [TrackProfileSegment], steepest: TrackGrade)) {
        self.init(structure: parts.structure, segments: parts.segments, steepest: parts.steepest)
    }
}
