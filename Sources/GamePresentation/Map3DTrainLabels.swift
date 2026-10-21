import GameCore

/// Decision 314: close up, a small label over the front of a few trains
/// near the middle of the 3D map: its line's badge (decision 216) and its
/// riders over its capacity. Ported from `Railway/taiwan-rail-reference-clean/`
/// rail-3d's `vehicleMarkers` (`integration/readability.js`), which each
/// frame projects the trains to the screen, skips those off it, and tags
/// them only past a zoom; here only within ``reach`` and the few nearest
/// the middle, so the labels never cover the scene.
public struct Map3DTrainLabels: Sendable {
    /// What a train's label says.
    public struct Info: Hashable, Sendable {
        public let line: LineID
        /// The line's code, as its badge shows it.
        public let code: String
        public let riders: Int64
        public let capacity: Int64
    }

    /// A label on the screen: its train, what it says, and where its foot
    /// is, in the view's points from the top left.
    public struct Label: Hashable, Sendable {
        public let train: TrainID
        public let info: Info
        public let x: Float
        public let y: Float
    }

    /// The camera's distance from its target within which labels show, in
    /// metres: about where a car is as long as a finger is wide.
    public static let reach: Float = 400
    /// The most labels at once.
    public static let most = 3
    /// How far from the middle a train's front may be, as a share of half
    /// the view each way.
    public static let middle: Float = 0.6

    /// Each passenger train on a line, by train.
    public let infos: [TrainID: Info]

    public init(infos: [TrainID: Info]) {
        self.infos = infos
    }

    /// The trains of `world`'s lines and what their labels say. A freight
    /// train or one on no line has none.
    public init(world: GameWorld) {
        let codes = LineBadge.codes(for: world.lines)
        var infos: [TrainID: Info] = [:]
        for line in world.lines {
            for train in line.trains {
                guard let load = world.trainLoadInfo(of: train), !load.isFreight, let code = codes[line.id] else { continue }
                infos[train] = Info(line: line.id, code: code, riders: load.passengerCount, capacity: load.capacity)
            }
        }
        self.infos = infos
    }

    /// The labels of `heads` (``Map3DTrains/Frame/heads``) seen by
    /// `camera`: none farther than ``reach``; at most ``most``, of the
    /// trains whose fronts are within ``middle`` of the view's middle,
    /// nearest it first.
    public func labels(heads: [Map3DTrains.Head], camera: Map3DCamera) -> [Label] {
        guard camera.distance <= Self.reach, !infos.isEmpty else { return [] }
        let matrix = camera.viewProjection
        var seen: [(train: TrainID, info: Info, x: Float, y: Float, off: Float)] = []
        for head in heads {
            guard let info = infos[head.train], let clip = matrix.project(head.point),
                  clip.z >= 0, clip.z <= 1, abs(clip.x) < Self.middle, abs(clip.y) < Self.middle else { continue }
            seen.append((head.train, info, clip.x, clip.y, clip.x * clip.x + clip.y * clip.y))
        }
        seen.sort { ($0.off, $0.train) < ($1.off, $1.train) }
        let (width, height) = camera.viewport
        return seen.prefix(Self.most).map {
            Label(train: $0.train, info: $0.info, x: ($0.x + 1) / 2 * width, y: (1 - $0.y) / 2 * height)
        }
    }
}
