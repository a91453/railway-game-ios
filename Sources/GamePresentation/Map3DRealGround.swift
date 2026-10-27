import GameCore

// Decision 234: a real-world map's ground in 3D, from the base map the 2D
// map draws: the land's cover, rivers and roads laid on the 64 m ground.
//
// The reference's location modeler lays its far zone the same way
// (`RKFAR.build` in `Railway/location_modeler_reference_clean/source/js/app.js`):
// roads as flat strips a little over the ground, split where the ground's
// triangles meet so they never sink into it (its `surf`), each class at
// its own width. Its land cover is painted into the ground grid's
// corners; here the polygons are cut to the ground's triangles instead,
// so a park keeps its shape on a 64 m grid.

extension Map3DScene.Builder {
    /// How far over the ground each part of the base map lies, in metres:
    /// each cover over the ones before it, the roads over the water, the
    /// bigger roads over the smaller, and all of them under the shadows
    /// (``Map3DShadow/lift``) and the track (``Map3DScene/railLift``).
    /// Decision 393: 0.035 m apart (0.04 before farmland came first), so
    /// the water stays under the sidewalks.
    static func lift(of cover: Map3DBaseMap.Cover) -> Float {
        0.035 * Float(cover.rawValue + 1)
    }

    static func lift(of road: Map3DBaseMap.RoadKind) -> Float {
        switch road {
        case .service, .minor: 0.28
        case .tertiary, .secondary, .primary: 0.32
        case .trunk, .motorway: 0.36
        }
    }

    /// Decision 241: the sidewalks under the roads, over every cover, and
    /// the centre lines over every road.
    static let sidewalkLift: Float = 0.26
    static let centreLineLift: Float = 0.38

    /// The sidewalk each side of a road, in metres: the 3D city preview's
    /// (`Web/CityView/tools/pipeline/taiwan.mjs`, `SIDEWALK`); none on a
    /// lane, a service road or a motorway.
    static func sidewalk(of road: Map3DBaseMap.RoadKind) -> Float {
        switch road {
        case .trunk, .primary, .secondary: 3
        case .tertiary: 2
        case .motorway, .minor, .service: 0
        }
    }

    /// Whether a road gets a yellow centre line: a two-way road of
    /// Taiwan's (a motorway's carriageways are apart, a ramp runs one way).
    static func hasCentreLine(_ road: Map3DBaseMap.Road) -> Bool {
        !road.isRamp && [.trunk, .primary, .secondary, .tertiary].contains(road.kind)
    }

    /// Half a city lot's side: water this near a lot's middle (in both
    /// directions) takes the lot, and a road this near leaves it only the
    /// room beside it (decision 345).
    static let lotReach: Float = 20

    /// The 64 m cells (by column and row) a real map's ground takes from
    /// the city's lots.
    struct TakenGround {
        /// The cells whose lot water, a park or a river takes.
        var whole = Set<Map3DScene.ChunkKey>()
        /// Decision 345: the cells only roads reach, whose lot keeps
        /// the room they leave (``roomBesideRoads(column:row:side:in:)``).
        var byRoads = Set<Map3DScene.ChunkKey>()
    }

    /// Lays `map` on the ground; the cells it takes from the city's lots.
    mutating func addBaseMap(_ map: Map3DBaseMap) -> TakenGround {
        var taken = TakenGround()
        // Decision 391: its bridges' decks, before the roads on them.
        roadBridges = bridgeDecks(of: map, frame: RealWorldFrame(world: world))
        for cover in Map3DBaseMap.Cover.allCases {
            for area in map.areas where area.cover == cover {
                addArea(area, taking: &taken.whole)
            }
        }
        for waterway in map.waterways {
            addStrip(waterway.points, bounds: waterway.bounds, width: waterway.kind.width,
                     lift: Self.lift(of: .water), color: Map3DPalette.water, paint: nil, water: true, taking: &taken.whole)
        }
        addRoads(map.roads, taking: &taken.byRoads)
        addRoadBridges(map.roads)
        taken.byRoads.subtract(taken.whole)
        return taken
    }

    /// Decision 391: no street furniture on a road this far over the
    /// ground (a bridge or its ramp), metres.
    static let propRise: Float = 0.3

    /// Decision 345: no lot's building is drawn narrower than this many
    /// metres beside the roads (a row of 透天厝 each side of 7 m deep).
    static let smallestLot = 16

