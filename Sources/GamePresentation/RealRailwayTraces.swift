import Foundation
import GameCore

// The real lines as a network to trace along (decision 213); the tool that
// uses it is in RealRailwayTracing.swift.

/// Taiwan's real railways laid over a world's plan, as a network to trace
/// along: each line's centre line in world units, and where a line's end
/// meets another line of the same system (a branch leaving a main line, or
/// two pieces of one line).
struct RealRailwayTraces: Sendable {
    /// A real line in the world's plan.
    struct Line: Sendable {
        let id: Int
        let system: String
        let path: WorldPath
        /// Its box in plan, for finding the lines near a point quickly.
        let minX: Double, minY: Double, maxX: Double, maxY: Double
    }

    /// A place along a line: how far along it.
    struct Place: Hashable, Sendable {
        let line: Int
        let along: Double
    }

    /// A place on the network near a point, and how far the point is from
    /// it, in world units.
    struct Snap: Sendable {
        let place: Place
        let point: WorldVector
        let distance: Double
    }

    /// Where a line's end meets another line, and the gap between them.
    struct Link: Sendable {
        let a: Place
        let b: Place
        let gap: Double
    }

    let lines: [Line]
    /// Each line as the map draws it, in whole world units.
    let drawn: [[WorldCoordinate]]
    let links: [Link]
    /// Which lines connect to each other, by any number of links: each
    /// line's group.
    let groups: [Int]
    /// The network ``route(from:to:)`` finds its way on, worked out once:
    /// the places a way may turn at (each line's ends and the links'
    /// places), and how they join.
    private let graph: Graph

    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How far a line's end may stand from another line and still join it:
    /// the bundled lines are drawn separately, and a branch's first point
    /// is a few metres off the main line's centre.
    static let joinReach = 60 * metre
    /// How far beyond the world's edge the lines are kept, so a line that
    /// leaves the map and comes back stays one.
    static let margin = 2_000 * metre

