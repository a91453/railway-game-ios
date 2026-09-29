/// What currently occupies a map tile.
///
/// Each case carries the minimum data needed to describe its occupant, so the
/// map grid is the single authoritative record of what is built where.
/// New terrain or building kinds are added as new cases.
public enum TileType: Hashable, Codable, Sendable {
    case empty
    /// A plain track piece: every exit joins every other, so a train may
    /// leave by any exit but the one it came in by.
    case track(connections: TrackConnections)
    /// A station tile. Full station data lives in ``GameWorld/stations``.
    case station(id: StationID)
    /// A turnout (Phase 4.5 Stage S1): exits `connections`, three or more,
    /// one of them the `stem`. The stem joins every other exit, and those
    /// join only the stem, so a train cannot pass from one branch to
    /// another.
    case turnout(connections: TrackConnections, stem: TrackDirection)
    /// A level crossing of two straight tracks (Stage S1): exits in all four
    /// directions, each joining only the one opposite.
    case crossing
}

/// A read-only snapshot of one map cell.
public struct MapTile: Hashable, Sendable {
    public let position: GridPosition
    public let type: TileType

    public init(position: GridPosition, type: TileType) {
        self.position = position
        self.type = type
    }
}
