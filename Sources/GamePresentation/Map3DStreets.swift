import GameCore

// Decision 263: the streets of a map with no base map. The city's lots
// stand on the world's 64 m grid, so its streets run along the grid's
// lines; which line is a main road, a street or a lane, and where two lots
// share a block with no street between them, is seeded from the line's
// place in the world, the same every time. The kinds and widths are the
// real map's (decision 241: `Map3DBaseMap.RoadKind`), so a seeded street
// looks, is furnished (decision 244) and carries traffic (decision 259)
// as a real one does. The track comes first: a street gives way where it
// would run along the track or a platform, and where it crosses track
// laid on the ground it crosses it at a level crossing (平交道).

/// Which grid edges beside the city's lots are streets, and of what kind.
struct Map3DSeededStreets: Sendable {
    /// One 64 m side of a grid cell: on the horizontal line `line`
    /// (between rows `line − 1` and `line`) at column `along`, or on the
    /// vertical line `line` (between columns) at row `along`.
    struct Edge: Hashable, Comparable, Sendable {
        let horizontal: Bool
        let line: Int
        let along: Int

        static func < (a: Edge, b: Edge) -> Bool {
            (a.horizontal ? 0 : 1, a.line, a.along) < (b.horizontal ? 0 : 1, b.line, b.along)
        }
    }

    let edges: [Edge: Map3DBaseMap.RoadKind]

    /// The streets beside `built`, the city's built lots by cell and their
    /// density: every edge with a built lot on either side, of its line's
    /// kind; a lane next to dense lots widened to a street; now and then a
    /// lane between two low lots left out, so they share a block.
    init(built: [Map3DScene.ChunkKey: Int]) {
        var edges: [Edge: Map3DBaseMap.RoadKind] = [:]
        for (cell, _) in built {
            let sides = [Edge(horizontal: true, line: cell.row, along: cell.column), Edge(horizontal: true, line: cell.row + 1, along: cell.column),
                         Edge(horizontal: false, line: cell.column, along: cell.row), Edge(horizontal: false, line: cell.column + 1, along: cell.row)]
            for edge in sides where edges[edge] == nil {
                let (first, second) = Self.cells(beside: edge)
                let densities = [built[first], built[second]]
                var kind = Self.kind(ofLine: edge.line, horizontal: edge.horizontal)
                if kind == .minor, densities.contains(where: { ($0 ?? 0) >= 3 }) { kind = .tertiary }
                if kind == .minor, densities.allSatisfy({ ($0 ?? 99) <= 2 }),
                   map3DRandom(Int32(truncatingIfNeeded: edge.line), Int32(truncatingIfNeeded: edge.along), salt: edge.horizontal ? 2631 : 2632) < 0.25 {
                    continue
                }
                edges[edge] = kind
            }
        }
        // A main road or a street (not a lane: lanes end at the railway)
        // goes on across a short stretch with no lot either side (the
        // cells the track takes, a plaza): up to three edges between two of
        // the same line's, so the track does not cut it in two; its level
        // crossing joins it.
        var lines: [Edge: [Int]] = [:]
        for edge in edges.keys { lines[Edge(horizontal: edge.horizontal, line: edge.line, along: 0), default: []].append(edge.along) }
        for (line, alongs) in lines {
            let sorted = alongs.sorted()
            for (a, b) in zip(sorted, sorted.dropFirst()) where b - a > 1 && b - a <= 4 {
                let gap = (a + 1)..<b
                let open = gap.allSatisfy { along in
                    let (first, second) = Self.cells(beside: Edge(horizontal: line.horizontal, line: line.line, along: along))
                    return built[first] == nil && built[second] == nil
                }
                let kind = Self.kind(ofLine: line.line, horizontal: line.horizontal)
                guard open, Self.crossesTrack(line: line.line, horizontal: line.horizontal) else { continue }
                for along in gap { edges[Edge(horizontal: line.horizontal, line: line.line, along: along)] = kind }
            }
        }
        self.edges = edges
    }

    /// The two cells an edge lies between.
    static func cells(beside edge: Edge) -> (Map3DScene.ChunkKey, Map3DScene.ChunkKey) {
        edge.horizontal
            ? (Map3DScene.ChunkKey(column: edge.along, row: edge.line - 1), Map3DScene.ChunkKey(column: edge.along, row: edge.line))
            : (Map3DScene.ChunkKey(column: edge.line - 1, row: edge.along), Map3DScene.ChunkKey(column: edge.line, row: edge.along))
    }

