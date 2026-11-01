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
///
/// On a ring (decision 49) a run goes round one way, ``way`` (decision
/// 535): from `from` it calls at the next stop that way each time, on past
/// the last stop to the first (or the first to the last), `times.count - 1`
/// legs, ending at `to`; `from == to` is a whole lap. A run of any other
/// line has no way.
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
    /// Decision 535: on a ring, the way round it goes; `nil` on any other
    /// line.
    public let way: RingDirection?

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

    public init(from: Int, to: Int, times: [LineRunTime], days: Int = everyDay, way: RingDirection? = nil) {
        self.from = from
        self.to = to
        self.times = times
        self.days = days
        self.way = way
    }

    /// The stops it calls at, as indices into the line's stops, in order,
    /// for a run of a line that is not a ring (see ``calls(stopCount:)``).
    public var calls: [Int] {
        from < to ? Array(from...to) : Array((to...from).reversed())
    }

    /// The stops it calls at on a line with `stopCount` stops, in order:
    /// on a ring (decision 535) `from`, then the next stop ``way`` each
    /// time, round past the line's ends, to `to`; otherwise ``calls``.
    public func calls(stopCount: Int) -> [Int] {
        guard let way, stopCount > 0 else { return calls }
        let step = way == .inner ? 1 : stopCount - 1
        return (0...Self.ringLegs(from: from, to: to, way: way, stopCount: stopCount)).map { (from + $0 * step) % stopCount }
    }

    /// Decision 535: the legs from stop `from` to stop `to` going `way`
    /// round a ring of `stopCount` stops: a whole lap when they are the
    /// same stop.
    static func ringLegs(from: Int, to: Int, way: RingDirection, stopCount: Int) -> Int {
        let difference = way == .inner ? to - from : from - to
        let legs = ((difference % stopCount) + stopCount) % stopCount
        return legs == 0 ? stopCount : legs
    }

    /// Whether it runs the way the line's stops are listed: on a ring
    /// (decision 535) the ``RingDirection/inner`` way.
    public var isOutbound: Bool {
        way.map { $0 == .inner } ?? (from < to)
    }

    /// Whether it is a run of a line with `stopCount` stops, a ring when
    /// `ring`: two different stops of it, or on a ring (decision 535) with
    /// a way and up to a whole lap round (the same stop); a time for each
    /// call, times that never go back (a call arrives no earlier than the
    /// one before leaves) and end before ``latestSecond``, and some day of
    /// the week.
    func isValid(stopCount: Int, ring: Bool = false) -> Bool {
        guard (0..<stopCount).contains(from), (0..<stopCount).contains(to), (1...Self.everyDay).contains(days) else { return false }
        if ring {
            guard let way, times.count == Self.ringLegs(from: from, to: to, way: way, stopCount: stopCount) + 1 else { return false }
        } else {
            guard way == nil, from != to, times.count == abs(to - from) + 1 else { return false }
        }
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

    /// Whether everything a train sent out on this run on game day `day`
    /// is timed at fits in a clock: its last call, after the latest
    /// dispatch and a terminal's dwell. Near the end of time a day does
    /// not, and is passed over.
    func fits(onDay day: Int64) -> Bool {
        let (base, over) = day.multipliedReportingOverflow(by: GameTime.secondsPerDay)
        guard !over, let last = times.map({ max($0.arrival, $0.departure) }).max() else { return false }
        let margin = last + LineRun.latestDispatch + ServiceDwell.terminalMinimum + 1
        return !base.addingReportingOverflow(margin).overflow
    }
}

extension ServiceLine {
    /// Whether the line runs a timetable (decision 133) rather than a
    /// headway.
    public var hasRuns: Bool {
        !runs.isEmpty
    }

    /// Whether `runs` can be this line's: each a run of it (see
    /// ``LineRun/isValid(stopCount:ring:)``), on a line that has no
    /// patterns and calls at no station twice. Since decision 535 a ring
    /// can have runs too, each going one way round.
    func canHave(_ runs: [LineRun]) -> Bool {
        guard !runs.isEmpty else { return true }
        return patterns.isEmpty && Set(stops).count == stops.count && runs.allSatisfy { $0.isValid(stopCount: stops.count, ring: isRing) }
    }

    /// The stops `run` calls at, in order (see ``LineRun/calls(stopCount:)``).
    func calls(of run: LineRun) -> [Int] {
        run.calls(stopCount: stops.count)
    }

