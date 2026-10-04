/// What occupies a map tile's land.
///
/// The map records land only (Phase 4.5 Stage S3A, ARCHITECTURE decision
/// 29): railway track lives in ``RailwayNetwork``, never here, so there is
/// one record of the railway, and stations stand at points that take no
/// tile. Until Stage F3c a station on the grid took a tile here (decision
/// 51). New terrain or building kinds are added as new cases.
public enum TileType: Hashable, Codable, Sendable {
    case empty
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
