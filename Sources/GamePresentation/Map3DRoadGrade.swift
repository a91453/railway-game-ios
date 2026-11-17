import GameCore

// Decision 833 (ROAD-GRADE-CAP, NEXT_PRIORITIES §29.23): a motorway keeps
// to a motorway's grade.
//
// Every road lies on the drawn ground (decisions 234, 241, 737), and the
// ground is the Copernicus surface model on 64 m corners (decision 124):
// over the hills a motorway climbed and fell with every ridge and gully
// the corners caught. Measured on the 林口 plateau (decision 737's
// `measure.py`, 18.9 km of motorway), its grade's 95th percentile was
// 12.7 % and its steepest 24.4 %, where Taiwan's freeways keep to 5 % or
// less (the freeway design code; decision 391 ramps an expressway at 5 %).
//
// Each motorway (the tiles' `motorway`, its link roads too; a `trunk` is
// left as it is, as a mountain highway climbs steeper for real) takes a
// profile of its own: the ground along it, held to 5 % either way. Along
// every ``Map3DRoadGrade/step`` metres of it, the highest that climbs no
// faster than 5 % from the ground at any point of the same road within
// ``Map3DRoadGrade/window`` (U), and the lowest that falls no faster (L),
// meet the ground wherever it is gentler; where it is not, the profile is
// halfway between them: through a crest in a cutting, over a gully on a
// fill. Where the road ends on the ground (into a tunnel, onto another
// road), the profile meets the ground at its end, held at 5 % from it.
//
// Over the ground (a fill) it is lifted as a bridge's ramp is
// (``Map3DScene/Builder/roadRise(at:along:onDeck:)``): walls under it,
// a girder and piers once the girder is clear; a deck of the road goes no
// lower than its profile. Under the ground it runs in a cutting: the
// ground and what lies on it cut away as round the track's trenches
// (decision 375), its floor under the road and grass slopes 1 : 1 up to
// the ground.
//
// The profile is slop-taipei's `build-elevated.mjs` idea (MIT, Copyright
// (c) 2026 Mr.doob, in the reference's
// `Railway/slop-taipei-reference-clean/source/Taipei_Basin_3D_Clean/tools/taipei/`:
// heights spread from the ground at a capped grade, "the height function
// is the ramp"), along one road and both ways. Presentation only:
// GameCore's ground, the saves and the golden scenarios are untouched; the
// drawn ground itself is not moved, so nothing else on it moves.

/// Decision 833: the motorways round a scene, each with its profile held
/// to ``grade``.
struct Map3DRoadGrade: Sendable {
    /// One motorway of the base map, kept to its tile (a road on the
    /// ground, or a bridge's).
    struct Piece: Sendable {
        let kind: Map3DBaseMap.RoadKind
        let isRamp: Bool
        let onBridge: Bool
        let points: [Map3DBaseMap.Point]
        /// How far each point lies along it from the first, metres.
        let distances: [Double]
        /// The profile every ``step`` metres from its first point, and at
        /// its last: the height of the ground under the road, metres over
        /// the sea; `nil` where nothing near enough holds it.
        var profile: [Float?] = []
        /// Whether each sample lies in a cutting (``cuts``).
        var inCut: [Bool] = []
    }

    /// The steepest a motorway climbs or falls (decision 391's 5 % for an
    /// expressway).
    static let grade: Float = 0.05
    /// The steepest the profile is let climb anywhere: where the ground
    /// climbs faster than ``grade`` for longer than the window (林口's
    /// climb from the basin), held at 5 % the road would sink 27 m into
    /// its cutting; at 8 % only the window's edge is clipped (decision
    /// 833's measurements).
    static let steepest: Float = 0.08
    /// How far round a point its profile looks along the same road,
    /// metres: within ``Map3DBaseMap/bridgeReach`` less a chunk's margin,
    /// so a chunk built apart finds the same road and ground.
    static let window: Double = 420
    /// Past this far, a point's hold on the profile gives way faster and
    /// faster, without end at the window's edge, so it comes in gently
    /// rather than at once as the window reaches it: no step anywhere.
    static let taper: Double = 300