    /// The road pieces (``roadLines``) by the cells they come within their
    /// half width of: each piece's ends, scene metres, and half width.
    func roadPieces(near cells: Set<Map3DScene.ChunkKey>) -> [Map3DScene.ChunkKey: [(a: Map3DPoint, b: Map3DPoint, half: Float)]] {
        var pieces: [Map3DScene.ChunkKey: [(a: Map3DPoint, b: Map3DPoint, half: Float)]] = [:]
        guard !cells.isEmpty else { return pieces }
        for (points, half) in roadLines {
            for (a, b) in zip(points, points.dropFirst()) {
                let reach = Double(half) + 1
                let west = gridCell(Double(min(a.x, b.x)) - reach, origin: originX), east = gridCell(Double(max(a.x, b.x)) + reach, origin: originX)
                let north = gridCell(Double(min(a.z, b.z)) - reach, origin: originY), south = gridCell(Double(max(a.z, b.z)) + reach, origin: originY)
                for row in north...south {
                    for column in west...east where cells.contains(Map3DScene.ChunkKey(column: column, row: row)) {
                        pieces[Map3DScene.ChunkKey(column: column, row: row), default: []].append((a, b, half))
                    }
                }
            }
        }
        return pieces
    }

    /// Decision 345: the biggest square of cell (`column`, `row`), up to
    /// `side` metres, that keeps half a metre clear of `pieces` (the
    /// roads and their pavements) and a metre in from the cell's edges,
    /// the one nearest the cell's middle: its middle in world units and
    /// its side in metres; `nil` when it is under ``smallestLot``.
    func roomBesideRoads(column: Int, row: Int, side: Int, in pieces: [(a: Map3DPoint, b: Map3DPoint, half: Float)])
        -> (x: Double, y: Double, side: Int)? {
        let size = Int(Double(Land.cellLength) / Self.metre)
        let west = Float(gridLine(column, origin: originX)), north = Float(gridLine(row, origin: originY))
        // Each metre square of the cell, clear or not.
        var clear = [Bool](repeating: true, count: size * size)
        for j in 0..<size {
            for i in 0..<size where i == 0 || j == 0 || i == size - 1 || j == size - 1 {
                clear[j * size + i] = false
            }
        }
        for piece in pieces {
            // A square is not clear when any of it comes within half a
            // metre of the piece's strip: its middle within half its
            // diagonal more.
            let reach = piece.half + 0.5 + 0.71
            let lowI = max(0, Int((min(piece.a.x, piece.b.x) - reach - west).rounded(.down)))
            let highI = min(size - 1, Int((max(piece.a.x, piece.b.x) + reach - west).rounded(.down)))
            let lowJ = max(0, Int((min(piece.a.z, piece.b.z) - reach - north).rounded(.down)))
            let highJ = min(size - 1, Int((max(piece.a.z, piece.b.z) + reach - north).rounded(.down)))
            guard lowI <= highI, lowJ <= highJ else { continue }
            let dx = piece.b.x - piece.a.x, dz = piece.b.z - piece.a.z
            let length2 = dx * dx + dz * dz
            for j in lowJ...highJ {
                for i in lowI...highI where clear[j * size + i] {
                    let px = west + Float(i) + 0.5 - piece.a.x, pz = north + Float(j) + 0.5 - piece.a.z
                    let t = length2 > 0 ? min(max((px * dx + pz * dz) / length2, 0), 1) : 0
                    let ox = px - dx * t, oz = pz - dz * t
                    if ox * ox + oz * oz < reach * reach { clear[j * size + i] = false }
                }
            }
        }
        // The biggest clear square ending at each metre square (south-east
        // corner), the usual running count.
        var biggest = [Int](repeating: 0, count: size * size), most = 0
        for j in 0..<size {
            for i in 0..<size where clear[j * size + i] {
                let n = i == 0 || j == 0 ? 1 : 1 + min(biggest[j * size + i - 1], biggest[(j - 1) * size + i], biggest[(j - 1) * size + i - 1])
                biggest[j * size + i] = n
                most = max(most, n)
            }
        }
        let wanted = min(most, side)
        guard wanted >= Self.smallestLot else { return nil }
        var best: (i: Int, j: Int, off: Int)?
        for j in 0..<size {
            for i in 0..<size where biggest[j * size + i] >= wanted {
                // Twice the square's middle less the cell's, each way.
                let ox = 2 * i + 2 - wanted - size, oz = 2 * j + 2 - wanted - size
                let off = ox * ox + oz * oz
                if best.map({ off < $0.off }) ?? true { best = (i, j, off) }
            }
        }
        guard let best else { return nil }
        let middleX = Double(west) + Double(best.i + 1) - Double(wanted) / 2
        let middleZ = Double(north) + Double(best.j + 1) - Double(wanted) / 2
        return (originX + middleX * Self.metre, originY + middleZ * Self.metre, wanted)
    }

