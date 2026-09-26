/// What currently occupies a map tile.
///
/// Each case carries the minimum data needed to describe its occupant, so the
/// map grid is the single authoritative record of what is built where.
/// New terrain or building kinds are added as new cases.
public enum TileType: Hashable, Codable, Sendable {
    case empty
    case track(connections: TrackConnections)
    /// A station tile. Full station data lives in ``GameWorld/stations``.
    case station(id: StationID)
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
