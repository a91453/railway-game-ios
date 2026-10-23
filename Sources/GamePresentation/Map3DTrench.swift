import GameCore

// Decision 375: the trench of track that runs below the drawn ground.
//
// The ground is drawn on the 64 m grid (``Map3DScene/Builder/drawnGround``),
// the track at its own height. Where that is under the ground (a cutting,
// a portal's approach, and surface track a little under the 64 m
// triangles), the ground, the base map's land and its roads lay over the
// bed, and the cab (84.1, the high-speed demo) saw a road and a white
// plane run into the hills instead of the rails. Each such stretch has a
// trench now: a floor beside the bed and grass slopes 1 : 1 up to the
// ground, cut out of the ground and of everything laid on it; a road
// across a trench deep enough for a train stays as a bridge over it.
//
// The cut is the reference's (`Railway/taiwan-rail-reference-clean/source/rail-3d/integration/portal-clearance.js`,
// `outsidePortalClearance`): a polygon less convex corridors along the
// track's samples, each corridor's sides in turn keeping what lies outside
// them; here level, as the ground lies on its 64 m triangles. Its terrain
// is a fine mesh lowered along the track (`Railway/city_world_reference`'s
// `carve`), which a 64 m grid cannot follow, so the trench's slopes are
// drawn as faces of their own (gap: no reference draws them). The 1 : 1
// slope is the embankment's (``Map3DScene/Builder/addTrackPiece(_:kind:)``)
// and the tunnel's bank's.

/// Decision 375: the trenches of the whole network's track, laid out as a
/// scene lays them (``Map3DTrackCover``, so a chunk built apart cuts the
/// same ground).
struct Map3DTrenches: Sendable {
    /// One cross-section of a trench, at a sample of the track's centre
    /// line.
    struct Section: Sendable {
        /// The rails' middle (``Map3DScene/railLift`` over the track).
        let rail: Map3DPoint
        /// Level, a metre long, to the track's right.
        let across: Map3DPoint
        /// How far the floor reaches each side (against ``across``, then
        /// along it), metres.
        let floor: (minus: Float, plus: Float)
        /// How far the rim reaches each side: as far as the floor where
        /// another trench runs beside (no slope between them).
        let rim: (minus: Float, plus: Float)

        /// The floor's height: a little under the bed's top, so its sides
        /// show.
        var floorHeight: Float { rail.y - Map3DScene.Builder.bedDrop - Map3DTrenches.floorDrop }

        func edge(_ side: Float, _ reach: Float) -> Map3DPoint { rail + across * (side * reach) }
    }

    /// The runs of sections, each along one stretch of track.
    let runs: [[Section]]
    /// Where each run opens into a tunnel: at its first section, at its
    /// last; the trench's end there is closed round the portal.
    let portalEnds: [(first: Bool, last: Bool)]
    /// The corridors cut out of the ground: one convex piece between each
    /// two sections of a run, level, in scene metres, with the floor's
    /// height along it.
    let pieces: [(ring: [Map3DBaseMap.Point], floor: Float, along: Map3DPoint)]
    /// The pieces by the ``Map3DTrackCover/cell`` squares their boxes touch.
    let cells: [Map3DScene.ChunkKey: [Int]]

    /// None.
    init() {
        runs = []
        portalEnds = []
        pieces = []
        cells = [:]
    }

    /// The floor's reach from the rails' middle (the bed's foot, 2.3 m,
    /// and a drain) and how far under the bed's top it lies, metres.
    static let floorReach: Float = 2.9
    static let floorDrop: Float = 0.3
    /// How far apart two trenches' tracks may run and share one floor.
    static let shared: Float = 15
    /// Track whose bed's top lies less than this over the drawn ground is
    /// in a trench: the base map's land and roads lie up to 0.42 m over it.
    static let clearance: Float = 0.45
    /// A road across a trench this deep (the bed's top to the ground) is a
    /// bridge over it: a train and its overhead line under its deck.
    static let bridgeDepth: Float = 6.5