    /// Decision 241: `roads` on the ground, each with its sidewalks and
    /// centre line, then (decision 244) their street furniture and
    /// (decision 259) their traffic and pavements' people: a real map's
    /// roads, or (decision 263) the seeded streets of a map without one.
    mutating func addRoads(_ roads: [Map3DBaseMap.Road], taking taken: inout Set<Map3DScene.ChunkKey>) {
        for road in roads {
            roadLines.append((road.points.map { Map3DPoint(Float($0.x), 0, Float($0.z)) },
                              road.kind.width(ramp: road.isRamp) / 2 + Self.sidewalk(of: road.kind)))
            roadKinds.append((road.kind, road.isRamp))
        }
        // Decision 241: the sidewalks first, a strip wider than the road
        // under it, so both edges show and they close at the junctions.
        for road in roads where Self.sidewalk(of: road.kind) > 0 && !road.isRamp {
            addStrip(road.points, bounds: road.bounds, width: road.kind.width(ramp: false) + 2 * Self.sidewalk(of: road.kind),
                     lift: Self.sidewalkLift, color: Map3DPalette.sidewalk, paint: Self.paving, raised: true, onDeck: road.bridgeLevel > 0,
                     taking: &taken)
        }
        for kind in Map3DBaseMap.RoadKind.allCases {
            for road in roads where road.kind == kind {
                addStrip(road.points, bounds: road.bounds, width: kind.width(ramp: road.isRamp), lift: Self.lift(of: kind),
                         color: Map3DPalette.road(kind), paint: nil, raised: true, onDeck: road.bridgeLevel > 0, taking: &taken)
            }
        }
        // Decision 355: the paint at the junctions, the centre lines
        // stopping at their crossings.
        // Decision 429: the junctions where they are in the world, for
        // their signals' offsets.
        let markings = Map3DRoadMarkings(roads, origin: Map3DBaseMap.Point(x: originX / Double(WorldCoordinate.unitsPerMetre),
                                                                           z: originY / Double(WorldCoordinate.unitsPerMetre)))
        var lines = Set<Map3DScene.ChunkKey>()
        for (number, road) in roads.enumerated() where Self.hasCentreLine(road) {
            for piece in markings.centreLines(of: road, number: number) {
                addStrip(piece, bounds: road.bounds, width: 0.3, lift: Self.centreLineLift, color: Map3DPalette.centreLine, paint: nil,
                         raised: true, onDeck: road.bridgeLevel > 0, taking: &lines)
            }
        }
        addRoadMarkings(markings)
        addStreetProps(roads)
        addStreetStops(roads, markings: markings)
        // Decision 259: their traffic and their pavements' people.
        for road in roads where road.points.count >= 2 { addStreetLife(road) }
    }

    // MARK: Cover

    /// The scene's x (or z) of the world's 64 m grid line `index`.
    func gridLine(_ index: Int, origin: Double) -> Double {
        (Double(index) * Double(Land.cellLength) - origin) / Self.metre
    }

    /// The grid cell holding scene coordinate `value`.
    func gridCell(_ value: Double, origin: Double) -> Int {
        Int(((origin + value * Self.metre) / Double(Land.cellLength)).rounded(.down))
    }

    /// `area` cut to the ground's triangles, each piece at its triangle's
    /// height.
    mutating func addArea(_ area: Map3DBaseMap.Area, taking taken: inout Set<Map3DScene.ChunkKey>) {
        guard let outer = area.rings.first else { return }
        let bounds = area.bounds
        let lowX = max(outer.map(\.x).min() ?? 0, bounds.minX), highX = min(outer.map(\.x).max() ?? 0, bounds.maxX)
        let lowZ = max(outer.map(\.z).min() ?? 0, bounds.minZ), highZ = min(outer.map(\.z).max() ?? 0, bounds.maxZ)
        guard lowX < highX, lowZ < highZ else { return }
        let color = Map3DPalette.cover(area.cover), paint: Map3DPaint? = area.cover == .water ? nil : Self.grass
        let lift = Self.lift(of: area.cover)
        let cellArea = Double(Land.cellLength) * Double(Land.cellLength) / (Self.metre * Self.metre)
        let takes = area.cover == .water || area.cover == .park || area.cover == .wood
        for row in gridCell(lowZ, origin: originY)...gridCell(highZ, origin: originY) {
            let top = max(gridLine(row, origin: originY), bounds.minZ), bottom = min(gridLine(row + 1, origin: originY), bounds.maxZ)
            guard top < bottom else { continue }
            let bandRings = Self.clipRings(area.rings, by: [{ $0.z - top }, { bottom - $0.z }])
            guard bandRings.first?.isEmpty == false else { continue }
            for column in gridCell(lowX, origin: originX)...gridCell(highX, origin: originX) {
                let left = max(gridLine(column, origin: originX), bounds.minX), right = min(gridLine(column + 1, origin: originX), bounds.maxX)
                guard left < right else { continue }
                let cellRings = Self.clipRings(bandRings, by: [{ $0.x - left }, { right - $0.x }])
                guard cellRings.first?.isEmpty == false else { continue }
                // The cell's two triangles: from its north-west corner to
                // its south-east one, as addGround() splits it.
                let westX = gridLine(column, origin: originX), northZ = gridLine(row, origin: originY)
                var covered = 0.0
                for side in [1.0, -1.0] {
                    let piece = Self.clipRings(cellRings, by: [{ side * (($0.z - northZ) - ($0.x - westX)) }])
                    guard let ring = piece.first, ring.count >= 3 else { continue }
                    // A hole as big as what is left of the outer ring
                    // (the base map's sea, its holes the land, over a
                    // tile inland) leaves nothing.
                    let net = abs(Self.area(ring)) - piece.dropFirst().reduce(0) { $0 + abs(Self.area($1)) }
                    guard net > 0.5 else { continue }
                    covered += net
                    let flat = piece.map { $0.map { (x: $0.x, y: $0.z) } }
                    var triangles = Earcut.triangulate(flat)
                    guard !triangles.isEmpty else { continue }
                    var points: [Map3DPoint] = []
                    for ring in piece {
                        for point in ring {
                            let x = Float(point.x), z = Float(point.z)
                            points.append(Map3DPoint(x, drawnGround(x: x, z: z) + lift, z))
                        }
                    }
                    // Decision 375: none of it over a trench.
                    (points, triangles) = outsideTrenches(points, triangles: triangles, lift: lift)
                    guard !triangles.isEmpty else { continue }
                    let middle = Map3DPoint(Float((westX + gridLine(column + 1, origin: originX)) / 2), 0,
                                            Float((northZ + gridLine(row + 1, origin: originY)) / 2))
                    mesh(at: middle) {
                        let start = $0.vertices.count
                        $0.addFlat(points, triangles: triangles, color: color, paint: paint)
                        // Decision 356: water mirrors the sky.
                        if area.cover == .water { $0.makeWater(from: start) }
                    }
                }
                if takes && covered > cellArea / 2 {
                    taken.insert(Map3DScene.ChunkKey(column: column, row: row))
                }
                // Decision 407: where the railway crosses water on a truss.
                if area.cover == .water && covered > 0 {
                    waterCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(cellRings)
                }
            }
        }
    }

