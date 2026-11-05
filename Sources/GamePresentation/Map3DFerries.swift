import Foundation
import GameCore

// Decision 585 PR-3 (FERRY3): the player's ferries in the 3D map. Each
// pier (``Map3DFerry/pier(far:)``) stands at its cell's edge on the side of
// the water nearest the way to the next pier, its pontoon out on the water;
// the boats (``Map3DFerry/Boat``) sail straight from one pier's berth to the
// next as GameCore's timetable runs them (``FerryRoute/headway``, the runs
// of a timetable), ``FerryRoute/dockMinutes`` at each pier. A passenger
// boat turns round at the ends while it lies there; the double-ended ferry
// sails back stern first. Boats with no sailing lie beside the first pier.
// Decision 358's rule for what is far, as the cable cars (decision 575 續).
//
// Laid once for a world's ferries and a scene (``init(world:scene:)``),
// then asked each frame (``frame(second:eye:target:pack:reach:)``): no
// state kept between frames. GameCore is only read.

/// Decision 585 PR-4 (FERRYFOLLOW): one boat of a player's ferry route:
/// the same boat from one moment to the next. A day's departures go to
/// the boats in turn (``Map3DFerries/Sailing/number``).
public struct FerryBoatID: Hashable, Sendable {
    public let route: FerryRouteID
    public let number: Int

    public init(route: FerryRouteID, number: Int) {
        self.route = route
        self.number = number
    }
}

/// The player's ferries laid in a 3D scene.
public struct Map3DFerries: Sendable {
    /// Where a boat is in one sailing (``stage(atMinute:legMetres:)``).
    public enum Stage: Equatable, Sendable {
        /// Crossing leg `leg` (pier `leg` to `leg + 1`), `share` (0–1) of
        /// the way, out from the first pier or back to it.
        case sailing(leg: Int, share: Double, outbound: Bool)
        /// Lying at pier `pier`, `share` (0–1) of its
        /// ``FerryRoute/dockMinutes``, on the way out or back. At the
        /// last pier on the way out and the first on the way back it
        /// turns round (a passenger boat).
        case docked(pier: Int, share: Double, outbound: Bool)
    }

    /// One pier: the pier model's origin (its waterline) and the way its
    /// +x points out over the water; the boats' berth off its pontoon.
    struct Pier: Sendable {
        let origin: Map3DPoint
        let out: Map3DPoint
        let berth: Map3DPoint
    }

    struct Line: Sendable {
        let id: FerryRouteID
        let route: FerryRoute
        let boat: Map3DFerry.Boat
        let piers: [Pier]
    }

    let lines: [Line]
    let world: GameWorld
    /// The ferries it was laid from, to know when to lay them again.
    public let routes: [FerryRoute]

    /// Within this of the eye a boat or pier is drawn whole (decision
    /// 417's far models come nearer on a weak device: `reach`).
    public static let nearReach: Float = 350
    /// Within this the far models; beyond, nothing.
    public static let farReach: Float = 2_000
    /// The most boats drawn whole and far in a frame: 12 × 6,304 and
    /// 40 × 2,344 triangles at most, about 170,000.
    public static let mostNearBoats = 12
    public static let mostFarBoats = 40
    /// The most idle boats drawn lying beside the first pier.
    public static let mostIdle = 4
    /// The water between a berthed boat's end and the pontoon's, metres.
    public static let berthGap: Float = 1
    /// Between two idle boats lying side by side, metres.
    public static let idleGap: Float = 2.5
    /// The water's surface over the scene's ground there (the scene's
    /// water lies that much over it, ``Map3DScene``).
    static let waterLift: Float = 0.05

