/// A read-only snapshot of the track piece on one tile.
///
/// Tracks are stored in the map as ``TileType/track(connections:)``,
/// ``TileType/turnout(connections:stem:)`` or ``TileType/crossing``; this
/// type is a convenient view for callers. Connections are the tile's own
/// exits, and the layout says which of them join (see ``TrackLayout``).
/// Whether a neighbouring tile is actually joined is derived from the map on
/// demand by ``GameWorld/connectedNeighbors(of:)``; no graph is stored.
public struct Track: Hashable, Sendable {
    public let position: GridPosition
    public let connections: TrackConnections
    public let layout: TrackLayout

    public init(position: GridPosition, connections: TrackConnections, layout: TrackLayout = .open) {
        self.position = position
        self.connections = connections
        self.layout = layout
    }
}

/// Which exits of a track piece a train may pass between (Phase 4.5 Stage
/// S1). A train never turns straight back; beyond that:
public enum TrackLayout: Hashable, Sendable {
    /// Every exit joins every other: a plain piece, or a junction where a
    /// train may take any way but back. Every piece built before Stage S1.
    case open
    /// The stem joins every other exit; those join only the stem.
    case turnout(stem: TrackDirection)
    /// Each exit joins only the one opposite: two straight tracks crossing.
    case crossing

    /// Whether a train that came in through `entry` (the side it came from,
    /// or `nil` if it did not come in through an exit, as when placed) may
    /// leave through `exit`, one of the piece's exits other than `entry`.
    func joins(_ entry: TrackDirection?, to exit: TrackDirection) -> Bool {
        switch self {
        case .open:
            return true
        case .turnout(let stem):
            guard let entry else { return true }
            return entry == stem || exit == stem
        case .crossing:
            return entry.map { exit == $0.opposite } ?? true
        }
    }
}
