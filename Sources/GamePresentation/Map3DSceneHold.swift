// Review L-1 (decision 460, later): when the 3D map's scene is let go
// (the 3D map closes on a device of little memory, the start screen, a
// memory warning), a build still running cannot be stopped; letting go of
// it only meant that a 3D map opened again before it ended started a
// second build beside it, two cities' scenes at once. So a build still
// running is held until it ends, then let go, and a 3D map opened again
// meanwhile takes it. Screen state, not game state.

/// Which build of the 3D map's scene the app's scene cache holds, and
/// whether to let go of it once built.
public struct Map3DSceneHold: Equatable, Sendable {
    /// The number of the build held, if one is.
    public private(set) var building: Int?
    /// Whether the build held has ended.
    public private(set) var isBuilt = false
    /// Whether the build held is let go once it ends.
    public private(set) var dropsWhenBuilt = false
    private var started = 0

    public init() {}

    /// A new build starts and is held; returns its number.
    public mutating func start() -> Int {
        started += 1
        building = started
        isBuilt = false
        dropsWhenBuilt = false
        return started
    }

    /// The build held is asked for again: it stays held.
    public mutating func reuse() {
        dropsWhenBuilt = false
    }

    /// Lets go of the build held: `true` when the cache lets go of it
    /// now, `false` when it is still running and is let go once it ends.
    public mutating func clear() -> Bool {
        guard building != nil, !isBuilt else {
            self = Self(started: started)
            return true
        }
        dropsWhenBuilt = true
        return false
    }

    /// Build `number` ended: `true` when the cache lets go of it now.
    public mutating func finished(_ number: Int) -> Bool {
        guard number == building else { return false }
        isBuilt = true
        guard dropsWhenBuilt else { return false }
        self = Self(started: started)
        return true
    }

    private init(started: Int) {
        self.started = started
    }
}
