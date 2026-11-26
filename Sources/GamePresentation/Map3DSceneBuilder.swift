import GameCore

// MARK: - The builder

/// What builds a 3D scene: its chunk keys, the heights file's ground, and
/// the builder's state, points and chunks. Its layers are in the
/// `Map3DScene*.swift` files beside it. Moved as it was out of
/// `Map3DScene.swift` (MAP3D-SCENE-SPLIT).
extension Map3DScene {
    /// A chunk's place, by column and row of ``chunkSize``.
    struct ChunkKey: Hashable, Comparable {
        let column: Int
        let row: Int

        static func < (a: ChunkKey, b: ChunkKey) -> Bool { (a.row, a.column) < (b.row, b.column) }

        /// Decision 876 (later, PERF-3D-BLOCK-FIXED): the key as one
        /// number, column over row (two keys equal in it may still differ,
        /// as ``==`` tells).
        private var packed: UInt64 {
            UInt64(truncatingIfNeeded: column) &<< 32 ^ UInt64(truncatingIfNeeded: UInt32(truncatingIfNeeded: row))
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(packed)
        }

        /// Decision 876 (later): the key's hash in a dictionary or a set,
        /// mixed with the table's `seed` by SplitMix64's finalizer instead
        /// of the standard library's SipHash. A 3D block looks keys up
        /// millions of times (the ground's corners, the roads' beds and
        /// bridges by cell), and hashing them was a sixth of a Hong Kong
        /// block's time. These tables hold the map's own cells, not
        /// anything an attacker picks, so a hash that is fast and spreads
        /// them well is enough. Where in a table a key lies changes, and
        /// nothing built depends on it: the standard library seeds every
        /// run differently already.
        func _rawHashValue(seed: Int) -> Int {
            var x = packed ^ UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15
            x = (x ^ (x &>> 30)) &* 0xBF58_476D_1CE4_E5B9
            x = (x ^ (x &>> 27)) &* 0x94D0_49BB_1331_11EB
            return Int(truncatingIfNeeded: x ^ (x &>> 31))
        }
    }

    /// The heights file's ground at the 64 m grid's corners round a
    /// region, each rounded to whole metres as a block reads them
    /// (``HeightGrid/ground(of:frame:)``), and between them blended as
    /// GameCore blends a block's corners.
    struct FileGround {
        let firstRow: Int
        let firstColumn: Int
        let rows: Int
        let columns: Int
        let heights: [Float]
        let grid: HeightGrid
        let frame: RealWorldFrame

        init(_ grid: HeightGrid, frame: RealWorldFrame, region: WorldRegion) {
            self.grid = grid
            self.frame = frame
            let cell = Double(Land.cellLength)
            firstRow = Int((region.minY / cell).rounded(.down)) - 1
            firstColumn = Int((region.minX / cell).rounded(.down)) - 1
            rows = Int((region.maxY / cell).rounded(.up)) + 2 - firstRow
            columns = Int((region.maxX / cell).rounded(.up)) + 2 - firstColumn
            // Web Mercator puts a point's latitude by its y alone and its
            // longitude by its x alone.
            let firstColumn = firstColumn
            let longitudes = (0..<columns).map { frame.coordinate(worldX: Double(firstColumn + $0) * cell, worldY: 0).longitude }
            let firstRow = firstRow, rows = rows
            var reader = HeightGrid.Reader(grid)
            var heights: [Float] = []
            heights.reserveCapacity(rows * columns)
            for row in 0..<rows {
                let latitude = frame.coordinate(worldX: 0, worldY: Double(firstRow + row) * cell).latitude
                reader.forgetRows(above: reader.row(at: latitude))
                for longitude in longitudes {
                    heights.append(Float(reader.height(latitude: latitude, longitude: longitude).rounded()))
                }
            }
            self.heights = heights
        }

        /// Decision 406: the height at the 64 m grid's corner (`row`,
        /// `column`), in metres, as a region round it reads it, wherever
        /// it is.
        func corner(row: Int, column: Int) -> Float {
            if (0..<rows).contains(row - firstRow), (0..<columns).contains(column - firstColumn) {
                return heights[(row - firstRow) * columns + column - firstColumn]
            }
            let cell = Double(Land.cellLength)
            let at = frame.coordinate(worldX: Double(column) * cell, worldY: Double(row) * cell)
            var reader = HeightGrid.Reader(grid)
            return Float(reader.height(latitude: at.latitude, longitude: at.longitude).rounded())
        }

