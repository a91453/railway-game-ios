import Foundation
import GameCore

// Decision 424: the player's bus routes follow the real roads. On a
// real-world map the roads GameCore keeps are 64 m cells (decision 400), and
// in a town nearly every cell has an alley across it, so a route drawn
// through cell middles cuts across city blocks and a bus in 3D drives
// through buildings. This is the base map's own road lines as a graph of
// points: a stop is put on the nearest line, the shortest way between two
// stops runs along the lines, and the metres of each leg (``BusWay``) go to
// GameCore as the legs it takes (`legMetres`). GameCore is not changed and
// still keeps each stop as a cell.
//
// The references: geo-scene's `BusEngine.ts` `snapToRoute` puts a point on
// the nearest piece of a line (the projection onto each segment, clamped,
// kept here); the world rail site's `build_london_shapes.py` makes a graph
// of the way points of a map, merges the points within a few metres of each
// other so ways that only touch still join, and runs Dijkstra over it (kept,
// at 1 m: the tiles' own lines meet exactly or within a tile unit). Neither
// finds a way over road lines for a bus (gap): the rest is the project's own.
// OSRM, Valhalla and A/B Street were read for ideas only; no code is taken.

/// The base map's bus roads as a graph, in metres east (x) and south (y) of
/// the world's north-west corner (the plan's own axes).
struct BusRoadNetwork: Sendable {
    /// A point on the plan, in metres.
    struct Point: Hashable, Sendable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(_ plan: PlanPoint) {
            let metre = Double(WorldCoordinate.unitsPerMetre)
            self.init(x: Double(plan.x) / metre, y: Double(plan.y) / metre)
        }

        var plan: PlanPoint {
            let metre = Double(WorldCoordinate.unitsPerMetre)
            return PlanPoint(x: Int64((x * metre).rounded()), y: Int64((y * metre).rounded()))
        }

