import GameCore

// Decision 424's second sequel: the player's bus routes are laid in the 3D
// scene off the main actor. Laying them reads the base map's tiles, builds
// its road network and finds each saved route's way (``BusRoads``), which
// on the frame's path made the 3D map stop for a moment the first time it
// drew the buses and whenever the routes changed. The frame now asks here:
// it gets the buses laid, the ones laid before for the same scene while
// the new ones are laid (the buses keep to their old ways for a moment), or
// none, and never waits.

extension Map3DBuses {
    /// When the buses are laid and which laying is kept: asked once a
    /// frame, it starts a laying off the main actor and hands it out once
    /// done, unless a later ask replaced it.
    @MainActor
    public final class Layer {
        /// What is being laid, and which laying it is, so that one a later
        /// ask replaced finds out when it is done.
        struct Laying {
            let signature: Signature
            let scene: SceneKey
            let serial: Int
            let task: Task<Void, Never>
        }

        private(set) var laid: Map3DBuses?
        private(set) var laying: Laying?
        /// How many layings were started, for a test.
        private(set) var started = 0

        public init() {}

        /// The buses of `signature` laid in `scene`: once laid, those; while
        /// they are being laid, the ones laid before if in the same scene,
        /// else `nil`. Starts laying them from `world`, `palette` and
        /// `roads` (what `signature` was made from) unless they are already
        /// being laid.
        public func buses(_ signature: Signature, world: GameWorld, in scene: Map3DScene, palette: LinePalette,
                          roads: BusRoads?) -> Map3DBuses? {
            if let laid, laid.isLaid(from: signature, in: scene) {
                laying?.task.cancel()
                laying = nil
                return laid
            }
            let key = SceneKey(scene)
            if laying?.signature != signature || laying?.scene != key {
                laying?.task.cancel()
                started += 1
                let serial = started
                let task = Task.detached(priority: .userInitiated) { [weak self] in
                    let buses = Map3DBuses(world: world, scene: scene, palette: palette, roads: roads)
                    guard !Task.isCancelled else { return }
                    await self?.finish(buses, serial: serial)
                }
                laying = Laying(signature: signature, scene: key, serial: serial, task: task)
            }
            return laid?.scene == key ? laid : nil
        }

        /// Keeps `buses` unless a later ask started another laying.
        private func finish(_ buses: Map3DBuses, serial: Int) {
            guard laying?.serial == serial else { return }
            laid = buses
            laying = nil
        }
    }
}
