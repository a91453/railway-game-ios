import GameCore

/// What stands still on the native 3D map (ARCHITECTURE decision 229): the
/// ground, the track and what carries it, the platforms, the city and the
/// player's buildings, merged into one mesh per ``chunkSize`` square so the
/// app draws each square in one call and skips the squares out of view.
///
/// Derived from the world and never kept as a second copy of it: the app
/// makes a new one when the network or the city changes, off the main
/// thread. The trains move, so they are not here (``Map3DTrains``).
///
/// Sizes are real (the art direction "F 台灣版＋", `docs/art/3d-style-2026-10-13/`):
/// the track's bed, viaduct and piers are `Railway/` rail-3d's
/// (`integration/rail-structures.js`, `map3d.js`), at Taiwan Railway's
/// 1,067 mm gauge; the row houses follow `Railway/city_world_reference/`'s
/// lot rules (`world-DCb11kLR.js`: widths, floors, floor heights, the wall
/// colours). Decoration is chosen by ``map3DRandom(_:_:salt:)`` from where
/// it stands, never at random.
public struct Map3DScene: Sendable {
    /// One square of the map: its meshes and the box holding them.
    public struct Chunk: Sendable {
        public let column: Int
        public let row: Int
        public let mesh: Map3DMesh
        public let minimum: Map3DPoint
        public let maximum: Map3DPoint
    }

    /// The side of a chunk, in metres.
    public static let chunkSize: Float = 512
    /// The most of the world a scene covers each way from the middle of
    /// what is built, in metres: a whole island's map would not fit a
    /// phone's memory as one scene (decision 89).
    public static let reach: Double = 6_000
    /// What is shown round what is built, in metres.
    public static let margin: Double = 1_500

    /// The world point (in world units) at the scene's origin.
    public let originX: Double
    public let originY: Double
    /// The part of the world the scene covers, in world units.
    public let region: WorldRegion
    public let chunks: [Chunk]

    public var triangleCount: Int { chunks.reduce(0) { $0 + $1.mesh.triangleCount } }

    // MARK: - Space

    /// Where world point (`x`, `y`, height `z`), in world units, is in the
    /// scene, in metres.
    public func point(worldX x: Double, worldY y: Double, height z: Double) -> Map3DPoint {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        return Map3DPoint(Float((x - originX) / metre), Float(z / metre), Float((y - originY) / metre))
    }

    public func point(_ coordinate: WorldCoordinate) -> Map3DPoint {
        point(worldX: Double(coordinate.x), worldY: Double(coordinate.y), height: Double(coordinate.z))
    }

    /// The world point (in world units, seen from above) at scene point
    /// `point`.
    public func worldPosition(of point: Map3DPoint) -> (x: Double, y: Double) {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        return (originX + Double(point.x) * metre, originY + Double(point.z) * metre)
    }

    // MARK: - Building

    /// The scene of `world`: what is built and ``margin`` round it, at most
    /// ``reach`` each way from its middle; on a map with nothing built, the
    /// ``reach`` round `focus` (world units), or round the map's middle.
    public init(world: GameWorld, snapshot: RailwaySnapshot? = nil, skyline: CitySkyline? = nil, focus: (x: Double, y: Double)? = nil) {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let mapRegion = WorldRegion(bounds: world.bounds)
        let built = WorldRegion.built(in: world)
        let middle = built.map { (x: ($0.minX + $0.maxX) / 2, y: ($0.minY + $0.maxY) / 2) }
            ?? focus ?? (x: (mapRegion.minX + mapRegion.maxX) / 2, y: (mapRegion.minY + mapRegion.maxY) / 2)
        let reach = Self.reach * metre, margin = Self.margin * metre
        let wanted = built.map { WorldRegion(minX: $0.minX - margin, minY: $0.minY - margin, maxX: $0.maxX + margin, maxY: $0.maxY + margin) }
            ?? WorldRegion(minX: middle.x - margin, minY: middle.y - margin, maxX: middle.x + margin, maxY: middle.y + margin)
        region = WorldRegion(
            minX: max(mapRegion.minX, max(wanted.minX, middle.x - reach)), minY: max(mapRegion.minY, max(wanted.minY, middle.y - reach)),
            maxX: min(mapRegion.maxX, min(wanted.maxX, middle.x + reach)), maxY: min(mapRegion.maxY, min(wanted.maxY, middle.y + reach))
        )
        originX = middle.x.rounded()
        originY = middle.y.rounded()

        var builder = Builder(originX: originX, originY: originY, region: region, world: world)
        let snapshot = snapshot ?? world.railwaySnapshot()
        builder.addGround()
        let cleared = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        builder.addPortals(snapshot)
        builder.addCity(skyline ?? CitySkyline(world: world), clearOf: cleared)
        builder.addPlacedBuildings()
        chunks = builder.chunks()
    }
}

