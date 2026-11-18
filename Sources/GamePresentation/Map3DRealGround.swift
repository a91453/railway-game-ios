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

    /// Decision 822: what a river's or a lake's island is drawn as, and
    /// how high, under every cover (``lift(of:)``'s least).
    static let islandCover = Map3DBaseMap.Cover.grass
    static let islandLift: Float = 0.0175

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
        // Decision 865: its roads' beds, before anything is laid on them.
        roadBed = roadBed(of: map)
        // Decision 391: its bridges' decks, before the roads on them.
        roadBridges = bridgeDecks(of: map, frame: RealWorldFrame(world: world))
        // Decision 822: a river's or a lake's islands (its holes) under
        // every cover, so one the tiles give no cover of its own is no
        // bare ground in the water (IMG_5324's grey strips).
        for area in map.areas where area.cover == .water && !area.isSea {
            for island in area.rings.dropFirst() where island.count >= 3 {
                addArea(Map3DBaseMap.Area(cover: Self.islandCover, rings: [island], bounds: area.bounds), lift: Self.islandLift,
                        taking: &taken.whole)
            }
        }
        for cover in Map3DBaseMap.Cover.allCases {
            for area in map.areas where area.cover == cover {
                addArea(area, taking: &taken.whole)
            }
        }
        mark("land cover and water")
        for waterway in map.waterways {
            addStrip(waterway.points, bounds: waterway.bounds, width: waterway.kind.width,
                     lift: Self.lift(of: .water), color: Map3DPalette.water, paint: nil, water: true, taking: &taken.whole)
        }
        mark("land cover and water")
        addRoads(map.roads, taking: &taken.byRoads)
        // Decision 709: what carries the bridges, under their decks.
        sizing = Map3DFarDetail.bridgeStructure
        addRoadBridges(map.roads)
        // Decision 865: and the walls under their beds.
        addRoadBedWalls(map.roads)
        sizing = nil
        // Decision 611: where the roads go into a hill.
        addRoadTunnels(map.tunnelEnds, areas: map.areas)
        mark("road bridges and tunnels")
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
        sizing = Map3DFarDetail.sidewalks
        for road in roads where Self.sidewalk(of: road.kind) > 0 && !road.isRamp {
            addStrip(road.points, bounds: road.bounds, width: road.kind.width(ramp: false) + 2 * Self.sidewalk(of: road.kind),
                     lift: Self.sidewalkLift, color: look.streets.sidewalk, paint: Self.paving, raised: true, onDeck: road.bridgeLevel > 0,
                     taking: &taken)
        }
        mark("sidewalks")
        for kind in Map3DBaseMap.RoadKind.allCases {
            let size = Map3DFarDetail.size(of: kind)
            sizing = size.isFinite ? size : nil
            for road in roads where road.kind == kind {
                addStrip(road.points, bounds: road.bounds, width: kind.width(ramp: road.isRamp), lift: Self.lift(of: kind),
                         color: Map3DPalette.road(kind), paint: nil, raised: true, onDeck: road.bridgeLevel > 0,
                         roadCuts: kind != .motorway, taking: &taken)
            }
        }
        // Decision 355: the paint at the junctions, the centre lines
        // stopping at their crossings.
        // Decision 429: the junctions where they are in the world, for
        // their signals' offsets.
        mark("roads")
        // Decision 732: whose roads they are, Hong Kong's on its map.
        let streets = look.streets
        let markings = Map3DRoadMarkings(roads, origin: Map3DBaseMap.Point(x: originX / Double(WorldCoordinate.unitsPerMetre),
                                                                           z: originY / Double(WorldCoordinate.unitsPerMetre)),
                                         region: streets)
        var lines = Set<Map3DScene.ChunkKey>()
        sizing = Map3DFarDetail.centreLines
        // Decision 732: Hong Kong's centre lines white.
        let centreLine = streets.hasYellowCentreLines ? Map3DPalette.centreLine : Self.paint
        for (number, road) in roads.enumerated() where Self.hasCentreLine(road) {
            for piece in markings.centreLines(of: road, number: number) {
                addStrip(piece, bounds: road.bounds, width: 0.3, lift: Self.centreLineLift, color: centreLine, paint: nil,
                         raised: true, onDeck: road.bridgeLevel > 0, taking: &lines)
            }
        }
        mark("centre lines")
        sizing = Map3DFarDetail.roadMarkings
        addRoadMarkings(markings)
        sizing = nil
        mark("road markings")
        addStreetProps(roads)
        addStreetStops(roads, markings: markings)
        mark("street furniture")
        // Decision 259: their traffic and their pavements' people.
        // Decision 596: waiting at their signals.
        for road in roads where road.points.count >= 2 { addStreetLife(road, markings: markings) }
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
    mutating func addArea(_ area: Map3DBaseMap.Area, lift drawnLift: Float? = nil, taking taken: inout Set<Map3DScene.ChunkKey>) {
        guard let outer = area.rings.first else { return }
        let bounds = area.bounds
        let lowX = max(outer.map(\.x).min() ?? 0, bounds.minX), highX = min(outer.map(\.x).max() ?? 0, bounds.maxX)
        let lowZ = max(outer.map(\.z).min() ?? 0, bounds.minZ), highZ = min(outer.map(\.z).max() ?? 0, bounds.maxZ)
        guard lowX < highX, lowZ < highZ else { return }
        let color = Map3DPalette.cover(area.cover), paint: Map3DPaint? = area.cover == .water ? nil : Self.grass
        let lift = drawnLift ?? Self.lift(of: area.cover)
        let cellArea = Double(Land.cellLength) * Double(Land.cellLength) / (Self.metre * Self.metre)
        let takes = area.cover == .water || area.cover == .park || area.cover == .wood
        // Decision 822: the area's triangles, cut once with its holes, each
        // then cut to the cells' triangles below. Cutting the outline and
        // its holes to a cell's triangle first, then triangulating, failed
        // where a hole (a river's island) reached the triangle's edge: the
        // whole triangle came out water (the owner's IMG_5325, sharp
        // triangles of water over the Tamsui's islands).
        // Only an area with holes needs it; a cell's half no hole reaches
        // is triangulated as before, with fewer triangles.
        let corners = area.rings.count > 1 ? area.rings.flatMap { $0 } : []
        let whole = area.rings.count > 1 ? Earcut.triangulate(area.rings.map { $0.map { (x: $0.x, y: $0.z) } }) : []
        var byCell: [Map3DScene.ChunkKey: [Int]] = [:]
        for first in stride(from: 0, to: whole.count - 2, by: 3) {
            let triangle = (0..<3).map { corners[whole[first + $0]] }
            let xs = triangle.map(\.x), zs = triangle.map(\.z)
            guard let minX = xs.min(), let maxX = xs.max(), let minZ = zs.min(), let maxZ = zs.max(),
                  maxX > lowX, minX < highX, maxZ > lowZ, minZ < highZ else { continue }
            for row in gridCell(max(minZ, lowZ), origin: originY)...gridCell(min(maxZ, highZ), origin: originY) {
                for column in gridCell(max(minX, lowX), origin: originX)...gridCell(min(maxX, highX), origin: originX) {
                    byCell[Map3DScene.ChunkKey(column: column, row: row), default: []].append(first)
                }
            }
        }
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
                let mine = byCell[Map3DScene.ChunkKey(column: column, row: row)] ?? []
                for side in [1.0, -1.0] {
                    let diagonal: (Map3DBaseMap.Point) -> Double = { side * (($0.z - northZ) - ($0.x - westX)) }
                    let half = Self.clipRings(cellRings, by: [diagonal])
                    guard let outline = half.first, outline.count >= 3 else { continue }
                    var points: [Map3DPoint] = []
                    var triangles: [Int] = []
                    if half.count == 1 {
                        // No hole reaches this half: its outline,
                        // triangulated.
                        let net = abs(Self.area(outline))
                        guard net > 0.5 else { continue }
                        triangles = Earcut.triangulate([outline.map { (x: $0.x, y: $0.z) }])
                        guard !triangles.isEmpty else { continue }
                        covered += net
                        for point in outline {
                            let x = Float(point.x), z = Float(point.z)
                            points.append(Map3DPoint(x, drawnGround(x: x, z: z) + lift, z))
                        }
                    } else {
                        // Decision 822: where a hole reaches, each of the
                        // area's triangles cut to this half of the cell, a
                        // convex cut.
                        let keeps: [(Map3DBaseMap.Point) -> Double] = [
                            { $0.z - top }, { bottom - $0.z }, { $0.x - left }, { right - $0.x },
                            diagonal,
                        ]
                        var pieces: [[Map3DBaseMap.Point]] = []
                        var net = 0.0
                        for first in mine {
                            var piece = (0..<3).map { corners[whole[first + $0]] }
                            for keep in keeps {
                                piece = Self.clip(piece, keep)
                                if piece.count < 3 { break }
                            }
                            guard piece.count >= 3 else { continue }
                            let size = abs(Self.area(piece))
                            guard size > 1e-4 else { continue }
                            net += size
                            pieces.append(piece)
                        }
                        // Slivers along a cell's edge (the base map's sea, its
                        // holes the land, over a tile inland) leave nothing.
                        guard net > 0.5 else { continue }
                        covered += net
                        for piece in pieces {
                            let start = points.count
                            for point in piece {
                                let x = Float(point.x), z = Float(point.z)
                                points.append(Map3DPoint(x, drawnGround(x: x, z: z) + lift, z))
                            }
                            for index in 1..<(piece.count - 1) { triangles += [start, start + index, start + index + 1] }
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
                // Decision 458: where the conifers and bushes may stand.
                if area.cover == .wood && covered > 0 {
                    woodCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(cellRings)
                }
                if area.cover == .grass && covered > 0 {
                    grassCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(cellRings)
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
    /// ground's grid and its triangles' diagonals. Decision 391: a `raised`
    /// strip (a road's) on a bridge's ramps at their height, and `onDeck`
    /// (a bridge's) on its deck too, split every ``raisedStep`` metres near
    /// one. ROAD-STRIP-WEDGE: where it bends it stops at the bend, closed by
    /// a join there (``addStripJoin``); at its own ends, and at a bend too
    /// slight to join, it runs on a half width so it meets the next way,
    /// past its own ends at their height.
    mutating func addStrip(_ points: [Map3DBaseMap.Point], bounds: Map3DBaseMap.Bounds, width: Float, lift: Float, color: UInt32,
                           paint: Map3DPaint?, water: Bool = false, raised: Bool = false, onDeck: Bool = false, roadCuts: Bool = true,
                           taking taken: inout Set<Map3DScene.ChunkKey>) {
        guard points.count >= 2 else { return }
        let half = Double(width) / 2
        // Each segment kept to `bounds`, and whether it reaches its own
        // first and last points.
        typealias Laid = (start: Map3DBaseMap.Point, end: Map3DBaseMap.Point, along: (x: Double, z: Double), length: Double,
                          fromFirst: Bool, toLast: Bool)
        let laid: [Laid?] = (1..<points.count).map { index in
            guard let (start, end) = Self.clipSegment(points[index - 1], points[index], to: bounds) else { return nil }
            let dx = end.x - start.x, dz = end.z - start.z
            let length = (dx * dx + dz * dz).squareRoot()
            guard length > 0.01 else { return nil }
            func same(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> Bool { abs(a.x - b.x) < 1e-6 && abs(a.z - b.z) < 1e-6 }
            return (start, end, (dx / length, dz / length), length, same(start, points[index - 1]), same(end, points[index]))
        }
        // ROAD-STRIP-WEDGE: the points where both segments reach and bend.
        let joined: [Bool] = (0..<points.count).map { vertex in
            guard vertex > 0, vertex < points.count - 1, let before = laid[vertex - 1], let after = laid[vertex],
                  before.toLast, after.fromFirst else { return false }
            return before.along.x * after.along.x + before.along.z * after.along.z < Self.joinedBend
        }
        var bridged: [Bool] = Array(repeating: false, count: laid.count)
        for index in 1..<points.count {
            guard let segment = laid[index - 1] else { continue }
            let (start, end, along, length) = (segment.start, segment.end, segment.along, segment.length)
            // Out a half width past each end, so the ways meeting there
            // close; none where it bends, which its join closes.
            let back = joined[index - 1] ? 0 : half, forth = joined[index] ? 0 : half
            let first = Map3DBaseMap.Point(x: start.x - along.x * back, z: start.z - along.z * back)
            let last = Map3DBaseMap.Point(x: end.x + along.x * forth, z: end.z + along.z * forth)
            var cuts = splits(from: first, to: last)
            // Decision 865: a road on its bed, cut where the bed bends.
            let bedded = raised && !roadBed.isEmpty
            if bedded { cuts = merged(cuts, bedCuts(from: first, to: last, along: along, onDeck: onDeck)) }
            // Decision 391: a road near a raised one at its height.
            let lifted = raised && nearRaisedRoad(from: first, to: last)
            if raised { cuts = merged(cuts, raisedCuts(from: first, to: last, anchor: points[index - 1], along: along, onDeck: onDeck)) }
            // ROAD-STRIP-WEDGE: past the way's own first and last points
            // (where another way may go on, or nothing), at the end's
            // height, going on at the end's own grade only where the
            // ground there is as high: under a deck the way ends beside,
            // the rise there is the ground's, a wedge down to it.
            let whole = length + back + forth
            // Near a raised road by the end itself, not the segment, which a
            // region cuts short.
            func nearEnd(_ end: Map3DBaseMap.Point) -> Bool {
                raised && nearRaisedRoad(from: Map3DBaseMap.Point(x: end.x - half, z: end.z - half),
                                         to: Map3DBaseMap.Point(x: end.x + half, z: end.z + half))
            }
            let capsFirst = index == 1 && segment.fromFirst && back > 0 && nearEnd(start)
            let capsLast = index == points.count - 1 && segment.toLast && forth > 0 && nearEnd(end)
            // Each at its own end only, so a segment a region cuts short
            // elsewhere is cut where the whole scene cuts it.
            if capsFirst { cuts = merged(cuts, [back / whole]) }
            if capsLast { cuts = merged(cuts, [1 - forth / whole]) }
            func cap(at end: Map3DBaseMap.Point, outward: (x: Double, z: Double)) -> (out: Float, end: Float, onBridge: Bool) {
                let atEnd = roadRise(at: end, along: along, onDeck: onDeck)
                let inward = min(half, length)
                let behind = roadRise(at: Map3DBaseMap.Point(x: end.x - outward.x * inward, z: end.z - outward.z * inward),
                                      along: along, onDeck: onDeck).rise
                let past = roadRise(at: Map3DBaseMap.Point(x: end.x + outward.x * half, z: end.z + outward.z * half),
                                    along: along, onDeck: onDeck).rise
                let graded = atEnd.rise + (atEnd.rise - behind) * Float(half / inward)
                return (min(graded, max(past, atEnd.rise)), atEnd.rise, atEnd.onBridge)
            }
            let firstCap = capsFirst ? cap(at: start, outward: (-along.x, -along.z)) : nil
            let lastCap = capsLast ? cap(at: end, outward: along) : nil
            // Decision 391: a road's rise over the ground at `t` of the way.
            func rise(_ t: Double, _ p: Map3DBaseMap.Point) -> (rise: Float, onBridge: Bool) {
                if let firstCap, t * whole < back - 1e-9 {
                    let share = Float(t * whole / back)
                    return (firstCap.out + (firstCap.end - firstCap.out) * share, firstCap.onBridge)
                }
                if let lastCap, (1 - t) * whole < forth - 1e-9 {
                    let share = Float((1 - t) * whole / forth)
                    return (lastCap.out + (lastCap.end - lastCap.out) * share, lastCap.onBridge)
                }
                return lifted ? roadRise(at: p, along: along, onDeck: onDeck) : (0, false)
            }
            // Decision 375: a road across a trench deep enough bridges it,
            // the whole of this stretch; otherwise it gives way to it.
            let bridges = bridgesTrench(from: first, to: last)
            bridged[index - 1] = bridges
            for step in 1..<cuts.count {
                let t0 = cuts[step - 1], t1 = cuts[step]
                guard t1 - t0 > 1e-6 else { continue }
                let a = Map3DBaseMap.Point(x: first.x + (last.x - first.x) * t0, z: first.z + (last.z - first.z) * t0)
                let b = Map3DBaseMap.Point(x: first.x + (last.x - first.x) * t1, z: first.z + (last.z - first.z) * t1)
                // Decision 391: each end at the road's height over the
                // ground there.
                let riseA = rise(t0, a), riseB = rise(t1, b)
                // Left of the way along is (z, −x) in x east, z south.
                let leftX = along.z, leftZ = -along.x
                // RAMP-EDGE-OVERLAP: a bridge's road cut back from where it
                // lies under another one's edge 0.5–4.5 m higher.
                let sideA = onDeck && lifted ? uncovered(a, rise: riseA.rise, along: along, half: half) : (left: half, right: half)
                let sideB = onDeck && lifted ? uncovered(b, rise: riseB.rise, along: along, half: half) : (left: half, right: half)
                guard sideA.left + sideA.right > 0.05 || sideB.left + sideB.right > 0.05 else { continue }
                // Decision 865: both kerbs at its bed's height there; off
                // any bed, each corner on the ground under it.
                let bedA = bedded ? roadBed.level(at: a, along: along, onDeck: onDeck) : nil
                let bedB = bedded ? roadBed.level(at: b, along: along, onDeck: onDeck) : nil
                var corners = [
                    (a.x + leftX * sideA.left, a.z + leftZ * sideA.left, riseA.rise, bedA), (a.x - leftX * sideA.right, a.z - leftZ * sideA.right, riseA.rise, bedA),
                    (b.x - leftX * sideB.right, b.z - leftZ * sideB.right, riseB.rise, bedB), (b.x + leftX * sideB.left, b.z + leftZ * sideB.left, riseB.rise, bedB),
                ].map { corner -> Map3DPoint in
                    let x = Float(corner.0), z = Float(corner.1)
                    return Map3DPoint(x, (corner.3 ?? drawnGround(x: x, z: z)) + lift + corner.2, z)
                }
                var triangles = [0, 1, 2, 0, 2, 3]
                let middle = Map3DPoint(Float((a.x + b.x) / 2), 0, Float((a.z + b.z) / 2))
                // Decision 391: a bridge's deck is over any trench, and so
                // is a road a metre or more over the ground (續篇二: a road
                // lifted over a cutting, onto its deck).
                if !bridges && !(riseA.onBridge && riseB.onBridge) && min(riseA.rise, riseB.rise) < 1 {
                    (corners, triangles) = outsideTrenches(corners, triangles: triangles, lift: lift, roadCuts: roadCuts, level: bedA != nil || bedB != nil)
                }
                mesh(at: middle) {
                    let start = $0.vertices.count
                    $0.addFlat(corners, triangles: triangles, color: color, paint: paint)
                    if water { $0.makeWater(from: start) }
                }
                take(from: a, to: b, half: half, into: &taken)
            }
        }
        for vertex in joined.indices where joined[vertex] {
            guard let before = laid[vertex - 1], let after = laid[vertex] else { continue }
            addStripJoin(at: points[vertex], before: before.along, after: after.along, half: half, lift: lift, color: color,
                         paint: paint, water: water, lifted: raised && nearRaisedRoad(from: points[vertex], to: points[vertex]),
                         onDeck: onDeck, bridges: bridged[vertex - 1] || bridged[vertex], roadCuts: roadCuts, bedded: raised && !roadBed.isEmpty)
        }
    }

    /// RAMP-EDGE-OVERLAP: how far each side of level point `p` (left and
    /// right of `along`) a bridge's road `half` metres wide each side and
    /// `rise` over the ground is drawn: cut back from the side whose edge
    /// lies under another bridge's surface 0.5–4.5 m higher
    /// (``underHigherDeck(_:along:rise:)``) to where it leaves it, to
    /// nothing where all of it does (it is out of sight under the other);
    /// the whole width where neither edge does.
    mutating func uncovered(_ p: Map3DBaseMap.Point, rise: Float, along: (x: Double, z: Double), half: Double) -> (left: Double, right: Double) {
        // Offsets left of the way, from -half (its right edge) to half.
        func covered(_ offset: Double) -> Bool {
            underHigherDeck(Map3DBaseMap.Point(x: p.x + along.z * offset, z: p.z - along.x * offset), along: along, rise: rise)
        }
        let left = covered(half), right = covered(-half)
        guard left || right else { return (half, half) }
        if left && right { return covered(0) ? (0, 0) : (half, half) }
        // From the covered edge in to where it is not: the uncovered side
        // keeps its edge, the other ends there.
        let sign = left ? 1.0 : -1.0
        var inside = -half, outside = half
        guard !covered(-sign * half * 0.999) else { return (0, 0) }
        for _ in 0..<7 {
            let middle = (inside + outside) / 2
            if covered(sign * middle) { outside = middle } else { inside = middle }
        }
        return left ? (inside, half) : (half, inside)
    }

    /// ROAD-STRIP-WEDGE: the cosine of the least bend a strip is joined
    /// at, 1°; under it each segment runs a half width on, sticking out
    /// under a fiftieth of the half width.
    static let joinedBend = 0.999_847_695_156_391_3

    /// ROAD-STRIP-WEDGE (MapLibre's line join, BSD-3, its way only): the
    /// outside of a strip's bend at `joint`, from the segment running
    /// `before` to the one running `after`, `half` metres each side: a
    /// mitre while it reaches at most twice `half` out and the bend is
    /// sharp enough to show it, else a bevel. Cut to the ground's
    /// triangles, at each segment's height over it at the joint.
    mutating func addStripJoin(at joint: Map3DBaseMap.Point, before: (x: Double, z: Double), after: (x: Double, z: Double),
                               half: Double, lift: Float, color: UInt32, paint: Map3DPaint?, water: Bool, lifted: Bool,
                               onDeck: Bool, bridges: Bool, roadCuts: Bool, bedded: Bool = false) {
        typealias Point = Map3DBaseMap.Point
        // The bend's outside: the side whose edge the next segment leaves.
        let left1 = (x: before.z, z: -before.x), left2 = (x: after.z, z: -after.x)
        let sign = left1.x * after.x + left1.z * after.z < 0 ? 1.0 : -1.0
        let n1 = (x: left1.x * sign, z: left1.z * sign), n2 = (x: left2.x * sign, z: left2.z * sign)
        let o1 = Point(x: joint.x + n1.x * half, z: joint.z + n1.z * half), o2 = Point(x: joint.x + n2.x * half, z: joint.z + n2.z * half)
        var outline = [joint, o1, o2]
        let dot = before.x * after.x + before.z * after.z
        let cosHalf = ((1 + dot) / 2).squareRoot()
        if dot <= Self.mitredBend && cosHalf * Self.mitreLimit >= 1 {
            let bx = n1.x + n2.x, bz = n1.z + n2.z, length = (bx * bx + bz * bz).squareRoot()
            let reach = half / cosHalf
            outline = [joint, o1, Point(x: joint.x + bx / length * reach, z: joint.z + bz / length * reach), o2]
        }
        // Each segment's rise at the joint, from one side's edge to the
        // other's.
        var rise1: (rise: Float, onBridge: Bool) = (0, false), rise2 = rise1
        if lifted {
            rise1 = roadRise(at: joint, along: before, onDeck: onDeck)
            rise2 = roadRise(at: joint, along: after, onDeck: onDeck)
        }
        let dx = o2.x - o1.x, dz = o2.z - o1.z, span = dx * dx + dz * dz
        func rise(_ p: Point) -> Float {
            guard span > 1e-12, abs(rise2.rise - rise1.rise) > 1e-4 else { return rise1.rise }
            let share = min(max(((p.x - o1.x) * dx + (p.z - o1.z) * dz) / span, 0), 1)
            return rise1.rise + (rise2.rise - rise1.rise) * Float(share)
        }
        // Cut to the ground's triangles, as addArea() cuts an area.
        let xs = outline.map(\.x), zs = outline.map(\.z)
        var points: [Map3DPoint] = []
        var triangles: [Int] = []
        // Decision 865: on its road's bed, level, in one piece.
        let bed = bedded ? roadBed.level(at: joint, along: before, onDeck: onDeck) : nil
        if let bed {
            points = outline.map { Map3DPoint(Float($0.x), bed + lift + rise($0), Float($0.z)) }
            triangles = Self.fan(outline.count)
        }
        for row in gridCell(zs.min()!, origin: originY)...gridCell(zs.max()!, origin: originY) where bed == nil {
            let top = gridLine(row, origin: originY), bottom = gridLine(row + 1, origin: originY)
            for column in gridCell(xs.min()!, origin: originX)...gridCell(xs.max()!, origin: originX) {
                let westX = gridLine(column, origin: originX), eastX = gridLine(column + 1, origin: originX)
                for side in [1.0, -1.0] {
                    var piece = outline
                    let keeps: [(Point) -> Double] = [
                        { $0.z - top }, { bottom - $0.z }, { $0.x - westX }, { eastX - $0.x },
                        { side * (($0.z - top) - ($0.x - westX)) },
                    ]
                    for keep in keeps {
                        piece = Self.clip(piece, keep)
                        if piece.count < 3 { break }
                    }
                    guard piece.count >= 3, abs(Self.area(piece)) > 1e-6 else { continue }
                    let start = points.count
                    for p in piece {
                        let x = Float(p.x), z = Float(p.z)
                        points.append(Map3DPoint(x, drawnGround(x: x, z: z) + lift + rise(p), z))
                    }
                    for index in 1..<(piece.count - 1) { triangles += [start, start + index, start + index + 1] }
                }
            }
        }
        guard !triangles.isEmpty else { return }
        // Decision 375, as its segments.
        if !bridges && !(rise1.onBridge && rise2.onBridge) && min(rise1.rise, rise2.rise) < 1 {
            (points, triangles) = outsideTrenches(points, triangles: triangles, lift: lift, roadCuts: roadCuts, level: bed != nil)
            guard !triangles.isEmpty else { return }
        }
        // Decision 709: sized as what it adds, its own width across, so
        // the far views leave it out before the road.
        let roadSizing = sizing
        sizing = min(sizing ?? .infinity, Float(2 * half))
        defer { sizing = roadSizing }
        mesh(at: Map3DPoint(Float(joint.x), 0, Float(joint.z))) {
            let start = $0.vertices.count
            $0.addFlat(points, triangles: triangles, color: color, paint: paint)
            if water { $0.makeWater(from: start) }
        }
    }

    /// ROAD-STRIP-WEDGE: the cosine of the least bend mitred rather than
    /// bevelled, 20°: under it the bevel leaves out a sliver under a
    /// twentieth of the half width.
    static let mitredBend = 0.939_692_620_785_908_4

    /// ROAD-STRIP-WEDGE: MapLibre's `line-miter-limit` default: a mitre
    /// reaching more than twice the half width out is bevelled.
    static let mitreLimit = 2.0

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
        guard !roadBridges.isEmpty || !roadGrade.isEmpty else { return [] }
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
        // Decision 846's later note: Finland's street lights too.
        let lamps = Set([Self.propModels[.lamp], Self.finlandModels[.lamp]].compactMap { $0 })
        guard !lamps.isEmpty else { return }
        for key in props.keys.sorted() {
            for instance in props[key] ?? [] where lamps.contains(instance.model) {
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
        // Decision 709: a pool as wide as its light reaches.
        let centre = onGround([under])[0], onGroundRing = onGround(ring)
        shadow(at: key(of: foot), size: 4 * Self.lampPoolRadius) {
            $0.addPool(centre: centre, ring: onGroundRing, colour: Map3DProp.lampLight, strength: Self.lampPoolStrength)
        }
    }

    /// How far a street light's pool reaches, in metres, and how strong it
    /// is at its middle (`Web/CityView/src/world/lamplight.js`'s street
    /// lamps light about a lamp's height round them).
    static let lampPoolRadius: Float = 9
    static let lampPoolStrength: Float = 0.55

    /// The models' places in ``Map3DModelPack/standard``.
    /// Decision 820: from ``Map3DModelCatalog``, not waiting for the pack.
    static let propModels: [Map3DProp: Int] = Dictionary(uniqueKeysWithValues: Map3DProp.allCases.compactMap { prop in
        Map3DModelCatalog.standard.index(of: prop.modelName).map { (prop, $0) }
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
                // Decision 846: no Taiwan's utility poles on Finland's lanes.
                for rule in rules where rule.prop != .pole || look.streets.hasUtilityPoles {
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
                            // Decision 846's later note: Finland's own
                            // street light on its streets.
                            let finnish = rule.prop == .lamp && look.streets.hasFinnishFurniture ? Self.finlandModels[.lamp] : nil
                            guard map3DRandom(seed.0, seed.1, salt: 71) >= (rule.prop == .tree ? 0.18 : 0.08), !nearJunction(x, z),
                                  let model = finnish ?? Self.propModels[rule.prop] else { continue }
                            // Decision 391: none on a bridge or its ramp.
                            guard roadRise(at: Map3DBaseMap.Point(x: centre.x, z: centre.z), along: along, onDeck: road.bridgeLevel > 0).rise < Self.propRise
                            else { continue }
                            // Decision 865: on the road's bed.
                            let foot = Map3DPoint(Float(x), roadGround(at: Map3DBaseMap.Point(x: x, z: z), along: along, onDeck: road.bridgeLevel > 0,
                                                                       beyond: 2.5) + Self.sidewalkLift, Float(z))
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
        isInside(p, waterCells)
    }

    /// Decision 458: whether scene point `p` is inside one of `cells`'
    /// areas (``waterCells``, ``woodCells``, ``grassCells``).
    func isInside(_ p: Map3DPoint, _ cells: [Map3DScene.ChunkKey: [[[Map3DBaseMap.Point]]]]) -> Bool {
        guard let areas = cells[Map3DScene.ChunkKey(column: gridCell(Double(p.x), origin: originX), row: gridCell(Double(p.z), origin: originY))]
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