    /// How much a point `distance` metres off lets the profile climb or
    /// fall from its ground: the grade, and past ``taper`` a slack that
    /// grows without end at the window's edge (5 cm a metre steeper 60 m
    /// into it, 3 m more).
    static func slack(_ distance: Double) -> Float {
        guard distance > taper else { return grade * Float(distance) }
        guard distance < window else { return .infinity }
        let past = distance - taper
        return grade * Float(distance) + grade * Float(past * past / (window - distance))
    }
    /// How far apart the profile's samples lie, metres.
    static let step: Double = 8
    /// How far apart two pieces' lines may be and meet, metres (as
    /// bridges, ``Map3DRoadBridges/join``).
    static let join: Double = 1.5
    /// How far beyond a motorway's lanes its cutting's floor reaches,
    /// metres: its hard shoulder and a drain.
    static let shoulder: Float = 1.5
    /// How far under the road's surface its cutting's floor lies, metres.
    static let floorDrop: Float = 0.05

    var pieces: [Piece] = []
    /// The pieces' segments (piece, first point), by the ``cell`` squares
    /// their lanes reach.
    var cells: [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] = [:]
    /// The cuttings, cut out of the ground as the track's trenches are.
    var cuts = Map3DTrenches()

    var isEmpty: Bool { pieces.isEmpty }

    static let cell: Double = 32

    static func key(_ x: Double, _ z: Double) -> Map3DScene.ChunkKey {
        Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((z / cell).rounded(.down)))
    }

    /// Half a road's drawn width, metres.
    static func half(_ piece: Piece) -> Float { piece.kind.width(ramp: piece.isRamp) / 2 }

    /// The profile of `piece` `distance` metres along it, and whether it is
    /// in a cutting there (both samples either side are).
    func profile(of piece: Piece, at distance: Double) -> (height: Float, inCut: Bool)? {
        guard let total = piece.distances.last, !piece.profile.isEmpty else { return nil }
        let at = min(max(distance, 0), total)
        let below = min(Int((at / Self.step).rounded(.down)), piece.profile.count - 1)
        let above = min(below + 1, piece.profile.count - 1)
        guard let low = piece.profile[below], let high = piece.profile[above] else { return nil }
        let start = Double(below) * Self.step, end = min(Double(above) * Self.step, total)
        let share = end > start ? Float((at - start) / (end - start)) : 0
        return (low + (high - low) * share, piece.inCut[below] && piece.inCut[above])
    }

    /// The profile under level point `p` of the motorway it lies on (a
    /// deck's when `onDeck`, else one on the ground), running along `along`
    /// (or any way, when `nil`): the nearest such piece's.
    func profile(at p: Map3DBaseMap.Point, along: (x: Double, z: Double)?, onDeck: Bool) -> (height: Float, inCut: Bool)? {
        var best: (distance: Double, found: (height: Float, inCut: Bool))?
        for (number, index) in cells[Self.key(p.x, p.z)] ?? [] {
            let piece = pieces[number]
            guard piece.onBridge == onDeck else { continue }
            let a = piece.points[index - 1], b = piece.points[index]
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01 else { continue }
            if let along, abs(dx * along.x + dz * along.z) / length < 0.9 { continue }
            let near = Map3DRoadBridges.nearest(p, a, b)
            guard near.distance <= Double(Self.half(piece)) + 0.5, best.map({ near.distance < $0.distance }) ?? true else { continue }
            let travelled = piece.distances[index - 1] + ((near.point.x - a.x) * dx + (near.point.z - a.z) * dz) / length
            if let found = profile(of: piece, at: travelled) { best = (near.distance, found) }
        }
        return best?.found
    }
}