    /// Whether riders can go from stop `from` to stop `to` (indices into
    /// the line's stops) on one train (decision 149): on a line with runs,
    /// some run goes that way and calls at both; on any other line, yes.
    /// A way or a stretch no run goes has no train, so no one sets out on
    /// it and no route plans it. On a ring with runs (decision 535) either
    /// way round, see ``runsServe(from:to:way:)``.
    func runsServe(from: Int, to: Int) -> Bool {
        guard hasRuns else { return true }
        if isRing { return RingDirection.allCases.contains { runsServe(from: from, to: to, way: $0) } }
        return runs.contains { run in
            run.isOutbound == (from < to) && min(run.from, run.to) <= min(from, to) && max(from, to) <= max(run.from, run.to)
        }
    }

    // MARK: - Arcs of a ring (decision 535)

    /// Where stop `stop` comes in a lap of the ring going `way` from its
    /// first stop: the place of its leg on (the ring's lap journeys'
    /// legs, ``ringCalls(_:)``).
    func ringPlace(of stop: Int, way: RingDirection) -> Int {
        way == .inner ? stop : (stops.count - stop) % stops.count
    }

    /// The legs of a ring a run going `way` drives, as the place of its
    /// first (see ``ringPlace(of:way:)``) and how many follow on round
    /// from there.
    func ringArc(of run: LineRun) -> (start: Int, legs: Int)? {
        guard isRing, let way = run.way else { return nil }
        return (ringPlace(of: run.from, way: way), LineRun.ringLegs(from: run.from, to: run.to, way: way, stopCount: stops.count))
    }

    /// Whether the legs `legs` from place `start` lie within those `legs`
    /// from place `outer` round a ring of `count` legs.
    static func arc(_ start: Int, _ legs: Int, liesWithin outer: Int, _ outerLegs: Int, count: Int) -> Bool {
        ((start - outer) % count + count) % count + legs <= outerLegs
    }

    /// Decision 535: whether a run of the ring goes `way` from stop `from`
    /// round to stop `to`, calling at both.
    func runsServe(from: Int, to: Int, way: RingDirection) -> Bool {
        guard isRing, from != to, stops.indices.contains(from), stops.indices.contains(to) else { return false }
        let start = ringPlace(of: from, way: way)
        let legs = LineRun.ringLegs(from: from, to: to, way: way, stopCount: stops.count)
        return runs.contains { run in
            guard run.way == way, let arc = ringArc(of: run) else { return false }
            return Self.arc(start, legs, liesWithin: arc.start, arc.legs, count: stops.count)
        }
    }

    /// Decision 535: what passengers ride a ring with runs on going `way`,
    /// as decision 149's stretches do on a line with ends: the stops a
    /// whole lap starts at, busiest first (then by stop), each a lap
    /// passengers ride round from there; and the arcs of the other runs,
    /// as the place of their first leg and how many legs, leaving out
    /// those inside one of those laps or inside another arc, by place.
    /// A ride within one of them is served (``runsServe(from:to:way:)``).
    func ringRunPaths(way: RingDirection) -> (laps: [Int], arcs: [(start: Int, legs: Int)]) {
        let count = stops.count
        var starts: [Int: Int] = [:]
        var arcs: [(start: Int, legs: Int)] = []
        for run in runs where run.way == way {
            guard let arc = ringArc(of: run) else { continue }
            if arc.legs == count { starts[run.from, default: 0] += 1 } else if !arcs.contains(where: { $0 == arc }) { arcs.append(arc) }
        }
        let laps = starts.keys.sorted { (starts[$0]!, -$0) > (starts[$1]!, -$1) }
        let kept = arcs.filter { arc in
            !laps.contains { Self.arc(arc.start, arc.legs, liesWithin: ringPlace(of: $0, way: way), count, count: count) }
                && !arcs.contains { $0 != arc && Self.arc(arc.start, arc.legs, liesWithin: $0.start, $0.legs, count: count) }
        }
        return (laps, kept.sorted { ($0.start, $0.legs) < ($1.start, $1.legs) })
    }

