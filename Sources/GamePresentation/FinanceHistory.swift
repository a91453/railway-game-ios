import GameCore

// The economy panel's trend charts (ARCHITECTURE decision 176): the
// company's days (`accounts.days`, 720 kept) and closed years
// (`accounts.years`) folded into the buckets a chart draws: days, weeks,
// months or years. The reference's finance dashboard does the same
// (`flowDashboardFinanceTrendData`: a series of buckets, each with its
// revenue, cost and profit; here the buckets are the window's last N days
// instead of calendar months, because the game's month is 30 days and its
// year 360). Everything is read from the accounts; nothing is kept.

/// How far back a trend chart looks.
public enum FinanceTrendRange: String, CaseIterable, Hashable, Sendable {
    case thirtyDays, ninetyDays, oneYear, allYears

    /// Days of one bucket, and how many buckets: 30 days, 13 weeks (91
    /// days), 12 months (360 days). `allYears` has a bucket per closed
    /// year, so no fixed count.
    var bucketDays: Int64 {
        switch self {
        case .thirtyDays: 1
        case .ninetyDays: 7
        case .oneYear: 30
        case .allYears: 360
        }
    }

    var bucketCount: Int {
        switch self {
        case .thirtyDays: 30
        case .ninetyDays: 13
        case .oneYear: 12
        case .allYears: CompanyAccounts.keptYears
        }
    }

    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .thirtyDays: language.text("30 days", "30 天")
        case .ninetyDays: language.text("90 days", "90 天")
        case .oneYear: language.text("1 year", "1 年")
        case .allYears: language.text("All years", "歷年")
        }
    }
}

/// One bucket of a trend chart.
public struct FinanceTrendPoint: Hashable, Identifiable, Sendable {
    /// The bucket's first day (a closed year's first day for `allYears`).
    public let startDay: Int64
    /// Its last day, inclusive.
    public let endDay: Int64
    public let fareRevenue: Money
    public let freightRevenue: Money
    public let propertyRevenue: Money
    /// Every cash cost: the running costs, the buildings' upkeep and tax,
    /// interest and the tax on profit. Depreciation and write-offs pay no
    /// cash, so they are not in it.
    public let cost: Money
    /// Passengers who paid, or `nil` where it was not kept (a closed
    /// year's statement has no count).
    public let trips: Int64?

    public var id: Int64 { startDay }

    public var revenue: Money {
        fareRevenue + freightRevenue + propertyRevenue
    }

    /// Revenue less cost: positive is a profit.
    public var netProfit: Money {
        revenue - cost
    }

    public init(
        startDay: Int64, endDay: Int64, fareRevenue: Money, freightRevenue: Money, propertyRevenue: Money, cost: Money,
        trips: Int64?
    ) {
        self.startDay = startDay
        self.endDay = endDay
        self.fareRevenue = fareRevenue
        self.freightRevenue = freightRevenue
        self.propertyRevenue = propertyRevenue
        self.cost = cost
        self.trips = trips
    }

    /// "Day 12", "Days 8–14" or, for a closed year, "Year 2".
    public func label(for range: FinanceTrendRange, in language: DisplayLanguage) -> String {
        switch range {
        case .allYears:
            return language.text("Year \(startDay / 360 + 1)", "第 \(startDay / 360 + 1) 年")
        case .thirtyDays:
            return language.text("Day \(startDay + 1)", "第 \(startDay + 1) 天")
        case .ninetyDays, .oneYear:
            // The first bucket of a young game reaches back before day 1.
            let from = max(startDay, 0) + 1, to = max(endDay, 0) + 1
            return language.text("Days \(from)–\(to)", "第 \(from)–\(to) 天")
        }
    }

    /// A tapped bucket's numbers, on one line.
    public func detailText(for range: FinanceTrendRange, in language: DisplayLanguage) -> String {
        var parts = [
            label(for: range, in: language),
            language.text("revenue \(revenue.moneyText)", "收入 \(revenue.moneyText)"),
            language.text("cost \(cost.moneyText)", "成本 \(cost.moneyText)"),
            netProfit < .zero
                ? language.text("loss \(Money(0 - netProfit.amount).moneyText)", "虧損 \(Money(0 - netProfit.amount).moneyText)")
                : language.text("profit \(netProfit.moneyText)", "利潤 \(netProfit.moneyText)"),
        ]
        if let trips {
            parts.append(language.text("\(trips) passengers", "旅客 \(trips) 人"))
        }
        return parts.joined(separator: " · ")
    }
}

/// The buckets of one range, oldest first.
public struct FinanceHistory: Hashable, Sendable {
    public let range: FinanceTrendRange
    public let points: [FinanceTrendPoint]
    /// The same window one step earlier, for the headline's comparison:
    /// fares and passengers over this window and the one before it.
    public let fareRevenue: Money
    public let previousFareRevenue: Money
    public let trips: Int64?
    public let previousTrips: Int64?

    public var isEmpty: Bool {
        points.isEmpty
    }

    /// Whether a chart of passengers has anything to draw (a closed year
    /// has no count).
    public var hasTrips: Bool {
        points.contains { $0.trips != nil }
    }

