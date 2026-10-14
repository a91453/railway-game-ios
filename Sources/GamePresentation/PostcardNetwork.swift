import Foundation
import GameCore

// The network as the postcard draws it (decision 215, v2): a route map's
// simplification of the map's lines (`LineMap`), worked out here so Linux
// tests can check it, drawn by the app (`PostcardCard`).
//
// - No trains, no platforms: the track thin, each line a thin stroke of its
//   colour, and where lines share track, side by side, as a metro map
//   draws them (the map's own offsets, ``LineMap/Stretch/offset``, are
//   taken as each edge's way; a double track's two edges run opposite ways
//   on some networks, so here each stretch is turned the way its line runs,
//   from the line's first stop towards its last, and the lines over it put
//   in the order of their IDs, so the strokes keep their order along both
//   tracks).
// - A station is a small dot, spanning the lines that call at it.
// - Each name on a plate (decision 205), off the lines, off the other
//   names, nearer its own dot than any other; beside a neighbour's name
//   when the stations crowd (the owner, 2026-10-14: Taipei left of Nangang,
//   Banqiao under the line); pushed further out with a thin leader only
//   when nothing nearer is free.

/// The postcard's map of the lines, in points of a map `size` large.
public struct PostcardNetwork: Sendable {
    /// One line's stroke along one stretch of track.
    public struct Stroke: Hashable, Sendable {
        public let line: LineID
        public let color: LineColor?
        public let points: [ScreenPoint]
    }

    /// A station's dot: a capsule from `from` to `to` (a circle where they
    /// meet), ``dotRadius`` round.
    public struct Dot: Hashable, Sendable {
        public let from: ScreenPoint
        public let to: ScreenPoint
    }

    /// A station's name on its plate, and the leader back to its dot when
    /// the name had to stand further out.
    public struct Label: Hashable, Sendable {
        public let name: String
        public let frame: PostcardLayout.Frame
        public let leader: [ScreenPoint]?
    }

    /// Every edge of track, thin, under the lines.
    public let track: [[ScreenPoint]]
    public let strokes: [Stroke]
    public let dots: [Dot]
    public let labels: [Label]
    /// The strokes' width: thinner when lines share track.
    public let lineWidth: Double

    /// The width of a stroke when lines run side by side, and the distance
    /// between their middles.
    public static let sharedLineWidth = 2.6
    public static let lineSpacing = 3.4
    /// A network of single lines draws them wider.
    public static let singleLineWidth = 4.0
    /// The casing under every stroke (``Palette.markerFill`` in the app),
    /// this much wider.
    public static let casing = 3.0
    public static let trackWidth = 1.2
    public static let dotRadius = 2.6
    public static let dotEdge = 1.1
    /// The names' type size, and the room round them on their plates.
    public static let labelSize = 8.5
    static let platePadding = (x: 3.0, y: 2.5)
    /// How close to the map's edge a plate may come.
    static let edgeInset = 4.0

