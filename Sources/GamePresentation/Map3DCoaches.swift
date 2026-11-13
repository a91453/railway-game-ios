import Foundation
import GameCore

// Decision 708: the real intercity coaches in the 3D map. The world's coach
// stops (``GameWorld/coachStops``, decision 706) each get a roadside coach
// stop beside the road nearest them, and the real routes' coaches
// (``RealCoaches``) run along their shapes as their timetables say: each
// departure of the game's weekday leaves its first stop at its minute and
// reaches each stop at the stop's minute, standing a moment at the stops on
// the way.
//
// Laid once for a scene (``init(world:scene:coaches:)``, off the main
// actor: ``Layer``), then asked each frame (``add(to:pack:second:eye:reach:)``):
// no state kept between frames, nothing saved, GameCore only read. The
// coaches are put on the scene's drawn roads (the motorways' carriageways
// too), at the roads' heights, and are not drawn where no road is drawn
// under a long stretch of their shape (a tunnel).

/// The real coaches and the coach stops laid in a 3D scene.
public struct Map3DCoaches: Sendable {
    // MARK: Models

    /// A livery's model name (``Map3DCoachBus/model(livery:far:)``'s).
    public static func name(_ livery: Map3DCoachLivery, far: Bool = false) -> String {
        "life-coachBus-" + livery.rawValue + (far ? "-far" : "-near")
    }

    /// The liveries the routes' coaches wear (not the tourist shuttle's).
    public static let liveries: [Map3DCoachLivery] = Map3DCoachLivery.allCases.filter { !$0.isTourism }

    /// Every model the 3D map draws for the coaches
    /// (``Map3DModelPack/standard``): each livery near, then far, then the
    /// coach stop near and far.
    public static var drawn: [Map3DModelPack.Model] {
        var made: [Map3DModelPack.Model] = []
        for far in [false, true] {
            for livery in liveries { made.append(Map3DCoachBus.model(livery: livery, far: far)) }
        }
        for far in [false, true] { made.append(Map3DCoachStop.model(far: far)) }
        return made
    }

