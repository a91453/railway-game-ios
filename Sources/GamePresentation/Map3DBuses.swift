import Foundation
import GameCore

// Decision 400, 10i-6: the player's bus routes' buses on the 3D map. Each
// route's way is laid once along the scene's streets (``Map3DBuses``),
// and where its buses are at a moment comes from the game's clock alone
// (``BusMotion``), so nothing is kept and GameCore never knows of them.
//
// Decision 424: on a real-world map with a base map the way follows the
// base map's own roads (``BusRoadNetwork``), the bus stopping at the stops
// as they lie on them. Decision 474: a bus comes back along the way back
// (``BusRoads/wayBack(stops:station:)``), which a one-way road can make
// another way, and is not drawn while in a tunnel; a route a leg of whose
// way no road joins has no bus (not one driving straight across the
// blocks), unless the player's own roads join it (decision 438), when it
// follows the following.
//
// The way follows the road cells GameCore finds the route's length on
// (``BusRoadPath``). On a map with no base map the streets run along the
// cells' edges (decision 263), so the way goes round each road cell's
// edges from corner to corner; on a real-world map it goes through the
// cells' middles, each put on the nearest road of the base map, as the
// reference's `snapToRoute` (`Railway/geo-scene-reference-clean`
// `BusEngine.ts`) puts a bus on its route.

/// The buses of the player's bus routes, laid in a scene.
public struct Map3DBuses: Sendable {
    /// What a scene's buses are made from: each route with its station's
    /// place and its colour; the same, the same buses.
    public struct Signature: Hashable, Sendable {
        struct Route: Hashable, Sendable {
            let route: BusRoute.Shape
            /// Its station's place; `nil` for a city route (decision 438).
            let station: PlanPoint?
            let colour: Int?
        }

        let routes: [Route]
        let roads: Int
        /// BUGHUNT_BUILD P2-2: the player's roads, which a road laid along
        /// the city's (free, decision 487) changes without changing
        /// ``roads``.
        let ownRoads: Set<CellPosition>
        /// Whether the way follows the base map's roads (decision 424).
        let onRoads: Bool
        let palette: LinePalette

        public init(world: GameWorld, palette: LinePalette, roads onRoads: BusRoads? = nil) {
            routes = world.busRoutes.compactMap { route in
                // Decision 438: a city route has no station.
                guard let id = route.station else { return Route(route: BusRoute.Shape(route), station: nil, colour: nil) }
                return world.station(id: id).map { station in
                    Route(route: BusRoute.Shape(route), station: station.location,
                          colour: world.lines(callingAt: station.id).first?.color?.rgb)
                }
            }
            roads = world.roads?.roadCellCount ?? 0
            ownRoads = world.roads?.built ?? []
            self.onRoads = onRoads != nil
            self.palette = palette
        }
    }

    /// One route laid in the scene.
    struct Route: Sendable {
        let motion: BusMotion
        /// The stops' and the station's distances along the way's middle.
        let stops: [Double]
        let length: Float
        /// The way kept to the right, going out and coming back.
        let out: Map3DStreetLife.Path
        let back: Map3DStreetLife.Path
        /// The stops' and the station's distances along the way back's
        /// middle, from where it starts (decision 474); in the stops' order.
        let backStops: [Double]
        let backLength: Float
        /// The shares of each way (0–1) in a tunnel, where no bus is drawn.
        var outHidden: [ClosedRange<Float>] = []
        var backHidden: [ClosedRange<Float>] = []
        let tint: UInt32
    }

    let routes: [Route]
    /// What it was laid from, and in which scene.
    public let signature: Signature
    let scene: SceneKey

    /// A scene, as far as the buses need to tell one from another.
    struct SceneKey: Hashable, Sendable {
        let originX: Double
        let originY: Double
        let region: WorldRegion
        let lanes: Int

        init(_ scene: Map3DScene) {
            originX = scene.originX
            originY = scene.originY
            region = scene.region
            lanes = scene.streetLife.lanes.count
        }
    }