// MARK: - Colours

/// The 3D map's colours (F 台灣版＋): soft, bright and a little warm; the
/// player's buildings the warm yellow of the 2D map (decision 205).
public enum Map3DPalette {
    public static let ground = Map3DColor.rgb(0xDDE4CF)
    public static let water = Map3DColor.rgb(0x8FC6E6)
    public static let park = Map3DColor.rgb(0xAFD38F)
    public static let farm = Map3DColor.rgb(0xD8D9A2)
    public static let plaza = Map3DColor.rgb(0xD9D4C8)
    public static let ballast = Map3DColor.rgb(0xA39B8E)
    public static let embankment = Map3DColor.rgb(0x9DB07E)
    public static let rail = Map3DColor.rgb(0x6E7379)
    public static let railTop = Map3DColor.rgb(0xC9CED4)
    public static let concrete = Map3DColor.rgb(0xCFCBC2)
    public static let bridge = Map3DColor.rgb(0x8E9CA8)
    public static let portal = Map3DColor.rgb(0x8B9096)
    public static let platform = Map3DColor.rgb(0xDCD6C8)
    public static let platformEdge = Map3DColor.rgb(0xF2C94C)
    /// Taiwanese station signs' blue, on the canopies.
    public static let canopy = Map3DColor.rgb(0x2F6DB5)
    public static let roof = Map3DColor.rgb(0xCBC7BF)
    public static let arcade = Map3DColor.rgb(0x6F6A64)
    public static let tankBlue = Map3DColor.rgb(0x3B7DD8)
    public static let tankSteel = Map3DColor.rgb(0xC8CDD2)
    public static let trunk = Map3DColor.rgb(0x8A6A4F)
    public static let crown = Map3DColor.rgb(0x6FA85A)
    /// The player's buildings (decision 205) and the navy rim that marks
    /// them apart from the city's offices in grey (the art direction's
    /// note).
    public static let player = Map3DColor.rgb(0xFFC86B)
    public static let playerRoof = Map3DColor.rgb(0xFFE2A6)
    public static let playerRim = Map3DColor.rgb(0x26385C)

    /// Row house walls: `city_world_reference`'s shophouse palette (white
    /// 4, #F2E2D6 2, #E0D0C8 1, #D6C2B0 1) and four tile colours common in
    /// Taiwan.
    static let houseWalls: [(color: UInt32, weight: Float)] = [
        (rgb(0xFFFFFF), 4), (rgb(0xF2E2D6), 2), (rgb(0xE0D0C8), 1), (rgb(0xD6C2B0), 1),
        (rgb(0xE8D8B8), 1), (rgb(0xC9D3D6), 1), (rgb(0xD9B9A2), 1), (rgb(0xBFC8B4), 1),
    ]
    static let officeWalls: [UInt32] = [rgb(0xAEBFCC), rgb(0xC2CCD4), rgb(0x9FB3C2)]
    static let industrialWalls: [UInt32] = [rgb(0xB9BEB4), rgb(0xA8B2A8), rgb(0xC6C2B4)]
    static let civicWalls: [UInt32] = [rgb(0xE6D9BF), rgb(0xDCCFB5)]
    static let leisureWalls: [UInt32] = [rgb(0xB9D9D0), rgb(0xE4CDB8)]

    private static func rgb(_ hex: UInt32) -> UInt32 { Map3DColor.rgb(hex) }
}

// MARK: - The builder

extension Map3DScene {
    /// A chunk's place, by column and row of ``chunkSize``.
    struct ChunkKey: Hashable, Comparable {
        let column: Int
        let row: Int

        static func < (a: ChunkKey, b: ChunkKey) -> Bool { (a.row, a.column) < (b.row, b.column) }
    }