    /// The livery of a route run by `operators`: the same for every route
    /// of a company, so a company's coaches are told apart from another's
    /// at a glance. The groups are the game's own (decision 593): no
    /// company's real paint or mark.
    public static func livery(of operators: [String]) -> Int {
        guard let first = operators.first else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in first.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash % UInt32(liveries.count))
    }

    // MARK: Limits

    /// Within this of the eye a coach is drawn whole (decision 417's far
    /// models come nearer on a weak device: `reach`).
    public static let nearReach: Float = 260
    /// Within this the far model; beyond, nothing.
    public static let farReach: Float = 2_400
    /// The most coaches drawn whole and far in a frame: 8 × 2,884 and
    /// 48 × 1,586 triangles at most, about 100,000.
    public static let mostNear = 8
    public static let mostFar = 48
    /// A coach stop whole, its far model, nothing.
    public static let stopNearReach: Float = 500
    public static let stopFarReach: Float = 3_500

    // MARK: Timetable

    /// When a coach is where along its route: the stops' minutes and
    /// metres, the coach going evenly from one to the next and standing
    /// ``dwell`` at each on the way. TDX's minutes are whole, so several
    /// stops can share one; of those only the first is a knot, and the
    /// coach passes the others on its even way to the next.
    public struct Timing: Sendable, Equatable {
        /// Minutes a coach stands at a stop on its way (at most a third
        /// of the time to the next).
        public static let dwell = 0.5

        public let minutes: [Double]
        public let metres: [Double]

        public init(stopMinutes: [Int], stopMetres: [Int]) {
            var minutes: [Double] = [], metres: [Double] = []
            for (minute, metre) in zip(stopMinutes, stopMetres) {
                if let last = minutes.last, Double(minute) <= last {
                    continue
                }
                minutes.append(Double(minute))
                metres.append(max(Double(metre), metres.last ?? 0))
            }
            // The last stop is where the run ends, whatever shared its minute.
            if let end = stopMetres.last, let last = metres.indices.last, metres.count > 1 { metres[last] = max(Double(end), metres[last - 1]) }
            self.minutes = minutes
            self.metres = metres
        }

        /// Minutes from the first stop to the last.
        public var runMinutes: Double { minutes.count > 1 ? minutes[minutes.count - 1] - minutes[0] : 0 }

        private func stand(at knot: Int) -> Double {
            knot == 0 ? 0 : min(Self.dwell, (minutes[knot + 1] - minutes[knot]) / 3)
        }

        /// How far along the route a coach is `elapsed` minutes after it
        /// left its first stop; `nil` before it leaves and after it
        /// arrives.
        public func metres(after elapsed: Double) -> Double? {
            guard minutes.count > 1, elapsed >= 0, elapsed <= runMinutes else { return nil }
            let time = minutes[0] + elapsed
            var low = 0, high = minutes.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if minutes[middle] <= time { low = middle } else { high = middle }
            }
            let wait = stand(at: low), span = minutes[high] - minutes[low] - wait
            let share = span > 0 ? min(max((time - minutes[low] - wait) / span, 0), 1) : 1
            return metres[low] + (metres[high] - metres[low]) * share
        }

        /// The minutes after leaving at which a coach is first `distance`
        /// along (the inverse of ``metres(after:)``).
        public func minutes(at distance: Double) -> Double {
            guard minutes.count > 1 else { return 0 }
            var low = 0, high = metres.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if metres[middle] <= distance { low = middle } else { high = middle }
            }
            let wait = stand(at: low), span = minutes[high] - minutes[low] - wait
            let length = metres[high] - metres[low]
            let share = length > 0 ? min(max((distance - metres[low]) / length, 0), 1) : 0
            return minutes[low] - minutes[0] + (share > 0 ? wait + span * share : 0)
        }
    }

    // MARK: What is laid

    /// A stretch of a route inside the scene.
    struct Piece: Sendable {
        /// How far along the route each point is, ascending.
        let metres: [Double]
        let points: [Map3DPoint]
        /// Whether the way to each point (from the one before) is not
        /// drawn: no road is drawn under it.
        let hidden: [Bool]
        /// The minutes after leaving at which a coach comes onto it and
        /// goes off it.
        let enters: Double
        let leaves: Double
        let minimum: (x: Float, z: Float)
        let maximum: (x: Float, z: Float)

        func boxDistance(to p: Map3DPoint) -> Float {
            let dx = max(minimum.x - p.x, 0, p.x - maximum.x), dz = max(minimum.z - p.z, 0, p.z - maximum.z)
            return (dx * dx + dz * dz).squareRoot()
        }

        /// The point `distance` along the route and the level way ahead
        /// there; `nil` off the piece or where it is hidden.
        func place(at distance: Double) -> (point: Map3DPoint, along: Map3DPoint)? {
            guard let first = metres.first, let last = metres.last, distance >= first, distance <= last else { return nil }
            var low = 0, high = metres.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if metres[middle] <= distance { low = middle } else { high = middle }
            }
            guard !hidden[high] else { return nil }
            let a = points[low], b = points[high]
            let span = metres[high] - metres[low]
            let share = span > 0 ? Float((distance - metres[low]) / span) : 0
            let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized ?? Map3DPoint(1, 0, 0)
            return (a + (b - a) * share, along)
        }
    }

    /// One route direction with a stretch in the scene.
    struct Line: Sendable {
        let id: String
        let livery: Int
        let timing: Timing
        /// The departures of each day, Monday first: minutes after
        /// midnight, ascending.
        let departures: [[Int]]
        let pieces: [Piece]
    }

    /// A coach stop: where its model stands and the way its road runs.
    public struct Stop: Sendable, Equatable {
        public let id: Int
        public let name: String
        public let point: Map3DPoint
        public let forward: Map3DPoint
    }

    /// A scene and a world's coach stops, as far as the coaches need to
    /// tell one laying from another.
    public struct Key: Hashable, Sendable {
        let originX: Double
        let originY: Double
        let region: WorldRegion
        let lanes: Int
        let stops: Int

        public init(world: GameWorld, scene: Map3DScene) {
            originX = scene.originX
            originY = scene.originY
            region = scene.region
            lanes = scene.streetLife.lanes.count
            stops = world.coachStops.count
        }
    }

    let lines: [Line]
    public let stops: [Stop]
    public let key: Key

    /// Whether there is anything to draw.
    public var isEmpty: Bool { lines.isEmpty && stops.isEmpty }
    /// How many route directions have a stretch in the scene.
    public var routeCount: Int { lines.count }

    // MARK: Laying

    /// The most a route's way is drawn straight between two points.
    static let step: Double = 20
    /// How far a point of a route's shape is moved onto a drawn road.
    static let snapReach: Float = 28
    /// A stretch of a route with no drawn road under it for longer than
    /// this is not drawn (a tunnel; a road the map does not draw).
    static let hiddenFrom: Double = 60
    /// How far from a coach stop its road is looked for.
    static let stopReach: Float = 90
    /// From the road's edge to the coach stop's middle.
    static let stopSetback: Float = 0.6
    /// How far along its street a stop is moved to stand clear of the
    /// buildings, and by what steps.
    static let stopSearch: Float = 120
    static let stopSearchStep: Float = 15

    /// The coach stops of `world` and the routes of `coaches` in `scene`;
    /// nothing off a real-world map or in a world with no coach stops
    /// (decision 706: such a map has no coaches).
    public init(world: GameWorld, scene: Map3DScene, coaches: RealCoaches?) {
        key = Key(world: world, scene: scene)
        guard !world.coachStops.isEmpty, let frame = RealWorldFrame(world: world) else {
            lines = []
            stops = []
            return
        }
        let region = scene.region
        let a = scene.point(worldX: region.minX, worldY: region.minY, height: 0), b = scene.point(worldX: region.maxX, worldY: region.maxY, height: 0)
        let low = (x: min(a.x, b.x), z: min(a.z, b.z)), high = (x: max(a.x, b.x), z: max(a.z, b.z))
        let roads = Roads(lanes: scene.streetLife.lanes)

        // The stops, each beside its road.
        var stops: [Stop] = []
        for stop in world.coachStops {
            let at = scene.point(worldX: Double(stop.point.x), worldY: Double(stop.point.y), height: 0)
            guard at.x >= low.x, at.x <= high.x, at.z >= low.z, at.z <= high.z else { continue }
            if let first = roads.kerb(near: at, within: Self.stopReach) {
                // The nearest stretch of kerb with no building, water or
                // street under the stop: along the street both ways and on
                // either side; the nearest kerb itself when there is none.
                let drawn = scene.drawnWater(round: at, radius: Self.stopReach + Self.stopSearch + Map3DCoachStop.length)
                func place(_ road: (foot: Map3DPoint, along: Map3DPoint, right: Map3DPoint, half: Float)) -> Map3DPoint {
                    road.foot + road.right * (road.half + Self.stopSetback + Map3DCoachStop.depth / 2)
                }
                func clear(_ road: (foot: Map3DPoint, along: Map3DPoint, right: Map3DPoint, half: Float)) -> Bool {
                    let middle = place(road)
                    for along in stride(from: -Map3DCoachStop.length / 2, through: Map3DCoachStop.length / 2, by: Map3DCoachStop.length / 6) {
                        for aside: Float in [-Map3DCoachStop.depth / 2, 0, Map3DCoachStop.depth / 2] {
                            let p = middle + road.along * along + road.right * aside
                            if drawn.isBuilt(x: p.x, z: p.z) || drawn.isWater(x: p.x, z: p.z) { return false }
                            if aside >= 0, let other = roads.kerb(near: p, within: 12), (other.foot - p).length < other.half + 0.3 { return false }
                        }
                    }
                    return true
                }
                var road = first
                search: if !clear(first) {
                    for step in 1...Int(Self.stopSearch / Self.stopSearchStep) {
                        for way: Float in [1, -1] {
                            for side: Float in [1, -1] {
                                let probe = first.foot + first.along * (way * Float(step) * Self.stopSearchStep) + first.right * (side * (first.half + 2))
                                guard let found = roads.kerb(near: probe, within: 10), clear(found) else { continue }
                                road = found
                                break search
                            }
                        }
                    }
                }
                stops.append(Stop(id: stop.id, name: stop.name, point: place(road), forward: road.along))
            } else {
                let height = scene.drawnGround.height(x: at.x, z: at.z, world: world)
                stops.append(Stop(id: stop.id, name: stop.name, point: Map3DPoint(at.x, height, at.z), forward: Map3DPoint(1, 0, 0)))
            }
        }
        self.stops = stops

        // The routes, each stretch inside the scene on its road.
        var lines: [Line] = []
        for route in coaches?.routes ?? [] {
            let shape = route.shape
            guard shape.count >= 2 else { continue }
            let flat = shape.map { coordinate -> Map3DPoint in
                let world = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return scene.point(worldX: world.x, worldY: world.y, height: 0)
            }
            guard flat.contains(where: { $0.x >= low.x - 2_000 && $0.x <= high.x + 2_000 && $0.z >= low.z - 2_000 && $0.z <= high.z + 2_000 })
                || Self.crosses(flat, low: low, high: high) else { continue }
            var along: [Double] = [0]
            along.reserveCapacity(shape.count)
            for index in 1..<shape.count { along.append(along[index - 1] + shape[index - 1].distance(to: shape[index])) }
            let timing = Timing(stopMinutes: route.stops.map(\.minutes), stopMetres: route.stops.map(\.metres))
            guard timing.minutes.count > 1 else { continue }
            var pieces: [Piece] = []
            for run in Self.runs(flat, metres: along, low: low, high: high) {
                if let piece = Self.piece(run, timing: timing, roads: roads) { pieces.append(piece) }
            }
            guard !pieces.isEmpty else { continue }
            lines.append(Line(id: route.id, livery: Self.livery(of: route.operators), timing: timing,
                              departures: (0..<7).map { route.departures(on: $0) }, pieces: pieces))
        }
        self.lines = lines
    }

    /// Whether the line through `points` crosses the box.
    static func crosses(_ points: [Map3DPoint], low: (x: Float, z: Float), high: (x: Float, z: Float)) -> Bool {
        for index in 1..<points.count where clip(points[index - 1], points[index], low: low, high: high) != nil { return true }
        return false
    }

    /// The shares (0–1) of the way from `a` to `b` inside the box, or `nil`.
    static func clip(_ a: Map3DPoint, _ b: Map3DPoint, low: (x: Float, z: Float), high: (x: Float, z: Float)) -> (from: Float, to: Float)? {
        var from: Float = 0, to: Float = 1
        for (start, change, least, most) in [(a.x, b.x - a.x, low.x, high.x), (a.z, b.z - a.z, low.z, high.z)] {
            if change == 0 {
                if start < least || start > most { return nil }
                continue
            }
            var enter = (least - start) / change, leave = (most - start) / change
            if enter > leave { swap(&enter, &leave) }
            from = max(from, enter)
            to = min(to, leave)
            if from > to { return nil }
        }
        return (from, to)
    }

    /// The stretches of the line through `points` (each `metres` along)
    /// inside the box, a point every ``step`` at most.
    static func runs(_ points: [Map3DPoint], metres: [Double], low: (x: Float, z: Float), high: (x: Float, z: Float))
        -> [[(point: Map3DPoint, metres: Double)]] {
        var runs: [[(point: Map3DPoint, metres: Double)]] = []
        var open: [(point: Map3DPoint, metres: Double)] = []
        func close() {
            if open.count >= 2 { runs.append(open) }
            open = []
        }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            guard let inside = clip(a, b, low: low, high: high) else {
                close()
                continue
            }
            let length = metres[index] - metres[index - 1]
            if inside.from > 0 { close() }
            let first = Double(inside.from), last = Double(inside.to)
            let steps = max(1, Int(((last - first) * length / step).rounded(.up)))
            for part in (open.isEmpty ? 0 : 1)...steps {
                let share = first + (last - first) * Double(part) / Double(steps)
                open.append((a + (b - a) * Float(share), metres[index - 1] + length * share))
            }
            if inside.to < 1 { close() }
        }
        close()
        return runs
    }

    /// `run` on the scene's roads: each point on the road under it, at
    /// the road's height; a long stretch with no road under it hidden.
    static func piece(_ run: [(point: Map3DPoint, metres: Double)], timing: Timing, roads: Roads) -> Piece? {
        var points = run.map(\.point)
        let metres = run.map(\.metres)
        var found = Array(repeating: false, count: run.count)
        var lane: Int32?
        for index in run.indices {
            let ahead = run[min(index + 1, run.count - 1)].point - run[max(index - 1, 0)].point
            guard let along = Map3DPoint(ahead.x, 0, ahead.z).normalized,
                  let road = roads.nearest(to: run[index].point, along: along, within: snapReach, last: lane) else {
                lane = nil
                continue
            }
            points[index] = road.point
            found[index] = true
            lane = road.lane
        }
        guard found.contains(true) else { return nil }
        // The stretches off every road: hidden when long, else straight
        // between the roads at either end.
        var hidden = Array(repeating: false, count: run.count)
        var index = 0
        while index < run.count {
            guard !found[index] else {
                index += 1
                continue
            }
            var end = index
            while end < run.count, !found[end] { end += 1 }
            let before = index > 0 ? index - 1 : nil, after = end < run.count ? end : nil
            let length = metres[after ?? run.count - 1] - metres[before ?? 0]
            if length > hiddenFrom {
                for off in index...min(end, run.count - 1) { hidden[off] = true }
            }
            for off in index..<end {
                let height: Float
                if let before, let after {
                    let share = Float((metres[off] - metres[before]) / max(metres[after] - metres[before], 0.001))
                    height = points[before].y + (points[after].y - points[before].y) * share
                } else {
                    height = points[before ?? after ?? 0].y
                }
                points[off].y = height
            }
            index = end
        }
        // Smoothed across the lanes, so a coach does not turn sharply
        // where its way goes from one road's line to another's.
        for _ in 0..<2 {
            let before = points
            for index in 1..<max(points.count - 1, 1) {
                points[index].x = (before[index - 1].x + 2 * before[index].x + before[index + 1].x) / 4
                points[index].z = (before[index - 1].z + 2 * before[index].z + before[index + 1].z) / 4
            }
        }
        return Piece(metres: metres, points: points, hidden: hidden,
                     enters: timing.minutes(at: metres[0]), leaves: timing.minutes(at: metres[metres.count - 1]),
                     minimum: (points.map(\.x).min() ?? 0, points.map(\.z).min() ?? 0),
                     maximum: (points.map(\.x).max() ?? 0, points.map(\.z).max() ?? 0))
    }

    /// The scene's roads' pieces, found by square.
    struct Roads: Sendable {
        struct Piece: Sendable {
            let a: Map3DPoint
            let b: Map3DPoint
            let half: Float
            let twoWay: Bool
            let motorway: Bool
            let lane: Int32
        }

        private var pieces: [Piece] = []
        private var squares: [Int64: [Int32]] = [:]
        private static let square: Float = 64

        private static func key(_ column: Int, _ row: Int) -> Int64 { Int64(column) &* 4_000_037 &+ Int64(row) }
        private static func cell(_ value: Float) -> Int { Int((value / square).rounded(.down)) }

        init(lanes: [Map3DStreetLife.Lane]) {
            for (number, lane) in lanes.enumerated() {
                let line = lane.path.points
                for index in 1..<line.count {
                    let a = line[index - 1], b = line[index]
                    pieces.append(Piece(a: a, b: b, half: lane.half, twoWay: lane.twoWay, motorway: !lane.scooters, lane: Int32(number)))
                    for column in Self.cell(min(a.x, b.x))...Self.cell(max(a.x, b.x)) {
                        for row in Self.cell(min(a.z, b.z))...Self.cell(max(a.z, b.z)) {
                            squares[Self.key(column, row), default: []].append(Int32(pieces.count - 1))
                        }
                    }
                }
            }
        }

        private func each(near point: Map3DPoint, within reach: Float, _ body: (Piece, _ foot: Map3DPoint, _ off: Float, _ way: Map3DPoint) -> Void) {
            for column in Self.cell(point.x - reach)...Self.cell(point.x + reach) {
                for row in Self.cell(point.z - reach)...Self.cell(point.z + reach) {
                    for number in squares[Self.key(column, row)] ?? [] {
                        let piece = pieces[Int(number)]
                        let span = Map3DPoint(piece.b.x - piece.a.x, 0, piece.b.z - piece.a.z)
                        let length = span.length
                        guard length > 0.01 else { continue }
                        let way = span * (1 / length)
                        let t = min(max(((point.x - piece.a.x) * way.x + (point.z - piece.a.z) * way.z) / length, 0), 1)
                        let foot = piece.a + (piece.b - piece.a) * t
                        let off = Map3DPoint(point.x - foot.x, 0, point.z - foot.z).length
                        if off <= reach { body(piece, foot, off, way) }
                    }
                }
            }
        }

        /// Where a coach going `along` near `point` drives: on the nearest
        /// road within `reach` that runs its way, to the right of the
        /// middle of a road with traffic both ways; the lane it was on
        /// (`last`) counts 6 m nearer, so it keeps to it.
        func nearest(to point: Map3DPoint, along: Map3DPoint, within reach: Float, last: Int32?) -> (point: Map3DPoint, lane: Int32)? {
            var best: (cost: Float, point: Map3DPoint, lane: Int32)?
            each(near: point, within: reach) { piece, foot, off, way in
                let agreement = way.x * along.x + way.z * along.z
                guard piece.twoWay ? abs(agreement) > 0.5 : agreement > 0.5 else { return }
                let cost = off + (piece.lane == last ? 0 : 6)
                guard best.map({ cost < $0.cost }) ?? true else { return }
                var place = foot
                if piece.twoWay {
                    let ahead = agreement < 0 ? way * -1 : way
                    place = foot + Map3DPoint(-ahead.z, 0, ahead.x) * max(piece.half * 0.5, 1.2)
                }
                best = (cost, place, piece.lane)
            }
            return best.map { ($0.point, $0.lane) }
        }

        /// The edge of the street nearest `point` (not a motorway's): the
        /// point on its middle, the way it runs and the way from its
        /// middle to the side `point` is on.
        func kerb(near point: Map3DPoint, within reach: Float) -> (foot: Map3DPoint, along: Map3DPoint, right: Map3DPoint, half: Float)? {
            var best: (off: Float, foot: Map3DPoint, along: Map3DPoint, right: Map3DPoint, half: Float)?
            each(near: point, within: reach) { piece, foot, off, way in
                guard !piece.motorway, best.map({ off < $0.off }) ?? true else { return }
                var right = Map3DPoint(-way.z, 0, way.x), along = way
                // The side the stop is on; on the road's line itself, the
                // right of the way it is drawn.
                if (point.x - foot.x) * right.x + (point.z - foot.z) * right.z < -0.5 {
                    right = right * -1
                    along = along * -1
                }
                best = (off, foot, along, right, piece.half)
            }
            return best.map { ($0.foot, $0.along, $0.right, $0.half) }
        }
    }

    // MARK: A frame

    /// One coach on the road now.
    public struct Coach: Sendable {
        public let route: String
        /// The minute of the day it left at, and the game day.
        public let departure: Int
        public let day: Int64
        public let livery: Int
        public let point: Map3DPoint
        public let along: Map3DPoint
    }

    /// Monday-first weekday (0 Monday to 6 Sunday) of game day `day`.
    public static func weekday(ofDay day: Int64) -> Int {
        (StationDemand.weekday(ofDay: day) + 6) % 7
    }

    /// The coaches on the scene's roads at game second `second`, within
    /// `reach` metres of `eye` on the level (all of them when `nil`).
    public func coaches(second: Double, near eye: Map3DPoint? = nil, within reach: Float = .infinity) -> [Coach] {
        let day = Int64((second / Double(GameTime.secondsPerDay)).rounded(.down))
        let minute = (second - Double(day) * Double(GameTime.secondsPerDay)) / 60
        var found: [Coach] = []
        for line in lines {
            for piece in line.pieces {
                if let eye, piece.boxDistance(to: eye) > reach { continue }
                // Today's departures, and yesterday's still on the road.
                for back in 0...1 {
                    let now = minute + Double(back) * 24 * 60
                    let list = line.departures[Self.weekday(ofDay: day - Int64(back))]
                    let earliest = now - piece.leaves, latest = now - piece.enters
                    guard latest >= 0, !list.isEmpty else { continue }
                    var low = 0, high = list.count
                    while low < high {
                        let middle = (low + high) / 2
                        if Double(list[middle]) < earliest { low = middle + 1 } else { high = middle }
                    }
                    var index = low
                    while index < list.count, Double(list[index]) <= latest {
                        if let metres = line.timing.metres(after: now - Double(list[index])), let place = piece.place(at: metres) {
                            found.append(Coach(route: line.id, departure: list[index], day: day - Int64(back), livery: line.livery,
                                               point: place.point, along: place.along))
                        }
                        index += 1
                    }
                }
            }
        }
        return found
    }

    /// Adds the coach stops and the coaches at game second `second` to
    /// `frame`, as seen from `eye`: the nearest ``mostNear`` coaches
    /// within ``nearReach`` whole, the next ``mostFar`` within
    /// ``farReach`` as their far models.
    public func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, second: Double, eye: Map3DPoint, reach: Float = 1) {
        guard !isEmpty else { return }
        if let near = pack.index(of: Map3DCoachStop.name()), let far = pack.index(of: Map3DCoachStop.name(far: true)) {
            for stop in stops {
                let away = (stop.point - eye).length
                guard away < Self.stopFarReach else { continue }
                frame.instances.append(.prop(away < Self.stopNearReach * reach ? near : far, at: stop.point, forward: stop.forward, scale: 1, tint: 0xFFFFFF))
            }
        }
        var models: [(near: Int, far: Int)] = []
        for livery in Self.liveries {
            guard let near = pack.index(of: Self.name(livery)), let far = pack.index(of: Self.name(livery, far: true)) else { return }
            models.append((near, far))
        }
        var seen: [(away: Float, coach: Coach)] = []
        for coach in coaches(second: second, near: eye, within: Self.farReach) {
            let away = (coach.point - eye).length
            if away < Self.farReach { seen.append((away, coach)) }
        }
        seen.sort { $0.away < $1.away }
        var whole = 0
        for (away, coach) in seen.prefix(Self.mostNear + Self.mostFar) {
            let near = away < Self.nearReach * reach && whole < Self.mostNear
            if near { whole += 1 }
            let pair = models[coach.livery % models.count]
            frame.instances.append(.prop(near ? pair.near : pair.far, at: coach.point, forward: coach.along, scale: 1, tint: 0xFFFFFF))
        }
    }
}