    /// The routes of `world` that have buses, laid in `scene`.
    public init(world: GameWorld, scene: Map3DScene, palette: LinePalette, roads onRoads: BusRoads? = nil) {
        signature = Signature(world: world, palette: palette, roads: onRoads)
        self.scene = SceneKey(scene)
        guard let roads = world.roads else {
            routes = []
            return
        }
        var laid: [(BusMotion, Plan, Plan?, PlanPoint?, UInt32)] = []
        for route in world.busRoutes {
            let station = route.station.flatMap { world.station(id: $0) }
            guard let motion = BusMotion(route), route.station == nil || station != nil, let last = route.stops.last else { continue }
            var way: Plan
            var back: Plan?
            let saved = world.geoAnchor == nil ? nil : onRoads?.way(ofSaved: route.stops, station: station?.location)
            if let saved, let onRoads, saved.firstBroken == nil {
                way = Plan(points: saved.points, stops: saved.marks, tunnels: saved.tunnels)
                let home = Array(saved.stops.dropLast(station == nil ? 0 : 1))
                let return_ = onRoads.wayBack(stops: home, station: station?.location)
                if return_.firstBroken == nil {
                    back = Plan(points: return_.points, stops: return_.marks, tunnels: return_.tunnels)
                }
            } else if saved != nil {
                // Decision 474: no road joins a leg (the player's own roads
                // are in the graph too, decision 476's sequel): no bus
                // rather than one across the blocks.
                continue
            } else if let station {
                way = Plan(Self.way(stops: route.stops, station: station.location, roads: roads.allCells, alongEdges: world.geoAnchor == nil))
            } else {
                // Decision 438: a city route, its last stop where a
                // station would be.
                way = Plan(Self.way(stops: Array(route.stops.dropLast()), station: last.middle, roads: roads.allCells, alongEdges: world.geoAnchor == nil))
            }
            let colour = station.flatMap { world.lines(callingAt: $0.id).first?.color }
            let tint = colour.map { Map3DColor.rgb(UInt32(palette.color(for: $0.rgb))) } ?? Map3DLowFloorBus.accentColor
            laid.append((motion, way, back, station?.location, tint))
        }
        let roadIndex = RoadIndex(lanes: scene.streetLife.lanes,
                                  near: laid.flatMap(\.1.points).map { scene.point(worldX: Double($0.x), worldY: Double($0.y), height: 0) })
        var routes: [Route] = []
        for (motion, plan, back, station, tint) in laid {
            if let route = Self.lay(motion, plan: plan, back: back, station: station, tint: tint, in: scene, roads: roadIndex,
                                    snaps: world.geoAnchor != nil) {
                routes.append(route)
            }
        }
        self.routes = routes
    }

    /// A way on the plan: its points, the index of each stop and last the
    /// station (a city route's last stop), and for each piece whether it
    /// runs in a tunnel.
    struct Plan {
        let points: [PlanPoint]
        let stops: [Int]
        let tunnels: [Bool]

        init(points: [PlanPoint], stops: [Int], tunnels: [Bool]) {
            self.points = points
            self.stops = stops
            self.tunnels = tunnels
        }

        init(_ way: (points: [PlanPoint], stops: [Int])) {
            self.init(points: way.points, stops: way.stops, tunnels: Array(repeating: false, count: max(way.points.count - 1, 0)))
        }

        /// The same way gone the other way round.
        var reversed: Plan {
            Plan(points: points.reversed(), stops: stops.map { points.count - 1 - $0 }.reversed(), tunnels: tunnels.reversed())
        }
    }

    /// Whether it was laid from `signature` in `scene`.
    public func isLaid(from signature: Signature, in scene: Map3DScene) -> Bool {
        self.signature == signature && self.scene == SceneKey(scene)
    }

    /// The routes laid, for a test.
    public var count: Int { routes.count }

    // MARK: The way on the plan

