// A service's dwell at each call, on the game's clock (Stage W2b,
// ARCHITECTURE decision 39): the train arrives, its doors open, passengers
// get off and on at a rate set by its doors, it holds for its timetable, its
// doors close and it leaves. The rules are the references' (see
// `StationDwell.swift`): the metro game's minimum dwell and door times, and
// the reference pack's `max(alighting ÷ rate, boarding ÷ rate)`. The rate
// and the doors are a gap the references leave (see `ServiceDwell`).

/// When a service's train arrived at and left its calls, and how far its
/// dwell has got (Stage W2b). Authoritative and saved with the train while
/// its service runs: the times are what happened, and the train's lateness
/// is worked out from them (see ``GameWorld/lateness(of:)``).
///
/// While the train waits at a call (``TimetableExecution/waitingAtStop(_:cycle:)``)
/// its dwell goes through these steps, each from what is stored here:
///
/// 1. the doors open for ``ServiceDwell/doorOpening`` after ``arrival``
///    (``exchangeEnd`` is `nil`);
/// 2. passengers get off and on until ``exchangeEnd``;
/// 3. with its doors open, the train holds until its minimum dwell is over
///    and, when it is early, until its doors must close for its scheduled
///    departure; passengers who come meanwhile board too, and the exchange
///    runs on while they do;
/// 4. the doors close (``closing``) for ``ServiceDwell/doorClosing``;
/// 5. the train leaves as soon as it can: if its route is held or there is
///    none, it waits with its doors closed.
public struct ServiceTimes: Hashable, Sendable {
    /// When the train arrived at the call it waits at, or, while it travels,
    /// at the call it last waited at. At the call its service started from,
    /// when the service started: starting a service, or sending a train out
    /// on a line, counts as arriving.
    public internal(set) var arrival: GameTime
    /// While the train waits: until when passengers get off and on, once its
    /// doors have opened; `nil` while they are still opening (and while it
    /// travels).
    public internal(set) var exchangeEnd: GameTime?
    /// While the train waits: when its doors started closing; `nil` while
    /// they are open (and while it travels).
    public internal(set) var closing: GameTime?
    /// When the train actually left the call before the one it waits at or
    /// travels to: while it travels, the call it has just left. `nil` until
    /// it has left a call in this service.
    public internal(set) var departure: GameTime?

    public init(arrival: GameTime, exchangeEnd: GameTime? = nil, closing: GameTime? = nil, departure: GameTime? = nil) {
        self.arrival = arrival
        self.exchangeEnd = exchangeEnd
        self.closing = closing
        self.departure = departure
    }
}

/// The dwell rules of a service's calls (Stage W2b): the least dwell, the
/// door times and the rate passengers get off and on at, in whole game
/// seconds, the step the clock goes in.
public enum ServiceDwell {
    /// The least dwell at a call between a service's ends: the metro game's
    /// 36 s (`DWELL_GAME_SEC`, ``StationDwell/metroDwell``).
    public static let minimum: Int64 = StationDwell.metroDwell / StationDwell.tenthsPerSecond
    /// The least dwell at a call where the train turns round, or where its
    /// service starts or ends: 42 s (`DWELL_TERMINAL_GAME_SEC`,
    /// ``StationDwell/metroTerminalDwell``).
    public static let terminalMinimum: Int64 = StationDwell.metroTerminalDwell / StationDwell.tenthsPerSecond
    /// The doors take 8 s to open (``StationDwell/metroDoorOpening``).
    public static let doorOpening: Int64 = StationDwell.metroDoorOpening / StationDwell.tenthsPerSecond
    /// The doors take 9 s to close: the metro game's 8.3 s
    /// (``StationDwell/metroDoorClosing``) rounded up to a whole second.
    public static let doorClosing: Int64 = (StationDwell.metroDoorClosing + StationDwell.tenthsPerSecond - 1) / StationDwell.tenthsPerSecond
    /// Passengers through one door in a second, getting off or getting on:
    /// the metro game's `PARAMS.BOARDING_RATE` of 2
    /// (``StationDwell/referenceBoardingRate``), which has no unit there;
    /// the unit is this project's (gap).
    public static let passengersPerDoorPerSecond: Int64 = StationDwell.referenceBoardingRate
    /// The doors on a car's platform side: four, as on a metro car (gap:
    /// neither reference counts doors).
    public static let doorsPerCar: Int64 = 4

    /// The least dwell at a call: ``terminalMinimum`` at a terminal (where
    /// the train turns round, or its service starts or ends), otherwise
    /// ``minimum``. Both include the door times.
    public static func minimumDwell(isTerminal: Bool) -> Int64 {
        isTerminal ? terminalMinimum : minimum
    }

    /// How many passengers a train of `cars` cars lets off, or takes on, in
    /// a second: through every door of every car.
    public static func passengersPerSecond(cars: Int) -> Int64 {
        passengersPerDoorPerSecond * doorsPerCar * Int64(cars)
    }

