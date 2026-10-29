import GameCore

// The panels' small charts (decision 472): a station's trips by hour with
// its rush hours, each line's riders over its last days with its peak load,
// and the network's fullest sections ranked. Only figures the world already
// keeps: a station keeps today and yesterday only, so it has no trend of
// its own (decision 472's next step). Each chart's numbers, sentences and
// audio graph are worked out here; the app draws them with Swift Charts.

// MARK: - A station's trips by hour

extension StationFlow {
    /// Which way its trips go through the station.
    public enum Direction: CaseIterable, Hashable, Sendable {
        /// Trips that start here.
        case entries
        /// Trips that end here.
        case exits

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .entries: language.text("Entries", "進站")
            case .exits: language.text("Exits", "出站")
            }
        }
    }

    public func hours(_ direction: Direction) -> [Int64] {
        direction == .entries ? entries : exits
    }

    /// The hours of `direction` as bars, people up the axis, for VoiceOver's
    /// audio graph and the chart's labels.
    public func chart(_ direction: Direction, in language: DisplayLanguage) -> ChartSpec {
        let hours = hours(direction)
        var summary = Self.summaryText(of: hours, in: language)
        if let rush = Self.rushText(of: hours, in: language) { summary += " · \(rush)" }
        return ChartSpec(
            title: direction.title(in: language), xTitle: language.text("Hour", "時段"),
            xLabels: (0..<24).map { clockText(minuteOfDay: 60 * $0) },
            axis: .people,
            series: [ChartSeries(name: direction.title(in: language), mark: .bars, values: hours.map { Double($0) })],
            summary: summary, language: language
        )
    }

    /// The rush hours of `hours`: each run of hours with at least two
    /// thirds of the busiest hour's trips, earliest first. None for a day
    /// without trips, or one so even that more than half its hours are
    /// that busy (it has no rush to show).
    public static func rushHours(of hours: [Int64]) -> [ClosedRange<Int>] {
        let peak = hours.max() ?? 0
        guard peak > 0 else { return [] }
        let busy = hours.indices.filter { 3 * hours[$0] >= 2 * peak }
        guard busy.count * 2 <= hours.count else { return [] }
        var runs: [ClosedRange<Int>] = []
        for hour in busy {
            if let last = runs.last, last.upperBound + 1 == hour {
                runs[runs.count - 1] = last.lowerBound...hour
            } else {
                runs.append(hour...hour)
            }
        }
        return runs
    }

    /// "Rush 07:00–09:00, 17:00–19:00"; "尖峰 07:00–09:00、17:00–19:00";
    /// `nil` without rush hours.
    public static func rushText(of hours: [Int64], in language: DisplayLanguage) -> String? {
        let runs = rushHours(of: hours)
        guard !runs.isEmpty else { return nil }
        let spans = runs.map { run in
            "\(clockText(minuteOfDay: 60 * run.lowerBound))–\(run.upperBound == 23 ? "24:00" : clockText(minuteOfDay: 60 * run.upperBound + 60))"
        }
        return language.text("Rush \(spans.joined(separator: ", "))", "尖峰 \(spans.joined(separator: "、"))")
    }
}

// MARK: - A line's riders and load

/// How full a line's fullest train was, for the lines list's bar: the
/// trains' load bar's rule (``TrainLoadInfo``), full at 100% and in the
/// error colour only over it.
public struct LineLoadGauge: Hashable, Sendable {
    public let percent: Int
    /// Whether it is yesterday's (else today's so far).
    public let isYesterday: Bool

    /// How much of the bar is filled, 0…1.
    public var fraction: Double {
        Double(min(100, max(0, percent))) / 100
    }

    /// More rode its fullest train than it is rated for.
    public var isOverload: Bool {
        percent > 100
    }

    /// "Fullest train yesterday 87%"; "昨日最滿 87%".
    public func text(in language: DisplayLanguage) -> String {
        isYesterday
            ? language.text("Fullest train yesterday \(percent)%", "昨日最滿 \(percent)%")
            : language.text("Fullest train today \(percent)%", "今日最滿 \(percent)%")
    }
}

