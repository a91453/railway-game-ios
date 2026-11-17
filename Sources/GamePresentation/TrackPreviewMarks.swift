import GameCore

// Decision 826: while the network tool previews a stretch of track, the
// stretches its curves slow a train are coloured by how slow (NEXT_PRIORITIES
// §29.16, TRACK-CURVE-COLOUR), and the tightest curve and steepest grade are
// marked where they are. The limits are GameCore's own (decision 217,
// ``CurveSpeedLimit/limits(from:to:curve:length:)``, the very limits the
// edge gets when it is built); this file only sorts them into bands and
// finds where to put the marks. The owner's references have no coloured
// preview (MapBuilder and `Simulator/` checked again for this decision;
// `Ci/` `radiusAtPoint` is already ``TrackCurvature``): the project's own.

/// How much a curve of the previewed stretch slows a train, for its colour;
/// none at all for track run at 120 km/h or more.
public enum TrackSpeedBand: Hashable, Sendable, CaseIterable {
    /// Held to 70–115 km/h.
    case reduced
    /// Held under 70 km/h.
    case slow

    /// A limit below this colours the track: 120 km/h, a radius of some
    /// 800 m, about what Taiwan Railway's main lines are built to.
    public static let reducedBelow: Int64 = 120
    /// A limit below this is ``slow``: 70 km/h, a radius under some 250 m,
    /// a metro's or a branch line's curve.
    public static let slowBelow: Int64 = 70

    /// The band of a limit of `speed` km/h; `nil` for none or a fast one.
    public init?(speed: Int64?) {
        guard let speed, speed < Self.reducedBelow else { return nil }
        self = speed < Self.slowBelow ? .slow : .reduced
    }
}

/// What the preview of a stretch marks on the map besides its centre line.
public struct TrackPreviewMarks: Hashable, Sendable {
    /// A stretch GameCore's curve limit slows below ``TrackSpeedBand/reducedBelow``.
    public struct Stretch: Hashable, Sendable {
        public let points: [WorldCoordinate]
        /// km/h.
        public let speed: Int64
        public let band: TrackSpeedBand
    }

    /// The tightest point of a curve that slows a train (or would, with
    /// the curve limits on).
    public struct Tightest: Hashable, Sendable {
        public let position: WorldCoordinate
        /// World units.
        public let radius: Double
        /// GameCore's limit there, km/h; `nil` with the curve limits off.
        public let speed: Int64?

        public var band: TrackSpeedBand? { TrackSpeedBand(speed: speed) }

        /// "Radius 320 m · 75 km/h", or just the radius.
        public func text(in language: DisplayLanguage) -> String {
            let radius = TrackCurvature.radiusText(radius, in: language)
            guard let speed else { return radius }
            return "\(radius) · \(speed) km/h"
        }
    }

    /// Where a stretch that climbs or falls is steepest.
    public struct Steepest: Hashable, Sendable {
        public let position: WorldCoordinate
        /// Whole per mille, at least 1.
        public let perMille: Int64
        /// Steeper than track may be laid (``TrackProfile/maximumGrade``).
        public let tooSteep: Bool

        /// "Steepest 27‰".
        public func text(in language: DisplayLanguage) -> String {
            language.text("Steepest \(perMille)‰", "最陡 \(perMille)‰")
        }
    }

    public var stretches: [Stretch] = []
    public var tightest: Tightest?
    public var steepest: Steepest?
    /// GameCore's lowest curve limit along the stretch, km/h; `nil` when it
    /// has none or the curve limits are off.
    public var lowestSpeed: Int64?

    public init() {}

