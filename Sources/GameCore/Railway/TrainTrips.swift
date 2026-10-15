// The trip log (ARCHITECTURE decision 223, point 5): each train's trips of
// today and yesterday, with the times it actually kept at every call and
// the share of the fares its line was given for the riders it took on. A
// record only: no rule reads it, so it never changes what the world does.

/// A call a trip made: the station, when the train arrived there, and when
/// it left (`nil` while it is still there).
public struct TripCall: Hashable, Sendable {
    public let station: StationID
    public let arrival: GameTime
    public internal(set) var departure: GameTime?

    public init(station: StationID, arrival: GameTime, departure: GameTime? = nil) {
        self.station = station
        self.arrival = arrival
        self.departure = departure
    }
}

/// One trip of a train (decision 223, point 5): a service from the first
/// call of its timetable (a line's round trip, a run, or one cycle of a
/// train's own timetable) to the last.
///
/// Opened when the train is sent out (it stands at its first call then),
/// and closed when it arrives at its last call. A service stopped on the
/// way closes it then, marked ``isInterrupted``. The train's trip number on
/// a day is its place among that day's trips, from 1; it is not stored.
public struct TrainTrip: Hashable, Sendable {
    public let train: TrainID
    /// The line the train ran the trip for, or `nil` for a train's own
    /// timetable.
    public let line: LineID?
    public let from: StationID
    public let to: StationID
    /// When the timetable had it leave its first call.
    public let scheduledDeparture: GameTime
    /// When the timetable had it arrive at its last call.
    public let scheduledArrival: GameTime
    /// Whether it was an empty run (decision 172), or into or out of a
    /// depot (decision 209).
    public let isDeadhead: Bool
    /// The calls it has made, in order, the first when it was sent out.
    /// Never empty.
    public internal(set) var calls: [TripCall]
    /// When it arrived at its last call; for an interrupted trip, when its
    /// service stopped. `nil` while it runs.
    public internal(set) var arrival: GameTime?
    /// Whether its service stopped before it reached its last call.
    public internal(set) var isInterrupted: Bool = false
    /// The share of the fares its line was given for the riders it took on
    /// (``GameWorld/shareFare(_:among:crediting:)``). A rider who changes
    /// pays once, at the start: the shares of the lines they ride later go
    /// to those lines' accounts, not to their later trains' trips. So a
    /// day's trips add up to at most the line's fares.
    public internal(set) var fare: Money = .zero
    /// How many got on.
    public internal(set) var boarded: Int64 = 0

    public init(train: TrainID, line: LineID?, from: StationID, to: StationID,
                scheduledDeparture: GameTime, scheduledArrival: GameTime, isDeadhead: Bool, calls: [TripCall]) {
        self.train = train
        self.line = line
        self.from = from
        self.to = to
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.isDeadhead = isDeadhead
        self.calls = calls
    }

    /// When it was sent out: its arrival at its first call.
    public var sentOut: GameTime { calls[0].arrival }

    /// When it actually left its first call, or `nil` until it has.
    public var departure: GameTime? { calls[0].departure }

    /// Whether it still runs.
    public var isRunning: Bool { arrival == nil }

    /// How late it arrived at its last call, in seconds (negative when
    /// early), as a line's punctuality counts it (decision 207); `nil`
    /// while it runs or for an interrupted trip.
    public var delay: Int64? {
        guard let arrival, !isInterrupted else { return nil }
        return GameWorld.gap(from: scheduledArrival, to: arrival)
    }

    /// Whether it arrived more than ``GameWorld/punctualSeconds`` late;
    /// `nil` as for ``delay``.
    public var isLate: Bool? {
        delay.map { $0 > GameWorld.punctualSeconds }
    }

    /// Whether the record is well formed.
    var isValid: Bool {
        guard let first = calls.first, first.station == from,
              fare >= .zero, fare.amount <= GameWorld.maximumHourly / 100 * 100,
              (0...GameWorld.maximumHourly).contains(boarded) else { return false }
        // The calls follow one another in time: each departure after its
        // arrival, each arrival after the departure before it. A departure
        // missing is not refused: a record must never stop a save loading.
        var last = first.arrival
        for call in calls {
            guard call.arrival >= last else { return false }
            last = call.arrival
            if let departure = call.departure {
                guard departure >= last else { return false }
                last = departure
            }
        }
        guard let arrival else { return !isInterrupted }
        return arrival >= calls[calls.count - 1].arrival
            && (isInterrupted || calls[calls.count - 1].station == to)
    }
}

