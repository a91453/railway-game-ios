import GameCore

// Trains drawn moving smoothly between the game's ticks (ARCHITECTURE
// decision 182). The game ticks every 100 ms and a train jumps along its
// track at each tick, a game minute's run at the normal speed; the map
// draws it instead gliding, frame by frame, along the track it covered in
// the last tick, from where it was to where it is: one tick behind, never
// ahead, so it never shows a place the train has not reached. Only drawing:
// nothing here is written back into the world.
//
// The track it covered is the way the train's movement said it would go
// at the tick before (``TrainMovement/remainingEdges``): from its previous
// head along the rest of that edge and the edges named after it, to its
// head now. When it came to the end of that way and set off along a new
// path within the same tick (a call passed while the game runs fast, a
// minute a tick), the way goes on along the edges of the new path it has
// entered since. A train that turned back, was placed or taken off, or got
// somewhere neither leads (a changed track, another game), jumps to where
// it is, as every train did before.
//
// The `Railway/` reference's 3D view places its cars by distance along a
// path (`rail-3d/integration/train-path.js` `makePath`: `at(s)` the point
// `s` along the path, `locate(coord)` the nearest place on it); ``Trail``
// is the same pair, in world units, without the reference's metres on the
// Earth, its spatial grid and its distance hint.

/// How a train looks on the map (decision 182): in its line's colour, grey
/// on a freight line, and as before (the map's train colour) when it runs
/// on no line.
public enum TrainLook: Hashable, Sendable {
    case plain
    case line(LineID, LineColor?)
    case freight
}

