// Track geometry (Phase 4.5 Stage S3, ARCHITECTURE decision 29). An edge of
// the track network is shaped in plan by a TrackCurve between its two end
// nodes. Everything else, the sampled centre line, the length and where a
// distance along the edge lies, is derived from those integers by the fixed
// rules below, so every platform and every port gets the same numbers. The
// derived values are never saved: only the end nodes and the curve are.

/// The shape of an edge seen from above, between its two end nodes.
///
/// The shape is in plan only: a curve never moves the track up or down.
public enum TrackCurve: Hashable, Sendable {
    /// A straight line from one end to the other.
    case straight
    /// A cubic Bézier curve from the `from` node to the `to` node, pulled
    /// by two control points: the first sets the way the track leaves the
    /// `from` node, the second the way it arrives at the `to` node. One
    /// curve can bend one way and then the other (an S-curve).
    case cubic(PlanPoint, PlanPoint)
}

extension TrackCurve {
    /// The control points of the curve: none for a straight edge.
    var controlPoints: [PlanPoint] {
        switch self {
        case .straight: []
        case .cubic(let control1, let control2): [control1, control2]
        }
    }
}

/// A point on the track and the way the track runs there, seen from above.
public struct TrackLocation: Hashable, Sendable {
    public let position: WorldCoordinate
    /// The way along the track, not normalised (see ``PlanVector``).
    public let direction: PlanVector

    public init(position: WorldCoordinate, direction: PlanVector) {
        self.position = position
        self.direction = direction
    }
}

/// The centre line of an edge: sampled points from its `from` node to its
/// `to` node, with the distance along the line to each.
///
/// Derived from the end nodes and the ``TrackCurve`` by exact integer rules
/// (see ``init(from:to:curve:)``). An edge never changes once built and its
/// ID is never reused, so a renderer can keep an edge's geometry for as
/// long as the edge exists.
public struct TrackGeometry: Hashable, Sendable {
    /// The sampled centre line: the `from` node first, the `to` node last,
    /// no two neighbours equal.
    public let points: [WorldCoordinate]
    /// The distance along the line to each point, in world units: 0 first,
    /// the edge's length last, strictly increasing.
    public let distances: [Int64]
    /// The way the track leaves the `from` node, along the edge.
    public let startDirection: PlanVector
    /// The way the track leaves the `to` node, back along the edge.
    public let endDirection: PlanVector

    /// The length of the edge: the length of the sampled centre line,
    /// measured in plan (horizontal chainage). This is the distance a train
    /// travels along the edge.
    public var length: Int64 {
        distances[distances.count - 1]
    }

    /// The smallest and largest number of pieces a curve is sampled into,
    /// and the longest a piece should be: a curve is sampled into the
    /// fewest pieces, a power of two between the bounds, that keeps each
    /// piece of its control polygon at most ``sampleSpacing`` long.
    static let minimumSamples: Int64 = 8
    static let maximumSamples: Int64 = 1024
    static let sampleSpacing: Int64 = 64

    /// The centre line of an edge from `start` to `end` shaped by `curve`,
    /// or `nil` if that is not an edge a train can run along.
    ///
    /// - A straight edge is the two end points; its length is
    ///   `round(√(dx² + dy²))`.
    /// - A cubic edge with control points `c1`, `c2` is sampled at
    ///   `t = i / N` for `i` in `0...N`: the exact value of
    ///   `(N−i)³·p0 + 3(N−i)²i·c1 + 3(N−i)i²·c2 + i³·p3`, divided by `N³`
    ///   and rounded to the nearest unit, halves up. `N` is the smallest
    ///   power of two from 8 to 1024 with `64 N` at least the length of the
    ///   control polygon (the sum of `|c1 − p0|`, `|c2 − c1|` and
    ///   `|p3 − c2|`, each rounded). Repeated points are dropped, and the
    ///   length is the sum of each piece's `round(√(dx² + dy²))`.
    ///
    /// Returns `nil` when a point lies beyond ``WorldCoordinate/limit``,
    /// the ends are at different heights (every edge is level until Stage
    /// S4) or at the same place in plan, a control point sits on its end
    /// (the curve would leave that end in no direction), or the sampled
    /// line doubles back on itself (a cusp: consecutive pieces at 90° or
    /// more).
    public init?(from start: WorldCoordinate, to end: WorldCoordinate, curve: TrackCurve) {
        guard start.isWithinLimits, end.isWithinLimits, start.z == end.z, start.plan != end.plan else { return nil }
        let p0 = start.plan
        let p3 = end.plan
        var plan: [PlanPoint]
        switch curve {
        case .straight:
            plan = [p0, p3]
            startDirection = p3.vector(from: p0)
            endDirection = p0.vector(from: p3)
        case .cubic(let c1, let c2):
            guard c1.isWithinLimits, c2.isWithinLimits, c1 != p0, c2 != p3 else { return nil }
            plan = Self.samples(p0, c1, c2, p3)
            startDirection = c1.vector(from: p0)
            endDirection = c2.vector(from: p3)
        }
        var distances: [Int64] = [0]
        distances.reserveCapacity(plan.count)
        for index in plan.indices.dropFirst() {
            let piece = plan[index].vector(from: plan[index - 1])
            if index >= 2, piece.dot(plan[index - 1].vector(from: plan[index - 2])) <= 0 {
                return nil
            }
            distances.append(distances[index - 1] + piece.length)
        }
        self.points = plan.map { WorldCoordinate(x: $0.x, y: $0.y, z: start.z) }
        self.distances = distances
    }