        /// The height at world point (`x`, `y`), in metres.
        func height(x: Double, y: Double) -> Float {
            let cell = Double(Land.cellLength)
            let gx = x / cell - Double(firstColumn), gy = y / cell - Double(firstRow)
            let column = min(max(Int(gx.rounded(.down)), 0), columns - 2), row = min(max(Int(gy.rounded(.down)), 0), rows - 2)
            let fx = Float(min(max(gx - Double(column), 0), 1)), fy = Float(min(max(gy - Double(row), 0), 1))
            func at(_ r: Int, _ c: Int) -> Float { heights[(row + r) * columns + column + c] }
            return at(0, 0) * (1 - fx) * (1 - fy) + at(0, 1) * fx * (1 - fy) + at(1, 0) * (1 - fx) * fy + at(1, 1) * fx * fy
        }
    }

    struct Builder {
        /// So the builder's extensions in other files name a chunk's key
        /// as the builder itself does.
        typealias ChunkKey = Map3DScene.ChunkKey
        let originX: Double
        let originY: Double
        let region: WorldRegion
        let world: GameWorld
        var meshes: [ChunkKey: Map3DMesh] = [:]
        var shadows: [ChunkKey: Map3DMesh] = [:]
        /// Decision 709: the size (``Map3DFarDetail``) of what is being laid
        /// with the ground (``Target/base``), left out from afar when too
        /// small to see; `nil` for what is always drawn.
        var sizing: Float?
        /// Decision 709: whether the simplified city being built
        /// (``Target/far``) is left out from afar building by building,
        /// each by its own size: the real buildings and the lots, not the
        /// landmarks, stations and temples.
        var sizesFar = false
        /// Decision 709: the parts of each chunk's ground, simplified city
        /// and shadows that are left out from afar.
        var baseParts: [ChunkKey: [Map3DFarDetail.Part]] = [:]
        var farParts: [ChunkKey: [Map3DFarDetail.Part]] = [:]
        var shadowParts: [ChunkKey: [Map3DFarDetail.Part]] = [:]

        /// Decision 709: `build`'s shadows at `key`, those of a thing
        /// `size` metres across.
        mutating func shadow(at key: ChunkKey, size: Float, _ build: (inout Map3DMesh) -> Void) {
            let first = shadows[key]?.indices.count ?? 0
            build(&shadows[key, default: Map3DMesh()])
            let count = (shadows[key]?.indices.count ?? 0) - first
            if count > 0 {
                shadowParts[key, default: []].append(Map3DFarDetail.Part(first: first, count: count,
                                                                         rank: Map3DFarDetail.rank(size: size * Map3DFarDetail.shadowShare)))
            }
        }

        /// Decision 709: what each layer added (``Map3DScene/layers``),
        /// and the totals at the last mark.
        var layers: [LayerTriangles] = []
        private var marked = LayerTriangles(layer: "")

        /// Decision 820: how long each step took (``Map3DScene/steps``),
        /// and when the last one ended.
        var steps: [(step: String, seconds: Double)] = []
        private var stepEnded = ContinuousClock.now

        /// Decision 820: the time since the last step is `step`'s.
        mutating func time(_ step: String) {
            let now = ContinuousClock.now, took = (now - stepEnded).components
            stepEnded = now
            steps.append((step, Double(took.seconds) + Double(took.attoseconds) * 1e-18))
        }

