/// A read-only snapshot of the track piece on one tile.
///
/// Tracks are stored as ``TileType/track(connections:)`` in the map; this type
/// is a convenient view for callers. Connections are local to the tile —
/// there is intentionally no network graph yet.
public struct Track: Hashable, Sendable {
    public let position: GridPosition
    public let connections: TrackConnections

    public init(position: GridPosition, connections: TrackConnections) {
        self.position = position
        self.connections = connections
    }
}