    /// The sampled points of the cubic curve `p0`, `c1`, `c2`, `p3` (see
    /// ``init(from:to:curve:)``), with repeated neighbours dropped.
    ///
    /// Every point is within ``WorldCoordinate/limit`` and `N³ ≤ 2^30`, so
    /// each weighted sum is at most 2^59 in magnitude.
    private static func samples(_ p0: PlanPoint, _ c1: PlanPoint, _ c2: PlanPoint, _ p3: PlanPoint) -> [PlanPoint] {
        let polygon = c1.vector(from: p0).length + c2.vector(from: c1).length + p3.vector(from: c2).length
        var count = minimumSamples
        var shift = 9 // 3 × log2(count)
        while count < maximumSamples, count * sampleSpacing < polygon {
            count *= 2
            shift += 3
        }
        var points: [PlanPoint] = [p0]
        points.reserveCapacity(Int(count) + 1)
        for step in 1...count {
            let rest = count - step
            let w0 = rest * rest * rest
            let w1 = 3 * rest * rest * step
            let w2 = 3 * rest * step * step
            let w3 = step * step * step
            let point = PlanPoint(
                x: FixedPoint.roundedShift(w0 * p0.x + w1 * c1.x + w2 * c2.x + w3 * p3.x, by: shift),
                y: FixedPoint.roundedShift(w0 * p0.y + w1 * c1.y + w2 * c2.y + w3 * p3.y, by: shift)
            )
            if point != points[points.count - 1] {
                points.append(point)
            }
        }
        return points
    }

    /// Where the point `distance` along the edge from its `from` node lies,
    /// and the way the edge runs there (from `from` toward `to`).
    ///
    /// The point lies on the sampled line: between two samples it is
    /// interpolated along the piece, rounded to the nearest unit, halves up.
    /// At a sample the way is that of the piece after it (at the `to` node,
    /// the last piece). Binary search: O(log n) in the number of samples.
    ///
    /// - Precondition: `0 <= distance <= length`.
    public func location(at distance: Int64) -> TrackLocation {
        precondition(distance >= 0 && distance <= length, "location(at:) needs a distance along the edge")
        var low = 0
        var high = distances.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if distances[middle] <= distance {
                low = middle
            } else {
                high = middle - 1
            }
        }
        let a = points[low]
        let b = points[low + 1]
        let piece = distances[low + 1] - distances[low]
        let along = distance - distances[low]
        let position = WorldCoordinate(
            x: a.x + FixedPoint.roundedDivision((b.x - a.x) * along, by: piece),
            y: a.y + FixedPoint.roundedDivision((b.y - a.y) * along, by: piece),
            z: a.z
        )
        return TrackLocation(position: position, direction: b.plan.vector(from: a.plan))
    }

    /// Where the point `distance` along a traversal of the edge lies, and
    /// the way a train on it faces: measured from the `from` node going
    /// ``TrackEdgeDirection/forward``, from the `to` node going
    /// ``TrackEdgeDirection/backward``.
    ///
    /// - Precondition: `0 <= distance <= length`.
    public func location(at distance: Int64, going direction: TrackEdgeDirection) -> TrackLocation {
        switch direction {
        case .forward:
            return location(at: distance)
        case .backward:
            let location = location(at: length - distance)
            return TrackLocation(position: location.position, direction: location.direction.reversed)
        }
    }
}

// MARK: - Codable

extension TrackCurve: Codable {
    private enum CodingKeys: String, CodingKey {
        case straight, cubic
    }

    private enum CubicKeys: String, CodingKey {
        case control1, control2
    }

    /// Decodes `{"straight": {}}` or `{"cubic": {"control1", "control2"}}`:
    /// exactly one of the two keys. Whether the curve makes an edge is
    /// checked with its end nodes (see ``TrackGeometry/init(from:to:curve:)``).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A curve is exactly one of straight or cubic.")
            )
        }
        switch key {
        case .straight:
            _ = try container.nestedContainer(keyedBy: CubicKeys.self, forKey: .straight)
            self = .straight
        case .cubic:
            let cubic = try container.nestedContainer(keyedBy: CubicKeys.self, forKey: .cubic)
            self = .cubic(try cubic.decode(PlanPoint.self, forKey: .control1), try cubic.decode(PlanPoint.self, forKey: .control2))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .straight:
            _ = container.nestedContainer(keyedBy: CubicKeys.self, forKey: .straight)
        case .cubic(let control1, let control2):
            var cubic = container.nestedContainer(keyedBy: CubicKeys.self, forKey: .cubic)
            try cubic.encode(control1, forKey: .control1)
            try cubic.encode(control2, forKey: .control2)
        }
    }
}
