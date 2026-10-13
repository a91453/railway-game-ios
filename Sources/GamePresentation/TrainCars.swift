import GameCore

/// A train's cars as the map draws them close up (ARCHITECTURE decision 205).
///
/// GameCore stands a train's cars ``Train/carLength`` (16 m) apart and its
/// body runs from the first car's centre to the last's (``Train/length``),
/// so a train drawn along it looked short and fat: a four-car train 48 m
/// long and nearly 5 m wide. The map draws each car ``drawnCarLength``
/// long instead, the first one's nose half a car ahead of its head, the
/// rest back along the track the train stands on and, past its tail,
/// straight on the way its last stretch runs. Only drawing: where the train
/// is, stops and what track it holds stay GameCore's.
public enum TrainCars {
    /// A car on the map: 20 m, about a Taiwanese commuter car's length
    /// (the EMU700 and EMU800 are 20 m).
    public static let drawnCarLength = 20.0 * Double(WorldCoordinate.unitsPerMetre)

    /// How many cars a train of `length` (``Train/length``, world units
    /// from its first car's centre to its last's) has.
    public static func count(length: Double) -> Int {
        max(1, Int((length / Double(Train.carLength)).rounded()) + 1)
    }

    /// The cars of a train whose `body` (head first, the first car's centre
    /// first) runs back from it and that faces `heading`: each car's
    /// polyline from its front to its back, the leading car first, `gap`
    /// world units apart. Empty when there is no body.
    public static func cars(
        body: [TrainMotion.Point], heading: TrainMotion.Point, count: Int, gap: Double = 0
    ) -> [[TrainMotion.Point]] {
        guard let head = body.first, count > 0 else { return [] }
        let forward = unit(heading) ?? backward(body).map { TrainMotion.Point(x: -$0.x, y: -$0.y) } ?? TrainMotion.Point(x: 1, y: 0)
        let half = drawnCarLength / 2
        let nose = TrainMotion.Point(x: head.x + forward.x * half, y: head.y + forward.y * half)
        var spine = [nose] + body
        let laid = TrainMotion.Trail(spine).length
        let needed = drawnCarLength * Double(count)
        if laid < needed, let tail = spine.last {
            let back = backward(body) ?? TrainMotion.Point(x: -forward.x, y: -forward.y)
            let rest = needed - laid
            spine.append(TrainMotion.Point(x: tail.x + back.x * rest, y: tail.y + back.y * rest))
        }
        let trail = TrainMotion.Trail(spine)
        let trim = min(max(gap, 0), drawnCarLength / 2) / 2
        return (0..<count).map { index in
            let front = Double(index) * drawnCarLength
            return trail.points(
                from: front + (index == 0 ? 0 : trim),
                to: front + drawnCarLength - (index == count - 1 ? 0 : trim)
            )
        }
    }

    /// The way the body runs at its tail, from its head towards it, as a
    /// unit vector; `nil` for a body of one point.
    private static func backward(_ body: [TrainMotion.Point]) -> TrainMotion.Point? {
        guard body.count > 1 else { return nil }
        let a = body[body.count - 2], b = body[body.count - 1]
        return unit(TrainMotion.Point(x: b.x - a.x, y: b.y - a.y))
    }

    private static func unit(_ point: TrainMotion.Point) -> TrainMotion.Point? {
        let size = (point.x * point.x + point.y * point.y).squareRoot()
        return size > 0 ? TrainMotion.Point(x: point.x / size, y: point.y / size) : nil
    }
}