    public init(world: GameWorld, scene: Map3DScene) {
        self.world = world
        routes = world.ferryRoutes
        func flat(_ plan: PlanPoint) -> Map3DPoint {
            let p = scene.point(worldX: Double(plan.x), worldY: Double(plan.y), height: 0)
            return Map3DPoint(p.x, 0, p.z)
        }
        lines = world.ferryRoutes.compactMap { route in
            guard route.piers.count >= 2 else { return nil }
            let boat = Map3DFerry.Boat.drawn(forMetres: route.metres)
            let piers = route.piers.indices.map { index -> Pier in
                let cell = route.piers[index]
                let other = route.piers[index == route.piers.count - 1 ? index - 1 : index + 1]
                let middle = flat(cell.middle)
                let edge: Map3DPoint, out: Map3DPoint
                if let shore = Self.shore(from: middle, toward: flat(other.middle), boat: boat,
                                          in: scene.drawnWater(round: middle, radius: Self.shoreReach + Self.clearWay + 60)) {
                    (edge, out) = shore
                } else {
                    let side = Self.waterSide(of: cell, toward: other, in: world)
                    let half = Land.cellLength / 2
                    edge = flat(PlanPoint(x: cell.middle.x + Int64(side.column) * half, y: cell.middle.y + Int64(side.row) * half))
                    out = Map3DPoint(edge.x - middle.x, 0, edge.z - middle.z).normalized ?? Map3DPoint(1, 0, 0)
                }
                var origin = edge + out * Map3DFerry.pierOffshore
                origin.y = scene.drawnGround.height(x: origin.x, z: origin.z, world: world) + Self.waterLift
                var berth = origin + out * (Map3DFerry.pontoonReach + Self.berthGap + boat.length / 2)
                berth.y = origin.y
                return Pier(origin: origin, out: out, berth: berth)
            }
            return Line(id: route.id, route: route, boat: boat, piers: piers)
        }
    }

    /// Whether there is anything to draw.
    public var isEmpty: Bool { lines.isEmpty }

    /// How far from a pier's cell its shore is looked for, metres, and
    /// in what steps.
    static let shoreReach: Float = 320
    static let shoreStep: Float = 2

    /// How far past a berth toward the next pier the water must be clear
    /// for a shore to be taken, metres: out of a basin behind a quay the
    /// boats would sail over the quay.
    static let clearWay: Float = 60

    /// The shore the pier at `middle` (its cell's middle) stands out
    /// from, `toward` being the next pier's, for boats of kind `boat`:
    /// of 16 ways round, those not turned from `toward`, each place
    /// along it where the land drawn gives way to water, the nearest
    /// whose pontoon lies on the water and whose boats leave the berth
    /// toward `toward` over ``clearWay`` of water, a way more toward
    /// `toward` counting nearer (up to 5/3 times, so the pier faces the
    /// crossing); with none clear, the nearest. The game's 64 m cells and
    /// the shores drawn differ (a pier cell beside a water cell can lie
    /// 100 m and more inland of the real harbour's quay), so the water
    /// drawn decides. From a middle drawn as water, the shore behind it
    /// on the way from `toward`. `nil` with no shore within
    /// ``shoreReach``.
    ///
    /// Water with a building of the city over it counts as land: the
    /// city's real buildings stand on the water drawn where a terminal
    /// or a shed stands on a quay or over the water (Gushan, screenshot
    /// run 41927167376), and a boat lying there would cut through one. A
    /// berth is taken only with the boat's turning circle (half its
    /// diagonal round the berth) all open water.
    static func shore(from middle: Map3DPoint, toward: Map3DPoint, boat kind: Map3DFerry.Boat,
                      in drawn: Map3DScene.DrawnWater) -> (edge: Map3DPoint, out: Map3DPoint)? {
        guard let ahead = Map3DPoint(toward.x - middle.x, 0, toward.z - middle.z).normalized else { return nil }
        let boat = kind.length, swing = (kind.length * kind.length + kind.beam * kind.beam).squareRoot() / 2
        func water(_ p: Map3DPoint) -> Bool { drawn.isOpenWater(x: p.x, z: p.z) }
        let steps = Int(shoreReach / shoreStep)
        if water(middle) {
            // Back to the land, the edge the last water before it.
            for step in 1...steps where !water(middle + ahead * (-Float(step) * shoreStep)) {
                return (middle + ahead * (-Float(step - 1) * shoreStep), ahead)
            }
            return nil
        }
        func clear(_ edge: Map3DPoint, _ way: Map3DPoint) -> Bool {
            // The landing, shelter and kiosk behind the shore (6.6 m back,
            // 6.3 m to a side) clear of the city's buildings.
            let side = Map3DPoint(way.z, 0, -way.x)
            for back: Float in [1, 3.4, 6.6] {
                for aside: Float in [-6.3, -3, 0, 3, 6.3] {
                    let p = edge - way * back + side * aside
                    if drawn.isBuilt(x: p.x, z: p.z) { return false }
                }
            }
            let pontoon = Map3DFerry.pierOffshore + Map3DFerry.pontoonReach
            for s in stride(from: shoreStep, through: pontoon, by: shoreStep) where !water(edge + way * s) { return false }
            let berth = edge + way * (pontoon + berthGap + boat / 2)
            for turn in 0..<16 {
                let angle = Float(turn) * .pi / 8, round = Map3DPoint(cos(angle), 0, sin(angle))
                for r in [swing / 2, swing] where !water(berth + round * r) { return false }
            }
            guard let leave = Map3DPoint(toward.x - berth.x, 0, toward.z - berth.z).normalized else { return true }
            let reach = min(clearWay, Map3DPoint(toward.x - berth.x, 0, toward.z - berth.z).length)
            for s in stride(from: 0, through: reach, by: 4) where !water(berth + leave * s) { return false }
            return true
        }
        var best: (clear: Bool, cost: Float, edge: Map3DPoint, way: Map3DPoint)?
        for turn in 0..<16 {
            let angle = Float(turn) * .pi / 8
            let way = Map3DPoint(cos(angle), 0, sin(angle))
            let lean = way.x * ahead.x + way.z * ahead.z
            guard lean > -1e-4 else { continue }
            var wet = false
            for step in 1...steps {
                let edge = middle + way * (Float(step) * shoreStep)
                let now = water(edge)
                defer { wet = drawn.isWater(x: edge.x, z: edge.z) }
                // Out from the land drawn, not from a building on the water.
                guard now, !wet else { continue }
                let isClear = clear(edge, way), cost = Float(step) * (1.25 - 0.5 * lean)
                let better = best.map { isClear != $0.clear ? isClear : cost < $0.cost } ?? true
                if better { best = (isClear, cost, edge, way) }
                if isClear { break }
            }
        }
        guard let best else { return nil }
        return (best.edge, best.way)
    }