    /// `rings` cut by each half-plane of `keeps` in turn (Sutherland and
    /// Hodgman): a point is kept where every one is at least 0. An outer
    /// ring cut away leaves nothing; a hole cut away is dropped.
    static func clipRings(_ rings: [[Map3DBaseMap.Point]], by keeps: [(Map3DBaseMap.Point) -> Double]) -> [[Map3DBaseMap.Point]] {
        var result: [[Map3DBaseMap.Point]] = []
        for (index, ring) in rings.enumerated() {
            var clipped = ring
            for keep in keeps {
                clipped = clip(clipped, keep)
                if clipped.count < 3 { break }
            }
            if clipped.count < 3 || abs(area(clipped)) < 0.01 {
                if index == 0 { return [] }
                continue
            }
            result.append(clipped)
        }
        return result
    }

    static func clip(_ ring: [Map3DBaseMap.Point], _ keep: (Map3DBaseMap.Point) -> Double) -> [Map3DBaseMap.Point] {
        guard var previous = ring.last else { return [] }
        var out: [Map3DBaseMap.Point] = []
        out.reserveCapacity(ring.count + 4)
        var previousSide = keep(previous)
        for point in ring {
            let side = keep(point)
            if (side >= 0) != (previousSide >= 0) {
                let t = previousSide / (previousSide - side)
                out.append(Map3DBaseMap.Point(x: previous.x + (point.x - previous.x) * t, z: previous.z + (point.z - previous.z) * t))
            }
            if side >= 0 { out.append(point) }
            previous = point
            previousSide = side
        }
        return out
    }

    static func area(_ ring: [Map3DBaseMap.Point]) -> Double {
        guard var previous = ring.last else { return 0 }
        var sum = 0.0
        for point in ring {
            sum += previous.x * point.z - point.x * previous.z
            previous = point
        }
        return sum / 2
    }

    // MARK: Strips

