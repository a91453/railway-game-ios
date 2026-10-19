import GameCore

// The per-line operating report (ARCHITECTURE decision 179): what each line
// carried, took in and cost yesterday and over its last 30 days, read from
// ``GameWorld/lineAccounts``. The reference's line report does the same
// (`flowDashboardReadLineOperatingDayFlow`, `flowDashboardGetLineBarRows`
// and `flowDashboardSortStationCards`: a bar per line with its day's
// riders, sorted by a chosen key). Nothing here is kept.

/// How the lines (and the trains) are ordered in their lists.
public enum LineReportSort: String, CaseIterable, Hashable, Sendable {
    /// Most profit first: the money losers last.
    case profit
    /// Most riders yesterday first.
    case ridership
    /// Fullest train first.
    case load
    case name

    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .profit: language.text("Profit", "損益")
        case .ridership: language.text("Riders", "運量")
        case .load: language.text("Load", "滿載率")
        case .name: language.text("Name", "名稱")
        }
    }
}

/// One day of a line's report: money in cents.
public struct LineOperatingDay: Hashable, Identifiable, Sendable {
    public let day: Int64
    public let riders: Int64
    public let fareRevenue: Money
    public let cost: Money
    /// The fullest a train was as it left a stop, in whole percent.
    public let peakLoadPercent: Int
    public let trainDistance: Int64

    public var id: Int64 { day }

    /// Fares less the line's own running costs.
    public var profit: Money {
        fareRevenue - cost
    }

    init(_ record: LineDay) {
        day = record.day
        riders = record.tally.boardings
        fareRevenue = record.tally.fareRevenue
        cost = record.tally.totalCost
        peakLoadPercent = Int((record.tally.peakLoad + 5) / 10)
        trainDistance = record.tally.trainDistance
    }
}

/// A line's report.
public struct LineReport: Hashable, Identifiable, Sendable {
    public let line: LineID
    public let name: String
    /// The current day's completed hourly settlements; excludes pending
    /// activity and expenses posted only at the end of the day.
    public let today: LineOperatingDay?
    /// The day before the clock's, or `nil` with no record of it.
    public let yesterday: LineOperatingDay?
    /// The completed days kept, oldest first (the day in progress is left
    /// out: half a day would read as a slump).
    public let days: [LineOperatingDay]

    public var id: LineID { line }

    public var totalFares: Money { days.reduce(.zero) { $0 + $1.fareRevenue } }
    public var totalCost: Money { days.reduce(.zero) { $0 + $1.cost } }
    public var totalProfit: Money { totalFares - totalCost }
    public var totalRiders: Int64 { days.reduce(0) { $0 + $1.riders } }

    /// Cost as a whole percent of fares over the days kept (the Japanese
    /// railways' 営業係数, 營業比): 100 breaks even, more loses; `nil`
    /// before any fares.
    public var operatingRatioPercent: Int? {
        let fares = totalFares.amount
        guard fares > 0 else { return nil }
        return Int((totalCost.amount * 100 + fares / 2) / fares)
    }

    /// "Yesterday 12,340 riders · fares $ 61,700 · profit $ -4,200 · peak
    /// 87%": the line's row in the lines list.
    public func rowText(in language: DisplayLanguage) -> String {
        guard let yesterday else {
            // A new line has no "yesterday" yet. The hourly accounts can
            // already tell the player whether its first trains carried
            // anyone; avoid provisional profit because daily staff and
            // energy costs have not been posted yet.
            guard let today else {
                return language.text("No record of yesterday yet", "昨日還沒有紀錄")
            }
            return language.joined([
                language.text("Today so far (through last hour): \(Money(today.riders).displayText) riders", "今日（截至上個整點）\(Money(today.riders).displayText) 人次"),
                language.text("fares \(today.fareRevenue.moneyText)", "票收 \(today.fareRevenue.moneyText)"),
                language.text("peak \(today.peakLoadPercent)%", "尖峰 \(today.peakLoadPercent)%"),
            ])
        }
        return language.joined([
            language.text("Yesterday \(Money(yesterday.riders).displayText) riders", "昨日 \(Money(yesterday.riders).displayText) 人次"),
            language.text("fares \(yesterday.fareRevenue.moneyText)", "票收 \(yesterday.fareRevenue.moneyText)"),
            language.text("profit \(yesterday.profit.moneyText)", "損益 \(yesterday.profit.moneyText)"),
            language.text("peak \(yesterday.peakLoadPercent)%", "尖峰 \(yesterday.peakLoadPercent)%"),
        ])
    }