    /// The side (row and column steps) of `cell` whose neighbour is water
    /// and lies most the way to `other`'s; the way to `other` itself when
    /// none is water.
    static func waterSide(of cell: CellPosition, toward other: CellPosition, in world: GameWorld) -> (row: Int, column: Int) {
        let dx = Double(other.column - cell.column), dy = Double(other.row - cell.row)
        var best: (score: Double, side: (row: Int, column: Int))?
        for side in [(-1, 0), (1, 0), (0, -1), (0, 1)] where world.terrain.isWater(row: cell.row + side.0, column: cell.column + side.1) {
            let score = Double(side.1) * dx + Double(side.0) * dy
            if best.map({ score > $0.score }) ?? true { best = (score, (side.0, side.1)) }
        }
        if let best { return best.side }
        return abs(dx) >= abs(dy) ? (0, dx < 0 ? -1 : 1) : (dy < 0 ? -1 : 1, 0)
    }

    // MARK: - The timetable (no scene)

    /// Minutes a crossing of `metres` takes at ``FerryRoute/metresPerHour``
    /// (not rounded: the boat moves on smoothly).
    public static func crossingMinutes(_ metres: Int64) -> Double {
        Double(metres) * 60 / Double(FerryRoute.metresPerHour)
    }

    /// Minutes one sailing takes, out and back to the first pier and its
    /// time there: the crossings and ``FerryRoute/dockMinutes`` twice at
    /// each pier between, once at each end (no more than
    /// ``FerryRoute/roundTripMinutes``, which rounds the crossings up).
    public static func sailingMinutes(legMetres: [Int64]) -> Double {
        2 * legMetres.reduce(0) { $0 + crossingMinutes($1) } + Double(2 * legMetres.count) * Double(FerryRoute.dockMinutes)
    }

    /// Where a boat is `minute` minutes into a sailing over `legMetres`;
    /// `nil` outside it.
    public static func stage(atMinute minute: Double, legMetres: [Int64]) -> Stage? {
        guard minute >= 0, !legMetres.isEmpty else { return nil }
        let dock = Double(FerryRoute.dockMinutes), last = legMetres.count
        var left = minute
        for leg in 0..<last {
            let crossing = crossingMinutes(legMetres[leg])
            if left < crossing { return .sailing(leg: leg, share: left / max(crossing, 1e-9), outbound: true) }
            left -= crossing
            if left < dock { return .docked(pier: leg + 1, share: left / dock, outbound: true) }
            left -= dock
        }
        for leg in (0..<last).reversed() {
            let crossing = crossingMinutes(legMetres[leg])
            if left < crossing { return .sailing(leg: leg, share: left / max(crossing, 1e-9), outbound: false) }
            left -= crossing
            if left < dock { return .docked(pier: leg, share: left / dock, outbound: false) }
            left -= dock
        }
        return nil
    }

