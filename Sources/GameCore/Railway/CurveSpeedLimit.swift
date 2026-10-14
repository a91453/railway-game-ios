// Curve speed limits (ARCHITECTURE decision 217): how fast a train may run
// round a curve of the track, from the curve's radius. A train in a curve
// leans out; the track's cant (superelevation) and the cant deficiency the
// passengers accept balance it up to V = √(127·R·(C + Cd) ÷ G) km/h, with R
// the radius in metres, C and Cd in millimetres and G the distance between
// the rails' centres. Taiwan Railway's narrow gauge (G 1120 mm, C at most
// 105 mm, Cd about 65 mm) gives V ≈ 4.4√R, and the high-speed line's
// standard gauge (G 1500 mm, C 180 mm, Cd 65 mm) about 4.6√R: one rule,
// ``kmhSquaredPerMetre``, serves both. The owner's references have no curve
// rule (the Railway reference's `SPEED_ZONES` are measured stretches of
// real lines, the metro game's `MIN_CURVE_RADIUS_M` only a drawing check),
// so the rule is this project's, from the formula above.
//
// An edge's limits are worked out once, from its end nodes and its cubic,
// when it is built or loaded (``TrackEdge/speedLimits``), never saved:
// the curvature is read exactly from the cubic at 65 steps, as the drawing
// loupe reads it (decision 204), but in integers.

/// A stretch of an edge, or of a run, a train may not pass faster than
/// ``speed`` km/h (decision 217).
public struct TrackSpeedLimit: Hashable, Sendable {
    /// World units from the edge's `from` node (or from a run's start) to
    /// where the limit begins and to where it ends: `start < end`.
    public let start: Int64
    public let end: Int64
    /// km/h, a multiple of ``CurveSpeedLimit/step``.
    public let speed: Int64

    public init(start: Int64, end: Int64, speed: Int64) {
        self.start = start
        self.end = end
        self.speed = speed
    }
}

/// Saved as `{"start", "end", "speed"}`.
extension TrackSpeedLimit: Codable {}

/// The curve speed rule (decision 217).
public enum CurveSpeedLimit {
    /// V² ÷ R, in km/h² per metre of radius, × 100: 19.4, so V = 4.4√R
    /// (radius 300 m: 75 km/h; 600 m: 105; 1000 m: 135; 4600 m: 295).
    public static let kmhSquaredPerMetre: Int64 = 1940
    /// Limits are posted in steps of 5 km/h, rounded down, as real lines
    /// post them.
    public static let step: Int64 = 5
    /// No limit is lower than this, however tight the curve: a train
    /// creeps round it.
    public static let lowest: Int64 = 15
    /// A curve gentler than this (km/h) has no limit: no train runs faster.
    public static let highest: Int64 = 400
    /// How many steps along a cubic its curvature is read at.
    static let steps: Int64 = 64
    /// How many stretches an edge is posted in.
    static let stretches: Int64 = 8

    /// The limit, in km/h, for a curve of radius `metres`, or `nil` when it
    /// is at least ``highest``.
    public static func speed(radiusMetres metres: Int64) -> Int64? {
        guard metres <= highest * highest else { return nil }
        return speed(squared: max(0, metres) * kmhSquaredPerMetre / 100)
    }

    /// The posted limit for a balancing speed whose square is `squared`.
    static func speed(squared: Int64) -> Int64? {
        let raw = FixedPoint.squareRoot(squared)
        guard raw < highest else { return nil }
        return max(lowest, raw / step * step)
    }

