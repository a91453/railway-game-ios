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

    public var totalCost: Money {
        operatingCost + maintenanceCost + energyCost + staffCost
    }

    /// Revenue less every cost; with no investing flows in G1 it is also
    /// the net cash flow.
    public var operatingProfit: Money {
        fareRevenue - totalCost
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
        mode == .free && fareRules == nil && pending == .empty && openedAt == nil && entries.isEmpty && days.isEmpty
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

    /// The statements of the period `period` containing day `day` and of
    /// the one before it.
    public func report(_ period: FinancePeriod, day: Int64) -> (current: FinanceSummary, previous: FinanceSummary) {
        let current = Self.floorDivide(day, period.days)
        func summary(_ index: Int64) -> FinanceSummary {
            let inPeriod = days.filter { Self.floorDivide($0.day, period.days) == index }
            func total(_ value: (DayAccount) -> Money) -> Money {
                inPeriod.reduce(.zero) { $0 + value($1) }
            }
            return FinanceSummary(
                index: index, fareRevenue: total(\.fareRevenue), operatingCost: total(\.operatingCost),
                maintenanceCost: total(\.maintenanceCost), energyCost: total(\.energyCost), staffCost: total(\.staffCost)
            )
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
extension DayAccount: Codable {}

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
        case mode, fareRules, pending, openedAt, entries, days
    }

    /// Decodes the accounts; rules the player never set have no
    /// `"fareRules"`. That the amounts are within bounds and in order is
    /// checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(EconomyMode.self, forKey: .mode)
        fareRules = container.contains(.fareRules) ? try container.decode(FareRules.self, forKey: .fareRules) : nil
        pending = try container.decode(HourlyAccrual.self, forKey: .pending)
        openedAt = container.contains(.openedAt) ? try container.decode(GameTime.self, forKey: .openedAt) : nil
        entries = try container.decode([LedgerEntry].self, forKey: .entries)
        days = try container.decode([DayAccount].self, forKey: .days)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        if let fareRules {
            try container.encode(fareRules, forKey: .fareRules)
        }
        try container.encode(pending, forKey: .pending)
        if let openedAt {
            try container.encode(openedAt, forKey: .openedAt)
        }
        try container.encode(entries, forKey: .entries)
        try container.encode(days, forKey: .days)
    }
}
