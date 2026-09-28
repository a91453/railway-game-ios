/// A read-only snapshot of the track piece on one tile.
///
/// Tracks are stored as ``TileType/track(connections:)`` in the map; this type
/// is a convenient view for callers. Connections are the tile's own exits.
/// Whether a neighbouring tile is actually joined is derived from the map on
/// demand by ``GameWorld/connectedNeighbors(of:)``; no graph is stored.
public struct Track: Hashable, Sendable {
    public let position: GridPosition
    public let connections: TrackConnections

    public init(position: GridPosition, connections: TrackConnections) {
        self.position = position
        self.connections = connections
    }
}