        /// Decision 709: everything built since the last mark is `layer`'s.
        /// Decision 820: and the time since the last step.
        mutating func mark(_ layer: String) {
            time(layer)
            func sum(_ meshes: [ChunkKey: Map3DMesh]) -> Int { meshes.values.reduce(0) { $0 + $1.triangleCount } }
            let now = LayerTriangles(layer: layer, base: sum(meshes), near: sum(nearMeshes),
                                     far: sum(farMeshes) + sum(ownColourFar),
                                     boxes: farMeshes.values.reduce(0) { $0 + $1.boxes.reduce(0) { $0 + $1.triangleCount } },
                                     close: sum(closeMeshes), shadows: sum(shadows))
            let added = LayerTriangles(layer: layer, base: now.base - marked.base, near: now.near - marked.near, far: now.far - marked.far,
                                       boxes: now.boxes - marked.boxes, close: now.close - marked.close, shadows: now.shadows - marked.shadows)
            marked = now
            guard added != LayerTriangles(layer: layer) else { return }
            if let at = layers.firstIndex(where: { $0.layer == layer }) {
                layers[at].base += added.base
                layers[at].near += added.near
                layers[at].far += added.far
                layers[at].boxes += added.boxes
                layers[at].close += added.close
                layers[at].shadows += added.shadows
            } else {
                layers.append(added)
            }
        }
        /// Decision 238: what is being built, and so where it goes: the
        /// ground and track drawn at every distance, or the city in full
        /// or simplified. The city's shadows are made once, in full.
        enum Target {
            case base, near, far
            /// Decision 267: the closest detail.
            case close
            /// The boxes standing in for the closest detail's models,
            /// drawn in full but not close up (``Chunk/standIn``).
            case standIn
            /// Decision 380: the overhead line, in the closest detail but
            /// in a coarse chunk too (decision 368 leaves the rest of the
            /// closest detail out of one), so it runs all along the line.
            case wires
            /// Decision 610: the real buildings' street fronts (``Chunk/facade``).
            case facade
        }
        var target = Target.base
        /// Decision 976: what each layer keeps while the scene is built, each
        /// layer's in its own file (``LayerStates``). A new layer's state
        /// goes there, not here.
        var state = LayerStates()
        /// Decision 610: the street fronts, by chunk.
        var facadeMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Decision 244: the street furniture, by chunk.
        var props: [ChunkKey: [Map3DInstance]] = [:]
        /// Decision 352: the signs, by chunk.
        var signs: [ChunkKey: [Map3DSign]] = [:]
        /// Decision 259: where people walk and vehicles drive.
        var streetLife = Map3DStreetLife()
        /// Review L14-7: where a study can be drawn (its origin in a chunk
        /// some block of the scene builds): a station stands for one only
        /// whose origin is in it, else it draws its own building, as a
        /// study out of it is drawn nowhere. Not asked when `nil` (a
        /// scene built apart in the tests).
        var studyRegion: WorldRegion?
        var nearMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Decision 370: colours the model look leaves as they are besides
        /// ``Map3DLook``'s own (the lines' bands).
        var keptColours = Set<UInt32>()
        var farMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Decision 455: whether the simplified city's boxes are kept as
        /// instances (the city's lots), not vertices.
        var instancingBoxes = false
        var closeMeshes: [ChunkKey: Map3DMesh] = [:]
        var standInMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Decision 625 續: what keeps its own colours, added to a chunk's
        /// near and far meshes after the look (the station studies): left
        /// out of ``keptColours``, which would keep the same colours
        /// elsewhere only in a build that holds them.
        var ownColourNear: [ChunkKey: Map3DMesh] = [:]
        var ownColourFar: [ChunkKey: Map3DMesh] = [:]
        /// Whether what is being built is the simplified city.
        var isFar: Bool { target == .far }
        /// The ground's heights at the 64 m grid's corners, in metres, by
        /// row and column, as ``addGround()`` lays them.
        var corners = CornerHeights()
        /// Decision 737: the levelled ground of a real-world map, once
        /// ``levelGround(under:)`` has worked it out; the world's own before.
        var levelling: Map3DLevelledGround?
        /// Decision 359 (續): the whole network's track, for the tunnels
        /// beside a tunnel (``addBore(_:into:)``).
        var trackCover = Map3DTrackCover()
        /// Decision 876: what the scene's builds work out once between
        /// them; a builder's own until it is given a scene's
        /// (``Map3DTrackCover/shared``).
        var shared = Map3DSharedBuild()
        /// Decision 368: the scene point within ``Map3DScene/detailRadius``
        /// of which the city is built in full; everywhere when `nil`.
        var detail: Map3DPoint?
        /// HSRPACE (decision 861): with it, the city is built in full
        /// within ``Map3DScene/detailRadius`` of the way from `detail` to
        /// here (``Map3DStreaming/way(target:velocity:)``).
        var detailAhead: Map3DPoint?