    public init(world: GameWorld, lines: LineMap, projection: some MapProjection, size: ScreenSize) {
        var geometries: [TrackEdgeID: TrackGeometry] = [:]
        func geometry(_ edge: TrackEdgeID) -> TrackGeometry? {
            if let known = geometries[edge] { return known }
            let found = world.trackGeometry(of: edge)
            geometries[edge] = found
            return found
        }
        track = world.network.edges.compactMap { edge in
            guard let shape = geometry(edge.id), shape.length > 0 else { return nil }
            return Self.simplified(shape.points(from: 0, to: shape.length).map { projection.screenPoint(of: $0) })
        }

        // Each line's stops, the way it is drawn: from the end met first
        // along the network's longer side, so lines sharing a corridor run
        // the same way.
        let chains: [LineID: [ScreenPoint]] = Dictionary(uniqueKeysWithValues: world.lines.map { line in
            var chain = line.stops.compactMap { world.station(id: $0) }.map { projection.screenPoint(of: $0.location) }
            if let first = chain.first, let last = chain.last {
                let across = abs(last.x - first.x) >= abs(last.y - first.y)
                if across ? last.x < first.x : last.y < first.y { chain.reverse() }
            }
            return (line.id, chain)
        })

        let byEdge = Dictionary(grouping: lines.stretches, by: \.edge)
        let shared = byEdge.values.contains { stretches in
            stretches.contains { a in stretches.contains { b in a.line != b.line && a.start < b.end && b.start < a.end } }
        }
        lineWidth = shared ? Self.sharedLineWidth : Self.singleLineWidth
        var strokes: [Stroke] = []
        for stretch in lines.stretches {
            guard let shape = geometry(stretch.edge) else { continue }
            let end = min(stretch.end, shape.length)
            guard stretch.start < end else { continue }
            var points = Self.simplified(shape.points(from: stretch.start, to: end).map { projection.screenPoint(of: $0) })
            guard points.count > 1 else { continue }
            if let chain = chains[stretch.line], chain.count > 1,
               Self.along(chain, points[0]) > Self.along(chain, points[points.count - 1]) {
                points.reverse()
            }
            let middle = (stretch.start + end) / 2
            let over = (byEdge[stretch.edge] ?? []).filter { $0.start <= middle && middle <= $0.end }.map(\.line)
            let order = Array(Set(over)).sorted()
            let rank = Double(order.firstIndex(of: stretch.line) ?? 0)
            let offset = (rank - Double(order.count - 1) / 2) * Self.lineSpacing
            strokes.append(Stroke(line: stretch.line, color: stretch.color, points: Self.offset(points, by: offset)))
        }
        self.strokes = strokes

        // The dots: across the lines that call at each station.
        var stopping: [StationID: [LineID]] = [:]
        for line in world.lines {
            for stop in Set(line.stops) { stopping[stop, default: []].append(line.id) }
        }
        var dots: [Dot] = []
        var places: [(name: String, at: ScreenPoint, tangent: ScreenPoint, reach: Double)] = []
        // A depot (decision 209) is no stop of a line: no dot, no name.
        for station in world.stations where !station.isDepot {
            let at = projection.screenPoint(of: station.location)
            let ids = Set(stopping[station.id] ?? [])
            let nearest = ids.compactMap { id -> (ScreenPoint, ScreenPoint)? in
                Self.nearest(to: at, on: strokes.filter { $0.line == id }.map(\.points))
            }
            let tangent = Self.nearest(to: at, on: strokes.map(\.points)).map(\.1)
                ?? Self.nearest(to: at, on: track).map(\.1) ?? ScreenPoint(x: 1, y: 0)
            let normal = ScreenPoint(x: -tangent.y, y: tangent.x)
            let across = nearest.map { ($0.0.x - at.x) * normal.x + ($0.0.y - at.y) * normal.y }
            let low = across.min() ?? 0, high = across.max() ?? 0
            dots.append(Dot(
                from: ScreenPoint(x: at.x + normal.x * low, y: at.y + normal.y * low),
                to: ScreenPoint(x: at.x + normal.x * high, y: at.y + normal.y * high)
            ))
            let middle = ScreenPoint(x: at.x + normal.x * (low + high) / 2, y: at.y + normal.y * (low + high) / 2)
            places.append((station.name, middle, tangent, (high - low) / 2 + Self.dotRadius + Self.dotEdge))
        }
        self.dots = dots
        labels = Self.place(places, avoiding: strokes.map(\.points), track: track, lineWidth: lineWidth, size: size)
    }

    // MARK: - Names

    /// The plate a name needs at ``labelSize``: a CJK character an em
    /// wide, others about 0.6 em.
    static func plateSize(_ name: String) -> (width: Double, height: Double) {
        let em = name.unicodeScalars.reduce(0.0) { $0 + ($1.value >= 0x2E80 ? 1 : 0.6) }
        return (em * labelSize + 2 * platePadding.x, labelSize + 2 * platePadding.y)
    }