    /// The history of `range` as of day `today` (the day in progress is the
    /// last one in the window).
    public static func make(_ range: FinanceTrendRange, accounts: CompanyAccounts, today: Int64) -> FinanceHistory {
        switch range {
        case .allYears:
            return years(accounts.years)
        case .thirtyDays, .ninetyDays, .oneYear:
            return windowed(range, accounts: accounts, today: today)
        }
    }

    public static func make(_ range: FinanceTrendRange, world: GameWorld) -> FinanceHistory {
        make(range, accounts: world.accounts, today: floorDay(world.clock.now))
    }

    static func floorDay(_ time: GameTime) -> Int64 {
        let quotient = time.seconds / GameTime.secondsPerDay
        return time.seconds % GameTime.secondsPerDay < 0 ? quotient - 1 : quotient
    }

    private static func windowed(_ range: FinanceTrendRange, accounts: CompanyAccounts, today: Int64) -> FinanceHistory {
        let size = range.bucketDays
        let count = Int64(range.bucketCount)
        let first = today - size * count + 1
        // One window earlier too, for the comparison.
        let byDay = Dictionary(accounts.days.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        func bucket(_ start: Int64) -> FinanceTrendPoint {
            var fare = Money.zero, freight = Money.zero, property = Money.zero, cost = Money.zero
            var trips: Int64 = 0
            for day in start..<(start + size) {
                guard let account = byDay[day] else { continue }
                fare = fare + account.fareRevenue
                freight = freight + account.freightRevenue
                property = property + account.propertyRevenue
                cost = cost + account.totalCost + account.propertyCost + account.interestCost + account.taxCost
                trips += account.fareTrips
            }
            return FinanceTrendPoint(
                startDay: start, endDay: start + size - 1, fareRevenue: fare, freightRevenue: freight, propertyRevenue: property,
                cost: cost, trips: trips
            )
        }
        let points = (0..<count).map { bucket(first + $0 * size) }
        let before = (0..<count).map { bucket(first - (count - $0) * size) }
        // Nothing before the company's first day: no points at all until it
        // has earned or spent something.
        let kept = points.drop { $0.revenue == .zero && $0.cost == .zero && $0.trips == 0 }
        return FinanceHistory(
            range: range, points: Array(kept), fareRevenue: points.reduce(.zero) { $0 + $1.fareRevenue },
            previousFareRevenue: before.reduce(.zero) { $0 + $1.fareRevenue },
            trips: points.reduce(0) { $0 + ($1.trips ?? 0) }, previousTrips: before.reduce(0) { $0 + ($1.trips ?? 0) }
        )
    }

    private static func years(_ statements: [AnnualStatement]) -> FinanceHistory {
        let points = statements.map { statement -> FinanceTrendPoint in
            let income = statement.income
            return FinanceTrendPoint(
                startDay: statement.year * 360, endDay: statement.year * 360 + 359, fareRevenue: income.fareRevenue,
                freightRevenue: income.freightRevenue, propertyRevenue: income.propertyRevenue,
                cost: income.totalCost + income.propertyCost + income.interestCost + income.taxCost, trips: nil
            )
        }
        return FinanceHistory(
            range: .allYears, points: points, fareRevenue: points.last?.fareRevenue ?? .zero,
            previousFareRevenue: points.dropLast().last?.fareRevenue ?? .zero, trips: nil, previousTrips: nil
        )
    }

    /// The change from the window before to this one, in whole percent,
    /// rounded to the nearest; `nil` when the window before had none to
    /// compare with.
    static func percentChange(from previous: Int64, to current: Int64) -> Int? {
        guard previous > 0 else { return nil }
        let change = (Double(current) - Double(previous)) / Double(previous) * 100
        return Int(change.rounded())
    }

    public var fareChangePercent: Int? {
        Self.percentChange(from: previousFareRevenue.amount, to: fareRevenue.amount)
    }

    public var tripsChangePercent: Int? {
        guard let trips, let previousTrips else { return nil }
        return Self.percentChange(from: previousTrips, to: trips)
    }

    /// What VoiceOver reads, and the line above the charts: "Last 30 days:
    /// fares up 12%, passengers down 3%".
    public func summaryText(in language: DisplayLanguage) -> String {
        let window: String
        switch range {
        case .thirtyDays: window = language.text("Last 30 days", "過去 30 天")
        case .ninetyDays: window = language.text("Last 90 days", "過去 90 天")
        case .oneYear: window = language.text("Last year", "過去 1 年")
        case .allYears: window = language.text("Latest closed year", "最近一個決算年度")
        }
        if points.isEmpty {
            return language.text("\(window): nothing to show yet.", "\(window)：還沒有資料。")
        }
        var parts = [Self.changeText(language.text("fares", "票收"), fareChangePercent, language)]
        if hasTrips {
            parts.append(Self.changeText(language.text("passengers", "旅客"), tripsChangePercent, language))
        }
        return window + (language == .english ? ": " : "：") + parts.joined(separator: language == .english ? ", " : "、")
    }

    private static func changeText(_ name: String, _ percent: Int?, _ language: DisplayLanguage) -> String {
        guard let percent else { return language.text("\(name) have no earlier period to compare with", "\(name)沒有更早的期間可比") }
        if percent == 0 { return language.text("\(name) unchanged", "\(name)持平") }
        let size = abs(percent)
        return percent > 0
            ? language.text("\(name) up \(size)%", "\(name)成長 \(size)%")
            : language.text("\(name) down \(size)%", "\(name)下降 \(size)%")
    }
}
