import GameCore

// While a finger draws track (decision 102), a magnifier shows the map
// under it a few times closer, and the stretch's tightest radius
// (decision 204, NEXT_PRIORITIES §4 item 1). The reference checks a drawn
// route's radius at each vertex from the circle through it and its
// neighbours (`Ci/` `radiusAtPoint`, Heron's formula, `minRadiusForSegment`
// the least along a segment); an edge here is one cubic, so its radius is
// worked out from the cubic itself, exactly, rather than from rounded
// sample points. The reference has no magnifier: native.

/// How tightly a stretch of track turns.
public enum TrackCurvature {
    /// How many steps along a cubic its curvature is read at.
    static let steps = 64

    /// The least radius of the edge from `start` to `end` along `curve`, in
    /// world units: `nil` for a straight edge, or one too nearly straight
    /// to have a radius worth reading (beyond ``straightRadius``).
    public static func tightestRadius(from start: PlanPoint, to end: PlanPoint, curve: TrackCurve) -> Double? {
        tightestPoint(from: start, to: end, curve: curve)?.radius
    }

    /// Beyond 10 km a curve reads as straight.
    public static let straightRadius = Double(10_000 * WorldCoordinate.unitsPerMetre)

    /// "Straight", or "Radius 320 m" for the tightest radius `radius` in
    /// world units, to the nearest 10 m (to the metre under 100 m).
    public static func radiusText(_ radius: Double?, in language: DisplayLanguage) -> String {
        guard let radius else { return language.text("Straight", "直線") }
        let metres = radius / Double(WorldCoordinate.unitsPerMetre)
        let shown = metres < 100 ? Int(metres.rounded()) : Int((metres / 10).rounded()) * 10
        return language.text("Radius \(shown) m", "半徑 \(shown) 公尺")
    }
}

extension NetworkPreview {
    /// The stretch's tightest radius (see ``TrackCurvature``).
    public var tightestRadius: Double? {
        guard let first = points.first, let last = points.last else { return nil }
        return TrackCurvature.tightestRadius(from: first.plan, to: last.plan, curve: curve)
    }

    /// "Straight" or "Radius 320 m".
    public func radiusText(in language: DisplayLanguage) -> String {
        TrackCurvature.radiusText(tightestRadius, in: language)
    }
}
