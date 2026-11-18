import GameCore

/// Decision 358: the 3D map's scene as a window of chunks that slides with
/// the camera. The scene is built once round where the map opened
/// (``Map3DScene/reach`` each way); as a followed train or a drag takes
/// the camera off it, the chunks ahead of the camera's motion are built in
/// the background a few at a time (``Map3DScene/chunks(_:of:...)``, each
/// built as the whole scene builds it) and those left far behind are let
/// go, so a train followed from Kaohsiung to Taipei keeps its ground,
/// track and city round it.
///
/// After the reference's `OpenWorld/reference_snapshot/play/src/engine/
/// world-stream.js` (chunks within a radius of the player's, acted on
/// only when that set changes) and `Railway/taiwan-rail-reference-clean/
/// source/rail-3d` (loads cancelled by generation); building toward where
/// the camera is going first is Cesium's idea (its flight destinations'
/// tiles loaded ahead), not its code.
public struct Map3DStreaming: Sendable {
    /// A chunk's place, by column and row of ``Map3DScene/chunkSize`` from
    /// the scene's origin (``Map3DScene/Chunk/column``, ``Map3DScene/Chunk/row``).
    public struct Key: Hashable, Comparable, Sendable {
        public let column: Int
        public let row: Int

        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }

        public static func < (a: Key, b: Key) -> Bool { (a.row, a.column) < (b.row, b.column) }
    }

    /// What to do next: the chunks to build, the most wanted first, and
    /// those to let go.
    public struct Plan: Equatable, Sendable {
        public var build: [Key]
        public var drop: [Key]
    }

    /// How far round the camera's target chunks are kept whatever its
    /// motion, in metres: the far view's reach (``Map3DCamera/detailDistance``
    /// and more), so a turn or a stop never shows the edge.
    public static let around: Float = 3_000
    /// How far ahead of the target's motion chunks are built, in metres:
    /// as far as the scene reaches from its middle (``Map3DScene/reach``),
    /// past what a followed train's camera sees (its far plane, 6 times
    /// its distance and 4 km).
    public static let ahead: Float = Float(Map3DScene.reach)
    /// How wide the strip ahead is, each side of the line of motion, in
    /// metres.
    public static let aheadWidth: Float = 1_500
    /// How much further than they are kept chunks are let go, in metres,
    /// so a chunk on the edge is not built and dropped by turns.
    public static let slack: Float = 1_024
    /// Slower than this, in metres a second, the target counts as still:
    /// a drag's last flick, not a journey.
    public static let still: Float = 2
    /// The most chunks a build takes at once: a block of five by five,
    /// which builds in less time a chunk than three by three (4–10 ms
    /// against 6–16, decision 358's numbers) and in a quarter second.
    public static let blockSide = 5

    /// How much further each way than the chunks it keeps a block is
    /// built, in metres, so what stands across a chunk's edge is laid
    /// as the whole scene lays it.
    public static let apron: Double = 256

    /// Whether the 3D map of `world` builds ahead as its camera moves:
    /// only a real-world map's. A made-up map lays its seeded streets
    /// (decision 263) across the whole scene at once, so a block built
    /// on its own lays its trees and lamps otherwise (decision 358's next
    /// step); its usual map is 16 km a side, most of which the first
    /// scene holds.
    public static func streams(_ world: GameWorld) -> Bool { world.geoAnchor != nil }

    /// Decision 578: how far round a stop ahead the followed train's chunks
    /// are built before it gets there, in metres: the platform view's
    /// sight over the platform (a block of five by five chunks).
    public static let stationRadius: Float = 1_024
    /// Decision 578: how far round a stop the chunks must stand for the
    /// camera to go to its platform, in metres: the neighbours it sees
    /// first from the platform, one chunk's side.
    public static let stationReady: Float = 512

    /// The scene's origin, world units.
    public let originX: Double
    public let originY: Double
    /// The map's extent from above, world units: no chunk past it is built.
    public let map: WorldRegion

    public init(originX: Double, originY: Double, map: WorldRegion) {
        self.originX = originX
        self.originY = originY
        self.map = map
    }

    public init(scene: Map3DScene, map: WorldRegion) {
        self.init(originX: scene.originX, originY: scene.originY, map: map)
    }

    // MARK: - Space

    private static var metre: Double { Double(WorldCoordinate.unitsPerMetre) }

    /// The chunk scene point `point` is in.
    public func key(of point: Map3DPoint) -> Key {
        let side = Map3DScene.chunkSize
        return Key(column: Int((point.x / side).rounded(.down)), row: Int((point.z / side).rounded(.down)))
    }

    /// `key`'s square, world units.
    public func region(of key: Key) -> WorldRegion {
        let side = Double(Map3DScene.chunkSize) * Self.metre
        let minX = originX + Double(key.column) * side, minY = originY + Double(key.row) * side
        return WorldRegion(minX: minX, minY: minY, maxX: minX + side, maxY: minY + side)
    }

    /// The smallest region holding `keys`' squares, world units; `nil`
    /// for none.
    public func region(of keys: some Sequence<Key>) -> WorldRegion? {
        keys.reduce(nil as WorldRegion?) { box, key in
            let square = region(of: key)
            guard let box else { return square }
            return WorldRegion(minX: min(box.minX, square.minX), minY: min(box.minY, square.minY),
                               maxX: max(box.maxX, square.maxX), maxY: max(box.maxY, square.maxY))
        }
    }

    /// The chunks whose squares `region` holds whole: what a scene of
    /// `region` built in full. A chunk on its edge is only partly built
    /// and is built again when wanted.
    public func keys(within region: WorldRegion) -> Set<Key> {
        let side = Double(Map3DScene.chunkSize) * Self.metre
        let first = Key(column: Int(((region.minX - originX) / side).rounded(.up)), row: Int(((region.minY - originY) / side).rounded(.up)))
        let last = Key(column: Int(((region.maxX - originX) / side).rounded(.down)) - 1, row: Int(((region.maxY - originY) / side).rounded(.down)) - 1)
        guard first.column <= last.column, first.row <= last.row else { return [] }
        var keys = Set<Key>()
        for row in first.row...last.row {
            for column in first.column...last.column { keys.insert(Key(column: column, row: row)) }
        }
        return keys
    }

    /// Decision 368: how far scene point `point` is from `key`'s square,
    /// seen from above, in metres (0 in it).
    public static func distance(of key: Key, to point: Map3DPoint) -> Float {
        let side = Map3DScene.chunkSize
        let low = SIMD2(Float(key.column) * side, Float(key.row) * side), at = SIMD2(point.x, point.z)
        return simd_length(simd_clamp(at, low, low + side) - at)
    }

    /// Decision 578: the chunks on the map within `radius` metres of scene
    /// point `point`, seen from above, the nearest first.
    public func area(round point: Map3DPoint, radius: Float) -> [Key] {
        let centre = key(of: point)
        let span = Int((radius / Map3DScene.chunkSize).rounded(.up)) + 1
        var keys: [(key: Key, distance: Float)] = []
        for row in (centre.row - span)...(centre.row + span) {
            for column in (centre.column - span)...(centre.column + span) {
                let key = Key(column: column, row: row)
                let distance = Self.distance(of: key, to: point)
                if distance <= radius, isOnMap(key) { keys.append((key, distance)) }
            }
        }
        return keys.sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }.map(\.key)
    }

    /// Whether any of `key`'s square is on the map.
    func isOnMap(_ key: Key) -> Bool {
        let square = region(of: key)
        return square.maxX > map.minX && square.minX < map.maxX && square.maxY > map.minY && square.minY < map.maxY
    }

    // MARK: - What the camera sees (decision 714)

    /// Decision 714 (MAP3D-FAR): how far from its target `camera`'s view
    /// is built and kept, in metres, seen from above: a little past its
    /// distance, which holds the corners of a phone held sideways looking
    /// straight down (1.07 times). Leaning, the view runs on to the
    /// horizon; no further than this is built for it.
    public static func sight(of camera: Map3DCamera) -> Float { camera.distance * 1.1 }

    /// Decision 714: how far above and below the camera's target the
    /// ground of a chunk not built yet is taken to lie, in metres.
    static let relief: Float = 600

    /// Decision 714: the chunks on the map whose ground `camera` sees
    /// within ``sight(of:)`` of its target, the nearest first; with
    /// `slack`, those it would see were their squares that much wider
    /// each way (metres). None while the view sees no further than the
    /// window keeps round its target anyway (``around``).
    public func seen(by camera: Map3DCamera, slack: Float = 0) -> [Key] {
        let reach = Self.sight(of: camera)
        guard reach > Self.around else { return [] }
        let target = camera.target, matrix = camera.viewProjection, side = Map3DScene.chunkSize
        let low = key(of: Map3DPoint(target.x - reach - slack, 0, target.z - reach - slack))
        let high = key(of: Map3DPoint(target.x + reach + slack, 0, target.z + reach + slack))
        var keys: [(key: Key, distance: Float)] = []
        for row in low.row...high.row {
            for column in low.column...high.column {
                let key = Key(column: column, row: row)
                let distance = Self.distance(of: key, to: target)
                guard distance <= reach + slack, isOnMap(key) else { continue }
                let x = Float(column) * side, z = Float(row) * side
                if Map3DCamera.sees(minimum: Map3DPoint(x - slack, target.y - Self.relief, z - slack),
                                    maximum: Map3DPoint(x + side + slack, target.y + Self.relief, z + side + slack), through: matrix) {
                    keys.append((key, distance))
                }
            }
        }
        return keys.sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }.map(\.key)
    }

    /// MEM3D (decision 749 續): whether `camera` sees any of `key`'s
    /// ground, however far from its target (``seen(by:slack:)`` stops at
    /// ``sight(of:)``): a leaning view's corners run past it, onto the
    /// scene's own chunks, which are let go last.
    public func isSeen(_ key: Key, by camera: Map3DCamera, slack: Float = 0) -> Bool {
        let side = Map3DScene.chunkSize, target = camera.target
        let x = Float(key.column) * side, z = Float(key.row) * side
        return Map3DCamera.sees(minimum: Map3DPoint(x - slack, target.y - Self.relief, z - slack),
                                maximum: Map3DPoint(x + side + slack, target.y + Self.relief, z + side + slack),
                                through: camera.viewProjection)
    }

    /// Decision 714: the map from above in the scene's metres (x east, z
    /// south of its origin): where the camera's target may be
    /// (``Map3DCamera/held(over:)``).
    public var ground: (x: ClosedRange<Float>, z: ClosedRange<Float>) {
        (Float((map.minX - originX) / Self.metre)...Float((map.maxX - originX) / Self.metre),
         Float((map.minY - originY) / Self.metre)...Float((map.maxY - originY) / Self.metre))
    }

    // MARK: - Planning

    /// How soon chunk `key` is wanted with the camera's target at `target`
    /// moving at `velocity` (metres a second, scene x and z), as a
    /// distance in metres; `nil` when it is not wanted. Within
    /// ``around`` of the target, its distance; in the strip ahead of the
    /// motion (``ahead`` long, ``aheadWidth`` each side), its distance
    /// along the motion, so the chunks the target reaches first come
    /// first. Distances are to the nearest point of the chunk's square.
    func wantedIn(_ key: Key, target: Map3DPoint, velocity: SIMD2<Float>, slack: Float = 0) -> Float? {
        let side = Map3DScene.chunkSize
        let low = SIMD2(Float(key.column) * side, Float(key.row) * side), high = low + side
        let at = SIMD2(target.x, target.z)
        let nearest = simd_clamp(at, low, high)
        let distance = simd_length(nearest - at)
        var best: Float? = distance <= Self.around + slack ? distance : nil
        let speed = simd_length(velocity)
        guard speed >= Self.still else { return best }
        let forward = velocity / speed
        // The square's nearest point to the line ahead, sampled along it.
        let step = side / 2
        var along: Float = 0
        while along <= Self.ahead + slack {
            let point = at + forward * along
            let gap = simd_length(simd_clamp(point, low, high) - point)
            if gap <= Self.aheadWidth + slack {
                best = min(best ?? .infinity, max(along, distance))
                break
            }
            along += step
        }
        return best
    }

    /// The chunks wanted round `target` moving at `velocity`, on the map,
    /// the soonest first (then from north-west).
    public func wanted(target: Map3DPoint, velocity: SIMD2<Float>) -> [Key] {
        wantedWithin(slack: 0, target: target, velocity: velocity).sorted { ($0.soon, $0.key) < ($1.soon, $1.key) }.map(\.key)
    }

    func wantedWithin(slack: Float, target: Map3DPoint, velocity: SIMD2<Float>) -> [(key: Key, soon: Float)] {
        let reach = max(Self.around, Self.ahead + Self.aheadWidth) + slack
        let low = key(of: Map3DPoint(target.x - reach, 0, target.z - reach))
        let high = key(of: Map3DPoint(target.x + reach, 0, target.z + reach))
        var wanted: [(key: Key, soon: Float)] = []
        for row in low.row...high.row {
            for column in low.column...high.column {
                let key = Key(column: column, row: row)
                guard isOnMap(key), let soon = wantedIn(key, target: target, velocity: velocity, slack: slack) else { continue }
                wanted.append((key, soon))
            }
        }
        return wanted
    }

    /// What to do with the target at `target` moving at `velocity`: the
    /// wanted chunks neither `built` nor `building`, the soonest first;
    /// and those `built` no longer wanted even ``slack`` further out.
    public func plan(target: Map3DPoint, velocity: SIMD2<Float>, built: Set<Key>, building: Set<Key> = [],
                     keeping stops: [Map3DPoint] = []) -> Plan {
        let build = wanted(target: target, velocity: velocity).filter { !built.contains($0) && !building.contains($0) }
        var kept = Set(wantedWithin(slack: Self.slack, target: target, velocity: velocity).map(\.key))
        // Decision 578: the chunks round the stops ahead are kept too.
        for stop in stops { kept.formUnion(area(round: stop, radius: Self.stationRadius + Self.slack)) }
        return Plan(build: build, drop: built.subtracting(kept).sorted())
    }

    /// The next block to build from `plan`'s wanted chunks: the first,
    /// and those wanted with it in the ``blockSide`` square round it,
    /// sorted.
    public static func block(of wanted: [Key]) -> [Key] {
        guard let first = wanted.first else { return [] }
        let reach = blockSide / 2
        return wanted.filter { abs($0.column - first.column) <= reach && abs($0.row - first.row) <= reach }.sorted()
    }

    /// HSRPACE (decision 861): the next block to build from `wanted`'s
    /// first, filled from `fill` (chunks wanted a little later, not built):
    /// of the ``blockSide`` squares holding the first, the one holding the
    /// most of `fill` (then the most of `wanted`, then the one round the
    /// first), and of it, every chunk of `wanted` or `fill`, sorted.
    ///
    /// A block costs about what the square round its chunks costs (the
    /// scene of their bounding square is built and the rest thrown away),
    /// most of it a fixed part (decision 358's numbers: 50–60 ms of a 5 × 5
    /// block's 0.1–0.25 s). Moving at speed, and worse on a slant, the
    /// chunks newly wanted at the strip's far end are a thin line, so a
    /// block of only those held a handful of chunks for the price of a
    /// whole square: at ten times real time the window fell behind a High
    /// Speed Rail train and the ground under it was missing.
    public static func block(of wanted: [Key], filling fill: Set<Key>) -> [Key] {
        guard let first = wanted.first else { return [] }
        let soon = Set(wanted)
        let every = soon.union(fill)
        var best: (column: Int, row: Int, filled: Int, soon: Int, off: Int)?
        for row in (first.row - blockSide + 1)...first.row {
            for column in (first.column - blockSide + 1)...first.column {
                var filled = 0, wantedIn = 0
                for key in every where key.column >= column && key.column < column + blockSide && key.row >= row && key.row < row + blockSide {
                    filled += 1
                    if soon.contains(key) { wantedIn += 1 }
                }
                let off = abs(column + blockSide / 2 - first.column) + abs(row + blockSide / 2 - first.row)
                if let current = best, (current.filled, current.soon, -current.off) >= (filled, wantedIn, -off) { continue }
                best = (column, row, filled, wantedIn, off)
            }
        }
        guard let best else { return [first] }
        return every.filter { $0.column >= best.column && $0.column < best.column + blockSide && $0.row >= best.row && $0.row < best.row + blockSide }.sorted()
    }

    /// HSRPACE (decision 861): how far down the way ahead the city is built
    /// in full (``way(target:velocity:)``), in metres: the whole strip
    /// ahead and its slack. Shorter (1–4 km tried in
    /// `Map3DStreamingPaceTests`), the chunks past it were built
    /// simplified and again in full as the target neared them, and the
    /// window was busy 94% of the time instead of 52–63%.
    public static let inFullAhead: Float = ahead + slack

    /// HSRPACE (decision 861): the far end of the way `target` moving at
    /// `velocity` is on, ``inFullAhead`` ahead; `nil` while it stands
    /// still. The city is built in full within ``Map3DScene/detailRadius``
    /// of the way from the target to it, so the chunks the target is
    /// about to pass are built in full the first time rather than
    /// simplified and built again as it nears them.
    public static func way(target: Map3DPoint, velocity: SIMD2<Float>) -> Map3DPoint? {
        let speed = simd_length(velocity)
        guard speed >= still else { return nil }
        let end = SIMD2(target.x, target.z) + velocity / speed * inFullAhead
        return Map3DPoint(end.x, target.y, end.y)
    }

    /// HSRPACE (decision 861): how far `key`'s square is from the way from
    /// `start` to `end` (from `start` alone without it), seen from above,
    /// in metres (0 where the way crosses it).
    public static func distance(of key: Key, toWayFrom start: Map3DPoint, to end: Map3DPoint?) -> Float {
        guard let end else { return distance(of: key, to: start) }
        let side = Map3DScene.chunkSize
        let low = SIMD2(Float(key.column) * side, Float(key.row) * side), high = low + side
        let a = SIMD2(start.x, start.z), b = SIMD2(end.x, end.z), d = b - a
        // Whether the way crosses the square (Liang–Barsky).
        var t0: Float = 0, t1: Float = 1, crosses = true
        for (p, q) in [(-d.x, a.x - low.x), (d.x, high.x - a.x), (-d.y, a.y - low.y), (d.y, high.y - a.y)] {
            if p == 0 {
                if q < 0 { crosses = false }
            } else if p < 0 {
                t0 = max(t0, q / p)
            } else {
                t1 = min(t1, q / p)
            }
        }
        if crosses, t0 <= t1 { return 0 }
        func toSquare(_ point: SIMD2<Float>) -> Float { simd_length(simd_clamp(point, low, high) - point) }
        func toWay(_ point: SIMD2<Float>) -> Float {
            let length = (d * d).sum()
            let t = length > 0 ? min(max(((point - a) * d).sum() / length, 0), 1) : 0
            return simd_length(a + d * t - point)
        }
        return min(toSquare(a), toSquare(b), toWay(low), toWay(high), toWay(SIMD2(low.x, high.y)), toWay(SIMD2(high.x, low.y)))
    }

    /// HSRPACE (decision 861): whether `key` is within
    /// ``Map3DScene/detailRadius`` of the way `target` moving at `velocity`
    /// is on (``way(target:velocity:)``): built in full however far ahead.
    /// Never while the target stands still.
    public static func isOnTheWay(_ key: Key, target: Map3DPoint, velocity: SIMD2<Float>) -> Bool {
        guard let end = way(target: target, velocity: velocity) else { return false }
        return distance(of: key, toWayFrom: target, to: end) <= Map3DScene.detailRadius
    }

    // MARK: - The window

    /// Faster than this, in metres a second, nothing is built or let go:
    /// a block takes about 0.1–0.2 s to build (decision 358's numbers),
    /// and a target this fast passes chunks quicker than they are built.
    /// A High Speed Rail train at ten times real time is 833 m/s.
    public static let fastest: Float = 1_000
    /// How often the window plans while nothing has just been built, in
    /// seconds.
    public static let interval: Double = 0.25
    /// HSRPACE (decision 861): the most blocks built at once: a second
    /// only while the target is within ``hurry`` of what it holds.
    public static let builders = 2
    /// HSRPACE (decision 861): how near the target the soonest chunk of a
    /// second block must be, in metres: some 3.6 s ahead of a High Speed
    /// Rail train at ten times real time, more than a block takes.
    public static let hurry: Float = 3_000

    /// The chunks a 3D map has and is building, and what to do next as
    /// its camera moves: the scene first built (``init(scene:map:kept:)``),
    /// then a block at a time ahead of the camera (``step(target:at:)``),
    /// placed when it is built unless the scene was built anew since
    /// (``finished(_:generation:)``).
    public struct Window: Sendable {
        public let grid: Map3DStreaming
        /// The scene's own whole chunks: never let go, so the view it
        /// opened on (the whole scene, from far out) stays.
        public private(set) var scene: Set<Key>
        /// Decision 711: the scene's chunks let go when memory ran short
        /// (``shed(farFrom:radius:)``): built again, and the scene's
        /// again, when the camera sees that far.
        public private(set) var gone: Set<Key> = []
        /// The chunks built whole, in the scene or since.
        public private(set) var built: Set<Key>
        /// Of them, those kept from before the scene was built anew,
        /// built again when nothing else is wanted.
        public private(set) var stale: Set<Key>
        /// Decision 368: of them, those built without the city in full
        /// (``Map3DScene/Chunk/coarse``), built again in full when the
        /// target comes within ``Map3DScene/detailRadius``.
        public private(set) var coarse: Set<Key>
        /// HSRPACE (decision 861): the blocks being built (at most
        /// ``Map3DStreaming/builders``), each with where it is built in full
        /// round (``buildingAround``, ``buildingAhead``).
        private var inFlight: [(keys: [Key], around: Map3DPoint, ahead: Map3DPoint?)] = []
        /// The chunks being built, for the scene ``generation``.
        public var building: [Key] { inFlight.flatMap(\.keys) }
        /// Decision 368: the scene point the newest block is built in full round
        /// (``Map3DScene/chunks(_:of:world:snapshot:skyline:baseMap:cityTiles:footprints:heights:lineBands:railways:temples:noBuild:trackCover:detail:)``'s
        /// `detail`): the target when it was asked for.
        public private(set) var buildingAround = Map3DPoint(0, 0, 0)
        /// HSRPACE (decision 861): with it, the block is built in full
        /// round the way from ``buildingAround`` to here
        /// (``Map3DStreaming/way(target:velocity:)``), not round a point.
        public private(set) var buildingAhead: Map3DPoint?
        public let generation: Int
        public private(set) var motion = Motion()
        private var planned: Double?

        /// The window of `scene` on a map of `map` (world units), the
        /// `generation`th scene built for the view; with `kept`, the chunks
        /// the view keeps from the scene before it (where the new one has
        /// none whole), built again in time.
        public init(scene: Map3DScene, map: WorldRegion, generation: Int = 0, kept: Set<Key> = []) {
            self.init(grid: Map3DStreaming(scene: scene, map: map), region: scene.region, generation: generation, kept: kept,
                      coarse: Set(scene.chunks.filter(\.coarse).map { Key(column: $0.column, row: $0.row) }))
        }

        /// The same for a scene of `region` round `grid`'s origin, whose
        /// chunks at `coarse` are built without the city in full.
        public init(grid: Map3DStreaming, region: WorldRegion, generation: Int = 0, kept: Set<Key> = [], coarse: Set<Key> = []) {
            self.grid = grid
            let whole = grid.keys(within: region)
            scene = whole
            stale = kept.subtracting(whole)
            built = whole.union(stale)
            self.coarse = coarse.intersection(whole)
            self.generation = generation
        }

        /// The camera's target is at `target` at time `seconds`: what to
        /// let go now (built since the scene), and the block to start
        /// building, if none is being built and one is wanted. Plans every ``interval`` (at once after
        /// a block is built); nothing while the target runs faster than
        /// ``fastest``.
        ///
        /// Decision 578: `stops` are the scene points the followed train
        /// runs to (the stop ahead's platform): once nothing the target's
        /// own plan wants is missing, the chunks round them
        /// (``Map3DStreaming/stationRadius``) are built, in full, and kept
        /// while they are `stops`; the target's order is not changed.
        ///
        /// Decision 583 (CABLEFOLLOW): with `ahead` (scene x and z), the
        /// way the followed vehicle runs, the strip ahead lies that way,
        /// not the way the target moved: a cabin's rope ahead is built
        /// while the window view looks out at the side, while it crawls
        /// through a station and while the game stands still.
        ///
        /// Decision 711: `sight` is how far from the target the camera
        /// sees, in metres (its distance): the scene's chunks let go
        /// (``gone``) within it are built again, after everything else.
        ///
        /// Decision 714 (MAP3D-FAR): with `camera`, the chunks it sees
        /// (``Map3DStreaming/seen(by:slack:)``) are built too, the nearest
        /// first, once nothing the target's own plan wants is missing, and
        /// kept while it sees them (a little past, ``Map3DStreaming/slack``):
        /// pulled out, the view sees several times further than
        /// ``Map3DStreaming/around``, and showed the scene it opened on as
        /// a strip of ground in the middle of nothing. Without `room` (the
        /// scene's buffers are over what the device holds, decision 711)
        /// none of them is built, and those standing are kept.
        public mutating func step(target: Map3DPoint, at seconds: Double, stops: [Map3DPoint] = [],
                                  ahead: SIMD2<Float>? = nil, sight: Float = 0,
                                  seeing camera: Map3DCamera? = nil, room: Bool = true) -> (drop: [Key], build: [Key]) {
            motion.update(target: target, at: seconds)
            if let planned, seconds - planned < Map3DStreaming.interval { return ([], []) }
            planned = seconds
            let velocity = Self.velocity(motion: motion.velocity, ahead: ahead)
            guard (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() <= Map3DStreaming.fastest else { return ([], []) }
            let plan = grid.plan(target: target, velocity: velocity, built: built, building: Set(building), keeping: stops)
            // Decision 714: what the camera sees is kept.
            let inSight = camera.map { Set(grid.seen(by: $0, slack: Map3DStreaming.slack)) } ?? []
            let drop = plan.drop.filter { !scene.contains($0) && !inSight.contains($0) }
            built.subtract(drop)
            stale.subtract(drop)
            coarse.subtract(drop)
            // HSRPACE (decision 861): a second block only to catch up.
            guard inFlight.count < Map3DStreaming.builders else { return (drop, []) }
            let catchingUp = !inFlight.isEmpty
            let underway = Set(building)
            // HSRPACE (decision 861): moving, every block is built in full
            // round the way ahead, as far as ``Map3DStreaming/inFullAhead``,
            // as well as round the target.
            let way = Map3DStreaming.way(target: target, velocity: velocity)
            var around = target, wayEnd = way
            // HSRPACE: the coarse chunks to build in full: near the target
            // (decision 368) and on the way ahead, the soonest reached first.
            let upgrade = coarse.subtracting(underway).compactMap { key -> (key: Key, soon: Float)? in
                let distance = Map3DStreaming.distance(of: key, to: target)
                if distance <= Map3DScene.detailRadius { return (key, distance) }
                guard Map3DStreaming.isOnTheWay(key, target: target, velocity: velocity) else { return nil }
                return (key, grid.wantedIn(key, target: target, velocity: velocity) ?? distance)
            }.sorted { ($0.soon, $0.key) < ($1.soon, $1.key) }
            // HSRPACE: the block filled with the chunks wanted a little
            // later (as far as the plan keeps them), while the scene's
            // buffers are within the device's budget; or, reached sooner
            // than the first missing chunk, the coarse ones.
            let fill = room ? Set(grid.wantedWithin(slack: Map3DStreaming.slack, target: target, velocity: velocity).map(\.key))
                .subtracting(built).subtracting(underway) : []
            var block = Map3DStreaming.block(of: plan.build, filling: fill)
            var soonest = plan.build.first.flatMap { grid.wantedIn($0, target: target, velocity: velocity) } ?? .infinity
            if let first = upgrade.first, first.soon < soonest {
                block = Map3DStreaming.block(of: upgrade.map(\.key))
                soonest = first.soon
            }
            // HSRPACE: while a block is built, a second one only when the
            // target is about to reach what it holds (``Map3DStreaming/hurry``):
            // a device too slow for one at a time keeps up on two cores,
            // and otherwise the window keeps to one.
            if catchingUp {
                guard simd_length(velocity) >= Map3DStreaming.still, soonest <= Map3DStreaming.hurry, !block.isEmpty else { return (drop, []) }
                inFlight.append((block, around, wayEnd))
                buildingAround = around
                buildingAhead = wayEnd
                return (drop, block)
            }
            func nearest(_ keys: some Sequence<Key>) -> [Key] {
                keys.map { (key: $0, distance: Map3DStreaming.distance(of: $0, to: target)) }.sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }.map(\.key)
            }
            let stopKeys = stops.flatMap { stop in grid.area(round: stop, radius: Map3DStreaming.stationRadius).map { (key: $0, stop: stop) } }
            if block.isEmpty {
                // Decision 578: the chunks round the stops ahead, missing or
                // simplified, the nearest to a stop first.
                let missing = stopKeys.filter { !building.contains($0.key) && (!built.contains($0.key) || coarse.contains($0.key)) }
                block = Map3DStreaming.block(of: missing.map(\.key))
                if let first = block.first, let stop = missing.first(where: { $0.key == first })?.stop {
                    around = stop
                    wayEnd = nil
                }
            }
            if block.isEmpty, room, let camera {
                // Decision 714: what the camera sees and is not there.
                block = Map3DStreaming.block(of: grid.seen(by: camera).filter { !built.contains($0) })
            }
            if block.isEmpty {
                // Decision 368: nothing missing: the coarse chunks near the
                // target in full, the nearest first; HSRPACE: and those on
                // the way ahead.
                block = Map3DStreaming.block(of: upgrade.map(\.key))
            }
            if block.isEmpty {
                // The kept chunks again, the soonest first.
                block = Map3DStreaming.block(of: grid.wanted(target: target, velocity: velocity).filter(stale.contains))
            }
            if block.isEmpty {
                // Decision 368: the chunks in full left far behind (the
                // scene's are never let go, the others only beyond the
                // plan's reach) simplified again, so the city in full stays
                // round the target only.
                // HSRPACE (decision 861): moving, only the scene's own
                // (those built since are let go behind the target soon
                // after: built again simplified, they kept a High Speed
                // Rail train's ground waiting), and not those on the way.
                let moving = simd_length(velocity) >= Map3DStreaming.still
                let far = built.subtracting(coarse).subtracting(stale).subtracting(stopKeys.map(\.key))
                    .filter { Map3DStreaming.distance(of: $0, to: target) > Map3DScene.detailRadius + Map3DStreaming.slack
                        && (!moving || scene.contains($0)) && !Map3DStreaming.isOnTheWay($0, target: target, velocity: velocity) }
                block = Map3DStreaming.block(of: nearest(far))
            }
            if block.isEmpty, !gone.isEmpty {
                // Decision 711: the scene's chunks let go, where the camera
                // now sees.
                // MEM3D (decision 749 續): with `camera`, only those it
                // sees (or round the target), so what ``shed(farFrom:radius:seeing:)``
                // let go off the screen is not built again at once.
                block = Map3DStreaming.block(of: nearest(gone.filter { key in
                    let distance = Map3DStreaming.distance(of: key, to: target)
                    guard !built.contains(key), distance <= sight else { return false }
                    guard let camera else { return true }
                    return distance <= Map3DStreaming.around || grid.isSeen(key, by: camera, slack: Map3DStreaming.slack)
                }))
            }
            if !block.isEmpty {
                inFlight.append((block, around, wayEnd))
                buildingAround = around
                buildingAhead = wayEnd
            }
            return (drop, block)
        }

        /// Decision 711 (MAP3D-CAP): memory runs short, or the scene's
        /// buffers are over their budget: every chunk built farther than
        /// `radius` metres from `target` (no nearer than
        /// ``Map3DStreaming/around``, which the plan keeps) is let go, the
        /// scene's own too, the farthest first. They are built again only
        /// if the camera's target comes near them.
        ///
        /// MEM3D (decision 749 續): with `camera` (the scene's buffers over
        /// their budget, not memory short), the chunks it does not see
        /// are let go instead, however near (but no nearer than
        /// ``Map3DStreaming/around``, nor in the strip ahead the plan
        /// keeps), and those it sees are kept however far: pulled out
        /// over the heaviest save, the 600 MB budget let go of the scene's
        /// chunks at the screen's edge and left them empty.
        public mutating func shed(farFrom target: Map3DPoint, radius: Float, seeing camera: Map3DCamera? = nil) -> [Key] {
            let reach = max(radius, Map3DStreaming.around)
            var candidates = built.subtracting(building).map { (key: $0, distance: Map3DStreaming.distance(of: $0, to: target)) }
            if let camera {
                let velocity = Self.velocity(motion: motion.velocity, ahead: nil)
                let kept = Set(grid.wantedWithin(slack: Map3DStreaming.slack, target: target, velocity: velocity).map(\.key))
                candidates = candidates.filter { $0.distance > Map3DStreaming.around && !kept.contains($0.key)
                    && !grid.isSeen($0.key, by: camera, slack: Map3DStreaming.slack) }
            } else {
                candidates = candidates.filter { $0.distance > reach }
            }
            let far = candidates.sorted { ($0.distance, $0.key) > ($1.distance, $1.key) }.map(\.key)
            letGo(far)
            return far
        }

        /// Decision 711: `keys` are no longer held (let go by
        /// ``shed(farFrom:radius:)`` of the window before this one, of a
        /// scene built again only in part): not built, nor the scene's
        /// until built again (``gone``).
        public mutating func letGo(_ keys: some Sequence<Key>) {
            let left = Set(keys).subtracting(building)
            gone.formUnion(left.intersection(scene))
            built.subtract(left)
            stale.subtract(left)
            coarse.subtract(left)
            scene.subtract(left)
        }

        /// Decision 583: the velocity the plan reads: `ahead`'s way, as fast
        /// as the target moves but at least twice ``Map3DStreaming/still``
        /// so the strip ahead is there; the target's own motion without it.
        public static func velocity(motion: SIMD2<Float>, ahead: SIMD2<Float>?) -> SIMD2<Float> {
            guard let ahead, simd_length(ahead) > 0 else { return motion }
            let way = ahead / simd_length(ahead)
            return way * max(simd_length(motion), 2 * Map3DStreaming.still)
        }

        /// Decision 578: whether the chunks round scene point `point` (the
        /// platform's eye) are all built, as far as
        /// ``Map3DStreaming/stationReady``.
        public func isBuilt(round point: Map3DPoint) -> Bool {
            grid.area(round: point, radius: Map3DStreaming.stationReady).allSatisfy(built.contains)
        }

        /// Decision 606 (續): the same, with none of those chunks built
        /// without the city in full (``coarse``): a followed real train's
        /// surroundings as the camera shows them.
        public func isBuiltInFull(round point: Map3DPoint) -> Bool {
            grid.area(round: point, radius: Map3DStreaming.stationReady).allSatisfy { built.contains($0) && !coarse.contains($0) }
        }

        /// The block `keys` built for the `generation`th scene is done:
        /// whether to place it. A block for a scene since built anew is not
        /// placed.
        public mutating func finished(_ keys: [Key], generation: Int) -> Bool {
            guard generation == self.generation, let index = inFlight.firstIndex(where: { $0.keys == keys }) else { return false }
            let done = inFlight.remove(at: index)
            built.formUnion(keys)
            stale.subtract(keys)
            // Decision 711: the scene's chunks let go are the scene's again.
            scene.formUnion(gone.intersection(keys))
            gone.subtract(keys)
            for key in keys {
                if Map3DStreaming.distance(of: key, toWayFrom: done.around, to: done.ahead) > Map3DScene.detailRadius { coarse.insert(key) } else { coarse.remove(key) }
            }
            planned = nil
            return true
        }
    }

    // MARK: - Motion

    /// The camera target's motion, from where it was frame by frame:
    /// smoothed over about ``smoothing`` seconds, so a train's steady run
    /// gives its heading and a single frame's jump does not.
    public struct Motion: Sendable {
        public static let smoothing: Double = 0.5
        /// A jump further than this in one step (metres) is the camera
        /// sent somewhere, not moving: the motion starts again from there.
        public static let jump: Float = 2_000
        public private(set) var velocity = SIMD2<Float>(0, 0)
        private var last: (point: SIMD2<Float>, seconds: Double)?

        public init() {}

        public mutating func update(target: Map3DPoint, at seconds: Double) {
            let point = SIMD2(target.x, target.z)
            defer { last = (point, seconds) }
            guard let last else { return }
            let elapsed = seconds - last.seconds
            guard elapsed > 0 else { return }
            let moved = point - last.point
            if simd_length(moved) > Self.jump {
                velocity = .zero
                return
            }
            let now = moved / Float(elapsed)
            let weight = Float(min(1, elapsed / Self.smoothing))
            velocity += (now - velocity) * weight
        }
    }
}

private func simd_clamp(_ value: SIMD2<Float>, _ low: SIMD2<Float>, _ high: SIMD2<Float>) -> SIMD2<Float> {
    SIMD2(min(max(value.x, low.x), high.x), min(max(value.y, low.y), high.y))
}

private func simd_length(_ value: SIMD2<Float>) -> Float {
    (value.x * value.x + value.y * value.y).squareRoot()
}
