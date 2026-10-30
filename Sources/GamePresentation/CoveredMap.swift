/// PERF_3D_COCKPIT (2026-10-30; TestFlight 96.1, the cockpit at 9 frames
/// a second, the main thread 120 ms a frame): what the 2D map keeps doing
/// while the 3D map's full-screen cover is over it.
///
/// The cover leaves the 2D map underneath, alive, and SwiftUI keeps it
/// updating. A 3D cockpit follows a train, and so the hidden 2D map followed
/// it too: its camera moved at every frame (decision 371: each such frame
/// draws the whole map again, up to ``MapGlide/followFramesPerSecond`` a
/// second), its trains, the real trains and the rain glided at
/// ``MapGlide/framesPerSecond``, and each tick's traffic drew its track again,
/// all for a map no one could see. Under the cover none of that runs; the
/// world's ticks still reach the map's own state that is cheap to keep
/// (the trains' glide, read with the tick), and the moment the cover goes
/// the map takes up the rest at once: the traffic of the world as it is
/// then, the follow camera snapped to its train, the glides running again.
public enum CoveredMap {
    /// Whether the 2D map's camera follows the followed train's glide frame
    /// by frame (decision 182, later): a train followed, the game running
    /// and a train gliding, and the 3D map not over the 2D map.
    public static func followsGlide(following: Bool, running: Bool, trainsMoving: Bool, covered: Bool) -> Bool {
        following && running && trainsMoving && !covered
    }

    /// Whether a tick moves the 2D map's camera to the followed train: when
    /// the frames do not (`gliding`), and not under the 3D map.
    public static func followsTick(gliding: Bool, covered: Bool) -> Bool {
        !gliding && !covered
    }

    /// Whether a glide or a pulse the map would run (`wanted`: its trains,
    /// the real trains, the waits' pulse, the rain) runs frame by frame:
    /// not under the 3D map.
    public static func glides(_ wanted: Bool, covered: Bool) -> Bool {
        wanted && !covered
    }

    /// Whether a tick's traffic (the waits and the blocks the track shows)
    /// reaches the 2D map: not under the 3D map, whose closing reads it
    /// again (``refreshesOnUncover(wasCovered:covered:)``).
    public static func takesTraffic(covered: Bool) -> Bool {
        !covered
    }

    /// Whether the 2D map, as the 3D map's cover goes, reads the traffic
    /// again and snaps its follow camera to the followed train: once, when
    /// it was covered and no longer is.
    public static func refreshesOnUncover(wasCovered: Bool, covered: Bool) -> Bool {
        wasCovered && !covered
    }
}