        func distance(to other: Point) -> Double {
            hypot(x - other.x, y - other.y)
        }
    }

    /// One line of the base map a bus can take.
    struct Road: Sendable {
        let points: [Point]
    }

    /// A point on a road, found by ``nearest(to:within:accepting:)``.
    struct Place: Hashable, Sendable {
        let point: Point
        /// The piece of road it lies on.
        let segment: Int
        /// How far it is from the point asked about, in metres.
        let distance: Double
    }

    /// How near the ends of two lines are merged into one point, in metres.
    static let mergeMetres = 1.0
    /// How far a tapped point is put onto a road (decision 424), in metres.
    static let snapReach = 25.0
    /// How far a saved stop is put onto a road from its cell's middle, in
    /// metres: past half the cell's diagonal.
    static let cellReach = 96.0
    /// How far a station is put onto a road, in metres: its building and the
    /// forecourt have no road across them.
    static let stationReach = 128.0
    /// The most points searched for one way.
    static let searchLimit = 400_000

    /// The base map's classes a bus takes (decision 424): `primary` to
    /// `minor`. Service roads, freeways and expressways are left out.
    static func takes(_ kind: Map3DBaseMap.RoadKind) -> Bool {
        switch kind {
        case .primary, .secondary, .tertiary, .minor: true
        case .service, .trunk, .motorway: false
        }
    }

    private struct Link {
        let node: Int
        let metres: Double
    }

    /// The graph's points, and for each piece of road the two it joins.
    private(set) var nodes: [Point] = []
    private var segments: [(from: Int, to: Int)] = []
    private var links: [[Link]] = []
    private var squares: [Int64: [Int]] = [:]
    private static let square = 32.0

    /// The graph of `roads`, in the order given: the same roads make the
    /// same graph.
    init(roads: [Road]) {
        var nodeAt: [Int64: [Int]] = [:]
        var pieces = Set<Pair>()
        func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) &* 2_000_003 &+ Int64(y) }
        func node(for point: Point) -> Int {
            let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
            var best: (node: Int, away: Double)?
            for dx in -1...1 {
                for dy in -1...1 {
                    for candidate in nodeAt[key(x + dx, y + dy)] ?? [] {
                        let away = nodes[candidate].distance(to: point)
                        if away <= Self.mergeMetres, best.map({ away < $0.away || away == $0.away && candidate < $0.node }) ?? true {
                            best = (candidate, away)
                        }
                    }
                }
            }
            if let best { return best.node }
            nodes.append(point)
            nodeAt[key(x, y), default: []].append(nodes.count - 1)
            return nodes.count - 1
        }
        for road in roads where road.points.count >= 2 {
            var previous = node(for: road.points[0])
            for point in road.points.dropFirst() {
                let next = node(for: point)
                defer { previous = next }
                guard next != previous, pieces.insert(Pair(previous, next)).inserted else { continue }
                segments.append((previous, next))
            }
        }
        links = Array(repeating: [], count: nodes.count)
        splitAtJunctions()
        for (number, segment) in segments.enumerated() {
            let metres = nodes[segment.from].distance(to: nodes[segment.to])
            links[segment.from].append(Link(node: segment.to, metres: metres))
            links[segment.to].append(Link(node: segment.from, metres: metres))
            for square in Self.squares(from: nodes[segment.from], to: nodes[segment.to], reach: 0) {
                squares[square, default: []].append(number)
            }
        }
    }

    /// The tiles simplify a straight road past the points where a side
    /// street meets it, so a street's end can lie on the inside of a piece
    /// of another road with no point there to join them. Cuts each piece at
    /// every other road's point within ``mergeMetres`` of it.
    private mutating func splitAtJunctions() {
        var near: [Int64: [Int]] = [:]
        for (number, segment) in segments.enumerated() {
            for square in Self.squares(from: nodes[segment.from], to: nodes[segment.to], reach: Self.mergeMetres) {
                near[square, default: []].append(number)
            }
        }
        var cuts: [Int: [(t: Double, node: Int)]] = [:]
        for (node, point) in nodes.enumerated() {
            for number in Set(near[Self.squares(from: point, to: point, reach: 0)[0]] ?? []) {
                let segment = segments[number]
                guard segment.from != node, segment.to != node else { continue }
                let a = nodes[segment.from], b = nodes[segment.to]
                let dx = b.x - a.x, dy = b.y - a.y, span = dx * dx + dy * dy
                let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / span
                guard t > 0, t < 1, hypot(a.x + dx * t - point.x, a.y + dy * t - point.y) <= Self.mergeMetres else { continue }
                cuts[number, default: []].append((t, node))
            }
        }
        guard !cuts.isEmpty else { return }
        var pieces = Set<Pair>()
        var cut: [(from: Int, to: Int)] = []
        for (number, segment) in segments.enumerated() {
            let through = (cuts[number] ?? []).sorted { ($0.t, $0.node) < ($1.t, $1.node) }.map(\.node)
            let chain = [segment.from] + through + [segment.to]
            for (from, to) in zip(chain, chain.dropFirst()) where from != to && pieces.insert(Pair(from, to)).inserted {
                cut.append((from, to))
            }
        }
        segments = cut
    }

    private struct Pair: Hashable {
        let low: Int, high: Int
        init(_ a: Int, _ b: Int) { (low, high) = (min(a, b), max(a, b)) }
    }

    /// The keys of the squares the box round `a` and `b`, `reach` more, covers.
    private static func squares(from a: Point, to b: Point, reach: Double) -> [Int64] {
        let columns = Int(((min(a.x, b.x) - reach) / square).rounded(.down))...Int(((max(a.x, b.x) + reach) / square).rounded(.down))
        let rows = Int(((min(a.y, b.y) - reach) / square).rounded(.down))...Int(((max(a.y, b.y) + reach) / square).rounded(.down))
        return rows.flatMap { row in columns.map { Int64($0) &* 1_000_003 &+ Int64(row) } }
    }

    var isEmpty: Bool { segments.isEmpty }

    // MARK: Putting a point on a road

    /// The nearest point on a road to `point`, within `reach` metres (the
    /// reference's `snapToRoute`, over every piece near), of those
    /// `accepting` takes; of two as near, the piece found first. Where the
    /// nearest point on a piece is not accepted, the piece is looked along
    /// for one that is.
    func nearest(to point: Point, within reach: Double, accepting: (Point) -> Bool = { _ in true }) -> Place? {
        var best: Place?
        var seen = Set<Int>()
        for key in Self.squares(from: point, to: point, reach: reach) {
            for number in squares[key] ?? [] where seen.insert(number).inserted {
                let a = nodes[segments[number].from], b = nodes[segments[number].to]
                guard let on = Self.closest(on: a, b, to: point, accepting: accepting) else { continue }
                let away = on.distance(to: point)
                if away <= reach, best.map({ away < $0.distance || away == $0.distance && number < $0.segment }) ?? true {
                    best = Place(point: on, segment: number, distance: away)
                }
            }
        }
        return best
    }

    /// The point of the piece from `a` to `b` nearest `point` that
    /// `accepting` takes, or `nil` when it takes none.
    private static func closest(on a: Point, _ b: Point, to point: Point, accepting: (Point) -> Bool) -> Point? {
        func at(_ t: Double) -> Point { Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let dx = b.x - a.x, dy = b.y - a.y, span = dx * dx + dy * dy
        let t = span > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / span, 0), 1) : 0
        let nearest = at(t)
        if accepting(nearest) { return nearest }
        let steps = max(1, Int((a.distance(to: b) / 4).rounded(.up)))
        var best: (point: Point, away: Double)?
        for step in 0...steps {
            let candidate = at(Double(step) / Double(steps))
            let away = candidate.distance(to: point)
            if best.map({ away < $0.away }) ?? true, accepting(candidate) { best = (candidate, away) }
        }
        return best?.point
    }

    // MARK: The way between two places

    /// The shortest way along the roads from `start` to `end`: the points
    /// from one to the other, or `nil` when no road joins them. Dijkstra's
    /// search, the nearest first and then by point, so the same roads give
    /// the same way.
    func way(from start: Place, to end: Place) -> [Point]? {
        if start.segment == end.segment { return Self.deduplicated([start.point, end.point]) }
        let first = segments[start.segment], last = segments[end.segment]
        var best = [Double](repeating: .infinity, count: nodes.count)
        var parent = [Int](repeating: -1, count: nodes.count)
        var heap = Heap()
        for node in [first.from, first.to] {
            let metres = start.point.distance(to: nodes[node])
            if metres < best[node] {
                best[node] = metres
                heap.push((metres, node))
            }
        }
        let rest = [last.from: nodes[last.from].distance(to: end.point), last.to: nodes[last.to].distance(to: end.point)]
        var found: (metres: Double, node: Int)?
        var settled = 0
        while let (metres, node) = heap.pop() {
            guard metres == best[node] else { continue }
            if let found, metres >= found.metres { break }
            settled += 1
            guard settled <= Self.searchLimit else { return nil }
            if let tail = rest[node], found.map({ metres + tail < $0.metres }) ?? true { found = (metres + tail, node) }
            for link in links[node] {
                let way = metres + link.metres
                if way < best[link.node] {
                    best[link.node] = way
                    parent[link.node] = node
                    heap.push((way, link.node))
                }
            }
        }
        guard let found else { return nil }
        var chain = [found.node]
        while parent[chain[chain.count - 1]] >= 0 { chain.append(parent[chain[chain.count - 1]]) }
        return Self.deduplicated([start.point] + chain.reversed().map { nodes[$0] } + [end.point])
    }

    private static func deduplicated(_ points: [Point]) -> [Point] {
        var kept: [Point] = []
        for point in points where kept.last.map({ $0.distance(to: point) > 1e-6 }) ?? true { kept.append(point) }
        return kept
    }

    /// A binary heap of (metres, point), the least first, then by point.
    private struct Heap {
        private var items: [(Double, Int)] = []

        private static func before(_ a: (Double, Int), _ b: (Double, Int)) -> Bool { a.0 != b.0 ? a.0 < b.0 : a.1 < b.1 }

        mutating func push(_ item: (Double, Int)) {
            items.append(item)
            var child = items.count - 1
            while child > 0 {
                let up = (child - 1) / 2
                guard Self.before(items[child], items[up]) else { break }
                items.swapAt(child, up)
                child = up
            }
        }

        mutating func pop() -> (Double, Int)? {
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

    // MARK: Reading the base map

    /// The bus roads of tile `column`, `row`'s `transportation` layer, kept
    /// to the tile (as ``Map3DBaseMap`` keeps them, so the tiles' overlap is
    /// not read twice; a road cut at the edge meets the next tile's piece
    /// within ``mergeMetres``). Tunnels are left out.
    static func roads(in layer: VectorTile.Layer, column: Int, row: Int, projection: RealRoadCells.Projection) -> [Road] {
        let (west, north, scale) = projection.place(column: column, row: row, extent: layer.extent)
        let size = projection.tilePoints / projection.pointsPerMetre
        let tile = Map3DBaseMap.Bounds(minX: west, minZ: north, maxX: west + size, maxZ: north + size)
        var roads: [Road] = []
        for feature in layer.features where feature.kind == .line {
            guard let kind = Map3DBaseMap.roadKind(feature.string("class")), takes(kind), feature.string("brunnel") != "tunnel" else { continue }
            for part in feature.parts where part.count >= 2 {
                let line = part.map { Map3DBaseMap.Point(x: west + Double($0.x) * scale, z: north + Double($0.y) * scale) }
                for run in Map3DBaseMap.parts(of: line, in: tile) {
                    roads.append(Road(points: run.map { Point(x: $0.x, y: $0.z) }))
                }
            }
        }
        return roads
    }
}

// MARK: - The base map's tiles as one network

/// The base map's bus roads of a real-world map, read tile by tile as a
/// route needs them and kept: a tile decoded once is not decoded again, and
/// the network of a region of tiles is built once. Made for one base map and
/// one frame (a session's), whose data never changes.
public final class BusRoads: @unchecked Sendable {
    private struct Tile: Hashable { let column: Int, row: Int }
    private struct Region: Hashable { let columns: ClosedRange<Int>, rows: ClosedRange<Int> }

    /// How far round a leg the roads are read, in metres: a way can go
    /// round a block or a river bend but not across the island.
    static let margin = 1_000.0
    /// How far round a station the tiles are read ahead, in metres: as far
    /// as the real bus stops (``RealBusLibrary/reach``).
    static let aheadReach = RealBusLibrary.reach
    /// The most tiles and regions kept: the tiles of ``aheadReach`` round a
    /// station (49 at most) with the margin of a tap at its edge.
    private static let keptTiles = 64
    private static let keptRegions = 8

    private let tiles: BaseMapTiles
    let projection: RealRoadCells.Projection
    private let lock = NSLock()
    private var read: [Tile: [BusRoadNetwork.Road]] = [:]
    private var named: [Tile: [NamedRoad]] = [:]
    private var built: [Region: BusRoadNetwork] = [:]

    init(tiles: BaseMapTiles, frame: RealWorldFrame) {
        self.tiles = tiles
        projection = RealRoadCells.Projection(frame: frame)
    }

    /// The network of the tiles round the box from `low` to `high`, a
    /// ``margin`` more each side.
    func network(from low: BusRoadNetwork.Point, to high: BusRoadNetwork.Point) -> BusRoadNetwork {
        let region = Region(
            columns: projection.column(min(low.x, high.x) - Self.margin)...projection.column(max(low.x, high.x) + Self.margin),
            rows: projection.row(min(low.y, high.y) - Self.margin)...projection.row(max(low.y, high.y) + Self.margin)
        )
        lock.lock()
        defer { lock.unlock() }
        if let known = built[region] { return known }
        var lines: [BusRoadNetwork.Road] = []
        for row in region.rows {
            for column in region.columns { lines += roads(of: Tile(column: column, row: row)) }
        }
        if built.count >= Self.keptRegions { built.removeAll() }
        let network = BusRoadNetwork(roads: lines)
        built[region] = network
        return network
    }

    /// Reads ahead what the bus tool asks first round `station` (decision
    /// 424's sequel), for a thread that is not the one drawing: the tiles
    /// within `reach` metres of it, and the network of the box round the
    /// station itself, which a tap beside it and the last leg of every
    /// route ask for. Changes no result, only what is already read when
    /// ``network(from:to:)`` is asked: it takes the lock a tile at a time, so
    /// a tap meanwhile waits for one tile, not for them all.
    func readAhead(round station: PlanPoint, reach: Double = BusRoads.aheadReach) {
        let here = BusRoadNetwork.Point(station)
        _ = network(from: here, to: here)
        let columns = projection.column(here.x - reach)...projection.column(here.x + reach)
        let rows = projection.row(here.y - reach)...projection.row(here.y + reach)
        for row in rows {
            for column in columns {
                if Task.isCancelled { return }
                lock.lock()
                _ = roads(of: Tile(column: column, row: row))
                lock.unlock()
            }
        }
    }

    /// The tiles and regions kept (for the tests).
    var kept: (tiles: Int, regions: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (read.count, built.count)
    }

    /// A tile's roads (the lock is held). A tile that fails to read has none.
    private func roads(of tile: Tile) -> [BusRoadNetwork.Road] {
        if let known = read[tile] { return known }
        var roads: [BusRoadNetwork.Road] = []
        if let bytes = try? tiles.archive.tile(zoom: BaseMapTiles.zoom, x: tile.column, y: tile.row),
           let decoded = try? VectorTile(bytes, layers: ["transportation"]), let layer = decoded.layers["transportation"] {
            roads = BusRoadNetwork.roads(in: layer, column: tile.column, row: tile.row, projection: projection)
        }
        if read.count >= Self.keptTiles { read.removeAll() }
        read[tile] = roads
        return roads
    }

    /// The named roads of a tile (decision 424, C2), read from the
    /// `transportation_name` layer and kept like the roads. A tile that
    /// fails to read has none.
    func namedRoads(column: Int, row: Int) -> [NamedRoad] {
        lock.lock()
        defer { lock.unlock() }
        let tile = Tile(column: column, row: row)
        if let known = named[tile] { return known }
        var roads: [NamedRoad] = []
        if let bytes = try? tiles.archive.tile(zoom: BaseMapTiles.zoom, x: column, y: row),
           let decoded = try? VectorTile(bytes, layers: ["transportation_name"]), let layer = decoded.layers["transportation_name"] {
            roads = BusRoadNames.roads(in: layer, column: column, row: row, projection: projection)
        }
        if named.count >= Self.keptTiles { named.removeAll() }
        named[tile] = roads
        return roads
    }
}

// MARK: - A route's way

/// A bus route's way along the roads: from its first stop (the farthest, as
/// GameCore lists them) through each stop to the station, a leg for each.
struct BusWay: Hashable, Sendable {
    /// One stretch, from a stop to the next stop or the station.
    struct Leg: Hashable, Sendable {
        /// The road's centre line, both ends included; empty when no road joins them.
        let line: [PlanPoint]
        /// Its metres, the line's length rounded: what GameCore is given.
        let metres: Int64?
    }

    let legs: [Leg]
    /// The way as it is drawn: the centre line of each leg after the last
    /// that no road joins, its corners rounded (``rounded(_:keeping:)``).
    let points: [PlanPoint]
    /// The index in ``points`` of the first stop, of each stop after it, and
    /// last the station, for the legs drawn.
    let marks: [Int]
    /// The first leg no road joins (in GameCore's order), or `nil`.
    let firstBroken: Int?

    /// How big a corner's round is, in metres.
    static let cornerRadius = 8.0

    /// Where the stops lie on the way (the legs' first points).
    var pins: [PlanPoint] {
        marks.dropLast().map { points[$0] }
    }

    /// The metres of every leg, or `nil` when a leg is broken.
    var legMetres: [Int64]? {
        let metres = legs.compactMap(\.metres)
        return metres.count == legs.count ? metres : nil
    }

    /// The way of `lines`, one for each leg: a leg of `nil` is broken.
    init(lines: [[PlanPoint]?]) {
        legs = lines.map { line in
            guard let line, line.count >= 1 else { return Leg(line: [], metres: nil) }
            return Leg(line: line, metres: Self.metres(of: line))
        }
        firstBroken = legs.firstIndex { $0.metres == nil }
        let drawn = (legs.lastIndex { $0.metres == nil }.map { $0 + 1 } ?? 0)..<legs.count
        var joined: [PlanPoint] = [], keep: [Int] = []
        for leg in legs[drawn] {
            if joined.isEmpty { keep.append(0) }
            joined += joined.isEmpty ? leg.line : Array(leg.line.dropFirst())
            keep.append(joined.count - 1)
        }
        (points, marks) = Self.rounded(joined, keeping: keep)
    }

    /// `line`'s length in whole metres.
    static func metres(of line: [PlanPoint]) -> Int64 {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var total = 0.0
        for (a, b) in zip(line, line.dropFirst()) { total += hypot(Double(b.x - a.x), Double(b.y - a.y)) / metre }
        return Int64(total.rounded())
    }

    /// `points` with each corner but those at `keeping` (and the ends)
    /// cut and joined by a curve of at most ``cornerRadius``, so the line
    /// turns where a road turns. Returns the new points and where each of
    /// `keeping` went.
    static func rounded(_ points: [PlanPoint], keeping keep: [Int]) -> (points: [PlanPoint], marks: [Int]) {
        guard points.count >= 3 else { return (points, keep) }
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var out: [PlanPoint] = [points[0]]
        var moved = [Int](repeating: 0, count: points.count)
        let kept = Set(keep)
        for index in 1..<points.count {
            defer { moved[index] = out.count - 1 }
            let here = points[index]
            guard index < points.count - 1, !kept.contains(index) else {
                if here != out.last { out.append(here) }
                continue
            }
            let before = points[index - 1], after = points[index + 1]
            let inX = Double(before.x - here.x) / metre, inY = Double(before.y - here.y) / metre
            let outX = Double(after.x - here.x) / metre, outY = Double(after.y - here.y) / metre
            let inLength = hypot(inX, inY), outLength = hypot(outX, outY)
            // A straight road keeps its point.
            let cosine = inLength > 0 && outLength > 0 ? (inX * outX + inY * outY) / (inLength * outLength) : -1
            let cut = min(cornerRadius, inLength / 2, outLength / 2)
            guard cosine > -0.985, cut >= 1 else {
                if here != out.last { out.append(here) }
                continue
            }
            func point(_ x: Double, _ y: Double) -> PlanPoint {
                PlanPoint(x: here.x + Int64((x * metre).rounded()), y: here.y + Int64((y * metre).rounded()))
            }
            let a = (x: inX / inLength * cut, y: inY / inLength * cut), b = (x: outX / outLength * cut, y: outY / outLength * cut)
            // A quadratic curve from the cut on the way in to the cut on the
            // way out, the corner its control.
            for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let u = 1 - t
                let candidate = point(u * u * a.x + t * t * b.x, u * u * a.y + t * t * b.y)
                if candidate != out.last { out.append(candidate) }
            }
        }
        return (out, keep.map { moved[$0] })
    }
}