extension Map3DScene.Builder {
    /// Decision 833: `map`'s motorways, each with its profile held to
    /// ``Map3DRoadGrade/grade`` over the drawn ground, and their cuttings.
    mutating func gradeMotorways(of map: Map3DBaseMap) -> Map3DRoadGrade {
        typealias Point = Map3DBaseMap.Point
        typealias Grade = Map3DRoadGrade
        func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }
        var result = Grade()
        let lines: [(kind: Map3DBaseMap.RoadKind, isRamp: Bool, onBridge: Bool, points: [Point])] =
            map.groundRoads.filter { $0.kind == .motorway }.map { ($0.kind, $0.isRamp, false, $0.points) }
            + map.bridges.filter { $0.kind == .motorway }.map { ($0.kind, false, true, $0.points) }
        for line in lines where line.points.count >= 2 {
            var distances = [0.0]
            for (a, b) in zip(line.points, line.points.dropFirst()) { distances.append(distances.last! + distance(a, b)) }
            guard distances.last! > 0.01 else { continue }
            result.pieces.append(.init(kind: line.kind, isRamp: line.isRamp, onBridge: line.onBridge, points: line.points, distances: distances))
        }
        guard !result.pieces.isEmpty else { return result }
        func segmentCells(_ wanted: (Int, Int) -> Bool) -> [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] {
            var cells: [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] = [:]
            for (number, piece) in result.pieces.enumerated() {
                let pad = Double(Grade.half(piece)) + 0.5
                for index in 1..<piece.points.count where wanted(number, index) {
                    let a = piece.points[index - 1], b = piece.points[index]
                    let low = Grade.key(min(a.x, b.x) - pad, min(a.z, b.z) - pad), high = Grade.key(max(a.x, b.x) + pad, max(a.z, b.z) + pad)
                    for row in low.row...high.row {
                        for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append((number, index)) }
                    }
                }
            }
            return cells
        }
        let allCells = segmentCells { _, _ in true }
        // Each piece's samples, the ground under them, and its box.
        var samples: [[Point]] = [], grounds: [[Float]] = []
        var boxes: [(minX: Double, minZ: Double, maxX: Double, maxZ: Double)] = []
        for piece in result.pieces {
            let total = piece.distances.last!
            let count = Int((total / Grade.step).rounded(.down)) + 1
            var along = (0..<count).map { Double($0) * Grade.step }
            if total - along.last! > 1e-6 { along.append(total) }
            var points: [Point] = []
            var segment = 1
            for at in along {
                while segment < piece.points.count - 1, piece.distances[segment] < at { segment += 1 }
                let a = piece.points[segment - 1], b = piece.points[segment]
                let span = piece.distances[segment] - piece.distances[segment - 1]
                let t = span > 0 ? min(max((at - piece.distances[segment - 1]) / span, 0), 1) : 0
                points.append(Point(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t))
            }
            samples.append(points)
            grounds.append(points.map { drawnGround(x: Float($0.x), z: Float($0.z)) })
            let xs = piece.points.map(\.x), zs = piece.points.map(\.z)
            boxes.append((xs.min()!, zs.min()!, xs.max()!, zs.max()!))
        }
        // Pieces meet where one's end lies on another (end to end across a
        // tile's edge, a link road's end on its motorway); an end that
        // meets none ends the road: into a tunnel, onto another road.
        var neighbours = [Set<Int>](repeating: [], count: result.pieces.count)
        var terminals = [[(point: Point, ground: Float)]](repeating: [], count: result.pieces.count)
        for (number, piece) in result.pieces.enumerated() {
            for (end, sample) in [(piece.points[0], 0), (piece.points[piece.points.count - 1], samples[number].count - 1)] {
                var met = false
                for (other, index) in allCells[Grade.key(end.x, end.z)] ?? [] where other != number {
                    let line = result.pieces[other].points
                    guard Map3DRoadBridges.nearest(end, line[index - 1], line[index]).distance <= Grade.join else { continue }
                    neighbours[number].insert(other)
                    neighbours[other].insert(number)
                    met = true
                }
                if !met { terminals[number].append((end, grounds[number][sample])) }
            }
        }
        func within(_ p: Point, _ box: (minX: Double, minZ: Double, maxX: Double, maxZ: Double)) -> Bool {
            p.x >= box.minX - Grade.window && p.x <= box.maxX + Grade.window && p.z >= box.minZ - Grade.window && p.z <= box.maxZ + Grade.window
        }
        for number in result.pieces.indices {
            var profile: [Float?] = []
            for p in samples[number] {
                // The road round it: the pieces met from this one, each
                // reaching within the window of it.
                var reached: Set<Int> = [number], frontier = [number]
                while let next = frontier.popLast() {
                    for other in neighbours[next].sorted() where !reached.contains(other) && within(p, boxes[other]) {
                        reached.insert(other)
                        frontier.append(other)
                    }
                }
                var upper = Float.infinity, lower = -Float.infinity
                var floor = -Float.infinity, ceiling = Float.infinity
                for other in reached.sorted() {
                    // A bridge's ground is what it spans: no hold on it.
                    if !result.pieces[other].onBridge {
                        for (q, ground) in zip(samples[other], grounds[other]) {
                            let d = distance(p, q)
                            guard d <= Grade.window else { continue }
                            upper = min(upper, ground + Grade.slack(d))
                            lower = max(lower, ground - Grade.slack(d))
                        }
                    }
                    for terminal in terminals[other] {
                        let d = distance(p, terminal.point)
                        guard d <= Grade.window else { continue }
                        floor = max(floor, terminal.ground - Grade.slack(d))
                        ceiling = min(ceiling, terminal.ground + Grade.slack(d))
                    }
                }
                guard upper.isFinite, lower.isFinite else {
                    profile.append(nil)
                    continue
                }
                // Held at the ground at the road's ends; between two ends
                // too close for their grade, halfway between their holds.
                var height = (upper + lower) / 2
                height = floor <= ceiling ? min(max(height, floor), ceiling) : (floor + ceiling) / 2
                profile.append(height)
            }
            // Where a far point's hold comes in steeply (in the window's
            // last stretch, ``slack(_:)``), held to ``steepest`` along the
            // piece itself, both ways.
            let along = samples[number]
            func hold(_ index: Int, to other: Int) {
                guard let height = profile[index], let held = profile[other] else { return }
                let most = Grade.steepest * Float(distance(along[index], along[other]))
                profile[index] = min(max(height, held - most), held + most)
            }
            for index in profile.indices.dropFirst() { hold(index, to: index - 1) }
            for index in profile.indices.dropLast().reversed() { hold(index, to: index + 1) }
            result.pieces[number].profile = profile
            result.pieces[number].inCut = [Bool](repeating: false, count: profile.count)
        }
        // The cuttings: each stretch of a road on the ground under it, down
        // to where the road comes back up to the ground, that somewhere
        // lies deeper than the land and roads laid over the ground.
        var cutLines: [(number: Int, range: ClosedRange<Int>)] = []
        for (number, piece) in result.pieces.enumerated() where !piece.onBridge {
            let depth = zip(piece.profile, grounds[number]).map { profile, ground in profile.map { ground - $0 } ?? 0 }
            var index = 0
            while index < depth.count {
                guard depth[index] > 0 else { index += 1; continue }
                var end = index
                while end + 1 < depth.count, depth[end + 1] > 0 { end += 1 }
                if depth[index...end].contains(where: { $0 > Map3DTrenches.clearance }) {
                    let range = max(0, index - 1)...min(depth.count - 1, end + 1)
                    cutLines.append((number, range))
                    for sample in range { result.pieces[number].inCut[sample] = true }
                }
                index = end + 1
            }
        }
        result.cuts = cuttings(cutLines, samples: samples, of: result)
        // Only where the profile leaves the ground is a road looked up on
        // it: elsewhere it lies on the ground as before.
        let moved: [[Bool]] = result.pieces.indices.map { number in
            zip(result.pieces[number].profile, grounds[number]).map { profile, ground in profile.map { abs($0 - ground) > 0.02 } ?? false }
        }
        result.cells = segmentCells { number, index in
            let piece = result.pieces[number]
            let first = Int(((piece.distances[index - 1] - Grade.step) / Grade.step).rounded(.down))
            let last = Int(((piece.distances[index] + Grade.step) / Grade.step).rounded(.up))
            return moved[number].indices.contains { $0 >= first && $0 <= last && moved[number][$0] }
        }
        return result
    }

    /// Decision 833: the sections of the motorways' cuttings `lines` (each
    /// a piece's run of samples): the floor under the road, its shoulder
    /// and a drain, shared halfway with a cutting beside (the other
    /// carriageway's), and 1 : 1 slopes up to the drawn ground.
    private mutating func cuttings(_ lines: [(number: Int, range: ClosedRange<Int>)], samples: [[Map3DBaseMap.Point]],
                                   of grade: Map3DRoadGrade) -> Map3DTrenches {
        guard !lines.isEmpty else { return Map3DTrenches() }
        // Each run's floor line, at the floor's height.
        let runs: [(line: [Map3DPoint], floor: Float)] = lines.map { number, range in
            let piece = grade.pieces[number]
            let line = range.map { index -> Map3DPoint in
                let p = samples[number][index]
                return Map3DPoint(Float(p.x), (piece.profile[index] ?? drawnGround(x: Float(p.x), z: Float(p.z))) - Map3DRoadGrade.floorDrop, Float(p.z))
            }
            return (line, Map3DRoadGrade.half(piece) + Map3DRoadGrade.shoulder)
        }
        var segments: [(a: Map3DPoint, b: Map3DPoint, run: Int)] = []
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        let reach: Float = 40
        for (number, run) in runs.enumerated() {
            for (a, b) in zip(run.line, run.line.dropFirst()) {
                let low = Map3DTrackCover.key(x: min(a.x, b.x) - reach, z: min(a.z, b.z) - reach)
                let high = Map3DTrackCover.key(x: max(a.x, b.x) + reach, z: max(a.z, b.z) + reach)
                for row in low.row...high.row {
                    for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(segments.count) }
                }
                segments.append((a, b, number))
            }
        }
        var sections: [[Map3DTrenches.Section]] = []
        for (number, run) in runs.enumerated() {
            let across = Map3DMesh.acrossDirections(run.line)
            sections.append(run.line.indices.map { index in
                let floorPoint = run.line[index]
                // Another cutting beside it, within two floors and the
                // slopes between them: the floor shared halfway.
                var minus: Float?, plus: Float?
                for segment in Set(cells[Map3DTrackCover.key(x: floorPoint.x, z: floorPoint.z)] ?? []) where segments[segment].run != number {
                    let (a, b, _) = segments[segment]
                    let along = Map3DPoint(b.x - a.x, 0, b.z - a.z), squared = along.dot(along)
                    guard squared > 0 else { continue }
                    let share = min(max(Map3DPoint(floorPoint.x - a.x, 0, floorPoint.z - a.z).dot(along) / squared, 0), 1)
                    let on = a + (b - a) * share
                    let gap = Map3DPoint(on.x - floorPoint.x, 0, on.z - floorPoint.z)
                    let distance = gap.length, sideways = gap.dot(across[index])
                    guard distance > run.floor, distance <= reach, abs(sideways) >= distance * 0.9 else { continue }
                    if sideways > 0 { plus = min(plus ?? distance, sideways) } else { minus = min(minus ?? distance, -sideways) }
                }
                func reaches(_ sign: Float, _ shared: Float?) -> (floor: Float, rim: Float) {
                    var rim = run.floor
                    for _ in 0..<2 {
                        let edge = floorPoint + across[index] * (sign * rim)
                        rim = run.floor + max(0, drawnGround(x: edge.x, z: edge.z) - floorPoint.y)
                    }
                    // Halfway to the other carriageway's floor, when its
                    // slope and this one's would cross.
                    if let shared, 2 * rim > shared { return (shared / 2, shared / 2) }
                    return (run.floor, rim)
                }
                let low = reaches(-1, minus), high = reaches(1, plus)
                // A section's rails lie a bed over its floor.
                let rail = floorPoint + Map3DPoint(0, Self.bedDrop + Map3DTrenches.floorDrop, 0)
                return Map3DTrenches.Section(rail: rail, across: across[index], floor: (low.floor, high.floor), rim: (low.rim, high.rim))
            })
        }
        return Map3DTrenches(runs: sections, portalEnds: sections.map { _ in (false, false) })
    }
}
