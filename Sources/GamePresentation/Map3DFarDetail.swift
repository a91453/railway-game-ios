// Decision 709: seen from far out, the 3D map leaves out what is too small
// to see. From 1.6 km out every chunk is drawn simplified (decision 238),
// and the same simplified city was drawn from there to the farthest the
// camera goes (12 km), where a phone's screen holds some 500 chunks: a
// whole-Taiwan game on an iPhone 17 Pro drew 2.7 million triangles there,
// two thirds of them buildings a point or less across.
//
// So the simplified city, the lesser roads and the ground shadows are
// kept in the order of their size, the largest first, and a chunk drawn
// from afar draws the first so many of each: the farther the camera, the
// larger the smallest thing drawn (``smallest(distance:)``). Nothing is
// built twice and nothing more is kept in memory: the same index and
// instance buffers, drawn shorter. As the camera pulls out the smallest
// things go first, a size class at a time, each when it is about a point
// and a half across on a phone.

/// Decision 709: how much of what is drawn from afar a camera's distance
/// leaves out.
public enum Map3DFarDetail {
    /// The size classes: a thing's ``rank(size:)`` is 0 for the smallest
    /// (under 1.4 m) and one more each time it is 1.41 times the size;
    /// the last is everything from 362 m and what is always drawn.
    public static let ranks = 18
    public static let always = ranks - 1

    /// From this distance out the smallest things are left out; nearer,
    /// everything is drawn as before. Past
    /// ``Map3DCamera/detailDistance`` and its margin (1,824 m), so no
    /// chunk drawn in full is beside one thinned.
    public static let from: Float = 2_000
    /// Metres of the smallest thing drawn for each metre the camera is
    /// past ``from``: 32 m at ``Map3DCamera/farthest`` (12 km), where a
    /// point of an iPhone's screen is 19 m of ground. At 0.0034 the
    /// farthest view drew things from 45 m and a town's streets (the
    /// tertiary roads count as 40 m) were gone with its houses; at this
    /// the streets stay (measured on an iPhone, decision 709's later
    /// part).
    public static let slope: Float = 0.0032

    /// The most triangles the still scene's chunks are drawn with from
    /// ``from`` out, whatever the map and however much of it is built: as
    /// many as decision 417 lets everything that moves have on the fastest
    /// phones.
    public static let budget = 1_000_000

    /// The size, in metres, of the smallest thing drawn from `distance`.
    public static func smallest(distance: Float) -> Float {
        max(0, distance - from) * slope
    }

    /// The smallest size of each class, in metres: 1, 1.41, 2, … 362.
    static let sizes: [Float] = (0..<ranks).map { rank in
        (0..<rank).reduce(Float(1)) { size, _ in size * 1.414_213_5 }
    }

    /// The class of a thing `size` metres across.
    public static func rank(size: Float) -> Int {
        guard !size.isNaN else { return 0 }
        return max(0, (sizes.firstIndex { $0 > size * 1.000_01 } ?? ranks) - 1)
    }

    /// The level a camera at `distance` draws: the classes from it up
    /// (0: everything), the smallest of them no smaller than
    /// ``smallest(distance:)``.
    public static func level(distance: Float) -> Int {
        let size = smallest(distance: distance)
        guard size > 1 else { return 0 }
        return sizes.firstIndex { $0 * 1.000_01 >= size } ?? always
    }

    /// The level at `distance` when the last frame drew `was`: the same
    /// while the camera is within ``margin`` of where it would change, so
    /// a camera resting at a step does not flicker between two levels.
    public static func level(distance: Float, was: Int) -> Int {
        min(max(was, level(distance: distance / margin)), level(distance: distance * margin))
    }

    /// ``level(distance:was:)``'s margin either way.
    public static let margin: Float = 1.03

    /// The sizes the roads and what lies on them count as: not their
    /// width (a street 8 m wide is a line across the whole screen), but
    /// how far out the 2D map still draws its kind. The main roads are
    /// always drawn.
    static func size(of kind: Map3DBaseMap.RoadKind) -> Float {
        switch kind {
        case .service: 10
        case .minor: 20
        case .tertiary: 40
        case .secondary: 80
        case .primary, .trunk, .motorway: .infinity
        }
    }
    /// The pavements beside a road, its centre line and the paint at its
    /// junctions.
    static let sidewalks: Float = 10
    static let centreLines: Float = 6
    static let roadMarkings: Float = 4
    /// What carries a road bridge (girders, piers, parapets), under its
    /// deck seen from above.
    static let bridgeStructure: Float = 12
    /// A ground shadow counts as this share of what casts it: a soft rim
    /// a few metres wide round it.
    static let shadowShare: Float = 0.5

    /// A run of a mesh's indices (and of its boxes) built as one thing,
    /// and its class.
    struct Part: Sendable {
        var first: Int
        var count: Int
        var firstBox = 0
        var boxCount = 0
        var rank: Int
    }

    /// How many of a mesh's indices (or boxes) each level draws, the mesh
    /// in the order ``order(_:parts:from:)`` leaves it; with none
    /// (``isEmpty``), every level draws all.
    /// What a chunk draws from afar at one level: how many of its base
    /// mesh's indices, of its far mesh's, of its boxes (and the triangles
    /// they make) and of its shadows' indices. Each is the first so many.
    public struct Counts: Equatable, Sendable {
        public var base: Int
        public var far: Int
        public var boxes: Int
        public var boxTriangles: Int
        public var shadows: Int
    }

    public struct Steps: Equatable, Sendable {
        public var counts: [Int] = []

        public init() {}

        public var isEmpty: Bool { counts.isEmpty }

        /// How many of `all` level `level` draws.
        public func count(at level: Int, of all: Int) -> Int {
            guard !counts.isEmpty, level > 0 else { return all }
            return min(all, counts[min(level, counts.count - 1)])
        }
    }