    struct Builder {
        let originX: Double
        let originY: Double
        let region: WorldRegion
        let world: GameWorld
        var meshes: [ChunkKey: Map3DMesh] = [:]

        static let metre = Double(WorldCoordinate.unitsPerMetre)

        // Track (rail-3d `rail-structures.js`, metres).
        static let gauge: Float = 1.067
        static let railWidth: Float = 0.14
        static let railHeight: Float = 0.2
        static let bedTop: Float = 3.4
        static let bedBottom: Float = 4.6
        static let bedDrop: Float = 0.35
        static let deckWidth: Float = 5
        static let girderDepth: Float = 1.8
        static let pierAlong: Float = 1.6
        static let pierAcross: Float = 2.2
        static let pierSpacing: Float = 32
        // Platforms: TRA's high platforms stand about 1.15 m above the rail,
        // their edge 1.6 m from the track's middle (no reference: gap).
        static let platformHeight: Float = 1.15
        static let platformEdge: Float = 1.6
        static let platformWidth: Float = 3.2
        static let canopyHeight: Float = 4.4
        /// How finely track is laid between its samples, in metres.
        static let trackStep: Double = 16

        init(originX: Double, originY: Double, region: WorldRegion, world: GameWorld) {
            self.originX = originX
            self.originY = originY
            self.region = region
            self.world = world
        }

        func point(x: Double, y: Double, height: Double) -> Map3DPoint {
            Map3DPoint(Float((x - originX) / Self.metre), Float(height / Self.metre), Float((y - originY) / Self.metre))
        }

        func point(_ c: WorldCoordinate) -> Map3DPoint {
            point(x: Double(c.x), y: Double(c.y), height: Double(c.z))
        }

