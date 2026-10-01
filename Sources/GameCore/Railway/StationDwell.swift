// Station dwell (G1b, ARCHITECTURE decision 35): every dwell rule of the
// owner's two references, ported as pure integer arithmetic, so that W2 can
// put "arrive → doors open → passengers → doors close → depart" on the
// game's clock with them. Nothing here is wired into `advance(ticks:)`
// yet: until W2, boarding happens at once as a train leaves a stop (see
// `Boarding.swift`), a transitional rule these replace.
//
// Sources:
//
// - `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js` (the metro game):
//   `DWELL_GAME_SEC`, `DWELL_TERMINAL_GAME_SEC`, `_advanceTrainOneStep`,
//   `metroHeadwayRoundTripMinutes`, the HSR stop minutes
//   (`hsrRuntimeBuildTimeline`, the real-world import and its estimate), and
//   the dead `PARAMS.BOARDING_RATE` and `PARAMS.TRAIN_DWELL_TIME`;
// - `Ci/reference_snapshot/dist/bootstrap-lazy__q_1d19ebbdad3f59c3.js`: the
//   door phases of a dwell;
// - `Railway/site_archive_clean/index.html` (the live map): `DWELL_SEC`,
//   `buildLineSchedule`, `trtcOfficialDwellAt`, `trtcOfficialCoastCycle`,
//   the observed line dwell (`trtcBrVehiclesFromBoard`), `retimeLoopTrains`
//   and `HSR_DEP_MID_SEC`.
//
// Times are in tenths of a second unless a name says minutes: the
// references use fractional seconds (8.3 s, 10.2 s, half a cycle), and
// tenths hold every one of them exactly. No rule in either reference
// makes a dwell depend on how many passengers board or alight, or on
// doors: see `StationDwell.referenceBoardingRate`.

/// The dwell rules of the references, as pure functions.
public enum StationDwell {
    /// Tenths of a second in a second.
    public static let tenthsPerSecond: Int64 = 10

    // MARK: - Ci metro game

    /// A metro train's dwell at a stop between its terminals: 36 game
    /// seconds (`DWELL_GAME_SEC`).
    public static let metroDwell: Int64 = 360
    /// A metro train's dwell at a terminal of its route leg, where it turns
    /// round: 42 game seconds (`DWELL_TERMINAL_GAME_SEC`).
    public static let metroTerminalDwell: Int64 = 420

    /// The dwell a metro train starts as it arrives at a stop
    /// (`_advanceTrainOneStep`): none at a station closed to it (it runs
    /// through), ``metroDwell`` on a ring line (which has no terminal) and
    /// between terminals, ``metroTerminalDwell`` at the terminal it is
    /// arriving at.
    public static func metroDwell(isServed: Bool, isRing: Bool, isTerminal: Bool) -> Int64 {
        guard isServed else { return 0 }
        return !isRing && isTerminal ? metroTerminalDwell : metroDwell
    }

    /// The dwell left after a step of `step` (the reference's
    /// `max(0, remain − step)`); the train may leave once it is 0, when the
    /// track ahead is clear (`metroSharedTrackHeadwayClearance`). A step
    /// never carries time past the departure: the reference ends the
    /// train's frame there.
    public static func remainingDwell(_ remaining: Int64, after step: Int64) -> Int64 {
        max(0, max(0, remaining) - max(0, step))
    }

    /// A metro line's round trip (`metroHeadwayRoundTripMinutes`, before
    /// its division by 60): on a line that runs out and back,
    /// `2 × travel + 2 × (stops − 2) × metroDwell + 2 × metroTerminalDwell`,
    /// `travel` being the running time from the first to the last stop; on
    /// a ring, `travel + stops × metroDwell`, `travel` including the leg
    /// back to the first stop. `nil` for fewer than two stops.
    public static func metroRoundTrip(travel: Int64, stops: Int, isRing: Bool) -> Int64? {
        guard stops >= 2 else { return nil }
        if isRing { return travel + Int64(stops) * metroDwell }
        return 2 * travel + 2 * Int64(stops - 2) * metroDwell + 2 * metroTerminalDwell
    }

    /// What a dwell is doing (`bootstrap-lazy`'s platform and cabin
    /// phases): the doors opening, passengers boarding, or the doors
    /// closing.
    public enum DoorPhase: String, CaseIterable, Sendable {
        case opening, boarding, closing
    }

    /// Metro doors take 8 s to open and start closing 8.3 s before the
    /// dwell ends; high-speed doors 7 s and 9 s.
    public static let metroDoorOpening: Int64 = 80
    public static let metroDoorClosing: Int64 = 83
    public static let highSpeedDoorOpening: Int64 = 70
    public static let highSpeedDoorClosing: Int64 = 90