extension BusRoads {
    /// The point on a bus road nearest `point`, within `reach` metres, of
    /// those `accepting` takes (the stop a tap puts there, decision 424).
    func place(near point: PlanPoint, within reach: Double, accepting: (PlanPoint) -> Bool = { _ in true }) -> PlanPoint? {
        let here = BusRoadNetwork.Point(point)
        return network(from: here, to: here)
            .nearest(to: here, within: reach, accepting: { accepting($0.plan) })?.point.plan
    }

    /// The way of a saved route through `stops` (GameCore's order, cells) to
    /// `station`: each stop put from its cell's middle on the nearest bus
    /// road (in the cell when one crosses it), the route's metres not
    /// worked out again. `nil` when a stop has no road near or a leg no road
    /// joins; the route is then drawn along the road cells.
    func way(ofSaved stops: [CellPosition], station: PlanPoint) -> BusWay? {
        var pins: [PlanPoint] = []
        for cell in stops {
            guard let pin = place(near: cell.middle, within: BusRoadNetwork.cellReach, accepting: { CellPosition(containing: $0) == cell })
                    ?? place(near: cell.middle, within: BusRoadNetwork.cellReach)
            else { return nil }
            pins.append(pin)
        }
        let way = way(stops: pins, station: station)
        return way.firstBroken == nil ? way : nil
    }