    /// The way of a route of `stops` to a station at `station` along
    /// `roads`, on the plan, and the index in it of each stop and, last,
    /// the station: round the road cells' edges when `alongEdges`, else
    /// through their middles. A leg no road joins goes straight.
    static func way(stops: [CellPosition], station: PlanPoint, roads: Set<CellPosition>, alongEdges: Bool)
        -> (points: [PlanPoint], stops: [Int]) {
        let ends = stops + [CellPosition(containing: station)]
        var legs: [[CellPosition]] = []
        for (from, to) in zip(ends, ends.dropFirst()) {
            legs.append(BusRoadPath.cells(from: from, to: to, roads: roads) ?? [from, to])
        }
        guard let first = ends.first else { return ([], []) }
        if !alongEdges {
            var points = [first.middle], indices = [0]
            for leg in legs {
                for cell in leg.dropFirst() where cell.middle != points.last { points.append(cell.middle) }
                indices.append(points.count - 1)
            }
            return (points, indices)
        }
        // Round the edges: from a corner of each cell to a corner it shares
        // with the next, along its own edges.
        let next = legs.first?.dropFirst().first.map(\.middle) ?? station
        var at = Corner.nearest(of: Corner.corners(of: first), to: next)
        var points = [at.point], indices = [0], cell = first
        func go(to target: Corner) {
            if target.row != at.row && target.column != at.column { points.append(Corner(row: at.row, column: target.column).point) }
            if target != at { points.append(target.point) }
            at = target
        }
        for (number, leg) in legs.enumerated() {
            for following in leg.dropFirst() {
                let shared = Set(Corner.corners(of: cell)).intersection(Corner.corners(of: following))
                if !shared.contains(at) {
                    if shared.isEmpty {
                        at = Corner.nearest(of: Corner.corners(of: following), to: at.point)
                        points.append(at.point)
                    } else {
                        go(to: Corner.nearest(of: Array(shared), to: at.point))
                    }
                }
                cell = following
            }
            // At the station, the corner of its cell nearest it.
            if number == legs.count - 1 { go(to: Corner.nearest(of: Corner.corners(of: cell), to: station)) }
            indices.append(points.count - 1)
        }
        return (points, indices)
    }

    /// A corner of the 64 m grid.
    struct Corner: Hashable {
        let row: Int
        let column: Int

        var point: PlanPoint { PlanPoint(x: Int64(column) * Land.cellLength, y: Int64(row) * Land.cellLength) }

        static func corners(of cell: CellPosition) -> [Corner] {
            [Corner(row: cell.row, column: cell.column), Corner(row: cell.row, column: cell.column + 1),
             Corner(row: cell.row + 1, column: cell.column), Corner(row: cell.row + 1, column: cell.column + 1)]
        }

        /// The one of `corners` nearest `point`, then by row and column.
        static func nearest(of corners: [Corner], to point: PlanPoint) -> Corner {
            func away(_ corner: Corner) -> Int64 {
                let dx = corner.point.x - point.x, dy = corner.point.y - point.y
                return dx * dx + dy * dy
            }
            return corners.min { away($0) != away($1) ? away($0) < away($1) : ($0.row, $0.column) < ($1.row, $1.column) }!
        }
    }

    // MARK: Laying it in the scene

    /// How far a real-world way's points are moved onto a road, metres.
    static let snapReach: Float = 40
    /// How far a road's height is looked for under a point, metres.
    static let heightReach: Float = 150
    /// The most a way is drawn straight between points on the ground.
    static let step: Float = 16
    /// How far short of its station a way ends: past a station's house
    /// (decision 132's, some 30 m long) and its forecourt, where no street
    /// runs (decision 263).
    static let stationClearance: Float = 40
    /// How near a road the way's end keeps, metres.
    static let roadEnd: Float = 4