    /// A grid line's kind: a main road every four to six lines each way
    /// (250–380 m, a Taiwanese town's 路 between its 街), the rest a
    /// street or a lane (巷) at about even odds.
    static func kind(ofLine line: Int, horizontal: Bool) -> Map3DBaseMap.RoadKind {
        let axis: Int32 = horizontal ? 1 : 2
        let period = 4 + min(Int(map3DRandom(axis, 0, salt: 2633) * 3), 2)
        let offset = min(Int(map3DRandom(axis, 0, salt: 2634) * Float(period)), period - 1)
        if ((line - offset) % period + period) % period == 0 { return .primary }
        return map3DRandom(Int32(truncatingIfNeeded: line), axis, salt: 2635) < 0.55 ? .tertiary : .minor
    }

    /// Whether a grid line's street goes on over the railway: every main
    /// road, half the streets (seeded), no lane; the rest end at it.
    static func crossesTrack(line: Int, horizontal: Bool) -> Bool {
        switch kind(ofLine: line, horizontal: horizontal) {
        case .primary: true
        case .tertiary: map3DRandom(Int32(truncatingIfNeeded: line), horizontal ? 1 : 2, salt: 2636) < 0.5
        default: false
        }
    }

    /// How far from a street's middle its pavement reaches, metres: where a
    /// house's front may stand.
    static func clearance(_ kind: Map3DBaseMap.RoadKind) -> Float {
        kind.width(ramp: false) / 2 + Map3DScene.Builder.sidewalk(of: kind)
    }
}

/// Decision 263: a level crossing (平交道): where a street crosses track
/// laid on the ground, a deck over the rails, ramps up to it, stop lines
/// and the barriers.
struct Map3DLevelCrossing: Sendable {
    /// On the street's middle line over the track, at the rails' height.
    let point: Map3DPoint
    /// The street's way, level.
    let along: Map3DPoint
    let kind: Map3DBaseMap.RoadKind

    /// Half the deck along the street (over a bed 4.6 m wide) and where
    /// the ramps reach the road again: long and gentle, about 1 in 13
    /// over the track's raised bed (``Map3DScene/railLift``).
    static let deckHalf: Float = 2.6
    static let rampEnd: Float = 12
    /// The deck's top over the rails' line (``Map3DScene/railLift``):
    /// just over the rail heads.
    static let deckRise: Float = 0.22
    /// Where the stop lines and the barriers stand from the track's middle.
    static let stopLine: Float = 8
    static let barrier: Float = 3.8

    var deckTop: Float { point.y + Self.deckRise }
    /// Half the street's width with its pavements.
    var halfWidth: Float { Map3DSeededStreets.clearance(kind) }

    /// How much higher than its road a point is over the deck or its
    /// ramps, given the road's surface there; 0 off the crossing.
    func rise(x: Float, z: Float, road: Float) -> Float {
        let dx = x - point.x, dz = z - point.z
        let d = abs(dx * along.x + dz * along.z), side = abs(dx * along.z - dz * along.x)
        guard side <= halfWidth + 0.5, d < Self.rampEnd else { return 0 }
        let full = max(deckTop - road, 0)
        return d <= Self.deckHalf ? full : full * (Self.rampEnd - d) / (Self.rampEnd - Self.deckHalf)
    }
}

extension Map3DScene.Builder {
    /// Decision 263: how high a level crossing lifts a street's traffic at
    /// scene point (`x`, `z`), over the street's own height there.
    mutating func crossingLift(x: Float, z: Float) -> Float {
        guard !crossings.isEmpty else { return 0 }
        var lift: Float = 0
        for crossing in crossings where abs(crossing.point.x - x) < 20 && abs(crossing.point.z - z) < 20 {
            lift = max(lift, crossing.rise(x: x, z: z, road: drawnGround(x: x, z: z) + Self.lift(of: crossing.kind)))
        }
        return lift
    }

