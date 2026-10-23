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

    /// Whether any of `key`'s square is on the map.
    func isOnMap(_ key: Key) -> Bool {
        let square = region(of: key)
        return square.maxX > map.minX && square.minX < map.maxX && square.maxY > map.minY && square.minY < map.maxY
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

    private func wantedWithin(slack: Float, target: Map3DPoint, velocity: SIMD2<Float>) -> [(key: Key, soon: Float)] {
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
    public func plan(target: Map3DPoint, velocity: SIMD2<Float>, built: Set<Key>, building: Set<Key> = []) -> Plan {
        let build = wanted(target: target, velocity: velocity).filter { !built.contains($0) && !building.contains($0) }
        let kept = Set(wantedWithin(slack: Self.slack, target: target, velocity: velocity).map(\.key))
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

    // MARK: - The window

    /// Faster than this, in metres a second, nothing is built or let go:
    /// a block takes about 0.1–0.2 s to build (decision 358's numbers),
    /// and a target this fast passes chunks quicker than they are built.
    /// A High Speed Rail train at ten times real time is 833 m/s.
    public static let fastest: Float = 1_000
    /// How often the window plans while nothing has just been built, in
    /// seconds.
    public static let interval: Double = 0.25

    /// The chunks a 3D map has and is building, and what to do next as
    /// its camera moves: the scene first built (``init(scene:map:kept:)``),
    /// then a block at a time ahead of the camera (``step(target:at:)``),
    /// placed when it is built unless the scene was built anew since
    /// (``finished(_:generation:)``).
    public struct Window: Sendable {
        public let grid: Map3DStreaming
        /// The scene's own whole chunks: never let go, so the view it
        /// opened on (the whole scene, from far out) stays.
        public let scene: Set<Key>
        /// The chunks built whole, in the scene or since.
        public private(set) var built: Set<Key>
        /// Of them, those kept from before the scene was built anew,
        /// built again when nothing else is wanted.
        public private(set) var stale: Set<Key>
        /// Decision 368: of them, those built without the city in full
        /// (``Map3DScene/Chunk/coarse``), built again in full when the
        /// target comes within ``Map3DScene/detailRadius``.
        public private(set) var coarse: Set<Key>
        /// The block being built, and the scene it is for.
        public private(set) var building: [Key] = []
        /// Decision 368: the scene point the block is built in full round
        /// (``Map3DScene/chunks(_:of:world:snapshot:skyline:baseMap:cityTiles:heights:lineBands:railways:temples:noBuild:trackCover:detail:)``'s
        /// `detail`): the target when it was asked for.
        public private(set) var buildingAround = Map3DPoint(0, 0, 0)
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
        public mutating func step(target: Map3DPoint, at seconds: Double) -> (drop: [Key], build: [Key]) {
            motion.update(target: target, at: seconds)
            if let planned, seconds - planned < Map3DStreaming.interval { return ([], []) }
            planned = seconds
            let velocity = motion.velocity
            guard (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() <= Map3DStreaming.fastest else { return ([], []) }
            let plan = grid.plan(target: target, velocity: velocity, built: built, building: Set(building))
            let drop = plan.drop.filter { !scene.contains($0) }
            built.subtract(drop)
            stale.subtract(drop)
            coarse.subtract(drop)
            guard building.isEmpty else { return (drop, []) }
            var block = Map3DStreaming.block(of: plan.build)
            func nearest(_ keys: some Sequence<Key>) -> [Key] {
                keys.map { (key: $0, distance: Map3DStreaming.distance(of: $0, to: target)) }.sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }.map(\.key)
            }
            if block.isEmpty {
                // Decision 368: nothing missing: the coarse chunks near the
                // target in full, the nearest first.
                block = Map3DStreaming.block(of: nearest(coarse.filter { Map3DStreaming.distance(of: $0, to: target) <= Map3DScene.detailRadius }))
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
                let far = built.subtracting(coarse).subtracting(stale)
                    .filter { Map3DStreaming.distance(of: $0, to: target) > Map3DScene.detailRadius + Map3DStreaming.slack }
                block = Map3DStreaming.block(of: nearest(far))
            }
            building = block
            if !block.isEmpty { buildingAround = target }
            return (drop, block)
        }

        /// The block `keys` built for the `generation`th scene is done:
        /// whether to place it. A block for a scene since built anew is not
        /// placed.
        public mutating func finished(_ keys: [Key], generation: Int) -> Bool {
            guard generation == self.generation, keys == building else { return false }
            building = []
            built.formUnion(keys)
            stale.subtract(keys)
            for key in keys {
                if Map3DStreaming.distance(of: key, to: buildingAround) > Map3DScene.detailRadius { coarse.insert(key) } else { coarse.remove(key) }
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
