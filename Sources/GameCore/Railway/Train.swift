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
/// A train has an identity, a name and, once placed, a position on the track
/// and a movement (rate and continuation). Routes, timetables and consists
/// are not modelled yet.
public struct Train: Identifiable, Hashable, Sendable {
    public let id: TrainID
    public let name: String
    /// Where the train is on the track, or `nil` while it is unplaced (as
    /// every newly bought train is).
    ///
    /// Only ``GameWorld`` changes it, through ``GameWorld/placeTrain(_:at:)``,
    /// ``GameWorld/unplaceTrain(_:)``, ``GameWorld/reverseTrain(_:)`` and
    /// ``GameWorld/advance(ticks:)``, which keep it on the world's track.
    public internal(set) var position: TrainPosition?
    /// How the train moves. Always ``TrainMovement/idle`` while the train is
    /// unplaced. Only ``GameWorld`` changes it.
    public internal(set) var movement: TrainMovement

    /// Creates an unplaced, idle train.
    public init(id: TrainID, name: String) {
        self.id = id
        self.name = name
        self.position = nil
        self.movement = .idle
    }
}

extension Train: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, position, movement
    }

    /// Decodes a train.
    ///
    /// An unplaced train has no `"position"` key, which is also how trains
    /// saved before positions existed read. An idle train has no `"movement"`
    /// key, which is also how trains saved before movement existed read. An
    /// explicit `null` for either is rejected, and so is a malformed value or
    /// a movement that does not fit the position (see
    /// ``TrainMovement/fits(_:)``): none is ever read as unplaced or idle.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TrainID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = container.contains(.position)
            ? try container.decode(TrainPosition.self, forKey: .position)
            : nil
        movement = container.contains(.movement)
            ? try container.decode(TrainMovement.self, forKey: .movement)
            : .idle
        guard movement.fits(position) else {
            throw DecodingError.dataCorruptedError(
                forKey: .movement, in: container,
                debugDescription: "Train \(id.rawValue)'s movement does not fit its position."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(position, forKey: .position)
        if movement != .idle {
            try container.encode(movement, forKey: .movement)
        }
    }
}
