import GameCore

/// A train's cars as the map draws them close up (ARCHITECTURE decision 205).
///
/// GameCore stands a train's cars ``Train/carPitch`` apart (16 m, or since
/// decision 227 its type's real length) and its
/// body runs from the first car's centre to the last's (``Train/length``),
/// so a train drawn along it looked short and fat: a four-car train 48 m
/// long and nearly 5 m wide. The map draws each car ``drawnCarLength``
/// long instead, the rest back along the track the train stands on and,
/// past its tail, straight on, the way its last stretch runs. Only drawing:
/// where the train is, stops and what track it holds stay GameCore's.
///
/// Decision 565: the first car's nose at the head, where GameCore stops a
/// train (a platform's far end, a signal, a buffer stop), not half a car
/// ahead of it: drawn that way, every train stood half a car past the end
/// of its platform (110.1, "overruns the platform by about a car"). And in
/// a world with real car lengths, each car its own length
/// (``carLength(pitch:)``), so a train as long as its platform is drawn
/// no longer than it.
public enum TrainCars {
    /// A car on the map: 20 m, about a Taiwanese commuter car's length
    /// (the EMU700 and EMU800 are 20 m).
    public static let drawnCarLength = 20.0 * Double(WorldCoordinate.unitsPerMetre)

    /// Decision 565: how long the map draws each car of a train whose cars
    /// stand `pitch` apart (``Train/carPitch``): ``drawnCarLength`` where
    /// they stand ``Train/carLength`` (16 m, a world without real car
    /// lengths, decision 205), otherwise `pitch` itself, the car's real
    /// length (decision 227), so the train drawn is the train GameCore
    /// fits to platforms.
    public static func carLength(pitch: Double) -> Double {
        pitch == Double(Train.carLength) || pitch <= 0 ? drawnCarLength : pitch
    }

    /// Decision 565: how long a train of `count` cars `pitch` apart is
    /// end to end (its cars' real lengths), or `nil` in a world without
    /// real car lengths (`pitch` ``Train/carLength``), where it is drawn
    /// longer than that (decision 205).
    public static func realLength(count: Int, pitch: Double) -> Double? {
        pitch == Double(Train.carLength) || pitch <= 0 ? nil : Double(count) * pitch
    }

    /// Decision 565: how far ahead of its head a train's first car's nose
    /// is drawn: nowhere with real car lengths, so it stops with its nose
    /// at the platform's end; half a ``drawnCarLength`` without them
    /// (`pitch` ``Train/carLength``), as before, where its cars are drawn
    /// 20 m on 16 m and the excess is shared between its two ends.
    public static func noseLead(pitch: Double) -> Double {
        pitch == Double(Train.carLength) || pitch <= 0 ? drawnCarLength / 2 : 0
    }

    /// How many cars a train of `length` (``Train/length``, world units
    /// from its first car's centre to its last's) has, its cars
    /// `carPitch` apart (``Train/carPitch``, ``TrainMotion/Run/carPitch``;
    /// decision 227). 16 m when not given, as every train before real car
    /// lengths.
    public static func count(length: Double, carPitch: Double = Double(Train.carLength)) -> Int {
        max(1, Int((length / carPitch).rounded()) + 1)
    }

    /// The cars of a train whose `body` (head first, the first car's centre
    /// first) runs back from it and that faces `heading`: each car's
    /// polyline from its front to its back, the leading car first, `gap`
    /// world units apart, each `length` long. Empty when there is no body.
    ///
    /// Decision 538: along `track` (``TrainMotion/Run/track(at:)``) past
    /// the body's two ends, as far as it goes, rather than straight on.
    public static func cars(
        body: [TrainMotion.Point], heading: TrainMotion.Point, count: Int, gap: Double = 0,
        length: Double = drawnCarLength, lead: Double = 0,
        track: (ahead: [TrainMotion.Point], behind: [TrainMotion.Point])? = nil
    ) -> [[TrainMotion.Point]] {
        guard count > 0, length > 0,
              let trail = spine(body: body, heading: heading, lead: lead, needed: length * Double(count), track: track) else { return [] }
        let trim = min(max(gap, 0), length / 2) / 2
        return (0..<count).map { index in
            let front = Double(index) * length
            return trail.points(
                from: front + (index == 0 ? 0 : trim),
                to: front + length - (index == count - 1 ? 0 : trim)
            )
        }
    }

    /// Decision 538 (continued): the cars the 2D map draws of `run` at
    /// `progress`, ``carLength(pitch:)`` each, its first car's nose at its
    /// head (decision 565): along the track past the body's tail and, where
    /// it glides on, ahead of the head, as the 3D map lays them
    /// (``Map3DTrains/cars(of:progress:heights:models:)``), so a car on a
    /// curve, through a switch or across a ring's seam stays on the track.
    ///
    /// The same cars as ``cars(body:heading:count:gap:track:)`` given
    /// ``TrainMotion/Run/track(at:)``, but read straight off the run's
    /// trail (which goes on past its tail along the track) and the track
    /// ahead, without building the spine each frame; the general way only
    /// where the track runs out (a buffer stop) or the train jumped.
    public static func mapCars(of run: TrainMotion.Run, progress: Double) -> [[TrainMotion.Point]] {
        guard let head = run.head(at: progress) else { return [] }
        let count = count(length: run.length, carPitch: run.carPitch)
        let length = carLength(pitch: run.carPitch), lead = noseLead(pitch: run.carPitch)
        let along = run.lag * (1 - min(max(progress, 0), 1))
        // Where the nose is along the trail: before its start (negative),
        // on the track ahead of the head now.
        let nose = along - lead
        let trail = run.trail, ahead = run.aheadTrail
        if nose + length * Double(count) <= trail.length, -nose <= ahead.length {
            return (0..<count).map { index in
                let front = nose + Double(index) * length, back = front + length
                guard front < 0 else { return trail.points(from: front, to: back) }
                return Array(ahead.points(from: 0, to: -front).reversed()) + trail.points(from: 0, to: back).dropFirst()
            }
        }
        return cars(body: run.body(at: progress), heading: head.heading, count: count, length: length, lead: lead, track: run.track(at: progress))
    }

