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
/// Deliberately minimal: position, route, timetable and consist are not
/// modelled yet, so that train simulation can be designed on top of a real
/// track topology rather than guessed now.
public struct Train: Identifiable, Hashable, Codable, Sendable {
    public let id: TrainID
    public let name: String

    public init(id: TrainID, name: String) {
        self.id = id
        self.name = name
    }
}