extension Map3DCoaches {
    /// When the coaches are laid and which laying is kept (as
    /// ``Map3DBuses/Layer``): asked once a frame, it starts a laying off
    /// the main actor and hands it out once done, the one laid before for
    /// the same scene meanwhile.
    @MainActor
    public final class Layer {
        private(set) var laid: Map3DCoaches?
        private var laying: (key: Key, serial: Int, task: Task<Void, Never>)?
        private var started = 0

        public init() {}

        public func coaches(world: GameWorld, in scene: Map3DScene, routes: RealCoaches?) -> Map3DCoaches? {
            let key = Key(world: world, scene: scene)
            if let laid, laid.key == key {
                return laid
            }
            if laying?.key != key {
                laying?.task.cancel()
                started += 1
                let serial = started
                let task = Task.detached(priority: .utility) { [weak self] in
                    let coaches = Map3DCoaches(world: world, scene: scene, coaches: routes)
                    guard !Task.isCancelled else { return }
                    await self?.finish(coaches, serial: serial)
                }
                laying = (key, serial, task)
            }
            return nil
        }

        private func finish(_ coaches: Map3DCoaches, serial: Int) {
            guard laying?.serial == serial else { return }
            laid = coaches
            laying = nil
        }
    }
}

/// Decision 708: the roadside coach station (decision 591's parts put
/// together at a size that stands beside a street): a raised platform
/// along the kerb, a long flat canopy on round columns with benches under
/// it, a small flat-roofed ticket and waiting house with a glazed front at
/// one end and a tall dark name pylon at the other. Its marks are plain
/// blocks of colour: no company's name.
public enum Map3DCoachStop {
    public static let length: Float = 26
    /// From the kerb to its back.
    public static let depth: Float = 5.6
    /// The canopy's and the house's roofs: a green no railway station's
    /// canopy has, so a coach station is told from one from above.
    static let roof = Map3DPalette.shopAwnings[0]