/// The trains' moves in the last tick, to draw them gliding until the next
/// (decision 182).
public struct TrainMotion: Sendable {
    /// A point in world units, in fractions.
    public struct Point: Hashable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(_ coordinate: WorldCoordinate) {
            self.init(x: Double(coordinate.x), y: Double(coordinate.y))
        }
    }

    /// A polyline and how far along it each of its points is: the
    /// reference's `makePath`.
    public struct Trail: Sendable {
        public let points: [Point]
        let distances: [Double]

        public init(_ points: [Point]) {
            var kept: [Point] = []
            var distances: [Double] = []
            for point in points {
                if let last = kept.last {
                    let step = Self.distance(last, point)
                    // A repeated point adds nothing and has no direction.
                    guard step > 0 else { continue }
                    distances.append(distances.last! + step)
                } else {
                    distances.append(0)
                }
                kept.append(point)
            }
            self.points = kept
            self.distances = distances
        }

        /// How long it is.
        public var length: Double { distances.last ?? 0 }

        /// The point `distance` along it, held at its ends; `nil` when it
        /// has no points. The reference's `at(s)`.
        public func point(at distance: Double) -> Point? {
            guard let first = points.first else { return nil }
            guard points.count > 1 else { return first }
            let s = min(max(distance, 0), length)
            let index = segment(at: s)
            let a = points[index], b = points[index + 1]
            let span = distances[index + 1] - distances[index]
            let share = span > 0 ? (s - distances[index]) / span : 0
            return Point(x: a.x + (b.x - a.x) * share, y: a.y + (b.y - a.y) * share)
        }

        /// The way the polyline runs at `distance` along it, as a unit
        /// vector from its start towards its end; `nil` for fewer than two
        /// points.
        public func direction(at distance: Double) -> Point? {
            guard points.count > 1 else { return nil }
            let index = segment(at: min(max(distance, 0), length))
            let a = points[index], b = points[index + 1]
            let size = Self.distance(a, b)
            return Point(x: (b.x - a.x) / size, y: (b.y - a.y) / size)
        }

        /// The stretch from `start` to `end` along it, both held at its
        /// ends: their points and every point between.
        public func points(from start: Double, to end: Double) -> [Point] {
            guard points.count > 1 else { return points }
            let a = min(max(start, 0), length), b = min(max(end, a), length)
            guard let first = point(at: a), let last = point(at: b) else { return [] }
            var stretch = [first]
            for index in points.indices where distances[index] > a && distances[index] < b {
                stretch.append(points[index])
            }
            stretch.append(last)
            return stretch
        }

        /// Where on it `point` is nearest, and how far `point` is from it:
        /// the reference's `locate(coord)`; `nil` when it has no points.
        public func locate(_ point: Point) -> (distance: Double, error: Double)? {
            guard let first = points.first else { return nil }
            guard points.count > 1 else { return (0, Self.distance(first, point)) }
            var best: (distance: Double, error: Double)?
            for index in 1..<points.count {
                let a = points[index - 1], b = points[index]
                let dx = b.x - a.x, dy = b.y - a.y
                let q = dx * dx + dy * dy
                let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / q, 0), 1)
                let error = Self.distance(Point(x: a.x + t * dx, y: a.y + t * dy), point)
                // The first of two as near (the reference's 1 mm tie, here
                // a hundredth of a unit) is kept: the nearer the head.
                if best == nil || error < best!.error - 0.01 {
                    best = (distances[index - 1] + t * (distances[index] - distances[index - 1]), error)
                }
            }
            return best
        }

        private func segment(at distance: Double) -> Int {
            // The last segment that starts at or before the distance.
            var low = 0, high = points.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if distances[middle] <= distance { low = middle } else { high = middle }
            }
            return low
        }

        static func distance(_ a: Point, _ b: Point) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// What a tick left of a train, for the next tick to start from.
    struct Sample: Sendable {
        let position: TrainPosition
        /// The edges the train was to enter, in order.
        let ahead: [TrackEdgeID]
        /// Its body, head first (``GameWorld/bodyPath(of:)``).
        let body: [Point]
    }

    /// One train's last move.
    public struct Run: Sendable {
        public let train: TrainID
        public let look: TrainLook
        public let isHighSpeed: Bool
        /// How its model is painted (decision 243).
        public let livery: TrainLivery
        /// The track from the train's head now back over the track it
        /// covered in the last tick, then back along its body as it was.
        public let trail: Trail
        /// How far along ``trail`` its head was at the last tick: 0 when it
        /// did not move or jumped.
        public let lag: Double
        /// From its head to its tail, in world units (0 for one car).
        public let length: Double
        /// How far apart its cars stand, in world units (``Train/carPitch``).
        public let carPitch: Double
        /// The way the head faces now, as GameCore says, in world units.
        public let heading: Point

        /// Its head at `progress` from the last tick (0) to now (1): where
        /// and which way it faces.
        public func head(at progress: Double) -> (point: Point, heading: Point)? {
            let along = lag * (1 - min(max(progress, 0), 1))
            guard let point = trail.point(at: along) else { return nil }
            guard along > 0, let backward = trail.direction(at: along) else { return (point, heading) }
            return (point, Point(x: -backward.x, y: -backward.y))
        }

        /// Decision 380: its head at `progress`, where and which way it
        /// faces, held steady: the track's sampled points, about a metre
        /// apart and each rounded to the world's units, turn this way and
        /// that by up to a degree, and its head (``head(at:)``) slides
        /// sideways by up to half a unit as it passes each. A parabola
        /// fitted to the track `span` world units back from the head
        /// (least squares, ``steadySamples`` points), there; `nil` with
        /// less than a tenth of `span` of track behind the head.
        public func steadyHead(at progress: Double, over span: Double) -> (point: Point, heading: Point)? {
            let along = lag * (1 - min(max(progress, 0), 1))
            let reach = min(span, trail.length - along)
            guard reach > span / 10, let head = trail.point(at: along) else { return nil }
            var x = (value: 0.0, slope: 0.0), y = (value: 0.0, slope: 0.0)
            for (index, weight) in Self.steadyWeights.enumerated() {
                guard let p = trail.point(at: along + reach * Double(index) / Double(Self.steadySamples - 1)) else { return nil }
                x = (x.value + weight.value * (p.x - head.x), x.slope + weight.slope * (p.x - head.x))
                y = (y.value + weight.value * (p.y - head.y), y.slope + weight.slope * (p.y - head.y))
            }
            // The slope runs back along the track, from the head.
            let size = (x.slope * x.slope + y.slope * y.slope).squareRoot()
            guard size > 0 else { return nil }
            return (Point(x: head.x + x.value, y: head.y + y.value), Point(x: -x.slope / size, y: -y.slope / size))
        }

        /// How many points of the track ``steadyHead(at:over:)`` fits.
        static let steadySamples = 41

        /// The least-squares parabola's value and slope at the first of
        /// ``steadySamples`` evenly spaced points, as weights of the points.
        static let steadyWeights: [(value: Double, slope: Double)] = {
            let ts = (0..<steadySamples).map { Double($0) / Double(steadySamples - 1) }
            var m = [[Double]](repeating: [0, 0, 0], count: 3)
            for t in ts {
                let f = [1, t, t * t]
                for row in 0..<3 { for column in 0..<3 { m[row][column] += f[row] * f[column] } }
            }
            // The inverse of the symmetric 3 × 3 normal matrix, by cofactors.
            func cofactor(_ r: Int, _ c: Int) -> Double {
                let rows = (0..<3).filter { $0 != r }, columns = (0..<3).filter { $0 != c }
                let minor = m[rows[0]][columns[0]] * m[rows[1]][columns[1]] - m[rows[0]][columns[1]] * m[rows[1]][columns[0]]
                return (r + c).isMultiple(of: 2) ? minor : -minor
            }
            let determinant = (0..<3).reduce(0.0) { $0 + m[0][$1] * cofactor(0, $1) }
            let inverse = (0..<3).map { r in (0..<3).map { c in cofactor(c, r) / determinant } }
            return ts.map { t in
                let f = [1, t, t * t]
                return ((0..<3).reduce(0.0) { $0 + inverse[0][$1] * f[$1] }, (0..<3).reduce(0.0) { $0 + inverse[1][$1] * f[$1] })
            }
        }()

        /// Its body at `progress`, head first: ``length`` along the trail
        /// from its head.
        public func body(at progress: Double) -> [Point] {
            let along = lag * (1 - min(max(progress, 0), 1))
            return trail.points(from: along, to: along + length)
        }
    }

    public let runs: [Run]
    /// When the tick was seen and how long the glide to it takes, in
    /// seconds of the caller's clock.
    public let time: Double
    public let duration: Double
    let samples: [TrainID: Sample]
    /// The game second the trains were seen at: `nil` for nothing moving.
    let second: Int64?

    /// Nothing moving.
    public init() {
        runs = []
        time = 0
        duration = TrainMotion.tickSeconds
        samples = [:]
        second = nil
    }

    /// The glide's length when the tick before is not known: the game's
    /// tick, 100 ms.
    public static let tickSeconds = 0.1
    /// The shortest and longest a glide lasts: ticks come at most this far
    /// apart when the game keeps up (``GameSession/maximumStepDuration``).
    static let durations = 0.05...0.5
    /// At 1× the trains move once a game second, every tenth tick: a glide
    /// lasts that second (and a little over, as ticks come late), so they
    /// do not stand still for nine ticks and then jump.
    static let longestSecondGlide = 1.25
    /// The furthest a train glides in one tick, in world units (40 km);
    /// further, it jumps.
    static let longestGlide = 40_000.0 * Double(WorldCoordinate.unitsPerMetre)

    /// The trains of `world` as they are at `time` (seconds on the
    /// caller's clock), each gliding from where `previous` saw it when it
    /// went along the way it was to go.
    public init(world: GameWorld, previous: TrainMotion? = nil, time: Double) {
        // At 1× a tick that does not finish a game second moves no train:
        // the glide begun at the last second goes on (the same trains, so a
        // train bought or sold shows by the next second).
        if world.clock.speed == .x1, let previous, previous.second == world.clock.now.seconds,
           Set(previous.samples.keys) == Set(world.trains.lazy.filter { $0.position != nil }.map(\.id)) {
            self = previous
            return
        }
        var looks: [TrainID: TrainLook] = [:]
        for line in world.lines {
            let look: TrainLook = line.isFreight ? .freight : .line(line.id, line.color)
            for train in line.trains + line.patterns.flatMap(\.trains) { looks[train] = look }
        }
        var runs: [Run] = []
        var samples: [TrainID: Sample] = [:]
        for train in world.trains {
            guard let position = train.position, let head = world.location(of: position) else { continue }
            let body = train.length > 0 ? world.bodyPath(of: train.id).map(Point.init) : [Point(head.position)]
            let sample = Sample(position: position, ahead: Array(train.movement.remainingEdges), body: body)
            samples[train.id] = sample
            let size = (Double(head.direction.dx) * Double(head.direction.dx) + Double(head.direction.dy) * Double(head.direction.dy)).squareRoot()
            let heading = size > 0 ? Point(x: Double(head.direction.dx) / size, y: Double(head.direction.dy) / size) : Point(x: 1, y: 0)
            var trail = Trail(body)
            var lag = 0.0
            // Through a call, the new path's edges entered so far; GameCore
            // keeps a path whose last edge has been entered as none, so the
            // edge the train is on is added too (a one-edge path, from one
            // station to the next, is spent within the tick).
            var entered = Array(train.movement.edges.prefix(train.movement.cursor))
            if case .onEdge(let now, _) = position, entered.last != now.edge { entered.append(now.edge) }
            if let before = previous?.samples[train.id],
               let covered = Self.covered(from: before.position, along: before.ahead, to: position, in: world)
                ?? Self.covered(from: before.position, along: before.ahead + entered, to: position, in: world) {
                let glide = Trail(covered.reversed())
                if glide.length > 0, glide.length <= Self.longestGlide {
                    trail = Trail(Array(covered.reversed()) + before.body.dropFirst())
                    lag = glide.length
                }
            }
            runs.append(Run(
                train: train.id, look: looks[train.id] ?? .plain, isHighSpeed: train.type?.isHighSpeed == true,
                livery: TrainLivery.of(type: train.type, performance: train.performance),
                trail: trail, lag: lag, length: Double(train.length), carPitch: Double(train.carPitch), heading: heading
            ))
        }
        self.runs = runs
        self.samples = samples
        self.time = time
        second = world.clock.now.seconds
        if let previous, previous.time > 0 {
            let longest = world.clock.speed == .x1 ? Self.longestSecondGlide : Self.durations.upperBound
            duration = min(max(time - previous.time, Self.durations.lowerBound), longest)
        } else {
            duration = Self.tickSeconds
        }
    }

    /// How far the glide has gone at `time`: 0 at the tick, 1 once it has
    /// lasted ``duration``.
    public func progress(at time: Double) -> Double {
        min(max((time - self.time) / duration, 0), 1)
    }

    /// Whether any train glides.
    public var isMoving: Bool {
        runs.contains { $0.lag > 0 }
    }

    /// Where train `id`'s head is drawn at `time` (seconds on the caller's
    /// clock): the point the camera following it looks at, frame by frame,
    /// so the map moves with the train rather than a step a tick. `nil`
    /// when it is not on the map.
    public func head(of id: TrainID, at time: Double) -> Point? {
        runs.first { $0.train == id }?.head(at: progress(at: time))?.point
    }

    /// The track from a head at `start` to one at `end`, going the way the
    /// edges `ahead` lead, in world coordinates; `nil` when `end` is not on
    /// that way: behind `start` on its edge, turned the other way, or on no
    /// edge `ahead` names (or one that is no longer there).
    static func covered(from start: TrainPosition, along ahead: [TrackEdgeID], to end: TrainPosition, in world: GameWorld) -> [Point]? {
        guard case .onEdge(var traversal, let startOffset) = start, case .onEdge(let target, let endOffset) = end else { return nil }
        var points: [Point] = []
        var offset = startOffset
        var next = ahead.makeIterator()
        while true {
            guard let edge = world.network.edge(traversal.edge), let geometry = world.trackGeometry(of: traversal.edge) else { return nil }
            if traversal == target, endOffset >= offset {
                points += stretch(of: geometry, traversal, from: offset, to: endOffset)
                return points
            }
            if traversal.edge == target.edge, traversal.direction != target.direction { return nil }
            points += stretch(of: geometry, traversal, from: offset, to: geometry.length)
            let node = traversal.direction == .forward ? edge.to : edge.from
            guard let id = next.next(), let following = world.network.edge(id) else { return nil }
            if following.from == node {
                traversal = TrackTraversal(edge: id, direction: .forward)
            } else if following.to == node {
                traversal = TrackTraversal(edge: id, direction: .backward)
            } else {
                return nil
            }
            offset = 0
        }
    }

    /// Edge `geometry` travelled as `traversal` from `start` to `end`
    /// along it, in the traversal's offsets.
    private static func stretch(of geometry: TrackGeometry, _ traversal: TrackTraversal, from start: Int64, to end: Int64) -> [Point] {
        let length = geometry.length
        let a = min(max(start, 0), length), b = min(max(end, 0), length)
        guard a < b else { return [Point(geometry.location(at: a, going: traversal.direction).position)] }
        switch traversal.direction {
        case .forward:
            return geometry.points(from: a, to: b).map(Point.init)
        case .backward:
            return geometry.points(from: length - b, to: length - a).reversed().map(Point.init)
        }
    }
}
