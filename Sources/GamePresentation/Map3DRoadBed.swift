import GameCore

// Decision 865 (HK-ROAD-TILT): a road is level from one side to the other.
//
// Every road lay on the drawn ground corner by corner (decisions 234, 241),
// and the ground is 64 m triangles (decisions 124, 737): on a hillside a
// road took the hill's slope across its own width, one kerb metres over the
// other (Hong Kong's hillside and shore roads 3–8 m at the 95th percentile,
// `docs/handoff/HK-ROADS.md`), where a real road is cut and filled level.
//
// Each road of the base map (on the ground, or a bridge's) now has a bed:
// along its line, every ``Map3DRoadBed/step`` metres and at its bends, the
// highest the drawn ground lies anywhere across it (its lanes and
// pavements), less ``Map3DRoadBed/slack``, and no lower than the ground
// under its middle. The road, its pavements, its paint, its furniture and
// its traffic stand on the bed, both kerbs at one height; the ground is not
// moved (cutting it for every road costs what decision 834's cuttings
// cost, for thousands of roads), so the road is filled, never cut: its
// downhill side stands over the ground on a wall
// (``Map3DScene/Builder/addRoadBedWalls(_:)``).
//
// Roads meet at one height: where one road's middle lies on another's bed
// (a junction, a crossing), it is no lower than the other there, and comes
// down from it along its own line ``Map3DRoadBed/ramp`` steeper than its
// ground; two roads side by side whose beds overlap (a road's two
// carriageways) take the higher one's height while they are within
// ``Map3DRoadBed/merged`` of each other, so one's pavement is not drawn
// over the other's lanes.
//
// The idea is the reference city's terrain carved by its roads
// (`Railway/city_world_reference/source/assets/terrainTilesField-CSA8QhEb.js`,
// `carved()`: each road's half width, a bank beyond it, the road's own
// height inside), turned round: that one carves a fine height field, which
// 64 m triangles cannot follow (decision 375's note in `Map3DTrench.swift`),
// so here the roads keep the heights and the ground stays. The code is this
// project's own. Presentation only: GameCore's ground, the saves and the
// golden scenarios are untouched.

/// Decision 865: the beds of the roads round a scene.
struct Map3DRoadBed: Sendable {
    typealias Point = Map3DBaseMap.Point

    /// One road of the base map, kept to its tile (a road on the ground, or
    /// a bridge's).
    struct Piece: Sendable {
        let onBridge: Bool
        /// Half its bed: its lanes and a pavement, metres.
        let half: Double
        let points: [Point]
        /// How far each point lies along it from the first, metres.
        let distances: [Double]
        /// Its bed's bends: how far along it each lies, and the bed's
        /// height there, metres over the sea; straight between them.
        /// Everything along the road is cut at them
        /// (``Map3DScene/Builder/bedCuts(from:to:along:onDeck:turning:)``).
        var along: [Double] = []
        var levels: [Float] = []
        /// Which of them the bed turns at by more than a centimetre (its
        /// ends, where it climbs or falls to them: past them it is
        /// level): where what only has to stay near it (a wall) is cut.
        var bent: [Bool] = []

        /// The point `distance` metres along it.
        func point(at distance: Double) -> Point {
            var low = 1, high = points.count - 1
            while low < high {
                let middle = (low + high) / 2
                if distances[middle] < distance { low = middle + 1 } else { high = middle }
            }
            let a = points[low - 1], b = points[low]
            let span = distances[low] - distances[low - 1]
            let share = span > 0 ? min(max((distance - distances[low - 1]) / span, 0), 1) : 0
            return Point(x: a.x + (b.x - a.x) * share, z: a.z + (b.z - a.z) * share)
        }
    }

