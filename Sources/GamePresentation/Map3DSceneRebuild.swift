import GameCore

/// Decision 517 續 (PR 3b): when the player lays or takes up track or a
/// platform, the 3D map builds again only the chunks round what changed
/// and keeps the rest of the scene it had (whose ground, city and real
/// lines the change did not touch), instead of building the whole scene
/// of some 12 km a side again (decision 614 measured 12–13 s on Linux).
/// The chunks built again are built as the streaming window builds the
/// chunks ahead of the camera (decision 358,
/// ``Map3DScene/chunks(_:of:world:snapshot:skyline:baseMap:cityTiles:footprints:heights:lineBands:railways:temples:noBuild:trackCover:detail:)``),
/// a block of five by five at a time with ``Map3DStreaming/apron`` round
/// it, but kept to the scene's own region, so a chunk on its edge is built
/// as the whole scene built it; what the whole scene works out over all of
/// it (the tunnels, the real trains, the drawn ground) is worked out again
/// over all of it, which takes a small part of the time.
///
/// Only on a map that builds ahead (``Map3DStreaming/streams(_:)``, a
/// real-world map): a made-up map lays its seeded streets over the whole
/// scene at once (decision 263), so a block built on its own lays them
/// otherwise; it still builds the whole scene.
public enum Map3DSceneRebuild {
    /// How far round what changed its chunks are built again, in metres:
    /// what the track brings beside it (its trench and cutting, the bushes
    /// and the city lots it clears, the overhead line's masts, a viaduct's
    /// piers shared with the track beside, a station's building, plaza and
    /// shops) all stand within it.
    public static let reach: Float = Float(Map3DStreaming.apron)

