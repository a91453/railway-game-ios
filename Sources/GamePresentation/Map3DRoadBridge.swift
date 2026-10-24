import GameCore

// Decision 391: the base map's road bridges raised over the ground.
//
// Every road lay on the drawn ground (decisions 234, 241), its bridges too,
// so a road bridge over the track ran through the embankment and the bed,
// and the owner asked (2026-10-22) for the roads at their real height. The
// tiles say which roads are bridges (`brunnel`) and, when they keep it,
// their `layer`; no source gives a road's height (TDX has none), so a
// bridge over a road or the track stands 6 m a level over the ground (an
// OpenStreetMap layer is a storey of a crossing), and higher where it must
// clear the track; one over a river or a ditch only, at the ground; the
// tallest motorway viaducts at their real decks (the freeway bureau's
// tallest bridges, data.gov.tw 30616). Roads running on from a bridge's
// ends ramp down to the ground at the reference city's grades
// (`Railway/city_world_reference`'s `roadClearance`, `A`: 5 % on an
// expressway, 6 % on a main road, 8 % on a street). Under a raised deck a
// girder and a pier every 38 m (its `regionTiles`, `W`), drawn through
// ``Map3DElevatedLook`` so the track's viaducts may draw theirs the same
// way later (NEXT_PRIORITIES 10f).

/// Decision 391: the base map's road bridges round a scene, joined across
/// the tiles' edges, each with the height of its deck.
struct Map3DRoadBridges: Sendable {
    /// One bridge of the base map, kept to its tile.
    struct Piece: Sendable {
        let kind: Map3DBaseMap.RoadKind
        let points: [Map3DBaseMap.Point]
        /// Its ``Deck`` in ``decks``.
        let deck: Int
        /// Whether its first and last points are a deck's ends: nothing of
        /// it lies past them.
        var opens = (first: false, last: false)
    }

    /// A height a deck must reach (`isFloor`) or keep under at a point,
    /// metres over the sea, giving way at the deck's grade from it.
    struct Bound: Sendable {
        let point: Map3DBaseMap.Point
        let height: Float
        let isFloor: Bool
    }

    /// Bridges joined end to end, or end to side: one deck.
    struct Deck: Sendable {
        /// Where it crosses over a lower road or the track, and how far
        /// over the ground it stands there, metres: within ``plateau`` of
        /// one, so high, then giving way at its grade. None on a culvert,
        /// over a cutting, or over nothing but water or a ditch: there it
        /// lies on the ground.
        let lifts: [(point: Map3DBaseMap.Point, rise: Float)]
        let grade: Float
        let bounds: [Bound]
    }

    /// Where a deck ends with no bridge going on: a road running on from it
    /// ramps down to the ground.
    struct End: Sendable {
        let point: Map3DBaseMap.Point
        /// Level, a metre long, out of the bridge.
        let outward: Map3DBaseMap.Point
        /// Half its road's width with its pavements, metres.
        let half: Float
        /// How far it stands over the ground there, and the grade it falls at.
        let rise: Float
        let grade: Float
    }

    var pieces: [Piece] = []
    var decks: [Deck] = []
    var ends: [End] = []
    /// The pieces' segments (piece, first point) and the ends, by the
    /// ``cell`` squares they reach.
    var segments: [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] = [:]
    var endCells: [Map3DScene.ChunkKey: [Int]] = [:]
    /// The roads on the ground, and their segments (road, first point) by
    /// the ``cell`` squares their surfaces reach: what may lie beside a
    /// raised road at its height.
    var grounds: [(kind: Map3DBaseMap.RoadKind, points: [Map3DBaseMap.Point])] = []
    var groundCells: [Map3DScene.ChunkKey: [(road: Int, index: Int)]] = [:]

    var isEmpty: Bool { pieces.isEmpty }

    static let cell: Double = 32
    /// How far apart two bridges' lines may be and be one, metres: the
    /// tiles' 4,096 units to a 2.2 km side, twice.
    static let join: Double = 1.5
    /// A level of the tiles' `layer` over the ground, metres: a storey of
    /// a crossing, the rail-3d viaduct's 6 m clear under a 1.8 m girder
    /// less the road's own 1.6 m (`regionTiles`' `B`).
    static let levelRise: Float = 6
    /// A bridge this short is a culvert over a ditch, flat in the road.
    static let culvert: Double = 20
    /// How far from where it crosses a deck keeps its full height,
    /// metres, before it gives way at its grade: so a viaduct over a
    /// street every few hundred metres stays up between them, and what
    /// lifts a point lies within ``Map3DBaseMap/bridgeReach`` of it
    /// (150 m and 6 m at 5 %, 270 m), so a chunk built apart raises it as
    /// the whole scene does.
    static let plateau: Float = 150
    /// The squares a deck's lifts are kept one to, metres.
    static let liftSpacing: Double = 50
    /// What a road must leave over the rails' bed (decision 375's
    /// bridge over a cutting: a train and its wires), and under a viaduct
    /// (the girder, then Taiwan's 4.6 m clearance for a road).
    static let overTrack: Float = Map3DTrenches.bridgeDepth
    static let underViaduct: Float = Map3DScene.Builder.girderDepth + 4.6
    /// The longest ramp down from a bridge's end, metres: within
    /// ``Map3DBaseMap/bridgeReach``, so a chunk built apart ramps as the
    /// whole scene.
    static let longestRamp: Float = 360
    /// How far past a raised road's edge another road's surface makes the
    /// two one to look at, metres: no parapet or wall between them (the
    /// owner, 2026-10-24: a road's carriageways and link roads, each its
    /// own line on the map, drew a parapet each side).
    static let beside: Float = 1.5

