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

    /// The part of `world` a scene covers and its origin (world units):
    /// what is built and ``margin`` round it, at most ``reach`` each way
    /// from its middle; with nothing built, round the map's middle.
    /// Decision 313, later (2026-10-21, the owner's iPhone: the high-speed
    /// demo's 3D map opened over Sun Moon Lake, a new real-world game's
    /// over the mountains, the middle of what is built or of the whole
    /// island): with `focus`, the point the 2D map looked at (kept within
    /// the map), the middle, and what is built and the focus with
    /// ``margin`` round them, at most ``reach`` each way from it.
    static func frame(world: GameWorld, focus: (x: Double, y: Double)?) -> (region: WorldRegion, originX: Double, originY: Double) {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let mapRegion = WorldRegion(bounds: world.bounds)
        let built = WorldRegion.built(in: world)
        let focus = focus.map { (x: min(max($0.x, mapRegion.minX), mapRegion.maxX), y: min(max($0.y, mapRegion.minY), mapRegion.maxY)) }
        let middle = focus ?? built.map { (x: ($0.minX + $0.maxX) / 2, y: ($0.minY + $0.maxY) / 2) }
            ?? (x: (mapRegion.minX + mapRegion.maxX) / 2, y: (mapRegion.minY + mapRegion.maxY) / 2)
        let reach = Self.reach * metre, margin = Self.margin * metre
        var shown = built ?? WorldRegion(minX: middle.x, minY: middle.y, maxX: middle.x, maxY: middle.y)
        if focus != nil {
            shown = WorldRegion(minX: min(shown.minX, middle.x), minY: min(shown.minY, middle.y),
                                maxX: max(shown.maxX, middle.x), maxY: max(shown.maxY, middle.y))
        }
        let wanted = WorldRegion(minX: shown.minX - margin, minY: shown.minY - margin, maxX: shown.maxX + margin, maxY: shown.maxY + margin)
        let region = WorldRegion(
            minX: max(mapRegion.minX, max(wanted.minX, middle.x - reach)), minY: max(mapRegion.minY, max(wanted.minY, middle.y - reach)),
            maxX: min(mapRegion.maxX, min(wanted.maxX, middle.x + reach)), maxY: min(mapRegion.maxY, min(wanted.maxY, middle.y + reach))
        )
        return (region, middle.x.rounded(), middle.y.rounded())
    }

    /// The part of `world` a scene built round `focus` covers
    /// (``frame(world:focus:)``), for a cache of scenes to tell whether it
    /// holds another focus (``holds(_:in:world:)``).
    public static func region(world: GameWorld, focus: (x: Double, y: Double)?) -> WorldRegion {
        frame(world: world, focus: focus).region
    }

    /// Whether a scene covering `region` holds `focus` (kept within the
    /// map) with half ``margin`` round it, as far as the map goes; any
    /// scene holds no focus at all. Decision 313, later (PR #873–#910
    /// review): a scene round a focus with nothing built near covers only
    /// ``margin`` round it, less than a ``FocusArea``'s square, so a focus
    /// in the same square can be off it.
    public static func holds(_ focus: (x: Double, y: Double)?, in region: WorldRegion, world: GameWorld) -> Bool {
        guard let focus else { return true }
        let map = WorldRegion(bounds: world.bounds)
        let half = margin / 2 * Double(WorldCoordinate.unitsPerMetre)
        let x = min(max(focus.x, map.minX), map.maxX), y = min(max(focus.y, map.minY), map.maxY)
        return region.minX <= max(map.minX, x - half) && min(map.maxX, x + half) <= region.maxX
            && region.minY <= max(map.minY, y - half) && min(map.maxY, y + half) <= region.maxY
    }

    /// Decision 313, later: which square of half ``reach`` a scene's focus
    /// falls in. A scene built round a focus in the same square is reused
    /// when it holds the new focus (``holds(_:in:world:)``), so the 3D map
    /// opens on a scene already built; a focus further off builds anew.
    public struct FocusArea: Hashable, Sendable {
        public let column: Int64
        public let row: Int64

        public init(x: Double, y: Double) {
            let side = Map3DScene.reach / 2 * Double(WorldCoordinate.unitsPerMetre)
            column = Int64((x / side).rounded(.down))
            row = Int64((y / side).rounded(.down))
        }
    }

    /// Decision 270: the seeded streets of `world` alone, as the scene
    /// would lay them (decision 263: the track and platforms first), for
    /// the 2D map: the track and platforms are laid, the city is not, so
    /// this is a small part of building the scene. None on a real-world
    /// map.
    public static func seededStreets(world: GameWorld, snapshot: RailwaySnapshot? = nil, skyline: CitySkyline? = nil) -> SeededStreetPlan {
        guard world.geoAnchor == nil else { return SeededStreetPlan(edges: [:]) }
        let frame = frame(world: world, focus: nil)
        var builder = Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: world)
        let snapshot = snapshot ?? world.railwaySnapshot()
        let cleared = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        builder.addSeededStreets(skyline ?? CitySkyline(world: world), clearOf: cleared)
        return SeededStreetPlan(edges: builder.streetEdges)
    }

    /// The scene of `world`: what is built and ``margin`` round it, at most
    /// ``reach`` each way from its middle; on a map with nothing built,
    /// round the map's middle. With `focus` (world units, the point the 2D
    /// map looked at), round it instead (decision 313, later).
    /// On a real-world map, `baseMap`'s ground and `cityTiles`' buildings,
    /// and `heights`' ground where the world has not read its own.
    /// Decision 314: `lineBands` beside the track. Decision 326: an
    /// overhead line over the track, but along `railways`' lines run
    /// without one. Decision 331: on a real-world map, `temples` where
    /// they stand, and the park kit's scenes in the base map's parks.
    /// Decision 389: on a real-world map, `footprints`' buildings, and the
    /// city's own only where there are none.
    public init(world: GameWorld, snapshot: RailwaySnapshot? = nil, skyline: CitySkyline? = nil, focus: (x: Double, y: Double)? = nil,
                baseMap: BaseMapTiles? = nil, cityTiles: [CityTileArea] = [], footprints: FootprintTiles? = nil, heights: HeightGrid? = nil,
                lineBands: Map3DLineBands? = nil, railways: RealRailways? = nil, temples: RealTemples? = nil, noBuild: RealNoBuildLand? = nil) {
        // Decision 368: on a map the camera builds ahead on (decision 358),
        // the city in full only round the middle, which the window builds
        // in full as the camera comes near.
        self.init(world: world, snapshot: snapshot, skyline: skyline, frame: Self.frame(world: world, focus: focus), baseMap: baseMap,
                  cityTiles: cityTiles, footprints: footprints, heights: heights, lineBands: lineBands, railways: railways, temples: temples,
                  noBuild: noBuild,
                  detail: Map3DStreaming.streams(world) ? Map3DPoint(0, 0, 0) : nil)
    }

    /// Decision 358: chunks `keys` of `streaming`'s scene (its origin),
    /// each built as the whole scene builds it, from the same files: a
    /// scene of the squares round them with ``Map3DStreaming/apron`` more
    /// each way, on the map, of which only `keys`' chunks are kept (a
    /// chunk with nothing in it is none). Its real trains and street life
    /// are not kept. Decision 359 (續): `trackCover` is the whole scene's
    /// (``trackCover``), worked out again when `nil`. Decision 368: with
    /// `detail`, a scene point, only the chunks within ``detailRadius`` of
    /// it in full (``Chunk/coarse``).
    public static func chunks(_ keys: some Collection<Map3DStreaming.Key>, of streaming: Map3DStreaming, world: GameWorld,
                              snapshot: RailwaySnapshot? = nil, skyline: CitySkyline? = nil, baseMap: BaseMapTiles? = nil,
                              cityTiles: [CityTileArea] = [], footprints: FootprintTiles? = nil, heights: HeightGrid? = nil,
                              lineBands: Map3DLineBands? = nil, railways: RealRailways? = nil, temples: RealTemples? = nil,
                              noBuild: RealNoBuildLand? = nil,
                              trackCover: Map3DTrackCover? = nil, detail: Map3DPoint? = nil) -> [Chunk] {
        guard let box = streaming.region(of: keys) else { return [] }
        let apron = Map3DStreaming.apron * Double(WorldCoordinate.unitsPerMetre), map = streaming.map
        let region = WorldRegion(minX: max(map.minX, box.minX - apron), minY: max(map.minY, box.minY - apron),
                                 maxX: min(map.maxX, box.maxX + apron), maxY: min(map.maxY, box.maxY + apron))
        guard region.minX < region.maxX, region.minY < region.maxY else { return [] }
        // Decision 359: the whole network's track cover (`trackCover`, the
        // scene's, or worked out again), which lays the tunnels.
        let scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, frame: (region, streaming.originX, streaming.originY),
                               baseMap: baseMap, cityTiles: cityTiles, footprints: footprints, heights: heights, lineBands: lineBands,
                               railways: railways, temples: temples, noBuild: noBuild, trackCover: trackCover, detail: detail)
        let wanted = Set(keys)
        return scene.chunks.filter { wanted.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }
    }

    /// Decision 358: the scene of `frame`'s region round its origin (world
    /// units), built as the public initializer builds it. Decision 359:
    /// with `trackCover`, or the network's own when `nil`. Decision 368:
    /// with `detail`, the city in full only within ``detailRadius`` of it.
    init(world: GameWorld, snapshot: RailwaySnapshot?, skyline: CitySkyline?, frame: (region: WorldRegion, originX: Double, originY: Double),
         baseMap: BaseMapTiles?, cityTiles: [CityTileArea], footprints footprintTiles: FootprintTiles? = nil, heights: HeightGrid?,
         lineBands: Map3DLineBands?, railways: RealRailways?, temples: RealTemples?, noBuild: RealNoBuildLand? = nil,
         trackCover: Map3DTrackCover? = nil, detail: Map3DPoint? = nil) {
        (region, originX, originY) = frame

        var builder = Builder(originX: originX, originY: originY, region: region, world: world, heights: heights)
        builder.detail = detail
        let snapshot = snapshot ?? world.railwaySnapshot()
        // Decision 234: on a real-world map, the base map's water, cover
        // and roads; the ground's own water then gives way to its finer
        // shores.
        var real: Map3DBaseMap?
        if let baseMap, let frame = RealWorldFrame(world: world) {
            real = Map3DBaseMap(tiles: baseMap, frame: frame, region: region, originX: originX, originY: originY)
            // Decision 385: the city's low homes and shops along the real
            // roads, and none on the land OpenStreetMap keeps clear.
            builder.streetFrontage = true
            if let noBuild { builder.prepareNoBuild(noBuild, frame: frame) }
        }
        // Decision 359 (續): the whole network's, so a chunk built apart
        // lays a bore beside another as the whole scene does; decision 375:
        // first, as its trenches are cut out of the ground and what lies
        // on it.
        builder.trackCover = trackCover ?? Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround(water: real == nil)
        let taken = real.map { builder.addBaseMap($0) } ?? Builder.TakenGround()
        let cleared = builder.addTrack(snapshot)
        builder.addTrenches()
        if let lineBands { builder.addLineBands(lineBands, snapshot: snapshot) }
        builder.addPlatforms(snapshot)
        builder.addPortals(snapshot)
        self.trackCover = builder.trackCover
        // Decision 339: the real lines' track, clear of the player's, and
        // their trains on it.
        if let railways, let operations = railways.operations, let frame = RealWorldFrame(world: world) {
            let region = builder.region, margin = Map3DRealTrains.margin * Builder.metre
            let traffic = RealTrainTraffic(operations: operations, bought: Set(world.acquisitions.map(\.realLine))) { coordinate in
                let at = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return at.x >= region.minX - margin && at.x <= region.maxX + margin && at.y >= region.minY - margin && at.y <= region.maxY + margin
            }
            // Decision 402: the real tracks, clear of the lines the
            // player bought.
            let bought = world.acquisitions.compactMap { acquisition -> (system: String, shape: [RealRailways.Coordinate])? in
                let parts = acquisition.realLine.split(separator: ":", maxSplits: 1).map(String.init)
                guard acquisition.kind == .railway, parts.count == 2, let line = operations.system(id: parts[0])?.lines.first(where: { $0.id == parts[1] }) else { return nil }
                return (parts[0], line.shape)
            }
            realTrains = Map3DRealTrains(traffic: traffic, structures: railways.structures, railTracks: railways.tracks, bought: bought,
                                         frame: frame, snapshot: snapshot, builder: &builder)
        } else {
            realTrains = nil
        }
        // Decision 238: the city twice, in full and simplified for afar.
        let city = skyline ?? CitySkyline(world: world)
        // Decision 370: Taipei 101 and Taipei Main Station, clear of the
        // track; on ground no real building, temple, scene or city lot
        // takes.
        let landmarks = RealWorldFrame(world: world).map { builder.addTaipeiLandmarks(frame: $0) } ?? [:]
        let landmarkCells = landmarks.values.reduce(into: Set<ChunkKey>()) { $0.formUnion($1) }
        // Decision 321: the stations' canopies and buildings from the
        // station kit, a plaza where a building stands; Taipei's the
        // landmark, where it stands (decision 370).
        let stations = cleared.union(builder.addStations(snapshot, frame: RealWorldFrame(world: world), shops: false,
                                                         drawnElsewhere: landmarks[.taipeiMainStation] == nil ? [] : [.taipei]))
        // Decision 263: on a map not of the real world, seeded streets
        // between the lots, clear of the track and the platforms but where
        // they cross it, and of the stations' buildings.
        if real == nil, world.geoAnchor == nil { builder.addSeededStreets(city, clearOf: cleared) }
        seededStreets = SeededStreetPlan(edges: builder.streetEdges)
        // Decision 322: the shops, clear of the streets.
        builder.addShopStreets()
        // Decision 326: the overhead line, its masts clear of the platforms;
        // on a real-world map, none along the real lines without one.
        if let railways, let frame = RealWorldFrame(world: world) { builder.addRealLines(railways, frame: frame) }
        builder.addOverheadLine()
        // Decision 244: no street furniture where the track runs (nor
        // where a station's building or a landmark stands).
        builder.removeProps(on: stations.union(landmarkCells))
        // Decision 229 續: the street lights' pools, seen at night.
        builder.addLampPools()
        // Decision 239: on a real-world map, the real buildings round
        // Kaohsiung and Taichung Stations, and no city lot where they
        // stand.
        let frame = real == nil ? nil : RealWorldFrame(world: world)
        builder.target = .near
        var standing = landmarkCells.union(frame.map { builder.addRealBuildings(cityTiles, frame: $0, clearOf: stations.union(landmarkCells)) } ?? [])
        // Decision 385: the airports' own buildings; decision 389: only
        // with no footprints, which have them.
        if footprintTiles == nil, let noBuild, let frame { builder.addAirportBuildings(noBuild, frame: frame, clearOf: stations.union(landmarkCells)) }
        // Decision 331: the real temples, on no station or real building.
        if let temples, let frame = RealWorldFrame(world: world) {
            standing.formUnion(builder.addTemples(temples, frame: frame, clearOf: stations.union(standing)))
            builder.target = .near
        }
        // Decision 331: the commercial kit's scenes before the big
        // stations, on no real building or temple.
        standing.formUnion(builder.addStationCommerce(clearOf: standing))
        builder.target = .near
        // Decision 331: the park kit's scenes in the real parks, on no
        // station, real building, temple or commercial scene; no city lot
        // on them.
        if let real {
            standing.formUnion(builder.addParks(real, clearOf: stations.union(standing)))
            builder.target = .near
        }
        // Decision 389: the footprints' buildings, on no station, landmark,
        // real building, temple or kit's scene; no city lot on them.
        var footprints: Map3DFootprints?
        if let frame, let tiles = footprintTiles {
            footprints = Map3DFootprints(tiles: tiles, frame: frame, region: builder.region)
        }
        let beforeFootprints = standing
        if let footprints { standing.formUnion(builder.addFootprints(footprints, clearOf: stations.union(landmarkCells), takenBy: beforeFootprints)) }
        builder.addCity(city, clearOf: stations.union(builder.realTrackCells), takenBy: taken.whole.union(standing), besideRoads: taken.byRoads)
        builder.target = .far
        if let frame { builder.addRealBuildings(cityTiles, frame: frame, clearOf: stations.union(landmarkCells)) }
        if let footprints { builder.addFootprints(footprints, clearOf: stations.union(landmarkCells), takenBy: beforeFootprints) }
        if footprintTiles == nil, let noBuild, let frame { builder.addAirportBuildings(noBuild, frame: frame, clearOf: stations.union(landmarkCells)) }
        builder.addCity(city, clearOf: stations.union(builder.realTrackCells), takenBy: taken.whole.union(standing), besideRoads: taken.byRoads)
        builder.target = .base
        builder.addPlacedBuildings()
        chunks = builder.chunks()
        streetLife = builder.streetLife
        levelCrossings = builder.crossings
    }
}

