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
        /// Decision 699: where the airfields' passengers board (a jet
        /// bridge's foot, or a stand with none), and how near a building
        /// stands to be their terminal (``isTerminal(_:)``).
        var terminalSpots: [(at: Map3DPoint, reach: Float)] = []
        var terminalsJoined = false
        /// Decision 610: the street fronts, by chunk.
        var facadeMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Decision 610: each chunk's buildings' street fronts as built, with
        /// the number they are kept by (``addFacadeParts()``).
        var facadeParts: [ChunkKey: [(rank: Float, mesh: Map3DMesh)]] = [:]
        /// Decision 817: each chunk's towers' reliefs (balconies, fins, bay
        /// windows) as built, kept by their number within their own budget
        /// (``Map3DFacadeVariety/chunkBudget``).
        var reliefParts: [ChunkKey: [(rank: Float, mesh: Map3DMesh)]] = [:]
        /// Decision 610: while the real buildings are built in full, the
        /// 4 m cells by their streets (``streetCells(within:)``), for
        /// ``addRealFacade``; `nil` builds no street fronts.
        var facadeStreets: Set<ChunkKey>?
        /// Decision 610 續 (review L12-1): whether the street fronts are
        /// built at all; not on a device or 3D look that never draws them,
        /// so their memory is not kept for nothing.
        var buildsFacades = true
        /// Decision 244: the street furniture, by chunk.
        var props: [ChunkKey: [Map3DInstance]] = [:]
        /// Decision 352: the signs, by chunk.
        var signs: [ChunkKey: [Map3DSign]] = [:]
        /// Decision 259: where people walk and vehicles drive.
        var streetLife = Map3DStreetLife()
        /// Decision 263: the track as laid (its centre line at the rails'
        /// height, by section), the platforms' lines, the seeded streets
        /// kept and the level crossings.
        var trackLines: [(points: [Map3DPoint], kind: TrackSectionKind)] = []
        /// Decision 947: which of ``trackLines`` are guideways (no overhead
        /// line over them).
        var guidedTrackLines: Set<Int> = []
        /// Decision 947: the edges that are guideways, and the lines of the
        /// platforms beside a suspended beam, once worked out
        /// (``guideways(of:)``).
        var guidewayEdges: (edges: [TrackEdgeID: Map3DGuideway.Kind], hung: [[Map3DPoint]])?
        /// Decision 964: the kind of each edge that is not ballast, once
        /// worked out (``trackKinds(of:)``).
        var trackKindEdges: [TrackEdgeID: Map3DTrackKind]?
        var platformLines: [[Map3DPoint]] = []
        /// Decision 321: the platforms as laid, for the station kit.
        var laidPlatforms: [LaidPlatform] = []
        /// Decision 860: the underground platforms as laid, for their
        /// props and screen doors (``addPlatformProps``) only: no canopy,
        /// building, street or shop stands by them as by those above.
        var laidUnderground: [LaidPlatform] = []
        /// Decision 436: each station's station kit system
        /// (``Map3DStationKit/Station/system``), as ``addStations`` found it.
        var stationSystems: [StationID: String] = [:]
        /// Decision 882: each real station's other name (its English one
        /// under a Chinese name), for its platforms' name boards.
        var boardSecondNames: [StationID: String] = [:]
        /// NAME-BOARD-STYLES: the boards of the stations of systems with
        /// a style of their own.
        var boardSigns: [StationID: Map3DBoardSign] = [:]
        /// Decision 874: the stations under a shell of their own
        /// (decision 827), with no kit canopy a sign could hang from.
        var shellRoofed: Set<StationID> = []
        /// Decision 936: the stations a real building stands for
        /// (decision 625), and where along each platform laid (by its
        /// place in ``laidPlatforms``) a footbridge's tower or an
        /// underpass's stairs stand (``addStationCrossings``).
        var studiedStations: Set<StationID> = []
        var crossingKeepOut: [Int: ClosedRange<Float>] = [:]
        var piers: [Map3DPoint] = []
        /// Decision 407: the viaducts laid and their piers, drawn together
        /// (``addViaducts()``) so the tracks of a pair share a pier and a
        /// truss; where the last viaduct laid ended, so the next piece of
        /// it keeps its piers' spacing.
        var viaducts = Map3DViaducts()
        /// Decision 407: on a real-world map, the base map's water areas
        /// by the 64 m cell, each area's rings cut to the cell; where the
        /// railway crosses one, it is on a truss.
        var waterCells: [ChunkKey: [[[Map3DBaseMap.Point]]]] = [:]
        /// Decision 458: the base map's woods and grass the same way, for
        /// the conifers and the bushes beside the line.
        var woodCells: [ChunkKey: [[[Map3DBaseMap.Point]]]] = [:]
        var grassCells: [ChunkKey: [[[Map3DBaseMap.Point]]]] = [:]
        /// Decision 811: the land cover of each 64 m cell round the region
        /// (``readLandCover(_:frame:)``), and the cells the city's lots
        /// stand on (``addGround(water:lots:clearOf:)``), which no forest
        /// tree of it takes.
        var landCover: [ChunkKey: LandCoverGrid.Cover] = [:]
        var lotCells = Set<ChunkKey>()
        /// Decision 458: each station building's middle, the way its
        /// front faces, its depth and width, for the bushes on its plaza.
        /// Decision 794: and its top and whether it is a big station's,
        /// for the winter event's lights and tree.
        var stationFronts: [(centre: Map3DPoint, forward: Map3DPoint, depth: Float, wide: Float, top: Float, big: Bool, strings: [Map3DPoint])] = []
        /// WINTER-LIGHTS-2: the lights on the stations' exits and stair
        /// entrances: the middle of each length and the way it runs.
        var exitLights: [(at: Map3DPoint, forward: Map3DPoint)] = []
        /// Decision 794: the winter event's trees and lights laid.
        var winterDecor: [Map3DWinterLights.Placement] = []
        /// Decision 840: the Santa Claus village's reindeer laid.
        var reindeerHerd: [Map3DReindeerHerd.Placement] = []
        /// Decision 407: the player's track a high-speed line runs on.
        var highSpeedEdges: Set<TrackEdgeID>?
        var streetEdges: [Map3DSeededStreets.Edge: Map3DBaseMap.RoadKind] = [:]
        var crossings: [Map3DLevelCrossing] = []
        /// Decision 941 (later, LEVEL-CROSSING-REAL-MAP): the roads laid on
        /// the ground (no bridge, link road or motorway) and the real
        /// lines' track laid on the ground, where they cross on the level
        /// (``addRealLevelCrossings()``).
        var groundRoadLines: [(points: [Map3DPoint], kind: Map3DBaseMap.RoadKind)] = []
        var realSurfaceLines: [[Map3DPoint]] = []
        /// Decision 322: every road's middle line and how far either side
        /// its carriageway and pavement reach, metres.
        var roadLines: [(points: [Map3DPoint], half: Float)] = []
        /// Decision 385: each of ``roadLines``' kind, and whether it is a
        /// link road; on a real-world map, the houses along them
        /// (``addFrontage``) and the land with none (``prepareNoBuild``).
        var roadKinds: [(kind: Map3DBaseMap.RoadKind, ramp: Bool)] = []
        var streetFrontage = false
        var frontage = Frontage()
        var noBuild = NoBuild()
        /// Decision 707: the airfields' runway strips, taxiways and aprons.
        var airfieldClear = AirfieldClear()
        /// Decision 707: the tallest real building round each place, which
        /// the game's own houses do not pass; `nil` without footprints.
        var lowRise: Map3DLowRise?
        /// Decision 723: the city tiles' buildings and the footprints
        /// drawn, and how much of each cell they cover: where that is
        /// little, the game's houses stand between them.
        var tileCover = RealCover()
        var footprintCover = RealCover()
        /// The corners of each station building's ground, and the
        /// shop streets still to lay beside them.
        var houseFootprints: [[Map3DPoint]] = []
        /// MRT-SHELL-CLEAR-OUTLINE: the outlines of the stations' own
        /// buildings (the Tamsui line's shells, the kit's houses, the
        /// depots' sheds), ``Map3DScene/Builder/stationOutlineMargin``
        /// wider, where a real building is left out; and the 64 m cells
        /// only they take, where no city lot goes but the real buildings
        /// round them stay (``underRailway(_:)``).
        var stationOutlines: [StationOutline] = []
        /// MRT-SHELL-CLEAR-OUTLINE: the pieces of the track and the
        /// platforms out of tunnels, with how far round them no real
        /// building stands, by the 64 m cells they reach (``onTrack(_:)``).
        var trackPieces: [ChunkKey: [(a: Map3DPoint, b: Map3DPoint, reach: Float)]] = [:]
        var outlineOnlyCells: Set<ChunkKey> = []
        /// XMAS-TREE-SIZE: the ground each station shop takes (its slab
        /// and awning), so a station's Christmas tree keeps off it.
        var shopFootprints: [[Map3DPoint]] = []
        /// Decision 331: the big stations' buildings, for their commercial
        /// kit (`addStationCommerce`).
        var bigStations: [(centre: Map3DPoint, forward: Map3DPoint, depth: Float)] = []
        var shopStreets: [(station: Map3DStationKit.Station, centre: Map3DPoint, forward: Map3DPoint, depth: Float, wide: Float,
                           cells: Set<ChunkKey>)] = []
        /// Decision 326: on a real-world map, the real lines round the
        /// scene and whether each runs under an overhead line.
        var realLines: [(points: [Map3DPoint], wired: Bool)] = []
        /// Decision 339: the 64 m cells the real lines' track runs through
        /// above the ground, which keep no city lot.
        var realTrackCells = Set<ChunkKey>()
        /// Decision 625: the real lines' track drawn (decision 402), each
        /// lane where a car shows, for the room the exterior studies keep.
        var realTrackLines: [[Map3DPoint]] = []
        /// Decision 625: the exterior studies stood.
        var stationExteriors: [Map3DStationExterior] = []
        /// Decision 837: the freight yards laid so far.
        var freightYardPlaces: [Map3DFreightYard.Place] = []
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
        /// Decision 791: the ground Hong Kong's landmarks stand on, where
        /// no footprint is drawn.
        var landmarkPlots: [PlacedSquare] = []
        /// OLD-PORT-AUDIT: the ground each of the cities' landmarks
        /// covers (``LandmarkPlan``), where no footprint is drawn.
        var landmarkPlans: [LandmarkPlan] = []
        /// Decision 879: the squares a model stands on in the place of one
        /// real building (the Wenwu temple's middle hall): the footprint
        /// whose middle is within one is not drawn again, but counts as
        /// built, so the houses along the roads round it stay
        /// (``landmarkPlots`` keeps them off its cells).
        var replacedPlots: [PlacedSquare] = []
        /// Decision 869: the suspension bridges round the scene, once found
        /// (``suspensionBridges()``).
        var placedSuspensionBridges: [Map3DSuspensionBridge.Placed]?
        /// Decision 944: the landmark bridges carrying a road round the
        /// scene, once found (``archBridges()``).
        var placedArchBridges: [Map3DArchBridgeDeck.Placed]?
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
        /// Decision 722: the triangles of the station kit's buildings among
        /// ``ownColourNear``'s, which hold the studies' too.
        var houseTriangleCount = 0
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
        /// Decision 860: the underground platforms and their stations'
        /// boxes, from the whole network.
        var undergroundStations = Map3DUndergroundStations()
        /// Decision 888: the track network's diamond crossings
        /// (``addTrack(_:)``'s).
        var diamonds: [Map3DDiamondCrossing] = []
        /// Decision 391: the base map's road bridges and their decks.
        var roadBridges = Map3DRoadBridges()
        /// Decision 834: the motorways' profiles and cuttings.
        var roadGrade = Map3DRoadGrade()
        /// Decision 865: the base map's roads' beds, level across.
        var roadBed = Map3DRoadBed()
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
                                               rank: Map3DFarDetail.rank(size: mesh.extent(fromVertex: firstVertex, fromBox: firstBox)))
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
            guard viaducts.isEmpty else {
                var drawn = self
                drawn.addViaducts()
                return drawn.chunks()
            }
            // Decision 610: the street fronts not yet kept, kept first.
            guard facadeParts.isEmpty, reliefParts.isEmpty else {
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
