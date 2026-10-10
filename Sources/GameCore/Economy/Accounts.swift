// The company's accounts (G1c, ARCHITECTURE decision 36), ported from the
// owner's `Ci/` reference's legacy economy path
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`): what the hour
// has earned and run (`metroEconomyNewHourlyPending`), the ledger rows the
// hourly and daily settlements write (`metro.hourly.netSettlement`,
// `metroEconomySettleDailyForEndedDay`) and the finance report's periods
// (`FLOW_DASHBOARD_FINANCE_BUCKETS`, `summarizeFinanceForTransport`).
// Every amount is whole cents (decision 36).

/// What the current hour has earned and run, until it is settled (the
/// reference's hourly pending bucket).
public struct HourlyAccrual: Hashable, Sendable {
    /// Fares charged this hour.
    public internal(set) var fareRevenue: Money = .zero
    /// Passengers who paid a fare.
    public internal(set) var fareTrips: Int64 = 0
    /// Times a line's train left a stop for the next.
    public internal(set) var departures: Int64 = 0
    /// How far those trains ran to their next stops, in world units
    /// (1/64 m): the reference's train-km.
    public internal(set) var trainDistance: Int64 = 0
    /// Passengers on board as those trains left, and the seats they had
    /// (their rated capacity).
    public internal(set) var passengers: Int64 = 0
    public internal(set) var seats: Int64 = 0

    public init() {}

    public static let empty = HourlyAccrual()
}

/// What a ledger amount is for (the reference's ledger categories): its
/// own sign is the amount's.
public enum LedgerItem: String, CaseIterable, Codable, Sendable {
    /// `metro_fare_revenue`: fares, in.
    case fareRevenue
    /// `metro_operating_cost`: running the trains and stations, out.
    case operatingCost
    /// `metro_maintenance_cost`: keeping the lines and trains, out.
    case maintenanceCost
    /// `metro_route_energy` and `metro_train_energy`: the day's energy, out.
    case routeEnergy
    case trainEnergy
    /// `metro_station_staff` and `metro_train_staff`: the day's staff, out.
    case stationStaff
    case trainStaff
    /// The day's interest on the company's loan, out (decision 67; the
    /// reference has no loans).
    case loanInterest
    /// The company's buildings (decision 94; native, the reference has no
    /// property): the day's rent in, their upkeep and the asset tax on the
    /// land they use out, and what demolishing one cost, out.
    case propertyRent
    case propertyUpkeep
    case propertyTax
    case propertyDemolition
    /// The tax on the day's profit, out (decision 131; native, the
    /// reference has no tax): half of what the day made before tax beyond
    /// ``CompanyAccounts/taxFreeProfit``.
    case incomeTax
}

/// One line of a ledger row's breakdown.
public struct LedgerLine: Hashable, Sendable {
    public let item: LedgerItem
    /// Positive for money in, negative for money out.
    public let amount: Money

    public init(item: LedgerItem, amount: Money) {
        self.item = item
        self.amount = amount
    }
}

/// How crowded the network was when an hour was settled (the reference's
/// `crowdingMetrics`): for the record, they charge nothing.
public struct CrowdingMetrics: Hashable, Sendable {
    /// Stations with more than ``crowdedWaiting`` waiting.
    public let crowdedStations: Int64
    /// Trains carrying at least their rated capacity.
    public let fullTrains: Int64
    /// The most waiting at any station.
    public let maxWaiting: Int64
    /// The highest load of any train against its rated capacity, in
    /// thousandths rounded half up.
    public let maxLoad: Int64

    public init(crowdedStations: Int64, fullTrains: Int64, maxWaiting: Int64, maxLoad: Int64) {
        self.crowdedStations = crowdedStations
        self.fullTrains = fullTrains
        self.maxWaiting = maxWaiting
        self.maxLoad = maxLoad
    }

    /// `CROWD_NOTIFY_WAITING_THRESHOLD`.
    public static let crowdedWaiting: Int64 = 1_500
}

/// A ledger row (the reference's `metro_hourly_net`, `metro_daily_energy`
/// and `metro_daily_staff` rows).
public struct LedgerEntry: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        /// An hour's fares less its running and upkeep.
        case hourlyNet
        /// A day's energy.
        case dailyEnergy
        /// A day's staff.
        case dailyStaff
        /// A day's interest on the loan (decision 67).
        case dailyInterest
        /// A day's rent, upkeep and tax of the company's buildings
        /// (decision 94).
        case dailyProperty
        /// What demolishing one of the company's buildings cost (decision
        /// 94), written when it was demolished.
        case buildingDemolition
        /// A day's tax on its profit (decision 131).
        case dailyTax
    }

    public let kind: Kind
    /// When it was written: the minute an hour was settled, or the last
    /// minute of the day settled.
    public let time: GameTime
    /// The row's total, positive for money in.
    public let amount: Money
    public let breakdown: [LedgerLine]
    /// The hour's crowding, for an hourly row.
    public let crowding: CrowdingMetrics?

    public init(kind: Kind, time: GameTime, amount: Money, breakdown: [LedgerLine], crowding: CrowdingMetrics? = nil) {
        self.kind = kind
        self.time = time
        self.amount = amount
        self.breakdown = breakdown
        self.crowding = crowding
    }
}

/// One day's totals by item (all non-negative): what the finance report
/// adds up.
public struct DayAccount: Hashable, Sendable {
    /// The day's index: second ÷ 86400 (minute ÷ 1440), rounded down.
    public let day: Int64
    public internal(set) var fareRevenue: Money = .zero
    public internal(set) var operatingCost: Money = .zero
    public internal(set) var maintenanceCost: Money = .zero
    public internal(set) var energyCost: Money = .zero
    public internal(set) var staffCost: Money = .zero
    /// Interest paid on the loan (decision 67): not a running cost, so not
    /// in ``totalCost``.
    public internal(set) var interestCost: Money = .zero
    /// Passengers who paid a fare that day (decision 86): what a riders
    /// goal reads. Not money, so in no statement.
    public internal(set) var fareTrips: Int64 = 0
    /// The company's buildings' rent, and their upkeep and tax (decision
    /// 94): not the railway's, so not in ``totalCost``.
    public internal(set) var propertyRevenue: Money = .zero
    public internal(set) var propertyCost: Money = .zero
    /// The tax on the day's profit (decision 131): not a running cost, so
    /// not in ``totalCost``.
    public internal(set) var taxCost: Money = .zero

    public init(day: Int64) {
        self.day = day
    }

    public var totalCost: Money {
        operatingCost + maintenanceCost + energyCost + staffCost
    }

    /// Adds `entry`'s breakdown.
    mutating func add(_ entry: LedgerEntry) {
        for line in entry.breakdown {
            let cost = Money(-line.amount.amount)
            switch line.item {
            case .fareRevenue: fareRevenue = fareRevenue + line.amount
            case .operatingCost: operatingCost = operatingCost + cost
            case .maintenanceCost: maintenanceCost = maintenanceCost + cost
            case .routeEnergy, .trainEnergy: energyCost = energyCost + cost
            case .stationStaff, .trainStaff: staffCost = staffCost + cost
            case .loanInterest: interestCost = interestCost + cost
            case .propertyRent: propertyRevenue = propertyRevenue + line.amount
            case .propertyUpkeep, .propertyTax, .propertyDemolition: propertyCost = propertyCost + cost
            case .incomeTax: taxCost = taxCost + cost
            }
        }
    }
}

/// A finance report's period (`FLOW_DASHBOARD_FINANCE_BUCKETS`).
public enum FinancePeriod: String, CaseIterable, Codable, Sendable {
    case day, week, month, year

    /// Days in the period: 1, 7, 30 and 360.
    public var days: Int64 {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .year: 360
        }
    }
}

/// A period's income statement (`summarizeFinanceForTransport`).
public struct FinanceSummary: Hashable, Sendable {
    /// The period's index: day ÷ its days, rounded down.
    public let index: Int64
    public let fareRevenue: Money
    public let operatingCost: Money
    public let maintenanceCost: Money
    public let energyCost: Money
    public let staffCost: Money
    /// Interest paid on the loan (decision 67).
    public let interestCost: Money
    /// Assets written down and written off (Phase 7a): costs that pay no
    /// cash.
    public var depreciationCost: Money = .zero
    public var writeOffCost: Money = .zero
    /// Cash paid for new assets, borrowed and repaid (Phase 7a): no profit
    /// or loss.
    public var capitalSpending: Money = .zero
    public var loanBorrowed: Money = .zero
    public var loanRepaid: Money = .zero
    /// The company's buildings' rent, and their upkeep and tax (decision
    /// 94), paid in cash.
    public var propertyRevenue: Money = .zero
    public var propertyCost: Money = .zero
    /// What the company's buildings sold for, and the book value they left
    /// the books at (decision 130).
    public var saleProceeds: Money = .zero
    public var saleBookValue: Money = .zero
    /// The tax on each day's profit (decision 131), paid in cash.
    public var taxCost: Money = .zero

    /// The railway's running costs.
    public var totalCost: Money {
        operatingCost + maintenanceCost + energyCost + staffCost
    }

    /// Revenue less every running cost: the railway's, and since decision
    /// 94 the company's buildings'.
    public var operatingProfit: Money {
        fareRevenue - totalCost + propertyRevenue - propertyCost
    }

    /// The gain realized on the company's buildings sold, or the loss when
    /// negative (decision 130): what they sold for less their book value.
    public var realizedGain: Money {
        saleProceeds - saleBookValue
    }

    /// The operating profit less the loan's interest (decision 67) and the
    /// assets written down and off (Phase 7a), with the gain or loss
    /// realized on buildings sold (decision 130): what each day's tax is on
    /// (decision 131).
    public var profitBeforeTax: Money {
        operatingProfit - interestCost - depreciationCost - writeOffCost + realizedGain
    }

    /// The profit before tax less the tax (decision 131).
    public var netProfit: Money {
        profitBeforeTax - taxCost
    }

    /// The cash the running of the network brought in: fares less the
    /// running costs, interest and tax, all paid in cash (the reference's
    /// `operatingCashFlow`, with the interest and tax it has not).
    public var operatingCashFlow: Money {
        operatingProfit - interestCost - taxCost
    }

    /// The cash spent on new assets, as negative, and since decision 130
    /// received for buildings sold (the reference's `investingCashFlow`,
    /// there quota purchases).
    public var investingCashFlow: Money {
        saleProceeds - capitalSpending
    }

    /// The cash borrowed less repaid (native: the reference has no loan).
    public var financingCashFlow: Money {
        loanBorrowed - loanRepaid
    }

    /// The change in cash over the period (the reference's `netCashFlow`).
    public var netCashFlow: Money {
        operatingCashFlow + investingCashFlow + financingCashFlow
    }
}

/// The company's accounts: its economy mode and fare rules, the hour being
/// accrued, the latest ledger rows and the days the report adds up.
public struct CompanyAccounts: Hashable, Sendable {
    public internal(set) var mode: EconomyMode = .free
    /// The fare rules the player set, or `nil` if never: then trips pay
    /// ``FareRules/standard`` and fares do not change demand (the
    /// reference's demand overlay starts with the first change of rules).
    public internal(set) var fareRules: FareRules?
    /// The fare the city's passengers think fair, which a fare's effect on
    /// demand is measured against (the reference's
    /// `metroFareDemandBaselineForCity`): ``FareRules/demandBaseline``,
    /// the reference's default city, until set.
    public internal(set) var fareBaseline: Money = FareRules.demandBaseline
    public internal(set) var pending: HourlyAccrual = .empty
    /// When the accrual in ``pending`` began: the minute the company became
    /// managed, or the last settlement. An hour is settled only once it
    /// has begun (the reference settles when the hour's key changes, never
    /// at its first frame). `nil` while the company was never managed.
    public internal(set) var openedAt: GameTime?
    /// The latest ledger rows, in the order they were written: at most
    /// ``keptEntries``. A day's energy and staff rows are dated its last
    /// minute but written after the hour settled at midnight, as in the
    /// reference.
    public internal(set) var entries: [LedgerEntry] = []
    /// The latest days with any ledger row, by ascending day: at most
    /// ``keptDays``.
    public internal(set) var days: [DayAccount] = []
    /// What the company owes the bank (decision 67): borrowed and repaid in
    /// ``loanStep``s up to ``maximumLoan``; interest is paid every midnight
    /// while the company is managed.
    public internal(set) var loan: Money = .zero
    /// What the company bought and still has, at what it paid, in the order
    /// bought (Phase 7a).
    public internal(set) var assets: [AssetRecord] = []
    /// The latest days with any depreciation, write-off, capital spending
    /// or loan movement, by ascending day: at most ``keptCapitalDays``.
    public internal(set) var capitalDays: [CapitalDay] = []
    /// The closed years, by ascending year: at most ``keptYears``.
    public internal(set) var years: [AnnualStatement] = []

    /// Loans are taken and repaid $100,000 at a time.
    public static let loanStep: Money = 10_000_000
    /// The most the company may owe: $5,000,000.
    public static let maximumLoan: Money = 500_000_000
    /// The yearly interest, in hundredths of a percent: 5 %, over the
    /// finance report's 360-day year, charged daily.
    public static let interestBasisPoints: Int64 = 500
    /// Decision 131: the profit a day makes before tax that is not taxed,
    /// $100,000, and the share of the rest paid as tax, in per cent: half.
    public static let taxFreeProfit: Money = 10_000_000
    public static let taxPercent: Int64 = 50

    /// The economy panel shows the last 12 rows and the last hour's totals;
    /// two days of rows cover both.
    public static let keptEntries = 50
    /// Two years of days, so the year report's previous year stays whole:
    /// the reference keeps its whole ledger (`FLOW_DASHBOARD_FINANCE_BUCKETS`
    /// reports up to 50 years), and this is the least that keeps both of
    /// the report's statements exact.
    public static let keptDays = 720

    public init() {}

    /// Whether there is nothing in the accounts: a world before G1c.
    var isPristine: Bool {
        mode == .free && fareRules == nil && fareBaseline == FareRules.demandBaseline && pending == .empty && openedAt == nil
            && entries.isEmpty && days.isEmpty && loan == .zero && assets.isEmpty && capitalDays.isEmpty && years.isEmpty
    }

    /// The rules trips pay by.
    public var effectiveFareRules: FareRules {
        fareRules ?? .standard
    }

    /// Writes `entry`, keeping the latest rows and days.
    mutating func record(_ entry: LedgerEntry, day: Int64) {
        entries.append(entry)
        if entries.count > Self.keptEntries {
            entries.removeFirst(entries.count - Self.keptEntries)
        }
        let index: Int
        if let known = days.firstIndex(where: { $0.day == day }) {
            index = known
        } else {
            index = days.firstIndex { $0.day > day } ?? days.count
            days.insert(DayAccount(day: day), at: index)
        }
        days[index].add(entry)
        days.removeAll { $0.day <= day - Int64(Self.keptDays) }
    }

    /// Adds `trips` fare-paying passengers to day `day`, which a row has
    /// just been written to, stopping at the most a save holds.
    mutating func addTrips(_ trips: Int64, day: Int64) {
        guard trips > 0, let index = days.firstIndex(where: { $0.day == day }) else { return }
        days[index].fareTrips = min(days[index].fareTrips + trips, GameWorld.maximumAccrued)
    }

    /// The statements of the period `period` containing day `day` and of
    /// the one before it.
    public func report(_ period: FinancePeriod, day: Int64) -> (current: FinanceSummary, previous: FinanceSummary) {
        let current = Self.floorDivide(day, period.days)
        func summary(_ index: Int64) -> FinanceSummary {
            let inPeriod = days.filter { Self.floorDivide($0.day, period.days) == index }
            func total(_ value: (DayAccount) -> Money) -> Money {
                inPeriod.reduce(.zero) { $0 + value($1) }
            }
            let capital = capitalDays.filter { Self.floorDivide($0.day, period.days) == index }
            func capitalTotal(_ value: (CapitalDay) -> Money) -> Money {
                capital.reduce(.zero) { $0 + value($1) }
            }
            var summary = FinanceSummary(
                index: index, fareRevenue: total(\.fareRevenue), operatingCost: total(\.operatingCost),
                maintenanceCost: total(\.maintenanceCost), energyCost: total(\.energyCost), staffCost: total(\.staffCost),
                interestCost: total(\.interestCost)
            )
            summary.depreciationCost = capitalTotal(\.depreciation)
            summary.writeOffCost = capitalTotal(\.writeOff)
            summary.capitalSpending = capitalTotal(\.capitalSpending)
            summary.loanBorrowed = capitalTotal(\.borrowed)
            summary.loanRepaid = capitalTotal(\.repaid)
            summary.propertyRevenue = total(\.propertyRevenue)
            summary.propertyCost = total(\.propertyCost)
            summary.saleProceeds = capitalTotal(\.saleProceeds)
            summary.saleBookValue = capitalTotal(\.saleBookValue)
            summary.taxCost = total(\.taxCost)
            return summary
        }
        return (summary(current), summary(current - 1))
    }

    static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }
}

// MARK: - Codable

extension HourlyAccrual: Codable {}
extension LedgerLine: Codable {}
extension CrowdingMetrics: Codable {}
extension FinanceSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case index, fareRevenue, operatingCost, maintenanceCost, energyCost, staffCost, interestCost
        case depreciationCost, writeOffCost, capitalSpending, loanBorrowed, loanRepaid, propertyRevenue, propertyCost
        case saleProceeds, saleBookValue, taxCost
    }

    /// Decodes a closed year's statement; one without the company's
    /// buildings (every year before save version 22) has no
    /// `"propertyRevenue"` or `"propertyCost"`, one that sold none
    /// (every year before save version 29) no `"saleProceeds"` or
    /// `"saleBookValue"`, and one without tax (every year before decision
    /// 131) no `"taxCost"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int64.self, forKey: .index)
        fareRevenue = try container.decode(Money.self, forKey: .fareRevenue)
        operatingCost = try container.decode(Money.self, forKey: .operatingCost)
        maintenanceCost = try container.decode(Money.self, forKey: .maintenanceCost)
        energyCost = try container.decode(Money.self, forKey: .energyCost)
        staffCost = try container.decode(Money.self, forKey: .staffCost)
        interestCost = try container.decode(Money.self, forKey: .interestCost)
        depreciationCost = try container.decode(Money.self, forKey: .depreciationCost)
        writeOffCost = try container.decode(Money.self, forKey: .writeOffCost)
        capitalSpending = try container.decode(Money.self, forKey: .capitalSpending)
        loanBorrowed = try container.decode(Money.self, forKey: .loanBorrowed)
        loanRepaid = try container.decode(Money.self, forKey: .loanRepaid)
        propertyRevenue = try container.decodeIfPresent(Money.self, forKey: .propertyRevenue) ?? .zero
        propertyCost = try container.decodeIfPresent(Money.self, forKey: .propertyCost) ?? .zero
        saleProceeds = try container.decodeIfPresent(Money.self, forKey: .saleProceeds) ?? .zero
        saleBookValue = try container.decodeIfPresent(Money.self, forKey: .saleBookValue) ?? .zero
        taxCost = try container.decodeIfPresent(Money.self, forKey: .taxCost) ?? .zero
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(fareRevenue, forKey: .fareRevenue)
        try container.encode(operatingCost, forKey: .operatingCost)
        try container.encode(maintenanceCost, forKey: .maintenanceCost)
        try container.encode(energyCost, forKey: .energyCost)
        try container.encode(staffCost, forKey: .staffCost)
        try container.encode(interestCost, forKey: .interestCost)
        try container.encode(depreciationCost, forKey: .depreciationCost)
        try container.encode(writeOffCost, forKey: .writeOffCost)
        try container.encode(capitalSpending, forKey: .capitalSpending)
        try container.encode(loanBorrowed, forKey: .loanBorrowed)
        try container.encode(loanRepaid, forKey: .loanRepaid)
        if propertyRevenue != .zero { try container.encode(propertyRevenue, forKey: .propertyRevenue) }
        if propertyCost != .zero { try container.encode(propertyCost, forKey: .propertyCost) }
        if saleProceeds != .zero { try container.encode(saleProceeds, forKey: .saleProceeds) }
        if saleBookValue != .zero { try container.encode(saleBookValue, forKey: .saleBookValue) }
        if taxCost != .zero { try container.encode(taxCost, forKey: .taxCost) }
    }
}

