import Foundation
import GameCore

/// Decision 876: the centre line of every stretch of a network's track as
/// the 3D map draws it (``Map3DScene/Builder/sample(_:from:to:)``), worked
/// out once for everything that lays it.
///
/// A scene samples the whole network, not its region's track: the ground
/// is levelled under all of it, the tunnels are found along all of it. A
/// block of chunks built apart (decision 358) did the same again, five
/// times over (the levelled ground, the cells kept plain, the track, the
/// track cover and a station's room), so a block's time grew with the
/// network, not with what is in it: 0.2 s of a block's 1.0 s in Taipei
/// with fifteen lines bought. The samples are the same whatever the
/// region, so they are made once and kept with the scene's track cover
/// (``Map3DSharedBuild``), each stretch with its box, so a block reads
/// only the stretches that reach it.
struct Map3DTrackSamples: Sendable {
    /// One section of an edge (``TrackEdge/sectionSpans``).
    struct Span: Sendable {
        let kind: TrackSectionKind
        let start: Int64
        let end: Int64
        /// Its centre line; of a span with no length, as it is sampled.
        let line: [WorldCoordinate]
        /// The box of `line`, world units; none (`minX` over `maxX`) for
        /// an empty line.
        let minX: Int64, minY: Int64, maxX: Int64, maxY: Int64

        init(_ span: TrackSectionSpan, line: [WorldCoordinate]) {
            kind = span.kind
            start = span.start
            end = span.end
            self.line = line
            var low = (x: Int64.max, y: Int64.max), high = (x: Int64.min, y: Int64.min)
            for coordinate in line {
                low = (min(low.x, coordinate.x), min(low.y, coordinate.y))
                high = (max(high.x, coordinate.x), max(high.y, coordinate.y))
            }
            (minX, minY, maxX, maxY) = (low.x, low.y, high.x, high.y)
        }

        /// Whether a point of `line` can lie in `region` grown by
        /// `margin` world units each way, its edges included: its box
        /// meets it. A span this is false of has no point there.
        func reaches(_ region: WorldRegion, by margin: Double = 0) -> Bool {
            minX <= maxX && Double(maxX) >= region.minX - margin && Double(minX) <= region.maxX + margin
                && Double(maxY) >= region.minY - margin && Double(minY) <= region.maxY + margin
        }
    }

    /// Each edge's spans, as `snapshot.edges` and ``TrackEdge/sectionSpans``
    /// order them.
    let edges: [[Span]]
    /// The 64 m cells the track runs through, by column and row: those
    /// whose ground stays the world's (``Map3DLevelledGround``).
    let cells: Set<Map3DScene.ChunkKey>
    /// What tells the snapshot these are of (``mark(of:)``).
    let mark: Int

    init(_ snapshot: RailwaySnapshot) {
        let cell = Double(Land.cellLength)
        var cells = Set<Map3DScene.ChunkKey>()
        edges = snapshot.edges.map { alignment in
            alignment.edge.sectionSpans.map { span in
                guard span.end > span.start else { return Span(span, line: []) }
                let line = Map3DScene.Builder.sample(alignment.geometry, from: span.start, to: span.end)
                for coordinate in line {
                    cells.insert(Map3DScene.ChunkKey(column: Int((Double(coordinate.x) / cell).rounded(.down)),
                                                     row: Int((Double(coordinate.y) / cell).rounded(.down))))
                }
                return Span(span, line: line)
            }
        }
        self.cells = cells
        mark = Self.mark(of: snapshot)
    }

    /// A number that differs between two snapshots whose track differs,
    /// read from each edge's ends, length, points' count and sections, not
    /// from every point: a few microseconds for a thousand edges. The same
    /// only within one run of the program (it is hashed).
    static func mark(of snapshot: RailwaySnapshot) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshot.edges.count)
        for alignment in snapshot.edges {
            let edge = alignment.edge, geometry = alignment.geometry
            hasher.combine(edge.id)
            hasher.combine(edge.from)
            hasher.combine(edge.to)
            hasher.combine(geometry.points.count)
            hasher.combine(geometry.length)
            hasher.combine(geometry.points.first)
            hasher.combine(geometry.points.last)
            hasher.combine(geometry.startHeight)
            hasher.combine(geometry.endHeight)
            for span in edge.sectionSpans {
                hasher.combine(span.kind)
                hasher.combine(span.start)
                hasher.combine(span.end)
            }
        }
        return hasher.finalize()
    }
}