    /// The minutes of game day `day` the route's boats leave its first
    /// pier: one each ``FerryRoute/headway`` from
    /// ``FerryRoute/firstDeparture``, or its timetable's runs, as many as
    /// ``FerryRoute/dailyDepartures(onDay:)``.
    public static func departures(of route: FerryRoute, onDay day: Int64) -> [Int64] {
        let count = Int(route.dailyDepartures(onDay: day))
        guard count > 0, let headway = route.headway else { return [] }
        switch route.service {
        case .every: return (0..<count).map { FerryRoute.firstDeparture + Int64($0) * headway }
        case .runs(let minutes): return Array(minutes.prefix(count))
        }
    }

    /// The sailings of `route` under way at game second `second` (since
    /// the game began), oldest first, no more than its boats; none on a
    /// day `open` says it does not sail (``GameWorld/ferryRouteIsOpen(_:onDay:)``).
    public static func sailings(of route: FerryRoute, atSecond second: Double, open: (Int64) -> Bool) -> [Stage] {
        numberedSailings(of: route, atSecond: second, open: open).map(\.stage)
    }

    /// Decision 585 PR-4 (FERRYFOLLOW): one sailing under way, and the
    /// boat that sails it (``FerryBoatID/number``).
    public struct Sailing: Equatable, Sendable {
        /// The boat: a day's departures go to the boats in turn, the
        /// first to boat 0 (departure `i` to boat `i` mod the boats).
        public let number: Int
        /// When it left the first pier, in game seconds since the game
        /// began.
        public let start: Double
        public let stage: Stage
    }

    /// ``sailings(of:atSecond:open:)`` with each sailing's boat and
    /// departure.
    public static func numberedSailings(of route: FerryRoute, atSecond second: Double, open: (Int64) -> Bool) -> [Sailing] {
        guard route.boats > 0 else { return [] }
        let perDay = Double(GameTime.secondsPerDay)
        let day = Int64((second / perDay).rounded(.down))
        var sailings: [Sailing] = []
        for d in [day - 1, day] where d >= 0 && open(d) {
            for (index, start) in departures(of: route, onDay: d).enumerated() {
                let at = Double(d) * perDay + Double(start) * 60
                if let stage = stage(atMinute: (second - at) / 60, legMetres: route.legMetres) {
                    sailings.append(Sailing(number: index % route.boats, start: at, stage: stage))
                }
            }
        }
        return Array(sailings.prefix(route.boats))
    }

    /// Decision 585 PR-4: boat `number` of `route` while it lies by the
    /// first pier at game second `second`: when its last sailing came
    /// back (`nil` with none since yesterday) and when its next one
    /// leaves (`nil` with none today or tomorrow), in game seconds.
    public static func lying(_ number: Int, of route: FerryRoute, atSecond second: Double,
                             open: (Int64) -> Bool) -> (since: Double?, until: Double?) {
        guard route.boats > 0 else { return (nil, nil) }
        let perDay = Double(GameTime.secondsPerDay)
        let day = Int64((second / perDay).rounded(.down))
        let length = sailingMinutes(legMetres: route.legMetres) * 60
        var since: Double?, until: Double?
        for d in [day - 1, day, day + 1] where d >= 0 && open(d) {
            for (index, start) in departures(of: route, onDay: d).enumerated() where index % route.boats == number {
                let at = Double(d) * perDay + Double(start) * 60
                if at + length <= second { since = at + length }
                if at > second, until == nil { until = at }
            }
        }
        return (since, until)
    }

    // MARK: - Where a boat is

    /// The way leg `leg` runs out, level.
    static func way(_ line: Line, leg: Int) -> Map3DPoint {
        let a = line.piers[leg].berth, b = line.piers[leg + 1].berth
        return Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized ?? line.piers[leg].out
    }

