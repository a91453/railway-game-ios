/// A game rule violation reported by ``GameWorld`` and related types.
///
/// These are expected, recoverable outcomes of player actions, not programmer
/// errors. Cases carry structured data rather than user-facing text so the
/// presentation layer can localise them.
public enum GameError: Error, Hashable, Sendable {
    /// Map dimensions must lie in `1...GridMap.maximumSideLength`.
    case invalidMapSize(width: Int, height: Int)
    /// The position is not inside the map.
    case outOfBounds(GridPosition)
    /// Something is already built at the position.
    case tileOccupied(GridPosition)
    /// A track piece must connect in at least one direction, and only in the
    /// four known directions (no other bits set).
    case invalidTrackConnections
    /// Names must contain at least one non-whitespace character.
    case invalidName
    /// The balance cannot cover the cost.
    case insufficientFunds(required: Money, available: Money)
    /// Track removal was requested where there is no track (an empty tile or
    /// a station).
    case noTrackToRemove(GridPosition)
}