/// Decision 876: what every build of one scene works out the same
/// whatever its region, kept with the scene's track cover
/// (``Map3DTrackCover/shared``) so the scene and each block of chunks
/// built apart after it (``Map3DScene/chunks(_:of:world:snapshot:skyline:baseMap:cityTiles:footprints:heights:landCover:lineBands:railways:temples:noBuild:trackCover:detail:detailAhead:facades:)``,
/// two at a time on the streamer's threads) work it out once between
/// them: the network's samples, the real lines' boxes on the map, their
/// timetables' runs and track assignment, the screen doors' plan, the
/// trains calling at each station and the underground
/// stations.
///
/// Nothing here changes what is built: each is what the build worked out
/// itself before, keyed by what it was worked out from, and a build
/// handed something else (another snapshot, another world) works its own
/// out as before.
final class Map3DSharedBuild: @unchecked Sendable {
    private let lock = NSLock()

    // MARK: The network

    private var samples: Map3DTrackSamples?

    /// `snapshot`'s samples: those kept when they are of it, or made (and
    /// kept, when none were).
    func samples(of snapshot: RailwaySnapshot) -> Map3DTrackSamples {
        let mark = Map3DTrackSamples.mark(of: snapshot)
        lock.lock()
        defer { lock.unlock() }
        if let samples, samples.mark == mark { return samples }
        let made = Map3DTrackSamples(snapshot)
        if samples == nil { samples = made }
        return made
    }

    /// The box of each of `snapshot`'s edges' points in the scene whose
    /// origin is (`originX`, `originY`), seen from above: for the track's
    /// own index (``Map3DRealTrains/PlayerTrack``), which then reads only
    /// the edges near what asks.
    private var edgeBoxes: (mark: Int, originX: Double, originY: Double, boxes: [Map3DRealTrains.PlayerTrack.Box])?

    func edgeBoxes(of snapshot: RailwaySnapshot, originX: Double, originY: Double,
                   point: (WorldCoordinate) -> Map3DPoint) -> [Map3DRealTrains.PlayerTrack.Box] {
        let mark = Map3DTrackSamples.mark(of: snapshot)
        lock.lock()
        defer { lock.unlock() }
        if let edgeBoxes, edgeBoxes.mark == mark, edgeBoxes.originX == originX, edgeBoxes.originY == originY { return edgeBoxes.boxes }
        let boxes = snapshot.edges.map { Map3DRealTrains.PlayerTrack.Box($0.geometry.points.map(point)) }
        if edgeBoxes == nil { edgeBoxes = (mark, originX, originY, boxes) }
        return boxes
    }

    // MARK: The guideways

    private var guideways: (key: Int, edges: [TrackEdgeID: Map3DGuideway.Kind])?

    /// Decision 947: the edges of `snapshot`'s track that are guideways in
    /// `world` (``Map3DGuideway/edges(in:)``): those kept when they are of
    /// the same track, or read (and kept, when none were).
    func guideways(of snapshot: RailwaySnapshot, world: GameWorld) -> [TrackEdgeID: Map3DGuideway.Kind] {
        var hasher = Hasher()
        hasher.combine(Map3DTrackSamples.mark(of: snapshot))
        hasher.combine(Map3DGuidewaySignature(world: world))
        let key = hasher.finalize()
        lock.lock()
        if let guideways, guideways.key == key {
            lock.unlock()
            return guideways.edges
        }
        lock.unlock()
        let made = Map3DGuideway.edges(in: world)
        lock.lock()
        defer { lock.unlock() }
        guideways = (key, made)
        return made
    }

    // MARK: The kinds of track

    private var trackKinds: (key: Int, edges: [TrackEdgeID: Map3DTrackKind])?

    /// Decision 964: the kind of each edge of `snapshot`'s track that is
    /// not ballast in `world` (``Map3DTrackKind/edges(in:)``): those kept
    /// when they are of the same track and trains, or worked out.
    func trackKinds(of snapshot: RailwaySnapshot, world: GameWorld) -> [TrackEdgeID: Map3DTrackKind] {
        var hasher = Hasher()
        hasher.combine(Map3DTrackSamples.mark(of: snapshot))
        hasher.combine(Map3DTrackKindSignature(world: world))
        let key = hasher.finalize()
        lock.lock()
        if let trackKinds, trackKinds.key == key {
            lock.unlock()
            return trackKinds.edges
        }
        lock.unlock()
        let made = Map3DTrackKind.edges(in: world)
        lock.lock()
        defer { lock.unlock() }
        trackKinds = (key, made)
        return made
    }

