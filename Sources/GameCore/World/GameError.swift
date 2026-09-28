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
    /// The track at the position carries a placed train (it is the train's
    /// node, or an end of its link), so it cannot be removed.
    case trackInUse(GridPosition)
    /// No train with this ID exists.
    case unknownTrain(TrainID)
    /// The train is already on the track. Placement does not move a train;
    /// unplace it first.
    case trainAlreadyPlaced(TrainID)
    /// The train is not on the track, so there is nothing to unplace or
    /// reverse.
    case trainNotPlaced(TrainID)
    /// A train cannot be placed there: the position is not at a track tile
    /// or strictly inside a link between two joined track tiles (see
    /// ``TrainPosition``).
    case invalidTrainPosition
    /// A train's movement rate must not be negative.
    case invalidMovementRate
    /// A continuation must name, in order, nodes the train can enter from
    /// where it is: each joined to the one before (starting from the train's
    /// node, or the end of its link), with no immediate U-turn.
    case invalidContinuation
    /// Advancing that many ticks at the current speed would take game time
    /// past the largest minute the clock can hold. Nothing was advanced.
    case clockOverflow
}