    /// The door phase with `remaining` of a dwell of `total` left (the
    /// reference's `Bt` for a metro and `Ta` for a high-speed train):
    /// opening until `opening` has passed, then closing once `closing` or
    /// less is left, boarding in between.
    /// As in the reference, the total is at least a second and the time
    /// left is clamped to `0...total`.
    public static func doorPhase(total: Int64, remaining: Int64, opening: Int64, closing: Int64) -> DoorPhase {
        let total = max(tenthsPerSecond, total)
        let remaining = min(max(0, remaining), total)
        if total - remaining < opening { return .opening }
        return remaining <= closing ? .closing : .boarding
    }

    /// The doors of a metro train start closing, with their warning, this
    /// long before it leaves, in real time (`METRO_TRAIN_DOOR_CLOSE_REAL_SEC`,
    /// 10.2 s): at a game speed of `speed` times real time, `speed` times
    /// as much game time (at least once).
    public static func metroDoorCloseWarning(speed: Int64) -> Int64 {
        102 * max(1, speed)
    }

    /// `PARAMS.BOARDING_RATE`: 2, without a unit. The reference defines it
    /// and never reads it; no formula of either reference turns passengers
    /// into seconds. Kept so that W2 has the reference's value, not as a
    /// rule.
    public static let referenceBoardingRate: Int64 = 2
    /// `PARAMS.TRAIN_DWELL_TIME`: 44 s. Defined in the reference and never
    /// read (the dwell it uses is ``metroDwell``).
    public static let referenceTrainDwellTime: Int64 = 440

    // MARK: - Ci high-speed timetables

    /// A high-speed stop's dwell in minutes from its arrival and departure
    /// minutes (`hsrRuntimeBuildTimeline` and the stop editor): the
    /// departure less the arrival, a day later while that is negative.
    public static func stopMinutes(arrival: Int64, departure: Int64) -> Int64 {
        let gap = (departure - arrival) % GameTime.minutesPerDay
        return gap < 0 ? gap + GameTime.minutesPerDay : gap
    }

    /// A stop's dwell in minutes as a real timetable is imported (the
    /// real-world import): 0 at the first and last stop, otherwise
    /// `max(0, (departure − arrival + 1440) % 1440)`, with the truncating
    /// remainder of the reference (the same as ``stopMinutes(arrival:departure:)``
    /// for minutes of one day).
    public static func importedStopMinutes(arrival: Int64, departure: Int64, isEndpoint: Bool) -> Int64 {
        isEndpoint ? 0 : max(0, (departure - arrival + GameTime.minutesPerDay) % GameTime.minutesPerDay)
    }

    /// The dwell a timetable without one implies (the real-world import's
    /// estimate): the listed duration of the leg, less the minutes from the
    /// departure to the next arrival (modulo a day); kept, and marked as an
    /// estimate, only if it is 1 to 60 minutes.
    public static func estimatedStopMinutes(listedDuration: Int64, departure: Int64, nextArrival: Int64) -> Int64? {
        let dwell = listedDuration - (nextArrival - departure + GameTime.minutesPerDay) % GameTime.minutesPerDay
        return (1...60).contains(dwell) ? dwell : nil
    }

    /// A stop inserted into a high-speed service dwells 2 minutes
    /// (`stopMin: 2`).
    public static let insertedStopMinutes: Int64 = 2

    // MARK: - Railway live map

    /// A station's dwell when the data gives none (`DWELL_SEC` and
    /// `TRTC_OFFICIAL_COAST_DWELL_SEC`): 25 s.
    public static let defaultDwell: Int64 = 250
    /// The least dwell of a train coasting on its cycle
    /// (`TRTC_OFFICIAL_COAST_DWELL_MIN_SEC`): 15 s.
    public static let minimumCoastDwell: Int64 = 150
    /// A line's dwell when too few observations give one
    /// (`TRTC_BR_DWELL_FALLBACK`): 29 s.
    public static let observedDwellFallback: Int64 = 290

    /// A station's dwell (`trtcOfficialDwellAt`): its own, else the line's
    /// for it, else ``defaultDwell``; a value that is not positive counts
    /// as none.
    public static func stationDwell(own: Int64?, line: Int64?) -> Int64 {
        if let own, own > 0 { return own }
        if let line, line > 0 { return line }
        return defaultDwell
    }

    /// A train coasting on its cycle (`trtcOfficialCoastCycle`): the cycle
    /// is the one given, else the gap between its last two arrivals, else
    /// the run plus ``defaultDwell`` (each only if positive); the dwell is
    /// the cycle less the run, at least ``minimumCoastDwell`` and at most
    /// half the cycle; the rest is travel.
    public static func coastCycle(given: Int64?, lastArrivalGap: Int64?, run: Int64) -> (cycle: Int64, dwell: Int64, travel: Int64) {
        let cycle = if let given, given > 0 {
            given
        } else if let lastArrivalGap, lastArrivalGap > 0 {
            lastArrivalGap
        } else {
            run + defaultDwell
        }
        // Half a cycle of whole seconds is a whole number of tenths, as
        // the reference's `cycle / 2` is exact; a cycle in odd tenths
        // rounds its half down to a tenth.
        let dwell = min(max(cycle - run, minimumCoastDwell), cycle / 2)
        return (cycle, dwell, cycle - dwell)
    }