    /// What the track does to a street from `a` to `b` (level scene points)
    /// reaching `half` metres each side: nothing; keeps it off (it would
    /// run along the track, under a viaduct's piers or over a platform, or
    /// cross a bank or a cutting); or crosses it at a level crossing.
    enum TrackMeeting: Equatable {
        case clear, blocked
        case crossing(Map3DPoint)
    }

    /// A level piece of the track (or, `isPlatform`, a platform's track)
    /// at the rails' height.
    struct TrackSegment {
        let p: Map3DPoint
        let q: Map3DPoint
        let kind: TrackSectionKind
        let isPlatform: Bool
    }

    func trackMeeting(from a: Map3DPoint, to b: Map3DPoint, half: Float, segments: [TrackSegment], index: [Int64: [Int]]) -> TrackMeeting {
        let low = (x: min(a.x, b.x) - half - 12, z: min(a.z, b.z) - half - 12)
        let high = (x: max(a.x, b.x) + half + 12, z: max(a.z, b.z) + half + 12)
        var seen = Set<Int>()
        var crossing: Map3DPoint?
        // Pieces too near the street, decided once a crossing is known: the
        // track's pieces next to its own crossing are near it too.
        var near: [(p: Map3DPoint, q: Map3DPoint, reach: Float)] = []
        let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized ?? Map3DPoint(1, 0, 0)
        for key in Self.trackCells(low: low, high: high) {
            for segment in index[key] ?? [] where seen.insert(segment).inserted {
                let (p, q, kind, isPlatform) = (segments[segment].p, segments[segment].q, segments[segment].kind, segments[segment].isPlatform)
                let clearance: Float = isPlatform ? Self.platformEdge + Self.platformWidth + 1 : Self.bedBottom / 2 + 1
                // No street over a platform, nor beside one.
                if isPlatform, Self.intersection(a, b, p, q) != nil || Self.distance(a, b, p, q) < half + clearance { return .blocked }
                if let hit = Self.intersection(a, b, p, q) {
                    // Crossing at a slant of less than 30° runs along it.
                    let way = Map3DPoint(q.x - p.x, 0, q.z - p.z).normalized ?? along
                    let slant = abs(way.x * along.z - way.z * along.x)
                    if let crossing, abs(crossing.x - hit.x) < 1, abs(crossing.z - hit.z) < 1 { continue }
                    switch kind {
                    case .tunnel: continue
                    // Under a viaduct or a bridge, where no pier stands in it.
                    case .viaduct where !isPlatform && slant > 0.5, .bridge where !isPlatform && slant > 0.5:
                        if piers.contains(where: { abs($0.x - hit.x) < half + 2 && abs($0.z - hit.z) < half + 2 }) { return .blocked }
                        continue
                    case .surface where !isPlatform && slant > 0.5 && crossing == nil:
                        let t = Map3DStreetLife.Path([p, q]).map { path in
                            min(max((Map3DPoint(hit.x - p.x, 0, hit.z - p.z)).length / path.length, 0), 1)
                        } ?? 0
                        crossing = Map3DPoint(hit.x, p.y + (q.y - p.y) * t, hit.z)
                    default:
                        return .blocked
                    }
                } else if kind != .tunnel {
                    // Beside a viaduct, clear of its piers; beside anything
                    // else, clear of its bed or platform.
                    let elevated = (kind == .viaduct || kind == .bridge) && !isPlatform
                    let reach = half + (elevated ? Self.pierAcross / 2 + 0.5 : clearance)
                    if Self.distance(a, b, p, q) < reach { near.append((p, q, reach)) }
                }
            }
        }
        for piece in near {
            // Within a crossing's own reach, it is the track crossing.
            if let crossing, Self.distance(crossing, crossing, piece.p, piece.q) < piece.reach + 16 { continue }
            return .blocked
        }
        return crossing.map { .crossing($0) } ?? .clear
    }