    /// The grade a road climbs at onto a bridge (the reference city's
    /// `A`: 5 % on an expressway, 6 % on a main road, 8 % on a street).
    static func grade(_ kind: Map3DBaseMap.RoadKind) -> Float {
        switch kind {
        case .motorway, .trunk: 0.05
        case .primary, .secondary, .tertiary: 0.06
        case .minor, .service: 0.08
        }
    }

    /// Half a road's width with its pavements, metres.
    static func half(_ kind: Map3DBaseMap.RoadKind) -> Float {
        kind.width(ramp: false) / 2 + Map3DScene.Builder.sidewalk(of: kind)
    }

    /// The freeway bureau's tallest bridges (data.gov.tw 30616, 國道最高橋梁
    /// 資訊): the deck at its tallest pier, metres over the sea (TWVD2001),
    /// at the motorway bridge OpenStreetMap draws over it (the
    /// bureau gives no position: the point on the bridge whose ground is
    /// the pier's foundation's top, or where it crosses the named river).
    static let tallestFreewayBridges: [(name: String, latitude: Double, longitude: Double, deck: Float)] = [
        ("國六 國姓高架橋 P11", 23.987_28, 120.794_28, 265.55),
        ("國五 烏塗溪橋 P3", 24.988_46, 121.658_69, 165.53),
        ("國五 潭邊高架橋 P3", 25.012_25, 121.644_06, 143.66),
        ("國三 西湖溪橋 PN2", 24.558_42, 120.754_99, 63.72),
        ("國一 泰山林口雙層橋 P328", 25.062_71, 121.394_31, 169.19),
    ]

    static func key(_ x: Double, _ z: Double) -> Map3DScene.ChunkKey {
        Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((z / cell).rounded(.down)))
    }

    /// The nearest point to `p` of the segment from `a` to `b`, and how
    /// far it is.
    static func nearest(_ p: Map3DBaseMap.Point, _ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> (point: Map3DBaseMap.Point, distance: Double) {
        let dx = b.x - a.x, dz = b.z - a.z, squared = dx * dx + dz * dz
        let t = squared > 0 ? min(max(((p.x - a.x) * dx + (p.z - a.z) * dz) / squared, 0), 1) : 0
        let on = Map3DBaseMap.Point(x: a.x + dx * t, z: a.z + dz * t)
        return (on, ((p.x - on.x) * (p.x - on.x) + (p.z - on.z) * (p.z - on.z)).squareRoot())
    }

    /// Where the segments from `a` to `b` and `c` to `d` cross, as a share
    /// of the first, if they do.
    static func crossing(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point, _ c: Map3DBaseMap.Point, _ d: Map3DBaseMap.Point) -> Double? {
        let r = (x: b.x - a.x, z: b.z - a.z), s = (x: d.x - c.x, z: d.z - c.z)
        let denominator = r.x * s.z - r.z * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.z - (c.z - a.z) * s.x) / denominator
        let u = ((c.x - a.x) * r.z - (c.z - a.z) * r.x) / denominator
        return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? t : nil
    }
}