    /// A strip `width` metres wide along `points`, kept to `bounds`, `lift`
    /// over the drawn ground: each segment split where it crosses the
    /// ground's grid and its triangles' diagonals, and drawn a half width
    /// past its ends so bends close. Decision 391: a `raised` strip (a
    /// road's) on a bridge's ramps at their height, and `onDeck` (a
    /// bridge's) on its deck too, split every ``raisedStep`` metres near
    /// one.
    mutating func addStrip(_ points: [Map3DBaseMap.Point], bounds: Map3DBaseMap.Bounds, width: Float, lift: Float, color: UInt32,
                           paint: Map3DPaint?, water: Bool = false, raised: Bool = false, onDeck: Bool = false,
                           taking taken: inout Set<Map3DScene.ChunkKey>) {
        let half = Double(width) / 2
        for index in 1..<points.count {
            guard let (start, end) = Self.clipSegment(points[index - 1], points[index], to: bounds) else { continue }
            let dx = end.x - start.x, dz = end.z - start.z
            let length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01 else { continue }
            let along = (x: dx / length, z: dz / length)
            // Out a half width past each end, so bends and joins close.
            let first = Map3DBaseMap.Point(x: start.x - along.x * half, z: start.z - along.z * half)
            let last = Map3DBaseMap.Point(x: end.x + along.x * half, z: end.z + along.z * half)
            var cuts = splits(from: first, to: last)
            // Decision 391: a road near a raised one at its height.
            let lifted = raised && nearRaisedRoad(from: first, to: last)
            if raised { cuts = merged(cuts, raisedCuts(from: first, to: last, anchor: points[index - 1], along: along, onDeck: onDeck)) }
            // Decision 375: a road across a trench deep enough bridges it,
            // the whole of this stretch; otherwise it gives way to it.
            let bridges = bridgesTrench(from: first, to: last)
            for step in 1..<cuts.count {
                let t0 = cuts[step - 1], t1 = cuts[step]
                guard t1 - t0 > 1e-6 else { continue }
                let a = Map3DBaseMap.Point(x: first.x + (last.x - first.x) * t0, z: first.z + (last.z - first.z) * t0)
                let b = Map3DBaseMap.Point(x: first.x + (last.x - first.x) * t1, z: first.z + (last.z - first.z) * t1)
                // Decision 391: each end at the road's height over the
                // ground there.
                let level: (rise: Float, onBridge: Bool) = (0, false)
                let riseA = lifted ? roadRise(at: a, along: along, onDeck: onDeck) : level,
                    riseB = lifted ? roadRise(at: b, along: along, onDeck: onDeck) : level
                // Left of the way along is (z, −x) in x east, z south.
                let leftX = along.z * half, leftZ = -along.x * half
                var corners = [
                    (a.x + leftX, a.z + leftZ, riseA.rise), (a.x - leftX, a.z - leftZ, riseA.rise),
                    (b.x - leftX, b.z - leftZ, riseB.rise), (b.x + leftX, b.z + leftZ, riseB.rise),
                ].map { corner -> Map3DPoint in
                    let x = Float(corner.0), z = Float(corner.1)
                    return Map3DPoint(x, drawnGround(x: x, z: z) + lift + corner.2, z)
                }
                var triangles = [0, 1, 2, 0, 2, 3]
                let middle = Map3DPoint(Float((a.x + b.x) / 2), 0, Float((a.z + b.z) / 2))
                // Decision 391: a bridge's deck is over any trench, and so
                // is a road a metre or more over the ground (續篇二: a road
                // lifted over a cutting, onto its deck).
                if !bridges && !(riseA.onBridge && riseB.onBridge) && min(riseA.rise, riseB.rise) < 1 {
                    (corners, triangles) = outsideTrenches(corners, triangles: triangles, lift: lift)
                }
                mesh(at: middle) {
                    let start = $0.vertices.count
                    $0.addFlat(corners, triangles: triangles, color: color, paint: paint)
                    if water { $0.makeWater(from: start) }
                }
                take(from: a, to: b, half: half, into: &taken)
            }
        }
    }

    /// Decision 391: how finely a road near a raised one is laid, metres,
    /// so its ramps keep their grade.
    static let raisedStep: Double = 4

    /// `cuts` and `extra` (fractions of the way, from 0 to 1) in order,
    /// each once.
    func merged(_ cuts: [Double], _ extra: [Double]) -> [Double] {
        guard !extra.isEmpty else { return cuts }
        var kept: [Double] = []
        for cut in (cuts + extra).sorted() where kept.last.map({ cut - $0 > 1e-9 }) ?? true {
            kept.append(cut)
        }
        return kept
    }

    /// Where the way from `first` to `last`, along `along` on the line
    /// through `anchor`, is cut near a raised road, as fractions of it:
    /// on the ``raisedStep`` metres from `anchor`, where its rise over the
    /// ground (`onDeck` as ``roadRise(at:along:onDeck:)``) bends, seen a
    /// step, four or sixteen either side (``Map3DScene/Builder/bends(_:)``);
    /// the ground's own bends are its grid's cuts. Measured from the line,
    /// not the way, which a tile or a chunk cuts short, so a chunk built
    /// apart cuts it where the whole scene does.
    mutating func raisedCuts(from first: Map3DBaseMap.Point, to last: Map3DBaseMap.Point, anchor: Map3DBaseMap.Point,
                             along: (x: Double, z: Double), onDeck: Bool) -> [Double] {
        guard !roadBridges.isEmpty else { return [] }
        let step = Self.raisedStep
        let start = (first.x - anchor.x) * along.x + (first.z - anchor.z) * along.z
        let end = (last.x - anchor.x) * along.x + (last.z - anchor.z) * along.z
        guard end - start > 1e-9 else { return [] }
        func at(_ distance: Double) -> Map3DBaseMap.Point {
            Map3DBaseMap.Point(x: anchor.x + along.x * distance, z: anchor.z + along.z * distance)
        }
        let reach = Double(Self.bendScales.last!) * step
        guard nearRaisedRoad(from: at(start - reach), to: at(end + reach)) else { return [] }
        // The rise on each step's multiple, worked out once.
        var rises: [Int: Float] = [:]
        func rise(_ number: Int) -> Float {
            if let known = rises[number] { return known }
            let found = roadRise(at: at(Double(number) * step), along: along, onDeck: onDeck).rise
            rises[number] = found
            return found
        }
        var cuts: [Double] = []
        var number = Int((start / step).rounded(.up))
        while Double(number) * step < end {
            defer { number += 1 }
            let distance = Double(number) * step
            guard distance > start else { continue }
            let bent = Self.bendScales.contains { scale in
                number % scale == 0 && Self.bends([rise(number - scale), rise(number), rise(number + scale)])
            }
            if bent { cuts.append((distance - start) / (end - start)) }
        }
        return cuts
    }