    /// How far apart a bed's samples lie, metres: on the whole multiples of
    /// it along each straight stretch, measured in the world (not from the
    /// road's first point), so anything laid along the same line finds the
    /// same places (``Map3DScene/Builder/bedCuts(from:to:along:onDeck:turning:)``).
    static let step: Double = 2
    /// How far under the highest ground across it a bed may lie, metres:
    /// under the least a road is lifted over its bed (a pavement's 0.26),
    /// so the road still covers the ground.
    static let slack: Float = 0.15
    /// How fast a road comes down from where another holds it up, over its
    /// own ground's grade.
    static let ramp: Float = 0.15
    /// The most another road holds one up over its own bed, metres: its
    /// ramp down then ends within 60 m, which with ``passes`` keeps what a
    /// bed depends on within ``reach``.
    static let tallest: Float = 9
    /// Two roads side by side take one height while their beds are this
    /// close, metres; twice it apart, each keeps its own, and between the
    /// two less and less of the difference.
    static let merged: Float = 1
    /// How far apart two lines may be and be one line, metres (as bridges,
    /// ``Map3DRoadBridges/join``).
    static let join: Double = 1.5
    /// How many times the roads are held up to each other: a road held up
    /// may hold up the next.
    static let passes = 3
    /// How far round the scene's region the roads on the ground get their
    /// beds, metres: ``passes`` times a ramp's 60 m and the 20 m two beds
    /// reach each other over, so a chunk built apart finds what the whole
    /// scene does.
    static let reach: Double = 250
    /// A wall stands under a bed's edge this far over the ground or more,
    /// metres: twice what a pavement's edge stood over the ground before
    /// it had a bed (its 0.26 m), which nothing closed.
    static let wall: Float = 0.5
    /// How far a bed's line may pass over or under a sample it leaves out
    /// between two bends, metres: under half what the least lifted thing
    /// on it (a pavement, 0.26 m) stands over the highest ground across
    /// it (``slack`` under the bed), so the ground stays covered.
    static let tolerance: Float = 0.05

    var pieces: [Piece] = []
    /// The pieces' segments (piece, first point), by the ``cell`` squares
    /// their beds reach.
    var cells: [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] = [:]

    var isEmpty: Bool { pieces.isEmpty }

    static let cell: Double = 32

    static func key(_ x: Double, _ z: Double) -> Map3DScene.ChunkKey {
        Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((z / cell).rounded(.down)))
    }

    /// Half a road's bed, metres: its lanes, and its pavement when it has
    /// one (``Map3DScene/Builder/sidewalk(of:)``; a link road has none).
    static func half(_ kind: Map3DBaseMap.RoadKind, ramp: Bool) -> Double {
        Double(kind.width(ramp: ramp) / 2 + (ramp ? 0 : Map3DScene.Builder.sidewalk(of: kind)))
    }

    /// How much of `over` (another road's bed over this one's, metres) a
    /// road beside it takes up.
    static func taper(_ over: Float) -> Float {
        over <= 0 ? 0 : over <= merged ? over : max(0, 2 * merged - over)
    }

    /// The height `distance` metres along samples (`along`, `levels`).
    static func level(along: [Double], levels: [Float], at distance: Double) -> Float {
        var low = 0, high = along.count - 1
        guard high > 0 else { return levels.first ?? 0 }
        if distance <= along[0] { return levels[0] }
        if distance >= along[high] { return levels[high] }
        while high - low > 1 {
            let middle = (low + high) / 2
            if along[middle] <= distance { low = middle } else { high = middle }
        }
        let span = along[high] - along[low]
        let share = span > 0 ? Float((distance - along[low]) / span) : 0
        return levels[low] + (levels[high] - levels[low]) * share
    }

    /// The bed under level point `p`: of the road nearest it whose bed
    /// reaches it (a bridge's when `onDeck`, else one on the ground),
    /// running along `along` (or any way, when `nil`), the higher of two
    /// as near; `nil` where no road's does. `beyond` metres past the bed's
    /// edge still counts (what stands beside a road stands on its bed).
    func level(at p: Point, along: (x: Double, z: Double)?, onDeck: Bool, beyond: Double = 0.5) -> Float? {
        found(at: p, along: along, onDeck: onDeck, beyond: beyond)?.level
    }

    /// The same, with the piece whose bed it is and how far along it `p`
    /// lies.
    func found(at p: Point, along: (x: Double, z: Double)?, onDeck: Bool, beyond: Double = 0.5)
        -> (piece: Int, index: Int, travelled: Double, level: Float)? {
        var best: (distance: Double, level: Float, piece: Int, index: Int, travelled: Double)?
        for (number, index) in cells[Self.key(p.x, p.z)] ?? [] {
            let piece = pieces[number]
            guard piece.onBridge == onDeck else { continue }
            let a = piece.points[index - 1], b = piece.points[index]
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01 else { continue }
            if let along, abs(dx * along.x + dz * along.z) / length < 0.9 { continue }
            let near = Map3DRoadBridges.nearest(p, a, b)
            guard near.distance <= piece.half + beyond else { continue }
            if let best, near.distance > best.distance + 1e-6 { continue }
            let travelled = piece.distances[index - 1] + ((near.point.x - a.x) * dx + (near.point.z - a.z) * dz) / length
            let found = Self.level(along: piece.along, levels: piece.levels, at: travelled)
            if let best, near.distance >= best.distance - 1e-6, found <= best.level { continue }
            best = (near.distance, found, number, index, travelled)
        }
        return best.map { ($0.piece, $0.index, $0.travelled, $0.level) }
    }

    /// Which of a bed's samples (`along` metres along it, at `levels`) are
    /// its bends: every `fixed` one (the first and the last are), and
    /// between each two of them those the line through the bends kept
    /// passes more than ``tolerance`` from (Douglas and Peucker's way,
    /// between the fixed ones only, so a bend depends on nothing past the
    /// fixed samples either side of it: a chunk built apart keeps the ones
    /// the whole scene does). The fixed ones are the road's own points and
    /// where its line crosses the ground's 64 m grid, so nothing on a bed
    /// is longer than a cell is across, as on the ground.
    static func bends(along: [Double], levels: [Float], fixed: [Bool]) -> [Int] {
        guard along.count > 2 else { return Array(along.indices) }
        var kept = [0]
        var from = 0
        for to in 1..<along.count where fixed[to] || to == along.count - 1 {
            var inner: [Int] = []
            var spans = [(from, to)]
            while let (first, last) = spans.popLast() {
                guard last - first > 1 else { continue }
                let span = along[last] - along[first]
                var worst: Float = tolerance, at: Int?
                for index in (first + 1)..<last {
                    let share = span > 0 ? Float((along[index] - along[first]) / span) : 0
                    let off = abs(levels[index] - (levels[first] + (levels[last] - levels[first]) * share))
                    if off > worst { (worst, at) = (off, index) }
                }
                guard let at else { continue }
                inner.append(at)
                spans.append((first, at))
                spans.append((at, last))
            }
            kept += inner.sorted()
            kept.append(to)
            from = to
        }
        return kept
    }

    /// Where the bed under level point `p` bends within half a
    /// ``step`` along it of `p` (from half a step behind it up to, not
    /// with, half a step ahead, so a line asked every step finds each
    /// bend): every one of them, or with `turning` the ones it turns at
    /// by more than a centimetre.
    func bends(at p: Point, along: (x: Double, z: Double), onDeck: Bool, turning: Bool) -> [Point] {
        guard let found = found(at: p, along: along, onDeck: onDeck) else { return [] }
        let piece = pieces[found.piece]
        var low = 0, high = piece.along.count
        while low < high {
            let middle = (low + high) / 2
            if piece.along[middle] < found.travelled - Self.step / 2 { low = middle + 1 } else { high = middle }
        }
        var bends: [Point] = []
        while low < piece.along.count, piece.along[low] < found.travelled + Self.step / 2 {
            if !turning || piece.bent[low] { bends.append(piece.point(at: piece.along[low])) }
            low += 1
        }
        return bends
    }
}