    // MARK: The underground stations

    /// What tells the underground stations of a snapshot laid in a scene:
    /// its track (``Map3DTrackSamples/mark(of:)``), its platforms in
    /// tunnels, whole (a platform is added to a tunnel without its track
    /// changing), and the scene's origin. The same only within one run of
    /// the program (it is hashed).
    struct UndergroundKey: Equatable {
        let track: Int, platforms: Int
        let originX: Double, originY: Double

        init(_ snapshot: RailwaySnapshot, originX: Double, originY: Double) {
            track = Map3DTrackSamples.mark(of: snapshot)
            var hasher = Hasher()
            for platform in snapshot.platforms where platform.structure == .tunnel { hasher.combine(platform) }
            platforms = hasher.finalize()
            (self.originX, self.originY) = (originX, originY)
        }
    }

    private var underground: (key: UndergroundKey, stations: Map3DUndergroundStations)?

    /// Decision 876 (later): the underground platforms and their stations' boxes
    /// of `snapshot` in the scene whose origin is (`originX`, `originY`)
    /// (``Map3DUndergroundStations/init(_:point:cover:)``, `make`): laid
    /// from the whole network and the whole track cover, the same
    /// whatever the region, so those kept when they are of it, or made
    /// (and kept, when none were).
    func undergroundStations(of snapshot: RailwaySnapshot, originX: Double, originY: Double,
                             make: () -> Map3DUndergroundStations) -> Map3DUndergroundStations {
        let key = UndergroundKey(snapshot, originX: originX, originY: originY)
        lock.lock()
        defer { lock.unlock() }
        if let underground, underground.key == key { return underground.stations }
        let made = make()
        if underground == nil { underground = (key, made) }
        return made
    }

    // MARK: The real lines

    /// A box on the map, world units.
    struct Box: Sendable {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity

        init() {}

        init(_ points: some Sequence<(x: Double, y: Double)>) {
            for point in points {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
        }

        /// Whether a point of what the box is of can lie in the box
        /// (`minX`...`maxX`, `minY`...`maxY`), its edges included.
        func meets(minX: Double, minY: Double, maxX: Double, maxY: Double) -> Bool {
            self.maxX >= minX && self.minX <= maxX && self.maxY >= minY && self.minY <= maxY
        }
    }

    /// What tells the real railways and the frame they are laid by.
    struct RealKey: Equatable {
        let lines: Int, operations: Int, tracks: Int
        let middleX: Double, middleY: Double
        let latitude: Double, longitude: Double

        init(_ railways: RealRailways, frame: RealWorldFrame) {
            lines = railways.lines.count
            operations = railways.operations?.orderedSystems.reduce(0) { $0 + $1.lines.count } ?? 0
            tracks = railways.tracks?.tracks.count ?? 0
            (middleX, middleY) = (frame.middleX, frame.middleY)
            (latitude, longitude) = (frame.anchor.latitudeDegrees, frame.anchor.longitudeDegrees)
        }
    }

    private var realKey: RealKey?
    private var lineBoxes: [Box]?
    private var trackBoxes: [Box]?
    private var operationBoxes: [String: Box] = [:]
    private var operationLines: [String: RealTrainTraffic.Line?] = [:]
    private var operationLegs: [String: [String: [Map3DRealTrains.Leg]]] = [:]

    /// Whether what is kept of the real railways is `key`'s: the first to
    /// ask sets it, and a build with other railways keeps nothing.
    private func holds(_ key: RealKey) -> Bool {
        if realKey == nil { realKey = key }
        return realKey == key
    }

    /// The box of each of `railways`' lines on the map (``RealRailways/lines``).
    func lineBoxes(of railways: RealRailways, frame: RealWorldFrame) -> [Box] {
        func made() -> [Box] {
            railways.lines.map { line in Box(line.points.lazy.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }) }
        }
        lock.lock()
        defer { lock.unlock() }
        guard holds(RealKey(railways, frame: frame)) else { return made() }
        if let lineBoxes { return lineBoxes }
        let boxes = made()
        lineBoxes = boxes
        return boxes
    }

