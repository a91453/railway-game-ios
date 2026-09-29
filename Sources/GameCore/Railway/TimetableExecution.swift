/// How far a train's active timetable service has got: the timetable entry
/// it is at or heading for, and which of the two it is doing.
///
/// A service runs a train's timetable once, in order, from its first stop
/// to its last (see ``GameWorld/startTrainService(_:)``). The execution is
/// authoritative state saved with the train, because where the train is
/// cannot tell it: a timetable may name the same station several times, so
/// only the index says which of those stops the train is making.
///
/// `stop` is always an index into ``Train/timetable``, never a station ID.
/// Nothing else is stored: the station is the timetable's, the route is the
/// train's continuation, and being stopped is derived from the train's
/// position and movement (``GameWorld/stationsStoppedAt(by:)``).
public enum TimetableExecution: Hashable, Sendable {
    /// The train is stopped at the station of timetable entry `stop` and
    /// leaves no earlier than that entry's scheduled departure.
    case waitingAtStop(Int)
    /// The train has left entry `stop - 1` and is on its way to the station
    /// of entry `stop`, following the continuation the service gave it.
    case travellingToStop(Int)

    /// The index of the timetable entry the train is at or heading for.
    public var stop: Int {
        switch self {
        case .waitingAtStop(let stop), .travellingToStop(let stop): stop
        }
    }
}

extension TimetableExecution {
    /// Whether this execution fits a train with `timetable`, `position` and
    /// `movement`, judged without a map: the timetable has entry ``stop``
    /// and the train is placed; a waiting train stands at a node with no
    /// continuation left; a travelling train is heading for an entry after
    /// the first and its journey has not ended there yet (it is on a link,
    /// or has continuation left). Whether the stations and platforms agree
    /// is checked by the ``GameWorld`` decoder.
    func fits(timetable: [ScheduledStop], position: TrainPosition?, movement: TrainMovement) -> Bool {
        guard timetable.indices.contains(stop), let position else { return false }
        let hasEnded: Bool = if case .atNode = position { movement.remainingContinuation.isEmpty } else { false }
        switch self {
        case .waitingAtStop:
            return hasEnded
        case .travellingToStop(let stop):
            return stop >= 1 && !hasEnded
        }
    }
}

// MARK: - Codable

extension TimetableExecution: Codable {
    private enum CodingKeys: String, CodingKey {
        case phase, stop
    }

    /// Decodes `{"phase": "waiting" | "travelling", "stop": index}`,
    /// rejecting an unknown phase or a negative index rather than repairing
    /// it. Whether the index fits the timetable and the train is checked by
    /// ``Train``'s decoder, and the stations by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let phase = try container.decode(String.self, forKey: .phase)
        let stop = try container.decode(Int.self, forKey: .stop)
        guard stop >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .stop, in: container, debugDescription: "A timetable index cannot be negative.")
        }
        switch phase {
        case "waiting": self = .waitingAtStop(stop)
        case "travelling": self = .travellingToStop(stop)
        default:
            throw DecodingError.dataCorruptedError(forKey: .phase, in: container, debugDescription: "Unknown service phase \"\(phase)\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .waitingAtStop: try container.encode("waiting", forKey: .phase)
        case .travellingToStop: try container.encode("travelling", forKey: .phase)
        }
        try container.encode(stop, forKey: .stop)
    }
}
