import GameCore

/// The track spacing of Stage F2 (ARCHITECTURE decision 52) written a second
/// time, straight from the documented rule, for differential testing.
/// Written differently from GameCore on purpose:
///
/// - a checkpoint's point is found by walking the samples from the start,
///   not by binary search;
/// - the distance beside a piece is compared without 128-bit products: the
///   cross product against the spacing times the floor of the piece's
///   length, and only in the band between that and the next whole length
///   by the exact remainder;
/// - the ways along the track are every node to every node at once, relaxed
///   over every edge until nothing changes (not Dijkstra from the ends
///   needed, and not cut off at the reach);
/// - the way from a point is its distance to every node first, then to the
///   other point;
/// - nothing is skipped by boxes or heights.
extension ReferenceWorld {
    /// Decision 52: the length of the shortest way along the track between
    /// every two nodes, by edges in either direction.
    func trackWays() -> [Int: [Int: Int64]] {
        var ways: [Int: [Int: Int64]] = [:]
        for node in networkNodes.keys { ways[node] = [node: 0] }
        var changed = true
        while changed {
            changed = false
            for edge in networkEdges.values {
                for (u, v) in [(edge.from, edge.to), (edge.to, edge.from)] {
                    for (start, known) in ways {
                        guard let there = known[u] else { continue }
                        if there + edge.length < ways[start]?[v] ?? Int64.max {
                            ways[start]?[v] = there + edge.length
                            changed = true
                        }
                    }
                }
            }
        }
        return ways
    }

    /// Decision 52: whether two edges keep 256 apart in plan wherever they
    /// are less than 512 apart in height, but for points within 32768 of
    /// each other along the track.
    /// `ways` is asked for the ways along the track only when some point is
    /// close.
    static func spaced(_ a: NetworkEdge, _ b: NetworkEdge, ways: () -> [Int: [Int: Int64]]) -> Bool {
        apart(a, from: b, ways: ways) && apart(b, from: a, ways: ways)
    }

    /// Whether every checkpoint of `a` close to `b` is within 32768 along
    /// the track of every point of `b` it is close to.
    static func apart(_ a: NetworkEdge, from b: NetworkEdge, ways: () -> [Int: [Int: Int64]]) -> Bool {
        var s: Int64 = 0
        var marks: [Int64] = []
        while s < a.length {
            marks.append(s)
            s += 64
        }
        marks.append(a.length)
        for s in marks {
            let close = near(a, at: s, to: b)
            guard !close.isEmpty else { continue }
            // The way from the point to every node, out through either end.
            let all = ways()
            var toNode: [Int: Int64] = [:]
            for (end, out) in [(a.from, s), (a.to, a.length - s)] {
                for (node, way) in all[end] ?? [:] where out + way < toNode[node] ?? Int64.max {
                    toNode[node] = out + way
                }
            }
            for t in close {
                let ways = [toNode[b.from].map { $0 + t }, toNode[b.to].map { $0 + b.length - t }].compactMap { $0 }
                if !ways.contains(where: { $0 <= 32_768 }) { return false }
            }
        }
        return true
    }

    /// The chainage along `b` of the nearest point of every piece of `b`
    /// less than 256 in plan from the point `s` along `a`, where `b` there
    /// is less than 512 above or below it.
    static func near(_ a: NetworkEdge, at s: Int64, to b: NetworkEdge) -> [Int64] {
        var k = 0
        while k + 2 < a.points.count, a.distances[k + 1] <= s {
            k += 1
        }
        let (u, v) = (a.points[k], a.points[k + 1])
        let piece = a.distances[k + 1] - a.distances[k]
        let p = PlanPoint(
            x: u.x + nearestQuotient((v.x - u.x) * (s - a.distances[k]), piece),
            y: u.y + nearestQuotient((v.y - u.y) * (s - a.distances[k]), piece)
        )
        let height = Self.height(of: a, at: s)
        var found: [Int64] = []
        for j in 0..<(b.points.count - 1) {
            let (r, t) = (b.points[j], b.points[j + 1])
            let (dx, dy) = (t.x - r.x, t.y - r.y)
            let (px, py) = (p.x - r.x, p.y - r.y)
            let lengthSquared = dx * dx + dy * dy
            let along = px * dx + py * dy
            let at: Int64
            if along <= 0 {
                guard px * px + py * py < 65_536 else { continue }
                at = b.distances[j]
            } else if along >= lengthSquared {
                let (qx, qy) = (p.x - t.x, p.y - t.y)
                guard qx * qx + qy * qy < 65_536 else { continue }
                at = b.distances[j + 1]
            } else {
                guard beside(abs(dx * py - dy * px), lengthSquared) else { continue }
                at = b.distances[j] + nearestQuotient(along * (b.distances[j + 1] - b.distances[j]), lengthSquared)
            }
            if abs(height - Self.height(of: b, at: at)) < 512 { found.append(at) }
        }
        return found
    }

