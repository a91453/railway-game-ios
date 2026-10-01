import GameCore

// What the economy panel, the HUD and the inspector show of G1c
// (ARCHITECTURE decision 36): money in the reference's dollars, ledger rows,
// the last hour by item, and the passengers waiting at a station and riding
// a train. All of it is read from the world; nothing here is kept.

extension Money {
    /// The amount in whole dollars, as the reference shows money
    /// (`metroEconomyMoneyText`: `"$ " + Math.round(dollars)` with thousands
    /// separators), such as "$ 12,345" or "$ -1,428". `Money` counts cents;
    /// half a dollar rounds up, as `Math.round` does.
    public var moneyText: String {
        // floor((amount + 50) / 100), without overflowing near Int64.max.
        let remainder = amount % 100 + 50
        let dollars = amount / 100 + (remainder >= 100 ? 1 : remainder < 0 ? -1 : 0)
        return "$ " + Money(dollars).displayText
    }

    /// The exact amount in dollars and cents, such as "$ 0.55" or
    /// "$ 5.00": for fares, and where rounding to dollars would hide a
    /// difference (not enough cash).
    public var centsText: String {
        let cents = amount.magnitude % 100
        return "$ \(amount < 0 ? "-" : "")\(Money(Int64(amount.magnitude / 100)).displayText).\(cents < 10 ? "0" : "")\(cents)"
    }
}

extension EconomyMode {
    public var displayName: String {
        switch self {
        case .free: "Free play"
        case .management: "Management"
        }
    }
}

extension LedgerEntry.Kind {
    /// The reference's ledger labels (`economy.ledger.metroHourlyNet`,
    /// `metroDailyEnergy`, `metroDailyStaff`), in English.
    public var displayName: String {
        switch self {
        case .hourlyNet: "Hourly net"
        case .dailyEnergy: "Energy (daily)"
        case .dailyStaff: "Staff (daily)"
        }
    }
}

extension LedgerItem {
    /// The reference's item labels (`economy.group.metroFareRevenue`,
    /// `economy.ledger.metroRouteEnergy` and the others), in English.
    public var displayName: String {
        switch self {
        case .fareRevenue: "Fares"
        case .operatingCost: "Operating"
        case .maintenanceCost: "Maintenance"
        case .routeEnergy: "Line power and traction"
        case .trainEnergy: "Train power"
        case .stationStaff: "Station staff"
        case .trainStaff: "Drivers and dispatchers"
        }
    }
}

extension FinancePeriod {
    public var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }
}

extension LedgerEntry {
    /// The row's amount with its sign, such as "+$ 1,200" or "-$ 1,428".
    public var amountText: String {
        Self.signedMoneyText(amount)
    }

    static func signedMoneyText(_ amount: Money) -> String {
        let digits = amount.moneyText.dropFirst(2)
        return digits.hasPrefix("-") ? "-$ \(digits.dropFirst())" : "+$ \(digits)"
    }
}

extension FareRules {
    /// A one-line description, such as "Flat · $ 5.00" or "By distance ·
    /// 5 steps from $ 0.55".
    public var displayText: String {
        switch self {
        case .flat(let fare): "Flat · \(fare.centsText)"
        case .distance(let bands):
            bands.count == 1
                ? "By distance · 1 step, \(bands[0].fare.centsText)"
                : "By distance · \(bands.count) steps from \(bands[0].fare.centsText)"
        }
    }
}

/// One item's total over the last hour of the ledger.
public struct LedgerTotal: Hashable, Sendable {
    public let item: LedgerItem
    public let amount: Money

    public init(item: LedgerItem, amount: Money) {
        self.item = item
        self.amount = amount
    }

    /// The total with its sign, such as "+$ 1,200".
    public var amountText: String {
        LedgerEntry.signedMoneyText(amount)
    }
}

extension GameWorld {
    /// The ledger's totals by item for the rows written in the last
    /// `minutes` game minutes (the reference's panel sums the last 60), in
    /// item order, leaving out items with nothing.
    public func recentLedgerTotals(minutes: Int64 = 60) -> [LedgerTotal] {
        let since = clock.now.minutes - minutes
        var totals: [LedgerItem: Int64] = [:]
        for entry in accounts.entries where entry.time.minutes > since {
            for line in entry.breakdown {
                totals[line.item, default: 0] += line.amount.amount
            }
        }
        return LedgerItem.allCases.compactMap { item in
            guard let amount = totals[item], amount != 0 else { return nil }
            return LedgerTotal(item: item, amount: Money(amount))
        }
    }

    /// The last `count` ledger rows, newest first.
    public func recentLedgerEntries(_ count: Int = 12) -> [LedgerEntry] {
        Array(accounts.entries.suffix(count).reversed())
    }

    /// Who waits at station `id`, by line and the way they go, such as
    /// ["Main to Gamma · 120", "Main to Alpha · 30"]: lines by ID, outbound
    /// first. Empty if nobody waits.
    public func waitingText(at id: StationID) -> [String] {
        var counts: [LineID: [LineDirection: Int64]] = [:]
        for group in waitingPassengers(at: id) {
            counts[group.line, default: [:]][group.direction, default: 0] += group.count
        }
        return counts.keys.sorted().flatMap { lineID -> [String] in
            let line = self.line(id: lineID)
            return LineDirection.allCases.compactMap { direction in
                guard let count = counts[lineID]?[direction] else { return nil }
                let end = direction == .outbound ? line?.stops.last : line?.stops.first
                let towards = end.flatMap { station(id: $0)?.name }.map { " to \($0)" } ?? ""
                return "\(line?.name ?? "Line #\(lineID.rawValue)")\(towards) · \(count)"
            }
        }
    }

    /// How full train `id` is, such as "640 riding · 33%": riders over its
    /// rated capacity (cars × 320), rounded half up, as the reference's
    /// load. `nil` if nobody rides it (or there is no such train).
    public func loadText(of id: TrainID) -> String? {
        guard let train = train(id: id) else { return nil }
        let count = riders(of: id).reduce(Int64(0)) { $0 + $1.count }
        guard count > 0 else { return nil }
        let percent = (200 * count + train.ratedCapacity) / (2 * train.ratedCapacity)
        return "\(count) riding · \(percent)%"
    }
}