    /// Decision 399: the cars of a train drawn at their own `lengths`
    /// (world units, front to back), `gaps[i]` between car `i` and the
    /// next, the first one's nose where every train's is, at its head
    /// (decision 565).
    ///
    /// No longer than the train it draws, though: a set laid at its real
    /// lengths (25 m a high-speed car) on a train whose cars stand closer
    /// (16 m, a world without real car lengths) is shrunk to the length
    /// ``drawnCarLength`` cars would be drawn at, or when that is longer,
    /// its body with `lead` before its head and a car and a half past its
    /// tail, so no more of it lies past
    /// its tail, off the track, than of a train drawn 20 m a car (88.1: a
    /// 12-car 700T or N700S-G ran some 120 m past its tail). Only when it
    /// is more than half a ``drawnCarLength`` longer than that, though: a
    /// set a few metres over is drawn at its own lengths, its cars at
    /// their models' own scale.
    ///
    /// Decision 565: with `real`, the train's length end to end at its
    /// real car lengths (``realLength(count:pitch:)``), never longer than
    /// that, so a train that fits its platform is drawn inside it (a
    /// 12-car EMU3000's models, 245.7 m, are drawn the 243.6 m its 20.3 m
    /// cars make, a hair shorter).
    public static func cars(
        body: [TrainMotion.Point], heading: TrainMotion.Point, lengths: [Double], gaps: [Double], real: Double? = nil, lead: Double = 0,
        track: (ahead: [TrainMotion.Point], behind: [TrainMotion.Point])? = nil
    ) -> [[TrainMotion.Point]] {
        var whole = 0.0
        for (index, length) in lengths.enumerated() { whole += length + (index < gaps.count ? gaps[index] : 0) }
        let scale: Double
        if let real {
            scale = whole > real ? real / whole : 1
        } else {
            let bound = max(TrainMotion.Trail(body).length + lead + 1.5 * drawnCarLength, drawnCarLength * Double(lengths.count))
            scale = whole > bound + drawnCarLength / 2 ? bound / whole : 1
        }
        var fronts: [Double] = [], front = 0.0
        for (index, length) in lengths.enumerated() {
            fronts.append(front)
            front += (length + (index < gaps.count ? gaps[index] : 0)) * scale
        }
        guard !lengths.isEmpty, let trail = spine(body: body, heading: heading, lead: lead, needed: front, track: track) else { return [] }
        return lengths.indices.map { trail.points(from: fronts[$0], to: fronts[$0] + lengths[$0] * scale) }
    }

    /// The track a train's cars are laid along, from its nose `lead`
    /// ahead of its head (decision 565: 0 with real car lengths, see
    /// ``noseLead(pitch:)``) back along its `body` and, past its tail,
    /// straight on, at least `needed` long. Decision 538: with `track`,
    /// the nose and what lies past the tail along it, as far as it goes:
    /// on a sharp curve, laid straight on, the last car swung metres off
    /// the track (104.1, Zhuzhong's viaduct platform).
    private static func spine(
        body: [TrainMotion.Point], heading: TrainMotion.Point, lead: Double, needed: Double,
        track: (ahead: [TrainMotion.Point], behind: [TrainMotion.Point])? = nil
    ) -> TrainMotion.Trail? {
        guard let head = body.first else { return nil }
        let forward = unit(heading) ?? backward(body).map { TrainMotion.Point(x: -$0.x, y: -$0.y) } ?? TrainMotion.Point(x: 1, y: 0)
        var spine: [TrainMotion.Point] = []
        if lead > 0 {
            let ahead = TrainMotion.Trail(track?.ahead ?? [])
            if ahead.length >= lead {
                spine = ahead.points(from: 0, to: lead).reversed()
            } else {
                spine = [TrainMotion.Point(x: head.x + forward.x * lead, y: head.y + forward.y * lead)]
            }
        }
        var rear = body
        if let behind = track?.behind, TrainMotion.Trail(behind).length >= TrainMotion.Trail(body).length { rear = behind }
        spine += rear
        let laid = TrainMotion.Trail(spine).length
        if laid < needed, let tail = spine.last {
            let back = backward(rear) ?? TrainMotion.Point(x: -forward.x, y: -forward.y)
            let rest = needed - laid
            spine.append(TrainMotion.Point(x: tail.x + back.x * rest, y: tail.y + back.y * rest))
        }
        return TrainMotion.Trail(spine)
    }

    /// The way the body runs at its tail, from its head towards it, as a
    /// unit vector: along its last ``drawnCarLength`` (all of it when
    /// shorter), not its last segment, which can be a few world units
    /// between rounded points and turned by degrees from the track (88.1:
    /// a long set's last cars, laid straight on from it, swung off the
    /// viaduct); `nil` for a body of one point.
    static func backward(_ body: [TrainMotion.Point]) -> TrainMotion.Point? {
        let trail = TrainMotion.Trail(body)
        guard let tail = trail.points.last, let from = trail.point(at: trail.length - drawnCarLength) else { return nil }
        return unit(TrainMotion.Point(x: tail.x - from.x, y: tail.y - from.y))
    }

    private static func unit(_ point: TrainMotion.Point) -> TrainMotion.Point? {
        let size = (point.x * point.x + point.y * point.y).squareRoot()
        return size > 0 ? TrainMotion.Point(x: point.x / size, y: point.y / size) : nil
    }
}