    /// The limits along an edge from `start` to `end` shaped by `curve`,
    /// `length` long (its ``TrackGeometry/length``), from its `start` end,
    /// in order, apart and none at the same speed as the next it touches.
    /// Empty for a straight edge.
    ///
    /// The curvature is read at `t = i ÷ 64`. The edge is posted in
    /// ``stretches`` stretches of eight steps, as a real line posts one
    /// limit over a stretch rather than one for every few metres: each
    /// takes the lowest limit at its nine steps. Where a step lies along the
    /// edge is its share of the chords between the exact points at the
    /// steps.
    public static func limits(from start: PlanPoint, to end: PlanPoint, curve: TrackCurve, length: Int64) -> [TrackSpeedLimit] {
        guard case .cubic(let c1, let c2) = curve, length > 0 else { return [] }
        let a = c1.vector(from: start), b = c2.vector(from: c1), c = end.vector(from: c2)
        let n = steps
        let speeds = (0...n).map { i in speed(at: i, a: a, b: b, c: c) }
        guard speeds.contains(where: { $0 != nil }) else { return [] }
        // The exact points at the steps, rounded, and the chords between.
        var reached: [Int64] = [0]
        var previous = start
        for i in 1...n {
            let rest = n - i
            let w0 = rest * rest * rest, w1 = 3 * rest * rest * i, w2 = 3 * rest * i * i, w3 = i * i * i
            let point = PlanPoint(
                x: FixedPoint.roundedShift(w0 * start.x + w1 * c1.x + w2 * c2.x + w3 * end.x, by: 18),
                y: FixedPoint.roundedShift(w0 * start.y + w1 * c1.y + w2 * c2.y + w3 * end.y, by: 18)
            )
            reached.append(reached[reached.count - 1] + point.vector(from: previous).length)
            previous = point
        }
        let chords = reached[reached.count - 1]
        guard chords > 0 else { return [] }
        let along = reached.map { WideInteger.product($0, length).dividedRoundingDown(by: chords).int64 }
        var limits: [TrackSpeedLimit] = []
        let group = Int(n / stretches)
        for first in stride(from: 0, to: Int(n), by: group) {
            let last = first + group
            guard let speed = speeds[first...last].compactMap({ $0 }).min(), along[first] < along[last] else { continue }
            if let previous = limits.last, previous.end == along[first], previous.speed == speed {
                limits[limits.count - 1] = TrackSpeedLimit(start: previous.start, end: along[last], speed: speed)
            } else {
                limits.append(TrackSpeedLimit(start: along[first], end: along[last], speed: speed))
            }
        }
        return limits
    }

    /// The limit at step `i` of the cubic whose control polygon's pieces
    /// are `a`, `b` and `c`, or `nil` where it is straight or gentle.
    ///
    /// With `M = 64`, `D1 = (M−i)²a + 2(M−i)i·b + i²c` (B′ × M² ÷ 3) and
    /// `D2 = (M−i)(b − a) + i(c − b)` (B″ × M ÷ 6), the radius is
    /// `|B′|³ ÷ |B′ × B″| = 3|D1|³ ÷ (2M³·|D1 × D2|)`. Both are scaled down
    /// to 24 bits a component first (control points within 2^29 make D1 at
    /// most 2^42 and D2 2^37), keeping seven figures, and the scales are put
    /// back as powers of two.
    static func speed(at i: Int64, a: PlanVector, b: PlanVector, c: PlanVector) -> Int64? {
        let n = steps
        let rest = n - i
        let d1 = PlanVector(dx: rest * rest * a.dx + 2 * rest * i * b.dx + i * i * c.dx,
                            dy: rest * rest * a.dy + 2 * rest * i * b.dy + i * i * c.dy)
        let d2 = PlanVector(dx: rest * (b.dx - a.dx) + i * (c.dx - b.dx), dy: rest * (b.dy - a.dy) + i * (c.dy - b.dy))
        let (first, shift1) = scaledDown(d1)
        let (second, shift2) = scaledDown(d2)
        let cross = abs(first.cross(second))
        let squared = first.dx * first.dx + first.dy * first.dy
        guard cross > 0, squared > 0 else { return nil }
        // R (world units) = 3·|D1′|³·2^(2·shift1) ÷ |X′| ÷ (2M³·2^shift2),
        // and V² = R ÷ 64 × kmhSquaredPerMetre ÷ 100.
        let cubed = WideInteger.product(squared, Int64(WideInteger(squared).squareRoot()))
        var numerator = cubed.multiplied(by: 3 * kmhSquaredPerMetre)
        // Beyond the highest limit there is nothing to work out (and the
        // shifts below could overflow).
        let ceiling = WideInteger.product(highest * highest, Int64(cross))
            .multiplied(by: 2 * n * n * n * 64 * 100)
        var exponent = 2 * shift1 - shift2
        while exponent > 0 {
            numerator = numerator.shiftedLeft(by: 1)
            exponent -= 1
            if ceiling < numerator { return nil }
        }
        let squaredSpeed = numerator.dividedRoundingDown(by: Int64(cross))
            .dividedRoundingDown(by: 2 * n * n * n * 64 * 100)
            .shiftedRight(by: Int(min(63, -exponent)))
        guard squaredSpeed < WideInteger(highest * highest) else { return nil }
        return speed(squared: squaredSpeed.int64)
    }

