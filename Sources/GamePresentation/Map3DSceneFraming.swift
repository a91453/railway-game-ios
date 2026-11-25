import GameCore

/// Which part of the world a 3D scene covers, where its origin is, and
/// building a few of its chunks on their own (decisions 313, 358, 368).
/// Moved as it was out of `Map3DScene.swift` (MAP3D-SCENE-SPLIT).
extension Map3DScene {
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
    /// this is a small part of building the scene; the streets are chosen,
    /// not laid (decision 659). None on a real-world map.
    public static func seededStreets(world: GameWorld, snapshot: RailwaySnapshot? = nil, skyline: CitySkyline? = nil) -> SeededStreetPlan {
        guard world.geoAnchor == nil else { return SeededStreetPlan(edges: [:]) }
        let frame = frame(world: world, focus: nil)
        var builder = Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: world)
        let snapshot = snapshot ?? world.railwaySnapshot()
        let cleared = builder.addTrack(snapshot)
        builder.addViaducts()
        builder.addPlatforms(snapshot)
        builder.addSeededStreets(skyline ?? CitySkyline(world: world), clearOf: cleared, laying: false)
        return SeededStreetPlan(edges: builder.state.streets.streetEdges)
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
                landCover: LandCoverGrid? = nil,
                lineBands: Map3DLineBands? = nil, railways: RealRailways? = nil, temples: RealTemples? = nil, noBuild: RealNoBuildLand? = nil,
                facades: Bool = true) {
        // Decision 368: on a map the camera builds ahead on (decision 358),
        // the city in full only round the middle, which the window builds
        // in full as the camera comes near.
        self.init(world: world, snapshot: snapshot, skyline: skyline, frame: Self.frame(world: world, focus: focus), baseMap: baseMap,
                  cityTiles: cityTiles, footprints: footprints, heights: heights, landCover: landCover, lineBands: lineBands, railways: railways,
                  temples: temples, noBuild: noBuild,
                  detail: Map3DStreaming.streams(world) ? Map3DPoint(0, 0, 0) : nil, facades: facades,
                  studies: Self.studyRegion(world: world, scene: Self.frame(world: world, focus: focus).region))
    }

    /// Review L14-7: where a station study (decision 625) of a scene of
    /// `scene`'s region can be drawn: the whole map where the camera builds
    /// ahead (decision 358), as a block of chunks there may hold its
    /// origin, else the scene's own region.
    static func studyRegion(world: GameWorld, scene: WorldRegion) -> WorldRegion {
        Map3DStreaming.streams(world) ? WorldRegion(bounds: world.bounds) : scene
    }

    /// Decision 358: chunks `keys` of `streaming`'s scene (its origin),
    /// each built as the whole scene builds it, from the same files: a
    /// scene of the squares round them with ``Map3DStreaming/apron`` more
    /// each way, on the map, of which only `keys`' chunks are kept (a
    /// chunk with nothing in it is none). Its real trains and street life
    /// are not kept. Decision 359 (續): `trackCover` is the whole scene's
    /// (``trackCover``), worked out again when `nil`. Decision 368: with
    /// `detail`, a scene point, only the chunks within ``detailRadius`` of
    /// it in full (``Chunk/coarse``); HSRPACE (decision 861): with
    /// `detailAhead` too, within it of the way from `detail` to there.
    /// Decision 610 續: the real buildings' street fronts only with
    /// `facades` (``Map3DRealFacade/mayDraw(quality:device:)``).
    public static func chunks(_ keys: some Collection<Map3DStreaming.Key>, of streaming: Map3DStreaming, world: GameWorld,
                              snapshot: RailwaySnapshot? = nil, skyline: CitySkyline? = nil, baseMap: BaseMapTiles? = nil,
                              cityTiles: [CityTileArea] = [], footprints: FootprintTiles? = nil, heights: HeightGrid? = nil,
                              landCover: LandCoverGrid? = nil, lineBands: Map3DLineBands? = nil, railways: RealRailways? = nil, temples: RealTemples? = nil,
                              noBuild: RealNoBuildLand? = nil,
                              trackCover: Map3DTrackCover? = nil, detail: Map3DPoint? = nil, detailAhead: Map3DPoint? = nil,
                              facades: Bool = true) -> [Chunk] {
        guard let box = streaming.region(of: keys) else { return [] }
        let apron = Map3DStreaming.apron * Double(WorldCoordinate.unitsPerMetre), map = streaming.map
        let region = WorldRegion(minX: max(map.minX, box.minX - apron), minY: max(map.minY, box.minY - apron),
                                 maxX: min(map.maxX, box.maxX + apron), maxY: min(map.maxY, box.maxY + apron))
        guard region.minX < region.maxX, region.minY < region.maxY else { return [] }
        // Decision 359: the whole network's track cover (`trackCover`, the
        // scene's, or worked out again), which lays the tunnels.
        let scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, frame: (region, streaming.originX, streaming.originY),
                               baseMap: baseMap, cityTiles: cityTiles, footprints: footprints, heights: heights, landCover: landCover,
                               lineBands: lineBands, railways: railways, temples: temples, noBuild: noBuild, trackCover: trackCover, detail: detail,
                               detailAhead: detailAhead, facades: facades, studies: map)
        let wanted = Set(keys)
        return scene.chunks.filter { wanted.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }
    }
}
