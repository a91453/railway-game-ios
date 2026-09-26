/// Stable identifier of a station, unique within a ``GameWorld``.
///
/// IDs are allocated sequentially by the world (never reused), so the same
/// sequence of actions always yields the same IDs.
public struct StationID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: StationID, rhs: StationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A station occupying a single map tile.
public struct Station: Identifiable, Hashable, Codable, Sendable {
    public let id: StationID
    public let name: String
    public let position: GridPosition

    public init(id: StationID, name: String, position: GridPosition) {
        self.id = id
        self.name = name
        self.position = position
    }
}
