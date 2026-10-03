import GameCore

/// Stage W2c (ARCHITECTURE decision 40), written a second time for
/// ``ReferenceWorld``: performances, the least second a run takes, and a
/// service's runs. Written from the rules, not from GameCore, and
/// differently where it can be:
///
/// - the least second a curve is built for is found by trying every second
///   upward from one below the whole way at top speed, not by halving;
/// - the way a train has left is walked along its path's edges, not taken
///   from its route's stretches;
/// - whether it can move is a one-unit step taken on a copy;
/// - a run's share of a second is the curve's distance at the second's end
///   less at its start, each second, not a whole span at once.
///
/// The curve itself is GameCore's ``RunningCurve`` (Stage W1): it is the
/// reference's `buildProfile`, checked against the JavaScript by its own
/// differential (`RunningCurveTests`).
extension ReferenceWorld {
    /// Every rate and the top speed from 1 to 2²⁰; a coast slowing less than
    /// the braking, to a ratio of the cruise speed below 1000.
    static func isValid(_ performance: TrainPerformance) -> Bool {
        let fits = { (value: Int64) in value >= 1 && value <= 1 << 20 }
        guard fits(performance.acceleration), fits(performance.braking), fits(performance.topSpeed) else { return false }
        if let value = performance.alternativeAcceleration, !fits(value) { return false }
        if let value = performance.alternativeBraking, !fits(value) { return false }
        if let coast = performance.coast {
            return fits(coast.deceleration) && coast.deceleration < performance.braking
                && coast.speedRatio >= 0 && coast.speedRatio < 1000
        }
        return true
    }

    /// The train, then not while it runs a service, then the performance.
    mutating func setPerformance(_ id: TrainID, _ performance: TrainPerformance) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            guard trains[i].service == nil else { return .trainServiceActive(id) }
            guard Self.isValid(performance) else { return .invalidTrainPerformance }
            trains[i].performance = performance
            return nil
        }
    }

    /// The longest run in seconds: 2³² ms.
    static let longestRun: Int64 = (1 << 32) / 1000

    /// The least whole second `performance` builds a curve for over `length`
    /// units, or `nil`: no run is faster than the whole way at top speed
    /// (`topSpeed` km/h is `160 × topSpeed ÷ 9` units a second), so every
    /// second from one below that is tried in turn.
    static func leastSeconds(_ length: Int64, _ performance: TrainPerformance) -> Int64? {
        // No curve is built for more than 2⁴⁰ units.
        guard length <= 1 << 40 else { return nil }
        var seconds = max(1, length * 9 / (160 * performance.topSpeed) - 1)
        while seconds <= longestRun {
            if RunningCurve(length: length, duration: seconds * 1000, performance: performance) != nil { return seconds }
            seconds += 1
        }
        return nil
    }

    /// The run `train`'s service sets off on now, from timetable entry
    /// `from` to `to` (stop and cycle each), over `length` units: the
    /// scheduled seconds from leaving to arriving if a curve is built for
    /// them, else the least, else none.
    func setOff(_ train: Train, length: Int64, from: (Int, Int64), to: (Int, Int64)) -> CurveRun? {
        let period = train.period ?? 0
        let leaving = train.timetable[from.0].departure.seconds + from.1 * period
        let arriving = train.timetable[to.0].arrival.seconds + to.1 * period
        return run(train, length: length, scheduled: arriving - leaving)
    }

    /// A run of `length` for `train` from now, in `scheduled` seconds if a
    /// curve is built for them, else in the least there is.
    func run(_ train: Train, length: Int64, scheduled: Int64?) -> CurveRun? {
        if let scheduled, scheduled >= 1, scheduled <= Self.longestRun,
           RunningCurve(length: length, duration: scheduled * 1000, performance: train.performance) != nil {
            return CurveRun(start: clockSeconds, length: length, seconds: scheduled)
        }
        guard let least = Self.leastSeconds(length, train.performance) else { return nil }
        return CurveRun(start: clockSeconds, length: length, seconds: least)
    }

    /// The units left to the end of `train`'s way: from its head along
    /// every edge it can still enter, to where its path stops on the last.
    func wayLeft(_ train: Train) -> Int64 {
        guard case .onEdge(let traversal, let offset)? = train.position else { return 0 }
        var run = Run(traversal)!
        var left = -offset
        var index = train.cursor
        while index < train.edges.count, let next = runs(after: run).first(where: { $0.edge == train.edges[index] }) {
            left += networkEdges[run.edge]!.length
            run = next
            index += 1
        }
        let last = networkEdges[run.edge]!.length
        return left + (index == train.edges.count ? (train.end ?? last) : last)
    }

    /// Whether `train` can go on one unit now.
    func canMove(_ train: Train) -> Bool {
        let moved = steppedOnNetwork(train, distance: 1)
        return moved.position != train.position || moved.cursor != train.cursor
    }

    /// After the second's travel: train `i`'s service, travelling on a run,
    /// drops it when the train has more way left than the curve leaves it
    /// by the second's end (held by a rate of 0 or by missing track).
    mutating func dropIfHeldUp(_ i: Int) {
        guard var service = trains[i].service, !service.waiting, let run = service.run else { return }
        let curve = RunningCurve(length: run.length, duration: run.seconds * 1000, performance: trains[i].performance)!
        let (elapsed, overflow) = (clockSeconds + 1).subtractingReportingOverflow(run.start)
        let along = overflow || elapsed >= run.seconds ? run.length : elapsed <= 0 ? 0 : curve.distance(at: elapsed * 1000)
        if wayLeft(trains[i]) > run.length - along {
            service.run = nil
            trains[i].service = service
        }
    }

    /// Train `i`'s service, travelling: a run over before it arrived is
    /// dropped; without a run, with a rate, able to move and with way left,
    /// it sets off on one over that way, as fast as it can.
    mutating func resume(_ i: Int) {
        guard var service = trains[i].service, !service.waiting else { return }
        if let run = service.run {
            guard clockSeconds >= Self.capped(run.start, run.seconds) else { return }
            service.run = nil
        }
        let train = trains[i]
        if train.rate > 0, canMove(train) {
            let left = wayLeft(train)
            if left > 0 { service.run = run(train, length: left, scheduled: nil) }
        }
        trains[i].service = service
    }

    /// The units train `i` travels in second `second` of the minute: along
    /// its run, its curve's distance at the second's end less at its start
    /// (all of its length from the run's end); otherwise its share of its
    /// rate. Nothing with a rate of 0.
    func travel(_ i: Int, second: Int64) -> Int64 {
        let train = trains[i]
        guard train.rate > 0 else { return 0 }
        guard let service = train.service, !service.waiting, let run = service.run else {
            return Self.share(of: train.rate, inSecond: second)
        }
        let curve = RunningCurve(length: run.length, duration: run.seconds * 1000, performance: train.performance)!
        func along(_ elapsed: Int64) -> Int64 {
            elapsed <= 0 ? 0 : elapsed >= run.seconds ? run.length : curve.distance(at: elapsed * 1000)
        }
        let (elapsed, overflow) = clockSeconds.subtractingReportingOverflow(run.start)
        if overflow || elapsed >= run.seconds { return 0 }
        return along(elapsed + 1) - along(elapsed)
    }
}
