import Foundation
@testable import GameCore

/// Decision 844 (TIMETABLE-CHECKUP): a timetabled line played minute by
/// minute, and how each run of one game day went. The deadlock safety
/// net (decisions 577, 836) keeps trains from standing for good, but a
/// run sent late, a run never sent and a peak with a gap in it are not
/// deadlocks: before this, people found them by playing. Four things are
/// measured, each run of the day counted once:
///
/// - **not sent**: the run's last chance (``LineRun/latestDispatch``)
///   passed and no train went (``RunsNotSent``);
/// - **late**: the train it sent left its first stop more than
///   ``RealisticOperation/punctualSeconds`` after the timetable, as the
///   game's punctuality counts a trip late;
/// - **late out of a depot**: of those, the runs whose train had come
///   straight out of a depot for it (its empty run began in one), the
///   morning queue decision 829 §6 names DEPOT-DAWN-QUEUE;
/// - **peak gap**: in the morning and evening peaks, each way from each
///   first stop, how much longer the longest wait between two trains
///   that left was than the longest the timetable has there.
///
/// Departure times are what the run's train was timetabled to leave at
/// when it was sent out (``RunTrip/timetable(_:calling:day:sentOutAt:)``:
/// the run's departure, or a terminal's dwell after the train arrived),
/// read once a tick: at a minute a tick, to the minute.
enum TimetableCheckup {
    /// The peaks the gaps are looked at in, seconds into the day: 07:00
    /// to 09:30 and 17:00 to 19:30.
    static let peaks: [Range<Int64>] = [7 * 3_600 ..< 9 * 3_600 + 1_800, 17 * 3_600 ..< 19 * 3_600 + 1_800]

    /// How one line's runs of the day went.
    struct Result: CustomStringConvertible {
        let line: String
        /// The runs of the day looked at (in the windows, if any).
        var runs = 0
        var notSent: [Int] = []
        /// Seconds late leaving the first stop, by run index, for every
        /// run that was sent.
        var lateness: [Int: Int64] = [:]
        /// Each run's timetabled first departure (clock seconds).
        var starts: [Int: Int64] = [:]
        /// The runs whose train came out of a depot for them.
        var outOfDepot: Set<Int> = []
        /// Runs sent whose train was not found (its departure is then the
        /// minute it was seen sent).
        var unmatched = 0
        /// The worst peak gap: (seconds over the timetable's, the longest
        /// actual gap, the timetable's, where).
        var peakGap: (excess: Int64, actual: Int64, timetabled: Int64, at: String) = (0, 0, 0, "")

        var late: [Int] { lateness.filter { $0.value > GameWorld.punctualSeconds }.map(\.key).sorted() }
        var lateOutOfDepot: [Int] { late.filter(outOfDepot.contains) }
        var worstLate: Int64 { lateness.values.max() ?? 0 }
        var worstOutOfDepot: Int64 { outOfDepot.compactMap { lateness[$0] }.max() ?? 0 }

        var description: String {
            func minutes(_ seconds: Int64) -> String { String(format: "%.1f", Double(seconds) / 60) }
            return "\(line): \(runs) runs, not sent \(notSent.count), late \(late.count) (worst \(minutes(worstLate)) min), "
                + "out of a depot \(outOfDepot.count) (late \(lateOutOfDepot.count), worst \(minutes(worstOutOfDepot)) min), "
                + "peak gap +\(minutes(peakGap.excess)) min (\(minutes(peakGap.actual)) against \(minutes(peakGap.timetabled))\(peakGap.at.isEmpty ? "" : " at \(peakGap.at)"))"
                + (unmatched > 0 ? ", \(unmatched) sent runs' trains not found" : "")
        }
    }

    /// The most a world may show, each line of it summed; a test's
    /// thresholds are `main`'s numbers, so a change that makes any worse
    /// turns it red (late runs with some room, ``overBudget(_:_:)``) and
    /// one that makes them better asks for them to be lowered (the
    /// message says so).
    struct Budget: CustomStringConvertible {
        var notSent = 0
        var late = 0
        var lateOutOfDepot = 0
        /// Minutes, the worst line's.
        var peakGapMinutes = 0

        var description: String {
            "not sent \(notSent), late \(late), late out of a depot \(lateOutOfDepot), peak gap +\(peakGapMinutes) min"
        }
    }

    /// The lines' results summed as a budget, the peak gap the worst line's
    /// (rounded up to the minute).
    static func measured(_ results: [Result]) -> Budget {
        Budget(
            notSent: results.reduce(0) { $0 + $1.notSent.count },
            late: results.reduce(0) { $0 + $1.late.count },
            lateOutOfDepot: results.reduce(0) { $0 + $1.lateOutOfDepot.count },
            peakGapMinutes: Int(((results.map(\.peakGap.excess).max() ?? 0) + 59) / 60)
        )
    }

    /// The figures of `measured` over `budget`, as sentences; empty when
    /// every one is within it.
    static func overBudget(_ measured: Budget, _ budget: Budget) -> [String] {
        var over: [String] = []
        if measured.notSent > budget.notSent { over.append("runs not sent \(measured.notSent) > \(budget.notSent)") }
        // Late runs move with any change to running times, a few at a
        // time, so they have room: 5 %, at least 2 runs. The rest are
        // exact.
        let lateRoom = max(2, budget.late * 5 / 100)
        if measured.late > budget.late + lateRoom { over.append("runs late \(measured.late) > \(budget.late) + \(lateRoom)") }
        if measured.lateOutOfDepot > budget.lateOutOfDepot { over.append("runs late out of a depot \(measured.lateOutOfDepot) > \(budget.lateOutOfDepot)") }
        if measured.peakGapMinutes > budget.peakGapMinutes { over.append("peak gap +\(measured.peakGapMinutes) min > +\(budget.peakGapMinutes)") }
        return over
    }