extension Map3DScene.Builder {
    /// Decision 391: `map`'s bridges joined into decks, each deck's height
    /// over the drawn ground and what it must clear of the track
    /// (``trackCover``), and where each ends; `frame` places the tallest
    /// freeway bridges.
    mutating func bridgeDecks(of map: Map3DBaseMap, frame: RealWorldFrame?) -> Map3DRoadBridges {
        var result = Map3DRoadBridges()
        let bridges = map.bridges.filter { $0.points.count >= 2 }
        guard !bridges.isEmpty else { return result }
        typealias Point = Map3DBaseMap.Point
        // Each bridge's segments by the squares they touch.
        var cells: [Map3DScene.ChunkKey: [(piece: Int, index: Int)]] = [:]
        for (number, bridge) in bridges.enumerated() {
            for index in 1..<bridge.points.count {
                let a = bridge.points[index - 1], b = bridge.points[index], pad = Map3DRoadBridges.join
                let low = Map3DRoadBridges.key(min(a.x, b.x) - pad, min(a.z, b.z) - pad)
                let high = Map3DRoadBridges.key(max(a.x, b.x) + pad, max(a.z, b.z) + pad)
                for row in low.row...high.row {
                    for column in low.column...high.column { cells[Map3DScene.ChunkKey(column: column, row: row), default: []].append((number, index)) }
                }
            }
        }
        func others(near p: Point, besides number: Int) -> [Int] {
            var found = Set<Int>()
            for (piece, index) in cells[Map3DRoadBridges.key(p.x, p.z)] ?? [] where piece != number && !found.contains(piece) {
                let points = bridges[piece].points
                if Map3DRoadBridges.nearest(p, points[index - 1], points[index]).distance <= Map3DRoadBridges.join { found.insert(piece) }
            }
            return found.sorted()
        }
        // Bridges whose end meets another join it; an end that meets none
        // is the deck's.
        var parent = Array(bridges.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        var openEnds: [(piece: Int, last: Bool)] = []
        for (number, bridge) in bridges.enumerated() {
            for last in [false, true] {
                let near = others(near: last ? bridge.points[bridge.points.count - 1] : bridge.points[0], besides: number)
                for other in near { parent[root(other)] = root(number) }
                if near.isEmpty { openEnds.append((number, last)) }
            }
        }
        var deckOf: [Int: Int] = [:]
        var members: [[Int]] = []
        for number in bridges.indices {
            let top = root(number)
            if deckOf[top] == nil {
                deckOf[top] = members.count
                members.append([])
            }
            members[deckOf[top]!].append(number)
        }
        // What each deck must clear: the track it crosses, and the tallest
        // freeway bridges' decks.
        var bounds = [[Map3DRoadBridges.Bound]](repeating: [], count: members.count)
        var overCutting = [Bool](repeating: false, count: members.count)
        // Where it crosses over something, the track or a lower road: a
        // bridge over nothing else (a river, a ditch) stays at the ground.
        // One a ``Map3DRoadBridges/liftSpacing`` square, the least of
        // them, whatever order they are found in.
        var crossings = [[Map3DScene.ChunkKey: Point]](repeating: [:], count: members.count)
        func cross(_ deck: Int, at p: Point) {
            let spacing = Map3DRoadBridges.liftSpacing
            let key = Map3DScene.ChunkKey(column: Int((p.x / spacing).rounded(.down)), row: Int((p.z / spacing).rounded(.down)))
            if let kept = crossings[deck][key], (kept.x, kept.z) <= (p.x, p.z) { return }
            crossings[deck][key] = p
        }
        for (number, bridge) in bridges.enumerated() where !trackCover.isEmpty {
            let deck = deckOf[root(number)]!
            for index in 1..<bridge.points.count {
                let a = bridge.points[index - 1], b = bridge.points[index]
                var seen = Set<Int>()
                let low = Map3DTrackCover.key(x: Float(min(a.x, b.x)), z: Float(min(a.z, b.z)))
                let high = Map3DTrackCover.key(x: Float(max(a.x, b.x)), z: Float(max(a.z, b.z)))
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        for track in trackCover.cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] where seen.insert(track).inserted {
                            let piece = trackCover.pieces[track]
                            guard !piece.isTunnel,
                                  let share = Map3DRoadBridges.crossing(a, b, Point(x: Double(piece.a.x), z: Double(piece.a.z)),
                                                                        Point(x: Double(piece.b.x), z: Double(piece.b.z))) else { continue }
                            let at = Point(x: a.x + (b.x - a.x) * share, z: a.z + (b.z - a.z) * share)
                            // The bed's top there.
                            let length = (piece.b - piece.a).length
                            let t = length > 0 ? Float(((at.x - Double(piece.a.x)) * Double(piece.b.x - piece.a.x) + (at.z - Double(piece.a.z)) * Double(piece.b.z - piece.a.z))
                                / Double(length * length)) : 0
                            let bed = piece.a.y + (piece.b.y - piece.a.y) * min(max(t, 0), 1) - Self.bedDrop
                            let ground = drawnGround(x: Float(at.x), z: Float(at.z))
                            if bed <= ground - Map3DRoadBridges.overTrack {
                                // Decision 375: a cutting it spans at the ground.
                                overCutting[deck] = true
                            } else if piece.isViaduct, bed - Map3DRoadBridges.underViaduct - Self.lift(of: bridge.kind) >= ground {
                                // Under a viaduct with room for it over the
                                // ground, it passes under, its surface clear
                                // of the girder, as at both tracks of a pair.
                                bounds[deck].append(.init(point: at, height: bed - Map3DRoadBridges.underViaduct - Self.lift(of: bridge.kind), isFloor: false))
                            } else {
                                bounds[deck].append(.init(point: at, height: bed + Map3DRoadBridges.overTrack, isFloor: true))
                                cross(deck, at: at)
                            }
                        }
                    }
                }
            }
        }
        // The lower roads it crosses: a road on the ground or a bridge of a
        // lower level, not where either ends (a junction at its end).
        var ground: [Map3DScene.ChunkKey: [(road: Int, index: Int)]] = [:]
        for (number, road) in map.groundRoads.enumerated() where road.points.count >= 2 {
            let line = road.points, pad = Double(Map3DRoadBridges.half(road.kind))
            for index in 1..<line.count {
                let a = line[index - 1], b = line[index]
                let low = Map3DRoadBridges.key(min(a.x, b.x), min(a.z, b.z)), high = Map3DRoadBridges.key(max(a.x, b.x), max(a.z, b.z))
                for row in low.row...high.row {
                    for column in low.column...high.column { ground[Map3DScene.ChunkKey(column: column, row: row), default: []].append((number, index)) }
                }
                let wide = (low: Map3DRoadBridges.key(min(a.x, b.x) - pad, min(a.z, b.z) - pad), high: Map3DRoadBridges.key(max(a.x, b.x) + pad, max(a.z, b.z) + pad))
                for row in wide.low.row...wide.high.row {
                    for column in wide.low.column...wide.high.column { result.groundCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append((number, index)) }
                }
            }
        }
        result.grounds = map.groundRoads
        let opens = Set(openEnds.map { "\($0.piece) \($0.last)" })
        func apart(_ p: Point, from line: [Point], ends: (first: Bool, last: Bool) = (true, true)) -> Bool {
            func far(_ q: Point) -> Bool { (p.x - q.x) * (p.x - q.x) + (p.z - q.z) * (p.z - q.z) > 4 }
            return (!ends.first || far(line[0])) && (!ends.last || far(line[line.count - 1]))
        }
        for (number, bridge) in bridges.enumerated() {
            let deck = deckOf[root(number)]!
            let ends = (first: opens.contains("\(number) false"), last: opens.contains("\(number) true"))
            for index in 1..<bridge.points.count {
                let a = bridge.points[index - 1], b = bridge.points[index]
                let low = Map3DRoadBridges.key(min(a.x, b.x), min(a.z, b.z)), high = Map3DRoadBridges.key(max(a.x, b.x), max(a.z, b.z))
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        let key = Map3DScene.ChunkKey(column: column, row: row)
                        var lines: [(points: [Point], index: Int)] = (ground[key] ?? []).map { (map.groundRoads[$0.road].points, $0.index) }
                        lines += (cells[key] ?? []).filter { bridges[$0.piece].level < bridge.level }.map { (bridges[$0.piece].points, $0.index) }
                        for (line, at) in lines {
                            guard let share = Map3DRoadBridges.crossing(a, b, line[at - 1], line[at]) else { continue }
                            let p = Point(x: a.x + (b.x - a.x) * share, z: a.z + (b.z - a.z) * share)
                            if apart(p, from: line), apart(p, from: bridge.points, ends: ends) { cross(deck, at: p) }
                        }
                    }
                }
            }
        }
        if let frame {
            for tall in Map3DRoadBridges.tallestFreewayBridges {
                let world = frame.worldPosition(latitude: tall.latitude, longitude: tall.longitude)
                let p = Point(x: (world.x - originX) / Self.metre, z: (world.y - originY) / Self.metre)
                // The motorway's bridges over it, of the highest level there.
                var near: [(piece: Int, point: Point)] = []
                for (piece, index) in cells[Map3DRoadBridges.key(p.x, p.z)] ?? [] where bridges[piece].kind == .motorway {
                    let points = bridges[piece].points
                    let on = Map3DRoadBridges.nearest(p, points[index - 1], points[index])
                    if on.distance <= 40 { near.append((piece, on.point)) }
                }
                let top = near.map { bridges[$0.piece].level }.max()
                for (piece, point) in near where bridges[piece].level == top {
                    bounds[deckOf[root(piece)]!].append(.init(point: point, height: tall.deck, isFloor: true))
                }
            }
        }
        for (deck, numbers) in members.enumerated() {
            let length = numbers.reduce(0.0) { total, number in
                zip(bridges[number].points, bridges[number].points.dropFirst()).reduce(total) { sum, step in
                    sum + ((step.1.x - step.0.x) * (step.1.x - step.0.x) + (step.1.z - step.0.z) * (step.1.z - step.0.z)).squareRoot()
                }
            }
            let level = numbers.map { bridges[$0].level }.max() ?? 1
            let kind = numbers.map { bridges[$0].kind }.max { $0.rawValue < $1.rawValue } ?? .minor
            let rise = Map3DRoadBridges.levelRise * Float(level)
            let lifts = length < Map3DRoadBridges.culvert || overCutting[deck] ? [] : crossings[deck].sorted { ($0.key.row, $0.key.column) < ($1.key.row, $1.key.column) }.map { (point: $0.value, rise: rise) }
            result.decks.append(.init(lifts: lifts, grade: Map3DRoadBridges.grade(kind), bounds: bounds[deck]))
        }
        result.pieces = bridges.enumerated().map { number, bridge in .init(kind: bridge.kind, points: bridge.points, deck: deckOf[root(number)]!) }
        result.segments = cells
        for (number, last) in openEnds {
            if last { result.pieces[number].opens.last = true } else { result.pieces[number].opens.first = true }
        }
        for (number, last) in openEnds {
            let points = bridges[number].points
            let end = last ? points[points.count - 1] : points[0], inner = last ? points[points.count - 2] : points[1]
            let dx = end.x - inner.x, dz = end.z - inner.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 1e-6 else { continue }
            let deck = result.pieces[number].deck
            let rise = deckRise(result.decks[deck], at: end)
            guard rise > 0.05 else { continue }
            let kind = bridges[number].kind
            let reach = Double(min(rise / Map3DRoadBridges.grade(kind), Map3DRoadBridges.longestRamp) + Map3DRoadBridges.half(kind)) + 4
            let low = Map3DRoadBridges.key(end.x - reach, end.z - reach), high = Map3DRoadBridges.key(end.x + reach, end.z + reach)
            for row in low.row...high.row {
                for column in low.column...high.column { result.endCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(result.ends.count) }
            }
            result.ends.append(.init(point: end, outward: Point(x: dx / length, z: dz / length), half: Map3DRoadBridges.half(kind), rise: rise,
                                     grade: Map3DRoadBridges.grade(kind)))
        }
        return result
    }

    /// Decision 391: how far `deck` stands over the drawn ground at `p`,
    /// metres: lifted where it crosses over, up to what it must clear and
    /// under what it must keep, giving way at its grade; never under the
    /// ground.
    mutating func deckRise(_ deck: Map3DRoadBridges.Deck, at p: Map3DBaseMap.Point) -> Float {
        let ground = drawnGround(x: Float(p.x), z: Float(p.z))
        var height = ground
        for lift in deck.lifts {
            let distance = Float(((p.x - lift.point.x) * (p.x - lift.point.x) + (p.z - lift.point.z) * (p.z - lift.point.z)).squareRoot())
            height = max(height, ground + lift.rise - deck.grade * max(0, distance - Map3DRoadBridges.plateau))
        }
        for bound in deck.bounds where bound.isFloor {
            let distance = Float(((p.x - bound.point.x) * (p.x - bound.point.x) + (p.z - bound.point.z) * (p.z - bound.point.z)).squareRoot())
            height = max(height, bound.height - deck.grade * distance)
        }
        for bound in deck.bounds where !bound.isFloor {
            let distance = Float(((p.x - bound.point.x) * (p.x - bound.point.x) + (p.z - bound.point.z) * (p.z - bound.point.z)).squareRoot())
            height = min(height, bound.height + deck.grade * distance)
        }
        return max(0, height - ground)
    }

    /// Decision 391: how far a road at level point `p`, running along
    /// `along` (or any way, when `nil`), lies over the drawn ground,
    /// metres, and whether it is on a bridge's deck there: on one, the
    /// deck's height; on a road running on from a bridge's end, its ramp
    /// down; else 0. Only a road `onDeck` (a bridge's) is on a deck: one
    /// on the ground under it is not.
    mutating func roadRise(at p: Map3DBaseMap.Point, along: (x: Double, z: Double)?, onDeck: Bool) -> (rise: Float, onBridge: Bool) {
        let bridges = roadBridges
        guard !bridges.isEmpty else { return (0, false) }
        let key = Map3DRoadBridges.key(p.x, p.z)
        var best: (rise: Float, onBridge: Bool) = (0, false)
        var decks = Set<Int>()
        for (number, index) in onDeck ? bridges.segments[key] ?? [] : [] {
            let piece = bridges.pieces[number]
            let a = piece.points[index - 1], b = piece.points[index]
            guard !decks.contains(piece.deck), Map3DRoadBridges.nearest(p, a, b).distance <= Double(Map3DRoadBridges.half(piece.kind)) + 0.5 else { continue }
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            // Past a deck's end is off it: a road running on ramps down.
            let share = length > 0 ? ((p.x - a.x) * dx + (p.z - a.z) * dz) / (length * length) : 0.5
            if share < 0 && index == 1 && piece.opens.first || share > 1 && index == piece.points.count - 1 && piece.opens.last { continue }
            if let along {
                guard length < 1 || abs(dx * along.x + dz * along.z) / length >= 0.9 else { continue }
            }
            decks.insert(piece.deck)
            best = (max(best.rise, deckRise(bridges.decks[piece.deck], at: p)), true)
        }
        for number in bridges.endCells[key] ?? [] {
            let end = bridges.ends[number]
            let vx = p.x - end.point.x, vz = p.z - end.point.z
            let out = vx * end.outward.x + vz * end.outward.z
            guard out >= -1 else { continue }
            let lateral = abs(vx * end.outward.z - vz * end.outward.x)
            guard lateral <= Double(end.half) + 0.15 * max(out, 0) else { continue }
            if let along, abs(along.x * end.outward.x + along.z * end.outward.z) < 0.9 { continue }
            let rise = end.rise - end.grade * Float(max(out, 0))
            // A ramp longer than the longest stands as the deck's end.
            guard Float(max(out, 0)) <= Map3DRoadBridges.longestRamp else { continue }
            best.rise = max(best.rise, rise)
        }
        return best
    }

    /// Decision 391 (the owner, 2026-10-24: too many parapets): whether
    /// another road's surface (a deck, or a road on the ground or ramping
    /// onto a deck) covers level point `probe` within `within` metres of
    /// `height` over the sea: a road beside the one along `centre`, at its
    /// height, so no parapet or wall stands between them.
    mutating func roadBeside(_ probe: Map3DBaseMap.Point, of centre: Map3DBaseMap.Point, at height: Float, within: Float) -> Bool {
        let bridges = roadBridges
        let key = Map3DRoadBridges.key(probe.x, probe.z)
        // Over the probe, and not the road along `centre` itself.
        func covers(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point, half: Float) -> Bool {
            Map3DRoadBridges.nearest(probe, a, b).distance <= Double(half)
                && Map3DRoadBridges.nearest(centre, a, b).distance > Double(half) + 0.5
        }
        let ground = drawnGround(x: Float(probe.x), z: Float(probe.z))
        for (number, index) in bridges.segments[key] ?? [] {
            let piece = bridges.pieces[number]
            let a = piece.points[index - 1], b = piece.points[index]
            guard covers(a, b, half: Map3DRoadBridges.half(piece.kind)) else { continue }
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            let share = length > 0 ? ((probe.x - a.x) * dx + (probe.z - a.z) * dz) / (length * length) : 0.5
            if share < 0 && index == 1 && piece.opens.first || share > 1 && index == piece.points.count - 1 && piece.opens.last { continue }
            let top = ground + Self.lift(of: piece.kind) + deckRise(bridges.decks[piece.deck], at: probe)
            if abs(top - height) < within { return true }
        }
        for (number, index) in bridges.groundCells[key] ?? [] {
            let road = bridges.grounds[number]
            let a = road.points[index - 1], b = road.points[index]
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01, covers(a, b, half: Map3DRoadBridges.half(road.kind)) else { continue }
            let top = ground + Self.lift(of: road.kind) + roadRise(at: probe, along: (dx / length, dz / length), onDeck: false).rise
            if abs(top - height) < within { return true }
        }
        return false
    }

    /// Decision 391: whether a road from `a` to `b` may come near a
    /// raised road (a bridge or a ramp onto one).
    func nearRaisedRoad(from a: Map3DBaseMap.Point, to b: Map3DBaseMap.Point) -> Bool {
        guard !roadBridges.isEmpty else { return false }
        let low = Map3DRoadBridges.key(min(a.x, b.x), min(a.z, b.z)), high = Map3DRoadBridges.key(max(a.x, b.x), max(a.z, b.z))
        for row in low.row...high.row {
            for column in low.column...high.column {
                let key = Map3DScene.ChunkKey(column: column, row: row)
                if roadBridges.segments[key] != nil || roadBridges.endCells[key] != nil { return true }
            }
        }
        return false
    }
}

