// A line's runs (ARCHITECTURE decision 133): the trains of a real
// timetable. A line with runs sends its trains out at the times they give
// rather than at a headway (decision 23): each run goes one way along the
// line, from any of its stops to any other, calling at every stop between,
// on the days of the week it runs, at the seconds of the day it lists. A
// train that finishes a run waits where it ended for the next run that
// starts there. Passengers ride runs as they ride any line (decision 35),
// the way each run goes.
//
// The reference runs TRA's trains from their timetable on its map
// (`Railway/site_archive_clean/index.html`, the `sched` systems): each
// train appears at its first station at its departure and moves along its
// stops by time. Here a train is bought and placed (decision 14), so a run
// takes a train already standing at its first stop; one with none there
// waits for it, and is dropped for the day when it is late by more than
// ``LineRun/latestDispatch``.

/// One call of a run: when the train arrives and leaves, in seconds of
/// the run's service day (0 its midnight; a call after the next midnight
/// is past 86,400).
public struct LineRunTime: Hashable, Sendable {
    public let arrival: Int64
    public let departure: Int64

    public init(arrival: Int64, departure: Int64) {
        self.arrival = arrival
        self.departure = departure
    }
}

/// One train of a line's timetable (decision 133): from stop `from` to
/// stop `to` (indices into the line's stops), calling at every stop
/// between, at `times`, on `days`.
public struct LineRun: Hashable, Sendable {
    /// The index, in the line's stops, of the stop it leaves first.
    public let from: Int
    /// The index of the stop it ends at.
    public let to: Int
    /// Each call's times, from `from` to `to`.
    public let times: [LineRunTime]
    /// The days of the week it runs: bit `w` for weekday `w`, 0 Sunday to 6
    /// Saturday (see ``StationDemand/weekday(ofDay:)``; a game starts on a
    /// Monday).
    public let days: Int

    /// Every day of the week.
    public static let everyDay = 0b111_1111
    /// How long before its first departure a run sends its train out, so
    /// it stands at the first stop taking on passengers: five minutes.
    public static let earliestDispatch: Int64 = 5 * GameTime.secondsPerMinute
    /// How late after its first departure a run that found no train ready
    /// still sends one out; later it is dropped for that day: half an hour.
    public static let latestDispatch: Int64 = 30 * GameTime.secondsPerMinute
    /// A run's times end before the second midnight after its day began.
    public static let latestSecond: Int64 = 2 * GameTime.secondsPerDay

    public init(from: Int, to: Int, times: [LineRunTime], days: Int = everyDay) {
        self.from = from
        self.to = to
        self.times = times
        self.days = days
    }

    /// The stops it calls at, as indices into the line's stops, in order.
    public var calls: [Int] {
        from < to ? Array(from...to) : Array((to...from).reversed())
    }

    /// Whether it runs the way the line's stops are listed.
    public var isOutbound: Bool {
        from < to
    }

    /// Whether it is a run of a line with `stopCount` stops: two different
    /// stops of it, a time for each call, times that never go back (a call
    /// arrives no earlier than the one before leaves) and end before
    /// ``latestSecond``, and some day of the week.
    func isValid(stopCount: Int) -> Bool {
        guard from != to, (0..<stopCount).contains(from), (0..<stopCount).contains(to),
              times.count == abs(to - from) + 1, (1...Self.everyDay).contains(days)
        else { return false }
        guard times.allSatisfy({ 0 <= $0.arrival && $0.arrival <= $0.departure && $0.departure < Self.latestSecond }) else { return false }
        return zip(times, times.dropFirst()).allSatisfy { $0.departure <= $1.arrival }
    }

    /// Whether it runs on game day `day`.
    func runs(onDay day: Int64) -> Bool {
        days & (1 << StationDemand.weekday(ofDay: day)) != 0
    }

    /// The second its first departure falls on, on game day `day`.
    func start(onDay day: Int64) -> Int64 {
        day * GameTime.secondsPerDay + times[0].departure
    }
}