    /// `plan`'s way in `scene`, on its roads' height, kept to the right;
    /// short of its station, when it has one (a city route, decision 438,
    /// ends at its last stop). Decision 474: the bus comes back along
    /// `back` (from the station to the first stop) when given, else the
    /// way out the other way round, and is not drawn in a tunnel.
    static func lay(_ motion: BusMotion, plan: Plan, back: Plan? = nil, station: PlanPoint?, tint: UInt32, in scene: Map3DScene,
                    roads: RoadIndex, snaps: Bool) -> Route? {
        guard let way = ground(plan, station: station, in: scene, roads: roads, snaps: snaps) else { return nil }
        // The way back, laid from the first stop as the way out is, and
        // gone the other way round.
        // One that cannot be laid is the way out, its stops with it.
        let laidBack = back.flatMap { back in ground(back.reversed, station: station, in: scene, roads: roads, snaps: snaps).map { (back, $0) } }
        let home = laidBack?.1 ?? way
        // As the cars keep to the right of the roads they share.
        let halves = way.halves + (laidBack == nil ? [] : home.halves)
        let half = halves.isEmpty ? 3 : halves.sorted()[halves.count / 2]
        let side = max(half * 0.5, 1.2)
        guard let out = Map3DStreetLife.Path(way.points)?.shifted(side), let backPath = Map3DStreetLife.Path(home.points.reversed())?.shifted(side)
        else { return nil }
        let length = way.length, backLength = home.length
        return Route(
            motion: motion, stops: plan.stops.map { way.distances[way.marks[$0]] }, length: Float(length), out: out, back: backPath,
            backStops: (laidBack?.0.reversed ?? plan).stops.map { backLength - home.distances[home.marks[$0]] },
            backLength: Float(backLength),
            outHidden: way.hidden.map { Float($0.lowerBound / length)...Float($0.upperBound / length) },
            backHidden: home.hidden.map { Float((backLength - $0.upperBound) / backLength)...Float((backLength - $0.lowerBound) / backLength) },
            tint: tint
        )
    }

    /// A way laid on the ground of a scene.
    struct Ground {
        let points: [Map3DPoint]
        /// Each point's distance along it, from its first.
        let distances: [Double]
        /// The point of each of the plan's points.
        let marks: [Int]
        /// The distances along it in a tunnel.
        let hidden: [ClosedRange<Double>]
        /// The half widths of the roads it was put on.
        let halves: [Float]

        var length: Double { distances.last ?? 0 }
    }

    /// `plan` in `scene`, on its roads' height, short of its station when
    /// it has one; `nil` when no road is near it or it is too short.
    static func ground(_ plan: Plan, station: PlanPoint?, in scene: Map3DScene, roads: RoadIndex, snaps: Bool) -> Ground? {
        var corners = plan.points.map { scene.point(worldX: Double($0.x), worldY: Double($0.y), height: 0) }
        var halves: [Float] = []
        // Whether the piece before point `index` is in a tunnel.
        func underground(_ index: Int) -> Bool { index > 0 && index - 1 < plan.tunnels.count && plan.tunnels[index - 1] }
        // On a real-world map each point on its nearest road, and from one
        // to the next along the roads where they join within three times
        // the straight way (and 200 m). A point inside a tunnel is not put
        // on the road over it (decision 474).
        var snapped: [RoadIndex.Snap?] = Array(repeating: nil, count: corners.count)
        if snaps {
            for index in corners.indices where !(underground(index) && underground(index + 1)) {
                guard let road = roads.nearest(to: corners[index], within: snapReach) else { continue }
                halves.append(road.half)
                snapped[index] = road
                corners[index] = Map3DPoint(road.point.x, 0, road.point.z)
            }
        }
        // Every ``step`` metres at most, so the way keeps to the ground.
        var points: [Map3DPoint] = [], marks: [Int] = [], tunnel: [Bool] = []
        func straight(to corner: Map3DPoint, under: Bool) {
            if let last = points.last {
                let span = Map3DPoint(corner.x - last.x, 0, corner.z - last.z), steps = max(1, Int((span.length / step).rounded(.up)))
                for part in 1..<steps {
                    points.append(last + span * (Float(part) / Float(steps)))
                    tunnel.append(under)
                }
            }
            points.append(Map3DPoint(corner.x, 0, corner.z))
            tunnel.append(under)
        }
        for (index, corner) in corners.enumerated() {
            let under = underground(index)
            if index > 0, !under, let from = snapped[index - 1], let to = snapped[index],
               let way = roads.way(from: from, to: to, longest: 3 * (corner - corners[index - 1]).length + 200) {
                for point in way.dropFirst() { straight(to: point, under: false) }
            } else {
                straight(to: corner, under: under)
            }
            marks.append(points.count - 1)
        }
        // Short of the station's house, at its front.
        if let station {
            let station = scene.point(worldX: Double(station.x), worldY: Double(station.y), height: 0)
            while points.count > 2, let end = points.last, Map3DPoint(end.x - station.x, 0, end.z - station.z).length < stationClearance {
                points.removeLast()
                tunnel.removeLast()
            }
            // And where the street drawn stops short of it.
            while points.count > 2, let end = points.last, (roads.nearest(to: end, within: roadEnd)?.distance ?? .infinity) >= roadEnd {
                points.removeLast()
                tunnel.removeLast()
            }
            marks = marks.map { min($0, points.count - 1) }
        }
        // Each at the height of the road under it, or of the one before.
        var heights = points.map { point -> Float? in
            guard let road = roads.nearest(to: point, within: heightReach) else { return nil }
            if !snaps, road.distance < 12 { halves.append(road.half) }
            return road.point.y
        }
        guard let known = heights.firstIndex(where: { $0 != nil }) else { return nil }
        var last = heights[known]!
        for index in heights.indices {
            if let height = heights[index] { last = height } else { heights[index] = last }
        }
        let ground = zip(points, heights).map { Map3DPoint($0.x, $1 ?? last, $0.z) }
        var distances: [Double] = [0]
        for index in 1..<max(ground.count, 1) {
            distances.append(distances[index - 1] + Double(Map3DPoint(ground[index].x - ground[index - 1].x, 0, ground[index].z - ground[index - 1].z).length))
        }
        guard let length = distances.last, length >= 1 else { return nil }
        // The stretches whose pieces are in a tunnel.
        var hidden: [ClosedRange<Double>] = []
        for index in 1..<ground.count where tunnel[index] {
            if let open = hidden.last, open.upperBound == distances[index - 1] {
                hidden[hidden.count - 1] = open.lowerBound...distances[index]
            } else {
                hidden.append(distances[index - 1]...distances[index])
            }
        }
        return Ground(points: ground, distances: distances, marks: marks, hidden: hidden, halves: halves)
    }