// MARK: - Piers and girders

/// Decision 391: how a raised deck's girder and piers are drawn. One look
/// now, the road bridge's; the track's viaducts (NEXT_PRIORITIES 10f) can
/// take another through the same calls.
struct Map3DElevatedLook: Sendable {
    /// The girder under the deck, metres, and the parapet over its edges.
    let girderDepth: Float
    let parapet: Float
    /// A pier every `pierSpacing` metres: a column `column` square, under a
    /// cap `capHeight` high, `capShare` of the deck's width across and
    /// `capAlong` along it.
    let pierSpacing: Float
    let column: Float
    let capHeight: Float
    let capShare: Float
    let capAlong: Float
    let colour: UInt32
    let paint: Map3DPaint

    /// The reference city's road viaduct (`regionTiles`: its deck 1.6 m
    /// deep, a pier every 38 m under a cap 1.1 m high and 0.85 of its
    /// width); the column 2 m square, the parapet 1 m.
    static let roadBridge = Map3DElevatedLook(girderDepth: 1.6, parapet: 1, pierSpacing: 38, column: 2, capHeight: 1.1, capShare: 0.85,
                                              capAlong: 1.6, colour: Map3DPalette.concrete, paint: Map3DScene.Builder.concrete)
}

extension Map3DMesh {
    /// Decision 391: a girder `look.girderDepth` deep under `deck` (the
    /// deck's top along its middle) and `width` wide, with its parapets:
    /// along the lines of `parapets` on each side (left, right of the
    /// way), or the whole deck's when `nil`.
    mutating func addGirder(along deck: [Map3DPoint], width: Float, look: Map3DElevatedLook, parapets: [[[Map3DPoint]]]? = nil) {
        guard deck.count > 1 else { return }
        addRibbon(along: deck, width: width, lift: -0.04, depth: look.girderDepth, top: look.colour, side: look.colour,
                  topPaint: look.paint, sidePaint: look.paint)
        // Its underside, which the camera sees from the street.
        let across = Self.acrossDirections(deck)
        for index in 1..<deck.count {
            let drop = Map3DPoint(0, -0.04 - look.girderDepth, 0), half = width / 2
            let a = deck[index - 1] + drop, b = deck[index] + drop
            addQuad(a - across[index - 1] * half, b - across[index] * half, b + across[index] * half, a + across[index - 1] * half,
                    color: look.colour, paint: look.paint)
        }
        for (number, side) in [Float(-1), 1].enumerated() {
            for run in parapets?[number] ?? [deck] {
                addRibbon(along: run, width: 0.3, offset: side * (width / 2 - 0.15), lift: look.parapet, depth: look.parapet + 0.04,
                          top: look.colour, side: look.colour, topPaint: look.paint, sidePaint: look.paint)
            }
        }
    }