        static let metre = Double(WorldCoordinate.unitsPerMetre)

        // Track (rail-3d `rail-structures.js`, metres).
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
        /// Decision 392: a high-speed station's platform edge, 1.76 m from
        /// the track's middle, as the Shinkansen standard the Taiwan High
        /// Speed Rail was built to (JRTT 新幹線鉄道実施基準, on the
        /// straight).
        static let highSpeedPlatformEdge: Float = 1.76
        static let platformWidth: Float = 3.2
        /// Decision 392: the narrowest platform drawn; where less room is
        /// left between a track and the next, none is.
        static let narrowestPlatform: Float = 2
        static let canopyHeight: Float = 4.4
        /// How finely track is laid between its samples, in metres.
        static let trackStep: Double = 16

        // Decision 231: how each part is painted, and the metres one
        // repeat covers. The ballast's sleepers lie every 0.6 m, four to a
        // repeat, on a 5 m bed (a 3.4 m bed shows its middle).
        static let grass = Map3DPaint.tile(.grass, 40)
        static let bank = Map3DPaint.tile(.grass, 8)
        static let ballast = Map3DPaint(.ballast, .tile(width: 5, height: 2.4))
        static let concrete = Map3DPaint.tile(.concrete, 6)
        static let paving = Map3DPaint.tile(.paving, 4)
        static let roofing = Map3DPaint.tile(.roof, 8)
        static let plaster = Map3DPaint.tile(.plaster, 4)
        static let metal = Map3DPaint.tile(.metalSheet, 4)

        /// The heights file's ground round the region, for the blocks the
        /// world has not read yet; `nil` without the file or off the Earth.
        let fileGround: FileGround?
        /// The ground the player's buildings take (``onPlacedGround(_:)``).
        let placedGround: [PlacedSquare]
        /// Decision 802: the look of the place the map is of.
        let look: Map3DRegionLook

        init(originX: Double, originY: Double, region: WorldRegion, world: GameWorld, heights: HeightGrid? = nil) {
            look = Map3DRegionLook(world: world)
            self.originX = originX
            self.originY = originY
            self.region = region
            self.world = world
            placedGround = Self.placedSquares(world, region: region, originX: originX, originY: originY)
            fileGround = heights.flatMap { grid in RealWorldFrame(world: world).map { FileGround(grid, frame: $0, region: region) } }
            corners = CornerHeights(region: region)
        }

        func point(x: Double, y: Double, height: Double) -> Map3DPoint {
            Self.point(x: x, y: y, height: height, originX: originX, originY: originY)
        }

        /// The scene point of a world point, in the scene whose origin is
        /// (`originX`, `originY`).
        static func point(x: Double, y: Double, height: Double, originX: Double, originY: Double) -> Map3DPoint {
            Map3DPoint(Float((x - originX) / metre), Float(height / metre), Float((y - originY) / metre))
        }

        func point(_ c: WorldCoordinate) -> Map3DPoint {
            point(x: Double(c.x), y: Double(c.y), height: Double(c.z))
        }

        /// Up by ``Map3DScene/railLift``: where track is drawn.
        static let lifted = Map3DPoint(0, Map3DScene.railLift, 0)

        /// The ground's height at world point (`x`, `y`), in metres: the
        /// map's ground (decision 151); where the world has not read it
        /// (it reads a 1,024 m block only where track comes), the heights
        /// file's, the same heights the block will read, so the blocks
        /// read and those not meet without a cliff; 0 m without the file.
        /// Past the world's edge, the ground at the edge.
        func ground(x: Double, y: Double) -> Float {
            // Decision 737: on a real-world map, between the levelled
            // corners, as GameCore's ground lies between its own.
            guard let levelling else { return worldGround(x: x, y: y) }
            let bounds = world.bounds, cell = Double(Land.cellLength)
            let px = min(max(x, 0), Double(bounds.width - 1)), py = min(max(y, 0), Double(bounds.height - 1))
            let column = Int((px / cell).rounded(.down)), row = Int((py / cell).rounded(.down))
            let fx = Float(px / cell - Double(column)), fy = Float(py / cell - Double(row))
            func at(_ row: Int, _ column: Int) -> Float {
                levelling.corner(row: row, column: column, own: worldGround(x: Double(column) * cell, y: Double(row) * cell))
            }
            let top = at(row, column) * (1 - fx) + at(row, column + 1) * fx
            let bottom = at(row + 1, column) * (1 - fx) + at(row + 1, column + 1) * fx
            return top * (1 - fy) + bottom * fy
        }