extension ServiceLine {
    /// Whether the line runs a timetable (decision 133) rather than a
    /// headway.
    public var hasRuns: Bool {
        !runs.isEmpty
    }

    /// Whether `runs` can be this line's: each a run of it (see
    /// ``LineRun/isValid(stopCount:)``), on a line that is not a ring, has
    /// no patterns and calls at no station twice.
    func canHave(_ runs: [LineRun]) -> Bool {
        guard !runs.isEmpty else { return true }
        return !isRing && patterns.isEmpty && Set(stops).count == stops.count && runs.allSatisfy { $0.isValid(stopCount: stops.count) }
    }

    /// The minutes between the line's runs each way, as the route planners
    /// and the line's queries see them (decision 133): the day its runs
    /// span, from the first departure to the last, shared between the runs
    /// of the busier way, rounded up; a whole day when that way has one.
    /// Never less than ``minimumHeadwayMinutes``.
    var runHeadway: Int64 {
        let outbound = runs.count { $0.isOutbound }
        let most = max(outbound, runs.count - outbound)
        guard most > 1 else { return GameTime.minutesPerDay }
        let departures = runs.map { $0.times[0].departure }
        let span = departures.max()! - departures.min()!
        let minutes = Self.dividedRoundingUp(Self.dividedRoundingUp(span, by: Int64(most - 1)), by: GameTime.secondsPerMinute)
        return max(Self.minimumHeadwayMinutes, minutes)
    }

    /// The days and runs due at `now`, earliest first (then in run order):
    /// those whose day it runs on, which have not sent a train out that
    /// day, and whose first departure is at most
    /// ``LineRun/earliestDispatch`` ahead of now and at most
    /// ``LineRun/latestDispatch`` behind.
    func dueRuns(at now: GameTime) -> [(run: Int, day: Int64)] {
        guard hasRuns else { return [] }
        let today = GameTime.floorDivide(now.seconds, GameTime.secondsPerDay)
        var due: [(run: Int, day: Int64, start: Int64)] = []
        for (index, run) in runs.enumerated() {
            for day in (today - 2)...(today + 1) where day >= 0 && run.runs(onDay: day) && (runDays[index] ?? -1) < day {
                let start = run.start(onDay: day)
                if start - LineRun.earliestDispatch <= now.seconds, now.seconds <= start + LineRun.latestDispatch {
                    due.append((index, day, start))
                }
            }
        }
        return due.sorted { ($0.start, $0.run) < ($1.start, $1.run) }.map { ($0.run, $0.day) }
    }

    /// The first second after `now` at which a run starts or stops being
    /// due (see ``dueRuns(at:)``), within the next two days, or `nil`.
    func nextRunChange(after now: GameTime) -> GameTime? {
        guard hasRuns else { return nil }
        let today = GameTime.floorDivide(now.seconds, GameTime.secondsPerDay)
        var soonest: Int64?
        for (index, run) in runs.enumerated() {
            for day in (today - 2)...(today + 2) where day >= 0 && run.runs(onDay: day) && (runDays[index] ?? -1) < day {
                let start = run.start(onDay: day)
                for edge in [start - LineRun.earliestDispatch, start + LineRun.latestDispatch + 1] where edge > now.seconds {
                    soonest = min(soonest ?? .max, edge)
                }
            }
        }
        return soonest.map { GameTime(seconds: $0) }
    }
}

/// The way a run sends a train (decision 133): whether it turns round
/// before it leaves its first stop, and the legs it drives from there.
struct RunTrip: Hashable, Sendable {
    let turnsFirst: Bool
    let legs: [LineLeg]
    /// Stops (indices into the run's calls) where the train turns round
    /// before going on (V4d).
    let turnbacks: [Int]