    public static func name(far: Bool = false) -> String { "coach-stop-roadside" + (far ? "-far" : "-near") }

    /// Its model: +x along the road, the kerb on its left (z = −depth / 2
    /// inside, the back at +depth / 2); the ground at 0.
    public static func model(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        let white = Map3DPalette.tileWhite, concrete = Map3DPalette.counters[2]
        let dark = Map3DPalette.playerRim, glass = Map3DPalette.glazing, deck = Map3DPalette.plaza
        let amber = Map3DPalette.platformEdge, bench = Map3DPalette.counters[1]
        let kerb = -depth / 2, back = depth / 2
        // The platform and its kerb line.
        b.box(0, 0, 0, length, depth, 0.22, deck)
        b.box(0, 0.22, kerb + 0.2, length, 0.4, 0.03, amber)
        // The ticket and waiting house at the rear end: white walls, a
        // glazed front to the road, a flat roof that oversails.
        let house: Float = -8.6, houseLength: Float = 7.2, houseDepth: Float = 3.8, eaves: Float = 3.5
        let houseMiddle = back - 0.3 - houseDepth / 2
        b.box(house, 0.22, houseMiddle, houseLength, houseDepth, eaves - 0.22, white)
        b.box(house, 0.9, houseMiddle - houseDepth / 2 - 0.03, houseLength - 1.0, 0.06, 1.9, glass)
        b.box(house, eaves, houseMiddle - 0.2, houseLength + 1.0, houseDepth + 1.4, 0.3, roof)
        // A white fascia under each roof's edge, so the roof is not a slab.
        b.box(house, eaves - 0.16, houseMiddle - 0.2, houseLength + 1.3, houseDepth + 1.7, 0.16, white)
        // The house's roof sign, facing the road: a white board on a dark
        // band with an amber stripe, no words.
        b.box(house, eaves + 0.3, houseMiddle - houseDepth / 2 - 0.5, houseLength - 0.6, 0.16, 0.2, dark)
        b.box(house, eaves + 0.5, houseMiddle - houseDepth / 2 - 0.5, houseLength - 0.6, 0.2, 1.0, white)
        b.box(house, eaves + 1.5, houseMiddle - houseDepth / 2 - 0.5, houseLength - 0.6, 0.24, 0.16, amber)
        if !far {
            // Its door and the ticket window's sill.
            b.box(house + 2.4, 0.22, houseMiddle - houseDepth / 2 - 0.05, 1.1, 0.06, 2.3, dark)
            b.box(house - 1.0, 0.85, houseMiddle - houseDepth / 2 - 0.2, 3.0, 0.3, 0.08, concrete)
        }
        // The canopy from the house to the front, lower than the house's
        // roof, on round columns along its back and its kerb side.
        let from: Float = house + houseLength / 2 + 0.2, to: Float = 10.2, top: Float = 3.0
        let middle = (from + to) / 2, span = to - from
        b.box(middle, top, 0.1, span, depth - 0.6, 0.26, roof)
        b.box(middle, top - 0.14, 0.1, span + 0.3, depth - 0.3, 0.14, white)
        for x in stride(from: from + 0.6, through: to - 0.6, by: (span - 1.2) / 3) {
            for z: Float in [kerb + 1.5, back - 0.5] { b.cylinder(x, 0.22, z, radius: 0.17, height: top - 0.22, color: concrete, sides: far ? 6 : 10) }
        }
        if !far {
            // Benches along the back, and the platform's hanging sign.
            for x in stride(from: from + 2.0, through: to - 2.0, by: 3.4) {
                b.box(x, 0.22, back - 1.0, 2.6, 0.5, 0.45, bench)
                b.box(x, 0.67, back - 0.78, 2.6, 0.08, 0.42, bench)
            }
            b.box(middle, top - 0.75, kerb + 1.5, 2.6, 0.12, 0.55, dark)
            b.box(middle, top - 0.32, kerb + 1.5, 2.6, 0.14, 0.1, amber)
            b.box(from + 1.0, 0.22, back - 2.4, 0.7, 0.6, 1.7, white)
        }
        // The name pylon at the front end: tall and dark, plain marks.
        let pylon: Float = 11.9
        b.box(pylon, 0.22, back - 1.3, 0.5, 1.7, 6.2, dark)
        b.box(pylon, 6.42, back - 1.3, 0.56, 1.76, 0.5, amber)
        for (index, height) in [5.1, 4.1, 3.1, 2.1].enumerated() where !far || index < 2 {
            for side: Float in [-0.26, 0.26] { b.box(pylon + side, Float(height), back - 1.3, 0.03, 0.9, 0.7, white) }
        }
        return .flat(named: name(far: far), from: b.mesh)
    }
}
