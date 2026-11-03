import Foundation

/// Decision 555: whether two fingers on the 3D map are leaning it over
/// (``Map3DCamera/leaned(dy:)``) rather than pinching or turning it. As
/// MapLibre GL JS's two-finger pitch handler decides
/// (`TwoFingersTouchPitchHandler` in `src/ui/handler/two_fingers_touch.ts`,
/// BSD-3-Clause, © 2023 MapLibre contributors; the rule, not its code):
/// the fingers side by side rather than one above the other, both moving
/// the same way up or down the screen and more up and down than across
/// (its `isVertical` and `isSameDirection`). Added here: the fingers
/// draw no closer or farther apart than a little, as UIKit's pinch runs
/// beside it (MapLibre's pinch is another handler it gives way to). Decided
/// once the fingers have moved ``decideAfter`` points; until then the
/// pinch and the turn act as before, and once it leans they wait until
/// the fingers lift.
public struct Map3DTiltDrag: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Not moved far enough to tell.
        case undecided
        /// Leaning the map: the pinch and the turn wait.
        case leans
        /// A pinch or a turn: the lean waits until the fingers lift.
        case other
    }

    public typealias Point = (x: Float, y: Float)

    /// Points the fingers move, on average, before it is decided.
    public static let decideAfter: Float = 10
    /// The most the line between the fingers may lie from level (45°,
    /// MapLibre's `isVertical` of it).
    public static let steepestPair: Float = 45 * .pi / 180
    /// How much more up and down than across each finger must move
    /// (MapLibre: more at all; here half as much again, as the turn and
    /// the pinch run beside it).
    public static let upright: Float = 1.5
    /// The share by which the fingers may draw apart or together.
    public static let spread: Float = 0.15

    public private(set) var verdict: Verdict = .undecided
    let start: (Point, Point)

    public init(_ first: Point, _ second: Point) {
        start = (first, second)
    }

    public static func == (a: Map3DTiltDrag, b: Map3DTiltDrag) -> Bool {
        a.verdict == b.verdict && a.start.0 == b.start.0 && a.start.1 == b.start.1
    }

    /// The verdict with the fingers now at `first` and `second` (the same
    /// fingers in the same order as at the start).
    @discardableResult
    public mutating func move(_ first: Point, _ second: Point) -> Verdict {
        guard verdict == .undecided else { return verdict }
        let a = (x: first.x - start.0.x, y: first.y - start.0.y)
        let b = (x: second.x - start.1.x, y: second.y - start.1.y)
        let moved = ((a.x * a.x + a.y * a.y).squareRoot() + (b.x * b.x + b.y * b.y).squareRoot()) / 2
        guard moved >= Self.decideAfter else { return .undecided }
        let across = abs(start.1.x - start.0.x), down = abs(start.1.y - start.0.y)
        let sideBySide = atan2f(down, across) <= Self.steepestPair
        let sameWay = a.y * b.y > 0
        let upAndDown = abs(a.y) >= Self.upright * abs(a.x) && abs(b.y) >= Self.upright * abs(b.x)
        func gap(_ p: Point, _ q: Point) -> Float { ((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)).squareRoot() }
        let before = gap(start.0, start.1), after = gap(first, second)
        let steady = before > 0 && abs(after - before) <= Self.spread * before
        verdict = sideBySide && sameWay && upAndDown && steady ? .leans : .other
        return verdict
    }

    /// How far the fingers have moved down the screen since the start, on
    /// average, in points: what ``Map3DCamera/leaned(dy:)`` takes.
    public func drop(_ first: Point, _ second: Point) -> Float {
        ((first.y - start.0.y) + (second.y - start.1.y)) / 2
    }
}