        /// The world's own ground at world point (`x`, `y`), in metres, as
        /// ``ground(x:y:)`` was before decision 737 levelled it.
        func worldGround(x: Double, y: Double) -> Float {
            let bounds = world.bounds
            let plan = PlanPoint(x: min(max(Int64(x.rounded()), 0), bounds.width - 1),
                                 y: min(max(Int64(y.rounded()), 0), bounds.height - 1))
            if let height = world.groundHeight(at: plan) { return Float(Double(height) / Self.metre) }
            return fileGround?.height(x: Double(plan.x), y: Double(plan.y)) ?? 0
        }

        /// The world's own ground at the 64 m grid's corner (`row`,
        /// `column`), in metres, as any region round it reads it
        /// (decision 406): past this region's edge, the heights file's
        /// corner there, not the edge's.
        func steadyCorner(row: Int, column: Int) -> Float {
            Self.steadyCorner(row: row, column: column, world: world, file: fileGround)
        }

        static func steadyCorner(row: Int, column: Int, world: GameWorld, file fileGround: FileGround?) -> Float {
            let cell = Double(Land.cellLength), bounds = world.bounds
            let plan = PlanPoint(x: min(max(Int64((Double(column) * cell).rounded()), 0), bounds.width - 1),
                                 y: min(max(Int64((Double(row) * cell).rounded()), 0), bounds.height - 1))
            if let height = world.groundHeight(at: plan) { return Float(Double(height) / Self.metre) }
            return fileGround?.corner(row: Int((Double(plan.y) / cell).rounded(.down)), column: Int((Double(plan.x) / cell).rounded(.down))) ?? 0
        }

        /// Decision 737: levels the drawn ground of a real-world map
        /// (``Map3DLevelledGround``), the corners of `snapshot`'s track
        /// kept as the world's; called before anything reads the ground.
        mutating func levelGround(under snapshot: RailwaySnapshot) {
            guard RealWorldFrame(world: world) != nil else { return }
            let cell = Double(Land.cellLength), bounds = world.bounds
            // The whole network's cells, so regions built apart hold the
            // same corners. Decision 876: sampled once for the scene.
            let held = shared.samples(of: snapshot).cells
            // The region's corners and two cells round them, which the
            // strips reaching past its edge read.
            let firstColumn = Int((region.minX / cell).rounded(.down)) - 2, lastColumn = Int((region.maxX / cell).rounded(.up)) + 2
            let firstRow = Int((region.minY / cell).rounded(.down)) - 2, lastRow = Int((region.maxY / cell).rounded(.up)) + 2
            guard firstColumn <= lastColumn, firstRow <= lastRow else { return }
            let world = world, file = fileGround
            corners = CornerHeights(region: region)
            levelling = Map3DLevelledGround(
                held: held, rows: firstRow...lastRow, columns: firstColumn...lastColumn,
                lastRow: Int((Double(bounds.height) / cell).rounded(.down)), lastColumn: Int((Double(bounds.width) / cell).rounded(.down)),
                raw: { Self.steadyCorner(row: $0, column: $1, world: world, file: file) },
                water: { row, column in
                    world.isWater(row: row - 1, column: column - 1) || world.isWater(row: row - 1, column: column)
                        || world.isWater(row: row, column: column - 1) || world.isWater(row: row, column: column)
                }
            )
        }