    static func place(
        _ places: [(name: String, at: ScreenPoint, tangent: ScreenPoint, reach: Double)],
        avoiding lines: [[ScreenPoint]], track: [[ScreenPoint]], lineWidth: Double, size: ScreenSize
    ) -> [Label] {
        let obstacles = lines.map { (points: $0, pad: lineWidth / 2 + 1.5, box: Box(enclosing: $0)) }
            + track.map { (points: $0, pad: trackWidth / 2 + 1.5, box: Box(enclosing: $0)) }
        let bounds = Box(minX: edgeInset, minY: edgeInset, maxX: size.width - edgeInset, maxY: size.height - edgeInset)
        var placed: [Box] = []
        var labels: [Label] = []
        let rings = 3, slides: [Double] = [0, 0.35, -0.35, 0.7, -0.7]
        for (index, place) in places.enumerated() {
            let (width, height) = plateSize(place.name)
            let t = place.tangent, n = ScreenPoint(x: -t.y, y: t.x)
            var candidates: [(box: Box, cost: Double, leader: Bool)] = []
            for ring in 0..<rings {
                for side in [1.0, -1.0] {
                    for (slideIndex, slide) in slides.enumerated() {
                        let reach = place.reach + 4 + Double(ring) * (height + 2) + width / 2 * abs(n.x) + height / 2 * abs(n.y)
                        let shift = slide * (width * abs(t.x) + height * abs(t.y))
                        let x = place.at.x + side * n.x * reach + t.x * shift
                        let y = place.at.y + side * n.y * reach + t.y * shift
                        // A plate a little over the map's edge is slid back in.
                        let midX = min(max(x, bounds.minX + width / 2), bounds.maxX - width / 2)
                        let midY = min(max(y, bounds.minY + height / 2), bounds.maxY - height / 2)
                        candidates.append((Box(midX: midX, midY: midY, width: width, height: height), 0.6 * Double(ring) + 0.1 * Double(slideIndex), ring > 0))
                    }
                }
            }
            // Beside the names of the two stations before it, on their row.
            for neighbour in placed.suffix(2) where abs(neighbour.midX - place.at.x) < 60 && abs(neighbour.midY - place.at.y) < 40 {
                for left in [true, false] {
                    let x = left ? neighbour.minX - 3 - width : neighbour.maxX + 3
                    candidates.append((Box(minX: x, minY: neighbour.minY, maxX: x + width, maxY: neighbour.minY + height), 0.3, false))
                }
            }
            func penalty(_ box: Box) -> Double {
                var cost = 0.0
                if obstacles.contains(where: { box.expanded(by: $0.pad).intersects($0.box) && box.distance(to: $0.points) < $0.pad }) { cost += 10 }
                if places.contains(where: { box.expanded(by: 4).contains($0.at) }) { cost += 6 }
                let own = box.distance(to: place.at)
                if places.indices.contains(where: { $0 != index && box.distance(to: places[$0].at) < own - 0.5 }) { cost += 9 }
                if placed.contains(where: { $0.expanded(by: 2).intersects(box) }) { cost += 20 }
                if !bounds.contains(box) { cost += 8 }
                return cost
            }
            var best = candidates[0], bestCost = Double.infinity
            for candidate in candidates {
                let cost = penalty(candidate.box) + candidate.cost
                if cost < bestCost { best = candidate; bestCost = cost }
            }
            placed.append(best.box)
            let leader = best.leader
                ? [place.at, ScreenPoint(x: min(max(place.at.x, best.box.minX), best.box.maxX), y: min(max(place.at.y, best.box.minY), best.box.maxY))]
                : nil
            labels.append(Label(
                name: place.name,
                frame: PostcardLayout.Frame(x: best.box.minX, y: best.box.minY, width: width, height: height),
                leader: leader
            ))
        }
        return labels
    }

    // MARK: - Geometry

    /// An axis-aligned box on the map.
    struct Box: Hashable {
        var minX, minY, maxX, maxY: Double

        init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        init(midX: Double, midY: Double, width: Double, height: Double) {
            self.init(minX: midX - width / 2, minY: midY - height / 2, maxX: midX + width / 2, maxY: midY + height / 2)
        }

        init(enclosing points: [ScreenPoint]) {
            self.init(
                minX: points.map(\.x).min() ?? 0, minY: points.map(\.y).min() ?? 0,
                maxX: points.map(\.x).max() ?? 0, maxY: points.map(\.y).max() ?? 0
            )
        }

        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }

        func expanded(by margin: Double) -> Box {
            Box(minX: minX - margin, minY: minY - margin, maxX: maxX + margin, maxY: maxY + margin)
        }

