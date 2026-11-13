/// Decision 711 (MAP3D-CAP): the most triangles a frame draws of the still
/// scene (its chunks: ground, roads, track, city, street furniture and
/// ground shadows).
///
/// Decision 417's budget (``Map3DMotionBudget``) is of what moves; the
/// still scene had none, so the ladder at its lowest rung ("250,000
/// triangles") still drew whatever the chunks in view held: 5.6 to 8.9
/// million on the owner's iPhone 17 Pro
/// (`docs/research/FPS_DEVICE_2026-11-12.md` §7). The chunks in view
/// are shared out from the nearest: in full while they fit, then
/// simplified, then their ground alone, and past twice the budget not at
/// all.
public enum Map3DSceneBudget {
    /// How much of a chunk a frame draws.
    public enum Share: Int, Comparable, Sendable {
        /// As the camera's distance asks (in full or simplified).
        case whole
        /// Its city simplified though the camera is near.
        case simplified
        /// Its ground, roads and track alone: no city, no ground shadows.
        case ground
        case nothing

        public static func < (a: Share, b: Share) -> Bool { a.rawValue < b.rawValue }
    }

    /// What a chunk costs each way, in triangles.
    public struct Cost: Equatable, Sendable {
        /// As the camera asks: in full with its street furniture when it
        /// is near, else as ``simplified``.
        public var whole: Int
        public var simplified: Int
        public var ground: Int

        public init(whole: Int, simplified: Int, ground: Int) {
            self.whole = whole
            self.simplified = simplified
            self.ground = ground
        }
    }

    /// The still scene's triangles a frame on the load ladder's `tier`
    /// (``Map3DLoadLevel/tier``, which steps down under load; `nil` for a
    /// device with no tier). The owner's phone drew 1.1 to 2.0 million
    /// smoothly (GPU 14–15 ms) and 5.6 million at 38 ms.
    public static func triangles(tier: Map3DDeviceTier?) -> Int {
        switch tier {
        case .higher?: 2_400_000
        case .standard?: 1_600_000
        case .lower?, nil: 1_000_000
        }
    }

    /// How many times ``triangles(tier:)`` a frame draws at the very most:
    /// past the budget the chunks farther out keep their ground, so the
    /// far view has no holes, and past this they are not drawn.
    public static let ceiling = 2

    /// The budget a chunk is held to for what it was drawn with last
    /// frame: an eighth over (REVIEW-L20 P2-3).
    public static func kept(_ budget: Int) -> Int {
        budget + budget / 8
    }

    /// The share of each chunk of `costs`, the nearest first, within
    /// `budget` triangles. `were` is what each was given last frame (`nil`
    /// for one not in view then; none, for every chunk new): a chunk keeps
    /// a share it had, or a better one, while the frame is within
    /// ``kept(_:)`` the budget, and is given a better one than it had only
    /// within the budget itself. Without that a view a little over the
    /// budget (decision 709's far view of Taipei is 990,000 triangles of
    /// the lowest 1,000,000 before anything is built) took the city off
    /// whichever chunk was farthest that frame, another one as the camera
    /// panned.
    public static func shares(of costs: [Cost], within budget: Int, were: [Share?] = []) -> [Share] {
        var spent = 0
        return costs.indices.map { index in
            let cost = costs[index], was: Share? = index < were.count ? were[index] : nil
            // The most the frame may have drawn for this chunk to be given
            // `share`.
            func room(_ share: Share) -> Int {
                let most = share == .ground ? budget * ceiling : budget
                guard let was, was <= share else { return most }
                return kept(most)
            }
            let share: Share = if spent + cost.whole <= room(.whole) {
                .whole
            } else if spent + cost.simplified <= room(.simplified) {
                .simplified
            } else if spent + cost.ground <= room(.ground) {
                .ground
            } else {
                .nothing
            }
            switch share {
            case .whole: spent += cost.whole
            case .simplified: spent += cost.simplified
            case .ground: spent += cost.ground
            case .nothing: break
            }
            return share
        }
    }

    /// The still scene's buffers a 3D map holds at most, in bytes, on a
    /// device of memory `tier`: over it, the chunks out of the camera's
    /// reach are let go (``Map3DStreaming/Window/shed(farFrom:radius:)``).
    /// A real city's scene is some 370–520 MB (decision 455).
    public static func bytes(memory tier: DeviceMemoryTier) -> Int {
        switch tier {
        case .tight: 400 << 20
        case .roomy: 700 << 20
        case .ample: 1_000 << 20
        }
    }
}
