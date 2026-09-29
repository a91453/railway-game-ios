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
/// position on the track and a movement (rate and continuation). Consists
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
    /// How often the timetable repeats, in whole game minutes, or `nil` for
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
    /// While it is set, the service owns the train's continuation (see
    /// ``TimetableExecution``).
    public internal(set) var execution: TimetableExecution?
    /// How many cars the train has (Phase 4.5 Stage S2), one to a tile:
    /// 1, as every newly bought train has, up to ``maximumCars``. Set by
    /// ``GameWorld/setTrainCars(_:to:)`` while the train is unplaced.
    public internal(set) var cars: Int
    /// The nodes the train's body lies over behind its head, nearest first
    /// (see ``length``): every node behind the head that the body reaches
    /// or passes, up to and including the first at or beyond its tail.
    /// Empty for a train of one car or unplaced. Only ``GameWorld``
    /// changes it, as the head moves.
    public internal(set) var trail: [GridPosition]

    /// Creates an unplaced, idle train of one car without a timetable or a
    /// service.
    public init(id: TrainID, name: String) {
        self.id = id
        self.name = name
        self.position = nil
        self.movement = .idle
        self.timetable = []
        self.timetablePeriod = nil
        self.execution = nil
        self.cars = 1
        self.trail = []
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
        return GameTime(minutes: departure.minutes + cycle * timetablePeriod)
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
        let departure = timetable[0].departure.minutes
        guard now.minutes > departure else { return 0 }
        // departure >= 0 and now > departure, so this is positive and fits.
        let late = now.minutes - departure
        let cycles = late / timetablePeriod + (late % timetablePeriod == 0 ? 0 : 1)
        return min(cycles, ScheduledStop.lastCycle(of: timetable, period: timetablePeriod))
    }
}

extension Train: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, position, movement, timetable, period, execution, cars, trail
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
    /// cycle or dropped. A train of one car has no `"cars"` and no
    /// `"trail"` key, which is also how trains saved before trains had
    /// length read; cars outside `minimumCars...maximumCars`, or a trail that does not
    /// fit the length and position (see ``isTrail(_:length:at:)``), are
    /// rejected. That the trail is on this map's track is checked by the
    /// ``GameWorld`` decoder.
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
        cars = container.contains(.cars) ? try container.decode(Int.self, forKey: .cars) : Self.minimumCars
        trail = container.contains(.trail) ? try container.decode([GridPosition].self, forKey: .trail) : []
        guard (Self.minimumCars...Self.maximumCars).contains(cars) else {
            throw DecodingError.dataCorruptedError(
                forKey: .cars, in: container, debugDescription: "Train \(id.rawValue) has \(cars) cars; a train has \(Self.minimumCars) to \(Self.maximumCars)."
            )
        }
        guard Self.isTrail(trail, length: length, at: position) else {
            throw DecodingError.dataCorruptedError(
                forKey: .trail, in: container, debugDescription: "Train \(id.rawValue)'s trail does not fit its length and position."
            )
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
                debugDescription: "Train \(id.rawValue)'s timetable cannot repeat every \(timetablePeriod ?? 0) minutes."
            )
        }
        if let execution, !execution.fits(timetable: timetable, period: timetablePeriod, position: position, movement: movement) {
            throw DecodingError.dataCorruptedError(
                forKey: .execution, in: container,
                debugDescription: "Train \(id.rawValue)'s service does not fit its timetable, period, position and movement."
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
        if cars != Self.minimumCars {
            try container.encode(cars, forKey: .cars)
        }
        if !trail.isEmpty {
            try container.encode(trail, forKey: .trail)
        }
    }
}