    /// The totals over the days kept, on one line (also what VoiceOver
    /// reads for the charts).
    public func summaryText(in language: DisplayLanguage) -> String {
        guard !days.isEmpty else { return language.text("No days recorded yet.", "還沒有每日紀錄。") }
        var parts = [
            language.text("Last \(days.count) days", "最近 \(days.count) 天"),
            language.text("\(Money(totalRiders).displayText) riders", "\(Money(totalRiders).displayText) 人次"),
            language.text("fares \(totalFares.moneyText)", "票收 \(totalFares.moneyText)"),
            language.text("cost \(totalCost.moneyText)", "成本 \(totalCost.moneyText)"),
            language.text("profit \(totalProfit.moneyText)", "損益 \(totalProfit.moneyText)"),
        ]
        if let ratio = operatingRatioPercent {
            parts.append(language.text("operating ratio \(ratio)%", "營業比 \(ratio)%"))
        }
        return language.joined(parts)
    }

    /// A tapped day's numbers, on one line.
    public func dayText(_ day: LineOperatingDay, in language: DisplayLanguage) -> String {
        language.joined([
            language.text("Day \(day.day + 1)", "第 \(day.day + 1) 天"),
            language.text("\(Money(day.riders).displayText) riders", "\(Money(day.riders).displayText) 人次"),
            language.text("fares \(day.fareRevenue.moneyText)", "票收 \(day.fareRevenue.moneyText)"),
            language.text("cost \(day.cost.moneyText)", "成本 \(day.cost.moneyText)"),
            language.text("profit \(day.profit.moneyText)", "損益 \(day.profit.moneyText)"),
            language.text("peak \(day.peakLoadPercent)%", "尖峰 \(day.peakLoadPercent)%"),
        ])
    }
}

extension DisplayLanguage {
    fileprivate func joined(_ parts: [String]) -> String {
        parts.joined(separator: " · ")
    }
}

extension GameWorld {
    /// The report of line `id`, or `nil` for a world without line accounts
    /// or no such line.
    public func lineReport(_ id: LineID) -> LineReport? {
        guard lineAccounts != nil, let line = line(id: id) else { return nil }
        let today = FinanceHistory.floorDay(clock.now)
        let lineDays = lineDays(id)
        let days = lineDays.filter { $0.day < today }.map(LineOperatingDay.init)
        let current = lineDays.first { $0.day == today }.map(LineOperatingDay.init)
        return LineReport(line: id, name: line.name, today: current, yesterday: days.first { $0.day == today - 1 }, days: days)
    }

    /// Every line's report, in `order`; empty without line accounts.
    public func lineReports(sortedBy order: LineReportSort = .name) -> [LineReport] {
        let reports = lines.compactMap { lineReport($0.id) }
        switch order {
        case .name:
            return reports.sorted { ($0.name, $0.line) < ($1.name, $1.line) }
        case .profit:
            return reports.sorted { Self.ranks($0, before: $1) { $0.profit.amount } }
        case .ridership:
            return reports.sorted { Self.ranks($0, before: $1) { $0.riders } }
        case .load:
            return reports.sorted { Self.ranks($0, before: $1) { Int64($0.peakLoadPercent) } }
        }
    }

    /// Whether `report` comes before `other` in a sort that puts the
    /// biggest figure of yesterday first; a line with no record of it goes
    /// last, and ties go by line.
    private static func ranks(_ report: LineReport, before other: LineReport, by value: (LineOperatingDay) -> Int64) -> Bool {
        switch (report.yesterday.map(value), other.yesterday.map(value)) {
        case (let left?, let right?) where left != right: return left > right
        case (nil, _?): return false
        case (_?, nil): return true
        default: return report.line < other.line
        }
    }