    /// Decision 391: the steps a raised road's bends are looked for over,
    /// in ``raisedStep``s: a step, four and sixteen, each on its own
    /// multiples, so a long gentle bend is cut at most 64 m apart and a
    /// level stretch not at all.
    static let bendScales = [1, 4, 16]

    /// Whether the middle of three heights an even step apart lies off the
    /// line through the other two by more than 1 cm.
    static func bends(_ heights: [Float]) -> Bool {
        abs(heights[1] - (heights[0] + heights[2]) / 2) > 0.01
    }

    /// Where the segment from `a` to `b` crosses the ground's grid lines
    /// and its triangles' diagonals, as fractions of the way, with 0 and 1.
    func splits(from a: Map3DBaseMap.Point, to b: Map3DBaseMap.Point) -> [Double] {
        var cuts: [Double] = [0, 1]
        let cell = Double(Land.cellLength) / Self.metre
        // In world metres, where the grid lines fall on whole cells.
        let ax = (originX / Self.metre) + a.x, az = (originY / Self.metre) + a.z
        let bx = (originX / Self.metre) + b.x, bz = (originY / Self.metre) + b.z
        func crossings(_ from: Double, _ to: Double) {
            guard from != to else { return }
            let low = (min(from, to) / cell).rounded(.up), high = (max(from, to) / cell).rounded(.down)
            guard low <= high else { return }
            for line in stride(from: low, through: high, by: 1) {
                cuts.append((line * cell - from) / (to - from))
            }
        }
        crossings(ax, bx)
        crossings(az, bz)
        // The diagonals: x − z on a whole number of cells.
        crossings(ax - az, bx - bz)
        var kept: [Double] = []
        for cut in cuts.filter({ $0 >= 0 && $0 <= 1 }).sorted() where kept.last.map({ cut - $0 > 1e-9 }) ?? true {
            kept.append(cut)
        }
        return kept
    }

    /// Marks the cells whose lot the strip from `a` to `b`, `half` metres
    /// each side, reaches.
    func take(from a: Map3DBaseMap.Point, to b: Map3DBaseMap.Point, half: Double, into taken: inout Set<Map3DScene.ChunkKey>) {
        let length = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
        let steps = max(1, Int((length / 4).rounded(.up)))
        let reach = Double(Self.lotReach) + half
        let cell = Double(Land.cellLength) / Self.metre
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t
            let worldX = originX / Self.metre + x, worldZ = originY / Self.metre + z
            let column = Int((worldX / cell).rounded(.down)), row = Int((worldZ / cell).rounded(.down))
            // This cell and its neighbours, whose lots a wide road can reach.
            for dr in -1...1 {
                for dc in -1...1 {
                    let middleX = (Double(column + dc) + 0.5) * cell, middleZ = (Double(row + dr) + 0.5) * cell
                    if abs(worldX - middleX) < reach && abs(worldZ - middleZ) < reach {
                        taken.insert(Map3DScene.ChunkKey(column: column + dc, row: row + dr))
                    }
                }
            }
        }
    }

    /// The part of the segment from `a` to `b` inside `bounds` (Liang and
    /// Barsky), or `nil` when none is.
    static func clipSegment(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point, to bounds: Map3DBaseMap.Bounds)
        -> (Map3DBaseMap.Point, Map3DBaseMap.Point)? {
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dz = b.z - a.z
        for (p, q) in [(-dx, a.x - bounds.minX), (dx, bounds.maxX - a.x), (-dz, a.z - bounds.minZ), (dz, bounds.maxZ - a.z)] {
            if p == 0 {
                if q < 0 { return nil }
                continue
            }
            let r = q / p
            if p < 0 {
                if r > t1 { return nil }
                t0 = max(t0, r)
            } else {
                if r < t0 { return nil }
                t1 = min(t1, r)
            }
        }
        guard t0 < t1 else { return nil }
        return (Map3DBaseMap.Point(x: a.x + dx * t0, z: a.z + dz * t0), Map3DBaseMap.Point(x: a.x + dx * t1, z: a.z + dz * t1))
    }
}

