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
    static func lift(of cover: Map3DBaseMap.Cover) -> Float {
        0.04 * Float(cover.rawValue + 1)
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

    /// Half a city lot's side: a road or water this near a lot's middle
    /// (in both directions) takes the lot.
    static let lotReach: Float = 20

    /// Lays `map` on the ground; the 64 m cells (by column and row) whose
    /// city lot a road, a river or a park takes.
    mutating func addBaseMap(_ map: Map3DBaseMap) -> Set<Map3DScene.ChunkKey> {
        var taken = Set<Map3DScene.ChunkKey>()
        for cover in Map3DBaseMap.Cover.allCases {
            for area in map.areas where area.cover == cover {
                addArea(area, taking: &taken)
            }
        }
        for waterway in map.waterways {
            addStrip(waterway.points, bounds: waterway.bounds, width: waterway.kind.width,
                     lift: Self.lift(of: .water), color: Map3DPalette.water, paint: nil, taking: &taken)
        }
        // Decision 241: the sidewalks first, a strip wider than the road
        // under it, so both edges show and they close at the junctions.
        for road in map.roads where Self.sidewalk(of: road.kind) > 0 && !road.isRamp {
            addStrip(road.points, bounds: road.bounds, width: road.kind.width(ramp: false) + 2 * Self.sidewalk(of: road.kind),
                     lift: Self.sidewalkLift, color: Map3DPalette.sidewalk, paint: Self.paving, taking: &taken)
        }
        for kind in Map3DBaseMap.RoadKind.allCases {
            for road in map.roads where road.kind == kind {
                addStrip(road.points, bounds: road.bounds, width: kind.width(ramp: road.isRamp), lift: Self.lift(of: kind),
                         color: Map3DPalette.road(kind), paint: nil, taking: &taken)
            }
        }
        var lines = Set<Map3DScene.ChunkKey>()
        for road in map.roads where Self.hasCentreLine(road) {
            addStrip(road.points, bounds: road.bounds, width: 0.3, lift: Self.centreLineLift, color: Map3DPalette.centreLine, paint: nil,
                     taking: &lines)
        }
        addStreetProps(map)
        return taken
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
                    let triangles = Earcut.triangulate(flat)
                    guard !triangles.isEmpty else { continue }
                    var points: [Map3DPoint] = []
                    for ring in piece {
                        for point in ring {
                            let x = Float(point.x), z = Float(point.z)
                            points.append(Map3DPoint(x, drawnGround(x: x, z: z) + lift, z))
                        }
                    }
                    let middle = Map3DPoint(Float((westX + gridLine(column + 1, origin: originX)) / 2), 0,
                                            Float((northZ + gridLine(row + 1, origin: originY)) / 2))
                    mesh(at: middle) { $0.addFlat(points, triangles: triangles, color: color, paint: paint) }
                }
                if takes && covered > cellArea / 2 {
                    taken.insert(Map3DScene.ChunkKey(column: column, row: row))
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
    /// past its ends so bends close.
    mutating func addStrip(_ points: [Map3DBaseMap.Point], bounds: Map3DBaseMap.Bounds, width: Float, lift: Float, color: UInt32,
                           paint: Map3DPaint?, taking taken: inout Set<Map3DScene.ChunkKey>) {
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
            let cuts = splits(from: first, to: last)
            for step in 1..<cuts.count {
                let t0 = cuts[step - 1], t1 = cuts[step]
                guard t1 - t0 > 1e-6 else { continue }
                let a = Map3DBaseMap.Point(x: first.x + (last.x - first.x) * t0, z: first.z + (last.z - first.z) * t0)
                let b = Map3DBaseMap.Point(x: first.x + (last.x - first.x) * t1, z: first.z + (last.z - first.z) * t1)
                // Left of the way along is (z, −x) in x east, z south.
                let leftX = along.z * half, leftZ = -along.x * half
                let corners = [
                    (a.x + leftX, a.z + leftZ), (a.x - leftX, a.z - leftZ), (b.x - leftX, b.z - leftZ), (b.x + leftX, b.z + leftZ),
                ].map { corner -> Map3DPoint in
                    let x = Float(corner.0), z = Float(corner.1)
                    return Map3DPoint(x, drawnGround(x: x, z: z) + lift, z)
                }
                let middle = Map3DPoint(Float((a.x + b.x) / 2), 0, Float((a.z + b.z) / 2))
                mesh(at: middle) { $0.addFlat(corners, triangles: [0, 1, 2, 0, 2, 3], color: color, paint: paint) }
                take(from: a, to: b, half: half, into: &taken)
            }
        }
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
    mutating func addStreetProps(_ map: Map3DBaseMap) {
        let junctions = Self.junctions(of: map.roads)
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
        for road in map.roads where !road.isRamp && road.points.count >= 2 {
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