    init(runs: [[Section]], portalEnds: [(first: Bool, last: Bool)]) {
        self.runs = runs
        self.portalEnds = portalEnds
        var pieces: [(ring: [Map3DBaseMap.Point], floor: Float, along: Map3DPoint)] = []
        for run in runs {
            for (a, b) in zip(run, run.dropFirst()) {
                let corners = [a.edge(-1, a.rim.minus), b.edge(-1, b.rim.minus), b.edge(1, b.rim.plus), a.edge(1, a.rim.plus)]
                let ring = Self.hull(corners.map { Map3DBaseMap.Point(x: Double($0.x), z: Double($0.z)) })
                guard ring.count >= 3, let along = Map3DPoint(b.rail.x - a.rail.x, 0, b.rail.z - a.rail.z).normalized else { continue }
                pieces.append((ring, (a.floorHeight + b.floorHeight) / 2, along))
            }
        }
        // Where one run ends at another's end (spans meet at a node), their
        // end lines cross at the rails and leave a wedge open between them
        // on a bend: a piece of both lines closes it.
        var ends: [Map3DScene.ChunkKey: [(section: Section, along: Map3DPoint)]] = [:]
        for run in runs where run.count >= 2 {
            for (end, next) in [(run[0], run[1]), (run[run.count - 1], run[run.count - 2])] {
                guard let along = Map3DPoint(end.rail.x - next.rail.x, 0, end.rail.z - next.rail.z).normalized else { continue }
                let key = Map3DScene.ChunkKey(column: Int((end.rail.x * 10).rounded()), row: Int((end.rail.z * 10).rounded()))
                for other in ends[key] ?? [] {
                    let corners = [end.edge(-1, end.rim.minus), end.edge(1, end.rim.plus), other.section.edge(-1, other.section.rim.minus),
                                   other.section.edge(1, other.section.rim.plus)]
                    let ring = Self.hull(corners.map { Map3DBaseMap.Point(x: Double($0.x), z: Double($0.z)) })
                    guard ring.count >= 3 else { continue }
                    pieces.append((ring, (end.floorHeight + other.section.floorHeight) / 2, along))
                }
                ends[key, default: []].append((end, along))
            }
        }
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        for (index, piece) in pieces.enumerated() {
            let xs = piece.ring.map(\.x), zs = piece.ring.map(\.z)
            let low = Map3DTrackCover.key(x: Float(xs.min()!), z: Float(zs.min()!)), high = Map3DTrackCover.key(x: Float(xs.max()!), z: Float(zs.max()!))
            for row in low.row...high.row {
                for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(index) }
            }
        }
        self.pieces = pieces
        self.cells = cells
    }

    var isEmpty: Bool { pieces.isEmpty }

    /// The pieces whose boxes may meet the box from (`minX`, `minZ`) to
    /// (`maxX`, `maxZ`), in order.
    func pieces(minX: Double, minZ: Double, maxX: Double, maxZ: Double) -> [Int] {
        guard !cells.isEmpty else { return [] }
        let low = Map3DTrackCover.key(x: Float(minX), z: Float(minZ)), high = Map3DTrackCover.key(x: Float(maxX), z: Float(maxZ))
        var found = Set<Int>()
        for row in low.row...high.row {
            for column in low.column...high.column { found.formUnion(cells[Map3DScene.ChunkKey(column: column, row: row)] ?? []) }
        }
        return found.sorted()
    }

    /// The piece holding level point `p`, if one does.
    func piece(at p: Map3DBaseMap.Point) -> Int? {
        pieces(minX: p.x, minZ: p.z, maxX: p.x, maxZ: p.z).first { Self.holds(pieces[$0].ring, p) }
    }

    /// Whether convex `ring` (counter-clockwise, x east and z south) holds
    /// `p`.
    static func holds(_ ring: [Map3DBaseMap.Point], _ p: Map3DBaseMap.Point) -> Bool {
        for (a, b) in zip(ring, ring.dropFirst() + ring.prefix(1)) where inside(a, b)(p) < -1e-9 { return false }
        return true
    }

    /// How far `p` is inside the edge from `a` to `b` of a ring turning as
    /// ``hull(_:)``'s do (less than 0 outside it).
    static func inside(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> (Map3DBaseMap.Point) -> Double {
        { p in (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x) }
    }

    /// The convex hull of `points`, turning one way (Andrew's monotone
    /// chain).
    static func hull(_ points: [Map3DBaseMap.Point]) -> [Map3DBaseMap.Point] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.z < $1.z }
        guard sorted.count >= 3 else { return sorted }
        func turn(_ o: Map3DBaseMap.Point, _ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> Double {
            (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x)
        }
        var lower: [Map3DBaseMap.Point] = [], upper: [Map3DBaseMap.Point] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 1e-9 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 1e-9 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// `polygon` (convex) less the pieces `near`: convex pieces of it, `nil`
    /// when none of them meets it.
    func cut(_ polygon: [Map3DBaseMap.Point], by near: [Int]) -> [[Map3DBaseMap.Point]]? {
        var parts = [polygon]
        var touched = false
        for index in near {
            let ring = pieces[index].ring
            var next: [[Map3DBaseMap.Point]] = []
            for part in parts {
                // Each side of the piece in turn: what lies outside it is
                // kept, the rest goes on to the next side; what is left
                // at the end is in the piece.
                var rest = part
                var outside: [[Map3DBaseMap.Point]] = []
                for (a, b) in zip(ring, ring.dropFirst() + ring.prefix(1)) {
                    let keep = Self.inside(a, b)
                    let out = Map3DScene.Builder.clip(rest, { -keep($0) })
                    if out.count >= 3, abs(Map3DScene.Builder.area(out)) > 1e-4 { outside.append(out) }
                    rest = Map3DScene.Builder.clip(rest, keep)
                    if rest.count < 3 || abs(Map3DScene.Builder.area(rest)) <= 1e-4 { break }
                }
                if rest.count >= 3, abs(Map3DScene.Builder.area(rest)) > 1e-4 {
                    touched = true
                    next += outside
                } else {
                    next.append(part)
                }
            }
            parts = next
        }
        return touched ? parts : nil
    }
}