// MARK: - Street furniture (decision 244)

extension Map3DScene.Builder {
    /// What stands along a road of a kind, and how: a prop every `spacing`
    /// metres, `offset` metres out from the road's middle (on both sides,
    /// or on alternate sides), as Taiwan's streets have them.
    struct PropRule {
        let prop: Map3DProp
        let spacing: Double
        let bothSides: Bool
        let offset: (Double) -> Double
    }

    static func propRules(_ kind: Map3DBaseMap.RoadKind) -> [PropRule] {
        let sidewalk = Double(Self.sidewalk(of: kind))
        switch kind {
        case .trunk, .primary, .secondary:
            return [PropRule(prop: .tree, spacing: 14, bothSides: true) { $0 / 2 + sidewalk * 0.6 },
                    PropRule(prop: .lamp, spacing: 36, bothSides: false) { $0 / 2 + 0.5 }]
        case .tertiary:
            return [PropRule(prop: .lamp, spacing: 36, bothSides: false) { $0 / 2 + 0.5 }]
        case .minor:
            return [PropRule(prop: .pole, spacing: 38, bothSides: false) { $0 / 2 + 0.6 }]
        case .motorway, .service:
            return []
        }
    }

    /// The pools of the street lights' light on the ground under their
    /// heads, seen as much as the city's lights are on
    /// (``Map3DMesh/addPool``): after the lights on the track are gone.
    mutating func addLampPools() {
        guard let lamp = Self.propModels[.lamp] else { return }
        for key in props.keys.sorted() {
            for instance in props[key] ?? [] where instance.model == lamp {
                addLampPool(instance)
            }
        }
    }

    private mutating func addLampPool(_ instance: Map3DInstance) {
        let t = instance.transform
        let foot = Map3DPoint(t[12], t[13], t[14])
        // The model's +y is the light's left, where its arm reaches
        // (`Map3DInstance.prop`).
        guard let left = Map3DPoint(t[4], 0, t[6]).normalized else { return }
        let under = foot + left * Map3DProp.lampReach
        let ring = Map3DProp.poolRing.map { under + $0 * Self.lampPoolRadius }
        shadows[key(of: foot), default: Map3DMesh()].addPool(centre: onGround([under])[0], ring: onGround(ring), colour: Map3DProp.lampLight,
                                                              strength: Self.lampPoolStrength)
    }

    /// How far a street light's pool reaches, in metres, and how strong it
    /// is at its middle (`Web/CityView/src/world/lamplight.js`'s street
    /// lamps light about a lamp's height round them).
    static let lampPoolRadius: Float = 9
    static let lampPoolStrength: Float = 0.55

    /// The models' places in ``Map3DModelPack/standard``.
    static let propModels: [Map3DProp: Int] = Dictionary(uniqueKeysWithValues: Map3DProp.allCases.compactMap { prop in
        Map3DModelPack.standard.index(of: prop.modelName).map { (prop, $0) }
    })