    /// `mesh`'s indices from `from` on put in the order of their parts'
    /// classes, the largest first (those in no part first of all, as
    /// always drawn), each class in the order it was built; and its boxes
    /// the same. `parts` are in the order they were built; when they do
    /// not fit the mesh (it was changed since), nothing is moved and
    /// every level draws all.
    static func order(_ mesh: inout Map3DMesh, parts: [Part], from: Int = 0) -> (indices: Steps, boxes: Steps) {
        guard !parts.isEmpty else { return (Steps(), Steps()) }
        var at = from, box = 0
        for part in parts {
            guard part.first >= at, part.count >= 0, part.first + part.count <= mesh.indices.count,
                  part.firstBox >= box, part.boxCount >= 0, part.firstBox + part.boxCount <= mesh.boxes.count
            else { return (Steps(), Steps()) }
            at = part.first + part.count
            box = part.firstBox + part.boxCount
        }
        // Each class's indices and boxes, in the order built.
        var indices = [[UInt32]](repeating: [], count: ranks), boxes = [[Map3DBoxInstance]](repeating: [], count: ranks)
        indices[always].reserveCapacity(mesh.indices.count - from)
        at = from
        box = 0
        for part in parts {
            indices[always] += mesh.indices[at..<part.first]
            boxes[always] += mesh.boxes[box..<part.firstBox]
            indices[part.rank] += mesh.indices[part.first..<part.first + part.count]
            boxes[part.rank] += mesh.boxes[part.firstBox..<part.firstBox + part.boxCount]
            at = part.first + part.count
            box = part.firstBox + part.boxCount
        }
        indices[always] += mesh.indices[at...]
        boxes[always] += mesh.boxes[box...]
        var ordered = Array(mesh.indices[..<from]), orderedBoxes: [Map3DBoxInstance] = []
        ordered.reserveCapacity(mesh.indices.count)
        orderedBoxes.reserveCapacity(mesh.boxes.count)
        var steps = (indices: Steps(), boxes: Steps())
        steps.indices.counts = [Int](repeating: 0, count: ranks)
        steps.boxes.counts = [Int](repeating: 0, count: ranks)
        for rank in (0..<ranks).reversed() {
            ordered += indices[rank]
            orderedBoxes += boxes[rank]
            steps.indices.counts[rank] = ordered.count
            steps.boxes.counts[rank] = orderedBoxes.count
        }
        mesh.reorder(indices: ordered, boxes: orderedBoxes)
        if mesh.boxes.isEmpty { steps.boxes = Steps() }
        return steps
    }

    /// `other` added to `mesh`, whose indices ``order(_:parts:from:)`` put
    /// in order (`steps`), as always drawn: its indices after those every
    /// level draws, and every level drawing them too. A station's studied
    /// building (decision 625) is added after the city's look, in its own
    /// colours; added at the end, only level 0 drew it (REVIEW-L20 P2-1).
    /// With no `steps` every level draws all, and it is added at the end.
    static func appendAlwaysDrawn(_ other: Map3DMesh, to mesh: inout Map3DMesh, steps: inout Steps) {
        let before = mesh.indices.count
        mesh.append(other)
        let added = mesh.indices.count - before
        guard !steps.isEmpty, added > 0 else { return }
        let always = min(steps.counts[Self.always], before)
        var ordered = Array(mesh.indices[..<always])
        ordered.reserveCapacity(mesh.indices.count)
        ordered += mesh.indices[before...]
        ordered += mesh.indices[always..<before]
        mesh.reorder(indices: ordered, boxes: mesh.boxes)
        steps.counts = steps.counts.map { $0 + added }
    }
}

extension Map3DScene.Chunk {
    /// Decision 709: how many of ``mesh``'s indices a chunk drawn from
    /// afar at `level` draws: its ground, track and roads, less the
    /// lesser roads too small to see.
    public func baseIndexCount(at level: Int) -> Int { baseSteps.count(at: level, of: baseIndexCount) }
    /// Of ``far``'s indices.
    public func farIndexCount(at level: Int) -> Int { farSteps.count(at: level, of: far.indices.count) }
    /// Of ``farBoxes``.
    public func farBoxCount(at level: Int) -> Int { farBoxSteps.count(at: level, of: farBoxes.count) }
    /// Of ``shadows``' indices.
    public func shadowIndexCount(at level: Int) -> Int { shadowSteps.count(at: level, of: shadows.indices.count) }

    /// Decision 709: what the chunk draws from afar at each level
    /// (``Map3DFarDetail/level(distance:)``), for the Metal view to keep
    /// beside its buffers.
    public var farLevels: [Map3DFarDetail.Counts] {
        (0..<Map3DFarDetail.ranks).map { level in
            let boxes = farBoxCount(at: level)
            return Map3DFarDetail.Counts(base: baseIndexCount(at: level), far: farIndexCount(at: level), boxes: boxes,
                                         boxTriangles: farBoxes.prefix(boxes).reduce(0) { $0 + $1.triangleCount },
                                         shadows: shadowIndexCount(at: level))
        }
    }

    /// Decision 709: the triangles and draw calls of the chunk drawn from
    /// afar at `level`, as the Metal view draws it: its ground, its
    /// simplified city, the city's boxes and its shadows.
    public func farFrame(at level: Int) -> (triangles: Int, drawCalls: Int) {
        let drawn = farLevels[min(max(level, 0), Map3DFarDetail.always)]
        let counts = [drawn.base / 3, drawn.far / 3, drawn.boxTriangles, drawn.shadows / 3]
        return (counts.reduce(0, +), counts.filter { $0 > 0 }.count)
    }
}