extension Map3DTrackCover {
    /// Decision 375: the sections of `line` (a stretch of track at the
    /// rails' height, `grounds` the drawn ground under it) that run in a
    /// trench, in runs; each run one section wider each way, where the
    /// trench comes up to the ground.
    static func trenchRuns(_ line: [Map3DPoint], grounds: [Float]) -> [ClosedRange<Int>] {
        let low = line.indices.map { line[$0].y - Map3DScene.Builder.bedDrop < grounds[$0] + Map3DTrenches.clearance }
        var runs: [ClosedRange<Int>] = []
        var index = 0
        while index < line.count {
            guard low[index] else { index += 1; continue }
            var end = index
            while end + 1 < line.count, low[end + 1] { end += 1 }
            runs.append(max(0, index - 1)...min(line.count - 1, end + 1))
            index = end + 1
        }
        return runs
    }

    /// Decision 375: `lines`' trenches, `builder`'s drawn ground round
    /// them: each section's floor and rim, the floor shared halfway to a
    /// trench beside.
    static func trenches(_ lines: [(line: [Map3DPoint], runs: [ClosedRange<Int>], opens: (first: Bool, last: Bool))],
                         builder: inout Map3DScene.Builder) -> Map3DTrenches {
        // Every trench's centre line, to find one beside.
        var segments: [(a: Map3DPoint, b: Map3DPoint)] = []
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        for (line, runs, _) in lines {
            for run in runs {
                for index in run.dropFirst() {
                    let a = line[index - 1], b = line[index]
                    let low = key(x: min(a.x, b.x) - Map3DTrenches.shared, z: min(a.z, b.z) - Map3DTrenches.shared)
                    let high = key(x: max(a.x, b.x) + Map3DTrenches.shared, z: max(a.z, b.z) + Map3DTrenches.shared)
                    for row in low.row...high.row {
                        for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(segments.count) }
                    }
                    segments.append((a, b))
                }
            }
        }
        func beside(_ point: Map3DPoint, across: Map3DPoint) -> (minus: Float?, plus: Float?) {
            var minus: Float?, plus: Float?
            for index in Set(cells[key(x: point.x, z: point.z)] ?? []) {
                let (a, b) = segments[index]
                let along = Map3DPoint(b.x - a.x, 0, b.z - a.z)
                let squared = along.dot(along)
                guard squared > 0 else { continue }
                let share = min(max(Map3DPoint(point.x - a.x, 0, point.z - a.z).dot(along) / squared, 0), 1)
                let on = a + (b - a) * share
                guard abs(point.y - on.y) <= rise else { continue }
                let gap = Map3DPoint(on.x - point.x, 0, on.z - point.z)
                let distance = gap.length, sideways = gap.dot(across)
                guard distance > reach, distance <= Map3DTrenches.shared, abs(sideways) >= distance * 0.9 else { continue }
                if sideways > 0 { plus = min(plus ?? distance, sideways) } else { minus = min(minus ?? distance, -sideways) }
            }
            return (minus, plus)
        }
        var runs: [[Map3DTrenches.Section]] = []
        var portalEnds: [(first: Bool, last: Bool)] = []
        for (line, lineRuns, opens) in lines {
            let across = Map3DMesh.acrossDirections(line)
            for run in lineRuns {
                var sections: [Map3DTrenches.Section] = []
                for index in run {
                    let rail = line[index], side = beside(rail, across: across[index])
                    let floorHeight = rail.y - Map3DScene.Builder.bedDrop - Map3DTrenches.floorDrop
                    func reach(_ sign: Float, _ shared: Float?) -> (floor: Float, rim: Float) {
                        if let shared { return (shared / 2, shared / 2) }
                        // Out 1 : 1 to the ground at the rim: twice, from
                        // the ground at the floor's edge and then at the
                        // rim that gives.
                        var rim = Map3DTrenches.floorReach
                        for _ in 0..<2 {
                            let edge = rail + across[index] * (sign * rim)
                            rim = Map3DTrenches.floorReach + max(0, builder.drawnGround(x: edge.x, z: edge.z) - floorHeight)
                        }
                        return (Map3DTrenches.floorReach, rim)
                    }
                    let minus = reach(-1, side.minus), plus = reach(1, side.plus)
                    sections.append(.init(rail: rail, across: across[index], floor: (minus.floor, plus.floor), rim: (minus.rim, plus.rim)))
                }
                runs.append(sections)
                portalEnds.append((opens.first && run.lowerBound == 0, opens.last && run.upperBound == line.count - 1))
            }
        }
        return Map3DTrenches(runs: runs, portalEnds: portalEnds)
    }
}