extension TripCall: Codable {
    // `[station, arrival]` or `[station, arrival, departure]`: a trip has
    // a call at every station, so the log is kept short.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        station = try container.decode(StationID.self)
        arrival = try container.decode(GameTime.self)
        departure = container.isAtEnd ? nil : try container.decode(GameTime.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A trip's call has a station, an arrival and at most a departure.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(station)
        try container.encode(arrival)
        if let departure { try container.encode(departure) }
    }
}

extension TrainTrip: Codable {
    private enum CodingKeys: String, CodingKey {
        case train, line, from, to, plannedDeparture, plannedArrival, deadhead, calls, arrival, interrupted, fare, boarded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        train = try container.decode(TrainID.self, forKey: .train)
        line = try container.decodeIfPresent(LineID.self, forKey: .line)
        from = try container.decode(StationID.self, forKey: .from)
        to = try container.decode(StationID.self, forKey: .to)
        scheduledDeparture = try container.decode(GameTime.self, forKey: .plannedDeparture)
        scheduledArrival = try container.decode(GameTime.self, forKey: .plannedArrival)
        isDeadhead = try container.decodeIfPresent(Bool.self, forKey: .deadhead) ?? false
        calls = try container.decode([TripCall].self, forKey: .calls)
        arrival = try container.decodeIfPresent(GameTime.self, forKey: .arrival)
        isInterrupted = try container.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
        fare = try container.decodeIfPresent(Money.self, forKey: .fare) ?? .zero
        boarded = try container.decodeIfPresent(Int64.self, forKey: .boarded) ?? 0
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .calls, in: container, debugDescription: "A trip's calls and times must follow one another.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(train, forKey: .train)
        try container.encodeIfPresent(line, forKey: .line)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(scheduledDeparture, forKey: .plannedDeparture)
        try container.encode(scheduledArrival, forKey: .plannedArrival)
        if isDeadhead { try container.encode(true, forKey: .deadhead) }
        try container.encode(calls, forKey: .calls)
        try container.encodeIfPresent(arrival, forKey: .arrival)
        if isInterrupted { try container.encode(true, forKey: .interrupted) }
        if fare != .zero { try container.encode(fare, forKey: .fare) }
        if boarded != 0 { try container.encode(boarded, forKey: .boarded) }
    }
}

// MARK: - The world's side

extension GameWorld {
    /// The trips of train `id` in the log, today's and yesterday's (and one
    /// still running from before), in the order it ran them.
    public func trips(of id: TrainID) -> [TrainTrip] {
        tripLog.filter { $0.train == id }
    }

    /// Whether the world keeps the trip log: with the line accounts
    /// (decision 179), as the screens that read it sit beside them.
    private var recordsTrips: Bool { lineAccounts != nil }

    /// The index of train `id`'s last trip in the log, or `nil`: the one
    /// before the first of a later train, found by halving, since the log
    /// is ordered by train (it is asked whenever riders board).
    private func lastTripIndex(of id: TrainID) -> Int? {
        let next = firstTripIndex(after: id)
        return next > 0 && tripLog[next - 1].train == id ? next - 1 : nil
    }

    /// The index of the first trip in the log of a train after `id`, or
    /// the log's end.
    private func firstTripIndex(after id: TrainID) -> Int {
        var (low, high) = (0, tripLog.count)
        while low < high {
            let middle = (low + high) / 2
            if tripLog[middle].train > id { high = middle } else { low = middle + 1 }
        }
        return low
    }

    /// The index of train `id`'s running trip, or `nil`.
    private func runningTripIndex(of id: TrainID) -> Int? {
        lastTripIndex(of: id).flatMap { tripLog[$0].isRunning ? $0 : nil }
    }