    /// The world points (world units, seen from above) where `new`'s
    /// track, platforms and stations differ from `old`'s: every point of
    /// each edge, platform or tunnel portal added, taken away or changed,
    /// in either world, and each station changed and its platforms.
    public static func changes(from old: RailwaySnapshot, _ oldWorld: GameWorld, to new: RailwaySnapshot, _ newWorld: GameWorld) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        func add(_ coordinates: [WorldCoordinate]) {
            for (index, point) in coordinates.enumerated() {
                points.append((Double(point.x), Double(point.y)))
                // Between the points, at most a quarter chunk apart, so a
                // long straight's chunks between its ends are found.
                guard index > 0 else { continue }
                let last = coordinates[index - 1]
                let dx = Double(point.x - last.x), dy = Double(point.y - last.y)
                let metres = (dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)
                let steps = Int((metres / Double(Map3DScene.chunkSize / 4)).rounded(.up))
                if steps > 1 {
                    for step in 1..<steps {
                        let t = Double(step) / Double(steps)
                        points.append((Double(last.x) + dx * t, Double(last.y) + dy * t))
                    }
                }
            }
        }
        // Edges by their ID; one whose alignment changed in any way (its
        // geometry, structure, sections, speed limits) counts both ways.
        let oldEdges = Dictionary(old.edges.map { ($0.edge.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newEdges = Dictionary(new.edges.map { ($0.edge.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, edge) in oldEdges where newEdges[id] != edge { add(edge.geometry.points) }
        for (id, edge) in newEdges where oldEdges[id] != edge { add(edge.geometry.points) }
        let oldNodes = Dictionary(old.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newNodes = Dictionary(new.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, node) in oldNodes where newNodes[id] != node { add([node.position]) }
        for (id, node) in newNodes where oldNodes[id] != node { add([node.position]) }
        // Platforms as values: one moved or resized is gone and new.
        let oldPlatforms = Set(old.platforms), newPlatforms = Set(new.platforms)
        for platform in oldPlatforms.symmetricDifference(newPlatforms) { add(platform.points) }
        // A station changed (its name on its signs, a depot, its shops):
        // where it stands and its platforms, in both worlds.
        let oldStations = Dictionary(oldWorld.stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newStations = Dictionary(newWorld.stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changedStations = Set<StationID>()
        for (id, station) in oldStations where newStations[id] != station { changedStations.insert(id) }
        for (id, station) in newStations where oldStations[id] != station { changedStations.insert(id) }
        for id in changedStations {
            for station in [oldStations[id], newStations[id]].compactMap({ $0 }) {
                points.append((Double(station.point.x), Double(station.point.y)))
            }
        }
        for platform in old.platforms + new.platforms where changedStations.contains(platform.platform.station) { add(platform.points) }
        return points
    }

    /// Whether `old`, built round `focus`, can be built again in part for
    /// `world`: on a map that builds ahead, and where the whole scene for
    /// `world` round `focus` covers the same place round the same origin
    /// (new track can widen the part of the map a scene covers).
    public static func fits(_ old: Map3DScene, world: GameWorld, focus: (x: Double, y: Double)?) -> Bool {
        guard Map3DStreaming.streams(world) else { return false }
        let frame = Map3DScene.frame(world: world, focus: focus)
        return frame.region == old.region && frame.originX == old.originX && frame.originY == old.originY
    }

    /// The chunks of `scene` within ``reach`` of `points` (world units):
    /// those to build again. Only the scene's own (a chunk the streaming
    /// window built beyond it is built again by the window, decision 358).
    public static func keys(round points: [(x: Double, y: Double)], in scene: Map3DScene, map: WorldRegion) -> Set<Map3DStreaming.Key> {
        let grid = Map3DStreaming(scene: scene, map: map)
        let own = Set(scene.chunks.map { Map3DStreaming.Key(column: $0.column, row: $0.row) })
        // A chunk of the scene's region with nothing in it is none of its
        // chunks; one the change brings something to is built too.
        let inScene = Self.keys(of: scene.region, in: grid)
        var found = Set<Map3DStreaming.Key>()
        for point in points {
            let at = scene.point(worldX: point.x, worldY: point.y, height: 0)
            for key in grid.area(round: at, radius: reach) where own.contains(key) || inScene.contains(key) { found.insert(key) }
        }
        return found
    }

    /// The chunks any of whose square `region` holds.
    static func keys(of region: WorldRegion, in grid: Map3DStreaming) -> Set<Map3DStreaming.Key> {
        let side = Double(Map3DScene.chunkSize) * Double(WorldCoordinate.unitsPerMetre)
        let first = (column: Int(((region.minX - grid.originX) / side).rounded(.down)), row: Int(((region.minY - grid.originY) / side).rounded(.down)))
        let last = (column: Int(((region.maxX - grid.originX) / side).rounded(.up)) - 1, row: Int(((region.maxY - grid.originY) / side).rounded(.up)) - 1)
        guard first.column <= last.column, first.row <= last.row else { return [] }
        var keys = Set<Map3DStreaming.Key>()
        for row in first.row...last.row {
            for column in first.column...last.column { keys.insert(Map3DStreaming.Key(column: column, row: row)) }
        }
        return keys
    }
}

extension Map3DScene {
    /// Decision 517 續 (PR 3b): `old` with its chunks at `keys` built again
    /// from `world` (and the same files it was built from), and what the
    /// whole scene works out over all of it (the track cover, the drawn
    /// ground, the real trains) worked out again: the scene the public
    /// initializer builds for `world` round `old`'s place, where the change
    /// is only within `keys`. The chunks are built a block of
    /// ``Map3DStreaming/blockSide`` at a time with ``Map3DStreaming/apron``
    /// round it, kept to `old`'s region; the city in full only within
    /// ``detailRadius`` of `detail`, as `old` was built.
    ///
    /// Street life: the lanes and the pavements are `old`'s (the roads are
    /// the same); the stations' platforms and fronts and the shops by them
    /// within `keys` are the blocks' own.
    public init(rebuilding keys: Set<Map3DStreaming.Key>, of old: Map3DScene, world: GameWorld, snapshot: RailwaySnapshot? = nil,
                skyline: CitySkyline? = nil, baseMap: BaseMapTiles? = nil, cityTiles: [CityTileArea] = [], footprints: FootprintTiles? = nil,
                heights: HeightGrid? = nil, lineBands: Map3DLineBands? = nil, railways: RealRailways? = nil, temples: RealTemples? = nil,
                noBuild: RealNoBuildLand? = nil, detail: Map3DPoint? = nil, facades: Bool = true) {
        region = old.region
        originX = old.originX
        originY = old.originY
        let snapshot = snapshot ?? world.railwaySnapshot()
        let skyline = skyline ?? CitySkyline(world: world)
        // What the whole scene works out over all of it, as its
        // initializer does before it lays the city.
        var builder = Builder(originX: originX, originY: originY, region: region, world: world, heights: heights)
        builder.detail = detail
        let cover = Map3DTrackCover(snapshot, builder: &builder)
        builder.trackCover = cover
        trackCover = cover
        drawnGround = builder.groundGrid()
        realTrains = Self.realTrains(world: world, railways: railways, snapshot: snapshot, builder: &builder)
        seededStreets = old.seededStreets
        levelCrossings = old.levelCrossings
        layers = old.layers

        let map = WorldRegion(bounds: world.bounds)
        let grid = Map3DStreaming(originX: originX, originY: originY, map: map)
        let apron = Map3DStreaming.apron * Double(WorldCoordinate.unitsPerMetre)
        var built: [Chunk] = []
        var life = Map3DStreetLife()
        var exteriors = old.stationExteriors
        var left = keys.sorted()
        while !left.isEmpty {
            let block = Map3DStreaming.block(of: left)
            left.removeAll(where: Set(block).contains)
            guard let box = grid.region(of: block) else { continue }
            let area = WorldRegion(minX: max(region.minX, box.minX - apron), minY: max(region.minY, box.minY - apron),
                                   maxX: min(region.maxX, box.maxX + apron), maxY: min(region.maxY, box.maxY + apron))
            guard area.minX < area.maxX, area.minY < area.maxY else { continue }
            let part = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, frame: (area, originX, originY), baseMap: baseMap,
                                  cityTiles: cityTiles, footprints: footprints, heights: heights, lineBands: lineBands, railways: railways,
                                  temples: temples, noBuild: noBuild, trackCover: cover, detail: detail, facades: facades,
                                  studies: Self.studyRegion(world: world, scene: region))
            let wanted = Set(block)
            built += part.chunks.filter { wanted.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }
            exteriors = Self.exteriors(exteriors, rebuilt: part.stationExteriors) { wanted.contains(grid.key(of: $0)) }
            life.spots += part.streetLife.spots.filter { Self.isStations($0) && wanted.contains(grid.key(of: $0.path.points[0])) }
        }
        stationExteriors = exteriors
        chunks = (old.chunks.filter { !keys.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) } + built)
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        var streetLife = old.streetLife
        streetLife.spots.removeAll { Self.isStations($0) && keys.contains(grid.key(of: $0.path.points[0])) }
        streetLife.spots += life.spots
        self.streetLife = streetLife
    }

    /// Review L14-6: the studies standing once the chunks `rebuilt(_:)`
    /// says hold an origin are built again: those of `old` elsewhere, and
    /// those `rebuilt` stood in them. One of `old` in them that `rebuilt`
    /// no longer stands (cut by new track to less than
    /// ``Builder/exteriorLeast``) goes, as it went from the drawing; one
    /// `rebuilt` stood only in the apron round them is drawn in no chunk
    /// kept, and is not taken.
    static func exteriors(_ old: [Map3DStationExterior], rebuilt: [Map3DStationExterior],
                          in block: (Map3DPoint) -> Bool) -> [Map3DStationExterior] {
        old.filter { !block($0.origin) } + rebuilt.filter { block($0.origin) }
    }

    /// Whether `spot` is a station's or its shops' (what a change of the
    /// track or the platforms moves), not a pavement's or a temple's.
    static func isStations(_ spot: Map3DStreetLife.Spot) -> Bool {
        switch spot.kind {
        case .platform, .stationFront, .shops: true
        case .temple, .sidewalk: false
        }
    }
}