    /// Decision 391: a pier from `foot` (on the ground) up to the girder
    /// under a deck at `deckTop`, `width` wide, facing `forward` (along
    /// the deck).
    mutating func addPier(foot: Map3DPoint, deckTop: Float, forward: Map3DPoint, width: Float, look: Map3DElevatedLook) {
        let under = deckTop - 0.04 - look.girderDepth
        let cap = under - look.capHeight
        guard cap - foot.y > 0.3 else { return }
        addBox(base: foot, forward: forward, length: look.column, width: look.column, height: cap - foot.y, top: look.colour, side: look.colour,
               frontPaint: look.paint, flankPaint: look.paint, capped: false)
        addBox(base: Map3DPoint(foot.x, cap, foot.z), forward: forward, length: look.capAlong, width: width * look.capShare,
               height: look.capHeight, top: look.colour, side: look.colour, frontPaint: look.paint, flankPaint: look.paint)
    }
}

extension Map3DScene.Builder {
    /// Decision 391: under each raised road of `roads` (a bridge's deck, or
    /// a ramp onto one), what holds it up: a girder and piers where it
    /// stands clear of the ground, walls down to the ground where it is
    /// lower. Each tile's share, laid every ``raisedStep`` metres from the
    /// road's first point and a pier every ``Map3DElevatedLook/pierSpacing``
    /// from it, so a chunk built apart draws what the whole scene does.
    mutating func addRoadBridges(_ roads: [Map3DBaseMap.Road], look: Map3DElevatedLook = .roadBridge) {
        guard !roadBridges.isEmpty else { return }
        typealias Point = Map3DBaseMap.Point
        for road in roads where road.points.count >= 2 {
            let xs = road.points.map(\.x), zs = road.points.map(\.z)
            guard nearRaisedRoad(from: Point(x: xs.min()!, z: zs.min()!), to: Point(x: xs.max()!, z: zs.max()!)) else { continue }
            let width = road.kind.width(ramp: road.isRamp) + (road.isRamp ? 0 : 2 * Self.sidewalk(of: road.kind))
            let lift = Self.lift(of: road.kind)
            // The road's middle every step, at its height, and whether it
            // is a deck clear of the ground there.
            struct Sample { let at: Point; let top: Map3DPoint; let rise: Float; let clear: Bool; let travelled: Double; let corner: Bool }
            var samples: [Sample] = []
            var travelled = 0.0
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                defer { travelled += length }
                guard length > 0.01 else { continue }
                let along = (x: dx / length, z: dz / length)
                let steps = max(1, Int((length / Self.raisedStep).rounded(.up)))
                for step in (samples.isEmpty ? 0 : 1)...steps {
                    let t = Double(step) / Double(steps)
                    let p = Point(x: a.x + dx * t, z: a.z + dz * t)
                    let raised = roadRise(at: p, along: along, onDeck: road.bridgeLevel > 0)
                    let top = Map3DPoint(Float(p.x), drawnGround(x: Float(p.x), z: Float(p.z)) + lift + raised.rise, Float(p.z))
                    samples.append(Sample(at: p, top: top, rise: raised.rise, clear: raised.onBridge && raised.rise >= look.girderDepth + 0.5,
                                          travelled: travelled + length * t, corner: step == steps))
                }
            }
            // A parapet or wall on each side (left, right of the way) only
            // where no other road lies beside it at its height.
            let across = Map3DMesh.acrossDirections(samples.map(\.top))
            var open = [[Bool]](repeating: [true, true], count: samples.count)
            for (number, sample) in samples.enumerated() where sample.rise > 0.05 {
                for (index, side) in [Float(-1), 1].enumerated() {
                    let probe = sample.top + across[number] * (side * (width / 2 + Map3DRoadBridges.beside))
                    open[number][index] = !roadBeside(Point(x: Double(probe.x), z: Double(probe.z)), of: sample.at, at: sample.top.y, within: look.parapet)
                }
            }
            // Runs of the same kind in the same chunk, each step's middle
            // in the road's tile.
            var index = 1
            while index < samples.count {
                let a = samples[index - 1], b = samples[index]
                let middle = Point(x: (a.at.x + b.at.x) / 2, z: (a.at.z + b.at.z) / 2)
                guard a.rise > 0.05 || b.rise > 0.05, Map3DRoadMarkings.inside(middle, road.bounds) else {
                    index += 1
                    continue
                }
                let clear = a.clear && b.clear
                let chunk = key(of: Map3DPoint(Float(middle.x), 0, Float(middle.z)))
                var run = [a, b]
                index += 1
                while index < samples.count {
                    let c = samples[index - 1], d = samples[index]
                    let next = Point(x: (c.at.x + d.at.x) / 2, z: (c.at.z + d.at.z) / 2)
                    guard c.rise > 0.05 || d.rise > 0.05, (c.clear && d.clear) == clear, Map3DRoadMarkings.inside(next, road.bounds),
                          key(of: Map3DPoint(Float(next.x), 0, Float(next.z))) == chunk else { break }
                    run.append(d)
                    index += 1
                }
                // The girder and walls only where the deck or the ground
                // bends (``bends(_:)``), at the road's corners and the run's
                // ends: a straight stretch is one piece.
                let first = index - run.count
                func bent(_ number: Int) -> Bool {
                    let sample = samples[number]
                    let ground = sample.top.y - lift - sample.rise
                    return Self.bendScales.contains { scale in
                        guard number % scale == 0 else { return false }
                        guard number >= scale, number + scale < samples.count else { return true }
                        let before = samples[number - scale], after = samples[number + scale]
                        return Self.bends([before.top.y, sample.top.y, after.top.y])
                            || Self.bends([before.top.y - lift - before.rise, ground, after.top.y - lift - after.rise])
                    }
                }
                func laid(_ part: [Int]) -> [Map3DPoint] {
                    part.indices.filter { $0 == 0 || $0 == part.count - 1 || run[part[$0]].corner || bent(first + part[$0]) }.map { run[part[$0]].top }
                }
                let line = laid(Array(run.indices))
                // Each side's parapet or walls (left, right of the way) on
                // the stretches of the run where it stands, each laid as the
                // girder is; walls only a parapet's height or more over the
                // ground: lower, the road meets the ground it lies on.
                let barriers: [[[Map3DPoint]]] = (0..<2).map { side in
                    var stretches: [[Int]] = [], stretch: [Int] = []
                    for number in run.indices {
                        if open[first + number][side] && (clear || run[number].rise >= look.parapet) {
                            stretch.append(number)
                        } else {
                            if stretch.count > 1 { stretches.append(stretch) }
                            stretch = []
                        }
                    }
                    if stretch.count > 1 { stretches.append(stretch) }
                    return stretches.map(laid)
                }
                if clear {
                    var built = Map3DMesh()
                    built.addGirder(along: line, width: width, look: look, parapets: barriers)
                    // A pier wherever the road's way from its first point
                    // passes a spacing's middle, clear of the track.
                    let spacing = Double(look.pierSpacing)
                    for (c, d) in zip(run, run.dropFirst()) {
                        let mark = ((c.travelled / spacing - 0.5).rounded(.up) + 0.5) * spacing
                        guard mark < d.travelled || (mark == d.travelled && d.travelled == run.last!.travelled) else { continue }
                        let share = Float((mark - c.travelled) / max(d.travelled - c.travelled, 1e-9))
                        let top = c.top + (d.top - c.top) * share
                        guard !nearTrack(x: top.x, z: top.z, within: look.column / 2 + 3) else { continue }
                        let foot = Map3DPoint(top.x, drawnGround(x: top.x, z: top.z), top.z)
                        built.addPier(foot: foot, deckTop: top.y - lift, forward: d.top - c.top, width: width, look: look)
                    }
                    mesh(at: Map3DPoint(Float(middle.x), 0, Float(middle.z))) { $0.append(built) }
                } else {
                    addRampWalls(barriers, at: line[line.count / 2], width: width, look: look)
                }
            }
        }
    }

    /// Decision 391: the walls of a ramp (or a low deck) along the lines
    /// of `sides` (left, right of the way), its top's middle, from its
    /// edges down to the drawn ground, in the chunk `at` is in.
    mutating func addRampWalls(_ sides: [[[Map3DPoint]]], at: Map3DPoint, width: Float, look: Map3DElevatedLook) {
        var built = Map3DMesh()
        for (lines, side) in zip(sides, [Float(-1), 1]) {
            for line in lines where line.count > 1 {
                let across = Map3DMesh.acrossDirections(line)
                let edges = line.indices.map { line[$0] + across[$0] * (side * width / 2) + Map3DPoint(0, -0.04, 0) }
                let feet = edges.map { Map3DPoint($0.x, drawnGround(x: $0.x, z: $0.z) - 0.3, $0.z) }
                for index in 1..<line.count {
                    // Facing out from the road.
                    let (a, b) = side > 0 ? (index - 1, index) : (index, index - 1)
                    built.addQuad(feet[a], feet[b], edges[b], edges[a], color: look.colour, paint: look.paint)
                }
            }
        }
        guard !built.vertices.isEmpty else { return }
        mesh(at: at) { $0.append(built) }
    }

    /// Decision 391: whether scene point (`x`, `z`) lies within `within`
    /// metres of the track out of a tunnel, seen from above.
    func nearTrack(x: Float, z: Float, within: Float) -> Bool {
        let low = Map3DTrackCover.key(x: x - within, z: z - within), high = Map3DTrackCover.key(x: x + within, z: z + within)
        for row in low.row...high.row {
            for column in low.column...high.column {
                for index in trackCover.cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] {
                    let piece = trackCover.pieces[index]
                    guard !piece.isTunnel else { continue }
                    let on = Map3DRoadBridges.nearest(Map3DBaseMap.Point(x: Double(x), z: Double(z)), Map3DBaseMap.Point(x: Double(piece.a.x), z: Double(piece.a.z)),
                                                      Map3DBaseMap.Point(x: Double(piece.b.x), z: Double(piece.b.z)))
                    if on.distance <= Double(within) { return true }
                }
            }
        }
        return false
    }
}