extension LineReport {
    /// Days in each of the two weeks ``ridersChangePercent`` compares.
    public static let trendDays = 7

    /// Riders over the last ``trendDays`` completed days against the
    /// ``trendDays`` before them, as a whole percent change; `nil` with
    /// fewer days kept, or none riding the earlier week.
    public var ridersChangePercent: Int? {
        let week = Self.trendDays
        guard days.count >= 2 * week else { return nil }
        let recent = days.suffix(week).reduce(Int64(0)) { $0 + $1.riders }
        let before = days.dropLast(week).suffix(week).reduce(Int64(0)) { $0 + $1.riders }
        guard before > 0 else { return nil }
        let change = (recent - before) * 100
        // Rounded half away from zero.
        return Int((change + (change < 0 ? -before / 2 : before / 2)) / before)
    }

    /// "Riders up 12% on the week before"; "運量比前一週多 12%"; `nil`
    /// without two weeks to compare.
    public func trendText(in language: DisplayLanguage) -> String? {
        guard let change = ridersChangePercent else { return nil }
        if change > 0 { return language.text("Riders up \(change)% on the week before", "運量比前一週多 \(change)%") }
        if change < 0 { return language.text("Riders down \(-change)% on the week before", "運量比前一週少 \(-change)%") }
        return language.text("Riders level with the week before", "運量和前一週持平")
    }

    /// Riders each completed day, oldest first: the lines list's small
    /// trend line. Empty with fewer than two days (a line needs two points).
    public var sparkline: [Int64] {
        days.count >= 2 ? days.map(\.riders) : []
    }

    /// Its fullest train yesterday, or today so far for a line with no
    /// record of yesterday; `nil` with neither.
    public var loadGauge: LineLoadGauge? {
        if let yesterday { return LineLoadGauge(percent: yesterday.peakLoadPercent, isYesterday: true) }
        return today.map { LineLoadGauge(percent: $0.peakLoadPercent, isYesterday: false) }
    }
}

// MARK: - The network's fullest sections

extension NetworkFlowReport {
    /// Sections the ranking chart shows.
    public static let rankedShown = 8

    /// The fullest sections with trains, fullest first, at most
    /// ``rankedShown``: the busiest page's ranking chart. A section no
    /// train carries has no percent and stays in the list under it.
    public var rankedSections: [SectionRow] {
        Array(sections.filter { $0.percent != nil }.prefix(Self.rankedShown))
    }

    /// The ranking as a chart: each section's fullest hour as a percent of
    /// its seats. Two sections of the same name (two lines' tracks between
    /// the same stations) are told apart by their hour.
    public func rankingChart(in world: GameWorld, language: DisplayLanguage) -> ChartSpec {
        let rows = rankedSections
        var labels: [String] = []
        for row in rows {
            var label = Self.title(of: row, in: world)
            if labels.contains(label) { label += " (\(SectionFlow.hourText(row.hour)))" }
            while labels.contains(label) { label += "′" }
            labels.append(label)
        }
        let overloaded = rows.filter(\.isOverloaded).count
        let summary: String
        if rows.isEmpty {
            summary = language.text("No section carries riders yet.", "還沒有區間載客。")
        } else if overloaded > 0 {
            summary = language.text("\(overloaded) of the \(rows.count) fullest sections carry more than their seats", "最擠的 \(rows.count) 個區間中，\(overloaded) 個超過運能")
        } else {
            summary = language.text("The fullest section is \(rows[0].percent ?? 0)% full", "最擠的區間滿載 \(rows[0].percent ?? 0)%")
        }
        return ChartSpec(
            title: language.text("Fullest sections", "最擠的區間"), xTitle: language.text("Section", "區間"),
            xLabels: labels, axis: .percent,
            series: [ChartSeries(name: language.text("Fullest hour", "最擠時段"), mark: .bars, values: rows.map { $0.percent.map(Double.init) })],
            summary: summary, language: language
        )
    }
}