extension DayAccount: Codable {
    private enum CodingKeys: String, CodingKey {
        case day, fareRevenue, operatingCost, maintenanceCost, energyCost, staffCost, interestCost, fareTrips
        case propertyRevenue, propertyCost, taxCost
    }

    /// Decodes a day; a day without interest, as every day before loans,
    /// has no `"interestCost"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Int64.self, forKey: .day)
        fareRevenue = try container.decode(Money.self, forKey: .fareRevenue)
        operatingCost = try container.decode(Money.self, forKey: .operatingCost)
        maintenanceCost = try container.decode(Money.self, forKey: .maintenanceCost)
        energyCost = try container.decode(Money.self, forKey: .energyCost)
        staffCost = try container.decode(Money.self, forKey: .staffCost)
        interestCost = container.contains(.interestCost) ? try container.decode(Money.self, forKey: .interestCost) : .zero
        fareTrips = container.contains(.fareTrips) ? try container.decode(Int64.self, forKey: .fareTrips) : 0
        // Decision 94: a day without the company's buildings has neither.
        propertyRevenue = try container.decodeIfPresent(Money.self, forKey: .propertyRevenue) ?? .zero
        propertyCost = try container.decodeIfPresent(Money.self, forKey: .propertyCost) ?? .zero
        // Decision 131: a day without tax has none.
        taxCost = try container.decodeIfPresent(Money.self, forKey: .taxCost) ?? .zero
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(fareRevenue, forKey: .fareRevenue)
        try container.encode(operatingCost, forKey: .operatingCost)
        try container.encode(maintenanceCost, forKey: .maintenanceCost)
        try container.encode(energyCost, forKey: .energyCost)
        try container.encode(staffCost, forKey: .staffCost)
        if interestCost != .zero {
            try container.encode(interestCost, forKey: .interestCost)
        }
        if fareTrips != 0 {
            try container.encode(fareTrips, forKey: .fareTrips)
        }
        if propertyRevenue != .zero {
            try container.encode(propertyRevenue, forKey: .propertyRevenue)
        }
        if propertyCost != .zero {
            try container.encode(propertyCost, forKey: .propertyCost)
        }
        if taxCost != .zero {
            try container.encode(taxCost, forKey: .taxCost)
        }
    }
}

