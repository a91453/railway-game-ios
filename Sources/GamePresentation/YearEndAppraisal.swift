import Foundation
import GameCore

// The year-end appraisal (decision 751, ANNUAL-FINANCE AF-3b; design page
// `docs/research/ANNUAL_FINANCE_DESIGN_2026-11-13.md` §3.7): a closed year
// graded A, B or C on five counts, from what the world already keeps. It
// gives and takes no money, is never saved and moves no GameCore rule; the
// year-end report shows it, the news log's year-close line carries its
// grades, and two achievements read it.

/// One of the appraisal's grades.
public enum AppraisalGrade: Int, Hashable, Sendable, Comparable {
    case a, b, c

    public static func < (lhs: AppraisalGrade, rhs: AppraisalGrade) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// "A", "B", "C": the same in both languages.
    public var letter: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .c: "C"
        }
    }
}

/// A closed year's appraisal.
public struct YearEndAppraisal: Hashable, Sendable {
    /// What is graded, in the order the card shows it.
    public enum Item: CaseIterable, Hashable, Sendable {
        case netProfit, revenueGrowth, ridershipGrowth, debtRatio, punctuality

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .netProfit: language.text("Net profit", "淨利")
            case .revenueGrowth: language.text("Revenue growth", "營收成長")
            case .ridershipGrowth: language.text("Ridership growth", "運量成長")
            case .debtRatio: language.text("Debt ratio", "負債比")
            case .punctuality: language.text("Punctuality", "準點率")
            }
        }
    }

    /// One graded count. `grade` is `nil` when the year cannot be graded
    /// on it (no year before to compare with, the days no longer kept, no
    /// timed trains), and the card says why in `detail`.
    public struct Row: Hashable, Sendable {
        public let item: Item
        public let grade: AppraisalGrade?
        /// The figure behind the grade, or why there is none.
        public let english: String
        public let chinese: String

        public func detail(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }
    }

    /// A tax owed for the year, and the day of the year (from 0) it is paid
    /// at the end of.
    public struct TaxDue: Hashable, Sendable {
        public let dueDay: Int64
        public let amount: Money

        /// The month it is paid in, from 1.
        public var month: Int64 { dueDay / 30 + 1 }
    }

    /// The year's index, as ``AnnualStatement/year``.
    public let year: Int64
    public let rows: [Row]
    /// With the annual taxes (decision 734, 736), what the closed year
    /// left owing and when it falls due; empty without them or when
    /// nothing is owed.
    public let taxesDue: [TaxDue]

    // MARK: - Thresholds (decision 751)

    /// Revenue and ridership: A from 10 % more than the year before, B
    /// from as much, C below.
    public static let growthPermilleForA = 100
    /// Debt ÷ total assets: A up to 30 %, B up to 60 %, C above.
    public static let debtPermilleForA = 300
    public static let debtPermilleForB = 600
    /// Trips on time (decision 207, within five minutes): A from 95 %, B
    /// from 85 %, C below.
    public static let punctualPermilleForA = 950
    public static let punctualPermilleForB = 850
    /// The fewest days of a year in both years' riders for ridership to be
    /// graded (the accounts keep 720 days, ``CompanyAccounts/keptDays``).
    public static let ridershipDaysNeeded = 300
    /// The fewest days of the year's last month with timed trips for
    /// punctuality to be graded (line records keep 30,
    /// ``LineAccounts/keptDays``).
    public static let punctualityDaysNeeded = 20

    // MARK: - Grading

    /// The appraisal of `statement`, beside `previous` (the year before,
    /// when it closed and is kept), from what `world` still keeps of the
    /// year's days and lines.
    public init(statement: AnnualStatement, previous: AnnualStatement?, world: GameWorld) {
        year = statement.year
        var rows: [Row] = []
        rows.append(Self.netProfitRow(statement, previous))
        rows.append(Self.revenueRow(statement, previous))
        rows.append(Self.ridershipRow(year: statement.year, days: world.accounts.days.map { ($0.day, $0.fareTrips) }))
        rows.append(Self.debtRow(statement.closing))
        rows.append(Self.punctualityRow(year: statement.year, world: world))
        self.rows = rows
        var dues: [TaxDue] = []
        // Only the newest closed year still owes what the accounts hold.
        if world.annualTaxes, world.accounts.years.last?.year == statement.year {
            let accounts = world.accounts
            let first = accounts.incomeTaxPayable + accounts.houseTaxPayable
            if first > .zero { dues.append(TaxDue(dueDay: CompanyAccounts.incomeTaxDueDay, amount: first)) }
            if accounts.landTaxPayable > .zero {
                dues.append(TaxDue(dueDay: CompanyAccounts.landTaxDueDay, amount: accounts.landTaxPayable))
            }
        }
        taxesDue = dues
    }

    /// The appraisal of the newest closed year, if any.
    public init?(latestOf world: GameWorld) {
        guard let statement = world.accounts.years.last else { return nil }
        let previous = world.accounts.years.last { $0.year == statement.year - 1 }
        self.init(statement: statement, previous: previous, world: world)
    }

    /// The grades given, in order.
    public var grades: [AppraisalGrade] {
        rows.compactMap(\.grade)
    }

    /// Every count graded A, the year before's comparisons included: net
    /// profit, revenue, ridership and debt must all be graded, and
    /// punctuality too when it is.
    public var isAllA: Bool {
        let required: Set<Item> = [.netProfit, .revenueGrowth, .ridershipGrowth, .debtRatio]
        return rows.allSatisfy { row in
            row.grade == .a || (row.grade == nil && !required.contains(row.item))
        }
    }

    /// "A A B A —": the news log's line.
    public var gradesText: String {
        rows.map { $0.grade?.letter ?? "—" }.joined(separator: " ")
    }

    // MARK: - The counts

    static func netProfitRow(_ statement: AnnualStatement, _ previous: AnnualStatement?) -> Row {
        let profit = statement.afterTaxProfit
        let grade: AppraisalGrade
        if profit <= .zero {
            grade = .c
        } else if let last = previous?.afterTaxProfit, profit < last {
            grade = .b
        } else {
            grade = .a
        }
        guard let last = previous?.afterTaxProfit else {
            return Row(item: .netProfit, grade: grade, english: profit.moneyText, chinese: profit.moneyText)
        }
        return Row(
            item: .netProfit, grade: grade,
            english: "\(profit.moneyText) (last year \(last.moneyText))",
            chinese: "\(profit.moneyText)（去年 \(last.moneyText)）"
        )
    }

    /// Fares, freight and the company's buildings' rent.
    static func revenue(_ income: FinanceSummary) -> Money {
        income.fareRevenue + income.freightRevenue + income.propertyRevenue
    }

    static func revenueRow(_ statement: AnnualStatement, _ previous: AnnualStatement?) -> Row {
        guard let previous, revenue(previous.income) > .zero else {
            return notGraded(.revenueGrowth, english: "No year before to compare", chinese: "沒有前一年可比")
        }
        return growthRow(.revenueGrowth, now: revenue(statement.income).amount, before: revenue(previous.income).amount)
    }

    /// Riders of the year against the same days of the year before, only
    /// the days both still keep.
    static func ridershipRow(year: Int64, days: [(day: Int64, trips: Int64)]) -> Row {
        let length = FinancePeriod.year.days
        let byDay = Dictionary(days.map { ($0.day, $0.trips) }, uniquingKeysWith: +)
        var now: Int64 = 0, before: Int64 = 0, matched = 0
        for (day, trips) in byDay where day / length == year {
            guard let earlier = byDay[day - length] else { continue }
            now += trips
            before += earlier
            matched += 1
        }
        guard matched >= ridershipDaysNeeded, before > 0 else {
            return notGraded(.ridershipGrowth, english: "Not enough days kept to compare", chinese: "保留的天數不夠比較")
        }
        return growthRow(.ridershipGrowth, now: now, before: before)
    }

    static func growthRow(_ item: Item, now: Int64, before: Int64) -> Row {
        let permille = Int(((Double(now) - Double(before)) * 1_000 / Double(before)).rounded(.down))
        let grade: AppraisalGrade = permille >= growthPermilleForA ? .a : permille >= 0 ? .b : .c
        let text = signedPercentText(permille)
        return Row(item: item, grade: grade, english: "\(text) on last year", chinese: "比去年 \(text)")
    }

    static func debtRow(_ closing: BalanceSheet) -> Row {
        let debt = closing.loan + closing.termLoans + closing.taxPayable
        guard closing.totalAssets > .zero else {
            return Row(item: .debtRatio, grade: .c, english: "Assets below zero", chinese: "資產小於零")
        }
        let permille = Int((Double(debt.amount) * 1_000 / Double(closing.totalAssets.amount)).rounded(.down))
        let grade: AppraisalGrade = permille <= debtPermilleForA ? .a : permille <= debtPermilleForB ? .b : .c
        let text = percentText(permille)
        return Row(item: .debtRatio, grade: grade, english: "\(text) of assets", chinese: "占資產 \(text)")
    }

    /// The year's last days with timed trips, every line together.
    static func punctualityRow(year: Int64, world: GameWorld) -> Row {
        let length = FinancePeriod.year.days
        var trips: Int64 = 0, late: Int64 = 0
        var days = Set<Int64>()
        for line in world.lines {
            for record in world.lineDays(line.id) where record.day / length == year && record.tally.trips > 0 {
                trips += record.tally.trips
                late += record.tally.lateTrips
                days.insert(record.day)
            }
        }
        guard days.count >= punctualityDaysNeeded, trips > 0 else {
            return notGraded(.punctuality, english: "Only with realistic operation", chinese: "寫實運轉才評")
        }
        return punctualityRow(trips: trips, late: late)
    }

    static func punctualityRow(trips: Int64, late: Int64) -> Row {
        let permille = Int((trips - late) * 1_000 / trips)
        let grade: AppraisalGrade = permille >= punctualPermilleForA ? .a : permille >= punctualPermilleForB ? .b : .c
        let text = percentText(permille)
        return Row(item: .punctuality, grade: grade, english: "\(text) on time, last month", chinese: "最後一個月 \(text) 準點")
    }

    static func notGraded(_ item: Item, english: String, chinese: String) -> Row {
        Row(item: item, grade: nil, english: english, chinese: chinese)
    }

    /// "12.3%" from 123 ‰.
    static func percentText(_ permille: Int) -> String {
        let magnitude = abs(permille)
        return "\(permille < 0 ? "-" : "")\(magnitude / 10).\(magnitude % 10)%"
    }

    /// "+12.3%", "-4.0%".
    static func signedPercentText(_ permille: Int) -> String {
        (permille >= 0 ? "+" : "") + percentText(permille)
    }

    // MARK: - Words

    /// The card's heading: "Year 3 appraisal".
    public func titleText(in language: DisplayLanguage) -> String {
        language.text("Year \(year + 1) appraisal", "第 \(year + 1) 年年終考核")
    }

    /// One line under the grades: what the grades are for.
    public static func footnote(in language: DisplayLanguage) -> String {
        language.text(
            "A report on the year only: it gives and takes no money.",
            "只是這一年的成績單，不加錢也不扣錢。"
        )
    }

    /// "Taxes due next year: NT$… at the end of May".
    public func taxDueText(_ due: TaxDue, in language: DisplayLanguage) -> String {
        language.text(
            "Tax due at the end of month \(due.month): \(due.amount.moneyText)",
            "\(due.month) 月底要繳稅 \(due.amount.moneyText)"
        )
    }
}