extension Map3DScene.Builder {
    // MARK: Cutting what lies on the ground

    /// Decision 375: `polygon` (convex, level) less the trenches: convex
    /// pieces of it, or `nil` when no trench meets it.
    func outsideTrenches(_ polygon: [Map3DBaseMap.Point]) -> [[Map3DBaseMap.Point]]? {
        let trenches = trackCover.trenches
        guard !trenches.isEmpty, let first = polygon.first else { return nil }
        var box = (minX: first.x, minZ: first.z, maxX: first.x, maxZ: first.z)
        for p in polygon {
            box = (min(box.minX, p.x), min(box.minZ, p.z), max(box.maxX, p.x), max(box.maxZ, p.z))
        }
        let near = trenches.pieces(minX: box.minX, minZ: box.minZ, maxX: box.maxX, maxZ: box.maxZ)
        guard !near.isEmpty else { return nil }
        return trenches.cut(polygon, by: near)
    }

    /// Decision 375: whether a road running along `along` (level) at level
    /// point `p` bridges the trench there: across it (more than 30° off
    /// the track) and over a trench deep enough for a train.
    mutating func bridgesTrench(at p: Map3DBaseMap.Point, along: (x: Double, z: Double)) -> Bool {
        let trenches = trackCover.trenches
        guard let index = trenches.piece(at: p) else { return false }
        let piece = trenches.pieces[index]
        let crossing = abs(Double(piece.along.x) * along.x + Double(piece.along.z) * along.z)
        return crossing < 0.86
            && drawnGround(x: Float(p.x), z: Float(p.z)) - piece.floor - Map3DTrenches.floorDrop >= Map3DTrenches.bridgeDepth
    }

