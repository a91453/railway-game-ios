@testable import GameCore

/// MISSRUN: which runs of a timetabled line (decision 133) sent no train
/// on a day. A run belongs to the day its timetable starts, so one listed
/// at 24:14 leaves after the next midnight; it is counted only once its
/// last chance to go, ``LineRun/latestDispatch`` after its first
/// departure, has passed. Counting at that midnight called the day's
/// after-midnight runs missed, although they went a few minutes later.
enum RunsNotSent {
    /// The indices of `line`'s runs that run on game day `day`, have
    /// passed their last chance by `now`, and sent no train for it.
    static func on(_ day: Int64, of line: ServiceLine, at now: GameTime) -> [Int] {
        line.runs.indices.filter { index in
            let run = line.runs[index]
            return run.runs(onDay: day) && run.start(onDay: day) + LineRun.latestDispatch < now.seconds
                && (line.runDays[index] ?? -1) < day
        }
    }

    /// The first second by which every run of `lines` on game day `day`
    /// has gone or passed its last chance.
    static func closed(day: Int64, of lines: [ServiceLine]) -> Int64 {
        let last = lines.flatMap(\.runs).map { $0.start(onDay: day) }.max() ?? day * GameTime.secondsPerDay
        return max((day + 1) * GameTime.secondsPerDay, last + LineRun.latestDispatch + 1)
    }
}