// MARK: - Colours

/// The 3D map's colours (F 台灣版＋): soft, bright and a little warm; the
/// player's buildings the warm yellow of the 2D map (decision 205).
public enum Map3DPalette {
    /// Decision 241: the ground and parks of the game's 2D map
    /// (`BaseMapStyle`'s light look: land #ECEEF6, park #D2E8C4), a little
    /// deeper and cooler so they read under the warm sun; the water a
    /// clearer blue than the 2D map's #C3CEEA, so a river never reads as
    /// one of the navy roads, and the farms a softer green.
    /// Decision 370 ((e), ``Map3DLook``): the ground the icon's pale
    /// #ECEEF6; the water, parks, farms and plazas the reference's
    /// `mapbox-palette.js` watercolor and atlas colours.
    public static let ground = Map3DColor.rgb(0xECEEF6)
    public static let water = Map3DColor.rgb(0x86D3E3)
    /// Decision 272: the parks' green and the trees' livelier, nearer the
    /// owner's sunny target picture; the ground and roads as decision 241.
    public static let park = Map3DColor.rgb(0xC8DFC0)
    public static let farm = Map3DColor.rgb(0xE2EBCF)
    public static let plaza = Map3DColor.rgb(0xEAD9BF)
    /// Decision 370: a step deeper, so the track stands off the pale ground
    /// and the trains off their bed.
    public static let ballast = Map3DColor.rgb(0x7E786D)
    public static let embankment = Map3DColor.rgb(0x9DB07E)
    public static let rail = Map3DColor.rgb(0x6E7379)
    public static let railTop = Map3DColor.rgb(0xC9CED4)
    public static let concrete = Map3DColor.rgb(0xCFCBC2)
    public static let bridge = Map3DColor.rgb(0x8E9CA8)
    public static let portal = Map3DColor.rgb(0x8B9096)
    /// Decision 359 (續): a tunnel's walls the ground's cool grey a step
    /// deeper, its roof and floor deeper still (the bore's shade), and its
    /// lamps the icon's warm yellow, lighter.
    public static let tunnelWall = Map3DColor.rgb(0xA9AFBE)
    public static let tunnelLining = Map3DColor.rgb(0x6E7487)
    public static let tunnelLamp = Map3DColor.rgb(0xFFE2A6)
    public static let platform = Map3DColor.rgb(0xDCD6C8)
    public static let platformEdge = Map3DColor.rgb(0xF2C94C)
    /// Taiwanese station signs' blue, on the canopies.
    public static let canopy = Map3DColor.rgb(0x2F6DB5)
    public static let roof = Map3DColor.rgb(0xC4C8D6)
    public static let arcade = Map3DColor.rgb(0x6F6A64)
    public static let tankBlue = Map3DColor.rgb(0x3B7DD8)
    public static let tankSteel = Map3DColor.rgb(0xC8CDD2)
    public static let trunk = Map3DColor.rgb(0x8A6A4F)
    public static let crown = Map3DColor.rgb(0x8DC27A)
    /// The player's buildings (decision 205) and the navy rim that marks
    /// them apart from the city's offices in grey (the art direction's
    /// note).
    public static let player = Map3DColor.rgb(0xFFC86B)
    public static let playerRoof = Map3DColor.rgb(0xFFE2A6)
    public static let playerRim = Map3DColor.rgb(0x26385C)

