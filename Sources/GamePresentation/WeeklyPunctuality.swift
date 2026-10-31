import GameCore

// A line's punctuality over its last seven settled days, beside Taiwan
// Railway's over a real year (NEXT_PRIORITIES §22.17, first card;
// docs/research/TRA_DELAY_ANALYSIS_2026-10-27.md §4.4, PR 1).
//
// Only adds up what the line accounts already keep (decision 207's
// ``LineTally/trips`` and ``LineTally/lateTrips``, counted with realistic
// operation): nothing is kept in the world. A trip is on time when it
// reaches its last call no more than ``GameWorld/punctualSeconds`` (five
// minutes) late, the same rule as Taiwan Railway's ("延遲 5 分鐘以內仍可列為
// 準點", judged at the end of the run).
//
// Taiwan Railway's figure is 92.92 % of 261,820 trips between 2025-11-20
// and 2026-10-26, from TDX's train delay reports (the owner's reference,
// `Railway/tdx-snapshot-2026-10/`, `TRA_LiveTrainDelay_*.jsonl.gz`; licence
// and credit in its `DATA_USE_NOTICES.json`: Open Government Data License,
// version 1.0, 「資料來源：交通部運輸資料流通服務平臺（TDX）」), worked out by
// `tools/tra-delay-analysis/analyze.py` (`results/final_by_all.csv`).

/// Taiwan Railway's real punctuality over a year, for comparison.
public enum TaiwanRailwayPunctuality {
    /// Trips no more than five minutes late at their last reporting
    /// station, in thousandths, rounded: 92.92 %.
    public static let pastYearPermille: Int64 = 929
    /// The trips it is counted from.
    public static let pastYearTrips: Int64 = 261_820
}

/// A line's trips on time over its last ``days`` settled days.
public struct WeeklyPunctuality: Hashable, Sendable {
    /// The settled days added up.
    public static let days: Int64 = 7
    /// Fewer finished trips than this show nothing: a handful of trips
    /// makes a percentage that jumps (the same as satisfaction's,
    /// ``LineSatisfaction/minimumTrips``).
    public static let minimumTrips: Int64 = LineSatisfaction.minimumTrips

    public let trips: Int64
    public let lateTrips: Int64

    /// The days of `records` from `settledDay − days` up to but not
    /// including `settledDay` (the first day not yet settled, decision
    /// 194's ``GameWorld/lineLossSettledDay``), or `nil` with fewer than
    /// ``minimumTrips`` trips finished over them.
    public init?(records: [LineDay], settledDay: Int64) {
        let week = records.filter { $0.day < settledDay && $0.day >= settledDay - Self.days }
        let trips = week.reduce(Int64(0)) { $0 + $1.tally.trips }
        guard trips >= Self.minimumTrips else { return nil }
        self.trips = trips
        self.lateTrips = min(week.reduce(Int64(0)) { $0 + $1.tally.lateTrips }, trips)
    }

    /// The trips on time, in thousandths.
    public var permille: Int64 {
        (trips - lateTrips) * 1_000 / trips
    }

    /// "On time, last 7 days: 93% (Taiwan Railway, past year: 93%)".
    public func text(in language: DisplayLanguage) -> String {
        let percent = "\(permille / 10)%"
        let real = "\((TaiwanRailwayPunctuality.pastYearPermille + 5) / 10)%"
        return language.text(
            "On time, last \(Self.days) days: \(percent) (Taiwan Railway, past year: \(real))",
            "最近 \(Self.days) 天準點率 \(percent)（台鐵近一年 \(real)）"
        )
    }
}

extension GameWorld {
    /// Line `id`'s punctuality over its last seven settled days, or `nil`
    /// for a freight line, no such line, a world without line accounts or
    /// realistic operation, or fewer than ``WeeklyPunctuality/minimumTrips``
    /// trips finished.
    public func lineWeeklyPunctuality(_ id: LineID) -> WeeklyPunctuality? {
        guard realisticOperation, lineAccounts != nil, let line = line(id: id), !line.isFreight else { return nil }
        return WeeklyPunctuality(records: lineDays(id), settledDay: lineLossSettledDay)
    }
}
