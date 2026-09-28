/// Stable identifier of a train, unique within a ``GameWorld``.
public struct TrainID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TrainID, rhs: TrainID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A train owned by the player.
///
/// A train has an identity, a name and, once placed, a position on the track.
/// Movement, route, timetable and consist are not modelled yet.
public struct Train: Identifiable, Hashable, Sendable {
    public let id: TrainID
    public let name: String
    /// Where the train is on the track, or `nil` while it is unplaced (as
    /// every newly bought train is).
    ///
    /// Only ``GameWorld`` changes it, through ``GameWorld/placeTrain(_:at:)``,
    /// ``GameWorld/unplaceTrain(_:)`` and ``GameWorld/reverseTrain(_:)``,
    /// which keep it on the world's track.
    public internal(set) var position: TrainPosition?

    /// Creates an unplaced train.
    public init(id: TrainID, name: String) {
        self.id = id
        self.name = name
        self.position = nil
    }
}

extension Train: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, position
    }

    /// Decodes a train. An unplaced train has no `"position"` key, which is
    /// also how trains saved before positions existed read. An explicit
    /// `null` is not a second spelling of unplaced and is rejected, and so is
    /// a malformed position: neither is ever read as unplaced.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TrainID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = container.contains(.position)
            ? try container.decode(TrainPosition.self, forKey: .position)
            : nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(position, forKey: .position)
    }
}
