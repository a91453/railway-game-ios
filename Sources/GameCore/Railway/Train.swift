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
/// A train has an identity, a name, a timetable (the stops it is scheduled
/// to make, once or repeating every period), whether it is running that
/// timetable as a service and how far it has got, and, once placed, a
/// position on the track and a movement (rate and path), and how it
/// accelerates and brakes (Stage W2c). Consists are not modelled yet.
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
    /// The stops the train is scheduled to make, in order (see
    /// ``ScheduledStop``). Empty for a train without a timetable, as every
    /// newly bought train is.
    ///
    /// Plan data, independent of where the train is and how it moves:
    /// placing, unplacing, reversing, the movement commands and time leave
    /// it as it is. Only an active service (``execution``) reads it to move
    /// the train. Only ``GameWorld`` changes it, through
    /// ``GameWorld/setTrainTimetable(_:to:repeatingEvery:)``, which is
    /// refused while a service is active.
    public internal(set) var timetable: [ScheduledStop]
    /// How often the timetable repeats, in whole game seconds, or `nil` for
    /// a timetable that runs once (as for every newly bought train).
    ///
    /// A service of a repeating timetable starts it again when it leaves the
    /// last stop: every time shifted one period later, cycle after cycle
    /// (see ``TimetableExecution/cycle``). Plan data like the timetable, and
    /// set together with it by
    /// ``GameWorld/setTrainTimetable(_:to:repeatingEvery:)``.
    public internal(set) var timetablePeriod: Int64?
    /// How far the train's timetable service has got, or `nil` while no
    /// service is active (as for every newly bought train).
    ///
    /// Only ``GameWorld`` changes it, through
    /// ``GameWorld/startTrainService(_:)``,
    /// ``GameWorld/stopTrainService(_:)`` and ``GameWorld/advance(ticks:)``.
    /// While it is set, the service owns the train's path (see
    /// ``TimetableExecution``).
    public internal(set) var execution: TimetableExecution?
    /// When the service's train arrived at and left its calls, and how far
    /// its dwell at the call it waits at has got (Stage W2b); set exactly
    /// while ``execution`` is. Only ``GameWorld`` changes it, with the
    /// execution.
    public internal(set) var times: ServiceTimes?
    /// How many cars the train has (Phase 4.5 Stage S2), one to a tile:
    /// 1, as every newly bought train has, up to ``maximumCars``. Set by
    /// ``GameWorld/setTrainCars(_:to:)`` while the train is unplaced.
    public internal(set) var cars: Int
    /// The edges the train's body lies over behind the edge its head is on
    /// (Stage S3), nearest first: every edge the body reaches into, up to
    /// and including the one its tail is on (see ``length``). Empty for a
    /// train of one car, for a train whose body fits on its head's edge, and
    /// for an unplaced train. Only ``GameWorld`` changes it, as the head
    /// moves.
    public internal(set) var trailEdges: [TrackEdgeID]
    /// The track this train has reserved for its route under traffic control
    /// (Phase 4.6 Stage T, ARCHITECTURE decision 32), in resource order,
    /// each once: everything its whole length covers from where its tail
    /// was when it took the route to where the route ends. Empty while
    /// traffic control is off, and for a train with no way left to go.
    ///
    /// Authoritative, and saved: it holds track the train has passed as well
    /// as track ahead, which its position alone could not tell. Only
    /// ``GameWorld`` changes it, as it gives the train a route or the route
    /// ends; its route itself stays in ``movement``.
    public internal(set) var reservation: [TrackResource]
    /// How the train accelerates, brakes and coasts, and how fast it may run
    /// (Stage W2c): a service's train follows the running curve this builds
    /// from one call to the next (see ``ServiceRun``). ``TrainPerformance/standard``
    /// for every newly bought train. Set by
    /// ``GameWorld/setTrainPerformance(_:to:)`` while the train runs no
    /// service.
    public internal(set) var performance: TrainPerformance

    /// Creates an unplaced, idle train of one car without a timetable or a
    /// service, with the standard performance.
    public init(id: TrainID, name: String) {
        self.id = id
        self.name = name
        self.position = nil
        self.movement = .idle
        self.timetable = []
        self.timetablePeriod = nil
        self.execution = nil
        self.times = nil
        self.cars = 1
        self.trailEdges = []
        self.reservation = []
        self.performance = .standard
    }
}

extension Train {
    /// The scheduled departure from timetable entry `stop` in `cycle`: the
    /// time the timetable holds, shifted `cycle` periods later.
    ///
    /// - Precondition: the timetable has entry `stop`, and `cycle` is 0 or
    ///   a cycle of a repeating timetable whose times fit (as every
    ///   execution's cycle is; see
    ///   ``TimetableExecution/fits(timetable:period:position:movement:)``),
    ///   so the sum cannot overflow.
    func scheduledDeparture(of stop: Int, cycle: Int64) -> GameTime {
        let departure = timetable[stop].departure
        guard cycle > 0, let timetablePeriod else { return departure }
        return GameTime(seconds: departure.seconds + cycle * timetablePeriod)
    }