    /// The marks of `preview`; none for a traced stretch, which is many
    /// edges (decision 213), or one that makes no edge.
    public init(_ preview: NetworkPreview, curveSpeedLimits: Bool) {
        guard preview.traced == nil, let first = preview.points.first, let last = preview.points.last,
              let geometry = TrackGeometry(from: first, to: last, curve: preview.curve, profile: preview.profile)
        else { return }
        let length = geometry.length
        let limits = curveSpeedLimits
            ? CurveSpeedLimit.limits(from: first.plan, to: last.plan, curve: preview.curve, length: length)
            : []
        lowestSpeed = limits.map(\.speed).min()
        for limit in limits {
            let start = max(0, limit.start), end = min(length, limit.end)
            guard start < end, let band = TrackSpeedBand(speed: limit.speed) else { continue }
            stretches.append(Stretch(points: geometry.points(from: start, to: end), speed: limit.speed, band: band))
        }
        if let (radius, t) = TrackCurvature.tightestPoint(from: first.plan, to: last.plan, curve: preview.curve) {
            let metres = Int64(radius / Double(WorldCoordinate.unitsPerMetre))
            // Marked where a curve slows a train: a gentler one is noise.
            if TrackSpeedBand(speed: CurveSpeedLimit.speed(radiusMetres: metres)) != nil {
                let point = TrackCurvature.point(at: t, from: first.plan, to: last.plan, curve: preview.curve)
                let index = Self.nearest(to: point, in: geometry.points)
                let along = geometry.distances[index]
                let speed = limits.first { $0.start <= along && along <= $0.end }?.speed
                tightest = Tightest(position: geometry.points[index], radius: radius, speed: speed)
            }
        }
        let grade = geometry.steepestGrade
        if grade.rise != 0 {
            let perMille = max(1, (abs(grade.rise) * 1_000 + grade.run / 2) / grade.run)
            // The middle of the steady grade, between any transitions.
            let steady = geometry.segments.first { $0.kind == .up || $0.kind == .down }
            let middle = steady.map { ($0.start + $0.end) / 2 } ?? length / 2
            steepest = Steepest(
                position: geometry.location(at: middle).position, perMille: perMille,
                tooSteep: !grade.isNoSteeper(than: TrackProfile.maximumGrade)
            )
        }
    }

    /// The index of the point of `points` nearest `point` in plan.
    static func nearest(to point: (x: Double, y: Double), in points: [WorldCoordinate]) -> Int {
        var best = (index: 0, distance: Double.infinity)
        for (index, candidate) in points.enumerated() {
            let dx = Double(candidate.x) - point.x, dy = Double(candidate.y) - point.y
            let squared = dx * dx + dy * dy
            if squared < best.distance { best = (index, squared) }
        }
        return best.index
    }
}

extension TrackCurvature {
    /// The least radius of the edge from `start` to `end` along `curve`
    /// (``tightestRadius(from:to:curve:)``) and the `t` of the cubic where
    /// it is; `nil` for a straight edge or one beyond ``straightRadius``.
    public static func tightestPoint(from start: PlanPoint, to end: PlanPoint, curve: TrackCurve) -> (radius: Double, t: Double)? {
        guard case .cubic(let c1, let c2) = curve else { return nil }
        let p = [start, c1, c2, end].map { (x: Double($0.x), y: Double($0.y)) }
        var tightest = (radius: Double.infinity, t: 0.0)
        for step in 0...steps {
            let t = Double(step) / Double(steps), u = 1 - t
            // B'(t) and B''(t) of the cubic.
            let d1x = 3 * (u * u * (p[1].x - p[0].x) + 2 * u * t * (p[2].x - p[1].x) + t * t * (p[3].x - p[2].x))
            let d1y = 3 * (u * u * (p[1].y - p[0].y) + 2 * u * t * (p[2].y - p[1].y) + t * t * (p[3].y - p[2].y))
            let d2x = 6 * (u * (p[2].x - 2 * p[1].x + p[0].x) + t * (p[3].x - 2 * p[2].x + p[1].x))
            let d2y = 6 * (u * (p[2].y - 2 * p[1].y + p[0].y) + t * (p[3].y - 2 * p[2].y + p[1].y))
            let cross = abs(d1x * d2y - d1y * d2x)
            let speed = (d1x * d1x + d1y * d1y).squareRoot()
            guard cross > 0, speed > 0 else { continue }
            let radius = speed * speed * speed / cross
            if radius < tightest.radius { tightest = (radius, t) }
        }
        return tightest.radius <= straightRadius ? tightest : nil
    }

    /// The point `t` along the edge from `start` to `end` shaped by `curve`.
    static func point(at t: Double, from start: PlanPoint, to end: PlanPoint, curve: TrackCurve) -> (x: Double, y: Double) {
        let (x0, y0, x3, y3) = (Double(start.x), Double(start.y), Double(end.x), Double(end.y))
        guard case .cubic(let c1, let c2) = curve else { return (x0 + (x3 - x0) * t, y0 + (y3 - y0) * t) }
        let u = 1 - t
        let (w0, w1, w2, w3) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
        return (w0 * x0 + w1 * Double(c1.x) + w2 * Double(c2.x) + w3 * x3,
                w0 * y0 + w1 * Double(c1.y) + w2 * Double(c2.y) + w3 * y3)
    }
}