    /// Decision 375: whether the road from `a` to `b` bridges a trench
    /// anywhere along it (looked at every 2 m).
    mutating func bridgesTrench(from a: Map3DBaseMap.Point, to b: Map3DBaseMap.Point) -> Bool {
        guard !trackCover.trenches.isEmpty else { return false }
        let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
        guard length > 0.01, !trackCover.trenches.pieces(minX: min(a.x, b.x), minZ: min(a.z, b.z), maxX: max(a.x, b.x), maxZ: max(a.z, b.z)).isEmpty
        else { return false }
        let along = (x: dx / length, z: dz / length), steps = max(1, Int((length / 2).rounded(.up)))
        return (0...steps).contains { step in
            let t = Double(step) / Double(steps)
            return bridgesTrench(at: Map3DBaseMap.Point(x: a.x + dx * t, z: a.z + dz * t), along: along)
        }
    }

    /// Decision 375: whether level point `p` is in a trench that a road
    /// running along `along` there gives way to (does not bridge).
    mutating func givesWay(at p: Map3DBaseMap.Point, along: (x: Double, z: Double)) -> Bool {
        trackCover.trenches.piece(at: p) != nil && !bridgesTrench(at: p, along: along)
    }

    /// Decision 375: `triangles` of `points` (laid `lift` over the drawn
    /// ground) less the trenches, each cut triangle's pieces laid as the
    /// rest are.
    mutating func outsideTrenches(_ points: [Map3DPoint], triangles: [Int], lift: Float) -> (points: [Map3DPoint], triangles: [Int]) {
        guard !trackCover.trenches.isEmpty, !points.isEmpty else { return (points, triangles) }
        let xs = points.map { Double($0.x) }, zs = points.map { Double($0.z) }
        guard !trackCover.trenches.pieces(minX: xs.min()!, minZ: zs.min()!, maxX: xs.max()!, maxZ: zs.max()!).isEmpty else {
            return (points, triangles)
        }
        var kept = points, keptTriangles: [Int] = []
        var index = 0
        while index + 2 < triangles.count {
            let corner = triangles[index..<(index + 3)]
            index += 3
            guard let pieces = outsideTrenches(corner.map { Map3DBaseMap.Point(x: Double(points[$0].x), z: Double(points[$0].z)) }) else {
                keptTriangles += corner
                continue
            }
            for piece in pieces {
                let start = kept.count
                for p in piece {
                    let x = Float(p.x), z = Float(p.z)
                    kept.append(Map3DPoint(x, drawnGround(x: x, z: z) + lift, z))
                }
                keptTriangles += Self.fan(piece.count).map { $0 + start }
            }
        }
        return (kept, keptTriangles)
    }

    /// The triangles of a fan round `ring` (convex), for ``Map3DMesh/addFlat``.
    static func fan(_ count: Int) -> [Int] {
        count < 3 ? [] : (1..<(count - 1)).flatMap { [0, $0, $0 + 1] }
    }

    // MARK: The trench