    /// The traffic lanes near a way (not the motorways' or the ramps',
    /// where a city bus does not go): their pieces, found by 32 m square,
    /// and the points they join at, to find a way along them.
    struct RoadIndex {
        struct Piece {
            let a: Map3DPoint
            let b: Map3DPoint
            let half: Float
            /// Its ends' points in ``nodes``.
            let from: Int
            let to: Int
        }

        /// A point on a piece.
        struct Snap {
            let point: Map3DPoint
            let half: Float
            let distance: Float
            let piece: Int
        }

        private var pieces: [Piece] = []
        private var squares: [Int64: [Int]] = [:]
        private var nodes: [Map3DPoint] = []
        private var links: [[(node: Int, metres: Float)]] = []
        private var nodeAt: [Int64: Int] = [:]
        private static let square: Float = 32

        /// The pieces of `lanes` within ``Map3DBuses/heightReach`` of the
        /// box round `points`.
        init(lanes: [Map3DStreetLife.Lane], near points: [Map3DPoint]) {
            guard let first = points.first else { return }
            var low = first, high = first
            for point in points {
                low = Map3DPoint(min(low.x, point.x), 0, min(low.z, point.z))
                high = Map3DPoint(max(high.x, point.x), 0, max(high.z, point.z))
            }
            let reach = Map3DBuses.heightReach, middle = (low + high) * 0.5, spread = (high - low).length / 2
            for lane in lanes where lane.twoWay && lane.path.boxDistance(to: middle) < reach + spread {
                let line = lane.path.points
                for index in 1..<line.count {
                    let a = line[index - 1], b = line[index]
                    guard max(a.x, b.x) > low.x - reach, min(a.x, b.x) < high.x + reach, max(a.z, b.z) > low.z - reach,
                          min(a.z, b.z) < high.z + reach else { continue }
                    let from = node(a), to = node(b)
                    let metres = Map3DPoint(b.x - a.x, 0, b.z - a.z).length
                    links[from].append((to, metres))
                    links[to].append((from, metres))
                    pieces.append(Piece(a: a, b: b, half: lane.half, from: from, to: to))
                    for key in Self.keys(low: (min(a.x, b.x), min(a.z, b.z)), high: (max(a.x, b.x), max(a.z, b.z))) {
                        squares[key, default: []].append(pieces.count - 1)
                    }
                }
            }
        }