        /// The ground's height at world point (`x`, `y`), in metres: the
        /// map's ground (decision 151), or 0 where it has none.
        func ground(x: Double, y: Double) -> Float {
            let plan = PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded()))
            return Float(Double(world.groundHeight(at: plan) ?? 0) / Self.metre)
        }

        func ground(at scene: Map3DPoint) -> Float {
            ground(x: originX + Double(scene.x) * Self.metre, y: originY + Double(scene.z) * Self.metre)
        }

        func key(of scene: Map3DPoint) -> ChunkKey {
            ChunkKey(column: Int((scene.x / Map3DScene.chunkSize).rounded(.down)), row: Int((scene.z / Map3DScene.chunkSize).rounded(.down)))
        }

        func contains(x: Double, y: Double) -> Bool {
            x >= region.minX && x <= region.maxX && y >= region.minY && y <= region.maxY
        }

        mutating func mesh(at scene: Map3DPoint, _ build: (inout Map3DMesh) -> Void) {
            build(&meshes[key(of: scene), default: Map3DMesh()])
        }

        func chunks() -> [Chunk] {
            meshes.keys.sorted().compactMap { key in
                guard let mesh = meshes[key], let bounds = mesh.bounds else { return nil }
                return Chunk(column: key.column, row: key.row, mesh: mesh, minimum: bounds.min, maximum: bounds.max)
            }
        }

        // MARK: Ground

        /// The ground: a grid of 64 m squares at the map's heights, the
        /// water on it.
        mutating func addGround() {
            let cell = Double(Land.cellLength)
            let firstColumn = Int((region.minX / cell).rounded(.down)), lastColumn = Int((region.maxX / cell).rounded(.up)) - 1
            let firstRow = Int((region.minY / cell).rounded(.down)), lastRow = Int((region.maxY / cell).rounded(.up)) - 1
            guard firstColumn <= lastColumn, firstRow <= lastRow else { return }
            var heights: [Int: Float] = [:]
            let width = lastColumn - firstColumn + 2
            func corner(_ row: Int, _ column: Int) -> Map3DPoint {
                let x = Double(column) * cell, y = Double(row) * cell
                let index = (row - firstRow) * width + (column - firstColumn)
                let height: Float
                if let known = heights[index] {
                    height = known
                } else {
                    height = ground(x: x, y: y)
                    heights[index] = height
                }
                return Map3DPoint(Float((x - originX) / Self.metre), height, Float((y - originY) / Self.metre))
            }
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    let a = corner(row, column), b = corner(row + 1, column), c = corner(row + 1, column + 1), d = corner(row, column + 1)
                    let water = world.isWater(row: row, column: column)
                    let lift = Map3DPoint(0, water ? 0.05 : 0, 0)
                    let middle = (a + c) * 0.5
                    mesh(at: middle) { $0.addQuad(a + lift, b + lift, c + lift, d + lift, color: water ? Map3DPalette.water : Map3DPalette.ground) }
                }
            }
        }

        // MARK: Track

        /// The track: its bed or viaduct, piers and rails, edge by edge and
        /// stretch by stretch of what carries it. Returns the 64 m cells
        /// it runs through, which keep no building.
        mutating func addTrack(_ snapshot: RailwaySnapshot) -> Set<ChunkKey> {
            var cleared = Set<ChunkKey>()
            let cell = Double(Land.cellLength)
            for alignment in snapshot.edges {
                for span in alignment.edge.sectionSpans where span.end > span.start {
                    let line = sample(alignment.geometry, from: span.start, to: span.end)
                    guard line.count > 1 else { continue }
                    for coordinate in line {
                        guard contains(x: Double(coordinate.x), y: Double(coordinate.y)) else { continue }
                        cleared.insert(ChunkKey(column: Int((Double(coordinate.x) / cell).rounded(.down)), row: Int((Double(coordinate.y) / cell).rounded(.down))))
                    }
                    guard line.contains(where: { contains(x: Double($0.x), y: Double($0.y)) }) else { continue }
                    let points = line.map(point)
                    for piece in Self.pieces(of: points) {
                        addTrackPiece(piece, kind: span.kind)
                    }
                }
            }
            return cleared
        }

        /// The centre line between `start` and `end` along `geometry`, at
        /// least every ``trackStep`` metres, with its heights.
        func sample(_ geometry: TrackGeometry, from start: Int64, to end: Int64) -> [WorldCoordinate] {
            let step = Int64(Self.trackStep * Self.metre)
            var distances: [Int64] = [start]
            var next = start + step
            for distance in geometry.distances where distance > start && distance < end {
                while next < distance {
                    distances.append(next)
                    next += step
                }
                distances.append(distance)
                next = distance + step
            }
            while next < end {
                distances.append(next)
                next += step
            }
            distances.append(end)
            return distances.map { geometry.location(at: $0).position }
        }

        /// `line` in pieces of at most 256 m, each sharing its first point
        /// with the last's end, so a long line falls into the chunks it
        /// crosses.
        static func pieces(of line: [Map3DPoint]) -> [[Map3DPoint]] {
            var pieces: [[Map3DPoint]] = []
            var current: [Map3DPoint] = []
            var length: Float = 0
            for point in line {
                if let last = current.last { length += (point - last).length }
                current.append(point)
                if length >= 256, current.count > 1 {
                    pieces.append(current)
                    current = [point]
                    length = 0
                }
            }
            if current.count > 1 { pieces.append(current) }
            return pieces
        }

        mutating func addTrackPiece(_ line: [Map3DPoint], kind: TrackSectionKind) {
            let middle = line[line.count / 2]
            switch kind {
            case .tunnel:
                return
            case .viaduct, .bridge:
                let deckColor = kind == .bridge ? Map3DPalette.bridge : Map3DPalette.concrete
                let grounds = line.map { ground(at: $0) }
                mesh(at: middle) { mesh in
                    mesh.addRibbon(along: line, width: Self.deckWidth, lift: -Self.bedDrop, depth: Self.girderDepth, top: Map3DPalette.ballast, side: deckColor)
                    // A pier every 32 m along the piece (rail-3d `PIER_M`).
                    var travelled: Float = 0, nextPier: Float = Self.pierSpacing / 2
                    for index in 1..<line.count {
                        let a = line[index - 1], b = line[index], step = (b - a).length
                        guard step > 0 else { continue }
                        while nextPier <= travelled + step {
                            let share = (nextPier - travelled) / step
                            let top = a + (b - a) * share
                            let foot = grounds[index - 1] + (grounds[index] - grounds[index - 1]) * share
                            let height = top.y - Self.bedDrop - Self.girderDepth - foot
                            if height > 0.5 {
                                mesh.addBox(base: Map3DPoint(top.x, foot, top.z), forward: b - a, length: Self.pierAlong, width: Self.pierAcross,
                                            height: height, top: deckColor, side: deckColor)
                            }
                            nextPier += Self.pierSpacing
                        }
                        travelled += step
                    }
                }
            case .surface, .embankment, .cutting:
                let lifts = line.map { $0.y - ground(at: $0) }
                let depth = max(0.45, (lifts.reduce(0, +) / Float(lifts.count)) - Self.bedDrop)
                let bank = kind == .embankment ? Map3DPalette.embankment : Map3DPalette.ballast
                mesh(at: middle) { mesh in
                    if kind == .embankment {
                        mesh.addRibbon(along: line, width: Self.bedBottom + min(depth, 4.7) * 2, lift: -Self.bedDrop - 0.05, depth: depth, top: bank, side: bank)
                    }
                    mesh.addRibbon(along: line, width: Self.bedTop, lift: -Self.bedDrop, depth: min(depth, 0.6), top: Map3DPalette.ballast, side: Map3DPalette.ballast)
                }
            }
            // The rails, their middles half a rail outside the gauge.
            let offset = (Self.gauge + Self.railWidth) / 2
            mesh(at: middle) { mesh in
                for side: Float in [-1, 1] {
                    mesh.addRibbon(along: line, width: Self.railWidth, offset: side * offset, lift: 0, depth: Self.railHeight,
                                   top: Map3DPalette.railTop, side: Map3DPalette.rail)
                }
            }
        }

        // MARK: Platforms

        /// Each platform beside its track: towards the other platform of
        /// its station within 15 m (an island between them), else on the
        /// side clear of other track, the left first; with a canopy.
        mutating func addPlatforms(_ snapshot: RailwaySnapshot) {
            let platforms = snapshot.platforms.filter { $0.points.count > 1 && $0.structure != .tunnel }
            let middles = platforms.map { point($0.points[$0.points.count / 2]) }
            let others = snapshot.edges.map { ($0.edge.id, $0.geometry.points.map(point)) }
            for (index, platform) in platforms.enumerated() {
                guard platform.points.contains(where: { contains(x: Double($0.x), y: Double($0.y)) }) else { continue }
                let line = platform.points.map(point)
                let across = Map3DMesh.acrossDirections(line)[line.count / 2]
                let middle = middles[index]
                var side: Float = -1, width = Self.platformWidth
                let partner = platforms.indices
                    .filter { $0 != index && platforms[$0].platform.station == platform.platform.station && platforms[$0].platform.edge != platform.platform.edge }
                    .map { (index: $0, distance: (middles[$0] - middle).length) }
                    .filter { $0.distance < 15 && $0.distance > 2 * Self.platformEdge + 1 }
                    .min { $0.distance < $1.distance }
                if let partner {
                    side = (middles[partner.index] - middle).dot(across) >= 0 ? 1 : -1
                    width = partner.distance / 2 - Self.platformEdge
                } else {
                    func blocked(_ side: Float) -> Bool {
                        let probe = middle + across * (side * (Self.platformEdge + Self.platformWidth / 2))
                        return others.contains { id, points in
                            id != platform.platform.edge && points.contains { abs($0.x - probe.x) < 3 && abs($0.z - probe.z) < 3 && ($0 - probe).length < 2.6 }
                        }
                    }
                    if blocked(-1), !blocked(1) { side = 1 }
                }
                let offset = side * (Self.platformEdge + width / 2)
                mesh(at: middle) { mesh in
                    mesh.addRibbon(along: line, width: width, offset: offset, lift: Self.platformHeight, depth: Self.platformHeight + Self.bedDrop,
                                   top: Map3DPalette.platform, side: Map3DPalette.platform)
                    mesh.addRibbon(along: line, width: 0.3, offset: side * (Self.platformEdge + 0.35), lift: Self.platformHeight + 0.01,
                                   top: Map3DPalette.platformEdge)
                    mesh.addRibbon(along: line, width: min(width, 3.6), offset: offset, lift: Self.canopyHeight, depth: 0.3,
                                   top: Map3DPalette.canopy, side: Map3DPalette.canopy)
                }
            }
        }

        // MARK: Tunnel portals

        /// A concrete frame where track enters the ground.
        mutating func addPortals(_ snapshot: RailwaySnapshot) {
            for node in snapshot.nodes where node.isTunnelPortal && contains(x: Double(node.position.x), y: Double(node.position.y)) {
                guard let alignment = snapshot.edges.first(where: { $0.edge.from == node.id || $0.edge.to == node.id }) else { continue }
                let direction = alignment.edge.from == node.id ? alignment.geometry.startDirection : alignment.geometry.endDirection
                let forward = Map3DPoint(Float(direction.dx), 0, Float(direction.dy))
                guard let along = forward.normalized else { continue }
                let across = Map3DPoint(-along.z, 0, along.x)
                let base = point(node.position) + Map3DPoint(0, -Self.bedDrop, 0)
                mesh(at: base) { mesh in
                    for side: Float in [-1, 1] {
                        mesh.addBox(base: base + across * (side * 3.6), forward: along, length: 1.2, width: 1.6, height: 6.4,
                                    top: Map3DPalette.portal, side: Map3DPalette.portal)
                    }
                    mesh.addBox(base: base + Map3DPoint(0, 5.6, 0), forward: along, length: 1.2, width: 8.8, height: 1.4,
                                top: Map3DPalette.portal, side: Map3DPalette.portal)
                }
            }
        }

        // MARK: City

        /// Every lot of the city in the scene, but those on cells the track
        /// runs through: row houses on low homes and shops, blocks for the
        /// rest, trees in the parks.
        mutating func addCity(_ skyline: CitySkyline, clearOf cleared: Set<ChunkKey>) {
            let cell = Double(Land.cellLength)
            for lot in skyline.lots(in: region) {
                let x = (Double(lot.column) + 0.5) * cell, y = (Double(lot.row) + 0.5) * cell
                guard contains(x: x, y: y) else { continue }
                let centre = point(x: x, y: y, height: 0)
                let base = Map3DPoint(centre.x, ground(x: x, y: y), centre.z)
                let side = Float(Double(lot.side) / Self.metre)
                let seed = (Int32(truncatingIfNeeded: lot.column), Int32(truncatingIfNeeded: lot.row))
                if lot.isOpenGround {
                    addOpenGround(lot, base: base, seed: seed)
                    continue
                }
                if cleared.contains(ChunkKey(column: lot.column, row: lot.row)) {
                    // A plaza where the track passes.
                    let half = Float(cell / Self.metre / 2) - 1
                    mesh(at: base) { mesh in
                        mesh.addQuad(base + Map3DPoint(-half, 0.03, -half), base + Map3DPoint(-half, 0.03, half),
                                     base + Map3DPoint(half, 0.03, half), base + Map3DPoint(half, 0.03, -half), color: Map3DPalette.plaza)
                    }
                    continue
                }
                switch lot.use {
                case .residential, .commercial:
                    if lot.density <= 2 {
                        addRowHouses(base: base, side: side, density: lot.density, shops: lot.use == .commercial, seed: seed)
                    } else {
                        addBlock(base: base, side: side, density: lot.density, walls: Self.pickWall(seed), seed: seed)
                    }
                case .office:
                    addBlock(base: base, side: side, density: lot.density, walls: Self.pick(Map3DPalette.officeWalls, seed), seed: seed)
                case .industrial:
                    addShed(base: base, side: side, walls: Self.pick(Map3DPalette.industrialWalls, seed))
                case .civic:
                    addBlock(base: base, side: side, density: min(lot.density, 2), walls: Self.pick(Map3DPalette.civicWalls, seed), seed: seed)
                default:
                    addBlock(base: base, side: side, density: min(lot.density, 2), walls: Self.pick(Map3DPalette.leisureWalls, seed), seed: seed)
                }
            }
        }

        mutating func addOpenGround(_ lot: CitySkyline.Lot, base: Map3DPoint, seed: (Int32, Int32)) {
            let half = Float(Double(Land.cellLength) / Self.metre / 2) - 0.5
            let park = lot.use == .park
            mesh(at: base) { mesh in
                mesh.addQuad(base + Map3DPoint(-half, 0.02, -half), base + Map3DPoint(-half, 0.02, half),
                             base + Map3DPoint(half, 0.02, half), base + Map3DPoint(half, 0.02, -half),
                             color: park ? Map3DPalette.park : Map3DPalette.farm)
                guard park else { return }
                // Up to nine trees on a hashed 20 m grid (rail-3d's trees
                // stand on a hashed 26 m grid).
                for i in -1...1 {
                    for j in -1...1 {
                        let salt = Int32(10 + (i + 1) * 3 + (j + 1))
                        guard map3DRandom(seed.0, seed.1, salt: salt) < 0.7 else { continue }
                        let jitterX = (map3DRandom(seed.0, seed.1, salt: salt + 20) - 0.5) * 8
                        let jitterZ = (map3DRandom(seed.0, seed.1, salt: salt + 40) - 0.5) * 8
                        let spot = base + Map3DPoint(Float(i) * 20 + jitterX, 0, Float(j) * 20 + jitterZ)
                        let size = 4 + map3DRandom(seed.0, seed.1, salt: salt + 60) * 3
                        mesh.addBox(base: spot, length: 0.6, width: 0.6, height: size * 0.45, top: Map3DPalette.trunk, side: Map3DPalette.trunk)
                        mesh.addBox(base: spot + Map3DPoint(0, size * 0.4, 0), length: size, width: size, height: size * 0.75,
                                    top: Map3DPalette.crown, side: Map3DPalette.crown)
                    }
                }
            }
        }

        /// Two rows of 透天厝 back to back on the lot, facing north and
        /// south, each house 4.4–6.6 m wide (a block of flats 6.5–12.5 m at
        /// density 2) with an arcade (騎樓) on most shops, a parapet and a
        /// water tank on many roofs (`city_world_reference` `pickType`,
        /// `floorsFor`, `widthFor`, `waterTank`).
        mutating func addRowHouses(base: Map3DPoint, side: Float, density: Int, shops: Bool, seed: (Int32, Int32)) {
            let depth = min(16, side / 2 - 1)
            guard depth > 4 else { return }
            let flats = density >= 2
            mesh(at: base) { mesh in
                for facing: Float in [-1, 1] {
                    // From the west end along the row.
                    var x = -side / 2 + 0.5
                    var number: Int32 = 0
                    while x < side / 2 - 3.2 {
                        let salt = Int32(facing > 0 ? 100 : 300) + number * 7
                        let r = { (extra: Int32) in map3DRandom(seed.0, seed.1, salt: salt + extra) }
                        var width = flats ? 6.5 + r(1) * 6 : 4.4 + r(1) * 2.2
                        width = min(width, side / 2 - 0.5 - x)
                        guard width >= 3.2 else { break }
                        let floors: Float = flats ? Float(3 + Int(r(2) * 4)) : (r(2) < 0.375 ? 2 : r(2) < 0.875 ? 3 : 4)
                        let groundFloor: Float = flats ? 3.5 + r(3) * 0.6 : 3.8 + r(3) * 0.5
                        let upper: Float = flats ? 3.0 + r(4) * 0.25 : 3.4 + r(4) * 0.3
                        let height = groundFloor + upper * (floors - 1)
                        let wall = Self.pickWall((seed.0 &+ salt, seed.1))
                        let middleX = x + width / 2
                        let front = Map3DPoint(0, 0, facing) // the way the house faces
                        let rowMiddle = base + Map3DPoint(middleX, 0, facing * (depth / 2 + 0.5))
                        let arcade = shops && r(5) < 0.8
                        if arcade {
                            // The ground floor set back 3.4 m, dark; the
                            // floors above over the arcade.
                            mesh.addBox(base: rowMiddle - front * 1.7, forward: front, length: depth - 3.4, width: width - 0.1,
                                        height: groundFloor, top: Map3DPalette.arcade, side: Map3DPalette.arcade)
                            mesh.addBox(base: rowMiddle + Map3DPoint(0, groundFloor, 0), forward: front, length: depth, width: width - 0.1,
                                        height: height - groundFloor, top: Map3DPalette.roof, side: wall)
                        } else {
                            mesh.addBox(base: rowMiddle, forward: front, length: depth, width: width - 0.1, height: height,
                                        top: Map3DPalette.roof, side: wall)
                        }
                        // A parapet's rim and a water tank on the roof.
                        mesh.addBox(base: rowMiddle + Map3DPoint(0, height, 0), forward: front, length: depth, width: width - 0.1,
                                    height: 0.7, top: Map3DPalette.roof, side: Map3DColor.shaded(wall, 0.95))
                        if r(6) < 0.6 {
                            let tank = r(7) < 0.5 ? Map3DPalette.tankBlue : Map3DPalette.tankSteel
                            mesh.addBox(base: rowMiddle + Map3DPoint(0, height + 0.7, 0) - front * (depth / 4), forward: front,
                                        length: 1.6, width: 1.6, height: 2.2, top: tank, side: tank)
                        }
                        x += width
                        number += 1
                    }
                }
            }
        }

        /// A block of flats, offices or a tower: density 3 a slab of 7–16
        /// floors, density 4 a two-floor podium under a tower of 18–40.
        mutating func addBlock(base: Map3DPoint, side: Float, density: Int, walls: UInt32, seed: (Int32, Int32)) {
            let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
            mesh(at: base) { mesh in
                let footprint = max(side - 4, 8)
                switch density {
                case ...2:
                    let floors = Float(3 + Int(r(1) * 4))
                    mesh.addBox(base: base, length: footprint * 0.8, width: footprint * 0.8, height: 3.8 + 3.2 * (floors - 1),
                                top: Map3DPalette.roof, side: walls)
                case 3:
                    let floors = Float(7 + Int(r(1) * 10))
                    let turned = r(2) < 0.5
                    mesh.addBox(base: base, forward: turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1),
                                length: footprint * 0.9, width: footprint * 0.45, height: 4.6 + 3.2 * (floors - 1), top: Map3DPalette.roof, side: walls)
                default:
                    let floors = Float(18 + Int(r(1) * 23))
                    mesh.addBox(base: base, length: footprint, width: footprint, height: 9, top: Map3DPalette.roof, side: Map3DColor.shaded(walls, 0.9))
                    mesh.addBox(base: base + Map3DPoint(0, 9, 0), length: footprint * 0.55, width: footprint * 0.55, height: 3.3 * floors,
                                top: Map3DPalette.roof, side: walls)
                }
            }
        }

        /// A factory: low, wide, with a lighter roof.
        mutating func addShed(base: Map3DPoint, side: Float, walls: UInt32) {
            let footprint = max(side - 6, 8)
            mesh(at: base) { mesh in
                mesh.addBox(base: base, length: footprint, width: footprint * 0.7, height: 8, top: Map3DColor.rgb(0xDADDE0), side: walls)
            }
        }

        // MARK: The player's buildings

        /// The player's and the company's buildings, warm yellow with a navy
        /// rim on the roof.
        mutating func addPlacedBuildings() {
            for building in world.placedBuildings {
                let x = Double(building.centre.x), y = Double(building.centre.y)
                guard contains(x: x, y: y) else { continue }
                let centre = point(x: x, y: y, height: 0)
                let base = Map3DPoint(centre.x, ground(x: x, y: y), centre.z)
                let side = Float(Double(building.kind.side) / Self.metre) - 2
                let height = 1.5 + 3.5 * Float(building.kind.floors)
                mesh(at: base) { mesh in
                    mesh.addBox(base: base, length: side, width: side, height: height, top: Map3DPalette.playerRoof, side: Map3DPalette.player)
                    mesh.addBox(base: base + Map3DPoint(0, height, 0), length: side, width: side, height: 0.6,
                                top: Map3DPalette.playerRim, side: Map3DPalette.playerRim)
                    mesh.addBox(base: base + Map3DPoint(0, height, 0), length: side - 2, width: side - 2, height: 0.4,
                                top: Map3DPalette.playerRoof, side: Map3DPalette.playerRoof)
                }
            }
        }

        // MARK: Choosing

        static func pickWall(_ seed: (Int32, Int32)) -> UInt32 {
            let walls = Map3DPalette.houseWalls
            let total = walls.reduce(0) { $0 + $1.weight }
            var roll = map3DRandom(seed.0, seed.1, salt: 7) * total
            for wall in walls {
                if roll < wall.weight { return wall.color }
                roll -= wall.weight
            }
            return walls[0].color
        }

        static func pick(_ colors: [UInt32], _ seed: (Int32, Int32)) -> UInt32 {
            colors[min(colors.count - 1, Int(map3DRandom(seed.0, seed.1, salt: 9) * Float(colors.count)))]
        }
    }
}