    /// Decision 375: each trench in the region: its floor, its slopes up
    /// to the drawn ground (cut where the ground's triangles meet, as a
    /// road is), and round a portal its end, closed to the ground over
    /// the portal's head wall.
    mutating func addTrenches() {
        let trenches = trackCover.trenches
        for (number, run) in trenches.runs.enumerated() {
            guard run.contains(where: { section in
                contains(x: originX + Double(section.rail.x) * Self.metre, y: originY + Double(section.rail.z) * Self.metre)
            }) else { continue }
            for (a, b) in zip(run, run.dropFirst()) {
                let middle = (a.rail + b.rail) * 0.5
                var built = Map3DMesh()
                for side: Float in [-1, 1] {
                    let floorA = side < 0 ? a.floor.minus : a.floor.plus, floorB = side < 0 ? b.floor.minus : b.floor.plus
                    let rimA = side < 0 ? a.rim.minus : a.rim.plus, rimB = side < 0 ? b.rim.minus : b.rim.plus
                    // The floor, from the rails' middle out.
                    let floor = [a.edge(side, 0), a.edge(side, floorA), b.edge(side, floorB), b.edge(side, 0)].enumerated().map { index, p in
                        Map3DPoint(p.x, (index < 2 ? a.floorHeight : b.floorHeight), p.z)
                    }
                    built.addFlat(floor, triangles: [0, 1, 2, 0, 2, 3], color: Map3DPalette.embankment, paint: Self.bank)
                    guard rimA > floorA + 0.01 || rimB > floorB + 0.01 else { continue }
                    // The slope, cut where its rim crosses the ground's
                    // grid lines and diagonals.
                    let topA = a.edge(side, rimA), topB = b.edge(side, rimB)
                    let footA = a.edge(side, floorA), footB = b.edge(side, floorB)
                    let cuts = splits(from: Map3DBaseMap.Point(x: Double(topA.x), z: Double(topA.z)), to: Map3DBaseMap.Point(x: Double(topB.x), z: Double(topB.z)))
                    func top(_ t: Float) -> Map3DPoint {
                        let p = topA + (topB - topA) * t
                        return Map3DPoint(p.x, drawnGround(x: p.x, z: p.z), p.z)
                    }
                    func foot(_ t: Float) -> Map3DPoint {
                        let p = footA + (footB - footA) * t
                        return Map3DPoint(p.x, a.floorHeight + (b.floorHeight - a.floorHeight) * t, p.z)
                    }
                    for step in 1..<cuts.count {
                        let t0 = Float(cuts[step - 1]), t1 = Float(cuts[step])
                        guard t1 - t0 > 1e-6 else { continue }
                        built.addQuad(foot(t0), foot(t1), top(t1), top(t0), color: Map3DPalette.embankment, paint: Self.bank)
                    }
                }
                mesh(at: middle) { $0.append(built) }
            }
            let opens = trenches.portalEnds[number]
            if opens.first, let first = run.first { addTrenchEnd(first) }
            if opens.last, let last = run.last { addTrenchEnd(last) }
        }
    }

    /// The end of a trench at a portal, facing back along it: the ground
    /// from rim to rim down to the floor, but where the portal's head wall
    /// stands (``portalShoulder`` past the opening, up to
    /// ``portalOverRoof`` over its roof).
    private mutating func addTrenchEnd(_ section: Map3DTrenches.Section) {
        let rimMinus = section.edge(-1, section.rim.minus), rimPlus = section.edge(1, section.rim.plus)
        // (across, height) round the end, as the trench's cross-section.
        let outline: [Map3DBaseMap.Point] = [
            .init(x: Double(-section.rim.minus), z: Double(drawnGround(x: rimMinus.x, z: rimMinus.z))),
            .init(x: Double(-section.floor.minus), z: Double(section.floorHeight)),
            .init(x: Double(section.floor.plus), z: Double(section.floorHeight)),
            .init(x: Double(section.rim.plus), z: Double(drawnGround(x: rimPlus.x, z: rimPlus.z))),
        ]
        let wall = Double(Self.boreHalfWidth + Self.portalShoulder)
        let top = Double(section.rail.y + Self.boreCrown + Self.portalOverRoof)
        let parts = [Self.clipRings([outline], by: [{ -wall - $0.x }]), Self.clipRings([outline], by: [{ $0.x - wall }]),
                     Self.clipRings([outline], by: [{ $0.x + wall }, { wall - $0.x }, { $0.z - top }])]
        var built = Map3DMesh()
        for part in parts {
            guard let ring = part.first, ring.count >= 3 else { continue }
            let corners = ring.map { section.rail + section.across * Float($0.x) + Map3DPoint(0, Float($0.z) - section.rail.y, 0) }
            built.addFacet(corners, color: Map3DPalette.embankment, paint: Self.bank)
        }
        mesh(at: section.rail) { $0.append(built) }
    }
}
