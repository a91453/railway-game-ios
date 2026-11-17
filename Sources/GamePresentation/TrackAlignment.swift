import Foundation
import GameCore

// Decision 826: drawing track with a finger (decision 102), the stretch's
// free end is drawn in line with the track around it when the finger is
// nearly there (NEXT_PRIORITIES §29.16, TRACK-ALIGN): straight on from the
// track it starts from, or parallel or at right angles to track near either
// end. A dashed guide shows the line it keeps to, and the loupe says what it
// lines up with, or else how far the stretch turns. Only where the free end
// is picked changes: GameCore is sent the same kind of stretch as ever
// (``NetworkBuilding/curve(from:leaving:to:leaving:)`` from the ends). The
// owner's MapBuilder and `Simulator/` have no angle snapping (their only
// "snap" is the map library's north snap): the project's own, after the
// guide lines of drawing programs.

/// What the stretch being drawn lines up with, and the dashed lines that
/// show it.
public struct TrackDrawGuide: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Straight on from the track it starts from.
        case straightOn
        /// Parallel to track nearby.
        case parallel
        /// At right angles to track nearby.
        case perpendicular
    }

    public let kind: Kind
    /// The dashed lines: through the stretch along the way it keeps to,
    /// and, for track nearby, a piece along that track where it is.
    public let lines: [[PlanPoint]]

    /// "Parallel to the track", for the loupe.
    public func text(in language: DisplayLanguage) -> String {
        switch kind {
        case .straightOn: language.text("Straight on from the track", "沿軌道直直延伸")
        case .parallel: language.text("Parallel to the track", "與軌道平行")
        case .perpendicular: language.text("At right angles to the track", "與軌道垂直")
        }
    }
}

/// Lining the free end of a stretch up with the track around it.
public enum TrackAlignment {
    /// How close, in degrees, the stretch's direction must come to one it
    /// lines up with before it is drawn exactly along it: 3°, small enough
    /// to draw any angle in between, as a drawing program's guides are.
    public static let tolerance = 3.0
    /// How far the guide reaches for track near an end, in touch reaches
    /// (``NetworkBuilding/touchRadius``): six, a finger's width or two.
    public static let guideReaches: Int64 = 6

    /// A direction the stretch may line up with.
    public struct Reference: Hashable, Sendable {
        /// The way the track runs (either way along it).
        public let direction: PlanVector
        /// The place on the track.
        public let at: PlanPoint
        /// Whether it is the track the stretch starts from, which it can
        /// only continue straight on.
        public let continues: Bool

        public init(direction: PlanVector, at: PlanPoint, continues: Bool) {
            self.direction = direction
            self.at = at
            self.continues = continues
        }
    }

    /// The free end `end` of a stretch from `start`, moved round `start` (at
    /// the same distance) to line up with the nearest of `references` within
    /// ``tolerance``, and the guide that shows it; `nil` when it lines up
    /// with none. The start's own track comes first; `reach` (world units)
    /// sets how long the guides are.
    public static func align(start: PlanPoint, end: PlanPoint, references: [Reference], reach: Int64) -> (end: PlanPoint, guide: TrackDrawGuide)? {
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        let angle = atan2(dy, dx)
        var best: (reference: Reference, kind: TrackDrawGuide.Kind, target: Double, off: Double)?
        for reference in references {
            let along = atan2(Double(reference.direction.dy), Double(reference.direction.dx))
            guard reference.direction.dx != 0 || reference.direction.dy != 0 else { continue }
            let targets: [(TrackDrawGuide.Kind, Double)] = reference.continues
                ? [(.straightOn, along)]
                : [(.parallel, along), (.parallel, along + .pi), (.perpendicular, along + .pi / 2), (.perpendicular, along - .pi / 2)]
            for (kind, target) in targets {
                let off = abs(remainder(angle - target, 2 * .pi)) * 180 / .pi
                guard off <= tolerance else { continue }
                // The start's own track wins; otherwise the nearest angle.
                if let current = best,
                   current.reference.continues == reference.continues ? current.off <= off : current.reference.continues { continue }
                best = (reference, kind, target, off)
            }
        }
        guard let best else { return nil }
        let (ux, uy) = (cos(best.target), sin(best.target))
        let moved = PlanPoint(x: start.x + Int64((ux * length).rounded()), y: start.y + Int64((uy * length).rounded()))
        // Through the stretch and a little past its end.
        let past = length + Double(reach * 2)
        var lines = [[start, PlanPoint(x: start.x + Int64((ux * past).rounded()), y: start.y + Int64((uy * past).rounded()))]]
        if !best.reference.continues {
            let way = (x: Double(best.reference.direction.dx), y: Double(best.reference.direction.dy))
            let norm = (way.x * way.x + way.y * way.y).squareRoot()
            let half = Double(reach * 3) / norm
            let at = best.reference.at
            lines.append([
                PlanPoint(x: at.x - Int64((way.x * half).rounded()), y: at.y - Int64((way.y * half).rounded())),
                PlanPoint(x: at.x + Int64((way.x * half).rounded()), y: at.y + Int64((way.y * half).rounded())),
            ])
        }
        return (moved, TrackDrawGuide(kind: best.kind, lines: lines))
    }