        /// The point at `point`, one for all the lanes' ends within half a
        /// metre of it, where roads meet.
        private mutating func node(_ point: Map3DPoint) -> Int {
            let key = Int64((point.x * 2).rounded()) &* 4_000_037 &+ Int64((point.z * 2).rounded())
            if let known = nodeAt[key] { return known }
            nodes.append(point)
            links.append([])
            nodeAt[key] = nodes.count - 1
            return nodes.count - 1
        }

        static func keys(low: (x: Float, z: Float), high: (x: Float, z: Float)) -> [Int64] {
            let columns = Int((low.x / square).rounded(.down))...Int((high.x / square).rounded(.down))
            let rows = Int((low.z / square).rounded(.down))...Int((high.z / square).rounded(.down))
            return rows.flatMap { row in columns.map { Int64($0) &* 1_000_003 &+ Int64(row) } }
        }

        /// The nearest point on a lane to `point` on the level, within
        /// `reach`, its height the lane's there: the reference's
        /// `snapToRoute`, over every lane near.
        func nearest(to point: Map3DPoint, within reach: Float) -> Snap? {
            var best: Snap?
            var seen = Set<Int64>()
            for key in Self.keys(low: (point.x - reach, point.z - reach), high: (point.x + reach, point.z + reach)) where seen.insert(key).inserted {
                for number in squares[key] ?? [] {
                    let piece = pieces[number]
                    let dx = piece.b.x - piece.a.x, dz = piece.b.z - piece.a.z, span = dx * dx + dz * dz
                    let t = span > 0 ? min(max(((point.x - piece.a.x) * dx + (point.z - piece.a.z) * dz) / span, 0), 1) : 0
                    let on = piece.a + (piece.b - piece.a) * t
                    let away = Map3DPoint(on.x - point.x, 0, on.z - point.z).length
                    if away <= reach, best.map({ away < $0.distance || away == $0.distance && number < $0.piece }) ?? true {
                        best = Snap(point: on, half: piece.half, distance: away, piece: number)
                    }
                }
            }
            return best
        }

        /// The shortest way along the lanes from `start` to `end`, both
        /// on them, or `nil` when none is shorter than `longest` metres.
        func way(from start: Snap, to end: Snap, longest: Float) -> [Map3DPoint]? {
            if start.piece == end.piece { return [start.point, end.point] }
            func level(_ a: Map3DPoint, _ b: Map3DPoint) -> Float { Map3DPoint(b.x - a.x, 0, b.z - a.z).length }
            let first = pieces[start.piece], last = pieces[end.piece]
            var best: [Int: Float] = [:], parent: [Int: Int] = [:]
            var heap = Heap()
            for node in [first.from, first.to] {
                let metres = level(start.point, nodes[node])
                if best[node].map({ metres < $0 }) ?? true {
                    best[node] = metres
                    heap.push((metres, node))
                }
            }
            let ends = [last.from: level(nodes[last.from], end.point), last.to: level(nodes[last.to], end.point)]
            var found: (metres: Float, node: Int)?
            while let (metres, node) = heap.pop() {
                guard metres == best[node] else { continue }
                if let found, metres >= found.metres { break }
                if metres > longest { break }
                if let rest = ends[node], found.map({ metres + rest < $0.metres }) ?? true { found = (metres + rest, node) }
                for link in links[node] {
                    let way = metres + link.metres
                    if best[link.node].map({ way < $0 }) ?? true {
                        best[link.node] = way
                        parent[link.node] = node
                        heap.push((way, link.node))
                    }
                }
            }
            guard let found, found.metres <= longest else { return nil }
            var chain = [found.node]
            while let previous = parent[chain[chain.count - 1]] { chain.append(previous) }
            return [start.point] + chain.reversed().map { nodes[$0] } + [end.point]
        }

        /// A binary heap of (metres, point), the least first, then by
        /// point.
        private struct Heap {
            private var items: [(Float, Int)] = []

            private static func before(_ a: (Float, Int), _ b: (Float, Int)) -> Bool { a.0 != b.0 ? a.0 < b.0 : a.1 < b.1 }

            mutating func push(_ item: (Float, Int)) {
                items.append(item)
                var child = items.count - 1
                while child > 0 {
                    let up = (child - 1) / 2
                    guard Self.before(items[child], items[up]) else { break }
                    items.swapAt(child, up)
                    child = up
                }
            }