    /// Plays `world` one tick at a time until every run of game day `day`
    /// has gone or passed its last chance (or until `until`, a clock
    /// second, when given), and tells how the timetabled lines' runs of
    /// that day went. With `windows` (seconds into the day), only the runs
    /// whose first departure falls in one are looked at.
    static func play(_ world: inout GameWorld, day: Int64, windows: [Range<Int64>]? = nil, until: Int64? = nil) throws -> [Result] {
        let timetabled = world.lines.filter(\.hasRuns).map(\.id)
        let base = day * GameTime.secondsPerDay
        func looked(_ run: LineRun) -> Bool {
            guard run.runs(onDay: day), run.fits(onDay: day) else { return false }
            guard let windows else { return true }
            let second = run.start(onDay: day) - base
            return windows.contains { $0.contains(second) }
        }
        var departures: [LineID: [Int: Int64]] = [:]
        var outOfDepot: [LineID: Set<Int>] = [:]
        var unmatched: [LineID: Int] = [:]
        let end = until ?? RunsNotSent.closed(day: day, of: world.lines.filter(\.hasRuns))
        while world.clock.now.seconds < end {
            let before = world.clock.now.seconds
            let sent = Dictionary(uniqueKeysWithValues: timetabled.compactMap { id in world.line(id: id).map { (id, $0.runDays) } })
            // Each train's empty run or service as it stood: where it began
            // and ends.
            var was: [TrainID: (first: StationID, last: StationID)] = [:]
            for train in world.trains {
                if let first = train.timetable.first, let last = train.timetable.last { was[train.id] = (first.station, last.station) }
            }
            try world.advance(ticks: 1)
            for id in timetabled {
                guard let line = world.line(id: id), let old = sent[id] else { continue }
                for index in line.runs.indices where line.runDays[index] == day && old[index] != day && looked(line.runs[index]) {
                    let run = line.runs[index]
                    let first = line.stops[run.calls(stopCount: line.stops.count)[0]]
                    var train: Train?
                    for candidate in line.assignedTrains {
                        guard let found = world.train(id: candidate), let stop = found.timetable.first,
                              stop.station == first, stop.arrival.seconds >= before else { continue }
                        train = found
                        break
                    }
                    guard let train, let stop = train.timetable.first else {
                        unmatched[id, default: 0] += 1
                        departures[id, default: [:]][index] = world.clock.now.seconds
                        continue
                    }
                    departures[id, default: [:]][index] = stop.departure.seconds
                    if let earlier = was[train.id], earlier.last == first, world.station(id: earlier.first)?.isDepot == true {
                        outOfDepot[id, default: []].insert(index)
                    }
                }
            }
        }
        return timetabled.compactMap { id -> Result? in
            guard let line = world.line(id: id) else { return nil }
            var result = Result(line: line.name)
            let indices = line.runs.indices.filter { looked(line.runs[$0]) }
            result.runs = indices.count
            let wanted = Set(indices)
            result.notSent = RunsNotSent.on(day, of: line, at: world.clock.now).filter(wanted.contains)
            let left = departures[id] ?? [:]
            for (index, departure) in left {
                result.lateness[index] = max(0, departure - line.runs[index].start(onDay: day))
                result.starts[index] = line.runs[index].start(onDay: day)
            }
            result.outOfDepot = outOfDepot[id] ?? []
            result.unmatched = unmatched[id] ?? 0
            // The peaks: each way from each first stop.
            var groups: [String: [Int]] = [:]
            for index in indices {
                let run = line.runs[index]
                let second = run.start(onDay: day) - base
                guard let peak = peaks.firstIndex(where: { $0.contains(second) }) else { continue }
                groups["\(peak) \(run.calls(stopCount: line.stops.count)[0]) \(run.isOutbound)", default: []].append(index)
            }
            for (_, group) in groups where group.count > 2 {
                let timetabled = group.map { line.runs[$0].start(onDay: day) }.sorted()
                let actual = group.compactMap { left[$0] }.sorted()
                func longest(_ times: [Int64]) -> Int64 { zip(times, times.dropFirst()).map { $1 - $0 }.max() ?? 0 }
                let planned = longest(timetabled)
                // A peak whose every run was missed but one has no gap to
                // read: its runs are counted as not sent.
                guard actual.count > 1 else { continue }
                let worst = longest(actual)
                // Where the longest gap ended.
                if worst - planned > result.peakGap.excess || result.peakGap.at.isEmpty {
                    let after = zip(actual, actual.dropFirst()).first { $1 - $0 == worst }?.1 ?? 0
                    let name = world.station(id: line.stops[line.runs[group[0]].calls(stopCount: line.stops.count)[0]])?.name ?? "?"
                    let minute = (after - base) / 60
                    result.peakGap = (max(0, worst - planned), worst, planned, name + String(format: " %02d:%02d", minute / 60, minute % 60))
                }
            }
            return result
        }
    }
}