    /// Decision 234: the base map's land cover, a little deeper than the
    /// 2D map's (its `landcover` and `park`) so it reads on the lit
    /// ground. Decision 241: the 2D map's own colours, deepened alike.
    static func cover(_ cover: Map3DBaseMap.Cover) -> UInt32 {
        switch cover {
        // Decision 393: decision 370's farm, as the game's own fields.
        case .farmland: farm
        case .grass: rgb(0xE2EBCF)
        case .sand: rgb(0xF2E2BD)
        case .wetland: rgb(0xD7E4EA)
        case .wood: rgb(0xB6DDCA)
        case .park: park
        case .water: water
        }
    }

    /// Decision 241: the roads drawn as a city map draws them (the
    /// reference's `city_map_reference_clean` ink look, deepest for the
    /// biggest), in the game's navy rather than its black: the motorways
    /// the navy of the app's text, the main roads its map shadow, lanes
    /// its accent. Plain (untextured) so they read from afar.
    /// Decision 370 ((e)): a mid grey darker than the ground (CIE L* 62,
    /// 64, 66, 69, the smaller roads a step lighter), with the hue of the
    /// icon's navy #262C57 (CIE LCh h −67°) at chroma 6, so it still reads
    /// as asphalt; lit by its street lights after dark (``Map3DLook``).
    static func road(_ kind: Map3DBaseMap.RoadKind) -> UInt32 {
        switch kind {
        case .motorway, .trunk: rgb(0x9595A0)
        case .primary, .secondary: rgb(0x9B9AA5)
        case .tertiary: rgb(0xA09FAA)
        case .minor, .service: rgb(0xA8A7B2)
        }
    }

    /// Decision 241: the sidewalks, paved. Decision 370: a white kerb that
    /// outlines the grey road.
    public static let sidewalk = Map3DColor.rgb(0xF7F7F4)
    /// Decision 370: the centre line in the icon's warm yellow #FFC86B; the
    /// platform edge keeps the safety yellow #F2C94C.
    public static let centreLine = Map3DColor.rgb(0xFFC86B)