            mutating func pop() -> (Float, Int)? {
                guard !items.isEmpty else { return nil }
                items.swapAt(0, items.count - 1)
                let top = items.removeLast()
                var parent = 0
                while true {
                    let left = parent * 2 + 1, right = left + 1
                    var least = parent
                    if left < items.count, Self.before(items[left], items[least]) { least = left }
                    if right < items.count, Self.before(items[right], items[least]) { least = right }
                    guard least != parent else { break }
                    items.swapAt(parent, least)
                    parent = least
                }
                return top
            }
        }
    }

    // MARK: A frame

    /// A frame's buses: their models and where each stands, for the
    /// street's traffic to keep clear of.
    public struct Frame: Sendable {
        public var instances: [Map3DInstance] = []
        var clear: [(point: Map3DPoint, along: Map3DPoint)] = []

        public init() {}
    }

    /// The model's place in ``Map3DModelPack/standard``.
    static let model = Map3DModelPack.standard.index(of: Map3DLowFloorBus.routeModelName)

    /// The buses at `second` of the game's day round `target` seen from
    /// `distance` away, as the street's vehicles are drawn (within
    /// ``Map3DStreetLife/vehiclesFrom``, shrinking away at the edge of
    /// their reach), the nearest ``Map3DStreetLife/mostBuses`` of them
    /// (the bus model's budget, which the street's own buses then share)
    /// and at most `detail`'s vehicles. Decision 417: at most `most` of
    /// them when given (the device's tier's buses, ``Map3DStreetLimits``).
    public func frame(second: Double, target: Map3DPoint, distance: Float, detail: Map3DStreetDetail, most: Int? = nil) -> Frame {
        var frame = Frame()
        guard detail != .off, distance <= Map3DStreetLife.vehiclesFrom, let model = Self.model else { return frame }
        let reach = Map3DStreetLife.vehiclesReach(distance)
        var seen: [(away: Float, instance: Map3DInstance, clear: (point: Map3DPoint, along: Map3DPoint))] = []
        for route in routes where route.out.boxDistance(to: target) < reach {
            for bus in route.motion.buses(at: second) {
                // Decision 474: each way's own distances, and none in a tunnel.
                let along = bus.outbound ? Float(bus.distance(along: route.stops)) / route.length
                    : Float(bus.distance(along: route.backStops)) / route.backLength
                guard !(bus.outbound ? route.outHidden : route.backHidden).contains(where: { $0.contains(along) }) else { continue }
                let path = bus.outbound ? route.out : route.back
                let place = path.at(along * path.length)
                let away = Map3DPoint(place.point.x - target.x, 0, place.point.z - target.z).length
                let size = Map3DStreetLife.fade(away, reach: reach) * Float(bus.scale)
                guard size > 0 else { continue }
                seen.append((away, .prop(model, at: place.point, forward: place.along, scale: size, tint: route.tint), (place.point, place.along)))
            }
        }
        // The nearest first; of two as near, the one found first.
        let kept = seen.indices.sorted { (seen[$0].away, $0) < (seen[$1].away, $1) }.prefix(min(most ?? Map3DStreetLife.mostBuses, detail.vehicles))
        for index in kept {
            frame.instances.append(seen[index].instance)
            frame.clear.append(seen[index].clear)
        }
        return frame
    }
}

extension BusRoute {
    /// What of a route its buses are laid and run from.
    struct Shape: Hashable, Sendable {
        let id: BusRouteID
        let stops: [CellPosition]
        let legMetres: [Int64]
        let service: BusService
        let buses: Int

        init(_ route: BusRoute) {
            id = route.id
            stops = route.stops
            legMetres = route.legMetres
            service = route.service
            buses = route.buses
        }
    }
}

extension RoadGrid {
    /// PERF_3D_COCKPIT (2026-10-30): how many cells have a road, the
    /// city's and the player's: ``RoadGrid/allCells``'s count without
    /// making that set. The 3D map's scene key and its buses' signature
    /// count the roads at every tick; on the owner's real-world save
    /// (81,088 city road cells) making the union took about 1.6 ms each
    /// time, on the main thread.
    public var roadCellCount: Int {
        cells.count + built.reduce(0) { $0 + (cells.contains($1) ? 0 : 1) }
    }
}
