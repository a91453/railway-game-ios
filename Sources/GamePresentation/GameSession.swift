import GameCore
import Observation

/// Owns the app's single authoritative ``GameWorld`` for as long as the app
/// runs, and applies every gameplay change to it through `GameWorld` commands.
///
/// SwiftUI observes the session rather than GameCore: `GameWorld` stays a
/// plain `Sendable` value type, and this class is the one place that holds it.
/// Views read ``world`` and call the session's methods; they never keep their
/// own copy of game state.
///
/// Besides the world, the session keeps only transient UI state (the selected
/// tile). Anything shown about the game is derived from ``world`` on demand.
///
/// Main-actor isolated because both SwiftUI and the host game loop run on the
/// main actor, so no locks or `@unchecked Sendable` are needed.
@MainActor
@Observable
public final class GameSession {
    /// The authoritative game state. Only the session mutates it.
    public private(set) var world: GameWorld

    /// The tile the player last selected. Always inside the map when set.
    public private(set) var selection: GridPosition?

    public init(world: GameWorld) {
        self.world = world
    }

    // MARK: - Selection

    /// The current contents of the selected tile, read from the world.
    public var selectedTile: MapTile? {
        selection.flatMap { world.map.tile(at: $0) }
    }

    /// Selects the tile at `position`; positions outside the map are ignored.
    public func select(_ position: GridPosition) {
        guard world.map.contains(position) else { return }
        selection = position
    }

    public func clearSelection() {
        selection = nil
    }

    /// Moves the selection one tile toward `direction`, staying inside the map.
    /// Selects the north-west corner if nothing is selected yet.
    public func moveSelection(_ direction: TrackDirection) {
        guard let current = selection else {
            select(GridPosition(x: 0, y: 0))
            return
        }
        var next = current
        switch direction {
        case .north: next.y -= 1
        case .east: next.x += 1
        case .south: next.y += 1
        case .west: next.x -= 1
        }
        select(next)
    }
}
