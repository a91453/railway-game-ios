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
        /// Everything in the chunk at its full detail: its ground, track
        /// and roads (the first ``baseIndexCount`` indices), then its city.
        public let mesh: Map3DMesh
        /// Decision 238: how many of ``mesh``'s indices are its ground,
        /// track, roads and the player's buildings, drawn at every
        /// distance; the city's buildings follow them.
        public let baseIndexCount: Int
        /// Decision 238: the city's buildings simplified, drawn instead of
        /// the rest of ``mesh`` when the chunk is far from the camera
        /// (``Map3DCamera/wantsDetail(minimum:maximum:)``).
        public let far: Map3DMesh
        /// Decision 455: the simplified city's boxes, drawn with ``far``
        /// as instances of one box (``Map3DBoxInstance``).
        public let farBoxes: [Map3DBoxInstance]
        /// Decision 267: the city's smallest things, drawn only close up
        /// (``Map3DCamera/wantsClose(minimum:maximum:wasClose:)``) on top
        /// of the full mesh.
        public let close: Map3DMesh
        /// What stands in for some of ``close``'s models (the player's kit
        /// buildings' boxes): drawn with the full mesh, but not when
        /// ``close`` is, which they would hide.
        public let standIn: Map3DMesh
        /// Decision 232: the soft shadows on its ground, drawn after
        /// everything else.
        public let shadows: Map3DMesh
        /// Decision 244: its street furniture, drawn as instances of
        /// ``Map3DModelPack/standard``'s models when the chunk is drawn in
        /// full.
        public let props: [Map3DInstance]
        public let minimum: Map3DPoint
        public let maximum: Map3DPoint
        /// Decision 342: the top of its city (the rest of ``mesh`` and
        /// ``far``) in each of its ``Map3DSeeThrough/cells`` by
        /// ``Map3DSeeThrough/cells`` squares, row by row from the north
        /// west; `-infinity` where none stands.
        public let cityTops: [Float]
        /// Decision 352: its signs, billboards and screens, drawn when it
        /// is drawn in full.
        public let signs: [Map3DSign]
        /// Decision 368: built without its city in full and its closest
        /// detail (more than ``Map3DScene/detailRadius`` from where the
        /// camera looked), so drawn simplified, as from afar, until it is
        /// built again in full (``Map3DStreaming/Window``).
        public let coarse: Bool
        /// Decision 610: what stands out of the real buildings' street
        /// fronts (arcade pillars, window grilles, air conditioners, blade
        /// signs, rooftop rooms): drawn as ``close`` is, but left out on
        /// Battery Saver and when memory runs short
        /// (``Map3DRealFacade/draws(quality:lowPower:heat:tier:)``).
        public var facade = Map3DMesh()
        /// Decision 709: how much of its ground, track and roads (the
        /// first ``baseIndexCount`` of ``mesh``'s indices), of ``far``, of
        /// ``farBoxes`` and of ``shadows`` each level draws from afar
        /// (``Map3DFarDetail``): each is kept the largest things first.
        public var baseSteps = Map3DFarDetail.Steps()
        public var farSteps = Map3DFarDetail.Steps()
        public var farBoxSteps = Map3DFarDetail.Steps()
        public var shadowSteps = Map3DFarDetail.Steps()

        /// Decision 455: ``far`` and ``farBoxes`` as one mesh, the boxes as
        /// the app's shader draws them.
        public var farWithBoxes: Map3DMesh {
            var mesh = far
            mesh.append(Map3DBoxInstance.mesh(farBoxes))
            return mesh
        }

        /// The triangles of ``far`` and ``farBoxes``.
        public var farTriangleCount: Int { far.triangleCount + farBoxes.reduce(0) { $0 + $1.triangleCount } }

        /// Whether it has no simplified city.
        public var farIsEmpty: Bool { far.isEmpty && farBoxes.isEmpty }
    }

    /// The side of a chunk, in metres.
    public static let chunkSize: Float = 512
    /// The most of the world a scene covers each way from the middle of
    /// what is built, in metres: a whole island's map would not fit a
    /// phone's memory as one scene (decision 89).
    public static let reach: Double = 6_000
    /// What is shown round what is built, in metres.
    public static let margin: Double = 1_500
    /// Decision 368: how far from where the camera looks a real-world
    /// map's chunks are built with the city in full and its closest
    /// detail, in metres; further out only the simplified city. Following
    /// a train (at most 4 times its usual distance) draws the city in full
    /// some 1.4 km round it (``Map3DCamera/wantsDetail(minimum:maximum:wasDetailed:)``).
    /// The whole 12 km scene in full was 41 million vertices round Taipei
    /// on the high-speed demo, 1.9 GB, twice that once on the GPU too: over
    /// the 3.4 GB an iPhone 17 Pro lets the app have.
    public static let detailRadius: Float = 2_000
    /// How far above the track's height the rails' tops are drawn, in
    /// metres, the trains with them (decision 231). The game lays track on
    /// the ground at the ground's height; drawn there, the bed 0.35 m below
    /// the rails was under the ground and the plazas, and only the rails'
    /// tops showed. Lifted, the bed's top stands 0.5 m over the ground,
    /// over the real map's cover, roads and the shadows (up to
    /// ``Map3DShadow/lift``, 0.4 m), which would otherwise paint over the
    /// ballast where track crosses a road or a park.
    public static let railLift: Float = 0.85

    /// The world point (in world units) at the scene's origin.
    public let originX: Double
    public let originY: Double
    /// The part of the world the scene covers, in world units.
    public let region: WorldRegion
    public let chunks: [Chunk]
    /// Decision 259: where its people walk and its vehicles drive.
    public let streetLife: Map3DStreetLife
    /// Decision 263: where its seeded streets cross the track.
    let levelCrossings: [Map3DLevelCrossing]
    /// Decision 270: its seeded streets, for the 2D map to draw the same.
    public let seededStreets: SeededStreetPlan
    /// Decision 339: on a real-world map, the real timetables' trains.
    public let realTrains: Map3DRealTrains?
    /// Decision 359: the player's track, where it runs in a tunnel and
    /// the ground drawn over it.
    public let trackCover: Map3DTrackCover
    /// Decision 625: the real stations' exterior studies stood in the scene.
    let stationExteriors: [Map3DStationExterior]
    /// Decision 794: the winter event's trees and lights, drawn only while
    /// it shows its decorations (``Map3DWinterLights/add(to:pack:eye:reach:)``).
    public let winterLights: Map3DWinterLights
    /// Decision 840: the Santa Claus village's reindeer, drawn all year
    /// (``Map3DReindeerHerd/add(to:pack:eye:reach:)``).
    public let reindeerHerd: Map3DReindeerHerd
    /// Decision 837: where its freight yards stand (``Map3DFreightYard``).
    public let freightYards: [Map3DFreightYard.Place]
    /// Decision 847: which of its platforms have screen doors, for the
    /// underground ones drawn through the ground (``Map3DXRay``).
    public let screenDoors: Map3DScreenDoors.Plan
    /// Decision 517 續 (BUILD3D-3): the ground as drawn, for taps
    /// (``Map3DPick/ground(of:world:)``).
    public let drawnGround: Map3DGroundGrid

    public var triangleCount: Int { chunks.reduce(0) { $0 + $1.mesh.triangleCount } }

    /// Decision 709: the triangles one layer of the scene added as it was
    /// built, by where they are drawn: with the ground at every distance
    /// (`base`), with the city in full (`near`), simplified (`far`, and
    /// its `boxes`), close up (`close`) and blended over the ground
    /// (`shadows`).
    struct LayerTriangles: Equatable, Sendable {
        var layer: String
        var base = 0, near = 0, far = 0, boxes = 0, close = 0, shadows = 0
    }

    /// Decision 709: what each layer added, in the order they were built,
    /// for the far view's report (`Map3DFarViewTests`).
    let layers: [LayerTriangles]

    /// Decision 820: how long each step of building the scene took, in
    /// seconds, in the order they ran, for the build-time report
    /// (`Map3DSceneBuildTimeReportTests`). Not part of what is drawn.
    let steps: [(step: String, seconds: Double)]

    /// Decision 820: the `count` steps of building it that took longest,
    /// each step's times summed, the longest first, for the problem
    /// report's line (``Map3DSceneBuildTime/slowest``).
    public func slowestSteps(_ count: Int) -> [Map3DSceneBuildTime.Step] {
        var summed: [(step: String, seconds: Double)] = []
        for (step, seconds) in steps {
            if let at = summed.firstIndex(where: { $0.step == step }) { summed[at].seconds += seconds } else { summed.append((step, seconds)) }
        }
        return summed.sorted { $0.seconds > $1.seconds }.prefix(count).map { Map3DSceneBuildTime.Step(name: $0.step, seconds: $0.seconds) }
    }

    /// Decision 585 PR-3: the water as drawn within `radius` metres of
    /// `centre`, for the ferry piers to stand at its shore. The ground's
    /// faces (the first ``Chunk/baseIndexCount`` indices) no more than 4 m
    /// over `centre`'s, the top one at a point deciding: the base map's
    /// water areas, waterways and cover over them, or the ground's own
    /// water cells, as the player sees them (the base map's water areas
    /// alone missed a Gushan basin's further 70 m). And the city's
    /// buildings over it (the faces after them more than
    /// ``DrawnWater/buildingRise`` over `centre` and not upright: roofs
    /// and floors), which stand on the water drawn where the real ones
    /// stand on a quay or over the water (Gushan's ferry terminal,
    /// screenshot run 41927167376).
    func drawnWater(round centre: Map3DPoint, radius: Float) -> DrawnWater {
        var water = DrawnWater()
        let top = centre.y + 4, rise = centre.y + DrawnWater.buildingRise
        for chunk in chunks {
            let vertices = chunk.mesh.vertices, indices = chunk.mesh.indices
            var k = 0
            while k + 2 < indices.count {
                let a = vertices[Int(indices[k])], b = vertices[Int(indices[k + 1])], c = vertices[Int(indices[k + 2])]
                let ground = k < chunk.baseIndexCount
                k += 3
                if ground {
                    guard max(a.y, b.y, c.y) <= top else { continue }
                } else {
                    let area = abs((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)) / 2
                    guard max(a.y, b.y, c.y) > rise, area > 0.5 else { continue }
                }
                let low = (x: min(a.x, b.x, c.x), z: min(a.z, b.z, c.z)), high = (x: max(a.x, b.x, c.x), z: max(a.z, b.z, c.z))
                guard high.x >= centre.x - radius, low.x <= centre.x + radius, high.z >= centre.z - radius, low.z <= centre.z + radius
                else { continue }
                water.add(DrawnWater.Face(a: a, b: b, c: c), low: low, high: high, building: !ground)
            }
        }
        return water
    }

    /// Decision 585 PR-3: ground faces by the 8 m square, to ask of a point
    /// whether its top face is water (``drawnWater(round:radius:)``).
    struct DrawnWater {
        struct Face {
            let a: Map3DVertex, b: Map3DVertex, c: Map3DVertex
        }

        static let square: Float = 8
        /// A face of the city this far over the centre's height, metres,
        /// is a building's (a quay's paving and the street's small things
        /// lie lower).
        static let buildingRise: Float = 2
        private var squares: [Int64: [Face]] = [:]
        private var buildings: [Int64: [Face]] = [:]

        private static func key(_ column: Int, _ row: Int) -> Int64 { Int64(column) << 32 | Int64(UInt32(bitPattern: Int32(row))) }

        private static func key(x: Float, z: Float) -> Int64 {
            key(Int((x / square).rounded(.down)), Int((z / square).rounded(.down)))
        }

        mutating func add(_ face: Face, low: (x: Float, z: Float), high: (x: Float, z: Float), building: Bool = false) {
            let s = Self.square
            for column in Int((low.x / s).rounded(.down))...Int((high.x / s).rounded(.down)) {
                for row in Int((low.z / s).rounded(.down))...Int((high.z / s).rounded(.down)) {
                    if building { buildings[Self.key(column, row), default: []].append(face) } else { squares[Self.key(column, row), default: []].append(face) }
                }
            }
        }

        private static func covers(_ face: Face, x: Float, z: Float) -> Bool {
            func side(_ p: Map3DVertex, _ q: Map3DVertex) -> Float { (q.x - p.x) * (z - p.z) - (q.z - p.z) * (x - p.x) }
            let d1 = side(face.a, face.b), d2 = side(face.b, face.c), d3 = side(face.c, face.a)
            return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
        }

        /// Whether the top face over (`x`, `z`) is water; `false` with none.
        func isWater(x: Float, z: Float) -> Bool {
            guard let faces = squares[Self.key(x: x, z: z)] else { return false }
            var best: (y: Float, water: Bool)?
            for face in faces where Self.covers(face, x: x, z: z) {
                let y = (face.a.y + face.b.y + face.c.y) / 3
                if best.map({ y > $0.y + 0.001 }) ?? true { best = (y, abs(face.a.layer - Map3DVertex.water) < 0.01 || abs(face.a.layer - Map3DVertex.ice) < 0.01) }
            }
            return best?.water ?? false
        }

        /// Whether a building of the city stands over (`x`, `z`).
        func isBuilt(x: Float, z: Float) -> Bool {
            buildings[Self.key(x: x, z: z)]?.contains { Self.covers($0, x: x, z: z) } ?? false
        }

        /// Water a boat can take: drawn as water, no building over it.
        func isOpenWater(x: Float, z: Float) -> Bool {
            isWater(x: x, z: z) && !isBuilt(x: x, z: z)
        }
    }

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
}
