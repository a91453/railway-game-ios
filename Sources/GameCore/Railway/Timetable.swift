/// One stop of a train's timetable: the station the train is scheduled to
/// call at, the game minutes it is scheduled to arrive there and to leave,
/// and whether it turns round there.
///
/// A timetable is an ordered list of stops (``Train/timetable``); the order
/// of the list is the order of the stops. It is plan data only: it says which
/// stations the train is scheduled to be at and when, never whether the
/// train should leave now. Only a service started with
/// ``GameWorld/startTrainService(_:)`` reads it, and decides that from the
/// scheduled departures (see ``GameWorld/advance(ticks:)``); without one, a
/// train moves exactly as it would without a timetable.
///
/// Times are ``GameTime`` values: whole game minutes since the game began,
/// the same absolute scale as ``GameClock/now``, with no calendar or time
/// of day. A repeating timetable (``Train/timetablePeriod``) keeps these
/// times as its first cycle; later cycles are the same times shifted by
/// whole periods, never stored.
///
/// Like ``TrainPosition``, the struct accepts any values. Validity is checked
/// where a timetable enters a world:
/// ``GameWorld/setTrainTimetable(_:to:repeatingEvery:)`` and decoding.
public struct ScheduledStop: Hashable, Sendable {
    /// The station the train is scheduled to call at.
    public let station: StationID
    /// The game minute the train is scheduled to arrive at the station.
    public let arrival: GameTime
    /// The game minute the train is scheduled to leave the station.
    public let departure: GameTime
    /// Whether a service turns the train round as it leaves this stop: it
    /// reverses the train where it stands, as ``GameWorld/reverseTrain(_:)``
    /// would, and only then looks up the route to the next stop. This is how
    /// a train leaves a terminus the way it came, since a route never turns
    /// straight back. Plan data like the times: nothing reads it outside a
    /// service.
    public let reverses: Bool

    public init(station: StationID, arrival: GameTime, departure: GameTime, reverses: Bool = false) {
        self.station = station
        self.arrival = arrival
        self.departure = departure
        self.reverses = reverses
    }
}

extension ScheduledStop {
    /// Whether `stops`, in order, is a timetable any world could hold, judged
    /// without a world: its times never go backwards, starting from minute 0.
    /// That is `0 <= arrival <= departure` at every stop, and each departure
    /// is no later than the next stop's arrival.
    ///
    /// Equal times are allowed (no dwell, or arriving at the minute the stop
    /// before is left), and so are repeated stations and no stops at all.
    /// Only compares times, so no value can overflow.
    static func isTimetable(_ stops: some Sequence<ScheduledStop>) -> Bool {
        var earliest = GameTime.zero
        for stop in stops {
            guard earliest <= stop.arrival, stop.arrival <= stop.departure else { return false }
            earliest = stop.departure
        }
        return true
    }

    /// Whether `stops`, in order, is a timetable any world could hold that
    /// runs once (`period` is `nil`) or repeats every `period` minutes,
    /// judged without a world.
    ///
    /// A repeating timetable is a timetable (see ``isTimetable(_:)``) with
    /// at least one stop and a period of at least one minute, whose times
    /// still never go backwards when it starts again: its last departure is
    /// no later than its first arrival one period later. So a period may
    /// equal the whole span from the first arrival to the last departure,
    /// and the next cycle may arrive at its first stop the minute the last
    /// stop is left. Only subtracts times that are at least 0, so no value
    /// can overflow.
    static func isTimetable(_ stops: [ScheduledStop], period: Int64?) -> Bool {
        guard isTimetable(stops) else { return false }
        guard let period else { return true }
        guard let first = stops.first, let last = stops.last, period >= 1 else { return false }
        return last.departure.minutes - first.arrival.minutes <= period
    }

    /// The last cycle of a timetable repeating every `period` minutes whose
    /// times all fit in a ``GameTime``: cycle `k` shifts every time by
    /// `k × period`, and its latest time is the last stop's departure. Every
    /// cycle up to this one can be scheduled; none after it can.
    ///
    /// - Precondition: `stops` and `period` form a repeating timetable (see
    ///   ``isTimetable(_:period:)``).
    static func lastCycle(of stops: [ScheduledStop], period: Int64) -> Int64 {
        (Int64.max - stops[stops.count - 1].departure.minutes) / period
    }
}

// MARK: - Codable

extension ScheduledStop: Codable {
    private enum CodingKeys: String, CodingKey {
        case station, arrival, departure, reverse
    }

    /// Decodes `{"station", "arrival", "departure"}`, plus `"reverse": true`
    /// for a stop the train turns round at. A stop without `"reverse"`,
    /// which is also how stops saved before turning round existed read,
    /// does not turn the train; an explicit `null` is rejected. Rejects a
    /// stop no timetable can hold (a negative time, or an arrival after the
    /// departure) rather than repairing it. The order between stops is
    /// checked by ``Train``'s decoder, and that the station exists by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            station: try container.decode(StationID.self, forKey: .station),
            arrival: try container.decode(GameTime.self, forKey: .arrival),
            departure: try container.decode(GameTime.self, forKey: .departure),
            reverses: container.contains(.reverse) ? try container.decode(Bool.self, forKey: .reverse) : false
        )
        guard Self.isTimetable(CollectionOfOne(self)) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A scheduled stop needs 0 <= arrival <= departure."
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station, forKey: .station)
        try container.encode(arrival, forKey: .arrival)
        try container.encode(departure, forKey: .departure)
        if reverses {
            try container.encode(true, forKey: .reverse)
        }
    }
}