    /// `vector` halved until both components are within 2^24, and how many
    /// times it was.
    private static func scaledDown(_ vector: PlanVector) -> (PlanVector, Int64) {
        var (dx, dy, shift) = (vector.dx, vector.dy, Int64(0))
        while abs(dx) > 1 << 24 || abs(dy) > 1 << 24 {
            dx /= 2
            dy /= 2
            shift += 1
        }
        return (PlanVector(dx: dx, dy: dy), shift)
    }
}

extension CurveSpeedLimit {
    /// The limits of an edge with centre line `geometry`, shaped by `curve`.
    static func limits(of geometry: TrackGeometry, curve: TrackCurve) -> [TrackSpeedLimit] {
        limits(from: geometry.points[0].plan, to: geometry.points[geometry.points.count - 1].plan, curve: curve, length: geometry.length)
    }
}

extension TrackEdge {
    /// ``speedLimits`` as a traversal of the edge going `direction` meets
    /// them, measured from where it starts.
    func speedLimits(going direction: TrackEdgeDirection) -> [TrackSpeedLimit] {
        switch direction {
        case .forward:
            return speedLimits
        case .backward:
            return speedLimits.reversed().map { TrackSpeedLimit(start: length - $0.end, end: length - $0.start, speed: $0.speed) }
        }
    }
}

extension CurveSpeedLimit {
    /// `limits` clipped to `0...length` and made apart: each stretch with
    /// the lowest of the limits over it, in order, neighbours that touch at
    /// the same speed joined. A sweep over the limits by their starts.
    public static func merged(_ limits: [TrackSpeedLimit], within length: Int64) -> [TrackSpeedLimit] {
        let kept = limits.compactMap { limit -> TrackSpeedLimit? in
            let start = max(0, limit.start), end = min(length, limit.end)
            return start < end && limit.speed >= 1 ? TrackSpeedLimit(start: start, end: end, speed: limit.speed) : nil
        }.sorted { $0.start < $1.start }
        guard !kept.isEmpty else { return [] }
        var cuts: [Int64] = []
        cuts.reserveCapacity(2 * kept.count)
        for limit in kept {
            cuts.append(limit.start)
            cuts.append(limit.end)
        }
        cuts.sort()
        // Every end is a cut, so a limit begun by a piece's start and not
        // ended by it covers the whole piece.
        var merged: [TrackSpeedLimit] = []
        var active: [TrackSpeedLimit] = []
        var next = 0
        var start = cuts[0]
        for end in cuts.dropFirst() where end > start {
            while next < kept.count, kept[next].start <= start {
                active.append(kept[next])
                next += 1
            }
            active.removeAll { $0.end <= start }
            if let speed = active.map(\.speed).min() {
                if let last = merged.last, last.end == start, last.speed == speed {
                    merged[merged.count - 1] = TrackSpeedLimit(start: last.start, end: end, speed: speed)
                } else {
                    merged.append(TrackSpeedLimit(start: start, end: end, speed: speed))
                }
            }
            start = end
        }
        return merged
    }
}

extension RailwayNetwork {
    /// The curve speed limits a run meets (decision 217), measured from its
    /// start, within `0...distance`: its head sets off `offset` along
    /// `first` and goes on through `rest`, `distance` in all. Each holds
    /// `trailing` farther, until the train's tail has left the curve; a
    /// curve behind the head when it sets off is not counted. Only those
    /// below `topSpeed`, the others change nothing. Merged (see
    /// ``CurveSpeedLimit/merged(_:within:)``): in order and apart.
    func speedLimits(from first: TrackTraversal, offset: Int64, through rest: [TrackTraversal], distance: Int64,
                     trailing: Int64, below topSpeed: Int64 = .max) -> [TrackSpeedLimit] {
        var limits: [TrackSpeedLimit] = []
        var reached = -offset
        for traversal in [first] + rest {
            guard reached < distance, let edge = edge(traversal.edge) else { break }
            for limit in edge.speedLimits(going: traversal.direction) where limit.speed < topSpeed {
                let start = max(0, reached + limit.start)
                let end = min(distance, reached + limit.end + max(0, trailing))
                if start < end {
                    limits.append(TrackSpeedLimit(start: start, end: end, speed: limit.speed))
                }
            }
            reached += edge.length
        }
        return CurveSpeedLimit.merged(limits, within: distance)
    }
}
