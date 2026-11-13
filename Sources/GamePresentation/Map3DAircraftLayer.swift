import GameCore

// Decision 713: the airfields are laid in the 3D scene off the main actor.
// Laying them places every runway, stand and taxiway point of every
// airfield of the map on the drawn ground and finds the taxiways' ways
// (``Map3DAircraft/Laid/init(world:scene:airfields:)``); on the frame's
// path that was the frame the 3D map opened on (0.27 s at an airport, a
// second and more over a city, on the owner's iPhone 17 Pro with thirteen
// airports). The frame now asks here, as it asks for the buses
// (``Map3DBuses/Layer``): it gets the airfields laid, or none while they
// are laid, and never waits. The aircraft show a moment after the scene
// does, where they would have been.

extension Map3DAircraft {
    /// When the airfields are laid and which laying is kept: asked once a
    /// frame, it starts a laying off the main actor and hands it out once
    /// done, unless a later ask replaced it.
    @MainActor
    public final class Layer {
        /// What a laying is of: the scene's place and the world's airports
        /// (as the frame's path told a laying out of date before).
        struct Key: Equatable {
            let originX: Double
            let originY: Double
            let airports: Int

            init(world: GameWorld, scene: Map3DScene) {
                originX = scene.originX
                originY = scene.originY
                airports = world.airports.count
            }
        }

        struct Laying {
            let key: Key
            let serial: Int
            let task: Task<Void, Never>
        }

        private(set) var laid: (key: Key, aircraft: Laid)?
        private(set) var laying: Laying?
        /// How many layings were started; the one kept is ``laidSerial``.
        public private(set) var started = 0
        /// Which laying ``aircraft(world:in:airfields:)`` hands out, 0 for
        /// none: it changes when the airfields are laid again.
        public private(set) var laidSerial = 0

        /// Whether the airfields are being laid: what is asked of them
        /// meanwhile has no answer yet, rather than the answer "none".
        public var isLaying: Bool { laying != nil }

        public init() {}

        /// `airfields` laid in `scene` of `world`: once laid, those; while
        /// they are being laid, `nil` (the ones laid before were for
        /// another scene or other airports). Starts laying them unless
        /// they are already being laid.
        public func aircraft(world: GameWorld, in scene: Map3DScene, airfields: RealAirfields) -> Laid? {
            let key = Key(world: world, scene: scene)
            if let laid, laid.key == key { return laid.aircraft }
            if laying?.key != key {
                laying?.task.cancel()
                started += 1
                let serial = started
                let task = Task.detached(priority: .userInitiated) { [weak self] in
                    let aircraft = Laid(world: world, scene: scene, airfields: airfields)
                    guard !Task.isCancelled else { return }
                    await self?.finish(aircraft, key: key, serial: serial)
                }
                laying = Laying(key: key, serial: serial, task: task)
            }
            return nil
        }

        /// Waits for the laying in progress, if any (for a test).
        func settle() async {
            await laying?.task.value
        }

        /// Keeps `aircraft` unless a later ask started another laying.
        private func finish(_ aircraft: Laid, key: Key, serial: Int) {
            guard laying?.serial == serial else { return }
            laid = (key, aircraft)
            laidSerial = serial
            laying = nil
        }
    }
}