    /// The scheduled arrival at timetable entry `stop` in `cycle`, shifted
    /// as ``scheduledDeparture(of:cycle:)`` is.
    ///
    /// - Precondition: as for ``scheduledDeparture(of:cycle:)``.
    func scheduledArrival(of stop: Int, cycle: Int64) -> GameTime {
        let arrival = timetable[stop].arrival
        guard cycle > 0, let timetablePeriod else { return arrival }
        return GameTime(seconds: arrival.seconds + cycle * timetablePeriod)
    }

    /// The call before timetable entry `stop` in `cycle`: the entry before
    /// it, or the last entry of the cycle before for entry 0; `nil` for
    /// entry 0 of cycle 0.
    func call(before stop: Int, cycle: Int64) -> (stop: Int, cycle: Int64)? {
        if stop > 0 { return (stop - 1, cycle) }
        return cycle > 0 ? (timetable.count - 1, cycle - 1) : nil
    }

    /// The call a service makes after leaving timetable entry `stop` in
    /// `cycle`: the next entry of the same cycle; after the last entry of a
    /// repeating timetable, the first entry of the next cycle, if its times
    /// fit in a ``GameTime``; otherwise `nil`, and the service is complete.
    func call(after stop: Int, cycle: Int64) -> (stop: Int, cycle: Int64)? {
        if stop + 1 < timetable.count { return (stop + 1, cycle) }
        guard let timetablePeriod, cycle < ScheduledStop.lastCycle(of: timetable, period: timetablePeriod) else { return nil }
        return (0, cycle + 1)
    }

    /// The cycle a newly started service runs first: 0 for a timetable
    /// that runs once, and for a repeating one the first cycle whose first
    /// departure is not before `now`, so the train starts on time. If even
    /// the last cycle whose times fit leaves its first stop before `now`,
    /// that last cycle.
    ///
    /// - Precondition: the timetable is not empty.
    func startingCycle(at now: GameTime) -> Int64 {
        guard let timetablePeriod else { return 0 }
        let departure = timetable[0].departure.seconds
        guard now.seconds > departure else { return 0 }
        // departure >= 0 and now > departure, so this is positive and fits.
        let late = now.seconds - departure
        let cycles = late / timetablePeriod + (late % timetablePeriod == 0 ? 0 : 1)
        return min(cycles, ScheduledStop.lastCycle(of: timetable, period: timetablePeriod))
    }
}