    /// `a` turned towards `b` by `share`, the short way round, or by half
    /// a turn (always the same way round) when `halfTurn`.
    static func turned(_ a: Map3DPoint, _ b: Map3DPoint, share: Float, halfTurn: Bool = false) -> Map3DPoint {
        let from = atan2f(a.z, a.x)
        var by: Float = halfTurn ? .pi : atan2f(b.z, b.x) - from
        if !halfTurn {
            while by > .pi { by -= 2 * .pi }
            while by < -.pi { by += 2 * .pi }
        }
        let angle = from + by * share
        return Map3DPoint(cosf(angle), 0, sinf(angle))
    }

    /// Eased: still at both ends, fastest in the middle.
    static func eased(_ share: Double) -> Float {
        let s = Float(min(max(share, 0), 1))
        return s * s * (3 - 2 * s)
    }

    /// Where a boat at `stage` on `line` is (its waterline's middle) and
    /// the way its bow (+x) points, level.
    static func place(_ stage: Stage, on line: Line) -> (point: Map3DPoint, forward: Map3DPoint) {
        let double = line.boat.isDoubleEnded, last = line.piers.count - 1
        switch stage {
        case .sailing(let leg, let share, let outbound):
            let a = line.piers[leg].berth, b = line.piers[leg + 1].berth
            let s = eased(share)
            let point = outbound ? a + (b - a) * s : b + (a - b) * s
            let way = way(line, leg: leg)
            return (point, outbound || double ? way : -way)
        case .docked(let pier, let share, let outbound):
            let point = line.piers[pier].berth
            let s = eased(share)
            if outbound {
                let came = way(line, leg: pier - 1)
                if pier == last { return (point, double ? came : turned(came, -came, share: s, halfTurn: true)) }
                return (point, turned(came, way(line, leg: pier), share: s))
            }
            let came = way(line, leg: pier)
            if pier == 0 { return (point, double ? came : turned(-came, came, share: s, halfTurn: true)) }
            let next = way(line, leg: pier - 1)
            return (point, double ? turned(came, next, share: s) : turned(-came, -next, share: s))
        }
    }

    /// Idle boat `slot` (from 1) lying beside the first pier's berth.
    static func idle(_ slot: Int, on line: Line) -> (point: Map3DPoint, forward: Map3DPoint) {
        let pier = line.piers[0]
        let left = Map3DPoint(pier.out.z, 0, -pier.out.x)
        return (pier.berth + left * (Float(slot) * (line.boat.beam + Self.idleGap)), way(line, leg: 0))
    }

    /// Every boat of the route laid as `id` at game second `second`: the
    /// ones sailing, then the idle ones (at most ``mostIdle``).
    func boats(of line: Line, second: Double) -> [(point: Map3DPoint, forward: Map3DPoint)] {
        laid(line, second: second).map { ($0.point, $0.forward) }
    }

    /// Decision 585 PR-4: how long a boat followed takes to move between
    /// the berth and its place beside it, game seconds.
    static let lyingShift: Double = 60

    /// One boat laid: which it is, where, the way its bow points, and
    /// how it sails (`nil` lying by the first pier).
    struct Laid {
        let number: Int
        let point: Map3DPoint
        let forward: Map3DPoint
        let sailing: Sailing?
    }

    /// Every boat of `line` at game second `second`, numbered: the ones
    /// sailing, then the idle ones (at most ``mostIdle``) side by side
    /// beside the first pier, in their numbers' order. Decision 585 PR-4:
    /// boat `following`, when idle, lies first (slot 1) and moves there
    /// from the berth over ``lyingShift`` after its sailing comes back,
    /// and back to the berth before its next leaves, so a camera on it
    /// never jumps.
    func laid(_ line: Line, second: Double, following: Int? = nil) -> [Laid] {
        let open: (Int64) -> Bool = { world.ferryRouteIsOpen(line.id, onDay: $0) }
        let sailing = Self.numberedSailings(of: line.route, atSecond: second, open: open)
        var boats = sailing.map { s -> Laid in
            let at = Self.place(s.stage, on: line)
            return Laid(number: s.number, point: at.point, forward: at.forward, sailing: s)
        }
        let out = Set(sailing.map(\.number))
        var idle = (0..<line.route.boats).filter { !out.contains($0) }
        if let following, let at = idle.firstIndex(of: following) {
            idle.remove(at: at)
            idle.insert(following, at: 0)
        }
        idle = Array(idle.prefix(max(0, line.route.boats - sailing.count)))
        for (slot, number) in idle.prefix(Self.mostIdle).enumerated() {
            let rest = Self.idle(slot + 1, on: line)
            guard number == following else {
                boats.append(Laid(number: number, point: rest.point, forward: rest.forward, sailing: nil))
                continue
            }
            let (since, until) = Self.lying(number, of: line.route, atSecond: second, open: open)
            let away = min(since.map { (second - $0) / Self.lyingShift } ?? 1, until.map { ($0 - second) / Self.lyingShift } ?? 1)
            let s = Self.eased(away)
            let berth = line.piers[0].berth
            boats.append(Laid(number: number, point: berth + (rest.point - berth) * s, forward: rest.forward, sailing: nil))
        }
        return boats
    }

