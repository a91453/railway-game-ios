/// How far a train's active timetable service has got: the timetable entry
/// it is at or heading for, which of the two it is doing, and, for a
/// timetable that repeats, which cycle of it.
///
/// A service runs a train's timetable in order, from its first stop to its
/// last: once, or cycle after cycle when the timetable repeats (see
/// ``GameWorld/startTrainService(_:)``). The execution is authoritative
/// state saved with the train, because where the train is cannot tell it: a
/// timetable may name the same station several times, and a repeating one
/// calls at every stop once per cycle, so only the index and the cycle say
/// which call the train is making.
///
/// `stop` is always an index into ``Train/timetable``, never a station ID.
/// `cycle` counts whole periods (``Train/timetablePeriod``) since the times
/// the timetable holds: cycle `k` is scheduled `k × period` minutes later.
/// It is 0 for a timetable that runs once. Nothing else is stored: the
/// station and times are the timetable's, the route is the train's
/// continuation, and being stopped is derived from the train's position
/// and movement (``GameWorld/stationsStoppedAt(by:)``).
public enum TimetableExecution: Hashable, Sendable {
    /// The train is stopped at the station of timetable entry `stop` and
    /// leaves no earlier than that entry's scheduled departure in `cycle`.
    case waitingAtStop(Int, cycle: Int64 = 0)
    /// The train has left the entry before `stop` (the last entry of the
    /// previous cycle when `stop` is 0) and is on its way to the station of
    /// entry `stop`, following the continuation the service gave it.
    case travellingToStop(Int, cycle: Int64 = 0)

    /// The index of the timetable entry the train is at or heading for.
    public var stop: Int {
        switch self {
        case .waitingAtStop(let stop, _), .travellingToStop(let stop, _): stop
        }
    }

    /// The cycle of the timetable the train is in: 0 until a repeating
    /// timetable starts again, and always 0 for one that runs once.
    public var cycle: Int64 {
        switch self {
        case .waitingAtStop(_, let cycle), .travellingToStop(_, let cycle): cycle
        }
    }
}

extension TimetableExecution {
    /// Whether this execution fits a train with `timetable`, `period`,
    /// `position` and `movement`, judged without a map: the timetable has
    /// entry ``stop``; the cycle is 0, or the timetable repeats and the
    /// cycle's times fit in a ``GameTime`` (see
    /// ``ScheduledStop/lastCycle(of:period:)``); and the train is placed. A
    /// waiting train stands at a node with no continuation left; a travelling
    /// train is heading for an entry after the service's very first one (not
    /// entry 0 of cycle 0) and its journey has not ended there yet (it is on
    /// a link, or has continuation left). Whether the stations and platforms
    /// agree is checked by the ``GameWorld`` decoder.
    ///
    /// - Precondition: `timetable` and `period` form a timetable (see
    ///   ``ScheduledStop/isTimetable(_:period:)``).
    func fits(timetable: [ScheduledStop], period: Int64?, position: TrainPosition?, movement: TrainMovement) -> Bool {
        guard timetable.indices.contains(stop), cycle >= 0, let position else { return false }
        if cycle > 0 {
            guard let period, cycle <= ScheduledStop.lastCycle(of: timetable, period: period) else { return false }
        }
        let hasEnded: Bool = if case .atNode = position { movement.remainingContinuation.isEmpty } else { false }
        switch self {
        case .waitingAtStop:
            return hasEnded
        case .travellingToStop(let stop, let cycle):
            return (stop >= 1 || cycle >= 1) && !hasEnded
        }
    }
}

// MARK: - Codable

extension TimetableExecution: Codable {
    private enum CodingKeys: String, CodingKey {
        case phase, stop, cycle
    }

    /// Decodes `{"phase": "waiting" | "travelling", "stop": index}`, plus
    /// `"cycle"` once a repeating timetable has started again. Without
    /// `"cycle"`, which is also how services saved before timetables could
    /// repeat read, the cycle is 0; an explicit `null` is rejected. Rejects
    /// an unknown phase, a negative index or a negative cycle rather than
    /// repairing it. Whether the index and the cycle fit the timetable and
    /// the train is checked by ``Train``'s decoder, and the stations by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let phase = try container.decode(String.self, forKey: .phase)
        let stop = try container.decode(Int.self, forKey: .stop)
        let cycle = container.contains(.cycle) ? try container.decode(Int64.self, forKey: .cycle) : 0
        guard stop >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .stop, in: container, debugDescription: "A timetable index cannot be negative.")
        }
        guard cycle >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .cycle, in: container, debugDescription: "A timetable cycle cannot be negative.")
        }
        switch phase {
        case "waiting": self = .waitingAtStop(stop, cycle: cycle)
        case "travelling": self = .travellingToStop(stop, cycle: cycle)
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
        if cycle > 0 {
            try container.encode(cycle, forKey: .cycle)
        }
    }
}