    /// The way through `stops` (GameCore's order) to `station`, a leg for
    /// each; `stops` and `station` are plan points, each put on its nearest
    /// road: a stop where it is (it was put there when it was tapped), the
    /// station within ``BusRoadNetwork/stationReach`` of it. A leg ends at
    /// the station itself, over the short way from its road. A leg whose
    /// ends no road joins is broken (`nil`).
    func way(stops: [PlanPoint], station: PlanPoint) -> BusWay {
        let ends = stops + [station]
        var lines: [[PlanPoint]?] = []
        for index in stops.indices {
            lines.append(leg(from: ends[index], to: ends[index + 1], toStation: index == stops.count - 1))
        }
        return BusWay(lines: lines)
    }

    private func leg(from start: PlanPoint, to end: PlanPoint, toStation: Bool) -> [PlanPoint]? {
        let a = BusRoadNetwork.Point(start), b = BusRoadNetwork.Point(end)
        let roads = network(from: a, to: b)
        guard let from = roads.nearest(to: a, within: BusRoadNetwork.snapReach),
              let to = roads.nearest(to: b, within: toStation ? BusRoadNetwork.stationReach : BusRoadNetwork.snapReach),
              let road = roads.way(from: from, to: to)
        else { return nil }
        var line = road.map(\.plan)
        if toStation, line.last != end { line.append(end) }
        return line
    }
}