    /// The run's timetable for a train sent out at `dispatch` for game day
    /// `day`: the first stop arriving now and leaving at the run's first
    /// departure (or ``ServiceDwell/terminalMinimum`` from now, if later),
    /// every other call at the run's times, but never before the call
    /// before has left; the last call is where the service ends.
    func timetable(_ run: LineRun, calling stops: [StationID], day: Int64, sentOutAt dispatch: GameTime) -> [ScheduledStop] {
        let base = day * GameTime.secondsPerDay
        let calls = run.calls
        var timetable = [ScheduledStop(
            station: stops[calls[0]], arrival: dispatch,
            departure: GameTime(seconds: max(dispatch.seconds + ServiceDwell.terminalMinimum, base + run.times[0].departure)), reverses: turnsFirst
        )]
        for index in calls.indices.dropFirst() {
            let left = timetable[index - 1].departure.seconds
            let arrival = max(left, base + run.times[index].arrival)
            let isLast = index == calls.count - 1
            let departure = isLast ? arrival : max(arrival, base + run.times[index].departure)
            timetable.append(ScheduledStop(
                station: stops[calls[index]], arrival: GameTime(seconds: arrival), departure: GameTime(seconds: departure),
                reverses: !isLast && turnbacks.contains(index)
            ))
        }
        return timetable
    }
}

extension GameWorld {
    /// The one-way trip `train` would make for `run` of `line` from where
    /// it stands: as it faces, or turned round first when only that can be
    /// driven or it is shorter. `nil` if neither can be driven, or the
    /// train is not placed. Each leg as a line's journey drives it (see
    /// ``drive(_:calling:from:routes:)``), turning round between the ends
    /// only where the track makes it (V4d).
    func runTrip(of line: ServiceLine, _ run: LineRun, for train: Train) -> RunTrip? {
        guard let placement = train.placement else { return nil }
        let ahead = driveRun(line, calling: run.calls, from: placement)
        let turned = driveRun(line, calling: run.calls, from: turnedRound(placement))
        func seconds(_ legs: [LineLeg]) -> Int64 { legs.reduce(0) { $0 + $1.seconds } }
        if let turned, ahead.map({ seconds(turned.legs) < seconds($0.legs) }) ?? true {
            return RunTrip(turnsFirst: true, legs: turned.legs, turnbacks: turned.turnbacks)
        }
        return ahead.map { RunTrip(turnsFirst: false, legs: $0.legs, turnbacks: $0.turnbacks) }
    }

    /// The legs of `line` calling at `calls` one way, driven from `start`,
    /// and where the train turns round between them, or `nil` if a leg has
    /// no route or no running curve.
    private func driveRun(_ line: ServiceLine, calling calls: [Int], from start: TrainPlacement) -> (legs: [LineLeg], turnbacks: [Int])? {
        let routes = line.routes(ofService: 0)
        var placement = start
        var legs: [LineLeg] = []
        var turnbacks: [Int] = []
        for (from, to) in zip(calls, calls.dropFirst()) {
            var chosen = linePath(line, from: from, to: to, start: placement.position, length: placement.length, routes: routes)
            if chosen == nil, isTrafficControlEnabled, !legs.isEmpty {
                let reverse = turnedRound(placement)
                if let path = linePath(line, from: from, to: to, start: reverse.position, length: reverse.length, routes: routes) {
                    placement = reverse
                    chosen = path
                    turnbacks.append(legs.count)
                }
            }
            guard let path = chosen else { return nil }
            var seconds: Int64 = 0
            if path.distance > 0 {
                guard let least = RunningCurve.leastSeconds(length: path.distance, performance: line.performance) else { return nil }
                seconds = least
            }
            legs.append(LineLeg(from: from, to: to, path: path, seconds: seconds))
            placement = self.placement(placement, after: path)
        }
        return (legs, turnbacks)
    }

