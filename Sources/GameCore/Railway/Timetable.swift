/// One stop of a train's timetable: the station the train is scheduled to
/// call at, and the game minutes it is scheduled to arrive there and to
/// leave.
///
/// A timetable is an ordered list of stops (``Train/timetable``); the order
/// of the list is the order of the stops. It is plan data only: it says which
/// stations the train is scheduled to be at and when, never whether the
/// train should leave now. Nothing in the simulation reads it yet, so a
/// train moves exactly as it would without one.
///
/// Times are ``GameTime`` values: whole game minutes since the game began,
/// the same absolute scale as ``GameClock/now``, with no calendar or time
/// of day.
///
/// Like ``TrainPosition``, the struct accepts any values. Validity is checked
/// where a timetable enters a world: ``GameWorld/setTrainTimetable(_:to:)``
/// and decoding.
public struct ScheduledStop: Hashable, Sendable {
    /// The station the train is scheduled to call at.
    public let station: StationID
    /// The game minute the train is scheduled to arrive at the station.
    public let arrival: GameTime
    /// The game minute the train is scheduled to leave the station.
    public let departure: GameTime

    public init(station: StationID, arrival: GameTime, departure: GameTime) {
        self.station = station
        self.arrival = arrival
        self.departure = departure
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
}

// MARK: - Codable

extension ScheduledStop: Codable {
    private enum CodingKeys: String, CodingKey {
        case station, arrival, departure
    }

    /// Decodes `{"station", "arrival", "departure"}`, rejecting a stop no
    /// timetable can hold (a negative time, or an arrival after the
    /// departure) rather than repairing it. The order between stops is
    /// checked by ``Train``'s decoder, and that the station exists by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            station: try container.decode(StationID.self, forKey: .station),
            arrival: try container.decode(GameTime.self, forKey: .arrival),
            departure: try container.decode(GameTime.self, forKey: .departure)
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
    }
}