    /// How far, in whole degrees, the edge from `start` to `end` shaped by
    /// `curve` turns from its start to its end: positive to the right (the
    /// plan's y grows south), negative to the left.
    public static func turn(from start: PlanPoint, to end: PlanPoint, curve: TrackCurve) -> Int {
        let chord = (x: Double(end.x - start.x), y: Double(end.y - start.y))
        let (leaving, arriving): ((x: Double, y: Double), (x: Double, y: Double))
        switch curve {
        case .straight:
            return 0
        case .cubic(let c1, let c2):
            let first = (x: Double(c1.x - start.x), y: Double(c1.y - start.y))
            let last = (x: Double(end.x - c2.x), y: Double(end.y - c2.y))
            leaving = first.x == 0 && first.y == 0 ? chord : first
            arriving = last.x == 0 && last.y == 0 ? chord : last
        }
        let cross = leaving.x * arriving.y - leaving.y * arriving.x
        let dot = leaving.x * arriving.x + leaving.y * arriving.y
        return Int((atan2(cross, dot) * 180 / .pi).rounded())
    }

    /// "Turns 35° right", or `nil` for a stretch that turns less than a
    /// degree.
    public static func turnText(_ degrees: Int, in language: DisplayLanguage) -> String? {
        guard degrees != 0 else { return nil }
        return degrees > 0
            ? language.text("Turns \(degrees)° right", "向右轉 \(degrees)°")
            : language.text("Turns \(-degrees)° left", "向左轉 \(-degrees)°")
    }
}

extension NetworkPreview {
    /// How far the stretch turns (``TrackAlignment/turn(from:to:curve:)``).
    public var turn: Int {
        guard traced == nil, let first = points.first, let last = points.last else { return 0 }
        return TrackAlignment.turn(from: first.plan, to: last.plan, curve: curve)
    }
}

extension GameSession {
    /// The loupe's second line while a finger draws track (decision 826):
    /// what the stretch lines up with, or else how far it turns; `nil` when
    /// neither.
    public var networkDragGuideText: String? {
        guard networkDragFinger != nil else { return nil }
        if let guide = networkDragGuide { return guide.text(in: language) }
        return networkPreview.flatMap { TrackAlignment.turnText($0.turn, in: language) }
    }

    /// The directions the stretch from `start` (standing at `from`) to a
    /// free end at `end` may line up with: the track it starts from, when
    /// it follows it; and the track nearest each end within `guideReach`.
    func alignmentReferences(start: NetworkAnchor, from: PlanPoint, end: PlanPoint, guideReach: Int64) -> [TrackAlignment.Reference] {
        var references: [TrackAlignment.Reference] = []
        if networkFollowsTrack {
            let leaving: PlanVector? = switch start {
            case .node(let id): world.joiningDirection(at: id, toward: end)
            case .track(let point): world.joiningDirection(at: point, toward: end)
            case .point: nil
            }
            if let leaving { references.append(TrackAlignment.Reference(direction: leaving, at: from, continues: true)) }
        }
        var places = [end]
        if case .point = start { places.append(from) }
        for place in places {
            guard let near = world.trackEdgePoint(near: place, within: guideReach),
                  let geometry = world.trackGeometry(of: near.edge) else { continue }
            let location = geometry.location(at: near.distance)
            references.append(TrackAlignment.Reference(direction: location.direction, at: location.position.plan, continues: false))
        }
        return references
    }
}