    /// Row house walls: `city_world_reference`'s shophouse palette (white
    /// 4, #F2E2D6 2, #E0D0C8 1, #D6C2B0 1) and four tile colours common in
    /// Taiwan.
    static let houseWalls: [(color: UInt32, weight: Float)] = [
        (rgb(0xFFFFFF), 4), (rgb(0xF2E2D6), 2), (rgb(0xE0D0C8), 1), (rgb(0xD6C2B0), 1),
        (rgb(0xE8D8B8), 1), (rgb(0xC9D3D6), 1), (rgb(0xD9B9A2), 1), (rgb(0xBFC8B4), 1),
    ]
    static let officeWalls: [UInt32] = [rgb(0xAEBFCC), rgb(0xC2CCD4), rgb(0x9FB3C2)]
    /// Decision 242: fair-faced concrete, in the cool light greys of the
    /// map's ground and roofs (decision 241) rather than a photograph's.
    static let concreteWalls: [UInt32] = [rgb(0xC9CCD5), rgb(0xBFC3CE), rgb(0xD3D4DA)]

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
        let originX: Double
        let originY: Double
        let region: WorldRegion
        let world: GameWorld
        var meshes: [ChunkKey: Map3DMesh] = [:]
        var shadows: [ChunkKey: Map3DMesh] = [:]
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
        }
        var target = Target.base
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
        var platformLines: [[Map3DPoint]] = []
        /// Decision 321: the platforms as laid, for the station kit.
        var laidPlatforms: [LaidPlatform] = []
        var piers: [Map3DPoint] = []
        var streetEdges: [Map3DSeededStreets.Edge: Map3DBaseMap.RoadKind] = [:]
        var crossings: [Map3DLevelCrossing] = []
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
        /// The corners of each station building's ground, and the
        /// shop streets still to lay beside them.
        var houseFootprints: [[Map3DPoint]] = []
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
        var nearMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Decision 370: colours the model look leaves as they are besides
        /// ``Map3DLook``'s own (the lines' bands).
        var keptColours = Set<UInt32>()
        var farMeshes: [ChunkKey: Map3DMesh] = [:]
        var closeMeshes: [ChunkKey: Map3DMesh] = [:]
        var standInMeshes: [ChunkKey: Map3DMesh] = [:]
        /// Whether what is being built is the simplified city.
        var isFar: Bool { target == .far }
        /// The ground's heights at the 64 m grid's corners, in metres, by
        /// row and column, as ``addGround()`` lays them.
        var corners: [ChunkKey: Float] = [:]
        /// Decision 359 (續): the whole network's track, for the tunnels
        /// beside a tunnel (``addBore(_:into:)``).
        var trackCover = Map3DTrackCover()
        /// Decision 391: the base map's road bridges and their decks.
        var roadBridges = Map3DRoadBridges()
        /// Decision 368: the scene point within ``Map3DScene/detailRadius``
        /// of which the city is built in full; everywhere when `nil`.
        var detail: Map3DPoint?

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

        init(originX: Double, originY: Double, region: WorldRegion, world: GameWorld, heights: HeightGrid? = nil) {
            self.originX = originX
            self.originY = originY
            self.region = region
            self.world = world
            placedGround = Self.placedSquares(world, region: region, originX: originX, originY: originY)
            fileGround = heights.flatMap { grid in RealWorldFrame(world: world).map { FileGround(grid, frame: $0, region: region) } }
        }

        func point(x: Double, y: Double, height: Double) -> Map3DPoint {
            Map3DPoint(Float((x - originX) / Self.metre), Float(height / Self.metre), Float((y - originY) / Self.metre))
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
            let bounds = world.bounds
            let plan = PlanPoint(x: min(max(Int64(x.rounded()), 0), bounds.width - 1),
                                 y: min(max(Int64(y.rounded()), 0), bounds.height - 1))
            if let height = world.groundHeight(at: plan) { return Float(Double(height) / Self.metre) }
            return fileGround?.height(x: Double(plan.x), y: Double(plan.y)) ?? 0
        }

        /// Decision 406: the drawn ground (``drawnGround(x:z:)``) at scene
        /// point (`x`, `z`) as a region round it draws it, past this
        /// region's edge too, where ``ground(x:y:)`` holds the edge's.
        func steadyGround(x: Float, z: Float) -> Float {
            let cell = Double(Land.cellLength)
            let worldX = originX + Double(x) * Self.metre, worldY = originY + Double(z) * Self.metre
            let column = Int((worldX / cell).rounded(.down)), row = Int((worldY / cell).rounded(.down))
            let fx = Float(worldX / cell - Double(column)), fy = Float(worldY / cell - Double(row))
            let bounds = world.bounds
            func corner(_ row: Int, _ column: Int) -> Float {
                let plan = PlanPoint(x: min(max(Int64((Double(column) * cell).rounded()), 0), bounds.width - 1),
                                     y: min(max(Int64((Double(row) * cell).rounded()), 0), bounds.height - 1))
                if let height = world.groundHeight(at: plan) { return Float(Double(height) / Self.metre) }
                return fileGround?.corner(row: Int((Double(plan.y) / cell).rounded(.down)), column: Int((Double(plan.x) / cell).rounded(.down))) ?? 0
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
            case .base: build(&meshes[key, default: Map3DMesh()])
            case .near: build(&nearMeshes[key, default: Map3DMesh()])
            case .far: build(&farMeshes[key, default: Map3DMesh()])
            case .close, .wires: build(&closeMeshes[key, default: Map3DMesh()])
            case .standIn: build(&standInMeshes[key, default: Map3DMesh()])
            }
        }

        /// Decision 368: whether chunk `key` is built without its city in
        /// full: further than ``Map3DScene/detailRadius`` from ``detail``.
        func isCoarse(_ key: ChunkKey) -> Bool {
            guard let detail else { return false }
            return Map3DStreaming.distance(of: Map3DStreaming.Key(column: key.column, row: key.row), to: detail) > Map3DScene.detailRadius
        }

        func chunks() -> [Chunk] {
            Set(meshes.keys).union(shadows.keys).union(nearMeshes.keys).union(farMeshes.keys).union(closeMeshes.keys).union(standInMeshes.keys).union(props.keys).union(signs.keys).sorted().compactMap { key in
                var mesh = meshes[key] ?? Map3DMesh()
                let baseIndexCount = mesh.indices.count
                mesh.append(nearMeshes[key] ?? Map3DMesh())
                var far = farMeshes[key] ?? Map3DMesh(), close = closeMeshes[key] ?? Map3DMesh(), standIn = standInMeshes[key] ?? Map3DMesh()
                let shadows = shadows[key] ?? Map3DMesh()
                // Decision 370: the city in the model look.
                Map3DLook.restyle(&mesh, keeping: keptColours)
                Map3DLook.restyle(&far, keeping: keptColours)
                Map3DLook.restyle(&close, keeping: keptColours)
                Map3DLook.restyle(&standIn, keeping: keptColours)
                // The props too: the renderer leaves out a chunk whose box
                // is off screen, which cut off a pole's top still in view.
                let propBoxes = (props[key] ?? []).compactMap { $0.bounds(in: .standard) }
                // And the signs, a rooftop board above its building.
                let signBoxes = (signs[key] ?? []).map { sign in
                    sign.corners.reduce((min: sign.centre, max: sign.centre)) {
                        (Map3DPoint(min($0.min.x, $1.x), min($0.min.y, $1.y), min($0.min.z, $1.z)), Map3DPoint(max($0.max.x, $1.x), max($0.max.y, $1.y), max($0.max.z, $1.z)))
                    }
                }
                let boxes = [mesh.bounds, far.bounds, shadows.bounds, close.bounds, standIn.bounds].compactMap { $0 } + propBoxes + signBoxes
                guard let first = boxes.first else { return nil }
                let low = boxes.reduce(first.min) { Map3DPoint(min($0.x, $1.min.x), min($0.y, $1.min.y), min($0.z, $1.min.z)) }
                let high = boxes.reduce(first.max) { Map3DPoint(max($0.x, $1.max.x), max($0.y, $1.max.y), max($0.z, $1.max.z)) }
                return Chunk(column: key.column, row: key.row, mesh: mesh, baseIndexCount: baseIndexCount, far: far, close: close, standIn: standIn, shadows: shadows,
                             props: props[key] ?? [], minimum: low, maximum: high,
                             cityTops: Map3DSeeThrough.tops(column: key.column, row: key.row, of: [(mesh, baseIndexCount), (far, 0), (standIn, 0)]),
                             signs: signs[key] ?? [], coarse: isCoarse(key))
            }
        }

        // MARK: Shadows (decision 232)

        /// The height of the ground as the scene draws it at scene point
        /// (`x`, `z`): the 64 m grid's corners, each square split from its
        /// north-west corner to its south-east one as ``addGround()``'s
        /// quads are.
        mutating func drawnGround(x: Float, z: Float) -> Float {
            let cell = Double(Land.cellLength)
            let worldX = originX + Double(x) * Self.metre, worldY = originY + Double(z) * Self.metre
            let column = Int((worldX / cell).rounded(.down)), row = Int((worldY / cell).rounded(.down))
            let fx = Float(worldX / cell - Double(column)), fy = Float(worldY / cell - Double(row))
            func corner(_ row: Int, _ column: Int) -> Float {
                let key = ChunkKey(column: column, row: row)
                if let known = corners[key] { return known }
                let height = ground(x: Double(column) * cell, y: Double(row) * cell)
                corners[key] = height
                return height
            }
            let a = corner(row, column), b = corner(row + 1, column), c = corner(row + 1, column + 1), d = corner(row, column + 1)
            // a (0, 0), b (0, 1), c (1, 1), d (1, 0) in (fx, fy): the
            // triangles a b c and a c d.
            return fy >= fx ? a + fx * (c - b) + fy * (b - a) : a + fx * (d - a) + fy * (c - d)
        }

        /// `points` laid on the drawn ground, ``Map3DShadow/lift`` over it.
        mutating func onGround(_ points: [Map3DPoint]) -> [Map3DPoint] {
            points.map { Map3DPoint($0.x, drawnGround(x: $0.x, z: $0.z) + Map3DShadow.lift, $0.z) }
        }

        /// A soft shadow under a footprint `length` along `forward` and
        /// `width` across, standing on `centre`, fading out over `spread`
        /// metres round it.
        mutating func addShadow(centre: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float,
                                spread: Float, darkness: Float) {
            guard !isFar else { return }
            let inner = onGround(Map3DMesh.footprint(centre: centre, forward: forward, length: length, width: width))
            let outer = onGround(Map3DMesh.footprint(centre: centre, forward: forward, length: length + 2 * spread, width: width + 2 * spread))
            shadows[key(of: centre), default: Map3DMesh()].addShadow(inner: inner, outer: outer, darkness: darkness)
        }

        // MARK: Ground

        /// The ground: a grid of 64 m squares at the map's heights, the
        /// water on it unless `water` is false (the base map's water lies
        /// on it instead, decision 234).
        mutating func addGround(water drawsWater: Bool = true) {
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
                    let water = drawsWater && world.isWater(row: row, column: column)
                    let lift = Map3DPoint(0, water ? 0.05 : 0, 0)
                    let middle = (a + c) * 0.5
                    let colour = water ? Map3DPalette.water : Map3DPalette.ground
                    // Decision 375: less the trenches, each triangle's
                    // pieces at its own heights, lit as the whole square.
                    let flat = { (p: Map3DPoint) in Map3DBaseMap.Point(x: Double(p.x), z: Double(p.z)) }
                    let halves = [[a, b, c], [a, c, d]].map { outsideTrenches($0.map(flat)) }
                    if halves.allSatisfy({ $0 == nil }) {
                        mesh(at: middle) {
                            // Decision 241: the ground plain, as the 2D map's land.
                            let start = $0.vertices.count
                            $0.addQuad(a + lift, b + lift, c + lift, d + lift, color: colour)
                            if water { $0.makeWater(from: start) }
                        }
                        continue
                    }
                    guard let normal = Map3DMesh.normal(of: [a, b, c, d]) else { continue }
                    var pieces: [[Map3DPoint]] = []
                    for (corners, half) in zip([[a, b, c], [a, c, d]], halves) {
                        for piece in half ?? [corners.map(flat)] {
                            pieces.append(piece.map { p in
                                let x = Float(p.x), z = Float(p.z)
                                return Map3DPoint(x, drawnGround(x: x, z: z), z) + lift
                            })
                        }
                    }
                    mesh(at: middle) {
                        let start = $0.vertices.count
                        for piece in pieces { $0.addFan(piece, normal: normal, color: colour) }
                        if water { $0.makeWater(from: start) }
                    }
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
                    let points = line.map { point($0) + Self.lifted }
                    trackLines.append((points, span.kind))
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
                // Decision 359 (續): its bore round its bed.
                var bore = Map3DMesh()
                addBore(line, into: &bore)
                mesh(at: middle) { mesh in
                    mesh.append(bore)
                    mesh.addRibbon(along: line, width: Self.bedTop, lift: -Self.bedDrop, depth: 0.6, top: Map3DPalette.ballast, side: Map3DPalette.ballast,
                                   topPaint: Self.ballast, sidePaint: Self.concrete)
                }
            case .viaduct, .bridge:
                let deckColor = kind == .bridge ? Map3DPalette.bridge : Map3DPalette.concrete
                let grounds = line.map { ground(at: $0) }
                addDeckShadow(line, grounds: grounds)
                var standing: [Map3DPoint] = []
                mesh(at: middle) { mesh in
                    mesh.addRibbon(along: line, width: Self.deckWidth, lift: -Self.bedDrop, depth: Self.girderDepth, top: Map3DPalette.ballast, side: deckColor,
                                   topPaint: Self.ballast, sidePaint: Self.concrete)
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
                                standing.append(Map3DPoint(top.x, foot, top.z))
                                mesh.addBox(base: Map3DPoint(top.x, foot, top.z), forward: b - a, length: Self.pierAlong, width: Self.pierAcross,
                                            height: height, top: deckColor, side: deckColor, frontPaint: Self.concrete, flankPaint: Self.concrete)
                            }
                            nextPier += Self.pierSpacing
                        }
                        travelled += step
                    }
                }
                // Decision 263: where they stand, for the streets under it.
                piers += standing
            case .surface, .embankment, .cutting:
                let lifts = line.map { $0.y - ground(at: $0) }
                let depth = max(0.45, (lifts.reduce(0, +) / Float(lifts.count)) - Self.bedDrop)
                let bank = kind == .embankment ? Map3DPalette.embankment : Map3DPalette.ballast
                // Decision 391 (續篇二): open over a road passing under it.
                let (banks, spans) = kind == .embankment ? openings(of: line) : ([line], [])
                mesh(at: middle) { mesh in
                    let width = Self.bedBottom + min(depth, 4.7) * 2
                    for part in banks where kind == .embankment {
                        mesh.addRibbon(along: part, width: width, lift: -Self.bedDrop - 0.05, depth: depth, top: bank, side: bank,
                                       topPaint: Self.bank, sidePaint: Self.bank)
                    }
                    for span in spans {
                        mesh.addRibbon(along: span, width: Self.bedBottom, lift: -Self.bedDrop - 0.05, depth: Self.girderDepth, top: Map3DPalette.concrete,
                                       side: Map3DPalette.concrete, topPaint: Self.concrete, sidePaint: Self.concrete)
                        // The bank's ends each side: its abutments.
                        for (end, inward) in [(span[0], span[1] - span[0]), (span[span.count - 1], span[span.count - 2] - span[span.count - 1])] {
                            guard let forward = Map3DPoint(inward.x, 0, inward.z).normalized else { continue }
                            let across = Map3DPoint(-forward.z, 0, forward.x) * (width / 2)
                            let top = end + Map3DPoint(0, -Self.bedDrop - 0.05, 0), foot = top + Map3DPoint(0, -depth, 0)
                            mesh.addQuad(foot - across, foot + across, top + across, top - across, color: bank, paint: Self.bank)
                            mesh.addQuad(foot + across, foot - across, top - across, top + across, color: bank, paint: Self.bank)
                        }
                    }
                    mesh.addRibbon(along: line, width: Self.bedTop, lift: -Self.bedDrop, depth: min(depth, 0.6), top: Map3DPalette.ballast, side: Map3DPalette.ballast,
                                   topPaint: Self.ballast, sidePaint: Self.concrete)
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

        /// Decision 391 (續篇二): `line` (an embankment's rails) in the
        /// stretches of bank and the spans open over a road passing under
        /// (``Map3DRoadBridges/openings``), each split where they meet.
        func openings(of line: [Map3DPoint]) -> (banks: [[Map3DPoint]], spans: [[Map3DPoint]]) {
            var travelled: [Float] = [0]
            for index in 1..<line.count { travelled.append(travelled[index - 1] + Map3DPoint(line[index].x - line[index - 1].x, 0, line[index].z - line[index - 1].z).length) }
            // The open stretches, by the way along the line.
            var open: [ClosedRange<Float>] = []
            for opening in roadBridges.openings {
                for index in 1..<line.count {
                    let a = Map3DBaseMap.Point(x: Double(line[index - 1].x), z: Double(line[index - 1].z)), b = Map3DBaseMap.Point(x: Double(line[index].x), z: Double(line[index].z))
                    let on = Map3DRoadBridges.nearest(opening.point, a, b)
                    guard on.distance < 1 else { continue }
                    let at = travelled[index - 1] + Float(((on.point.x - a.x) * (on.point.x - a.x) + (on.point.z - a.z) * (on.point.z - a.z)).squareRoot())
                    open.append(max(0, at - opening.half)...min(travelled[travelled.count - 1], at + opening.half))
                    break
                }
            }
            guard !open.isEmpty else { return ([line], []) }
            open.sort { $0.lowerBound < $1.lowerBound }
            var merged: [ClosedRange<Float>] = []
            for range in open {
                if let last = merged.last, range.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
                } else {
                    merged.append(range)
                }
            }
            func point(at distance: Float) -> Map3DPoint {
                let index = max(1, min(line.count - 1, travelled.firstIndex { $0 >= distance } ?? line.count - 1))
                let length = travelled[index] - travelled[index - 1]
                let share = length > 0 ? (distance - travelled[index - 1]) / length : 0
                return line[index - 1] + (line[index] - line[index - 1]) * min(max(share, 0), 1)
            }
            func part(_ from: Float, _ to: Float) -> [Map3DPoint] {
                [point(at: from)] + line.indices.filter { travelled[$0] > from && travelled[$0] < to }.map { line[$0] } + [point(at: to)]
            }
            var banks: [[Map3DPoint]] = [], spans: [[Map3DPoint]] = []
            var from: Float = 0
            for range in merged {
                if range.lowerBound > from { banks.append(part(from, range.lowerBound)) }
                if range.upperBound > range.lowerBound { spans.append(part(range.lowerBound, range.upperBound)) }
                from = range.upperBound
            }
            if travelled[travelled.count - 1] > from { banks.append(part(from, travelled[travelled.count - 1])) }
            return (banks, spans)
        }

        /// Decision 232: the deck's shadow on the ground under a viaduct
        /// or bridge, wider the higher it stands.
        mutating func addDeckShadow(_ line: [Map3DPoint], grounds: [Float]) {
            let heights = zip(line, grounds).map { $0.y - $1 }
            let height = heights.reduce(0, +) / Float(max(heights.count, 1))
            guard height > 2 else { return }
            let half = Self.deckWidth / 2, spread = min(5, 1.5 + height * 0.15)
            let across = Map3DMesh.acrossDirections(line)
            var rows: [[Map3DPoint]] = []
            for (point, side) in zip(line, across) {
                rows.append(onGround([-(half + spread), -half, half, half + spread].map { point + side * $0 }))
            }
            shadows[key(of: line[line.count / 2]), default: Map3DMesh()].addShadowStrip(rows, darkness: 0.26)
        }

        // MARK: Platforms

        /// Each platform beside its track: towards the other platform of
        /// its station across the next track within 15 m (an island
        /// between them), else on the side clear of other track, the left
        /// first; with a canopy. Decision 392: only where it stands clear
        /// of every other track, its edge as far from that one's middle as
        /// from its own, and at least ``narrowestPlatform`` wide; where
        /// there is no such room either side (the high-speed demo's through
        /// tracks between their loops, 5 m apart), none.
        mutating func addPlatforms(_ snapshot: RailwaySnapshot) {
            let platforms = snapshot.platforms.filter { $0.points.count > 1 && $0.structure != .tunnel }
            let middles = platforms.map { point($0.points[$0.points.count / 2]) }
            let others = snapshot.edges.map { ($0.edge.id, $0.geometry.points.map(point)) }
            let fast = world.highSpeedStations
            for (index, platform) in platforms.enumerated() {
                guard platform.points.contains(where: { contains(x: Double($0.x), y: Double($0.y)) }) else { continue }
                let line = platform.points.map { point($0) + Self.lifted }
                let across = Map3DMesh.acrossDirections(line)[line.count / 2]
                let middle = middles[index]
                let edge = fast.contains(platform.platform.station) ? Self.highSpeedPlatformEdge : Self.platformEdge
                let near = Self.nearestTracks(beside: line, others: others.filter { $0.0 != platform.platform.edge }.map(\.1))
                // The other platforms of its station across the nearest
                // track either side.
                let partner = platforms.indices
                    .filter { $0 != index && platforms[$0].platform.station == platform.platform.station && platforms[$0].platform.edge != platform.platform.edge }
                    .map { (index: $0, lateral: (middles[$0] - middle).dot(across)) }
                    .filter { abs($0.lateral) < 15 && abs(abs($0.lateral) - near[$0.lateral >= 0 ? 1 : 0]) < 1 }
                    .min { abs($0.lateral) < abs($1.lateral) }
                var side: Float = -1, width = Self.platformWidth
                if let partner, abs(partner.lateral) / 2 - edge >= Self.narrowestPlatform / 2 {
                    side = partner.lateral >= 0 ? 1 : -1
                    width = abs(partner.lateral) / 2 - edge
                } else {
                    func room(_ side: Float) -> Float { min(Self.platformWidth, near[side > 0 ? 1 : 0] - 2 * edge) }
                    if room(-1) < Self.platformWidth, room(1) > room(-1) { side = 1 }
                    width = room(side)
                }
                platformLines.append(line) // Decision 263: no street over it.
                guard width >= Self.narrowestPlatform else { continue }
                let offset = side * (edge + width / 2)
                // Decision 259: its waiting crowd, and the station's
                // passengers outside.
                addStationLife(line: line, offset: offset, width: width, station: platform.platform.station)
                mesh(at: middle) { mesh in
                    mesh.addRibbon(along: line, width: width, offset: offset, lift: Self.platformHeight, depth: Self.platformHeight + Self.bedDrop,
                                   top: Map3DPalette.platform, side: Map3DPalette.platform, topPaint: Self.paving, sidePaint: Self.concrete)
                    mesh.addRibbon(along: line, width: 0.3, offset: side * (edge + 0.35), lift: Self.platformHeight + 0.01,
                                   top: Map3DPalette.platformEdge)
                }
                // Decision 321: its canopy and its station's building come
                // with the station kit (`addStations`).
                laidPlatforms.append(LaidPlatform(station: platform.platform.station, line: line, offset: offset, width: width,
                                                  structure: platform.structure))
            }
        }

        /// Decision 392: how far beside `line` the nearest of `others`'
        /// middles runs within 15 m (beyond 1.5 m), on its left (across
        /// it, negative) and its right, alongside it and at its level;
        /// `.infinity` where none does.
        static func nearestTracks(beside line: [Map3DPoint], others: [[Map3DPoint]]) -> [Float] {
            let reach: Float = 15, step: Float = 2
            let across = Map3DMesh.acrossDirections(line)
            let minX = line.map(\.x).min()! - reach, maxX = line.map(\.x).max()! + reach
            let minZ = line.map(\.z).min()! - reach, maxZ = line.map(\.z).max()! + reach
            var nearest: [Float] = [.infinity, .infinity]
            func consider(_ point: Map3DPoint) {
                guard point.x > minX, point.x < maxX, point.z > minZ, point.z < maxZ,
                      let index = line.indices.min(by: { (line[$0] - point).length < (line[$1] - point).length })
                else { return }
                let offset = point - line[index], forward = Map3DPoint(across[index].z, 0, -across[index].x)
                let beyond = forward.dot(offset)
                guard abs(offset.y) < 3, !(index == 0 && beyond < -1), !(index == line.count - 1 && beyond > 1) else { return }
                let lateral = across[index].dot(offset)
                // Closer than any other track could be: the platform's own,
                // past a node.
                guard abs(lateral) < reach, abs(lateral) > 1.5 else { return }
                let side = lateral >= 0 ? 1 : 0
                nearest[side] = min(nearest[side], abs(lateral))
            }
            for points in others {
                for (a, b) in zip(points, points.dropFirst()) {
                    guard max(a.x, b.x) > minX, min(a.x, b.x) < maxX, max(a.z, b.z) > minZ, min(a.z, b.z) < maxZ else { continue }
                    let pieces = max(1, Int(((b - a).length / step).rounded(.up)))
                    for piece in 0...pieces { consider(a + (b - a) * (Float(piece) / Float(pieces))) }
                }
            }
            return nearest
        }

        /// The middle `share` of `line`, by length.
        static func middle(of line: [Map3DPoint], share: Float) -> [Map3DPoint] {
            guard let path = Map3DStreetLife.Path(line) else { return line }
            let from = path.length * (1 - share) / 2, to = path.length - from
            var points = [path.at(from).point]
            for (point, distance) in zip(path.points, path.distances) where distance > from && distance < to { points.append(point) }
            points.append(path.at(to).point)
            return points
        }

        // MARK: City

        /// Every lot of the city in the scene, but those on cells the track
        /// runs through: row houses on low homes and shops, blocks for the
        /// rest, trees in the parks.
        mutating func addCity(_ skyline: CitySkyline, clearOf cleared: Set<ChunkKey>, takenBy taken: Set<ChunkKey> = [],
                              besideRoads: Set<ChunkKey> = []) {
            let cell = Double(Land.cellLength)
            let pieces = roadPieces(near: besideRoads)
            // Decision 385: on a real-world map, the houses along its roads,
            // laid in the first pass and drawn again in the second.
            if streetFrontage, frontage.pieces.isEmpty { prepareFrontage() }
            let blocked = streetFrontage ? cleared.union(taken) : []
            for lot in skyline.lots(in: region) {
                var x = (Double(lot.column) + 0.5) * cell, y = (Double(lot.row) + 0.5) * cell
                // Decision 234: no lot where the real map has water or a
                // park.
                let key = ChunkKey(column: lot.column, row: lot.row)
                guard contains(x: x, y: y), !taken.contains(key) else { continue }
                // Decision 385: low homes and shops along the real roads,
                // house by house clear of the no-build land; no other lot
                // whose middle is on it.
                if streetFrontage, !lot.isOpenGround, !cleared.contains(key), lot.use == .residential || lot.use == .commercial, lot.density <= 2 {
                    addFrontage(column: lot.column, row: lot.row, density: lot.density, shops: lot.use == .commercial, blocked: blocked)
                    continue
                }
                if onNoBuildLand(point(x: x, y: y, height: 0)) { continue }
                var side = Float(Double(lot.side) / Self.metre)
                // Decision 345: where its roads reach, a building in the
                // room they leave, if a big enough one fits.
                if besideRoads.contains(key), !lot.isOpenGround, !cleared.contains(key) {
                    guard let room = roomBesideRoads(column: lot.column, row: lot.row, side: Int(side.rounded(.down)), in: pieces[key] ?? [])
                    else { continue }
                    (x, y, side) = (room.x, room.y, Float(room.side))
                } else if besideRoads.contains(key) {
                    continue
                }
                let centre = point(x: x, y: y, height: 0)
                let base = Map3DPoint(centre.x, ground(x: x, y: y), centre.z)
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
                                     base + Map3DPoint(half, 0.03, half), base + Map3DPoint(half, 0.03, -half), color: Map3DPalette.plaza,
                                     paint: Self.paving)
                    }
                    continue
                }
                switch lot.use {
                case .residential, .commercial:
                    if lot.density <= 2 {
                        addRowHouses(base: base, side: side, density: lot.density, shops: lot.use == .commercial, seed: seed,
                                     fronts: streetFronts(column: lot.column, row: lot.row))
                    } else {
                        addBlock(base: base, side: side, density: lot.density, walls: Self.pickWall(seed), facade: .flatWindows, seed: seed,
                                 commercial: lot.use == .commercial)
                    }
                case .office:
                    addBlock(base: base, side: side, density: lot.density, walls: Self.pick(Map3DPalette.officeWalls, seed), facade: .officeGlass, seed: seed)
                // Decision 235: factories, schools, clinics, temples and
                // malls from the asset library's rules.
                case .industrial:
                    addFactory(base: base, side: side, seed: seed)
                case .civic:
                    addCivic(base: base, side: side, density: lot.density, seed: seed)
                default:
                    addLeisure(base: base, side: side, seed: seed, front: templeFront(column: lot.column, row: lot.row))
                }
            }
        }

        mutating func addOpenGround(_ lot: CitySkyline.Lot, base: Map3DPoint, seed: (Int32, Int32)) {
            let half = Float(Double(Land.cellLength) / Self.metre / 2) - 0.5
            let park = lot.use == .park
            let far = isFar
            // Up to nine trees on a hashed 20 m grid (rail-3d's trees
            // stand on a hashed 26 m grid): where each stands and its size.
            var trees: [(spot: Map3DPoint, size: Float)] = []
            if park {
                for i in -1...1 {
                    for j in -1...1 {
                        let salt = Int32(10 + (i + 1) * 3 + (j + 1))
                        guard map3DRandom(seed.0, seed.1, salt: salt) < 0.7 else { continue }
                        let jitterX = (map3DRandom(seed.0, seed.1, salt: salt + 20) - 0.5) * 8
                        let jitterZ = (map3DRandom(seed.0, seed.1, salt: salt + 40) - 0.5) * 8
                        let spot = base + Map3DPoint(Float(i) * 20 + jitterX, 0, Float(j) * 20 + jitterZ)
                        trees.append((spot, 4 + map3DRandom(seed.0, seed.1, salt: salt + 60) * 3))
                    }
                }
            }
            mesh(at: base) { mesh in
                mesh.addQuad(base + Map3DPoint(-half, 0.02, -half), base + Map3DPoint(-half, 0.02, half),
                             base + Map3DPoint(half, 0.02, half), base + Map3DPoint(half, 0.02, -half),
                             color: park ? Map3DPalette.park : Map3DPalette.farm, paint: Self.grass)
                for (spot, size) in trees {
                    if !far {
                        mesh.addBox(base: spot, length: 0.6, width: 0.6, height: size * 0.45, top: Map3DPalette.trunk, side: Map3DPalette.trunk)
                    }
                    mesh.addBox(base: spot + Map3DPoint(0, size * 0.4, 0), length: size, width: size, height: size * 0.75,
                                top: Map3DPalette.crown, side: Map3DPalette.crown)
                }
            }
            // Decision 232: a round-ish shadow under each crown.
            for (spot, size) in trees {
                addShadow(centre: spot, length: size * 0.3, width: size * 0.3, spread: size * 0.55, darkness: 0.3)
            }
        }

        /// Decision 263: where a lot's rows of houses stand, from its middle,
        /// metres: each row's front (north, south: `nil` with no street on
        /// that side), and the rows' west and east ends.
        struct RowFronts {
            let north: Float?
            let south: Float?
            let west: Float
            let east: Float
            /// Decision 267: the kind of street each row faces.
            var northKind: Map3DBaseMap.RoadKind?
            var southKind: Map3DBaseMap.RoadKind?

            /// Decision 267: the share of a row's houses with a shop on the
            /// ground floor: on a main road most, on a street some, on a
            /// lane or the back none (a Taiwanese 透天厝 on a busy street
            /// keeps a shop below its home).
            func shopShare(facing: Float) -> Float {
                switch facing > 0 ? southKind : northKind {
                case .primary, .secondary, .trunk: 0.7
                case .tertiary: 0.4
                default: 0
                }
            }
        }

        /// The fronts on the seeded streets round cell (`column`, `row`), or
        /// `nil` on a map without them.
        func streetFronts(column: Int, row: Int) -> RowFronts? {
            guard !streetEdges.isEmpty else { return nil }
            let half = Float(Double(Land.cellLength) / Self.metre / 2)
            func clear(_ horizontal: Bool, _ line: Int, _ along: Int) -> Float? {
                streetEdges[Map3DSeededStreets.Edge(horizontal: horizontal, line: line, along: along)].map { Map3DSeededStreets.clearance($0) + 0.3 }
            }
            return RowFronts(north: clear(true, row, column).map { half - $0 }, south: clear(true, row + 1, column).map { half - $0 },
                             west: -half + (clear(false, column, row) ?? 2), east: half - (clear(false, column + 1, row) ?? 2),
                             northKind: streetEdges[Map3DSeededStreets.Edge(horizontal: true, line: row, along: column)],
                             southKind: streetEdges[Map3DSeededStreets.Edge(horizontal: true, line: row + 1, along: column)])
        }

        /// Decision 268: the way a temple on cell (`column`, `row`) faces,
        /// toward the busiest seeded street beside it (south first, as
        /// temples face, when two are alike), and how far from the lot's
        /// middle that street's pavement begins; `nil` with no street
        /// beside it.
        func templeFront(column: Int, row: Int) -> (forward: Map3DPoint, distance: Float)? {
            let half = Float(Double(Land.cellLength) / Self.metre / 2)
            let sides: [(Map3DPoint, Map3DSeededStreets.Edge)] = [
                (Map3DPoint(0, 0, 1), Map3DSeededStreets.Edge(horizontal: true, line: row + 1, along: column)),
                (Map3DPoint(1, 0, 0), Map3DSeededStreets.Edge(horizontal: false, line: column + 1, along: row)),
                (Map3DPoint(-1, 0, 0), Map3DSeededStreets.Edge(horizontal: false, line: column, along: row)),
                (Map3DPoint(0, 0, -1), Map3DSeededStreets.Edge(horizontal: true, line: row, along: column)),
            ]
            var best: (forward: Map3DPoint, distance: Float, kind: Map3DBaseMap.RoadKind)?
            for (forward, edge) in sides {
                guard let kind = streetEdges[edge], kind.rawValue > (best?.kind.rawValue ?? -1) else { continue }
                best = (forward, half - Map3DSeededStreets.clearance(kind) - 0.3, kind)
            }
            return best.map { ($0.forward, $0.distance) }
        }

        /// Two rows of 透天厝 back to back on the lot, facing north and
        /// south, each house 4.4–6.6 m wide (a block of flats 6.5–12.5 m at
        /// density 2) with an arcade (騎樓) on most shops, a parapet and a
        /// water tank on many roofs (`city_world_reference` `pickType`,
        /// `floorsFor`, `widthFor`, `waterTank`).
        mutating func addRowHouses(base: Map3DPoint, side: Float, density: Int, shops lotShops: Bool, seed: (Int32, Int32), fronts: RowFronts? = nil) {
            var depth = min(16, side / 2 - 1)
            // Decision 263: on seeded streets, each row's front at its
            // street's pavement (back to back where it has none), from the
            // side street's pavement to the other's.
            let span = fronts.map { ($0.west, $0.east) } ?? (-side / 2 + 0.5, side / 2)
            func frontAt(_ facing: Float) -> Float {
                (facing > 0 ? fronts?.south : fronts?.north) ?? depth + 0.5
            }
            if let fronts { depth = min(depth, [fronts.north, fronts.south].compactMap { $0 }.map { $0 - 0.5 }.min() ?? depth) }
            guard depth > 4 else { return }
            // Decision 267: the street's smallest things, drawn only close.
            var closeDetail = Map3DMesh()
            // Decision 352: the blade signs' words.
            var blades: [Map3DSign] = []
            let flats = density >= 2
            let far = isFar
            mesh(at: base) { mesh in
                for facing: Float in [-1, 1] {
                    // From the west end along the row.
                    var x = span.0
                    var number: Int32 = 0
                    while x < span.1 - 3.2 {
                        let salt = Int32(facing > 0 ? 100 : 300) + number * 7
                        let r = { (extra: Int32) in map3DRandom(seed.0, seed.1, salt: salt + extra) }
                        var width = flats ? 6.5 + r(1) * 6 : 4.4 + r(1) * 2.2
                        width = min(width, span.1 - x)
                        guard width >= 3.2 else { break }
                        let wall = Self.pickWall((seed.0 &+ salt, seed.1))
                        let middleX = x + width / 2
                        let front = Map3DPoint(0, 0, facing) // the way the house faces
                        let rowMiddle = base + Map3DPoint(middleX, 0, facing * (frontAt(facing) - depth / 2))
                        // Decision 267: a shop below on a commercial lot, and
                        // on a busy street's houses now and then.
                        let shops = lotShops || r(13) < (fronts?.shopShare(facing: facing) ?? 0)
                        Self.addTownHouse(&mesh, close: &closeDetail, blades: &blades, middle: rowMiddle, front: front, width: width,
                                          depth: depth, flats: flats, shops: shops, wall: wall, far: far, r: r)
                        x += width
                        number += 1
                    }
                }
            }
            for blade in blades { addSign(blade) }
            if !closeDetail.isEmpty {
                let saved = target
                target = .close
                mesh(at: base) { $0.append(closeDetail) }
                target = saved
            }
            // Decision 268: between two rows facing streets on both sides,
            // the back yards; on most lots a lawn down their middle with a
            // few trees (the rest stay paved, for parking).
            if let north = fronts?.north, let south = fronts?.south {
                let yard = (from: -(north - depth) + 1.5, to: south - depth - 1.5)
                let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
                if yard.to - yard.from >= 5, span.1 - span.0 > 16, r(90) < 0.7 {
                    let length = (span.1 - span.0) * (0.5 + 0.3 * r(91))
                    let middleX = (span.0 + span.1) / 2 + (r(92) - 0.5) * (span.1 - span.0 - length)
                    let west = middleX - length / 2, east = middleX + length / 2
                    mesh(at: base) { mesh in
                        mesh.addQuad(base + Map3DPoint(west, 0.02, yard.from), base + Map3DPoint(west, 0.02, yard.to),
                                     base + Map3DPoint(east, 0.02, yard.to), base + Map3DPoint(east, 0.02, yard.from),
                                     color: Map3DPalette.park, paint: Self.grass)
                    }
                    if target == .near, let tree = Self.propModels[.tree] {
                        let count = 1 + Int(r(93) * 3)
                        for index in 0..<count {
                            let x = west + length * (Float(index) + 0.5 + (r(Int32(94 + index)) - 0.5) * 0.5) / Float(count)
                            let foot = base + Map3DPoint(x, 0, (yard.from + yard.to) / 2 + (r(Int32(98 + index)) - 0.5) * (yard.to - yard.from - 3))
                            props[key(of: foot), default: []].append(.prop(tree, at: foot, forward: Map3DPoint(1, 0, 0), scale: 0.9 + 0.4 * r(Int32(102 + index)),
                                                                           tint: Self.pick(Map3DProp.greens, r(Int32(106 + index)))))
                        }
                    }
                }
            }
            // Decision 232: a shadow round each row.
            for facing: Float in [-1, 1] {
                addShadow(centre: base + Map3DPoint((span.0 + span.1) / 2, 0, facing * (frontAt(facing) - depth / 2)), forward: Map3DPoint(1, 0, 0),
                          length: span.1 - span.0, width: depth + 0.5, spread: 3, darkness: 0.3)
            }
            // Decision 259: shoppers along the shops' fronts (decision 267:
            // and along a busy street's).
            for facing: Float in [-1, 1] where lotShops || (fronts?.shopShare(facing: facing) ?? 0) > 0 {
                let out = facing * (frontAt(facing) + 1.2)
                addShopLife(from: base + Map3DPoint(span.0 + 0.5, 0.05, out), to: base + Map3DPoint(span.1 - 0.5, 0.05, out), density: density)
            }
        }

        /// A block of flats, offices or a tower: density 3 a slab of 7–16
        /// floors, density 4 a two-floor podium under a tower of 18–40.
        /// Decision 231: every side windows of `facade`, a bay to each
        /// 3.2 m (an office's curtain wall 3 m) and floor; a tower's podium
        /// shops, or glass under offices.
        mutating func addBlock(base: Map3DPoint, side: Float, density: Int, walls: UInt32, facade: Map3DSurface, seed: (Int32, Int32),
                               commercial: Bool = false) {
            let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
            let bay: Float = facade == .officeGlass ? 3 : 3.2
            // Flats' windows with or without blinds, and the podium's shop,
            // picked by where the block stands.
            let windowSurface = facade == .flatWindows ? Self.pick(Map3DSurface.flats, r(3)) : facade
            // Decision 242: flats faced with tiles or grit, offices now and
            // then fair-faced concrete.
            let facing = facade == .officeGlass ? (r(5) < 0.4 ? Map3DSurface.formConcrete : nil) : Self.homeMaterial(r(5))
            func windows(_ floors: Float) -> Map3DPaint { Map3DPaint.bays(windowSurface, bay: bay, floors: Int(floors)).on(facing) }
            let far = isFar
            mesh(at: base) { mesh in
                let footprint = max(side - 4, 8)
                switch density {
                case ...2:
                    let floors = Float(3 + Int(r(1) * 4))
                    mesh.addBox(base: base, length: footprint * 0.8, width: footprint * 0.8, height: 3.8 + 3.2 * (floors - 1),
                                top: Map3DPalette.roof, side: walls, topPaint: Self.roofing, frontPaint: windows(floors), flankPaint: windows(floors))
                case 3:
                    let floors = Float(7 + Int(r(1) * 10))
                    let turned = r(2) < 0.5
                    mesh.addBox(base: base, forward: turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1),
                                length: footprint * 0.9, width: footprint * 0.45, height: 4.6 + 3.2 * (floors - 1), top: Map3DPalette.roof, side: walls,
                                topPaint: Self.roofing, frontPaint: windows(floors), flankPaint: windows(floors))
                    // Decision 235: a stair house and air conditioners on top;
                    // decision 238: near, a balcony along each long side
                    // on every floor.
                    if !far {
                        let along = turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1)
                        Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, 4.6 + 3.2 * (floors - 1), 0), forward: along,
                                          length: footprint * 0.9, width: footprint * 0.45, r: r, salt: 30)
                        let across = Map3DPoint(-along.z, 0, along.x)
                        for floor in 1..<Int(floors) {
                            for side: Float in [-1, 1] {
                                mesh.addBox(base: base + across * (side * (footprint * 0.225 + 0.5)) + Map3DPoint(0, 4.6 + 3.2 * Float(floor - 1), 0),
                                            forward: along, length: footprint * 0.9 - 2, width: 1, height: 1.05,
                                            top: Map3DColor.shaded(walls, 0.97), side: Map3DColor.shaded(walls, 0.93))
                            }
                        }
                    }
                default:
                    let floors = Float(18 + Int(r(1) * 23))
                    let podium = facade == .officeGlass ? Map3DPaint.bays(.officeGlass, bay: 3, floors: 2) : Map3DPaint.bays(Self.pick(Map3DSurface.shops, r(4)), bay: 5.4, floors: 2)
                    mesh.addBox(base: base, length: footprint, width: footprint, height: 9, top: Map3DPalette.roof, side: Map3DColor.shaded(walls, 0.9),
                                topPaint: Self.roofing, frontPaint: podium, flankPaint: podium)
                    mesh.addBox(base: base + Map3DPoint(0, 9, 0), length: footprint * 0.55, width: footprint * 0.55, height: 3.3 * floors,
                                top: Map3DPalette.roof, side: walls, topPaint: Self.roofing, frontPaint: windows(floors), flankPaint: windows(floors))
                    if !far {
                        Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, 9 + 3.3 * floors, 0), forward: Map3DPoint(0, 0, -1),
                                          length: footprint * 0.55, width: footprint * 0.55, r: r, salt: 30)
                    }
                }
            }
            if !far { addBlockAds(base: base, side: side, density: density, office: facade == .officeGlass, commercial: commercial, r: r) }
            // Decision 259: shoppers round a tower's shops.
            if density >= 4, facade != .officeGlass {
                let half = max(side - 4, 8) / 2 + 1.7
                for (a, b) in [((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))] as [((Float, Float), (Float, Float))] {
                    addShopLife(from: base + Map3DPoint(a.0 * half, 0.05, a.1 * half), to: base + Map3DPoint(b.0 * half, 0.05, b.1 * half),
                                density: density)
                }
            }
            // Decision 232: the shadow round its foot, wider under a taller
            // block.
            let footprint = max(side - 4, 8)
            switch density {
            case ...2:
                addShadow(centre: base, length: footprint * 0.8, width: footprint * 0.8, spread: 2.5, darkness: 0.32)
            case 3:
                let turned = r(2) < 0.5
                addShadow(centre: base, forward: turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1), length: footprint * 0.9,
                          width: footprint * 0.45, spread: 3.5, darkness: 0.34)
            default:
                addShadow(centre: base, length: footprint, width: footprint, spread: 4.5, darkness: 0.36)
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
                if addPlacedKitBuilding(building, base: base, side: side) { continue }
                let height = 1.5 + 3.5 * Float(building.kind.floors)
                let windows = Map3DPaint.bays(.flatWindows, bay: 3.2, floors: Int(building.kind.floors))
                mesh(at: base) { mesh in
                    mesh.addBox(base: base, length: side, width: side, height: height, top: Map3DPalette.playerRoof, side: Map3DPalette.player,
                                frontPaint: windows, flankPaint: windows)
                    mesh.addBox(base: base + Map3DPoint(0, height, 0), length: side, width: side, height: 0.6,
                                top: Map3DPalette.playerRim, side: Map3DPalette.playerRim)
                    mesh.addBox(base: base + Map3DPoint(0, height, 0), length: side - 2, width: side - 2, height: 0.4,
                                top: Map3DPalette.playerRoof, side: Map3DPalette.playerRoof, topPaint: Self.roofing)
                }
                addShadow(centre: base, length: side, width: side, spread: 2.5, darkness: 0.32)
            }
        }

        // MARK: Choosing

        /// Decision 242: what a home's walls are faced with, by a share
        /// from 0 to 1: 二丁掛 tiles on half, 馬賽克 on a quarter, 洗石子 on
        /// some, plain paint on the rest.
        static func homeMaterial(_ share: Float) -> Map3DSurface? {
            share < 0.5 ? .brickTile : share < 0.75 ? .mosaicTile : share < 0.9 ? .terrazzo : nil
        }

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

        /// One of `choices` by a share from 0 up to 1.
        static func pick<Choice>(_ choices: [Choice], _ share: Float) -> Choice {
            choices[min(choices.count - 1, max(0, Int(share * Float(choices.count))))]
        }
    }
}