    /// The track's and the platforms' segments, and their numbers by the
    /// 32 m squares they touch, for ``trackMeeting(from:to:half:segments:index:)``.
    func trackSegments() -> (segments: [TrackSegment], index: [Int64: [Int]]) {
        var segments: [TrackSegment] = []
        for line in trackLines where line.points.count > 1 {
            for i in 1..<line.points.count { segments.append(TrackSegment(p: line.points[i - 1], q: line.points[i], kind: line.kind, isPlatform: false)) }
        }
        for line in platformLines where line.count > 1 {
            for i in 1..<line.count { segments.append(TrackSegment(p: line[i - 1], q: line[i], kind: .surface, isPlatform: true)) }
        }
        var index: [Int64: [Int]] = [:]
        for (number, segment) in segments.enumerated() {
            let (p, q) = (segment.p, segment.q)
            for key in Self.trackCells(low: (min(p.x, q.x), min(p.z, q.z)), high: (max(p.x, q.x), max(p.z, q.z))) {
                index[key, default: []].append(number)
            }
        }
        return (segments, index)
    }

    static func trackCells(low: (x: Float, z: Float), high: (x: Float, z: Float)) -> [Int64] {
        let columns = Int((low.x / 32).rounded(.down))...Int((high.x / 32).rounded(.down))
        let rows = Int((low.z / 32).rounded(.down))...Int((high.z / 32).rounded(.down))
        return rows.flatMap { row in columns.map { junctionKey($0, row) } }
    }

    /// Where level segments `a`–`b` and `p`–`q` cross, if they do.
    static func intersection(_ a: Map3DPoint, _ b: Map3DPoint, _ p: Map3DPoint, _ q: Map3DPoint) -> Map3DPoint? {
        let r = (x: b.x - a.x, z: b.z - a.z), s = (x: q.x - p.x, z: q.z - p.z)
        let denominator = r.x * s.z - r.z * s.x
        guard abs(denominator) > 1e-6 else { return nil }
        let t = ((p.x - a.x) * s.z - (p.z - a.z) * s.x) / denominator
        let u = ((p.x - a.x) * r.z - (p.z - a.z) * r.x) / denominator
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return Map3DPoint(a.x + r.x * t, 0, a.z + r.z * t)
    }

    /// The least level distance between segments `a`–`b` and `p`–`q`
    /// that do not cross.
    static func distance(_ a: Map3DPoint, _ b: Map3DPoint, _ p: Map3DPoint, _ q: Map3DPoint) -> Float {
        func toSegment(_ point: Map3DPoint, _ from: Map3DPoint, _ to: Map3DPoint) -> Float {
            let dx = to.x - from.x, dz = to.z - from.z
            let length = dx * dx + dz * dz
            let t = length > 0 ? min(max(((point.x - from.x) * dx + (point.z - from.z) * dz) / length, 0), 1) : 0
            let x = from.x + dx * t - point.x, z = from.z + dz * t - point.z
            return (x * x + z * z).squareRoot()
        }
        return min(toSegment(a, p, q), toSegment(b, p, q), toSegment(p, a, b), toSegment(q, a, b))
    }