    /// The whole seconds `count` passengers take to get off or on a train of
    /// `cars` cars, rounded up; those getting off and those getting on use
    /// the doors at once, so an exchange takes as long as the larger of the
    /// two (the reference pack's `max(alighting ÷ rate, boarding ÷ rate)`).
    ///
    /// - Precondition: `count >= 0` and `cars >= 1`.
    public static func exchangeSeconds(_ count: Int64, cars: Int) -> Int64 {
        let rate = passengersPerSecond(cars: cars)
        return count / rate + (count % rate == 0 ? 0 : 1)
    }
}

extension ServiceTimes: Codable {
    private enum CodingKeys: String, CodingKey {
        case arrival, exchangeEnd, closing, departure
    }

    /// Decodes `{"arrival": second}`, plus `"exchangeEnd"`, `"closing"` and
    /// `"departure"` when they are set; an explicit `null` is rejected. That
    /// they fit the train's service and the clock is checked by ``Train``'s
    /// and ``GameWorld``'s decoders.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrival = try container.decode(GameTime.self, forKey: .arrival)
        exchangeEnd = container.contains(.exchangeEnd) ? try container.decode(GameTime.self, forKey: .exchangeEnd) : nil
        closing = container.contains(.closing) ? try container.decode(GameTime.self, forKey: .closing) : nil
        departure = container.contains(.departure) ? try container.decode(GameTime.self, forKey: .departure) : nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arrival, forKey: .arrival)
        try container.encodeIfPresent(exchangeEnd, forKey: .exchangeEnd)
        try container.encodeIfPresent(closing, forKey: .closing)
        try container.encodeIfPresent(departure, forKey: .departure)
    }
}

extension ServiceTimes {
    /// Whether these times fit a service in `execution`, judged without the
    /// clock: while the train waits, the exchange ends no earlier than the
    /// doors finish opening, the doors start closing only once it has
    /// ended, and the call before was left no later than this one was
    /// reached; while it travels, it has left the call before, no earlier
    /// than it reached that call, and nothing of a dwell is set. Times
    /// compared with a sum are compared without overflowing.
    func fits(_ execution: TimetableExecution) -> Bool {
        switch execution {
        case .waitingAtStop:
            if let departure, departure > arrival { return false }
            guard let exchangeEnd else { return closing == nil }
            let (opened, overflow) = arrival.seconds.addingReportingOverflow(ServiceDwell.doorOpening)
            guard !overflow, exchangeEnd.seconds >= opened else { return false }
            return closing.map { $0 >= exchangeEnd } ?? true
        case .travellingToStop:
            guard let departure, exchangeEnd == nil, closing == nil else { return false }
            return departure >= arrival
        }
    }

    /// The latest time stored, which the clock cannot be before; the end of
    /// an exchange still under way may be.
    var latest: GameTime {
        [arrival, closing, departure].compactMap { $0 }.max()!
    }
}

extension GameWorld {
    /// How late train `id`'s service is now, in whole seconds, worked out
    /// from its actual times and its timetable (Stage W2b); negative when it
    /// is early, `nil` for a train without a service or no such train.
    ///
    /// - Waiting at a stop: once its scheduled departure has passed, by how
    ///   long; before that, early by how much sooner than scheduled it
    ///   arrived, and otherwise on time (0), since it will leave on time
    ///   unless its dwell keeps it.
    /// - Travelling to a stop: by how late it left the stop before, and
    ///   once its scheduled arrival has passed, by how long, whichever is
    ///   more. A train that has not left a stop yet in its service counts
    ///   only the second.
    public func lateness(of id: TrainID) -> Int64? {
        guard let train = train(id: id), let execution = train.execution, let times = train.times else { return nil }
        let now = clock.now
        switch execution {
        case .waitingAtStop(let stop, let cycle):
            let departure = train.scheduledDeparture(of: stop, cycle: cycle)
            if now > departure { return Self.gap(from: departure, to: now) }
            let arrival = train.scheduledArrival(of: stop, cycle: cycle)
            return times.arrival < arrival ? -Self.gap(from: times.arrival, to: arrival) : 0
        case .travellingToStop(let stop, let cycle):
            var late: Int64 = 0
            if let left = times.departure, let previous = train.call(before: stop, cycle: cycle) {
                late = max(late, Self.gap(from: train.scheduledDeparture(of: previous.stop, cycle: previous.cycle), to: left))
            }
            let arrival = train.scheduledArrival(of: stop, cycle: cycle)
            if now > arrival {
                late = max(late, Self.gap(from: arrival, to: now))
            }
            return late
        }
    }

    /// `to − from` in seconds, at most `Int64.max`.
    private static func gap(from: GameTime, to: GameTime) -> Int64 {
        let (gap, overflow) = to.seconds.subtractingReportingOverflow(from.seconds)
        return overflow ? (to > from ? .max : .min + 1) : gap
    }
}
