import GameCore

// Decision 468: a trace along a real line that meets track already laid on
// that line (the player's own, a bought line's, the demo's) takes it as
// laid: it skips that stretch, joins both of its ends, and traces on beyond
// it, rather than stopping in front of it as GameCore refuses track that
// close to other track. Track that crosses the way, or runs beside it
// farther off than a traced line keeps to its real line, is not the same
// line, and stops the trace as before.

/// The track already laid along a traced way: where it runs, and the nodes
/// a trace joins at either end.
struct TraceOverlap {
    /// One edge of the network, in plan.
    struct Edge {
        let id: TrackEdgeID
        let from: TrackNodeID
        let to: TrackNodeID
        /// Its centre line, from `from` to `to`.
        let points: [WorldVector]
    }

    /// A run of edges along the way, one after another: from `entry`, at
    /// `range.lowerBound` along the way, to `exit`, at its upper bound.
    struct Run: Equatable {
        let range: ClosedRange<Double>
        let entry: TrackNodeID
        let exit: TrackNodeID
        let edges: [TrackEdgeID]
        /// Its centre line from `entry` to `exit`.
        let points: [WorldVector]

        static func == (lhs: Run, rhs: Run) -> Bool {
            lhs.range == rhs.range && lhs.entry == rhs.entry && lhs.exit == rhs.exit && lhs.edges == rhs.edges
        }
    }

    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How far from the way every point of an edge lies for it to be on
    /// the same line: a traced edge keeps within 3 m of the real line's
    /// smoothed centre (decision 213), a double track's second 5 m beside.
    static let reach = 8 * metre
    /// How much of an edge's length runs along the way, at least: an edge
    /// crossing it, short enough to lie within reach, runs across it.
    static let along = 0.7
    /// How much of an edge lies along the way, at least.
    static let minimumLength = 10 * metre