    /// Decision 263: the seeded streets between `skyline`'s lots (a map with
    /// no base map), clear of the cells in `cleared` that the track takes
    /// unless a street crosses it there, then laid as a real map's roads
    /// are, with their level crossings.
    mutating func addSeededStreets(_ skyline: CitySkyline, clearOf cleared: Set<Map3DScene.ChunkKey>) {
        var built: [Map3DScene.ChunkKey: Int] = [:]
        for lot in skyline.lots(in: region) where !lot.isOpenGround {
            let cell = Map3DScene.ChunkKey(column: lot.column, row: lot.row)
            guard !cleared.contains(cell), contains(x: (Double(lot.column) + 0.5) * Double(Land.cellLength),
                                                     y: (Double(lot.row) + 0.5) * Double(Land.cellLength)) else { continue }
            built[cell] = lot.density
        }
        let streets = Map3DSeededStreets(built: built)
        let (segments, index) = trackSegments()
        var kept: [Map3DSeededStreets.Edge: Map3DBaseMap.RoadKind] = [:]
        var crossingsOn: [Map3DSeededStreets.Edge: Map3DPoint] = [:]
        for (edge, kind) in streets.edges.sorted(by: { $0.key < $1.key }) {
            let (a, b) = edgeEnds(edge)
            switch trackMeeting(from: a, to: b, half: Map3DSeededStreets.clearance(kind), segments: segments, index: index) {
            case .clear: kept[edge] = kind
            case .blocked: continue
            case .crossing(let at):
                // A lane, and half the streets, end at the railway.
                guard Map3DSeededStreets.crossesTrack(line: edge.line, horizontal: edge.horizontal) else { continue }
                kept[edge] = kind
                crossingsOn[edge] = at
            }
        }
        // A crossing only where the street goes on both sides of it, never
        // a stub over the track.
        for edge in crossingsOn.keys.sorted() {
            let before = Map3DSeededStreets.Edge(horizontal: edge.horizontal, line: edge.line, along: edge.along - 1)
            let after = Map3DSeededStreets.Edge(horizontal: edge.horizontal, line: edge.line, along: edge.along + 1)
            if kept[before] == nil || kept[after] == nil {
                kept[edge] = nil
                crossingsOn[edge] = nil
            }
        }
        streetEdges = kept
        // The level crossings first: their decks lift the traffic.
        for (edge, at) in crossingsOn.sorted(by: { $0.key < $1.key }) {
            let (a, b) = edgeEnds(edge)
            guard let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized, let kind = kept[edge] else { continue }
            crossings.append(Map3DLevelCrossing(point: at, along: along, kind: kind))
        }
        // Each line's edges next to one another of one kind, one road.
        var roads: [Map3DBaseMap.Road] = []
        let regionBounds = Map3DBaseMap.Bounds(minX: (region.minX - originX) / Self.metre, minZ: (region.minY - originY) / Self.metre,
                                               maxX: (region.maxX - originX) / Self.metre, maxZ: (region.maxY - originY) / Self.metre)
        var run: [Map3DSeededStreets.Edge] = []
        func flush() {
            guard let first = run.first, let last = run.last, let kind = kept[first] else { return }
            let start = edgeEnds(first).0, end = edgeEnds(last).1
            let length = (end - start).length
            guard let along = (end - start).normalized else { return }
            // Every 16 m, and round each crossing where its deck and ramps
            // begin and end.
            var distances = Set(stride(from: Float(0), through: length, by: 16).map { $0 })
            distances.insert(length)
            for edge in run {
                guard let at = crossingsOn[edge] else { continue }
                let d = Map3DPoint(at.x - start.x, 0, at.z - start.z).dot(along)
                for offset in [-Map3DLevelCrossing.rampEnd, -Map3DLevelCrossing.deckHalf, 0, Map3DLevelCrossing.deckHalf, Map3DLevelCrossing.rampEnd]
                    where d + offset > 0 && d + offset < length {
                    distances.insert(d + offset)
                }
            }
            let points = distances.sorted().map { d in
                Map3DBaseMap.Point(x: Double(start.x + along.x * d), z: Double(start.z + along.z * d))
            }
            roads.append(Map3DBaseMap.Road(kind: kind, isRamp: false, points: points, bounds: regionBounds))
        }
        for edge in kept.keys.sorted() {
            if let last = run.last, last.horizontal == edge.horizontal, last.line == edge.line, last.along + 1 == edge.along, kept[last] == kept[edge] {
                run.append(edge)
            } else {
                flush()
                run = [edge]
            }
        }
        flush()
        var taken = Set<Map3DScene.ChunkKey>()
        addRoads(roads, taking: &taken)
        for crossing in crossings { addLevelCrossing(crossing) }
    }

    /// The level ends of `edge`, in the scene, west to east or north to
    /// south.
    func edgeEnds(_ edge: Map3DSeededStreets.Edge) -> (Map3DPoint, Map3DPoint) {
        if edge.horizontal {
            let z = Float(gridLine(edge.line, origin: originY))
            return (Map3DPoint(Float(gridLine(edge.along, origin: originX)), 0, z), Map3DPoint(Float(gridLine(edge.along + 1, origin: originX)), 0, z))
        }
        let x = Float(gridLine(edge.line, origin: originX))
        return (Map3DPoint(x, 0, Float(gridLine(edge.along, origin: originY))), Map3DPoint(x, 0, Float(gridLine(edge.along + 1, origin: originY))))
    }