    /// A line's periodic timetable (`buildLineSchedule`): from the first
    /// station to the last and back to the first (on a loop, once round
    /// back to the first), each station's arrival and departure from the
    /// period's start and the period. `runs[i]` is the running time from
    /// station `i` to `i + 1` (on a loop also from the last back to the
    /// first); `dwells[i]` the station's dwell, ``defaultDwell`` where it
    /// is `nil` or not positive. The first station dwells at both ends of
    /// the period, so it turns round with twice its dwell.
    ///
    /// - Precondition: at least two stations, and one run per gap.
    public static func periodicTimetable(dwells: [Int64?], runs: [Int64], isLoop: Bool) -> (calls: [(station: Int, arrival: Int64, departure: Int64)], period: Int64) {
        let count = dwells.count
        precondition(count >= 2 && runs.count == (isLoop ? count : count - 1))
        let sequence = isLoop ? Array(0..<count) + [0] : Array(0..<count) + (0..<count - 1).reversed()
        var calls: [(station: Int, arrival: Int64, departure: Int64)] = []
        var time: Int64 = 0
        for (index, station) in sequence.enumerated() {
            if index > 0 {
                let gap = isLoop || index <= count - 1 ? index - 1 : 2 * (count - 1) - index
                time += runs[gap]
            }
            let dwell = dwells[station].flatMap { $0 > 0 ? $0 : nil } ?? defaultDwell
            calls.append((station, time, time + dwell))
            time += dwell
        }
        return (calls, time)
    }

    /// A line's dwell observed from the countdown boards (the TRTC
    /// census): each hop between adjacent stations gives one sample, the
    /// gap between the boards' arrivals less the running time. With 8
    /// samples or more their median (the upper one of an even count) is
    /// the line's dwell if it is plausible: between 0 and 180 s
    /// exclusive when the line has running times, otherwise when the first
    /// hop's run plus it is 40 to 240 s. `nil` otherwise: the line keeps
    /// what it had, or ``observedDwellFallback``.
    public static func observedLineDwell(samples: [Int64], hasRunningTimes: Bool, firstRun: Int64) -> Int64? {
        guard samples.count >= 8 else { return nil }
        let median = samples.sorted()[samples.count / 2]
        let plausible = hasRunningTimes ? median > 0 && median < 1_800 : (400...2_400).contains(firstRun + median)
        return plausible ? median : nil
    }

    /// The round-the-island loop trains (`retimeLoopTrains`): they leave at
    /// 08:00 (`LOOP_DEP`) and take 12 hours (`LOOP_SEC`), dwelling 120 s
    /// (`LOOP_DWELL`) at the start and at every stop between the ends; the
    /// rest of the 12 hours is shared among the legs by length. Each
    /// arrival is the previous departure plus the leg's share rounded half
    /// up to a whole second, as the reference's `Math.round`; the last
    /// arrives exactly 12 hours after the first.
    public static let loopDeparture: Int64 = 288_000
    public static let loopDuration: Int64 = 432_000
    public static let loopDwell: Int64 = 1_200

    /// See ``loopDeparture``. `lengths[i]` is the leg from stop `i` to
    /// `i + 1`, in any unit; `stops[i]` whether stop `i` is a stop (the
    /// first and last always are).
    ///
    /// - Precondition: one more stop than legs, at least one leg, and a
    ///   positive total length.
    public static func loopTimetable(lengths: [Int64], stops: [Bool]) -> [(arrival: Int64, departure: Int64)] {
        let total = lengths.reduce(0, +)
        precondition(!lengths.isEmpty && stops.count == lengths.count + 1 && total > 0)
        let last = stops.count - 1
        let dwellingStops = (1..<last).count { stops[$0] }
        let travel = loopDuration - Int64(dwellingStops + 1) * loopDwell
        var times = [(arrival: loopDeparture, departure: loopDeparture + loopDwell)]
        for index in 1...last {
            // round(departure + share) in seconds for a departure of whole
            // seconds: the share rounded half up to a second.
            let seconds = (2 * lengths[index - 1] * (travel / tenthsPerSecond) + total) / (2 * total)
            let arrival = times[index - 1].departure + seconds * tenthsPerSecond
            times.append((arrival, arrival + (index < last && stops[index] ? loopDwell : 0)))
        }
        times[last] = (loopDeparture + loopDuration, loopDeparture + loopDuration)
        return times
    }

    /// High-speed departures in the minute-granular data leave at the
    /// middle of their minute (`HSR_DEP_MID_SEC`): 30 s after the listed
    /// minute at every stop but the last.
    public static let highSpeedDepartureOffset: Int64 = 300
}
