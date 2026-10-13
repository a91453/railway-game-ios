// Realistic operation, first stage (ARCHITECTURE decision 207). Measured
// against the real timetables, the game's trains ran 0.72 to 0.78 times the
// real time on the high-speed line (docs/research/NEXT_PRIORITIES_2026-10-12.md
// §9.2): every leg was planned at its least time, a high-speed line's at the
// reference's fallback rates (`aAlt` 2.0, `bAlt` 2.7 km/h/s, which its
// `assignRunProfiles` takes only when a timetable is too tight), and every
// line dwelt one minute. A late train never made up time on the way: its
// run took the timetable's time from the scheduled departure, so it arrived
// as late as it left.
//
// With the world's ``GameWorld/realisticOperation`` on:
//
// 1. a leg is planned at the performance's usual rates (``usualRates``);
// 2. its time has a recovery margin of ``recoveryMarginPercent``, and a
//    train sets off on a curve for the time left to its scheduled arrival,
//    never less than the least its performance (fallback rates and all)
//    takes, so a late train makes the margin up;
// 3. a line dwells ``ServiceLine/dwellSeconds`` at a stop between its
//    ends, or by its kind: ``highSpeedDwellSeconds`` on a high-speed line,
//    ``defaultDwellSeconds`` on any other;
// 4. each passenger line counts its trips and the late ones (``LineTally``).
//
// Missing key is off: GameCore's new world, old saves, the demos, the
// challenges and the tutorial plan, run and count as before. A dwell a line
// sets is kept either way (it is 60 s for every line that sets none).

extension TrainPerformance {
    /// This performance without its fallback rates (decision 207): the
    /// rates a realistic timetable is planned at. The fallbacks stay a
    /// running train's, for when it is late.
    public var usualRates: TrainPerformance {
        TrainPerformance(acceleration: acceleration, braking: braking, topSpeed: topSpeed, coast: coast)
    }
}

extension ServiceLine {
    /// The dwells a line may set (decision 207).
    public static let dwellRange: ClosedRange<Int64> = ServiceDwell.minimum...maximumDwellSeconds
}

extension GameWorld {
    /// A line's dwell at a stop between its ends without one of its own
    /// (decision 207): one minute, as every line dwelt before it.
    public static let defaultDwellSeconds: Int64 = ServiceLine.dwellMinutes * GameTime.secondsPerMinute
    /// A high-speed line's dwell with realistic operation and none of its
    /// own (decision 207): the real all-stops trains' 108.9 s on average
    /// (the bundled `thsr-schedule.json`, 32 trains), to the nearest ten.
    public static let highSpeedDwellSeconds: Int64 = 110
    /// The recovery margin of a realistic leg, in percent of its least time
    /// at the usual rates, rounded up to a whole second (decision 207):
    /// real timetables keep 3 to 8 %.
    public static let recoveryMarginPercent: Int64 = 4
    /// How late a trip may reach its last call and still be on time
    /// (decision 207): the reference's 5 minutes (`delay-stats.json`,
    /// `final_delay ≤ 5`, Taiwan Railway's and the high-speed line's own
    /// rule).
    public static let punctualSeconds: Int64 = 5 * GameTime.secondsPerMinute

    /// Turns realistic operation on or off (decision 207). A train already
    /// on its way keeps its timetable; the next one a line sends out is
    /// planned the new way.
    public mutating func setRealisticOperation(_ enabled: Bool) {
        guard enabled != realisticOperation else { return }
        realisticOperation = enabled
        passengerPlan = PassengerPlanCache()
        passengerRouteMemo = PassengerRouteMemo()
        routeMemo = RouteMemo()
    }

    /// Seconds `line`'s trains stay at a stop between its ends (decision
    /// 207): its own dwell, or else ``highSpeedDwellSeconds`` for a
    /// high-speed line with realistic operation, or
    /// ``defaultDwellSeconds``.
    public func dwellSeconds(of line: ServiceLine) -> Int64 {
        if let own = line.dwellSeconds { return own }
        return realisticOperation && line.isHighSpeed ? Self.highSpeedDwellSeconds : Self.defaultDwellSeconds
    }

    /// Seconds `line`'s trains stay at either end, where they turn round:
    /// two minutes, or its dwell at a stop if that is longer.
    func terminalDwellSeconds(of line: ServiceLine) -> Int64 {
        max(ServiceLine.terminalDwellMinutes * GameTime.secondsPerMinute, dwellSeconds(of: line))
    }

    /// The whole seconds `line` plans a leg of `length` world units to take
    /// (`length >= 1`), or `nil` when its performance builds no curve for
    /// it: the least in which it builds one (Stage W2c); with realistic
    /// operation (decision 207) the least at its usual rates, and
    /// ``recoveryMarginPercent`` more.
    func plannedSeconds(length: Int64, line: ServiceLine) -> Int64? {
        guard realisticOperation else { return RunningCurve.leastSeconds(length: length, performance: line.performance) }
        guard let least = RunningCurve.leastSeconds(length: length, performance: line.performance.usualRates) else { return nil }
        let margin = (least * Self.recoveryMarginPercent + 99) / 100
        return min(least + margin, RunningCurve.maximumSeconds)
    }

    /// The seconds a train travelling to stop `stop` of `cycle` has left to
    /// its scheduled arrival there (decision 207), at least 1: the time a
    /// realistic run is fitted to, so a late train makes up its margin.
    func secondsToScheduledArrival(of train: Train, stop: Int, cycle: Int64) -> Int64 {
        let (left, overflow) = train.scheduledArrival(of: stop, cycle: cycle).seconds.subtractingReportingOverflow(clock.now.seconds)
        return overflow ? 1 : max(1, left)
    }
}