    /// A level crossing's deck over the rails and its two ramps (at every
    /// distance, as the road is), and near, its stop lines and barriers.
    mutating func addLevelCrossing(_ crossing: Map3DLevelCrossing) {
        let along = crossing.along, across = Map3DPoint(-along.z, 0, along.x)
        let half = crossing.halfWidth, top = crossing.deckTop
        let road = Map3DPalette.road(crossing.kind)
        // The deck: rubber panels over the rails, the light grey of Taiwan's
        // crossings.
        let deck = Self.crossingDeck
        let middle = Map3DPoint(crossing.point.x, 0, crossing.point.z)
        let base = Map3DPoint(middle.x, drawnGround(x: middle.x, z: middle.z), middle.z)
        var corners: [[Map3DPoint]] = []
        for end: Float in [-1, 1] {
            let near = middle + along * (end * Map3DLevelCrossing.deckHalf), far = middle + along * (end * Map3DLevelCrossing.rampEnd)
            let farY = drawnGround(x: far.x, z: far.z) + Self.lift(of: crossing.kind)
            corners.append([near + across * half + Map3DPoint(0, top, 0), near - across * half + Map3DPoint(0, top, 0),
                            far - across * half + Map3DPoint(0, farY, 0), far + across * half + Map3DPoint(0, farY, 0)])
        }
        let saved = target
        target = .base
        mesh(at: base) { mesh in
            let deckCorners = [-1, 1].flatMap { (end: Float) in
                [middle + along * (end * Map3DLevelCrossing.deckHalf) + across * (end * half), middle + along * (end * Map3DLevelCrossing.deckHalf) - across * (end * half)]
            }.map { Map3DPoint($0.x, top, $0.z) }
            let up = (deckCorners[1] - deckCorners[0]).cross(deckCorners[3] - deckCorners[0]).y > 0
            mesh.addFacet(up ? deckCorners : deckCorners.reversed(), color: deck)
            for ramp in corners {
                // Facing up whichever way the end lies.
                let up = (ramp[1] - ramp[0]).cross(ramp[3] - ramp[0]).y > 0
                mesh.addFacet(up ? ramp : ramp.reversed(), color: road)
            }
        }
        target = .near
        var feet: [Float: Map3DPoint] = [:]
        for end: Float in [-1, 1] {
            let foot = middle + along * (end * Map3DLevelCrossing.barrier) + across * (-end * (crossing.kind.width(ramp: false) / 2 + 0.6))
            feet[end] = Map3DPoint(foot.x, drawnGround(x: foot.x, z: foot.z) + Self.sidewalkLift, foot.z)
        }
        mesh(at: base) { mesh in
            for end: Float in [-1, 1] {
                // A stop line across the way in, on the driver's right.
                let line = middle + along * (end * Map3DLevelCrossing.stopLine)
                let lineY = Map3DPoint(0, base.y + Self.centreLineLift, 0)
                mesh.addBox(base: line + across * (-end * crossing.kind.width(ramp: false) / 4) + lineY, forward: along, length: 0.4,
                            width: crossing.kind.width(ramp: false) / 2, height: 0.02, top: Self.stopWhite, side: Self.stopWhite)
                // A barrier on that side: a striped post and its boom,
                // raised.
                guard let ground = feet[end] else { continue }
                mesh.addBox(base: ground, forward: along, length: 0.3, width: 0.3, height: 1.2, top: Self.barrierBlack, side: Self.barrierYellow)
                for segment in 0..<4 {
                    mesh.addBox(base: ground + Map3DPoint(0, 1.2 + Float(segment), 0), forward: along, length: 0.12, width: 0.12, height: 1,
                                top: Self.stopWhite, side: segment.isMultiple(of: 2) ? Self.barrierRed : Self.stopWhite)
                }
                // The warning lights' post beside it, its two lamps red.
                let post = ground + along * (end * 0.8)
                mesh.addBox(base: post, forward: along, length: 0.14, width: 0.14, height: 3, top: Self.barrierBlack, side: Self.barrierBlack)
                mesh.addBox(base: post + Map3DPoint(0, 2.6, 0), forward: along, length: 0.25, width: 0.9, height: 0.3, top: Self.barrierBlack,
                            side: Self.barrierRed)
            }
        }
        target = saved
    }

    static let stopWhite = Map3DColor.rgb(0xF4F4F0)
    static let crossingDeck = Map3DColor.rgb(0xB4B8C2)
    static let barrierYellow = Map3DColor.rgb(0xF2C94C)
    static let barrierBlack = Map3DColor.rgb(0x2B2E34)
    static let barrierRed = Map3DColor.rgb(0xD9473F)
}