extension Train: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, position, movement, timetable, period, execution, times, cars, trail, trailEdges, reservation, performance
    }

    /// Decodes a train.
    ///
    /// An unplaced train has no `"position"` key, which is also how trains
    /// saved before positions existed read. An idle train has no `"movement"`
    /// key, which is also how trains saved before movement existed read. A
    /// train without a timetable has no `"timetable"` key, which is also how
    /// trains saved before timetables existed read. A timetable that runs
    /// once has no `"period"` key, which is also how trains saved before
    /// timetables could repeat read. A train without an active service has
    /// no `"execution"` key, which is also how trains saved before services
    /// existed read. An explicit `null` for any of them is rejected, and so
    /// is a malformed value, a movement that does not fit the position (see
    /// ``TrainMovement/fits(_:)``), a timetable and period that are not a
    /// timetable (see ``ScheduledStop/isTimetable(_:period:)``), or an
    /// execution that does not fit the timetable, period, position and
    /// movement (see
    /// ``TimetableExecution/fits(timetable:period:position:movement:)``):
    /// none is ever read as unplaced, idle, without a timetable, as running
    /// once or without a service, no timetable is sorted or trimmed, no
    /// period is changed, and no execution is moved to another stop or
    /// cycle or dropped. A train of one car has no `"cars"` key, which is
    /// also how trains saved before trains had length read; cars outside
    /// `minimumCars...maximumCars` are rejected.
    ///
    /// A train whose body reaches beyond its head's edge has `"trailEdges"`
    /// (edge numbers, Stage S3); without the key, which is also how trains
    /// saved before Stage S3 read, it has none, and an explicit `null` is
    /// rejected. An unplaced train with trail edges and a train with a body
    /// at offset 0 (see ``TrainPosition``) are rejected; whether its edges
    /// exist and its body fits them is checked by the ``GameWorld`` decoder.
    ///
    /// A body on the grid (a `"trail"` of tiles), which only a save made by
    /// hand could hold, is refused with that reason: the grid went in Stage
    /// F3c (ARCHITECTURE decision 51). An empty `"trail"`, which every train
    /// could have had, is read as none.
    ///
    /// A train running a service has `"times"` (Stage W2b; see
    /// ``ServiceTimes``), and one without a service has none; times without
    /// a service, a service without times, or times that do not fit what
    /// the service is doing (see ``ServiceTimes/fits(_:)``) are rejected,
    /// and so is an explicit `null`. That they are not after the clock is
    /// checked by the ``GameWorld`` decoder.
    ///
    /// A train without a reservation (Stage T) has no `"reservation"` key,
    /// which is also how trains saved before traffic control read; an
    /// explicit `null`, resources out of order or repeated, and a
    /// reservation on an unplaced train are rejected. Whether the resources
    /// exist and fit the train's route is checked by the ``GameWorld``
    /// decoder.
    ///
    /// A train with the standard performance (Stage W2c) has no
    /// `"performance"` key, which is also how trains saved before Stage W2c
    /// read; an explicit `null` and a performance that is not valid (see
    /// ``TrainPerformance/isValid``) are rejected, and so is a service run
    /// (see ``ServiceRun``) for which the performance builds no curve.
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
        timetable = container.contains(.timetable)
            ? try container.decode([ScheduledStop].self, forKey: .timetable)
            : []
        timetablePeriod = container.contains(.period)
            ? try container.decode(Int64.self, forKey: .period)
            : nil
        execution = container.contains(.execution)
            ? try container.decode(TimetableExecution.self, forKey: .execution)
            : nil
        times = container.contains(.times) ? try container.decode(ServiceTimes.self, forKey: .times) : nil
        cars = container.contains(.cars) ? try container.decode(Int.self, forKey: .cars) : Self.minimumCars
        let gridTrail = container.contains(.trail) ? try container.decode([GridPosition].self, forKey: .trail) : []
        guard gridTrail.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .trail, in: container,
                debugDescription: "Train \(id.rawValue) has a body on the grid, which is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold one."
            )
        }
        trailEdges = container.contains(.trailEdges) ? try container.decode([Int].self, forKey: .trailEdges).map(TrackEdgeID.edge) : []
        reservation = container.contains(.reservation) ? try container.decode([TrackResource].self, forKey: .reservation) : []
        performance = container.contains(.performance) ? try container.decode(TrainPerformance.self, forKey: .performance) : .standard
        guard zip(reservation, reservation.dropFirst()).allSatisfy({ $0 < $1 }), position != nil || reservation.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .reservation, in: container,
                debugDescription: "Train \(id.rawValue)'s reservation must be in resource order without repeats, and only on a placed train."
            )
        }
        guard (Self.minimumCars...Self.maximumCars).contains(cars) else {
            throw DecodingError.dataCorruptedError(
                forKey: .cars, in: container, debugDescription: "Train \(id.rawValue) has \(cars) cars; a train has \(Self.minimumCars) to \(Self.maximumCars)."
            )
        }
        if case .onEdge(_, let offset)? = position {
            guard length == 0 || offset > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .position, in: container,
                    debugDescription: "Train \(id.rawValue) has a body at offset 0."
                )
            }
            guard trailEdges.allSatisfy({ ($0.networkNumber ?? 0) >= 1 }) else {
                throw DecodingError.dataCorruptedError(forKey: .trailEdges, in: container, debugDescription: "Train \(id.rawValue)'s trail edges must be numbered from 1.")
            }
        } else {
            guard trailEdges.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .trailEdges, in: container, debugDescription: "Train \(id.rawValue) has trail edges but is not on the track.")
            }
        }
        guard movement.fits(position) else {
            throw DecodingError.dataCorruptedError(
                forKey: .movement, in: container,
                debugDescription: "Train \(id.rawValue)'s movement does not fit its position."
            )
        }
        guard ScheduledStop.isTimetable(timetable) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timetable, in: container,
                debugDescription: "Train \(id.rawValue)'s timetable goes back in time."
            )
        }
        guard ScheduledStop.isTimetable(timetable, period: timetablePeriod) else {
            throw DecodingError.dataCorruptedError(
                forKey: .period, in: container,
                debugDescription: "Train \(id.rawValue)'s timetable cannot repeat every \(timetablePeriod ?? 0) seconds."
            )
        }
        if let execution, !execution.fits(timetable: timetable, period: timetablePeriod, position: position, movement: movement) {
            throw DecodingError.dataCorruptedError(
                forKey: .execution, in: container,
                debugDescription: "Train \(id.rawValue)'s service does not fit its timetable, period, position and movement."
            )
        }
        // Stage W2b: a service has its times, and they fit what it is doing.
        guard (execution == nil) == (times == nil), execution.map({ times!.fits($0) }) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .times, in: container,
                debugDescription: "Train \(id.rawValue)'s service times are missing, or do not fit what its service is doing."
            )
        }
        // Stage W2c: the train's performance builds a curve for its run.
        if let run = times?.run, run.curve(for: performance) == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .times, in: container,
                debugDescription: "Train \(id.rawValue)'s performance builds no curve for its run."
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
        if !timetable.isEmpty {
            try container.encode(timetable, forKey: .timetable)
        }
        try container.encodeIfPresent(timetablePeriod, forKey: .period)
        try container.encodeIfPresent(execution, forKey: .execution)
        try container.encodeIfPresent(times, forKey: .times)
        if cars != Self.minimumCars {
            try container.encode(cars, forKey: .cars)
        }
        if !trailEdges.isEmpty {
            try container.encode(trailEdges.map { $0.networkNumber }, forKey: .trailEdges)
        }
        if !reservation.isEmpty {
            try container.encode(reservation, forKey: .reservation)
        }
        if performance != .standard {
            try container.encode(performance, forKey: .performance)
        }
    }
}