    /// Trees, lights and poles along `map`'s roads (not on ramps, nor
    /// within 9 m of a junction, where they would stand in the other
    /// road), each tile's share on its own ground, the same every time.
    mutating func addStreetProps(_ roads: [Map3DBaseMap.Road]) {
        let junctions = Self.junctions(of: roads)
        func nearJunction(_ x: Double, _ z: Double) -> Bool {
            let column = Int((x / 32).rounded(.down)), row = Int((z / 32).rounded(.down))
            for dr in -1...1 {
                for dc in -1...1 {
                    for point in junctions[Self.junctionKey(column + dc, row + dr)] ?? [] where (point.x - x) * (point.x - x) + (point.z - z) * (point.z - z) < 81 {
                        return true
                    }
                }
            }
            return false
        }
        let east = originX / Double(WorldCoordinate.unitsPerMetre), south = originY / Double(WorldCoordinate.unitsPerMetre)
        for road in roads where !road.isRamp && road.points.count >= 2 {
            let rules = Self.propRules(road.kind)
            guard !rules.isEmpty else { continue }
            let width = Double(road.kind.width(ramp: false))
            let start = road.points[0]
            // Seeded from the map, not the scene, whose origin moves as
            // track is laid (as a real building is).
            let phase = Double(map3DRandom(Int32(truncatingIfNeeded: Int((start.x + east).rounded())),
                                           Int32(truncatingIfNeeded: Int((start.z + south).rounded())), salt: 70))
            var travelled = 0.0
            for index in 1..<road.points.count {
                let a = road.points[index - 1], b = road.points[index]
                let dx = b.x - a.x, dz = b.z - a.z
                let length = (dx * dx + dz * dz).squareRoot()
                defer { travelled += length }
                guard length > 0.01 else { continue }
                let along = (x: dx / length, z: dz / length)
                // Left of the way along is (z, −x) in x east, z south.
                let left = (x: along.z, z: -along.x)
                for rule in rules {
                    let first = phase * rule.spacing
                    var place = ((travelled - first) / rule.spacing).rounded(.up) * rule.spacing + first
                    while place < travelled + length {
                        defer { place += rule.spacing }
                        let t = place - travelled
                        let centre = (x: a.x + along.x * t, z: a.z + along.z * t)
                        // The tile's own share of the road.
                        guard centre.x >= road.bounds.minX, centre.x < road.bounds.maxX, centre.z >= road.bounds.minZ, centre.z < road.bounds.maxZ
                        else { continue }
                        let number = Int((place / rule.spacing).rounded())
                        for side: Double in rule.bothSides ? [1, -1] : [number % 2 == 0 ? 1 : -1] {
                            let out = rule.offset(width) * side
                            let x = centre.x + left.x * out, z = centre.z + left.z * out
                            let seed = (Int32(truncatingIfNeeded: Int(((x + east) * 2).rounded())), Int32(truncatingIfNeeded: Int(((z + south) * 2).rounded())))
                            // Now and then a gap, as a real street has.
                            guard map3DRandom(seed.0, seed.1, salt: 71) >= (rule.prop == .tree ? 0.18 : 0.08), !nearJunction(x, z),
                                  let model = Self.propModels[rule.prop] else { continue }
                            // Decision 391: none on a bridge or its ramp.
                            guard roadRise(at: Map3DBaseMap.Point(x: centre.x, z: centre.z), along: along, onDeck: road.bridgeLevel > 0).rise < Self.propRise
                            else { continue }
                            let foot = Map3DPoint(Float(x), drawnGround(x: Float(x), z: Float(z)) + Self.sidewalkLift, Float(z))
                            // Its left, where a light's arm reaches, toward the road.
                            let forward = side > 0 ? Map3DPoint(Float(-along.x), 0, Float(-along.z)) : Map3DPoint(Float(along.x), 0, Float(along.z))
                            let scale: Float = rule.prop == .tree ? 0.8 + 0.45 * map3DRandom(seed.0, seed.1, salt: 72) : 1
                            let tint = rule.prop == .tree ? Self.pick(Map3DProp.greens, map3DRandom(seed.0, seed.1, salt: 73)) : Map3DColor.rgb(0xFFFFFF)
                            props[key(of: foot), default: []].append(.prop(model, at: foot, forward: forward, scale: scale, tint: tint))
                        }
                    }
                }
            }
        }
    }

    /// The road points two or more roads share (the junctions), by 32 m
    /// square.
    static func junctions(of roads: [Map3DBaseMap.Road]) -> [Int64: [Map3DBaseMap.Point]] {
        var counts: [Int64: (point: Map3DBaseMap.Point, roads: Int)] = [:]
        for road in roads {
            var seen = Set<Int64>()
            for point in road.points {
                let key = Int64((point.x * 2).rounded()) << 32 ^ Int64((point.z * 2).rounded()) & 0xFFFF_FFFF
                guard seen.insert(key).inserted else { continue }
                counts[key, default: (point, 0)].roads += 1
            }
        }
        var squares: [Int64: [Map3DBaseMap.Point]] = [:]
        for (_, entry) in counts where entry.roads >= 2 {
            squares[junctionKey(Int((entry.point.x / 32).rounded(.down)), Int((entry.point.z / 32).rounded(.down))), default: []].append(entry.point)
        }
        return squares
    }

    static func junctionKey(_ column: Int, _ row: Int) -> Int64 {
        Int64(column) << 32 ^ (Int64(row) & 0xFFFF_FFFF)
    }

    /// No street furniture on the 64 m cells in `cleared` (the track's).
    mutating func removeProps(on cleared: Set<Map3DScene.ChunkKey>) {
        guard !cleared.isEmpty else { return }
        for (key, instances) in props {
            props[key] = instances.filter { instance in
                let x = Double(instance.transform[12]), z = Double(instance.transform[14])
                return !cleared.contains(Map3DScene.ChunkKey(column: gridCell(x, origin: originX), row: gridCell(z, origin: originY)))
            }
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 407: whether scene point `p` is over the base map's water
    /// (its areas, not the narrow waterways' lines): inside an odd number
    /// of one area's rings in its cell.
    func isOverWater(_ p: Map3DPoint) -> Bool {
        guard let areas = waterCells[Map3DScene.ChunkKey(column: gridCell(Double(p.x), origin: originX), row: gridCell(Double(p.z), origin: originY))]
        else { return false }
        let x = Double(p.x), z = Double(p.z)
        return areas.contains { rings in
            var inside = false
            for ring in rings {
                var j = ring.count - 1
                for i in ring.indices {
                    let a = ring[i], b = ring[j]
                    if (a.z > z) != (b.z > z), x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
                    j = i
                }
            }
            return inside
        }
    }
}
