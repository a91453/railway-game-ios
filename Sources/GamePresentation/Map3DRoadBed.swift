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
        /// Its samples: how far along it each lies, and the bed's height
        /// there, metres over the sea; straight between them.
        var along: [Double] = []
        var levels: [Float] = []
    }

    /// How far apart a bed's samples lie, metres: on the whole multiples of
    /// it along each straight stretch, measured in the world (not from the
    /// road's first point), so anything laid along the same line finds the
    /// same places (``Map3DScene/Builder/bedCuts(from:to:along:onDeck:)``).
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
    /// metres.
    static let wall: Float = 0.35

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
        var best: (distance: Double, level: Float)?
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
            best = (near.distance, found)
        }
        return best?.level
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
        for piece in result.pieces {
            var place: [Point] = [], way: [(x: Double, z: Double)] = [], along: [Double] = [], levels: [Float] = []
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
                    place.append(a); way.append(direction); along.append(piece.distances[index - 1]); levels.append(first)
                }
                let start = (east + a.x) * direction.x + (south + a.z) * direction.z
                var number = Int((start / Bed.step).rounded(.down)) + 1
                while Double(number) * Bed.step < start + length - 0.01 {
                    let travelled = Double(number) * Bed.step - start
                    if travelled > 0.01 {
                        let p = Point(x: a.x + direction.x * travelled, z: a.z + direction.z * travelled)
                        place.append(p); way.append(direction); along.append(piece.distances[index - 1] + travelled)
                        levels.append(bedLevel(at: p, along: direction, half: piece.half))
                    }
                    number += 1
                }
                place.append(b); way.append(direction); along.append(piece.distances[index]); levels.append(bedLevel(at: b, along: direction, half: piece.half))
            }
            places.append(place); ways.append(way); alongs.append(along); raw.append(levels)
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
        for number in result.pieces.indices {
            result.pieces[number].along = alongs[number]
            result.pieces[number].levels = levels[number]
        }
        return result
    }

    /// Decision 865: where the way from `first` to `last` along `along` is
    /// cut so it follows its road's bed (a bridge's when `onDeck`), as
    /// fractions of it: on the whole ``Map3DRoadBed/step``s of the world's
    /// metres along it, which are the bed's own samples, where the bed
    /// bends, seen a step, four or sixteen either side
    /// (``bends(_:)``). Measured in the world, so every strip along the
    /// same line (a road, its pavements, its centre line) is cut at the
    /// same places, and a chunk built apart cuts it where the whole scene
    /// does.
    mutating func bedCuts(from first: Map3DBaseMap.Point, to last: Map3DBaseMap.Point, along: (x: Double, z: Double), onDeck: Bool) -> [Double] {
        guard !roadBed.isEmpty else { return [] }
        let step = Map3DRoadBed.step
        let start = (originX / Self.metre + first.x) * along.x + (originY / Self.metre + first.z) * along.z
        let end = start + (last.x - first.x) * along.x + (last.z - first.z) * along.z
        guard end - start > 1e-9 else { return [] }
        let bed = roadBed
        var known: [Int: Float?] = [:]
        func level(_ number: Int) -> Float? {
            if let found = known[number] { return found }
            let travelled = Double(number) * step - start
            let found = bed.level(at: Map3DBaseMap.Point(x: first.x + along.x * travelled, z: first.z + along.z * travelled), along: along, onDeck: onDeck)
            known[number] = found
            return found
        }
        var cuts: [Double] = []
        var number = Int((start / step).rounded(.down)) + 1
        while Double(number) * step < end - 1e-6 {
            defer { number += 1 }
            let travelled = Double(number) * step - start
            guard travelled > 1e-6, let here = level(number) else { continue }
            let bent = Self.bendScales.contains { scale in
                guard number % scale == 0 else { return false }
                guard let before = level(number - scale), let after = level(number + scale) else { return true }
                return Self.bends([before, here, after])
            }
            if bent { cuts.append(travelled / (end - start)) }
        }
        return cuts
    }

    /// Decision 865: the walls under the beds of `roads` on the ground:
    /// along each side of a road (its pavement's edge) that stands
    /// ``Map3DRoadBed/wall`` or more over what lies beside it (the drawn
    /// ground, or another road's bed), from its edge down into the ground,
    /// in the road bridges' concrete. Not where a ramp's own walls or a
    /// deck's girder stand (decision 391: a road a parapet's height or
    /// more over its bed). Each tile's share, on the bed's own samples
    /// along the road's line, so a chunk built apart draws what the whole
    /// scene does.
    mutating func addRoadBedWalls(_ roads: [Map3DBaseMap.Road], look: Map3DElevatedLook = .roadBridge) {
        guard !roadBed.isEmpty else { return }
        typealias Point = Map3DBaseMap.Point
        let step = Map3DRoadBed.step
        let east = originX / Self.metre, south = originY / Self.metre
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
            // The last stretch's end, each side: (top, foot, over, low).
            var ended: [(top: Map3DPoint, foot: Float, over: Float, low: Bool)?]?
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                guard length > 0.01 else { continue }
                let along = (x: dx / length, z: dz / length)
                // The stretch's ends and the bed's samples between them.
                let start = (east + a.x) * along.x + (south + a.z) * along.z
                var stations: [(number: Int?, travelled: Double)] = [(nil, 0)]
                var number = Int((start / step).rounded(.down)) + 1
                while Double(number) * step < start + length - 0.01 {
                    if Double(number) * step - start > 0.01 { stations.append((number, Double(number) * step - start)) }
                    number += 1
                }
                stations.append((nil, length))
                // Each station's edge on each side (left, right of the
                // way): its top, the ground under it, and how far it
                // stands over what lies beside it; `nil` off a bed.
                struct Edge { let top: Map3DPoint; let foot: Float; let over: Float; let low: Bool }
                var edges: [[Edge?]] = []
                for station in stations {
                    let p = Point(x: a.x + along.x * station.travelled, z: a.z + along.z * station.travelled)
                    guard let bed = roadBed.level(at: p, along: along, onDeck: false) else {
                        edges.append([nil, nil])
                        continue
                    }
                    let raised = roadRise(at: p, along: along, onDeck: false)
                    let top = bed + lift + raised.rise
                    edges.append([1.0, -1.0].map { side in
                        let edge = Point(x: p.x + along.z * side * half, z: p.z - along.x * side * half)
                        let probe = Point(x: p.x + along.z * side * (half + 0.6), z: p.z - along.x * side * (half + 0.6))
                        let ground = drawnGround(x: Float(edge.x), z: Float(edge.z))
                        // Another road's bed beside it, at its height: no
                        // wall between them.
                        let beside = max(ground, roadBed.level(at: probe, along: nil, onDeck: false, beyond: 0) ?? ground)
                        // The bed's own standing over the ground, not a
                        // ramp's rise: a road rising to a deck has no
                        // wall under a parapet's height (decision 391).
                        return Edge(top: Map3DPoint(Float(edge.x), top, Float(edge.z)), foot: ground - 0.3, over: bed + lift - beside,
                                    low: raised.rise < look.parapet)
                    })
                }
                // Round a bend, from the last stretch's end to this one's
                // start.
                if let ended, Map3DRoadMarkings.inside(a, road.bounds) {
                    for side in 0..<2 {
                        guard let first = ended[side], let last = edges[0][side], first.low || last.low, max(first.over, last.over) >= Map3DRoadBed.wall,
                              abs(first.top.x - last.top.x) + abs(first.top.z - last.top.z) > 0.05 else { continue }
                        lay(first.top, first.foot, last.top, last.foot, side: side)
                    }
                }
                ended = edges[edges.count - 1].map { edge in edge.map { ($0.top, $0.foot, $0.over, $0.low) } }
                for side in 0..<2 {
                    // Laid where the top or the ground under it bends, and
                    // at the stretch's ends.
                    // No piece longer than 64 m, so each lies in its chunk.
                    func bent(_ index: Int) -> Bool {
                        guard let number = stations[index].number, let here = edges[index][side], number % 32 != 0 else { return true }
                        return Self.bendScales.contains { scale in
                            guard number % scale == 0 else { return false }
                            guard index >= scale, index + scale < stations.count, stations[index - scale].number == number - scale,
                                  stations[index + scale].number == number + scale,
                                  let before = edges[index - scale][side], let after = edges[index + scale][side] else { return true }
                            return Self.bends([before.top.y, here.top.y, after.top.y]) || Self.bends([before.foot, here.foot, after.foot])
                        }
                    }
                    let kept = stations.indices.filter(bent)
                    for (from, to) in zip(kept, kept.dropFirst()) {
                        guard let first = edges[from][side], let last = edges[to][side], first.low || last.low,
                              max(first.over, last.over) >= Map3DRoadBed.wall else { continue }
                        // The tile's own share of the road.
                        guard Map3DRoadMarkings.inside(Point(x: a.x + along.x * (stations[from].travelled + stations[to].travelled) / 2,
                                                             z: a.z + along.z * (stations[from].travelled + stations[to].travelled) / 2), road.bounds)
                        else { continue }
                        lay(first.top, first.foot, last.top, last.foot, side: side)
                    }
                }
            }
        }
    }
}