        /// Decision 406: the drawn ground (``drawnGround(x:z:)``) at scene
        /// point (`x`, `z`) as a region round it draws it, past this
        /// region's edge too, where ``ground(x:y:)`` holds the edge's.
        func steadyGround(x: Float, z: Float) -> Float {
            let cell = Double(Land.cellLength)
            let worldX = originX + Double(x) * Self.metre, worldY = originY + Double(z) * Self.metre
            let column = Int((worldX / cell).rounded(.down)), row = Int((worldY / cell).rounded(.down))
            let fx = Float(worldX / cell - Double(column)), fy = Float(worldY / cell - Double(row))
            func corner(_ row: Int, _ column: Int) -> Float {
                let own = steadyCorner(row: row, column: column)
                // Decision 737: levelled as every region levels it.
                return levelling?.corner(row: row, column: column, own: own) ?? own
            }
            let a = corner(row, column), b = corner(row + 1, column), c = corner(row + 1, column + 1), d = corner(row, column + 1)
            return fy >= fx ? a + fx * (c - b) + fy * (b - a) : a + fx * (d - a) + fy * (c - d)
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
            let key = key(of: scene)
            // Decision 368: none of the city in full in a coarse chunk.
            guard target == .base || target == .far || target == .wires || !isCoarse(key) else { return }
            switch target {
            case .base:
                guard let sizing else {
                    build(&meshes[key, default: Map3DMesh()])
                    break
                }
                // Decision 709: sized, so left out from afar.
                let first = meshes[key]?.indices.count ?? 0
                build(&meshes[key, default: Map3DMesh()])
                let count = (meshes[key]?.indices.count ?? 0) - first
                if count > 0 { baseParts[key, default: []].append(Map3DFarDetail.Part(first: first, count: count, rank: Map3DFarDetail.rank(size: sizing))) }
            case .near: build(&nearMeshes[key, default: Map3DMesh()])
            case .far:
                farMeshes[key, default: Map3DMesh()].collectsBoxes = instancingBoxes
                guard sizesFar else {
                    build(&farMeshes[key, default: Map3DMesh()])
                    break
                }
                // Decision 709: one building, the size of what it adds.
                var part: Map3DFarDetail.Part?
                func sized(_ mesh: inout Map3DMesh) {
                    let first = mesh.indices.count, firstVertex = mesh.vertices.count, firstBox = mesh.boxes.count
                    build(&mesh)
                    guard mesh.indices.count > first || mesh.boxes.count > firstBox else { return }
                    part = Map3DFarDetail.Part(first: first, count: mesh.indices.count - first, firstBox: firstBox, boxCount: mesh.boxes.count - firstBox,
                                               rank: Map3DFarDetail.rank(size: mesh.extent(fromVertex: firstVertex, fromBox: firstBox,
                                                                                                    heightShare: Map3DFarDetail.heightSeen)))
                }
                sized(&farMeshes[key, default: Map3DMesh()])
                if let part { farParts[key, default: []].append(part) }
            case .close, .wires: build(&closeMeshes[key, default: Map3DMesh()])
            case .facade: build(&facadeMeshes[key, default: Map3DMesh()])
            case .standIn: build(&standInMeshes[key, default: Map3DMesh()])
            }
        }

        /// Decision 368: whether chunk `key` is built without its city in
        /// full: further than ``Map3DScene/detailRadius`` from ``detail``.
        func isCoarse(_ key: ChunkKey) -> Bool {
            guard let detail else { return false }
            return Map3DStreaming.distance(of: Map3DStreaming.Key(column: key.column, row: key.row), toWayFrom: detail, to: detailAhead)
                > Map3DScene.detailRadius
        }