    /// Train `index`, whose service has just come to wait at a stop, calls
    /// there now: at the first stop of its timetable a new trip opens
    /// (closing one still running as interrupted), at any other the running
    /// trip gains the call, and at the last it ends.
    mutating func logArrival(of index: Int) {
        guard recordsTrips, case .waitingAtStop(let stop, let cycle)? = trains[index].execution else { return }
        let train = trains[index]
        let now = clock.now
        let call = TripCall(station: train.timetable[stop].station, arrival: now)
        let last = train.timetable.count - 1
        let slot: Int
        if stop == 0 {
            interruptTrip(of: train.id)
            dropTrips(before: dayIndex(of: now) - 1)
            let trip = TrainTrip(
                train: train.id, line: assignedLine(of: train.id),
                from: train.timetable[0].station, to: train.timetable[last].station,
                scheduledDeparture: train.scheduledDeparture(of: 0, cycle: cycle),
                scheduledArrival: train.scheduledArrival(of: last, cycle: cycle),
                isDeadhead: train.isDeadheading, calls: [call]
            )
            slot = firstTripIndex(after: train.id)
            tripLog.insert(trip, at: slot)
        } else {
            // A trip from before the log was kept (an older save) is not
            // recorded halfway.
            guard let running = runningTripIndex(of: train.id) else { return }
            slot = running
            tripLog[slot].calls.append(call)
        }
        if stop == last { tripLog[slot].arrival = now }
    }

    /// Train `id` has left its call at `station` now: its last trip's last
    /// call there, if it has not left it yet, has its departure (the last
    /// call of a trip that has just ended too).
    mutating func logDeparture(of id: TrainID, from station: StationID) {
        guard recordsTrips, let index = lastTripIndex(of: id), !tripLog[index].isInterrupted else { return }
        let last = tripLog[index].calls.count - 1
        guard tripLog[index].calls[last].station == station, tripLog[index].calls[last].departure == nil else { return }
        tripLog[index].calls[last].departure = clock.now
    }

    /// Train `id`'s running trip, if any, ends now, interrupted: its
    /// service stopped, or another began, before it reached its last call.
    mutating func interruptTrip(of id: TrainID) {
        guard recordsTrips, let index = runningTripIndex(of: id) else { return }
        tripLog[index].arrival = clock.now
        tripLog[index].isInterrupted = true
    }

    /// Train `id`'s running trip took on `boarded` riders, and its line was
    /// given `fare` of what they paid.
    mutating func creditTrip(of id: TrainID, fare: Money, boarded: Int64) {
        guard recordsTrips, let index = runningTripIndex(of: id) else { return }
        // Each is at most what the line's accounts were given, a sum that
        // is itself capped, so these stay far from overflowing.
        tripLog[index].fare = Money(min(tripLog[index].fare.amount + fare.amount, Self.maximumHourly / 100 * 100))
        tripLog[index].boarded = min(tripLog[index].boarded + boarded, Self.maximumHourly)
    }

    /// Drops the finished trips sent out before day `day`: the log keeps
    /// today and yesterday.
    mutating func dropTrips(before day: Int64) {
        // The day's first second; a day too far off to start in a game
        // time drops all or nothing.
        let (start, overflow) = day.multipliedReportingOverflow(by: GameTime.secondsPerDay)
        let first = overflow ? (day < 0 ? Int64.min : .max) : start
        tripLog.removeAll { !$0.isRunning && $0.sentOut.seconds < first }
    }

    /// What is wrong with the trip log, or `nil`: each trip well formed and
    /// of a train ID handed out, ordered by train and then by when they
    /// were sent out, and only a train's last trip running.
    func tripLogProblem(trainIDsBelow next: Int) -> String? {
        guard tripLog.allSatisfy({ $0.isValid && $0.train.rawValue < next }) else {
            return "Every trip in the log must be well formed, of a train ID handed out."
        }
        for (earlier, later) in zip(tripLog, tripLog.dropFirst()) {
            guard earlier.train < later.train || earlier.train == later.train && earlier.sentOut <= later.sentOut && !earlier.isRunning else {
                return "The trip log must be ordered by train and time, with only a train's last trip running."
            }
        }
        return nil
    }
}