    /// The stretches of the line its runs go `outbound` or back (decision
    /// 149), as ranges of stop indices in the line's order: each run's,
    /// leaving out those inside another's, by their first stop. A ride
    /// within one of them is served (``runsServe(from:to:)``).
    func runStretches(outbound: Bool) -> [ClosedRange<Int>] {
        let spans = Set(runs.filter { $0.isOutbound == outbound }.map { min($0.from, $0.to)...max($0.from, $0.to) })
        return spans
            .filter { span in !spans.contains { $0 != span && $0.lowerBound <= span.lowerBound && span.upperBound <= $0.upperBound } }
            .sorted { ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound) }
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
            for day in (today - 2)...(today + 1) where day >= 0 && run.runs(onDay: day) && (runDays[index] ?? -1) < day && run.fits(onDay: day) {
                let start = run.start(onDay: day)
                if start - LineRun.earliestDispatch <= now.seconds, now.seconds <= start + LineRun.latestDispatch {
                    due.append((index, day, start))
                }
            }
        }
        return due.sorted { ($0.start, $0.run) < ($1.start, $1.run) }.map { ($0.run, $0.day) }
    }

    /// The first second after `now` at which a run starts or stops being
    /// due (see ``dueRuns(at:)``), or `nil` if none ever does. The days
    /// looked at run a week past tomorrow, so a run on any weekday is
    /// seen: an idle step skips to this second, and a run days away must
    /// still wake it (decision 133).
    func nextRunChange(after now: GameTime) -> GameTime? {
        guard hasRuns else { return nil }
        let today = GameTime.floorDivide(now.seconds, GameTime.secondsPerDay)
        var soonest: Int64?
        for (index, run) in runs.enumerated() {
            for day in (today - 2)...(today + 8) where day >= 0 && run.runs(onDay: day) && (runDays[index] ?? -1) < day && run.fits(onDay: day) {
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
    /// departure (or ``ServiceDwell/terminalMinimum`` from now, if later;
    /// on a ring, decision 535, ``ServiceDwell/minimum`` unless the train
    /// turns round first, as a ring's lap leaves), every other call at the
    /// run's times, but never before the call before has left; the last
    /// call is where the service ends.
    func timetable(_ run: LineRun, calling stops: [StationID], day: Int64, sentOutAt dispatch: GameTime) -> [ScheduledStop] {
        let base = day * GameTime.secondsPerDay
        let calls = run.calls(stopCount: stops.count)
        let least = run.way != nil && !turnsFirst ? ServiceDwell.minimum : ServiceDwell.terminalMinimum
        var timetable = [ScheduledStop(
            station: stops[calls[0]], arrival: dispatch,
            departure: GameTime(seconds: max(dispatch.seconds + least, base + run.times[0].departure)), reverses: turnsFirst
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
    ///
    /// Decision 535: on a ring the train goes as it faces when it faces the
    /// run's way round (``facesRingWay(_:_:on:at:)``), and turns round
    /// first only when it does not, or cannot go on as it faces: one way
    /// round is one track of a double ring, and turned round where it is
    /// shorter it would run against that way's trains.
    func runTrip(of line: ServiceLine, _ run: LineRun, for train: Train) -> RunTrip? {
        guard let placement = train.placement else { return nil }
        let calls = line.calls(of: run)
        let ahead = driveRun(line, calling: calls, from: placement)
        if let way = run.way, let ahead, facesRingWay(placement, way, on: line, at: run.from) {
            return RunTrip(turnsFirst: false, legs: ahead.legs, turnbacks: ahead.turnbacks)
        }
        let turned = driveRun(line, calling: calls, from: turnedRound(placement))
        if run.way != nil {
            if let turned { return RunTrip(turnsFirst: true, legs: turned.legs, turnbacks: turned.turnbacks) }
            return ahead.map { RunTrip(turnsFirst: false, legs: $0.legs, turnbacks: $0.turnbacks) }
        }
        func seconds(_ legs: [LineLeg]) -> Int64 { legs.reduce(0) { $0 + $1.seconds } }
        if let turned, ahead.map({ seconds(turned.legs) < seconds($0.legs) }) ?? true {
            return RunTrip(turnsFirst: true, legs: turned.legs, turnbacks: turned.turnbacks)
        }
        return ahead.map { RunTrip(turnsFirst: false, legs: $0.legs, turnbacks: $0.turnbacks) }
    }

    /// Decision 535: whether a train standing at `placement` at stop `stop`
    /// of ring `line` faces the way `way` round it: going on as it faces,
    /// the next stop that way is nearer than the next stop the other way
    /// (which, facing that way, it reaches only round the whole ring), or
    /// the other way has no route ahead at all.
    func facesRingWay(_ placement: TrainPlacement, _ way: RingDirection, on line: ServiceLine, at stop: Int) -> Bool {
        let count = line.stops.count
        guard line.isRing, count >= 3 else { return false }
        let routes = line.routes(ofService: 0)
        let next = way == .inner ? (stop + 1) % count : (stop + count - 1) % count
        let other = way == .inner ? (stop + count - 1) % count : (stop + 1) % count
        guard let there = linePath(line, from: stop, to: next, start: placement.position, length: placement.length, routes: routes) else { return false }
        guard let back = linePath(line, from: stop, to: other, start: placement.position, length: placement.length, routes: routes) else { return true }
        return there.distance < back.distance
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
                guard let least = RunCurve.leastSeconds(length: path.distance, performance: line.performance,
                                                       limits: speedLimits(from: placement, along: path, below: line.performance.topSpeed)) else { return nil }
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
    /// of its first departure now, or the route its line names for that
    /// leg (decision 323), which it leaves by first when it can (decision
    /// 61). With its index and timetable.
    ///
    /// Decision 535: on a ring, a train that faces the run's way round
    /// first, and only when none does one that turns round.
    func readyRunTrain(of line: ServiceLine, _ run: LineRun, day: Int64) -> (index: Int, timetable: [ScheduledStop])? {
        if run.way != nil {
            return readyRunTrain(of: line, run, day: day, turning: false) ?? readyRunTrain(of: line, run, day: day, turning: true)
        }
        return readyRunTrain(of: line, run, day: day, turning: nil)
    }

    /// ``readyRunTrain(of:_:day:)`` among the trains whose trip turns
    /// round first when `turning` is `true`, or does not when `false`, or
    /// either when `nil`.
    private func readyRunTrain(of line: ServiceLine, _ run: LineRun, day: Int64, turning: Bool?) -> (index: Int, timetable: [ScheduledStop])? {
        let first = line.stops[run.from]
        for id in line.trains {
            guard let index = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[index]
            guard train.execution == nil, train.placement != nil, train.movement.rate > 0, isStopped(train, at: first),
                  let trip = runTrip(of: line, run, for: train), turning.map({ $0 == trip.turnsFirst }) ?? true
            else { continue }
            let timetable = trip.timetable(run, calling: line.stops, day: day, sentOutAt: clock.now)
            if isTrafficControlEnabled, let leaving = sentOut(train, on: timetable), case .held = reservingDeparture(leaving) {
                var memo = PathMemo()
                guard case .setsOff(let preferred, _)? = preferredLeaving(dispatched(train, on: timetable), stop: 0, cycle: 0, memo: &memo),
                      case .granted = reserving(preferred, following: blockSections)
                else { continue }
            }
            return (index, timetable)
        }
        return nil
    }

    /// `train` sent out now on `timetable`, as it would be once it has left
    /// the first call.
    func sentOut(_ train: Train, on timetable: [ScheduledStop]) -> Train? {
        leaving(dispatched(train, on: timetable), stop: 0, cycle: 0).train
    }

    /// `train` given `timetable` now, waiting at its first call.
    private func dispatched(_ train: Train, on timetable: [ScheduledStop]) -> Train {
        var sent = train
        sent.timetable = timetable
        sent.timetablePeriod = nil
        sent.execution = .waitingAtStop(0)
        sent.times = ServiceTimes(arrival: clock.now)
        return sent
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
        case from, to, times, days, way
    }

    /// Decodes `{"from", "to", "times": [[arrival, departure], …], "days",
    /// "way"}`, `"days"` left out for every day, `"way"` (decision 535,
    /// `"inner"` or `"outer"`) for a run of a ring only. Whether the run
    /// fits its line is the line's to check.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pairs = try container.decode([[Int64]].self, forKey: .times)
        guard pairs.allSatisfy({ $0.count == 2 }) else {
            throw DecodingError.dataCorruptedError(forKey: .times, in: container, debugDescription: "A run's call is [arrival, departure].")
        }
        self.init(
            from: try container.decode(Int.self, forKey: .from), to: try container.decode(Int.self, forKey: .to),
            times: pairs.map { LineRunTime(arrival: $0[0], departure: $0[1]) },
            days: container.contains(.days) ? try container.decode(Int.self, forKey: .days) : Self.everyDay,
            way: try container.decodeIfPresent(RingDirection.self, forKey: .way)
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
        try container.encodeIfPresent(way, forKey: .way)
    }
}