    /// Whether line `id` lost money on each of the last
    /// ``losingDays`` completed days (decision 179): the map's bubble. Not
    /// for a line with no trains (decision 179, later): it says that, the
    /// cause the player can act on, and its stations cost what they cost.
    public func lineLosingMoney(_ id: LineID) -> Bool {
        guard let line = line(id: id), !line.isFreight,
              !(line.trains.isEmpty && line.patterns.allSatisfy({ $0.trains.isEmpty })),
              let report = lineReport(id)
        else { return false }
        let today = FinanceHistory.floorDay(clock.now)
        let last = (1...Self.losingDays).map { today - Int64($0) }
        return last.allSatisfy { day in
            guard let record = report.days.first(where: { $0.day == day }) else { return false }
            return record.profit < .zero
        }
    }

    /// Days in a row a line loses money before the map says so.
    public static let losingDays = 7

    /// "Yesterday 1,200 in · 980 out": how many got on and off at station
    /// `id`, or `nil` without line accounts.
    public func stationFlowText(at id: StationID, in language: DisplayLanguage) -> String? {
        guard lineAccounts != nil else { return nil }
        let flow = stationFlowYesterday(id)
        return language.text(
            "Yesterday \(Money(flow.boarded).displayText) boarded · \(Money(flow.alighted).displayText) got off",
            "昨日進站 \(Money(flow.boarded).displayText) 人 · 出站 \(Money(flow.alighted).displayText) 人"
        )
    }
}

// MARK: - The fleet list

/// How the fleet overview orders the trains.
public enum FleetSort: String, CaseIterable, Hashable, Sendable {
    case name, line, load, late

    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .name: language.text("Name", "名稱")
        case .line: language.text("Line", "路線")
        case .load: language.text("Load", "滿載")
        case .late: language.text("Late", "誤點")
        }
    }
}

extension GameWorld {
    /// The trains in `order`: by name (the world's), by the line they run
    /// for (those on none last), fullest first, or latest first (a train
    /// with no punctuality last). Ties keep the world's order.
    public func fleet(sortedBy order: FleetSort, in language: DisplayLanguage = .english) -> [Train] {
        let keyed = trains.enumerated().map { index, train -> (train: Train, index: Int, key: Int64) in
            switch order {
            case .name:
                (train, index, 0)
            case .line:
                (train, index, assignedLine(of: train.id).map { Int64($0.rawValue) } ?? Int64.max)
            case .load:
                (train, index, trainLoadInfo(of: train.id).map { -Int64($0.percentage) } ?? Int64.max)
            case .late:
                (train, index, Self.latenessKey(trainServiceStatus(of: train.id, in: language)?.punctuality))
            }
        }
        return keyed.sorted { ($0.key, $0.index) < ($1.key, $1.index) }.map(\.train)
    }

    /// The trains in the order `ids` gives (the fleet list's order when
    /// it was sorted, decision 184, later), then any train not in it in
    /// the world's order; a train no longer in the world is left out. A
    /// list sorted by load or lateness so keeps still while the game runs,
    /// and a tap lands on the train it was aimed at.
    public func fleet(keeping ids: [TrainID]) -> [Train] {
        let listed = Set(ids)
        return ids.compactMap { train(id: $0) } + trains.filter { !listed.contains($0.id) }
    }

    /// The lines in the order `ids` gives (the line panel's order when it
    /// was sorted, decision 184, later), then any line not in it in the
    /// world's order; a line no longer in the world is left out. As
    /// ``fleet(keeping:)``: a list sorted by profit, riders or load keeps
    /// still while the game runs.
    public func lines(keeping ids: [LineID]) -> [ServiceLine] {
        let listed = Set(ids)
        return ids.compactMap { line(id: $0) } + lines.filter { !listed.contains($0.id) }
    }

    /// Smaller sorts first: the later, the smaller; none the largest.
    private static func latenessKey(_ punctuality: Punctuality?) -> Int64 {
        switch punctuality {
        case .late(let minutes)?: -minutes
        case .onTime?: 0
        case .early(let minutes)?: minutes
        case nil: Int64.max
        }
    }
}