        func intersects(_ other: Box) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }

        func contains(_ point: ScreenPoint) -> Bool {
            minX <= point.x && point.x <= maxX && minY <= point.y && point.y <= maxY
        }

        func contains(_ other: Box) -> Bool {
            minX <= other.minX && minY <= other.minY && other.maxX <= maxX && other.maxY <= maxY
        }

        func distance(to point: ScreenPoint) -> Double {
            hypot(max(minX - point.x, 0, point.x - maxX), max(minY - point.y, 0, point.y - maxY))
        }

        /// The least distance from the box to the polyline: 0 where it
        /// crosses the box.
        func distance(to points: [ScreenPoint]) -> Double {
            var least = Double.infinity
            for (a, b) in zip(points, points.dropFirst()) {
                least = min(least, distance(from: a, to: b))
                if least == 0 { return 0 }
            }
            if points.count == 1 { least = distance(to: points[0]) }
            return least
        }

        private func distance(from a: ScreenPoint, to b: ScreenPoint) -> Double {
            if contains(a) || contains(b) { return 0 }
            let corners = [
                ScreenPoint(x: minX, y: minY), ScreenPoint(x: maxX, y: minY),
                ScreenPoint(x: maxX, y: maxY), ScreenPoint(x: minX, y: maxY),
            ]
            for (c, d) in zip(corners, corners.dropFirst() + [corners[0]]) where PostcardNetwork.cross(a, b, c, d) {
                return 0
            }
            return min(
                distance(to: a), distance(to: b),
                corners.map { PostcardNetwork.distance(from: $0, toSegment: a, b) }.min() ?? .infinity
            )
        }
    }

    /// Whether segments `a`–`b` and `c`–`d` cross.
    static func cross(_ a: ScreenPoint, _ b: ScreenPoint, _ c: ScreenPoint, _ d: ScreenPoint) -> Bool {
        func side(_ p: ScreenPoint, _ q: ScreenPoint, _ r: ScreenPoint) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
        return d1 * d2 < 0 && d3 * d4 < 0
    }

    static func distance(from p: ScreenPoint, toSegment a: ScreenPoint, _ b: ScreenPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /// The point of `polylines` nearest `point`, and the unit direction of
    /// the segment it is on.
    static func nearest(to point: ScreenPoint, on polylines: [[ScreenPoint]]) -> (ScreenPoint, ScreenPoint)? {
        var best: (ScreenPoint, ScreenPoint, Double)?
        for points in polylines {
            for (a, b) in zip(points, points.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = dx * dx + dy * dy
                guard length > 0 else { continue }
                let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / length, 0), 1)
                let at = ScreenPoint(x: a.x + t * dx, y: a.y + t * dy)
                let distance = hypot(point.x - at.x, point.y - at.y)
                if distance < best?.2 ?? .infinity {
                    let norm = length.squareRoot()
                    best = (at, ScreenPoint(x: dx / norm, y: dy / norm), distance)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// How far along `chain` (a polyline) `point` lies, by its nearest
    /// point on it.
    static func along(_ chain: [ScreenPoint], _ point: ScreenPoint) -> Double {
        var travelled = 0.0, best = (distance: Double.infinity, along: 0.0)
        for (a, b) in zip(chain, chain.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            let t = length > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / (length * length), 0), 1) : 0
            let distance = hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
            if distance < best.distance { best = (distance, travelled + t * length) }
            travelled += length
        }
        return best.along
    }

    /// How far a simplified polyline may stray from the track, in points:
    /// a quarter of a point, finer than the picture's pixel (a third).
    static let tolerance = 0.25

    /// `points` with the points the line would pass within ``tolerance``
    /// of anyway left out (Douglas and Peucker's simplification): the
    /// track's geometry has a point every few metres, hundreds of thousands
    /// over a whole island.
    static func simplified(_ points: [ScreenPoint]) -> [ScreenPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(0, points.count - 1)]
        while let (first, last) = spans.popLast() {
            guard last > first + 1 else { continue }
            var farthest = (index: first, distance: 0.0)
            for index in (first + 1)..<last {
                let distance = Self.distance(from: points[index], toSegment: points[first], points[last])
                if distance > farthest.distance { farthest = (index, distance) }
            }
            if farthest.distance > tolerance {
                keep[farthest.index] = true
                spans.append((first, farthest.index))
                spans.append((farthest.index, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// `points` moved `distance` to their left (as they run; the screen's y
    /// grows downwards), each by the mean of its segments' normals.
    static func offset(_ points: [ScreenPoint], by distance: Double) -> [ScreenPoint] {
        guard distance != 0, points.count > 1 else { return points }
        return points.indices.map { index in
            let a = points[max(index - 1, 0)], b = points[min(index + 1, points.count - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            return ScreenPoint(x: points[index].x + dy / length * distance, y: points[index].y - dx / length * distance)
        }
    }
}