extension Map3DScene.Builder {
    /// Decision 865: the bed of a road `half` metres wide each side running
    /// along `along` at level point `p`, before other roads hold it up: the
    /// highest the drawn ground lies across it, less
    /// ``Map3DRoadBed/slack``, and no lower than the ground at `p`.
    mutating func bedLevel(at p: Map3DBaseMap.Point, along: (x: Double, z: Double), half: Double) -> Float {
        let left = Map3DBaseMap.Point(x: p.x + along.z * half, z: p.z - along.x * half)
        let right = Map3DBaseMap.Point(x: p.x - along.z * half, z: p.z + along.x * half)
        // The ground is flat between where the line across crosses its
        // grid and its diagonals: its highest is at one of them.
        var highest = -Float.infinity
        for t in splits(from: left, to: right) {
            highest = max(highest, drawnGround(x: Float(left.x + (right.x - left.x) * t), z: Float(left.z + (right.z - left.z) * t)))
        }
        return max(drawnGround(x: Float(p.x), z: Float(p.z)), highest - Map3DRoadBed.slack)
    }

    /// Decision 865: what a road's things stand on at level point `p`: its
    /// bed (``Map3DRoadBed/level(at:along:onDeck:beyond:)``), and the drawn
    /// ground where no road's bed reaches.
    mutating func roadGround(at p: Map3DBaseMap.Point, along: (x: Double, z: Double)? = nil, onDeck: Bool, beyond: Double = 0.5) -> Float {
        if let bed = roadBed.level(at: p, along: along, onDeck: onDeck, beyond: beyond) { return bed }
        return drawnGround(x: Float(p.x), z: Float(p.z))
    }