    /// The lines of `railways` that reach the world `frame` and `bounds`
    /// make, projected as the map projects them.
    init(railways: RealRailways, frame: RealWorldFrame, bounds: WorldBounds) {
        let region = WorldRegion(bounds: bounds)
        var lines: [Line] = []
        for line in railways.lines {
            let points = line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            guard points.count > 1 else { continue }
            let xs = points.map(\.x), ys = points.map(\.y)
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            guard maxX >= region.minX - Self.margin, minX <= region.maxX + Self.margin,
                  maxY >= region.minY - Self.margin, minY <= region.maxY + Self.margin else { continue }
            let path = WorldPath(points)
            guard path.points.count > 1 else { continue }
            lines.append(Line(id: lines.count, system: line.system.id, path: path, minX: minX, minY: minY, maxX: maxX, maxY: maxY))
        }
        self.lines = lines
        drawn = lines.map { line in line.path.points.map { $0.coordinate() } }

        // Each line's two ends, joined to the nearest place on another line
        // of its system within reach.
        var links: [Link] = []
        for line in lines {
            for along in [0, line.path.length] {
                let end = line.path.point(at: along)
                var best: (place: Place, gap: Double)?
                for other in lines where other.id != line.id && other.system == line.system {
                    guard let found = Self.nearest(to: end, on: other, within: Self.joinReach) else { continue }
                    if best == nil || found.distance < best!.gap {
                        best = (Place(line: other.id, along: found.along), found.distance)
                    }
                }
                if let best {
                    links.append(Link(a: Place(line: line.id, along: along), b: best.place, gap: best.gap))
                }
            }
        }
        self.links = links

        var groups = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while groups[index] != index { index = groups[index] }
            return index
        }
        for link in links {
            let a = root(link.a.line), b = root(link.b.line)
            if a != b { groups[max(a, b)] = min(a, b) }
        }
        self.groups = lines.indices.map(root)
        graph = Graph(lines: lines, links: links)
    }

    /// The places a way may turn at, and how they join: along each line to
    /// the next place on it either way, and across each link. Built once
    /// with the lines, as a drag asks for several ways each time it moves
    /// (one for each line within reach at either end).
    private struct Graph: Sendable {
        /// Each place once: each line's ends, then the links' places.
        let stops: [Place]
        let index: [Place: Int]
        /// Each line's places, by how far along it.
        let byLine: [[Int]]
        /// Each place's neighbours along its line, then across links.
        let alongLine: [[(stop: Int, cost: Double)]]
        let acrossLinks: [[(stop: Int, cost: Double)]]

        init(lines: [Line], links: [Link]) {
            var candidates: [Place] = []
            for line in lines { candidates += [Place(line: line.id, along: 0), Place(line: line.id, along: line.path.length)] }
            for link in links { candidates += [link.a, link.b] }
            var index: [Place: Int] = [:]
            var stops: [Place] = []
            for stop in candidates where index[stop] == nil {
                index[stop] = stops.count
                stops.append(stop)
            }
            var byLine = [[Int]](repeating: [], count: lines.count)
            for (number, stop) in stops.enumerated() { byLine[stop.line].append(number) }
            byLine = byLine.map { numbers in numbers.sorted { stops[$0].along < stops[$1].along } }
            var alongLine = [[(stop: Int, cost: Double)]](repeating: [], count: stops.count)
            for numbers in byLine {
                for (a, b) in zip(numbers, numbers.dropFirst()) {
                    let cost = stops[b].along - stops[a].along
                    alongLine[a].append((b, cost))
                    alongLine[b].append((a, cost))
                }
            }
            var acrossLinks = [[(stop: Int, cost: Double)]](repeating: [], count: stops.count)
            for link in links {
                guard let a = index[link.a], let b = index[link.b] else { continue }
                acrossLinks[a].append((b, link.gap))
                acrossLinks[b].append((a, link.gap))
            }
            self.stops = stops
            self.index = index
            self.byLine = byLine
            self.alongLine = alongLine
            self.acrossLinks = acrossLinks
        }
    }

    /// The place on any line nearest `point` within `reach` world units,
    /// on a line of group `group` when one is given, of `system` (a site
    /// system's ID) when one is given, and on line `only` when one is.
    func snap(_ point: WorldVector, within reach: Double, group: Int? = nil, system: String? = nil, only: Int? = nil) -> Snap? {
        var best: Snap?
        for line in lines where (group == nil || groups[line.id] == group) && (system == nil || line.system == system) && (only == nil || line.id == only) {
            guard point.x >= line.minX - reach, point.x <= line.maxX + reach,
                  point.y >= line.minY - reach, point.y <= line.maxY + reach else { continue }
            guard let found = Self.nearest(to: point, on: line, within: best?.distance ?? reach) else { continue }
            if best == nil || found.distance < best!.distance {
                best = Snap(place: Place(line: line.id, along: found.along), point: line.path.point(at: found.along), distance: found.distance)
            }
        }
        return best
    }

    /// The place nearest `point` within `reach` on each line that comes
    /// that near, nearest first, with the same filters as
    /// ``snap(_:within:group:system:only:)``.
    func snaps(_ point: WorldVector, within reach: Double, group: Int? = nil, system: String? = nil) -> [Snap] {
        lines.compactMap { line -> Snap? in
            guard (group == nil || groups[line.id] == group) && (system == nil || line.system == system),
                  point.x >= line.minX - reach, point.x <= line.maxX + reach,
                  point.y >= line.minY - reach, point.y <= line.maxY + reach,
                  let found = Self.nearest(to: point, on: line, within: reach) else { return nil }
            return Snap(place: Place(line: line.id, along: found.along), point: line.path.point(at: found.along), distance: found.distance)
        }.sorted { $0.distance < $1.distance }
    }

    /// The way along the lines from `start` to `end`: the shortest, along
    /// lines and across the links between them; `nil` where no way joins
    /// them.
    func path(from start: Place, to end: Place) -> [WorldVector]? {
        route(from: start, to: end)?.points
    }

    /// ``path(from:to:)`` with its `hops`: each the index of a point the
    /// way leaves across a link, the next point on the other line, the
    /// link's gap to the side of it.
    func route(from start: Place, to end: Place) -> (points: [WorldVector], hops: [Int])? {
        // The places the way may turn at: the network's (``Graph``), and
        // the two ends asked for where they are not among them, each put
        // between the places either side of it on its line.
        guard lines.indices.contains(start.line), lines.indices.contains(end.line) else { return nil }
        var extra: [Place] = []
        func number(of place: Place) -> Int {
            if let known = graph.index[place] { return known }
            if let added = extra.firstIndex(of: place) { return graph.stops.count + added }
            extra.append(place)
            return graph.stops.count + extra.count - 1
        }
        let from = number(of: start), to = number(of: end)
        func place(_ stop: Int) -> Place {
            stop < graph.stops.count ? graph.stops[stop] : extra[stop - graph.stops.count]
        }
        // The lines an added end stands on: their neighbours along the line,
        // worked out again with it.
        var alongChanged: [Int: [(stop: Int, cost: Double)]] = [:]
        for line in Set(extra.map(\.line)) {
            let added = extra.indices.filter { extra[$0].line == line }.map { graph.stops.count + $0 }
            let numbers = (graph.byLine[line] + added).sorted { place($0).along < place($1).along }
            for stop in numbers { alongChanged[stop] = [] }
            for (a, b) in zip(numbers, numbers.dropFirst()) {
                let cost = place(b).along - place(a).along
                alongChanged[a]?.append((b, cost))
                alongChanged[b]?.append((a, cost))
            }
        }
        let count = graph.stops.count + extra.count

        // Dijkstra's shortest path, the nearest place first (the lowest
        // number of those as near), from a heap.
        var distance = [Double](repeating: .infinity, count: count)
        var previous = [Int?](repeating: nil, count: count)
        var done = [Bool](repeating: false, count: count)
        var heap = StopHeap()
        distance[from] = 0
        heap.push(0, from)
        while let next = heap.pop() {
            let current = next.stop
            guard !done[current], next.distance == distance[current] else { continue }
            if current == to { break }
            done[current] = true
            let along = alongChanged[current] ?? (current < graph.stops.count ? graph.alongLine[current] : [])
            let across = current < graph.stops.count ? graph.acrossLinks[current] : []
            for neighbours in [along, across] {
                for (stop, cost) in neighbours where distance[current] + cost < distance[stop] {
                    distance[stop] = distance[current] + cost
                    previous[stop] = current
                    heap.push(distance[stop], stop)
                }
            }
        }
        guard distance[to] < .infinity else { return nil }
        var route = [to]
        while let before = previous[route[route.count - 1]] { route.append(before) }
        route.reverse()

        var points: [WorldVector] = [lines[start.line].path.point(at: start.along)]
        var hops: [Int] = []
        for (a, b) in zip(route, route.dropFirst()) {
            let p = place(a), q = place(b)
            if p.line == q.line {
                let line = lines[p.line].path
                let along = line.points(from: min(p.along, q.along), to: max(p.along, q.along))
                points += p.along <= q.along ? along : along.reversed()
            } else {
                hops.append(points.count - 1)
                points.append(lines[q.line].path.point(at: q.along))
            }
        }
        return (points, hops)
    }

    /// A binary min-heap of places by distance, the lower number first
    /// among places as near, for ``route(from:to:)``.
    private struct StopHeap {
        private var items: [(distance: Double, stop: Int)] = []

        private static func before(_ a: (distance: Double, stop: Int), _ b: (distance: Double, stop: Int)) -> Bool {
            a.distance < b.distance || (a.distance == b.distance && a.stop < b.stop)
        }

        mutating func push(_ distance: Double, _ stop: Int) {
            items.append((distance, stop))
            var child = items.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard Self.before(items[child], items[parent]) else { break }
                items.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> (distance: Double, stop: Int)? {
            guard let first = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var parent = 0
                while true {
                    let left = 2 * parent + 1, right = left + 1
                    var smallest = parent
                    if left < items.count, Self.before(items[left], items[smallest]) { smallest = left }
                    if right < items.count, Self.before(items[right], items[smallest]) { smallest = right }
                    if smallest == parent { break }
                    items.swapAt(parent, smallest)
                    parent = smallest
                }
            }
            return first
        }
    }

    /// The gentlest a way moves over from one line to the one beside it
    /// (``eased(_:hops:)``): as a curve of 300 m either way.
    static let easedRadius = 300 * metre
    /// A step to the side shorter than this is left as it is: the way's
    /// smoothing takes it up.
    static let easedGap = 2 * metre

    /// `points` with each step to the side at `hops` (the index of the
    /// point before it) laid slanting, as a crossover is: where the way
    /// leaves one line for another drawn beside it (a link's gap, or an
    /// end on track or on a line a few metres from the one it follows),
    /// the points either side of the step are left out over the length a
    /// crossover of ``easedRadius`` takes, √(4 × radius × gap), half
    /// before it and half after, or what the way has there, and a curve
    /// joins the two, leaving the one line along it and reaching the other
    /// along it. Straight across, 12 m to the side in 12 m, no track could
    /// follow it.
    ///
    /// `leaving` and `arriving` are the ways the track runs at the first
    /// and the last point, where they stand on track: the curve from the
    /// first, and to the last, runs along them there.
    static func eased(_ points: [WorldVector], hops: [Int], leaving: WorldVector? = nil, arriving: WorldVector? = nil) -> [WorldVector] {
        let hops = hops.filter { $0 >= 0 && $0 + 1 < points.count }.sorted()
        guard !hops.isEmpty else { return points }
        var runs: [[WorldVector]] = []
        var first = 0
        for hop in hops {
            runs.append(Array(points[first...hop]))
            first = hop + 1
        }
        runs.append(Array(points[first...]))
        func length(_ run: [WorldVector]) -> Double {
            zip(run, run.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
        }
        // A run between two steps gives each half of itself.
        let room = runs.indices.map { index in
            length(runs[index]) * (index == 0 || index == runs.count - 1 ? 1 : 0.5)
        }
        // `run` without its first `cut` along it.
        func trimmed(_ run: [WorldVector], by cut: Double) -> [WorldVector] {
            guard cut > 0 else { return run }
            var left = cut
            for index in run.indices.dropLast() {
                let piece = (run[index + 1] - run[index]).length
                if piece > left {
                    return [run[index] + (run[index + 1] - run[index]) * (left / piece)] + run[(index + 1)...]
                }
                left -= piece
            }
            return [run[run.count - 1]]
        }
        var eased: [WorldVector] = []
        for index in runs.indices {
            eased += runs[index]
            guard index + 1 < runs.count, let a = runs[index].last, let b = runs[index + 1].first else { continue }
            let gap = (b - a).length
            guard gap >= easedGap else { continue }
            let whole = (4 * easedRadius * gap).squareRoot()
            var before = min(whole / 2, room[index])
            let after = min(whole - before, room[index + 1])
            before = min(whole - after, room[index])
            let left = Array(trimmed(runs[index].reversed(), by: before).reversed())
            eased.removeLast(runs[index].count)
            eased += left
            runs[index + 1] = trimmed(runs[index + 1], by: after)
            // The curve between: a cubic from the one line's end along it
            // to the other's start along it, a point every 10 m.
            guard let from = left.last, let to = runs[index + 1].first else { continue }
            let chord = to - from
            guard chord.length >= easedGap else { continue }
            let away = left.count > 1 ? (from - left[left.count - 2]).unit : (index == 0 ? leaving : nil) ?? chord.unit
            let toward = runs[index + 1].count > 1 ? (runs[index + 1][1] - to).unit : (index + 2 == runs.count ? arriving : nil) ?? chord.unit
            let c1 = from + away * (chord.length / 3), c2 = to - toward * (chord.length / 3)
            let steps = Int((chord.length / (10 * metre)).rounded(.up))
            for step in 1..<max(steps, 1) {
                let t = Double(step) / Double(steps), u = 1 - t
                eased.append(from * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + to * (t * t * t))
            }
        }
        return eased
    }

    /// How far along `line` its point nearest `point` is, if it is within
    /// `reach`.
    private static func nearest(to point: WorldVector, on line: Line, within reach: Double) -> (along: Double, distance: Double)? {
        let path = line.path
        var best: (along: Double, distance: Double)?
        for index in path.points.indices.dropLast() {
            let a = path.points[index], b = path.points[index + 1]
            guard point.x >= min(a.x, b.x) - reach, point.x <= max(a.x, b.x) + reach,
                  point.y >= min(a.y, b.y) - reach, point.y <= max(a.y, b.y) + reach else { continue }
            let along = b - a
            let squared = along.dot(along)
            let t = squared > 0 ? max(0, min(1, (point - a).dot(along) / squared)) : 0
            let away = (a + along * t - point).length
            if away <= (best?.distance ?? reach) {
                best = (path.distances[index] + t * (path.distances[index + 1] - path.distances[index]), away)
            }
        }
        return best
    }
}

/// What the real lines of a map were worked out for: where the map is and
/// how far it reaches (``GameSession/realRailwayTraces``).
struct RealRailwayTracesKey: Equatable {
    let frame: RealWorldFrame
    let bounds: WorldBounds
}

/// What ``GameSession/networkTracedWay`` was worked out for.
struct TracedWayKey: Equatable {
    let lines: RealRailwayTracesKey
    let from: WorldCoordinate
    let to: WorldCoordinate
}

/// What ``GameSession/tracedRoute(from:to:reach:)`` was worked out for.
struct TracedRouteKey: Equatable {
    let lines: RealRailwayTracesKey
    let from: PlanPoint
    let to: PlanPoint
    let reach: Double
}
