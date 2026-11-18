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
        /// ROAD-RAMP-HEIGHT: a link road's bridge (the tiles' `ramp`).
        var isRamp = false
        /// ROAD-RAMP-HEIGHT: on a link road's bridge joined to a deck's
        /// main road, how far along the link roads it is from where they
        /// come down to the ground and from where they leave the main road;
        /// `nil` when it has no way to either.
        var ramp: Ramp?
        /// ROAD-LAYER-HEIGHT: the tiles' `layer` (at least 1).
        var level = 1
        /// ROAD-LAYER-HEIGHT: on a bridge of a lower level than its deck's
        /// highest, the most it stands over the ground by its own level
        /// (``levelRise`` a level), metres; `nil` on one of the highest.
        var ceiling: Float?
        /// ROAD-LAYER-HEIGHT: on such a bridge, every ``rampSample``
        /// metres along it, how high over the ground it must stand there
        /// to meet a higher bridge of its deck it joins or lies on, coming
        /// down from it at twice its grade at most; empty when nothing
        /// lifts it over ``ceiling``.
        var lifted: [(along: Double, rise: Float)] = []

        /// ROAD-LAYER-HEIGHT: ``lifted`` at `along` metres from its first
        /// point, at least ``ceiling``.
        func levelCap(at along: Double) -> Float {
            let ceiling = ceiling ?? .infinity
            guard let first = lifted.first else { return ceiling }
            var index = 1
            while index < lifted.count - 1, lifted[index].along < along { index += 1 }
            guard lifted.count >= 2 else { return max(ceiling, first.rise) }
            let before = lifted[index - 1], after = lifted[index]
            let t = after.along > before.along ? Float(min(max((along - before.along) / (after.along - before.along), 0), 1)) : 0
            return max(ceiling, before.rise + (after.rise - before.rise) * t)
        }

        /// ROAD-RAMP-HEIGHT: every ``Map3DRoadBridges/rampSample`` metres
        /// along a piece from its first point, and at its last: how far
        /// along it (`along`), and how far along the link roads from an
        /// open end (`down`) and from the main road (`up`), metres.
        struct Ramp: Sendable {
            let samples: [(along: Double, down: Double, up: Double)]
        }

        /// How far along it from its first point level point `p` lies
        /// (at its nearest point), metres.
        func travelled(to p: Map3DBaseMap.Point) -> Double {
            var best = (distance: Double.infinity, along: 0.0)
            var travelled = 0.0
            for (a, b) in zip(points, points.dropFirst()) {
                let length = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
                let on = Map3DRoadBridges.nearest(p, a, b)
                if on.distance < best.distance {
                    best = (on.distance, travelled + ((on.point.x - a.x) * (on.point.x - a.x) + (on.point.z - a.z) * (on.point.z - a.z)).squareRoot())
                }
                travelled += length
            }
            return best.along
        }
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
        /// Decision 607: how far out it keeps `rise` before it falls,
        /// metres: a road leaving another raised one at a junction stays at
        /// its height while it lies on the other's surface.
        var plateau: Float = 0
        /// Review H4: the segments (road, first point) of the roads on the
        /// ground running on from it (``runOn(from:axis:reach:first:)``):
        /// only they ramp down, not a road beside them.
        var roads: [(road: Int, index: Int)] = []
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
    var grounds: [(kind: Map3DBaseMap.RoadKind, points: [Map3DBaseMap.Point], isRamp: Bool)] = []
    var groundCells: [Map3DScene.ChunkKey: [(road: Int, index: Int)]] = [:]

    /// Decision 391 (續篇二): where a road on the ground crosses the track
    /// on an embankment or in a cutting, the road over it, and the
    /// ``cell`` squares each one's ramps reach.
    var joins: [Join] = []
    var joinCells: [Map3DScene.ChunkKey: [Int]] = [:]
    /// Where a road on the ground passes under an embankment high enough
    /// for it: the bank open over the road for `half` metres along the
    /// track each side of `point` (on the track's middle), a girder over it.
    var openings: [(point: Map3DBaseMap.Point, half: Float)] = []
    /// What each crossing of a road on the ground and the track out of a
    /// tunnel was taken as (``Crossing``), for the tests.
    var crossings: [Crossing: Int] = [:]

    var isEmpty: Bool { pieces.isEmpty && joins.isEmpty }

    /// Decision 391 (續篇二): a road on the ground lifted over the track
    /// where it crosses: at `point`, running along `along` (level, a metre
    /// long), `half` wide each side, its way `height` (metres over the sea,
    /// under its own lift) for `plateau` metres each side of the point
    /// along it, then down at `grade`; `reach` metres along it each way
    /// its ramps end.
    struct Join: Sendable {
        let point: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
        let half: Float
        let height: Float
        let plateau: Float
        let grade: Float
        let reach: Float
        /// Review H4: the segments of its road and those running on from
        /// it, which alone it lifts.
        var roads: [(road: Int, index: Int)] = []
    }

    /// How a road on the ground meets the track out of a tunnel.
    enum Crossing: Hashable, Sendable {
        /// On the level: a level crossing.
        case level
        /// Under a viaduct or a bridge.
        case underViaduct
        /// Over a cutting deep enough for a train (decision 375's bridge).
        case overDeepCutting
        /// Lifted over a shallower cutting, or over an embankment.
        case overCutting, overEmbankment
        /// Under an embankment high enough for it, the bank open over it.
        case underEmbankment
        /// Along the track (under 30° off it): no join.
        case alongside
    }

    /// The least height of the track's bed over the drawn ground that is an
    /// embankment a road goes over, metres.
    static let embankment: Float = 1

    static let cell: Double = 32
    /// How far apart two bridges' lines may be and be one, metres: the
    /// tiles' 4,096 units to a 2.2 km side, twice.
    static let join: Double = 1.5
    /// Decision 822: how far apart two bridges' edges may run side by side
    /// and be one deck, metres: 華江橋's scooter lanes run 4.6 m off
    /// their carriageways' edges as the map draws them.
    static let alongside: Double = 6
    /// Decision 822: how near a deck's height a road running on from a
    /// deck's end must be to stay on it (``Map3DScene/Builder/levelRun(from:outward:rise:reach:in:)``), metres.
    static let levelGap: Float = 0.5
    /// Decision 822: the longest a road running on from a deck's end stays
    /// on a deck at its height, metres: a run longer is a street under the
    /// viaduct, which stays on the ground (at 300 m, streets under 三重's
    /// viaduct rose to it).
    static let longestLevel: Double = 150
    /// ROAD-RAMP-HEIGHT: how far apart a link road's bridge is looked at
    /// along it, metres.
    static let rampSample: Double = 5
    /// ROAD-RAMP-HEIGHT: how many times its own grade a link road's bridge
    /// may come down at, at its steepest, while it still lies on its main
    /// road's surface before it leaves it: else it stays at the main
    /// road's height there (a link drawn beside its main road, within
    /// their widths, comes down only past it).
    static let steepestRamp: Double = 2
    /// Decision 822 (後來三): the least sine of the angle at which a lower
    /// bridge crosses under a higher one of its deck (20°); less is two
    /// running side by side whose lines the map draws across each other
    /// (ROAD-LAYER-HEIGHT: the lower one lifted to the higher one there).
    static let crossingSine: Double = 0.34
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
    /// (Decision 407: each viaduct's own girder, ``Map3DTrackCover/Piece/underViaduct``.)
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

    /// Decision 822: half a road's drawn width, metres: a ramp's own
    /// (``Map3DBaseMap/RoadKind/width(ramp:)``, no pavements), else
    /// ``half(_:)``. A street 7.5 m off a trunk's ramp is not on it
    /// (三重, beside 台北橋's ramp: it rose with the ramp to 2 m under
    /// the deck).
    static func half(_ kind: Map3DBaseMap.RoadKind, ramp: Bool) -> Float {
        ramp ? kind.width(ramp: true) / 2 : half(kind)
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

    /// Review H4: every point of ``grounds`` (road, index), by the ``cell``
    /// squares within ``join`` of it.
    var groundPoints: [Map3DScene.ChunkKey: [(road: Int, index: Int)]] = [:]

    /// Review H4: the segments (road, first point) of the roads on the
    /// ground running on from `start` along level unit `axis`, either way,
    /// that come within `reach` metres of it: the roads `first`, or else
    /// each with a point within ``join`` of `start`, and those met at one
    /// of their ends inside `reach`, each leaving the point it is met at
    /// within 25° of `axis`. A road alongside them that meets them nowhere
    /// is not one, however near (a bridge's ramp and its frontage road).
    func runOn(from start: Map3DBaseMap.Point, axis: Map3DBaseMap.Point, reach: Double, first: [Int] = []) -> [(road: Int, index: Int)] {
        typealias Point = Map3DBaseMap.Point
        func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }
        var met = Set(first)
        var frontier = first.isEmpty ? [start] : first.flatMap { road in
            [grounds[road].points[0], grounds[road].points[grounds[road].points.count - 1]].filter { distance($0, start) <= reach }
        }
        var next = 0
        while next < frontier.count {
            let q = frontier[next]
            next += 1
            for (road, index) in groundPoints[Self.key(q.x, q.z)] ?? [] where !met.contains(road) {
                let line = grounds[road].points
                guard distance(line[index], q) <= Self.join else { continue }
                // Each way from it, toward its first point 5 m off (a
                // tile's quantising can leave a stub of a first segment).
                let leaves = [-1, 1].contains { step in
                    var other = index + step
                    while line.indices.contains(other + step), distance(line[other], line[index]) < 5 { other += step }
                    guard line.indices.contains(other) else { return false }
                    let length = distance(line[other], line[index])
                    return length > 0.01 && abs((line[other].x - line[index].x) * axis.x + (line[other].z - line[index].z) * axis.z) / length >= 0.9
                }
                guard leaves else { continue }
                met.insert(road)
                frontier += [line[0], line[line.count - 1]].filter { distance($0, start) <= reach }
            }
        }
        return met.sorted().flatMap { road in
            let line = grounds[road].points, pad = Double(Self.half(grounds[road].kind))
            return (1..<line.count).filter { Self.nearest(start, line[$0 - 1], line[$0]).distance <= reach + pad }.map { (road, $0) }
        }
    }

    /// Review H4: whether level point `p` is on one of `roads`' segments
    /// (within half its drawn width, ``half(_:ramp:)``, and half a metre).
    func isOn(_ p: Map3DBaseMap.Point, _ roads: [(road: Int, index: Int)]) -> Bool {
        roads.contains { segment in
            let line = grounds[segment.road].points
            let road = grounds[segment.road]
            return Self.nearest(p, line[segment.index - 1], line[segment.index]).distance <= Double(Self.half(road.kind, ramp: road.isRamp)) + 0.5
        }
    }

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
        // Decision 822: bridges of a level running side by side (a bridge's
        // carriageways, its scooter lane, mapped apart), their edges
        // ``Map3DRoadBridges/alongside`` apart or less for 30 m or more,
        // are one deck too: the owner's IMG_5324 (華江橋's scooter lane, its
        // ends 4 m from the carriageway's, flat on the river beside its
        // raised deck) and IMG_5323 (parallel decks at different heights).
        for (number, bridge) in bridges.enumerated() {
            let half = Double(Map3DRoadBridges.half(bridge.kind))
            var runs: [Int: Int] = [:]
            var travelled = 0.0
            for (a, b) in zip(bridge.points, bridge.points.dropFirst()) {
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                guard length > 0.01 else { continue }
                var along = (10 - travelled.truncatingRemainder(dividingBy: 10)).truncatingRemainder(dividingBy: 10)
                while along <= length {
                    let p = Point(x: a.x + dx * along / length, z: a.z + dz * along / length)
                    let reach = half + Double(Map3DRoadBridges.half(.motorway)) + Map3DRoadBridges.alongside
                    let low = Map3DRoadBridges.key(p.x - reach, p.z - reach), high = Map3DRoadBridges.key(p.x + reach, p.z + reach)
                    var seen = Set<Int>()
                    for row in low.row...high.row {
                        for column in low.column...high.column {
                            for (other, index) in cells[Map3DScene.ChunkKey(column: column, row: row)] ?? []
                            where other > number && bridges[other].level == bridge.level && !seen.contains(other) {
                                let c = bridges[other].points[index - 1], d = bridges[other].points[index]
                                let ex = d.x - c.x, ez = d.z - c.z, span = (ex * ex + ez * ez).squareRoot()
                                guard span > 0.01, abs(ex * dx + ez * dz) / (span * length) >= 0.9 else { continue }
                                let gap = Map3DRoadBridges.nearest(p, c, d).distance - half - Double(Map3DRoadBridges.half(bridges[other].kind))
                                if gap <= Map3DRoadBridges.alongside {
                                    seen.insert(other)
                                    runs[other, default: 0] += 1
                                }
                            }
                        }
                    }
                    along += 10
                }
                travelled += length
            }
            for (other, count) in runs where count >= 4 { parent[root(other)] = root(number) }
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
                            } else if piece.isViaduct, bed - piece.underViaduct - Self.lift(of: bridge.kind) >= ground {
                                // Under a viaduct with room for it over the
                                // ground, it passes under, its surface clear
                                // of the girder, as at both tracks of a pair.
                                bounds[deck].append(.init(point: at, height: bed - piece.underViaduct - Self.lift(of: bridge.kind), isFloor: false))
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
        for (number, road) in map.groundRoads.enumerated() where road.points.count >= 2 {
            for (index, p) in road.points.enumerated() {
                let pad = Map3DRoadBridges.join
                let low = Map3DRoadBridges.key(p.x - pad, p.z - pad), high = Map3DRoadBridges.key(p.x + pad, p.z + pad)
                for row in low.row...high.row {
                    for column in low.column...high.column { result.groundPoints[Map3DScene.ChunkKey(column: column, row: row), default: []].append((number, index)) }
                }
            }
        }
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
                            // Decision 607: a road ending under it, not at
                            // one of its points (a junction of the roads
                            // under it), is crossed over all the same.
                            let joined = bridge.points.contains { ($0.x - p.x) * ($0.x - p.x) + ($0.z - p.z) * ($0.z - p.z) <= 4 }
                            if apart(p, from: line) || !joined, apart(p, from: bridge.points, ends: ends) { cross(deck, at: p) }
                        }
                    }
                }
            }
        }
        // Decision 607: over a road running under it, along it (a viaduct
        // over the street it follows), for 30 m or more: lifted all along
        // it, not dipping onto it between its crossings.
        for (number, bridge) in bridges.enumerated() {
            let deck = deckOf[root(number)]!
            let half = Double(bridge.kind.width(ramp: false)) / 2
            var run: [Point] = []
            var travelled = 0.0
            for (a, b) in zip(bridge.points, bridge.points.dropFirst()) {
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                guard length > 0.01 else { continue }
                var along = (10 - travelled.truncatingRemainder(dividingBy: 10)).truncatingRemainder(dividingBy: 10)
                while along <= length {
                    let p = Point(x: a.x + dx * along / length, z: a.z + dz * along / length)
                    let key = Map3DRoadBridges.key(p.x, p.z)
                    var lines: [(points: [Point], index: Int, half: Double)] = (ground[key] ?? []).map {
                        (map.groundRoads[$0.road].points, $0.index, Double(map.groundRoads[$0.road].kind.width(ramp: false)) / 2)
                    }
                    lines += (cells[key] ?? []).filter { bridges[$0.piece].level < bridge.level }.map {
                        (bridges[$0.piece].points, $0.index, Double(bridges[$0.piece].kind.width(ramp: false)) / 2)
                    }
                    let under = lines.contains { line, index, other in
                        let c = line[index - 1], d = line[index]
                        let ex = d.x - c.x, ez = d.z - c.z, span = (ex * ex + ez * ez).squareRoot()
                        return span > 0.01 && abs(ex * dx + ez * dz) / (span * length) >= 0.9
                            && Map3DRoadBridges.nearest(p, c, d).distance <= max(half, other)
                    }
                    if under {
                        run.append(p)
                    } else {
                        if run.count >= 4 { run.forEach { cross(deck, at: $0) } }
                        run = []
                    }
                    along += 10
                }
                travelled += length
            }
            if run.count >= 4 { run.forEach { cross(deck, at: $0) } }
        }
        addJoins(of: map, into: &result)
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
        result.pieces = bridges.enumerated().map { number, bridge in
            .init(kind: bridge.kind, points: bridge.points, deck: deckOf[root(number)]!, isRamp: bridge.isRamp, level: max(bridge.level, 1))
        }
        result.segments = cells
        for (number, last) in openEnds {
            if last { result.pieces[number].opens.last = true } else { result.pieces[number].opens.first = true }
        }
        // Decision 822 (後來三): a bridge of a lower level than a higher
        // one of its deck, ending on the higher one's surface (三重's
        // approaches to 忠孝橋 and 台北橋: the scooter lane's and the
        // street's bridges, `layer` 1, end beside the trunk's viaduct,
        // `layer` 2–4, which goes on), comes down inside itself as a link
        // road does: it ramped on from its end at the deck's height, over
        // the streets under the viaduct, 1–6 m beneath it.
        for (number, last) in openEnds where !bridges[number].isRamp {
            let bridge = bridges[number], deck = deckOf[root(number)]!
            let end = last ? bridge.points[bridge.points.count - 1] : bridge.points[0]
            let half = Double(Map3DRoadBridges.half(bridge.kind))
            let reach = half + Double(Map3DRoadBridges.half(.motorway))
            let low = Map3DRoadBridges.key(end.x - reach, end.z - reach), high = Map3DRoadBridges.key(end.x + reach, end.z + reach)
            var under = false
            for row in low.row...high.row where !under {
                for column in low.column...high.column where !under {
                    for (other, index) in cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] {
                        let higher = bridges[other]
                        guard higher.level > bridge.level, !higher.isRamp, deckOf[root(other)] == deck else { continue }
                        let a = higher.points[index - 1], b = higher.points[index]
                        let dx = b.x - a.x, dz = b.z - a.z, span = dx * dx + dz * dz
                        guard span > 1e-6 else { continue }
                        // Beside it, not past one of its ends.
                        let share = ((end.x - a.x) * dx + (end.z - a.z) * dz) / span
                        guard share >= 0, share <= 1 else { continue }
                        if Map3DRoadBridges.nearest(end, a, b).distance < half + Double(Map3DRoadBridges.half(higher.kind)) {
                            under = true
                            break
                        }
                    }
                }
            }
            // ROAD-LAYER-HEIGHT: one crossing under a higher bridge of its
            // deck where it comes down (忠孝橋's east end under 市民大道's
            // viaduct) does so too: it stands at its own level there, a
            // storey under the higher one (``levelHeights(into:others:)``).
            if under { result.pieces[number].isRamp = true }
        }
        rampDistances(into: &result, others: others)
        levelHeights(into: &result, others: others)
        for (number, last) in openEnds {
            let points = bridges[number].points
            let end = last ? points[points.count - 1] : points[0], inner = last ? points[points.count - 2] : points[1]
            let dx = end.x - inner.x, dz = end.z - inner.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 1e-6 else { continue }
            let rise = pieceRise(result, piece: number, at: end)
            guard rise > 0.05 else { continue }
            let kind = bridges[number].kind
            let outward = Point(x: dx / length, z: dz / length)
            // Decision 822: a road running on from the end under a deck at
            // the end's height stays at it while it lies there, as one
            // leaving a raised road at a junction does (decision 607): it
            // ramped down under the deck, a slab 1–4 m beneath it (the
            // owner's IMG_5323, 忠孝橋's east end and 台北橋's in 三重).
            let level = Double(levelRun(from: end, outward: outward, rise: rise, reach: Double(rise / Map3DRoadBridges.grade(kind)), in: result))
            let reach = Double(min(rise / Map3DRoadBridges.grade(kind), Map3DRoadBridges.longestRamp) + Map3DRoadBridges.half(kind)) + 4 + level
            let low = Map3DRoadBridges.key(end.x - reach, end.z - reach), high = Map3DRoadBridges.key(end.x + reach, end.z + reach)
            for row in low.row...high.row {
                for column in low.column...high.column { result.endCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(result.ends.count) }
            }
            result.ends.append(.init(point: end, outward: outward, half: Map3DRoadBridges.half(kind), rise: rise,
                                     grade: Map3DRoadBridges.grade(kind), plateau: Float(level),
                                     roads: result.runOn(from: end, axis: outward, reach: reach)))
        }
        spreadRamps(into: &result)
        return result
    }

    /// Decision 822: how far out from a deck's end at `end`, along level
    /// unit `outward`, the line lies on a deck of `bridges` standing
    /// within ``levelGap`` of `rise` over the ground, metres, looked at
    /// every 2 m up to `reach` and given up 20 m past the last found; 0
    /// where it leaves the decks at once, and where it runs on along one
    /// past ``Map3DRoadBridges/longestLevel`` (a street under a viaduct
    /// the end's ramp meets, not a road leaving it).
    mutating func levelRun(from end: Map3DBaseMap.Point, outward: Map3DBaseMap.Point, rise: Float, reach: Double,
                           in bridges: Map3DRoadBridges) -> Float {
        var last = 0.0
        var out = 2.0
        while out <= min(reach, Map3DRoadBridges.longestLevel + 2), out - last <= 20 {
            defer { out += 2 }
            let p = Map3DBaseMap.Point(x: end.x + outward.x * out, z: end.z + outward.z * out)
            for (number, index) in bridges.segments[Map3DRoadBridges.key(p.x, p.z)] ?? [] {
                let piece = bridges.pieces[number]
                let a = piece.points[index - 1], b = piece.points[index]
                guard Map3DRoadBridges.nearest(p, a, b).distance <= Double(Map3DRoadBridges.half(piece.kind)) + 0.5 else { continue }
                let dx = b.x - a.x, dz = b.z - a.z, length = dx * dx + dz * dz
                let share = length > 0 ? ((p.x - a.x) * dx + (p.z - a.z) * dz) / length : 0.5
                if share < 0 && index == 1 && piece.opens.first || share > 1 && index == piece.points.count - 1 && piece.opens.last { continue }
                guard abs(pieceRise(bridges, piece: number, at: p) - rise) < Map3DRoadBridges.levelGap else { continue }
                last = out
                break
            }
        }
        return last > Map3DRoadBridges.longestLevel ? 0 : Float(last)
    }

    /// Decision 391 (續篇二, HANDOFF §4.12 第 6 點): where each road on the
    /// ground of `map` crosses the track out of a tunnel more than 30° off it, on an
    /// embankment or in a cutting, the road lifted over it: its way the
    /// height a deck over the track takes (``Map3DRoadBridges/overTrack``
    /// over the bed), across the bed or the cutting and a little more,
    /// then down at its grade. Over a cutting deep enough already (decision
    /// 375), under a viaduct and on the level, it stays.
    mutating func addJoins(of map: Map3DBaseMap, into result: inout Map3DRoadBridges) {
        typealias Point = Map3DBaseMap.Point
        guard !trackCover.isEmpty else { return }
        var found: [Map3DRoadBridges.Join] = []
        var openings: [(point: Point, half: Float)] = []
        for (number, road) in map.groundRoads.enumerated() where road.points.count >= 2 {
            let line = road.points
            for index in 1..<line.count {
                let a = line[index - 1], b = line[index]
                let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
                guard length > 0.01 else { continue }
                var seen = Set<Int>()
                let low = Map3DTrackCover.key(x: Float(min(a.x, b.x)), z: Float(min(a.z, b.z)))
                let high = Map3DTrackCover.key(x: Float(max(a.x, b.x)), z: Float(max(a.z, b.z)))
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        for track in trackCover.cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] where seen.insert(track).inserted {
                            let piece = trackCover.pieces[track]
                            guard !piece.isTunnel else { continue }
                            let c = Point(x: Double(piece.a.x), z: Double(piece.a.z)), d = Point(x: Double(piece.b.x), z: Double(piece.b.z))
                            guard let share = Map3DRoadBridges.crossing(a, b, c, d) else { continue }
                            let at = Point(x: a.x + dx * share, z: a.z + dz * share)
                            // Not where the road ends: it meets the track there.
                            func far(_ q: Point) -> Bool { (at.x - q.x) * (at.x - q.x) + (at.z - q.z) * (at.z - q.z) > 4 }
                            guard far(line[0]), far(line[line.count - 1]) else { continue }
                            var crossing: Map3DRoadBridges.Crossing
                            defer { result.crossings[crossing, default: 0] += 1 }
                            let trackLength = (piece.b - piece.a).length
                            guard trackLength > 0 else { crossing = .alongside; continue }
                            let sine = Float(abs(dx * Double(piece.b.z - piece.a.z) - dz * Double(piece.b.x - piece.a.x)) / length) / trackLength
                            guard sine >= 0.5 else { crossing = .alongside; continue }
                            if piece.isViaduct { crossing = .underViaduct; continue }
                            let t = Float(((at.x - c.x) * (d.x - c.x) + (at.z - c.z) * (d.z - c.z)) / Double(trackLength * trackLength))
                            let bed = piece.a.y + (piece.b.y - piece.a.y) * min(max(t, 0), 1) - Self.bedDrop
                            let surface = drawnGround(x: Float(at.x), z: Float(at.z))
                            // How far across the track's ground it takes,
                            // metres, either side of its middle.
                            let across: Float
                            // TestFlight 113.1's crash: a height that is
                            // no number crosses nothing.
                            guard bed.isFinite, surface.isFinite else { crossing = .level; continue }
                            // The trench's rim: its floor's reach, then 1 : 1 up.
                            let rim = Map3DTrenches.floorReach + surface - bed + Map3DTrenches.floorDrop
                            if bed <= surface - Map3DRoadBridges.overTrack {
                                crossing = .overDeepCutting
                                continue
                            } else if rim > 0, trackCover.trenches.piece(at: at) != nil {
                                // A cutting's piece whose bed stands over
                                // the ground (no rim to reach) is taken as
                                // on the ground below, as an embankment or
                                // on the level (TestFlight 113.1's crash).
                                crossing = .overCutting
                                across = rim
                            } else if bed - surface >= Map3DRoadBridges.embankment {
                                let bank = Self.bedBottom / 2 + min(bed - surface, 4.7)
                                if bed - surface >= Map3DRoadBridges.underViaduct + Self.lift(of: road.kind) {
                                    // Room under it: the bank opens over the
                                    // road's width (its slant across the
                                    // bank's) and a metre each side.
                                    crossing = .underEmbankment
                                    let cosine = (1 - sine * sine).squareRoot()
                                    let rail = Map3DRoadBridges.nearest(at, c, d).point
                                    openings.append((rail, (Map3DRoadBridges.half(road.kind) + 1) / sine + bank * cosine / sine))
                                    continue
                                }
                                crossing = .overEmbankment
                                across = bank
                            } else {
                                crossing = .level
                                continue
                            }
                            let half = Map3DRoadBridges.half(road.kind), grade = Map3DRoadBridges.grade(road.kind)
                            // Its deck clear of the track's ground, its own
                            // width's slant included.
                            let plateau = (across + 2) / sine + half * (1 - sine * sine).squareRoot() / sine
                            // Never a reach backwards (the cells below would
                            // run from high to low and trap).
                            guard plateau.isFinite, plateau > 0 else { crossing = .level; continue }
                            // Clear of the rails all under it: the line's
                            // highest within the plateau, as it climbs.
                            var highest = bed
                            let reachLow = Map3DTrackCover.key(x: Float(at.x) - plateau, z: Float(at.z) - plateau)
                            let reachHigh = Map3DTrackCover.key(x: Float(at.x) + plateau, z: Float(at.z) + plateau)
                            for row in reachLow.row...reachHigh.row {
                                for column in reachLow.column...reachHigh.column {
                                    for other in trackCover.cells[Map3DScene.ChunkKey(column: column, row: row)] ?? [] {
                                        let near = trackCover.pieces[other]
                                        guard !near.isTunnel, !near.isViaduct,
                                              Map3DRoadBridges.nearest(at, Point(x: Double(near.a.x), z: Double(near.a.z)),
                                                                       Point(x: Double(near.b.x), z: Double(near.b.z))).distance <= Double(plateau) else { continue }
                                        for y in [near.a.y, near.b.y] where abs(y - Self.bedDrop - bed) < 2 { highest = max(highest, y - Self.bedDrop) }
                                    }
                                }
                            }
                            let height = highest + Map3DRoadBridges.overTrack
                            var join = Map3DRoadBridges.Join(point: at, along: Point(x: dx / length, z: dz / length), half: half, height: height,
                                                             plateau: plateau, grade: grade,
                                                             reach: plateau + min((height - surface) / grade, Map3DRoadBridges.longestRamp))
                            join.roads = result.runOn(from: at, axis: join.along, reach: Double(join.reach), first: [number])
                            found.append(join)
                        }
                    }
                }
            }
        }
        // In one order whatever order the roads came in (a road's highest
        // join wins where they meet, so the order changes nothing drawn).
        for join in found.sorted(by: { ($0.point.x, $0.point.z, $0.height) < ($1.point.x, $1.point.z, $1.height) }) {
            let reach = Double(join.reach + join.half) + 4
            let low = Map3DRoadBridges.key(join.point.x - reach, join.point.z - reach), high = Map3DRoadBridges.key(join.point.x + reach, join.point.z + reach)
            for row in low.row...high.row {
                for column in low.column...high.column { result.joinCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(result.joins.count) }
            }
            result.joins.append(join)
        }
        result.openings = openings.sorted { ($0.point.x, $0.point.z, $0.half) < ($1.point.x, $1.point.z, $1.half) }
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

    /// ROAD-RAMP-HEIGHT: how far piece `number` of `bridges` stands over
    /// the drawn ground at `p`, metres: its deck's height (``deckRise(_:at:)``),
    /// but on a link road's bridge joined to a deck's main road no higher
    /// than its way along the link roads from where they reach the ground
    /// allows at its grade (slop-taipei's `build-elevated.mjs`, MIT: "the
    /// height function itself is the ramp"), steeper where the link is too
    /// short to reach the main road's height at its grade, so it meets
    /// the main road at the main road's height; never under what it must
    /// clear of the track.
    mutating func pieceRise(_ bridges: Map3DRoadBridges, piece number: Int, at p: Map3DBaseMap.Point) -> Float {
        pieceRise(bridges, piece: number, at: p, deckRise: deckRise(bridges.decks[bridges.pieces[number].deck], at: p), along: nil)
    }

    /// The same, given its deck's ``deckRise(_:at:)`` at `p` and, when
    /// known, how far along it `p` is (``levelHeights(into:others:)``
    /// asks again and again at the same points).
    mutating func pieceRise(_ bridges: Map3DRoadBridges, piece number: Int, at p: Map3DBaseMap.Point, deckRise full: Float, along known: Double?) -> Float {
        let piece = bridges.pieces[number], deck = bridges.decks[piece.deck]
        var rise = full
        var along = known
        // ROAD-LAYER-HEIGHT: a lower level's bridge no higher than its own
        // level, or what lifts it to a higher one it joins; never under
        // what it must clear of the track.
        if let ceiling = piece.ceiling, rise > ceiling {
            var cap = ceiling
            if !piece.lifted.isEmpty {
                let s = along ?? piece.travelled(to: p)
                along = s
                cap = piece.levelCap(at: s)
            }
            if cap < rise { rise = max(cap, min(rise, floorRise(deck, at: p))) }
        }
        guard let ramp = piece.ramp, rise > 0, ramp.samples.count >= 2 else { return rise }
        let s = along ?? piece.travelled(to: p)
        var index = 1
        while index < ramp.samples.count - 1, ramp.samples[index].along < s { index += 1 }
        let before = ramp.samples[index - 1], after = ramp.samples[index]
        let t = after.along > before.along ? min(max((s - before.along) / (after.along - before.along), 0), 1) : 0
        func mix(_ a: Double, _ b: Double) -> Double { a.isFinite && b.isFinite ? a + (b - a) * t : min(a, b) }
        let down = mix(before.down, after.down), up = mix(before.up, after.up)
        guard down.isFinite, up.isFinite else { return rise }
        let grade = Map3DRoadBridges.grade(piece.kind)
        let cap = down + up > 0 ? max(Float(down) * grade, rise * Float(down / (down + up))) : 0
        guard cap < rise else { return rise }
        return min(rise, max(cap, floorRise(deck, at: p)))
    }

    /// What `deck` must clear of the track at `p`: how far over the drawn
    /// ground it must stand there, metres (0 where nothing holds it up).
    mutating func floorRise(_ deck: Map3DRoadBridges.Deck, at p: Map3DBaseMap.Point) -> Float {
        guard deck.bounds.contains(where: \.isFloor) else { return 0 }
        let ground = drawnGround(x: Float(p.x), z: Float(p.z))
        var floor: Float = 0
        for bound in deck.bounds where bound.isFloor {
            let distance = Float(((p.x - bound.point.x) * (p.x - bound.point.x) + (p.z - bound.point.z) * (p.z - bound.point.z)).squareRoot())
            floor = max(floor, bound.height - deck.grade * distance - ground)
        }
        return floor
    }

    /// ROAD-LAYER-HEIGHT: each bridge of a lower level than its deck's
    /// highest (decision 391 stood the whole deck at the highest level's
    /// height: 忠孝橋, `layer` 1, at 三重's viaduct's 24 m, `layer` 4) gets
    /// its own level's height as its ``Map3DRoadBridges/Piece/ceiling``,
    /// and is lifted over it (``Map3DRoadBridges/Piece/lifted``) only to
    /// meet another bridge of its deck standing higher: where an end of
    /// one meets the other's line (``Map3DRoadBridges/join``), and where
    /// it runs along the other's surface (their lines under 20° apart,
    /// ``Map3DRoadBridges/crossingSine``, their drawn widths overlapping:
    /// a road's two carriageways, a link beside its main road), coming
    /// down from there at twice its grade at most
    /// (``Map3DRoadBridges/steepestRamp``). Lifting one may lift another,
    /// so it is done again until nothing moves. One crossing another at a
    /// wider angle passes under it at its own level. `others` gives the
    /// pieces within ``Map3DRoadBridges/join`` of a point.
    mutating func levelHeights(into result: inout Map3DRoadBridges, others: (Map3DBaseMap.Point, Int) -> [Int]) {
        typealias Point = Map3DBaseMap.Point
        var top: [Int: Int] = [:]
        for piece in result.pieces { top[piece.deck] = max(top[piece.deck] ?? 0, piece.level) }
        let lower = result.pieces.indices.filter { result.pieces[$0].level < top[result.pieces[$0].deck]! && result.pieces[$0].points.count >= 2 }
        guard !lower.isEmpty else { return }
        for number in lower { result.pieces[number].ceiling = Map3DRoadBridges.levelRise * Float(result.pieces[number].level) }
        func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }
        // Each lower piece's samples every ``rampSample`` metres along it,
        // and where it meets another end to line, exactly.
        var looked: [Int: [(along: Double, point: Point, direction: Point)]] = [:]
        for number in lower {
            let piece = result.pieces[number]
            var found: [(along: Double, point: Point, direction: Point)] = []
            var travelled = 0.0
            for (a, b) in zip(piece.points, piece.points.dropFirst()) {
                let length = distance(a, b)
                defer { travelled += length }
                guard length > 1e-6 else { continue }
                let direction = Point(x: (b.x - a.x) / length, z: (b.z - a.z) / length)
                var along = found.isEmpty ? 0 : Map3DRoadBridges.rampSample - travelled.truncatingRemainder(dividingBy: Map3DRoadBridges.rampSample)
                while along < length {
                    found.append((travelled + along, Point(x: a.x + direction.x * along, z: a.z + direction.z * along), direction))
                    along += Map3DRoadBridges.rampSample
                }
            }
            if let last = found.last, travelled > last.along + 1e-9 { found.append((travelled, piece.points[piece.points.count - 1], last.direction)) }
            if !found.isEmpty { looked[number] = found }
        }
        // Where pieces of a deck meet end to line, either way: (the piece,
        // the other, the point).
        var touches: [(piece: Int, other: Int, point: Point)] = []
        for (number, piece) in result.pieces.enumerated() where piece.points.count >= 2 {
            for end in [piece.points[0], piece.points[piece.points.count - 1]] {
                for other in others(end, number) where result.pieces[other].deck == piece.deck {
                    if looked[number] != nil { touches.append((number, other, end)) }
                    if looked[other] != nil { touches.append((other, number, end)) }
                }
            }
        }
        for touch in touches {
            let along = result.pieces[touch.piece].travelled(to: touch.point)
            guard var samples = looked[touch.piece], !samples.contains(where: { abs($0.along - along) < 0.05 }) else { continue }
            let at = samples.firstIndex { $0.along > along } ?? samples.count
            let direction = samples[max(at - 1, 0)].direction
            samples.insert((along, touch.point, direction), at: at)
            looked[touch.piece] = samples
        }
        // Where each crosses another of its deck (20° or more apart, not
        // by either one's ends): an exact sample there too.
        var crossings: [(piece: Int, other: Int, point: Point, along: Double)] = []
        for number in lower {
            let piece = result.pieces[number]
            var travelled = 0.0
            for (a, b) in zip(piece.points, piece.points.dropFirst()) {
                let length = distance(a, b)
                defer { travelled += length }
                guard length > 1e-6 else { continue }
                let low = Map3DRoadBridges.key(min(a.x, b.x), min(a.z, b.z)), high = Map3DRoadBridges.key(max(a.x, b.x), max(a.z, b.z))
                var seen = Set<Int>()
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        for (other, at) in result.segments[Map3DScene.ChunkKey(column: column, row: row)] ?? [] where other != number {
                            let them = result.pieces[other]
                            guard them.deck == piece.deck, seen.insert(other * 100_000 + at).inserted else { continue }
                            let c = them.points[at - 1], d = them.points[at], span = distance(c, d)
                            guard span > 1e-6, let share = Map3DRoadBridges.crossing(a, b, c, d),
                                  abs((b.x - a.x) * (d.z - c.z) - (b.z - a.z) * (d.x - c.x)) / (length * span) >= Map3DRoadBridges.crossingSine else { continue }
                            let p = Point(x: a.x + (b.x - a.x) * share, z: a.z + (b.z - a.z) * share)
                            let ends = [piece.points[0], piece.points[piece.points.count - 1], them.points[0], them.points[them.points.count - 1]]
                            guard !ends.contains(where: { distance($0, p) < 2 }) else { continue }
                            crossings.append((number, other, p, travelled + share * length))
                        }
                    }
                }
            }
        }
        for crossing in crossings {
            guard var samples = looked[crossing.piece], !samples.contains(where: { abs($0.along - crossing.along) < 0.05 }) else { continue }
            let at = samples.firstIndex { $0.along > crossing.along } ?? samples.count
            samples.insert((crossing.along, crossing.point, samples[max(at - 1, 0)].direction), at: at)
            looked[crossing.piece] = samples
        }
        // What may hold each up: (its sample, the other piece, the point
        // on it, the other's deck height there, how far along the other
        // it is, whether it crosses it, its own deck height there): the
        // touches, the pieces of its deck whose surface it runs along,
        // and those it crosses.
        var holds: [Int: [(sample: Int, other: Int, point: Point, deck: Float, along: Double, crossing: Bool, own: Float)]] = [:]
        func hold(_ number: Int, _ index: Int, _ other: Int, _ point: Point, crossing: Bool = false) {
            let deck = deckRise(result.decks[result.pieces[other].deck], at: point)
            holds[number, default: []].append((index, other, point, deck, result.pieces[other].travelled(to: point), crossing, crossing ? deck : 0))
        }
        for touch in touches {
            let along = result.pieces[touch.piece].travelled(to: touch.point)
            guard let index = looked[touch.piece]!.firstIndex(where: { abs($0.along - along) < 0.05 }) else { continue }
            hold(touch.piece, index, touch.other, touch.point)
        }
        for crossing in crossings {
            guard let index = looked[crossing.piece]!.firstIndex(where: { abs($0.along - crossing.along) < 0.05 }) else { continue }
            hold(crossing.piece, index, crossing.other, crossing.point, crossing: true)
        }
        // Where two pieces meet (a fork, a T), each one's points there.
        var meets: [Int: [Int: [Point]]] = [:]
        for touch in touches { meets[touch.piece, default: [:]][touch.other, default: []].append(touch.point) }
        for number in lower {
            guard let samples = looked[number] else { continue }
            let piece = result.pieces[number]
            let half = Double(Map3DRoadBridges.half(piece.kind, ramp: piece.isRamp))
            let reach = half + Double(Map3DRoadBridges.half(.motorway))
            for (index, sample) in samples.enumerated() {
                let q = sample.point
                let low = Map3DRoadBridges.key(q.x - reach, q.z - reach), high = Map3DRoadBridges.key(q.x + reach, q.z + reach)
                var seen: Set<Int> = [number]
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        for (other, at) in result.segments[Map3DScene.ChunkKey(column: column, row: row)] ?? [] {
                            let beside = result.pieces[other]
                            guard beside.deck == piece.deck, !seen.contains(other) else { continue }
                            let c = beside.points[at - 1], d = beside.points[at], span = distance(c, d)
                            let on = Map3DRoadBridges.nearest(q, c, d)
                            let width = half + Double(Map3DRoadBridges.half(beside.kind, ramp: beside.isRamp))
                            guard span > 1e-6, on.distance < width else { continue }
                            // Along it, or by where the two meet (their
                            // surfaces overlap round a fork or a T at any
                            // angle); not one crossing it elsewhere.
                            let along = abs(sample.direction.x * (d.z - c.z) - sample.direction.z * (d.x - c.x)) / span < Map3DRoadBridges.crossingSine
                            guard along || (meets[number]?[other] ?? []).contains(where: { distance($0, q) < width + Map3DRoadBridges.rampSample }) else { continue }
                            seen.insert(other)
                            hold(number, index, other, on.point)
                        }
                    }
                }
            }
        }
        // Lifted until nothing moves (each pass can only raise, and no
        // higher than the deck's own height).
        for _ in 0..<12 {
            var changed = false
            for number in lower {
                guard let samples = looked[number], let found = holds[number] else { continue }
                let piece = result.pieces[number], ceiling = piece.ceiling!
                var need = [Float](repeating: 0, count: samples.count)
                for hold in found {
                    let rise = pieceRise(result, piece: hold.other, at: hold.point, deckRise: hold.deck, along: hold.along)
                    if hold.crossing {
                        // Decision 607: a storey apart or at one height. One
                        // that cannot come down far enough under the other
                        // crosses it at its height, as the whole deck did.
                        let mine = pieceRise(result, piece: number, at: hold.point, deckRise: hold.own, along: samples[hold.sample].along)
                        guard rise - mine > 0.3, rise - mine < 4.8 else { continue }
                    }
                    if rise > ceiling, rise > need[hold.sample] { need[hold.sample] = rise }
                }
                guard need.contains(where: { $0 > ceiling + 0.01 }) || !piece.lifted.isEmpty else { continue }
                // Coming down from each at twice its grade, either way.
                let slope = Float(Map3DRoadBridges.steepestRamp) * Map3DRoadBridges.grade(piece.kind)
                for index in samples.indices.dropFirst() {
                    need[index] = max(need[index], need[index - 1] - slope * Float(samples[index].along - samples[index - 1].along))
                }
                for index in samples.indices.dropLast().reversed() {
                    need[index] = max(need[index], need[index + 1] - slope * Float(samples[index + 1].along - samples[index].along))
                }
                var lifted = zip(samples, need).map { (along: $0.along, rise: max($1, ceiling)) }
                if !lifted.contains(where: { $0.rise > ceiling + 0.01 }) { lifted = [] }
                // Never lower than it was: a pass only raises.
                if lifted.count == piece.lifted.count { lifted = zip(lifted, piece.lifted).map { ($0.along, max($0.rise, $1.rise)) } }
                if lifted.count != piece.lifted.count || zip(lifted, piece.lifted).contains(where: { $0.rise > $1.rise + 0.05 }) {
                    result.pieces[number].lifted = lifted
                    changed = true
                }
            }
            if !changed { break }
        }
    }

    /// ROAD-RAMP-HEIGHT: each link road's bridge joined end to end to a
    /// deck's main road (a bridge not a link) gets its ``Map3DRoadBridges/Piece/ramp``:
    /// shortest ways along the link roads' bridges of the deck, end to
    /// end, from their open ends (where they come down to the ground) and
    /// from where they leave the main road: their ends that meet it, and
    /// where they still lie on its surface with room enough to come down
    /// (slop-taipei's `build-elevated.mjs`, MIT: Dijkstra from the
    /// portals). `others` gives the pieces within ``Map3DRoadBridges/join``
    /// of a point.
    func rampDistances(into result: inout Map3DRoadBridges, others: (Map3DBaseMap.Point, Int) -> [Int]) {
        typealias Point = Map3DBaseMap.Point
        let pieces = result.pieces
        var mains = Set<Int>()
        for piece in pieces where !piece.isRamp { mains.insert(piece.deck) }
        let ramps = pieces.indices.filter {
            pieces[$0].isRamp && mains.contains(pieces[$0].deck) && pieces[$0].points.count >= 2 && !result.decks[pieces[$0].deck].lifts.isEmpty
        }
        guard !ramps.isEmpty else { return }
        func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }
        // Whether `q` on a link road of `deck` `half` wide lies on one of
        // the deck's main roads' surfaces.
        // ROAD-LAYER-HEIGHT: the highest level of them, `nil` on none.
        func onMain(_ q: Point, deck: Int, half: Double) -> Int? {
            var found: Int?
            let reach = half + Double(Map3DRoadBridges.half(.motorway))
            let low = Map3DRoadBridges.key(q.x - reach, q.z - reach), high = Map3DRoadBridges.key(q.x + reach, q.z + reach)
            for row in low.row...high.row {
                for column in low.column...high.column {
                    for (number, index) in result.segments[Map3DScene.ChunkKey(column: column, row: row)] ?? [] {
                        let piece = pieces[number]
                        guard piece.deck == deck, !piece.isRamp else { continue }
                        if Map3DRoadBridges.nearest(q, piece.points[index - 1], piece.points[index]).distance < half + Double(Map3DRoadBridges.half(piece.kind)) {
                            found = max(found ?? piece.level, piece.level)
                        }
                    }
                }
            }
            return found
        }
        // Each ramp piece looked at every sample, the samples nodes joined
        // along it, and its ends to the ends of the deck's other ramp
        // pieces they meet.
        var first: [Int: Int] = [:], final: [Int: Int] = [:]
        var samples: [(piece: Int, along: Double, point: Point)] = []
        for number in ramps {
            first[number] = samples.count
            let points = pieces[number].points
            var travelled = 0.0
            samples.append((number, 0, points[0]))
            for (a, b) in zip(points, points.dropFirst()) {
                let length = distance(a, b)
                var along = Map3DRoadBridges.rampSample - travelled.truncatingRemainder(dividingBy: Map3DRoadBridges.rampSample)
                while along < length {
                    samples.append((number, travelled + along, Point(x: a.x + (b.x - a.x) * along / length, z: a.z + (b.z - a.z) * along / length)))
                    along += Map3DRoadBridges.rampSample
                }
                travelled += length
            }
            if travelled > samples[samples.count - 1].along + 1e-9 || samples.count - first[number]! < 2 {
                samples.append((number, travelled, points[points.count - 1]))
            }
            final[number] = samples.count - 1
        }
        var edges = [[(node: Int, length: Double)]](repeating: [], count: samples.count)
        var portals: [Int] = [], junctions: [Int] = []
        for number in ramps {
            let low = first[number]!, high = final[number]!
            for node in low..<high {
                let length = samples[node + 1].along - samples[node].along
                edges[node].append((node + 1, length))
                edges[node + 1].append((node, length))
            }
            if pieces[number].opens.first { portals.append(low) }
            if pieces[number].opens.last { portals.append(high) }
            for node in [low, high] {
                let p = samples[node].point
                for other in others(p, number) where pieces[other].deck == pieces[number].deck {
                    if pieces[other].isRamp, let low = first[other], let high = final[other] {
                        let ends = [low, high].filter { distance(samples[$0].point, p) <= Map3DRoadBridges.join }
                        for otherNode in ends { edges[node].append((otherNode, 0)) }
                        // Decision 822 (後來三): an end meeting the other's
                        // side (三重's link from 忠孝橋 meets a loop's
                        // middle): joined to its nearest sample.
                        if ends.isEmpty, let nearest = (low...high).min(by: { distance(samples[$0].point, p) < distance(samples[$1].point, p) }) {
                            let length = distance(samples[nearest].point, p)
                            edges[node].append((nearest, length))
                            edges[nearest].append((node, length))
                        }
                    } else if !pieces[other].isRamp {
                        junctions.append(node)
                    }
                }
            }
        }
        guard !portals.isEmpty else { return }
        // Dijkstra from `sources` (a binary heap of distance, node).
        func distances(from sources: [Int]) -> [Double] {
            var found = [Double](repeating: .infinity, count: samples.count)
            var heap: [(distance: Double, node: Int)] = []
            func less(_ a: Int, _ b: Int) -> Bool { (heap[a].distance, heap[a].node) < (heap[b].distance, heap[b].node) }
            func push(_ item: (distance: Double, node: Int)) {
                heap.append(item)
                var child = heap.count - 1
                while child > 0, less(child, (child - 1) / 2) {
                    heap.swapAt(child, (child - 1) / 2)
                    child = (child - 1) / 2
                }
            }
            func pop() -> (distance: Double, node: Int) {
                let top = heap[0]
                heap[0] = heap[heap.count - 1]
                heap.removeLast()
                var parent = 0
                while true {
                    var smallest = parent
                    for child in [2 * parent + 1, 2 * parent + 2] where child < heap.count && less(child, smallest) { smallest = child }
                    guard smallest != parent else { break }
                    heap.swapAt(parent, smallest)
                    parent = smallest
                }
                return top
            }
            for source in Set(sources).sorted() { push((0, source)) }
            while !heap.isEmpty {
                let next = pop()
                guard next.distance < found[next.node] else { continue }
                found[next.node] = next.distance
                for edge in edges[next.node] where next.distance + edge.length < found[edge.node] { push((next.distance + edge.length, edge.node)) }
            }
            return found
        }
        let down = distances(from: portals)
        // Where a link road still lies on its main road's surface with
        // room to come down from there at twice its grade at most, it
        // leaves the main road there.
        // ROAD-LAYER-HEIGHT: the main road's own level's height, not the
        // deck's highest (a link beside a `layer` 2 road came down past
        // it only where it had room to come down from a `layer` 4's).
        for (node, sample) in samples.enumerated() where down[node].isFinite {
            let piece = pieces[sample.piece]
            guard let level = onMain(sample.point, deck: piece.deck, half: Double(piece.kind.width(ramp: true)) / 2) else { continue }
            let rise = min(Double(result.decks[piece.deck].lifts.map(\.rise).max() ?? 0), Double(Map3DRoadBridges.levelRise) * Double(level))
            if down[node] * Map3DRoadBridges.steepestRamp * Double(Map3DRoadBridges.grade(piece.kind)) >= rise { junctions.append(node) }
        }
        guard !junctions.isEmpty else { return }
        let up = distances(from: junctions)
        for number in ramps {
            let nodes = first[number]!...final[number]!
            guard nodes.contains(where: { down[$0].isFinite }), nodes.contains(where: { up[$0].isFinite }) else { continue }
            result.pieces[number].ramp = .init(samples: nodes.map { (samples[$0].along, down[$0], up[$0]) })
        }
    }

    /// Decision 391: how far a road at level point `p`, running along
    /// `along` (or any way, when `nil`), lies over the drawn ground,
    /// metres, and whether it is on a bridge's deck there: on one, the
    /// deck's height; on a road running on from a bridge's end, its ramp
    /// down; else 0. Only a road `onDeck` (a bridge's) is on a deck: one
    /// on the ground under it is not.
    mutating func roadRise(at p: Map3DBaseMap.Point, along: (x: Double, z: Double)?, onDeck: Bool) -> (rise: Float, onBridge: Bool) {
        let bridges = roadBridges
        guard !bridges.isEmpty || !roadGrade.isEmpty else { return (0, false) }
        let key = Map3DRoadBridges.key(p.x, p.z)
        var best: (rise: Float, onBridge: Bool) = (0, false)
        // ROAD-RAMP-HEIGHT: on each deck, the piece whose line is nearest:
        // a link road coming down beside or under its main road is at its
        // own height, the main road at the deck's.
        var nearest: [Int: (distance: Double, piece: Int)] = [:]
        for (number, index) in onDeck ? bridges.segments[key] ?? [] : [] {
            let piece = bridges.pieces[number]
            let a = piece.points[index - 1], b = piece.points[index]
            let distance = Map3DRoadBridges.nearest(p, a, b).distance
            guard distance <= Double(Map3DRoadBridges.half(piece.kind)) + 0.5 else { continue }
            if let kept = nearest[piece.deck], (kept.distance, kept.piece) <= (distance, number) { continue }
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            // Past a deck's end is off it: a road running on ramps down.
            let share = length > 0 ? ((p.x - a.x) * dx + (p.z - a.z) * dz) / (length * length) : 0.5
            if share < 0 && index == 1 && piece.opens.first || share > 1 && index == piece.points.count - 1 && piece.opens.last { continue }
            if let along {
                guard length < 1 || abs(dx * along.x + dz * along.z) / length >= 0.9 else { continue }
            }
            nearest[piece.deck] = (distance, number)
        }
        for (_, found) in nearest.sorted(by: { $0.key < $1.key }) {
            best = (max(best.rise, pieceRise(bridges, piece: found.piece, at: p)), true)
        }
        for number in bridges.endCells[key] ?? [] {
            let end = bridges.ends[number]
            let vx = p.x - end.point.x, vz = p.z - end.point.z
            let out = vx * end.outward.x + vz * end.outward.z
            guard out >= -1 else { continue }
            let lateral = abs(vx * end.outward.z - vz * end.outward.x)
            guard lateral <= Double(end.half) + 0.15 * max(out, 0) else { continue }
            if let along, abs(along.x * end.outward.x + along.z * end.outward.z) < 0.9 { continue }
            let fall = Float(max(out, 0)) - end.plateau
            let rise = end.rise - end.grade * max(fall, 0)
            // A ramp longer than the longest stands as the deck's end.
            // Review H4: only on a road running on from it.
            guard fall <= Map3DRoadBridges.longestRamp, rise > 0, bridges.isOn(p, end.roads) else { continue }
            best.rise = max(best.rise, rise)
        }
        // Decision 391 (續篇二): a road on the ground lifted over the
        // track, on its deck across the track's ground.
        for number in onDeck ? [] : bridges.joinCells[key] ?? [] {
            let join = bridges.joins[number]
            let vx = p.x - join.point.x, vz = p.z - join.point.z
            let out = Float(abs(vx * join.along.x + vz * join.along.z))
            guard out <= join.reach, Float(abs(vx * join.along.z - vz * join.along.x)) <= join.half + 0.5 + 0.1 * max(0, out - join.plateau) else { continue }
            if let along, abs(along.x * join.along.x + along.z * join.along.z) < 0.9 { continue }
            let rise = join.height - join.grade * max(0, out - join.plateau) - drawnGround(x: Float(p.x), z: Float(p.z))
            guard rise > 0, bridges.isOn(p, join.roads) else { continue }
            best = (max(best.rise, rise), best.onBridge || out <= join.plateau)
        }
        // Decision 834: a motorway on its profile: a deck no lower, a road
        // on the ground lifted over it (a deck once its girder is clear)
        // or down in its cutting.
        if !roadGrade.isEmpty, let graded = roadGrade.profile(at: p, along: along, onDeck: onDeck) {
            let rise = graded.height - drawnGround(x: Float(p.x), z: Float(p.z))
            if onDeck {
                best = (max(best.rise, rise), true)
            } else if graded.inCut, best.rise <= 0 {
                best.rise = rise
            } else if rise > best.rise {
                best = (rise, best.onBridge || rise >= Map3DElevatedLook.roadBridge.girderDepth + 0.5)
            }
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
            let top = ground + Self.lift(of: piece.kind) + pieceRise(bridges, piece: number, at: probe)
            if abs(top - height) < within { return true }
        }
        for (number, index) in bridges.groundCells[key] ?? [] {
            let road = bridges.grounds[number]
            let a = road.points[index - 1], b = road.points[index]
            let dx = b.x - a.x, dz = b.z - a.z, length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01, covers(a, b, half: Map3DRoadBridges.half(road.kind, ramp: road.isRamp)) else { continue }
            let top = ground + Self.lift(of: road.kind) + roadRise(at: probe, along: (dx / length, dz / length), onDeck: false).rise
            if abs(top - height) < within { return true }
        }
        return false
    }

    /// Decision 391: whether a road from `a` to `b` may come near a
    /// raised road (a bridge or a ramp onto one).
    func nearRaisedRoad(from a: Map3DBaseMap.Point, to b: Map3DBaseMap.Point) -> Bool {
        guard !roadBridges.isEmpty || !roadGrade.isEmpty else { return false }
        let low = Map3DRoadBridges.key(min(a.x, b.x), min(a.z, b.z)), high = Map3DRoadBridges.key(max(a.x, b.x), max(a.z, b.z))
        for row in low.row...high.row {
            for column in low.column...high.column {
                let key = Map3DScene.ChunkKey(column: column, row: row)
                if roadBridges.segments[key] != nil || roadBridges.endCells[key] != nil || roadBridges.joinCells[key] != nil { return true }
                // Decision 834: a motorway off its ground.
                if roadGrade.cells[key] != nil { return true }
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
        guard !roadBridges.isEmpty || !roadGrade.isEmpty else { return }
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
                        guard !nearTrack(x: top.x, z: top.z, within: look.column / 2 + 3),
                              trackCover.trenches.piece(at: Point(x: Double(top.x), z: Double(top.z))) == nil else { continue }
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