    /// The first of `line`'s trains, in ID order, that `run` can send out
    /// now for game day `day`: one without a service, placed, with a rate
    /// above 0, stopped at the run's first stop, and able to drive it from
    /// there; under traffic control (Stage T) also able to take the route
    /// of its first departure now. With its index and timetable.
    func readyRunTrain(of line: ServiceLine, _ run: LineRun, day: Int64) -> (index: Int, timetable: [ScheduledStop])? {
        let first = line.stops[run.from]
        for id in line.trains {
            guard let index = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[index]
            guard train.execution == nil, train.placement != nil, train.movement.rate > 0, isStopped(train, at: first),
                  let trip = runTrip(of: line, run, for: train)
            else { continue }
            let timetable = trip.timetable(run, calling: line.stops, day: day, sentOutAt: clock.now)
            if isTrafficControlEnabled, let leaving = sentOut(train, on: timetable), case .held = reservingDeparture(leaving) {
                continue
            }
            return (index, timetable)
        }
        return nil
    }

    /// `train` sent out now on `timetable`, as it would be once it has left
    /// the first call.
    func sentOut(_ train: Train, on timetable: [ScheduledStop]) -> Train? {
        var sent = train
        sent.timetable = timetable
        sent.timetablePeriod = nil
        sent.execution = .waitingAtStop(0)
        sent.times = ServiceTimes(arrival: clock.now)
        return leaving(sent, stop: 0, cycle: 0).train
    }

    /// The departure `train`, idle on a line with runs, is due to make now
    /// whether or not its route is free (Stage V2): the first run due now
    /// that it stands at the first stop of and can drive, as it would
    /// leave. `nil` when there is none.
    func dueRunDeparture(of train: Train, on line: ServiceLine) -> Train? {
        guard train.execution == nil, train.placement != nil, train.movement.rate > 0 else { return nil }
        for (index, day) in line.dueRuns(at: clock.now) {
            let run = line.runs[index]
            guard isStopped(train, at: line.stops[run.from]), let trip = runTrip(of: line, run, for: train) else { continue }
            return sentOut(train, on: trip.timetable(run, calling: line.stops, day: day, sentOutAt: clock.now))
        }
        return nil
    }

    /// Whether some run of `line` is due now with a train ready (see
    /// ``readyRunTrain(of:_:day:)``).
    func hasReadyRun(_ line: ServiceLine) -> Bool {
        line.dueRuns(at: clock.now).contains { readyRunTrain(of: line, line.runs[$0.run], day: $0.day) != nil }
    }

    /// Whether some run of `line` is due now that one of its trains stands
    /// at the start of and could drive, but only its route keeps from
    /// leaving (Stage V2).
    func hasRunWaitingForRoute(_ line: ServiceLine) -> Bool {
        line.trains.contains { id in
            guard let train = train(id: id) else { return false }
            return dueRunDeparture(of: train, on: line) != nil
        } && !hasReadyRun(line)
    }
}

// MARK: - Codable

extension LineRun: Codable {
    private enum CodingKeys: String, CodingKey {
        case from, to, times, days
    }

    /// Decodes `{"from", "to", "times": [[arrival, departure], …], "days"}`,
    /// `"days"` left out for every day. Whether the run fits its line is the
    /// line's to check.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pairs = try container.decode([[Int64]].self, forKey: .times)
        guard pairs.allSatisfy({ $0.count == 2 }) else {
            throw DecodingError.dataCorruptedError(forKey: .times, in: container, debugDescription: "A run's call is [arrival, departure].")
        }
        self.init(
            from: try container.decode(Int.self, forKey: .from), to: try container.decode(Int.self, forKey: .to),
            times: pairs.map { LineRunTime(arrival: $0[0], departure: $0[1]) },
            days: container.contains(.days) ? try container.decode(Int.self, forKey: .days) : Self.everyDay
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(times.map { [$0.arrival, $0.departure] }, forKey: .times)
        if days != Self.everyDay {
            try container.encode(days, forKey: .days)
        }
    }
}