extension LedgerEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, time, amount, breakdown, crowding
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        time = try container.decode(GameTime.self, forKey: .time)
        amount = try container.decode(Money.self, forKey: .amount)
        breakdown = try container.decode([LedgerLine].self, forKey: .breakdown)
        crowding = container.contains(.crowding) ? try container.decode(CrowdingMetrics.self, forKey: .crowding) : nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(time, forKey: .time)
        try container.encode(amount, forKey: .amount)
        try container.encode(breakdown, forKey: .breakdown)
        if let crowding {
            try container.encode(crowding, forKey: .crowding)
        }
    }
}

extension CompanyAccounts: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, fareRules, fareBaseline, pending, openedAt, entries, days, loan, assets, capitalDays, years
    }

    /// Decodes the accounts; rules the player never set have no
    /// `"fareRules"`, and the default city's baseline no `"fareBaseline"`.
    /// That the amounts are within bounds and in order is checked by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(EconomyMode.self, forKey: .mode)
        fareRules = container.contains(.fareRules) ? try container.decode(FareRules.self, forKey: .fareRules) : nil
        fareBaseline = container.contains(.fareBaseline) ? try container.decode(Money.self, forKey: .fareBaseline) : FareRules.demandBaseline
        pending = try container.decode(HourlyAccrual.self, forKey: .pending)
        openedAt = container.contains(.openedAt) ? try container.decode(GameTime.self, forKey: .openedAt) : nil
        entries = try container.decode([LedgerEntry].self, forKey: .entries)
        days = try container.decode([DayAccount].self, forKey: .days)
        loan = container.contains(.loan) ? try container.decode(Money.self, forKey: .loan) : .zero
        // Phase 7a: accounts before save version 16 kept no assets.
        assets = container.contains(.assets) ? try container.decode([AssetRecord].self, forKey: .assets) : []
        capitalDays = container.contains(.capitalDays) ? try container.decode([CapitalDay].self, forKey: .capitalDays) : []
        years = container.contains(.years) ? try container.decode([AnnualStatement].self, forKey: .years) : []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        if let fareRules {
            try container.encode(fareRules, forKey: .fareRules)
        }
        if fareBaseline != FareRules.demandBaseline {
            try container.encode(fareBaseline, forKey: .fareBaseline)
        }
        try container.encode(pending, forKey: .pending)
        if let openedAt {
            try container.encode(openedAt, forKey: .openedAt)
        }
        try container.encode(entries, forKey: .entries)
        try container.encode(days, forKey: .days)
        if loan != .zero {
            try container.encode(loan, forKey: .loan)
        }
        if !assets.isEmpty {
            try container.encode(assets, forKey: .assets)
        }
        if !capitalDays.isEmpty {
            try container.encode(capitalDays, forKey: .capitalDays)
        }
        if !years.isEmpty {
            try container.encode(years, forKey: .years)
        }
    }
}
