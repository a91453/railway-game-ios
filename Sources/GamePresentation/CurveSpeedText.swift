import GameCore

// What the player sees of the curve speed limits (ARCHITECTURE decision
// 217): no signs on the map, but the followed or selected train says when
// it is held to a curve's limit or braking for one, and the drawing loupe
// says how fast the radius under the finger may be run.

/// A train held to a curve's limit, or braking for one ahead.
public struct CurveLimitReading: Hashable, Sendable {
    /// km/h.
    public let speed: Int64
    /// Whether the curve is still ahead of the train's head.
    public let ahead: Bool

    /// "Curve limit 60 km/h" or "Curve ahead: 60 km/h".
    public func text(in language: DisplayLanguage) -> String {
        ahead
            ? language.text("Curve ahead: \(speed) km/h", "前方彎道 \(speed) km/h")
            : language.text("Curve limit \(speed) km/h", "彎道限速 \(speed) km/h")
    }
}

extension GameWorld {
    /// How far ahead a curve is named: 1 km, about the braking distance of
    /// a 130 km/h express.
    public static let curveLimitLookahead: Int64 = 1_000 * WorldCoordinate.unitsPerMetre

    /// The curve limit train `id` keeps to now, where its head is, or else
    /// the first its run brakes for within ``curveLimitLookahead``; `nil`
    /// with the curve limits off, for a train not running a service, and
    /// where no limit below its top speed holds.
    public func curveLimit(of id: TrainID) -> CurveLimitReading? {
        guard curveSpeedLimits, let train = train(id: id), train.execution != nil, case .onEdge(let traversal, let offset)? = train.position,
              let edge = network.edge(traversal.edge) else { return nil }
        let along = traversal.direction == .forward ? offset : edge.length - offset
        if let here = edge.speedLimits.first(where: { $0.start <= along && along < $0.end }), here.speed < train.performance.topSpeed {
            return CurveLimitReading(speed: here.speed, ahead: false)
        }
        guard case .travellingToStop? = train.execution, let run = train.times?.run, clock.now >= run.start, clock.now < run.end,
              let curve = runCurve(of: run, for: train.performance) else { return nil }
        let covered = curve.distance(at: (clock.now.seconds - run.start.seconds) * 1000)
        if let current = run.limits.first(where: { $0.start <= covered && covered < $0.end }) {
            // Its tail is still in the curve behind it.
            return CurveLimitReading(speed: current.speed, ahead: false)
        }
        guard let next = run.limits.first(where: { $0.start > covered }), next.start - covered <= Self.curveLimitLookahead else { return nil }
        return CurveLimitReading(speed: next.speed, ahead: true)
    }
}

extension TrackCurvature {
    /// "Up to 105 km/h" for a curve of `radius` world units, or `nil` for
    /// one with no limit (or none at all).
    public static func speedText(_ radius: Double?, in language: DisplayLanguage) -> String? {
        guard let radius, radius.isFinite else { return nil }
        let metres = Int64(radius / Double(WorldCoordinate.unitsPerMetre))
        guard let speed = CurveSpeedLimit.speed(radiusMetres: metres) else { return nil }
        return language.text("up to \(speed) km/h", "可跑 \(speed) km/h")
    }
}

extension NetworkPreview {
    /// "Radius 320 m · up to 75 km/h" with the curve limits on, or just the
    /// radius (see ``radiusText(in:)``).
    public func radiusText(in language: DisplayLanguage, curveSpeedLimits: Bool) -> String {
        let radius = tightestRadius
        guard curveSpeedLimits, let speed = TrackCurvature.speedText(radius, in: language) else {
            return TrackCurvature.radiusText(radius, in: language)
        }
        return "\(TrackCurvature.radiusText(radius, in: language)) · \(speed)"
    }
}