        func chunks() -> [Chunk] {
            // Decision 407: the viaducts not yet drawn, drawn first.
            guard state.elevated.viaducts.isEmpty else {
                var drawn = self
                drawn.addViaducts()
                return drawn.chunks()
            }
            // Decision 610: the street fronts not yet kept, kept first.
            guard state.facades.facadeParts.isEmpty, state.facades.reliefParts.isEmpty else {
                var drawn = self
                drawn.addFacadeParts()
                return drawn.chunks()
            }
            let snowy = look.snow
            return Set(meshes.keys).union(shadows.keys).union(nearMeshes.keys).union(farMeshes.keys).union(closeMeshes.keys).union(facadeMeshes.keys).union(standInMeshes.keys).union(ownColourNear.keys).union(ownColourFar.keys).union(props.keys).union(signs.keys).sorted().compactMap { key in
                var mesh = meshes[key] ?? Map3DMesh()
                let baseIndexCount = mesh.indices.count
                // Decision 709: the ground's lesser roads last.
                let baseSteps = Map3DFarDetail.order(&mesh, parts: baseParts[key] ?? []).indices
                mesh.append(nearMeshes[key] ?? Map3DMesh())
                var far = farMeshes[key] ?? Map3DMesh(), close = closeMeshes[key] ?? Map3DMesh(), standIn = standInMeshes[key] ?? Map3DMesh()
                // Decision 709: the simplified city and the shadows, the
                // largest first.
                var farSteps = Map3DFarDetail.order(&far, parts: farParts[key] ?? [])
                var farBoxes = far.boxes
                far.boxes = []
                far.collectsBoxes = false
                var shadows = shadows[key] ?? Map3DMesh()
                let shadowSteps = Map3DFarDetail.order(&shadows, parts: shadowParts[key] ?? []).indices
                // Decision 370: the city in the model look; decision 451:
                // its closest detail nearer its own colours.
                Map3DLook.restyle(&mesh, keeping: keptColours)
                Map3DLook.restyle(&far, keeping: keptColours)
                Map3DLook.restyle(&farBoxes, keeping: keptColours)
                Map3DLook.restyle(&close, keeping: keptColours, strength: Map3DLook.close)
                var facade = facadeMeshes[key] ?? Map3DMesh()
                Map3DLook.restyle(&facade, keeping: keptColours, strength: Map3DLook.close)
                Map3DLook.restyle(&standIn, keeping: keptColours)
                // Decision 799: a northern map's ground under snow.
                if snowy {
                    Map3DSnowGround.cover(&mesh)
                    Map3DSnowGround.cover(&far)
                }
                if let own = ownColourNear[key] { mesh.append(own) }
                // Always drawn, whatever the far view leaves out of the
                // city round it (REVIEW-L20 P2-1).
                if let own = ownColourFar[key] { Map3DFarDetail.appendAlwaysDrawn(own, to: &far, steps: &farSteps.indices) }
                // The props too: the renderer leaves out a chunk whose box
                // is off screen, which cut off a pole's top still in view.
                let propBoxes = (props[key] ?? []).compactMap { $0.bounds(from: Map3DModelCatalog.standard) }
                // And the signs, a rooftop board above its building.
                let signBoxes = (signs[key] ?? []).map { sign in
                    sign.corners.reduce((min: sign.centre, max: sign.centre)) {
                        (Map3DPoint(min($0.min.x, $1.x), min($0.min.y, $1.y), min($0.min.z, $1.z)), Map3DPoint(max($0.max.x, $1.x), max($0.max.y, $1.y), max($0.max.z, $1.z)))
                    }
                }
                let boxes = [mesh.bounds, far.bounds, shadows.bounds, close.bounds, facade.bounds, standIn.bounds].compactMap { $0 } + farBoxes.map(\.bounds)
                    + propBoxes + signBoxes
                guard let first = boxes.first else { return nil }
                let low = boxes.reduce(first.min) { Map3DPoint(min($0.x, $1.min.x), min($0.y, $1.min.y), min($0.z, $1.min.z)) }
                let high = boxes.reduce(first.max) { Map3DPoint(max($0.x, $1.max.x), max($0.y, $1.max.y), max($0.z, $1.max.z)) }
                // Decision 833: and its trees under snow.
                let chunkProps = snowy ? Map3DSnowTrees.cover(props[key] ?? []) : props[key] ?? []
                var chunk = Chunk(column: key.column, row: key.row, mesh: mesh, baseIndexCount: baseIndexCount, far: far, farBoxes: farBoxes, close: close,
                             standIn: standIn, shadows: shadows, props: chunkProps, minimum: low, maximum: high,
                             cityTops: Map3DSeeThrough.tops(column: key.column, row: key.row, of: [(mesh, baseIndexCount), (far, 0), (standIn, 0)],
                                                            boxes: farBoxes),
                             signs: signs[key] ?? [], coarse: isCoarse(key))
                chunk.facade = facade
                chunk.baseSteps = baseSteps
                chunk.farSteps = farSteps.indices
                chunk.farBoxSteps = farSteps.boxes
                chunk.shadowSteps = shadowSteps
                return chunk
            }
        }
    }
}