    // MARK: - A frame

    /// The models' indices in `pack`, or `nil` when it lacks any.
    struct Models {
        let boat: [Map3DFerry.Boat: (near: Int, far: Int)]
        let pier: (near: Int, far: Int)

        init?(_ pack: Map3DModelPack) {
            var boat: [Map3DFerry.Boat: (near: Int, far: Int)] = [:]
            for kind in Map3DFerry.Boat.allCases {
                guard let near = pack.index(of: Map3DFerry.name(kind)), let far = pack.index(of: Map3DFerry.name(kind, far: true)) else { return nil }
                boat[kind] = (near, far)
            }
            guard let near = pack.index(of: Map3DFerry.pierName()), let far = pack.index(of: Map3DFerry.pierName(far: true)) else { return nil }
            self.boat = boat
            pier = (near, far)
        }
    }

    /// One frame's ferries.
    public struct Frame: Sendable {
        public var instances: [Map3DInstance] = []
        /// The boats drawn whole, and far.
        public var nearBoats = 0
        public var farBoats = 0
    }

    /// Everything seen from `eye` looking at `target` at game second
    /// `second` (since the game began), with `pack`'s models; `reach`
    /// brings the near models nearer (``Map3DModelReach/farModel``).
    ///
    /// Decision 585 PR-4 (FERRYFOLLOW): boat `following` is drawn whole
    /// wherever it is, first; with `ahead` (the way it sails, level), what
    /// counts as behind is behind it on its way, not behind the camera.
    public func frame(second: Double, eye: Map3DPoint, target: Map3DPoint, pack: Map3DModelPack, reach: Float = 1,
                      following: FerryBoatID? = nil, ahead: Map3DPoint? = nil) -> Frame {
        var frame = Frame()
        guard !lines.isEmpty, let models = Models(pack) else { return frame }
        let near = Self.nearReach * reach, far = Self.farReach
        let look = ahead.flatMap { Map3DPoint($0.x, 0, $0.z).normalized } ?? Map3DPoint(target.x - eye.x, 0, target.z - eye.z).normalized
        func weight(_ p: Map3DPoint) -> Float {
            let d = (p - eye).length
            guard let look, Map3DPoint(p.x - eye.x, 0, p.z - eye.z).dot(look) < 0 else { return d }
            return d * 3
        }
        var boats: [(weight: Float, distance: Float, point: Map3DPoint, forward: Map3DPoint, kind: Map3DFerry.Boat)] = []
        for line in lines {
            for pier in line.piers {
                let d = (pier.origin - eye).length
                guard d < far else { continue }
                frame.instances.append(.prop(d < near ? models.pier.near : models.pier.far, at: pier.origin, forward: pier.out, scale: 1,
                                             tint: 0xFFFFFF))
            }
            let followed = following?.route == line.id ? following?.number : nil
            for boat in laid(line, second: second, following: followed) {
                if boat.number == followed, let pair = models.boat[line.boat] {
                    frame.instances.append(.prop(pair.near, at: boat.point, forward: boat.forward, scale: 1, tint: 0xFFFFFF))
                    frame.nearBoats += 1
                    continue
                }
                let d = (boat.point - eye).length
                guard d < far else { continue }
                boats.append((weight(boat.point), d, boat.point, boat.forward, line.boat))
            }
        }
        boats.sort { $0.weight < $1.weight }
        for boat in boats {
            guard let pair = models.boat[boat.kind] else { continue }
            if boat.distance < near, frame.nearBoats < Self.mostNearBoats {
                frame.instances.append(.prop(pair.near, at: boat.point, forward: boat.forward, scale: 1, tint: 0xFFFFFF))
                frame.nearBoats += 1
            } else if frame.farBoats < Self.mostFarBoats {
                frame.instances.append(.prop(pair.far, at: boat.point, forward: boat.forward, scale: 1, tint: 0xFFFFFF))
                frame.farBoats += 1
            }
        }
        return frame
    }