    /// Decision 865: the beds of `map`'s roads: every bridge's, and those
    /// of the roads on the ground within ``Map3DRoadBed/reach`` of the
    /// region, held up to each other where they meet.
    mutating func roadBed(of map: Map3DBaseMap) -> Map3DRoadBed {
        typealias Point = Map3DBaseMap.Point
        typealias Bed = Map3DRoadBed
        var result = Bed()
        let low = Point(x: (region.minX - originX) / Self.metre - Bed.reach, z: (region.minY - originY) / Self.metre - Bed.reach)
        let high = Point(x: (region.maxX - originX) / Self.metre + Bed.reach, z: (region.maxY - originY) / Self.metre + Bed.reach)
        func near(_ points: [Point]) -> Bool {
            var box = (minX: Double.infinity, minZ: Double.infinity, maxX: -Double.infinity, maxZ: -Double.infinity)
            for p in points { box = (min(box.minX, p.x), min(box.minZ, p.z), max(box.maxX, p.x), max(box.maxZ, p.z)) }
            return box.maxX >= low.x && box.minX <= high.x && box.maxZ >= low.z && box.minZ <= high.z
        }
        let lines: [(half: Double, onBridge: Bool, points: [Point])] =
            map.groundRoads.filter { near($0.points) }.map { (Bed.half($0.kind, ramp: $0.isRamp), false, $0.points) }
            + map.bridges.map { (Bed.half($0.kind, ramp: $0.isRamp), true, $0.points) }
        for line in lines where line.points.count >= 2 {
            var distances = [0.0]
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                distances.append(distances.last! + ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot())
            }
            guard distances.last! > 0.01 else { continue }
            result.pieces.append(.init(onBridge: line.onBridge, half: line.half, points: line.points, distances: distances))
        }
        guard !result.pieces.isEmpty else { return result }
        // Each piece's samples: its points, and between them the whole
        // steps of the world's metres along each stretch.
        let east = originX / Self.metre, south = originY / Self.metre
        var places: [[Point]] = [], ways: [[(x: Double, z: Double)]] = [], alongs: [[Double]] = [], raw: [[Float]] = []
        // Which samples are bends whatever the bed does there: the piece's
        // points, and where its line crosses the ground's grid.
        var fixes: [[Bool]] = []
        for piece in result.pieces {
            var place: [Point] = [], way: [(x: Double, z: Double)] = [], along: [Double] = [], levels: [Float] = [], fixed: [Bool] = []
            for index in 1..<piece.points.count {
                let a = piece.points[index - 1], b = piece.points[index]
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                guard length > 0.01 else { continue }
                let direction = (x: dx / length, z: dz / length)
                // A bend's bed is the higher of the two stretches' there.
                let first = bedLevel(at: a, along: direction, half: piece.half)
                if let last = along.last, abs(last - piece.distances[index - 1]) < 1e-9 {
                    levels[levels.count - 1] = max(levels[levels.count - 1], first)
                } else {
                    place.append(a); way.append(direction); along.append(piece.distances[index - 1]); levels.append(first); fixed.append(true)
                }
                // Between them, where the line crosses the ground's grid
                // (fixed) and its diagonals (where the ground under it may
                // bend), and the whole steps.
                let lines = splits(from: a, to: b, diagonals: false)
                var between: [(travelled: Double, fixed: Bool)] = splits(from: a, to: b).dropFirst().dropLast().map { cut in
                    (cut * length, lines.contains { abs($0 - cut) < 1e-12 })
                }.filter { $0.travelled > 0.01 && $0.travelled < length - 0.01 }
                let crossings = between.map(\.travelled)
                let start = (east + a.x) * direction.x + (south + a.z) * direction.z
                var number = Int((start / Bed.step).rounded(.down)) + 1
                while Double(number) * Bed.step < start + length - 0.01 {
                    let travelled = Double(number) * Bed.step - start
                    if travelled > 0.01, !crossings.contains(where: { abs($0 - travelled) < 0.01 }) { between.append((travelled, false)) }
                    number += 1
                }
                for sample in between.sorted(by: { $0.travelled < $1.travelled }) {
                    let p = Point(x: a.x + direction.x * sample.travelled, z: a.z + direction.z * sample.travelled)
                    place.append(p); way.append(direction); along.append(piece.distances[index - 1] + sample.travelled)
                    levels.append(bedLevel(at: p, along: direction, half: piece.half)); fixed.append(sample.fixed)
                }
                place.append(b); way.append(direction); along.append(piece.distances[index]); levels.append(bedLevel(at: b, along: direction, half: piece.half))
                fixed.append(true)
            }
            places.append(place); ways.append(way); alongs.append(along); raw.append(levels); fixes.append(fixed)
        }
        // The roads on the ground, by the squares within two beds of them.
        let widest = result.pieces.map(\.half).max() ?? 0
        var wide: [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] = [:]
        for (number, piece) in result.pieces.enumerated() {
            for index in 1..<piece.points.count {
                let a = piece.points[index - 1], b = piece.points[index]
                func register(_ pad: Double, into cells: inout [Map3DScene.ChunkKey: [(piece: Int, index: Int)]]) {
                    let low = Bed.key(min(a.x, b.x) - pad, min(a.z, b.z) - pad), high = Bed.key(max(a.x, b.x) + pad, max(a.z, b.z) + pad)
                    for row in low.row...high.row {
                        for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append((number, index)) }
                    }
                }
                // What stands 2.5 m beside a road stands on its bed.
                register(piece.half + 3, into: &result.cells)
                if !piece.onBridge { register(piece.half + widest + 0.5, into: &wide) }
            }
        }
        // What holds each sample up: another road's bed at a place along
        // it, wholly (a junction, a crossing, the same line going on) or
        // as a road beside it (``Map3DRoadBed/taper(_:)``).
        var holds = [[[(piece: Int, at: Double, beside: Bool)]]](repeating: [], count: result.pieces.count)
        for (number, piece) in result.pieces.enumerated() where !piece.onBridge {
            var mine = [[(piece: Int, at: Double, beside: Bool)]](repeating: [], count: places[number].count)
            for sample in places[number].indices {
                let p = places[number][sample], way = ways[number][sample]
                for (other, index) in wide[Bed.key(p.x, p.z)] ?? [] where other != number {
                    let against = result.pieces[other]
                    let a = against.points[index - 1], b = against.points[index]
                    let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                    guard length > 0.01 else { continue }
                    let cosine = abs(dx * way.x + dz * way.z) / length
                    let distance = Map3DRoadBridges.nearest(p, a, b).distance
                    let share = ((p.x - a.x) * dx + (p.z - a.z) * dz) / (length * length)
                    let at = against.distances[index - 1] + min(max(share, 0), 1) * length
                    if cosine >= 0.9 {
                        // Beside it, not past its end: the same line going
                        // on holds only the end it shares.
                        guard share * length >= -0.05, (share - 1) * length <= 0.05 else { continue }
                        if distance <= Bed.join {
                            mine[sample].append((other, at, false))
                        } else if distance <= piece.half + against.half {
                            mine[sample].append((other, at, true))
                        }
                    } else if distance <= against.half + piece.half * cosine + Bed.step + 1 {
                        // A step and a metre past its bed's edge, so the
                        // sample outside the edge is held too and the
                        // road meets the edge at its height.
                        mine[sample].append((other, at, false))
                    }
                }
            }
            holds[number] = mine
        }
        var levels = raw
        for _ in 0..<Bed.passes {
            var next = levels
            var moved = false
            for number in result.pieces.indices where !holds[number].isEmpty {
                var target = levels[number]
                var held = false
                for sample in target.indices {
                    var wanted = target[sample]
                    for hold in holds[number][sample] {
                        let theirs = Bed.level(along: alongs[hold.piece], levels: levels[hold.piece], at: hold.at)
                        wanted = max(wanted, hold.beside ? target[sample] + Bed.taper(theirs - target[sample]) : theirs)
                    }
                    wanted = min(wanted, max(target[sample], raw[number][sample] + Bed.tallest))
                    if wanted > target[sample] + 1e-4 {
                        target[sample] = wanted
                        held = true
                    }
                }
                guard held else { continue }
                // Down from where it is held, a ramp over its own ground;
                // never up from it (where its ground climbs, level).
                let along = alongs[number], own = raw[number]
                func carried(to sample: Int, from other: Int) -> Float {
                    min(target[other], own[sample] + (target[other] - own[other]) - Bed.ramp * Float(abs(along[sample] - along[other])))
                }
                for sample in target.indices.dropFirst() { target[sample] = max(target[sample], carried(to: sample, from: sample - 1)) }
                for sample in target.indices.dropLast().reversed() { target[sample] = max(target[sample], carried(to: sample, from: sample + 1)) }
                next[number] = target
                moved = true
            }
            levels = next
            if !moved { break }
        }
        // Each bed kept as its bends, straight between them: everything on
        // it (the road, its pavements, its paint, its walls) is cut at
        // them and no oftener.
        for number in result.pieces.indices {
            let along = alongs[number], level = levels[number]
            let kept = Bed.bends(along: along, levels: level, fixed: fixes[number])
            result.pieces[number].along = kept.map { along[$0] }
            result.pieces[number].levels = kept.map { level[$0] }
            result.pieces[number].bent = kept.indices.map { index in
                guard index > 0, index < kept.count - 1 else {
                    // An end: level past it, so it turns as it climbs to it.
                    let next = kept[index > 0 ? index - 1 : min(1, kept.count - 1)], here = kept[index]
                    let span = abs(along[next] - along[here])
                    return span > 0 && abs(level[next] - level[here]) / Float(span) * Float(Bed.step) > 0.01
                }
                let before = kept[index - 1], here = kept[index], after = kept[index + 1]
                let span = along[after] - along[before]
                let share = span > 0 ? Float((along[here] - along[before]) / span) : 0
                return abs(level[here] - (level[before] + (level[after] - level[before]) * share)) > 0.01
            }
        }
        return result
    }

    /// Decision 865: where the way from `first` to `last` along `along` is
    /// cut so it follows its road's bed (a bridge's when `onDeck`), as
    /// fractions of it: at the bed's own bends
    /// (``Map3DRoadBed/bends(at:along:onDeck:turning:)``), asked for on
    /// the whole ``Map3DRoadBed/step``s of the world's metres along it.
    /// What lies on the road (the road, its pavements, its paint) is cut
    /// at every bend, so it lies on the bed all the way; what only has to
    /// stay near it (`turning`: a wall) at the bends the bed turns at.
    /// The same places for everything along the same line, and for a
    /// chunk built apart as for the whole scene.
    func bedCuts(from first: Map3DBaseMap.Point, to last: Map3DBaseMap.Point, along: (x: Double, z: Double), onDeck: Bool, turning: Bool = false) -> [Double] {
        guard !roadBed.isEmpty else { return [] }
        let step = Map3DRoadBed.step
        let start = (originX / Self.metre + first.x) * along.x + (originY / Self.metre + first.z) * along.z
        let end = start + (last.x - first.x) * along.x + (last.z - first.z) * along.z
        guard end - start > 1e-9 else { return [] }
        var found: [Double] = []
        // From the step before the way to the one after it: a bend half a
        // step past either end is asked for from outside it.
        var number = Int((start / step).rounded(.down))
        while Double(number) * step < end + step {
            defer { number += 1 }
            let travelled = Double(number) * step - start
            for bend in roadBed.bends(at: Map3DBaseMap.Point(x: first.x + along.x * travelled, z: first.z + along.z * travelled), along: along,
                                      onDeck: onDeck, turning: turning) {
                // Where the bend lies along the way.
                let at = ((bend.x - first.x) * along.x + (bend.z - first.z) * along.z) / (end - start)
                if at > 1e-6, at < 1 - 1e-6 { found.append(at) }
            }
        }
        var cuts: [Double] = []
        for cut in found.sorted() where cuts.last.map({ cut - $0 > 1e-9 }) ?? true { cuts.append(cut) }
        return cuts
    }

    /// Decision 865: the walls under the beds of `roads` on the ground:
    /// along each side of a road (its pavement's edge) that stands
    /// ``Map3DRoadBed/wall`` or more over what lies beside it (the drawn
    /// ground, or another road's bed), from its edge down into the ground,
    /// in the road bridges' concrete. Not where a ramp's own walls or a
    /// deck's girder stand (decision 391: a road a parapet's height or
    /// more over its bed). Each tile's share, cut where the bed bends and
    /// where a wall begins or ends, no piece longer than 64 m, so a chunk
    /// built apart draws what the whole scene does.
    mutating func addRoadBedWalls(_ roads: [Map3DBaseMap.Road], look: Map3DElevatedLook = .roadBridge) {
        guard !roadBed.isEmpty else { return }
        typealias Point = Map3DBaseMap.Point
        let step = Map3DRoadBed.step
        let east = originX / Self.metre, south = originY / Self.metre
        // A side's edge at a place along a road: its top, the ground under
        // it, how far it stands over what lies beside it, whether a ramp's
        // own wall stands there instead, and the road's rise over its bed.
        struct Edge { let top: Map3DPoint; let ground: Float; let over: Float; let low: Bool; let rise: Float }
        func needs(_ edge: Edge?) -> Bool { edge.map { $0.low && $0.over >= Map3DRoadBed.wall } ?? false }
        for road in roads where road.points.count >= 2 && road.bridgeLevel == 0 {
            let half = Map3DRoadBed.half(road.kind, ramp: road.isRamp)
            let lift = (Self.sidewalk(of: road.kind) > 0 && !road.isRamp ? Self.sidewalkLift : Self.lift(of: road.kind)) - 0.02
            // A wall's piece from one edge to the next, facing out from
            // the road.
            func lay(_ first: Map3DPoint, _ firstFoot: Float, _ last: Map3DPoint, _ lastFoot: Float, side: Int) {
                let feet = [Map3DPoint(first.x, firstFoot, first.z), Map3DPoint(last.x, lastFoot, last.z)]
                mesh(at: Map3DPoint((first.x + last.x) / 2, 0, (first.z + last.z) / 2)) {
                    if side == 0 {
                        $0.addQuad(feet[1], feet[0], first, last, color: look.colour, paint: look.paint)
                    } else {
                        $0.addQuad(feet[0], feet[1], last, first, color: look.colour, paint: look.paint)
                    }
                }
            }
            // Each stretch's way; none for one too short to have one.
            let ways: [(x: Double, z: Double)?] = zip(road.points, road.points.dropFirst()).map { a, b in
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                return length > 0.01 ? (dx / length, dz / length) : nil
            }
            // How far out of `joint` a side's edge (left of the way, or
            // right) stands where the road bends from `before` to `after`:
            // on the bend's outside, where the two stretches' edges part,
            // at their corner (the pavement's mitre), so the wall goes
            // round in one; `nil` on its inside (the edges cross under the
            // road), on a straight, and round a bend sharper than 60°,
            // which a piece of its own closes.
            func corner(before: (x: Double, z: Double), after: (x: Double, z: Double), side: Double) -> (x: Double, z: Double)? {
                let first = (x: before.z * side, z: -before.x * side), second = (x: after.z * side, z: -after.x * side)
                guard first.x * after.x + first.z * after.z < -1e-9 else { return nil }
                let cosHalf = ((1 + before.x * after.x + before.z * after.z) / 2).squareRoot()
                guard cosHalf >= 0.866 else { return nil }
                let x = first.x + second.x, z = first.z + second.z, length = (x * x + z * z).squareRoot()
                return (x / length / cosHalf, z / length / cosHalf)
            }
            func outside(before: (x: Double, z: Double), after: (x: Double, z: Double), side: Double) -> Bool {
                before.z * side * after.x - before.x * side * after.z < -1e-9
            }
            // The last stretch's end, each side.
            var ended: [Edge?]?
            for index in 1..<road.points.count {
                let a = road.points[index - 1], b = road.points[index]
                guard let along = ways[index - 1] else {
                    ended = nil
                    continue
                }
                let length = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
                // The stretch's ends, the bed's bends between them, and
                // the whole steps (where a wall may begin or end).
                var stations: [(number: Int?, travelled: Double, bend: Bool)] = []
                let start = (east + a.x) * along.x + (south + a.z) * along.z
                var number = Int((start / step).rounded(.down)) + 1
                while Double(number) * step < start + length - 0.01 {
                    if Double(number) * step - start > 0.01 { stations.append((number, Double(number) * step - start, false)) }
                    number += 1
                }
                for cut in bedCuts(from: a, to: b, along: along, onDeck: false, turning: true) {
                    let travelled = cut * length
                    guard travelled > 0.01, travelled < length - 0.01 else { continue }
                    if let same = stations.firstIndex(where: { abs($0.travelled - travelled) < 0.01 }) {
                        stations[same].bend = true
                    } else {
                        stations.append((nil, travelled, true))
                    }
                }
                stations.sort { $0.travelled < $1.travelled }
                stations.insert((nil, 0, true), at: 0)
                stations.append((nil, length, true))
                // Each station's edge on each side (left, right of the
                // way); `nil` off a bed.
                let before = index >= 2 ? ways[index - 2] : nil, after = index < ways.count ? ways[index] : nil
                var edges: [[Edge?]] = []
                for (place, station) in stations.enumerated() {
                    let p = Point(x: a.x + along.x * station.travelled, z: a.z + along.z * station.travelled)
                    guard let bed = roadBed.level(at: p, along: along, onDeck: false) else {
                        edges.append([nil, nil])
                        continue
                    }
                    let raised = roadRise(at: p, along: along, onDeck: false)
                    let top = bed + lift + raised.rise
                    edges.append([1.0, -1.0].map { side in
                        // Straight out from the way, or at a bend's corner.
                        var out = (x: along.z * side, z: -along.x * side)
                        if place == 0, let before, let turned = corner(before: before, after: along, side: side) { out = turned }
                        if place == stations.count - 1, let after, let turned = corner(before: along, after: after, side: side) { out = turned }
                        let edge = Point(x: p.x + out.x * half, z: p.z + out.z * half)
                        let probe = Point(x: p.x + out.x * (half + 0.6), z: p.z + out.z * (half + 0.6))
                        let ground = drawnGround(x: Float(edge.x), z: Float(edge.z))
                        // Another road's bed beside it, at its height: no
                        // wall between them.
                        let beside = max(ground, roadBed.level(at: probe, along: nil, onDeck: false, beyond: 0) ?? ground)
                        // The bed's own standing over the ground, not a
                        // ramp's rise: a road rising to a deck has no
                        // wall under a parapet's height (decision 391).
                        return Edge(top: Map3DPoint(Float(edge.x), top, Float(edge.z)), ground: ground, over: bed + lift - beside,
                                    low: raised.rise < look.parapet, rise: raised.rise)
                    })
                }
                // Round a bend too sharp for a corner, on its outside:
                // from the last stretch's end to this one's start.
                if let ended, let before, Map3DRoadMarkings.inside(a, road.bounds) {
                    for (side, sign) in [1.0, -1.0].enumerated() {
                        guard outside(before: before, after: along, side: sign), corner(before: before, after: along, side: sign) == nil,
                              let first = ended[side], let last = edges[0][side], needs(first) || needs(last) else { continue }
                        lay(first.top, first.ground - Self.wallFoot, last.top, last.ground - Self.wallFoot, side: side)
                    }
                }
                ended = edges[edges.count - 1]
                for side in 0..<2 {
                    // Laid from one station kept to the next: the ends,
                    // the bed's bends, where a wall begins or ends, where
                    // a ramp's rise bends, and every 64 m, so each piece
                    // lies in its chunk.
                    func kept(_ place: Int) -> Bool {
                        let station = stations[place]
                        guard !station.bend, let here = edges[place][side] else { return true }
                        if let number = station.number, number % 32 == 0 { return true }
                        let before = edges[place - 1][side], after = edges[place + 1][side]
                        if needs(here) != needs(before) || needs(here) != needs(after) { return true }
                        guard let before, let after else { return true }
                        guard max(abs(here.rise), abs(before.rise), abs(after.rise)) > 0.001 else { return false }
                        let span = stations[place + 1].travelled - stations[place - 1].travelled
                        let share = span > 0 ? Float((station.travelled - stations[place - 1].travelled) / span) : 0
                        return abs(here.top.y - (before.top.y + (after.top.y - before.top.y) * share)) > 0.01
                    }
                    let places = stations.indices.filter(kept)
                    for (from, to) in zip(places, places.dropFirst()) {
                        guard let first = edges[from][side], let last = edges[to][side], needs(first) || needs(last) else { continue }
                        // The tile's own share of the road.
                        guard Map3DRoadMarkings.inside(Point(x: a.x + along.x * (stations[from].travelled + stations[to].travelled) / 2,
                                                             z: a.z + along.z * (stations[from].travelled + stations[to].travelled) / 2), road.bounds)
                        else { continue }
                        // Its foot in the ground all the way: under the
                        // ground at both ends, and lower still where the
                        // ground between them dips under the line.
                        var firstFoot = first.ground - Self.wallFoot, lastFoot = last.ground - Self.wallFoot
                        let span = stations[to].travelled - stations[from].travelled
                        var proud: Float = 0
                        for place in (from + 1)..<to {
                            guard let between = edges[place][side] else { continue }
                            let share = span > 0 ? Float((stations[place].travelled - stations[from].travelled) / span) : 0
                            proud = max(proud, firstFoot + (lastFoot - firstFoot) * share - (between.ground - Self.wallFoot))
                        }
                        firstFoot -= proud
                        lastFoot -= proud
                        lay(first.top, firstFoot, last.top, lastFoot, side: side)
                    }
                }
            }
        }
    }

    /// Decision 865: how far into the ground a bed's wall goes, metres.
    static let wallFoot: Float = 0.3
}