    /// The runs of `edges` along `way`, in order along it, none overlapping
    /// another: where two run side by side (a double track), the longer,
    /// then the nearer the way's centre.
    static func runs(along way: WorldPath, edges: [Edge]) -> [Run] {
        guard way.points.count > 1 else { return [] }
        let xs = way.points.map(\.x), ys = way.points.map(\.y)
        let minX = (xs.min() ?? 0) - reach, maxX = (xs.max() ?? 0) + reach
        let minY = (ys.min() ?? 0) - reach, maxY = (ys.max() ?? 0) + reach

        // Each edge that follows the way, turned to run forward along it.
        struct Following {
            let id: TrackEdgeID
            let low: TrackNodeID, high: TrackNodeID
            let range: ClosedRange<Double>
            let points: [WorldVector]
            let away: Double
        }
        var following: [Following] = []
        let index = Index(way)
        for edge in edges where edge.points.count > 1 {
            guard edge.points.contains(where: { $0.x >= minX && $0.x <= maxX && $0.y >= minY && $0.y <= maxY }) else { continue }
            // Decision 521's fourth sequel: an edge no piece of the way comes
            // within reach of has no point within reach, so none along it.
            guard index.comesWithin(reach, of: edge.points) else { continue }
            // Every point within reach of the way, but those beyond either
            // end of it: an edge the trace starts or ends partway along.
            var places: [(along: Double, away: Double)?] = []
            var fits = true
            for point in edge.points {
                let place = index.nearest(point)
                if place.away <= reach {
                    places.append(place)
                } else if place.along <= 0 || place.along >= way.length {
                    places.append(nil)
                } else {
                    fits = false
                    break
                }
            }
            guard fits else { continue }
            var length = 0.0
            for (index, (a, b)) in zip(edge.points, edge.points.dropFirst()).enumerated() where places[index] != nil && places[index + 1] != nil {
                length += (b - a).length
            }
            let inside = places.compactMap { $0 }
            guard length >= minimumLength, let first = inside.first, let last = inside.last,
                  abs(last.along - first.along) >= along * length else { continue }
            let forward = first.along <= last.along
            following.append(Following(
                id: edge.id, low: forward ? edge.from : edge.to, high: forward ? edge.to : edge.from,
                range: min(first.along, last.along)...max(first.along, last.along),
                points: forward ? edge.points : edge.points.reversed(),
                away: inside.map(\.away).reduce(0, +) / Double(inside.count)
            ))
        }
        following.sort { $0.range.lowerBound < $1.range.lowerBound || ($0.range.lowerBound == $1.range.lowerBound && $0.id < $1.id) }

        // Edges joined end to end, forward along the way, into runs.
        var used = Set<TrackEdgeID>()
        var candidates: [(run: Run, away: Double)] = []
        for start in following where !used.contains(start.id) {
            used.insert(start.id)
            var chain = [start]
            while let next = following.first(where: { !used.contains($0.id) && $0.low == chain[chain.count - 1].high }) {
                used.insert(next.id)
                chain.append(next)
            }
            var points: [WorldVector] = []
            for part in chain { points += points.isEmpty ? part.points : Array(part.points.dropFirst()) }
            let run = Run(
                range: chain[0].range.lowerBound...(chain.map(\.range.upperBound).max() ?? chain[0].range.upperBound),
                entry: chain[0].low, exit: chain[chain.count - 1].high, edges: chain.map(\.id), points: points
            )
            candidates.append((run, chain.map(\.away).reduce(0, +) / Double(chain.count)))
        }

        // One run where several lie side by side.
        candidates.sort {
            let a = $0.run.range.upperBound - $0.run.range.lowerBound, b = $1.run.range.upperBound - $1.run.range.lowerBound
            return a != b ? a > b : $0.away < $1.away
        }
        var kept: [Run] = []
        for candidate in candidates where !kept.contains(where: { $0.range.overlaps(candidate.run.range) }) {
            kept.append(candidate.run)
        }
        return kept.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

extension TraceOverlap {
    /// Decision 521's fourth sequel: a traced way in pieces of
    /// ``Index/chunk`` segments, each with its box, so a point's nearest
    /// place on the way looks only at the pieces that can hold it. It
    /// gives what ``WorldPath/nearest(_:)`` gives, segment for segment:
    /// a long trace over a large network asked it of a thousand edges,
    /// each time of every 5 m of the way, and that was most of the
    /// preview's time.
    struct Index {
        static let chunk = 32
        let way: WorldPath
        /// For each piece, its first segment and the box its points lie in.
        let pieces: [(first: Int, minX: Double, minY: Double, maxX: Double, maxY: Double)]

        init(_ way: WorldPath) {
            self.way = way
            let segments = way.points.count - 1
            pieces = stride(from: 0, to: max(segments, 0), by: Self.chunk).map { first in
                let points = way.points[first...min(first + Self.chunk, segments)]
                let xs = points.map(\.x), ys = points.map(\.y)
                return (first, xs.min()!, ys.min()!, xs.max()!, ys.max()!)
            }
        }

        /// Whether some segment of the way may come within `reach` of some
        /// point of `points`: false only where none can.
        func comesWithin(_ reach: Double, of points: [WorldVector]) -> Bool {
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return false }
            // A unit (under 2 cm) over, against rounding.
            let reach = reach + 1
            return pieces.contains { piece in
                piece.minX <= maxX + reach && minX - reach <= piece.maxX && piece.minY <= maxY + reach && minY - reach <= piece.maxY
            }
        }

        /// ``WorldPath/nearest(_:)``: the same segments in the same order,
        /// passing over a piece whose box lies farther than the nearest
        /// found so far (by more than a unit, against rounding), as
        /// none of its segments could be nearer.
        func nearest(_ point: WorldVector) -> (along: Double, away: Double) {
            let points = way.points, distances = way.distances
            var best = (along: 0.0, away: Double.infinity)
            for piece in pieces {
                let dx = max(piece.minX - point.x, 0, point.x - piece.maxX)
                let dy = max(piece.minY - point.y, 0, point.y - piece.maxY)
                guard (dx * dx + dy * dy).squareRoot() - 1 <= best.away else { continue }
                for index in piece.first..<min(piece.first + Self.chunk, points.count - 1) {
                    let a = points[index], b = points[index + 1]
                    let along = b - a
                    let squared = along.dot(along)
                    let t = squared > 0 ? max(0, min(1, (point - a).dot(along) / squared)) : 0
                    let away = (a + along * t - point).length
                    if away < best.away {
                        best = (distances[index] + t * (distances[index + 1] - distances[index]), away)
                    }
                }
            }
            return best
        }
    }
}

extension TraceOverlap.Edge {
    /// The edges of `world`'s network that may follow `way`, in plan: an
    /// end within ``TraceOverlap/reach`` of its box (the other may lie
    /// beyond the way's end).
    static func near(_ way: WorldPath, in world: GameWorld) -> [TraceOverlap.Edge] {
        let reach = TraceOverlap.reach
        let xs = way.points.map(\.x), ys = way.points.map(\.y)
        let minX = (xs.min() ?? 0) - reach, maxX = (xs.max() ?? 0) + reach
        let minY = (ys.min() ?? 0) - reach, maxY = (ys.max() ?? 0) + reach
        func inside(_ node: TrackNodeID) -> Bool {
            guard let position = world.network.node(node)?.position else { return false }
            let x = Double(position.x), y = Double(position.y)
            return x >= minX && x <= maxX && y >= minY && y <= maxY
        }
        return world.network.edges.compactMap { edge in
            guard inside(edge.from) || inside(edge.to), let geometry = world.trackGeometry(of: edge.id) else { return nil }
            return TraceOverlap.Edge(id: edge.id, from: edge.from, to: edge.to, points: geometry.points.map { WorldVector($0.plan) })
        }
    }
}

extension GameSession {
    /// The traced stretch from `start` to `end` (decision 213), taking the
    /// track already laid along the way as laid (decision 468): the way in
    /// pieces between that track, each traced as ``tracePlan(from:to:along:platforms:onGround:system:)``
    /// traces one, the first from `start`, each after a piece of laid track
    /// from that track's far node, the last to `end`; together one chain of
    /// stretches, stopping where GameCore refuses one. Where no track lies
    /// along the way, as ``tracePlan(from:to:along:platforms:onGround:system:)``.
    func traceAlong(from start: NetworkAnchor, to end: NetworkAnchor) -> TracePlan? {
        let reach = Self.traceReach(NetworkBuilding.minimumSpacing * 2)
        guard tracesRealRailway, let from = world.position(of: start, height: networkHeight),
              let to = world.position(of: end, height: networkHeight),
              let way = tracedWay(from: from, to: to, reach: reach) else { return tracePlan(from: start, to: end) }
        let raw = WorldPath(way)
        guard raw.points.count > 1 else { return tracePlan(from: start, to: end) }
        let smooth = raw.smoothed()
        let runs = TraceOverlap.runs(along: smooth, edges: TraceOverlap.Edge.near(smooth, in: world))
        guard !runs.isEmpty else { return tracePlan(from: start, to: end) }

        let shortest = Double(NetworkBuilding.minimumSpacing)
        var stretches: [PlayerCommand.TrackStretch] = []
        var buildable = 0
        var problem: String?
        var existing: [(after: Int, points: [WorldCoordinate])] = []
        var refusedWay: [WorldCoordinate] = []
        var cursor = (anchor: start, point: WorldVector(from.plan), along: 0.0, fromRun: false)
        // Decision 521's fourth sequel: each piece built on the copy the
        // pieces before it were built on, so the whole chain is built once,
        // as the command builds it, and the preview prices that copy.
        var built: GameWorld? = world.trackPreviewCopy()
        var builtEdges: [TrackEdgeID] = []

        // One piece of the way, traced; false where it stops the trace.
        func trace(to anchor: NetworkAnchor, at point: WorldVector) -> Bool {
            let a = raw.nearest(cursor.point).along, b = raw.nearest(point).along
            let given = [cursor.point] + (a < b ? raw.points(from: a, to: b) : []) + [point]
            guard let piece = tracePlan(from: cursor.anchor, to: anchor, along: given, buildingOn: built) else {
                problem = language.text("This stretch cannot be traced.", "這段無法描線。")
                return false
            }
            built = piece.built
            builtEdges += piece.builtEdges
            buildable = stretches.count + piece.buildable
            stretches += piece.stretches
            if piece.stopped || piece.stretches.isEmpty {
                refusedWay = piece.refusedWay
                problem = piece.problem ?? language.text("This stretch cannot be traced.", "這段無法描線。")
                return false
            }
            return true
        }

        var reached = true
        for run in runs {
            guard let entry = world.network.node(run.entry)?.position, let exit = world.network.node(run.exit)?.position else { continue }
            if run.range.lowerBound - cursor.along >= shortest {
                guard trace(to: .node(run.entry), at: WorldVector(entry.plan)) else {
                    reached = false
                    break
                }
            } else if cursor.fromRun, case .node(let node) = cursor.anchor, node != run.entry {
                // Two pieces of laid track too close together to lay track
                // between them.
                problem = language.text(
                    "The track already laid here leaves too short a gap to join.",
                    "這裡已經鋪好的軌道之間空隙太短，接不起來。"
                )
                reached = false
                break
            }
            existing.append((stretches.count, run.points.map { WorldCoordinate(x: Int64($0.x.rounded()), y: Int64($0.y.rounded()), z: 0) }))
            cursor = (.node(run.exit), WorldVector(exit.plan), run.range.upperBound, true)
        }
        var endNode: TrackNodeID?
        if reached {
            if smooth.length - cursor.along >= shortest {
                if !trace(to: end, at: WorldVector(to.plan)) { reached = false }
            } else if case .node(let node) = cursor.anchor {
                endNode = node
            }
        }
        if stretches.isEmpty, problem == nil {
            problem = language.text("Track is already laid all along here.", "這段已經有軌道了。")
        }
        guard !stretches.isEmpty else {
            var refused = TracePlan(stretches: [], buildable: 0, problem: problem)
            refused.refusedWay = refusedWay
            return refused
        }
        var plan = TracePlan(stretches: stretches, buildable: buildable, problem: reached ? nil : problem)
        plan.existing = existing.filter { $0.after <= buildable }
        plan.existingLength = plan.existing.reduce(0) { total, run in
            total + zip(run.points, run.points.dropFirst()).reduce(0) { $0 + (WorldVector($1.1.plan) - WorldVector($1.0.plan)).length }
        }
        plan.endNode = reached ? endNode : nil
        plan.stopsAfter = !reached && buildable == stretches.count
        plan.built = built
        plan.builtEdges = built == nil ? [] : builtEdges
        return plan
    }
}