    // MARK: - Following a boat (decision 585 PR-4)

    /// The way boat `laid` on `line` runs, level: its bow's, but a
    /// double-ended ferry sailing back runs stern first; lying at a pier,
    /// the way it came for the first half of its time there and the way
    /// it leaves for the second (the bridge view turns round at once, as
    /// its master walks to the other end).
    static func travel(_ laid: Laid, on line: Line) -> Map3DPoint {
        guard line.boat.isDoubleEnded, let stage = laid.sailing?.stage else { return laid.forward }
        let last = line.piers.count - 1
        let back: Bool
        switch stage {
        case .sailing(_, _, let outbound): back = !outbound
        case .docked(let pier, let share, let outbound):
            if share < 0.5 { back = !outbound } else { back = outbound ? pier == last : pier != 0 }
        }
        return back ? -laid.forward : laid.forward
    }

    /// Decision 585 PR-4: what the follow camera needs of boat `id` at
    /// game second `second` (with its fraction): its waterline's middle,
    /// the way it runs, its bridge's eye and its cabin's seat; `nil` when
    /// its route is gone or it has no such boat, or (beyond
    /// ``mostIdle``) it is not drawn. It moves on without a jump: in a
    /// sailing, lying at a pier, and to and from its place beside the
    /// first pier (``laid(_:second:following:)``).
    public func pose(of id: FerryBoatID, second: Double) -> Map3DFollow.Pose? {
        guard let line = lines.first(where: { $0.id == id.route }), id.number >= 0, id.number < line.route.boats,
              let laid = laid(line, second: second, following: id.number).first(where: { $0.number == id.number }) else { return nil }
        let boat = line.boat
        let forward = Self.travel(laid, on: line)
        return Map3DFollow.Pose(forward: forward, nose: laid.point + forward * boat.bridgeFront, rail: laid.point, middle: laid.point,
                                length: boat.length, ground: nil, inTunnel: false, eyeHeight: boat.bridgeEye, bodyHeight: boat.height,
                                window: .init(across: boat.seatAcross, height: boat.seatHeight, lookDown: Self.seatLookDown))
    }

    /// Decision 585 PR-4: the cabin window view looks a little down, at
    /// the water going by.
    public static let seatLookDown: Float = 4 * .pi / 180

    /// Decision 585 PR-4: the pier boat `id` comes to next at `second`
    /// (the second pier while it lies by the first), for the 3D map to
    /// build round before it is there; `nil` as ``pose(of:second:)``.
    public func pierAhead(of id: FerryBoatID, second: Double) -> Map3DPoint? {
        guard let line = lines.first(where: { $0.id == id.route }), id.number >= 0, id.number < line.route.boats,
              let laid = laid(line, second: second, following: id.number).first(where: { $0.number == id.number }) else { return nil }
        return line.piers[FerryBoats.piers(of: laid.sailing?.stage, piers: line.piers.count).next].origin
    }

    /// Decision 585 PR-4: the boat drawn nearest the finger at (`x`, `y`)
    /// in `camera`'s view, within `reach` points, at `second`, for a tap
    /// on the 3D map; only those within ``nearReach`` of the eye.
    public func boat(atX x: Float, y: Float, camera: Map3DCamera, second: Double, within reach: Float) -> FerryBoatID? {
        var best: (away: Float, id: FerryBoatID)?
        let eye = camera.eye
        for line in lines {
            for laid in laid(line, second: second) {
                let body = laid.point + Map3DPoint(0, line.boat.height / 2, 0)
                guard (body - eye).length < Self.nearReach, let screen = camera.screenPoint(of: body) else { continue }
                let away = ((screen.x - x) * (screen.x - x) + (screen.y - y) * (screen.y - y)).squareRoot()
                if away <= reach, best.map({ away < $0.away }) ?? true { best = (away, FerryBoatID(route: line.id, number: laid.number)) }
            }
        }
        return best?.id
    }

    /// The first route's first boat at `second`: a sailing one, or the
    /// first idle one; for a screenshot's camera.
    public func firstBoat(second: Double) -> Map3DPoint? {
        guard let line = lines.first else { return nil }
        return boats(of: line, second: second).first?.point
    }
}