    /// The box of each of `tracks`' real tracks on the map
    /// (``RealRailTracks/tracks``), `key`'s railways'.
    func trackBoxes(of tracks: RealRailTracks, key: RealKey, frame: RealWorldFrame) -> [Box] {
        func made() -> [Box] {
            tracks.tracks.map { track in
                Box(track.points.lazy.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) })
            }
        }
        lock.lock()
        defer { lock.unlock() }
        guard holds(key) else { return made() }
        if let trackBoxes { return trackBoxes }
        let boxes = made()
        trackBoxes = boxes
        return boxes
    }

    /// The box of `line` of `system` on the map: its shape and its
    /// stations.
    func box(of line: RealOperationLine, system: String, key: RealKey, frame: RealWorldFrame) -> Box {
        func made() -> Box {
            var box = Box(line.shape.lazy.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) })
            let stations = Box(line.stations.lazy.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) })
            box.minX = min(box.minX, stations.minX); box.maxX = max(box.maxX, stations.maxX)
            box.minY = min(box.minY, stations.minY); box.maxY = max(box.maxY, stations.maxY)
            return box
        }
        let name = "\(system):\(line.id)"
        lock.lock()
        defer { lock.unlock() }
        guard holds(key) else { return made() }
        if let box = operationBoxes[name] { return box }
        let box = made()
        operationBoxes[name] = box
        return box
    }

    /// `line` of `system` with its trains (``RealTrainTraffic/line(_:of:in:)``),
    /// `nil` when it has none: the same whatever part of it a region sees.
    func trafficLine(_ line: RealOperationLine, system: String, key: RealKey, operations: RealRailwayOperations) -> RealTrainTraffic.Line? {
        let name = "\(system):\(line.id)"
        lock.lock()
        defer { lock.unlock() }
        guard holds(key) else { return RealTrainTraffic.line(line, of: system, in: operations) }
        if let made = operationLines[name] { return made }
        let made = RealTrainTraffic.line(line, of: system, in: operations)
        operationLines[name] = made
        return made
    }

    /// The legs of `line`'s trains on the tracks they are assigned
    /// (``Map3DRealTrains/legs(of:traffic:dispatch:operations:)``).
    func legs(of line: RealTrainTraffic.Line, key: RealKey, make: () -> [String: [Map3DRealTrains.Leg]]) -> [String: [Map3DRealTrains.Leg]] {
        let name = "\(line.system):\(line.line.id)"
        lock.lock()
        defer { lock.unlock() }
        guard holds(key) else { return make() }
        if let made = operationLegs[name] { return made }
        let made = make()
        operationLegs[name] = made
        return made
    }

    // MARK: The world's trains

    /// What tells the world the trains' plans are of: its clock and how
    /// much it holds of what they read.
    struct WorldKey: Equatable {
        let clock: GameClock
        let trains: Int, lines: Int, stations: Int, acquisitions: Int

        init(_ world: GameWorld) {
            clock = world.clock
            trains = world.trains.count
            lines = world.lines.count
            stations = world.stations.count
            acquisitions = world.acquisitions.count
        }
    }

    private var worldKey: WorldKey?
    private var screenDoors: Map3DScreenDoors.Plan?
    private var calling: [StationID: (formations: [Map3DPlatformProps.Formation], metro: Int)]?

    private func holds(_ key: WorldKey) -> Bool {
        if worldKey == nil { worldKey = key }
        return worldKey == key
    }

    /// The screen doors' plan of `world` (``Map3DScreenDoors/Plan``).
    func screenDoors(of world: GameWorld) -> Map3DScreenDoors.Plan {
        lock.lock()
        defer { lock.unlock() }
        guard holds(WorldKey(world)) else { return Map3DScreenDoors.Plan(world: world) }
        if let screenDoors { return screenDoors }
        let plan = Map3DScreenDoors.Plan(world: world)
        screenDoors = plan
        return plan
    }

    /// The trains calling at each station of `world`
    /// (``Map3DScene/Builder/callingFormations()``).
    func calling(in world: GameWorld, make: () -> [StationID: (formations: [Map3DPlatformProps.Formation], metro: Int)])
        -> [StationID: (formations: [Map3DPlatformProps.Formation], metro: Int)] {
        lock.lock()
        defer { lock.unlock() }
        guard holds(WorldKey(world)) else { return make() }
        if let calling { return calling }
        let made = make()
        calling = made
        return made
    }
}