    /// Whether `cross / √lengthSquared < 256`, that is `cross² < 256² ·
    /// lengthSquared`. With `root = ⌊√lengthSquared⌋`: it holds when `cross <
    /// 256·root`, fails when `cross >= 256·(root + 1)`, and in between, with
    /// `cross = 256·root + e`, holds exactly when `2·256·root·e + e² < 256² ·
    /// (lengthSquared − root²)`.
    static func beside(_ cross: Int64, _ lengthSquared: Int64) -> Bool {
        let root = floorRoot(lengthSquared)
        if cross < 256 * root { return true }
        if cross >= 256 * (root + 1) { return false }
        let e = cross - 256 * root
        return 2 * 256 * root * e + e * e < 65_536 * (lengthSquared - root * root)
    }
}

/// The reference's fouling (decision 53) of one network: worked out when
/// first asked for and kept while the network (its edges and platforms) is
/// the same, so that worlds that never ask, without traffic control, never
/// pay for it. Shared by copies of a world; keyed by the network itself, so
/// a copy with another network never reads another's.
final class ReferenceFoulingMemo: Equatable {
    private var edges: [Int: ReferenceWorld.NetworkEdge]?
    private var platforms: [TrackPlatform] = []
    private var value: Set<[TrackSpan]> = []

    func fouling(of world: ReferenceWorld) -> Set<[TrackSpan]> {
        let platforms = world.stations.flatMap(\.trackPlatforms)
        if edges == world.networkEdges, self.platforms == platforms { return value }
        value = world.workOutFouling()
        edges = world.networkEdges
        self.platforms = platforms
        return value
    }

    /// The memo is not part of a world's value.
    static func == (lhs: ReferenceFoulingMemo, rhs: ReferenceFoulingMemo) -> Bool {
        true
    }
}

extension ReferenceWorld {
    /// Decision 53: every pair of spans that foul each other, both ways
    /// round.
    var fouling: Set<[TrackSpan]> {
        foulingMemo.fouling(of: self)
    }

    /// Decision 53 (Stage F2b): whether track in `a` and track in `b` are the
    /// same, or a span of one fouls a span of the other.
    func foul(_ a: Set<TrackResource>, _ b: Set<TrackResource>) -> Bool {
        if a.contains(where: b.contains) { return true }
        let spansB = b.compactMap { if case .span(let y) = $0 { y } else { nil } }
        guard a.contains(where: { if case .span = $0 { true } else { false } }), !spansB.isEmpty else { return false }
        let fouling = self.fouling
        for case .span(let x) in a {
            for y in spansB where fouling.contains([x, y]) { return true }
        }
        return false
    }

    /// Decision 53: every pair of spans of two edges with a point of one
    /// less than 256 in plan from a point of the other, less than 512 apart
    /// in height there, more than 512 apart along the track (or not joined
    /// by track at all), both ways round. Every ordered pair of edges is
    /// looked at, so each checkpoint of each edge is tried against the
    /// other; only pairs whose sampled lines come within 256 of each other's
    /// extent (from the samples themselves) can have such points.
    func workOutFouling() -> Set<[TrackSpan]> {
        var found: Set<[TrackSpan]> = []
        let numbers = networkEdges.keys.sorted()
        var ways: [Int: [Int: Int64]]?
        func extent(_ edge: NetworkEdge) -> (Int64, Int64, Int64, Int64) {
            (edge.points.map(\.x).min()!, edge.points.map(\.x).max()!, edge.points.map(\.y).min()!, edge.points.map(\.y).max()!)
        }
        for a in numbers {
            let ea = networkEdges[a]!
            let spansA = resourceSpans(of: a, length: ea.length)
            let boxA = extent(ea)
            for b in numbers where b != a {
                let eb = networkEdges[b]!
                let boxB = extent(eb)
                if boxA.1 + 256 <= boxB.0 || boxB.1 + 256 <= boxA.0 || boxA.3 + 256 <= boxB.2 || boxB.3 + 256 <= boxA.2 { continue }
                var s: Int64 = 0
                var marks: [Int64] = []
                while s < ea.length {
                    marks.append(s)
                    s += 64
                }
                marks.append(ea.length)
                for s in marks {
                    let close = Self.near(ea, at: s, to: eb)
                    guard !close.isEmpty else { continue }
                    if ways == nil { ways = trackWays() }
                    var toNode: [Int: Int64] = [:]
                    for (end, out) in [(ea.from, s), (ea.to, ea.length - s)] {
                        for (node, way) in ways![end] ?? [:] where out + way < toNode[node] ?? Int64.max {
                            toNode[node] = out + way
                        }
                    }
                    for t in close {
                        let paths = [toNode[eb.from].map { $0 + t }, toNode[eb.to].map { $0 + eb.length - t }].compactMap { $0 }
                        guard !paths.contains(where: { $0 <= 512 }) else { continue }
                        for x in spansA where x.start <= s && s <= x.end {
                            for y in resourceSpans(of: b, length: eb.length) where y.start <= t && t <= y.end {
                                let p = TrackSpan(edge: .edge(a), start: x.start, end: x.end)
                                let q = TrackSpan(edge: .edge(b), start: y.start, end: y.end)
                                found.insert([p, q])
                                found.insert([q, p])
                            }
                        }
                    }
                }
            }
        }
        return found
    }
}
