import GameCore

// What the economy panel, the HUD and the inspector show of G1c
// (ARCHITECTURE decision 36): money in the reference's dollars, ledger rows,
// the last hour by item, and the passengers waiting at a station and riding
// a train, in English or Traditional Chinese (see ``DisplayLanguage``). All
// of it is read from the world; nothing here is kept.

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

extension GameWorld {
    /// What adding a car to a train costs, for the control that adds them:
    /// each car added is paid for and taking cars off pays nothing back, so
    /// stepping up, down and up again pays twice. `nil` when cars are free.
    public func carPriceText(in language: DisplayLanguage) -> String? {
        let price = economy.costs.car
        guard price > .zero else { return nil }
        return language.text(
            "Each car added costs \(price.moneyText); taking cars off refunds nothing.",
            "每加一節車廂 \(price.moneyText)；減少車廂不退費。"
        )
    }
}

extension EconomyMode {
    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .free: language.text("Free play", "自由模式")
        case .management: language.text("Management", "經營模式")
        }
    }
}

extension LedgerEntry.Kind {
    /// The reference's ledger labels (`economy.ledger.metroHourlyNet`,
    /// `metroDailyEnergy`, `metroDailyStaff`).
    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .hourlyNet: language.text("Hourly net", "小時淨額")
        case .dailyEnergy: language.text("Energy (daily)", "能源費用（日結）")
        case .dailyStaff: language.text("Staff (daily)", "員工費用（日結）")
        case .dailyInterest: language.text("Loan interest (daily)", "貸款利息（日結）")
        }
    }
}

extension LedgerItem {
    /// The reference's item labels (`economy.group.metroFareRevenue`,
    /// `economy.ledger.metroRouteEnergy` and the others).
    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .fareRevenue: language.text("Fares", "票價收入")
        case .operatingCost: language.text("Operating", "營運成本")
        case .maintenanceCost: language.text("Maintenance", "維護成本")
        case .routeEnergy: language.text("Line power and traction", "路線供電與牽引用電")
        case .trainEnergy: language.text("Train power", "列車日用電")
        case .stationStaff: language.text("Station staff", "車站員工")
        case .trainStaff: language.text("Drivers and dispatchers", "司機與調度員工")
        case .loanInterest: language.text("Loan interest", "貸款利息")
        }
    }
}

extension FinancePeriod {
    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .day: language.text("Day", "日")
        case .week: language.text("Week", "週")
        case .month: language.text("Month", "月")
        case .year: language.text("Year", "年")
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
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .flat(let fare):
            language.text("Flat · \(fare.centsText)", "固定票價 · \(fare.centsText)")
        case .distance(let bands):
            bands.count == 1
                ? language.text("By distance · 1 step, \(bands[0].fare.centsText)", "階梯票價 · 1 段，\(bands[0].fare.centsText)")
                : language.text(
                    "By distance · \(bands.count) steps from \(bands[0].fare.centsText)",
                    "階梯票價 · \(bands.count) 段，\(bands[0].fare.centsText) 起"
                )
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
        let since = clock.now.seconds - minutes * GameTime.secondsPerMinute
        var totals: [LedgerItem: Int64] = [:]
        for entry in accounts.entries where entry.time.seconds > since {
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
    public func waitingText(at id: StationID, in language: DisplayLanguage) -> [String] {
        var counts: [LineID: [LineDirection: Int64]] = [:]
        for group in waitingPassengers(at: id) {
            counts[group.line, default: [:]][group.direction, default: 0] += group.count
        }
        return counts.keys.sorted().flatMap { lineID -> [String] in
            let line = self.line(id: lineID)
            return LineDirection.allCases.compactMap { direction in
                guard let count = counts[lineID]?[direction] else { return nil }
                let end = direction == .outbound ? line?.stops.last : line?.stops.first
                let towards = end.flatMap { station(id: $0)?.name }.map { language.text(" to \($0)", " 往 \($0)") } ?? ""
                let name = line?.name ?? language.text("Line #\(lineID.rawValue)", "路線 #\(lineID.rawValue)")
                return "\(name)\(towards) · \(count)"
            }
        }
    }

    /// Who waits at station `id`, as one line for the inspector: "waiting
    /// Main to Gamma · 120, Main to Alpha · 30", or `nil` if nobody waits.
    public func waitingSummary(at id: StationID, in language: DisplayLanguage) -> String? {
        let groups = waitingText(at: id, in: language)
        guard !groups.isEmpty else { return nil }
        return language.text("waiting \(groups.joined(separator: ", "))", "候車 \(groups.joined(separator: "、"))")
    }

    /// How full train `id` is, such as "640 riding · 33%": riders over its
    /// rated capacity (cars × 320), rounded half up, as the reference's
    /// load (``TrainLoadInfo/percentage(passengers:capacity:)``). `nil` if
    /// nobody rides it (or there is no such train).
    public func loadText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let load = trainLoadInfo(of: id), load.passengerCount > 0 else { return nil }
        return language.text("\(load.passengerCount) riding · \(load.percentage)%", "載客 \(load.passengerCount) 人 · \(load.percentage)%")
    }

    /// How full train `id` is, for the load bar: its riders and its rated
    /// capacity (cars × 320, the reference's `cap`). `nil` for an unknown ID.
    public func trainLoadInfo(of id: TrainID) -> TrainLoadInfo? {
        guard let train = train(id: id) else { return nil }
        let count = riders(of: id).reduce(Int64(0)) { $0 + $1.count }
        return TrainLoadInfo(passengerCount: count, capacity: train.ratedCapacity)
    }

    /// How full the trains on the track are together, for the fleet
    /// overview's average load: the riders of every placed train over their
    /// rated capacities. A train off the track carries nobody and is not in
    /// service, so it counts in neither. `nil` when no train is placed.
    public func fleetLoadInfo() -> TrainLoadInfo? {
        let placed = trains.filter { $0.position != nil }
        guard !placed.isEmpty else { return nil }
        let count = placed.reduce(Int64(0)) { sum, train in sum + riders(of: train.id).reduce(0) { $0 + $1.count } }
        let capacity = placed.reduce(Int64(0)) { $0 + $1.ratedCapacity }
        return TrainLoadInfo(passengerCount: count, capacity: capacity)
    }
}

/// How full a train is, as the `Ci/` reference's train panel shows it
/// (`metro.train.load_factor`, `#pt-load` and the `.pax-bar-fill` bar):
///
///     u = e.cap ? Math.round((e.pax || 0) / e.cap * 100) : 0
///     bar width = Math.min(100, Math.max(0, u)) + "%"
///     u > 100 ? add("is-overload") : remove("is-overload")
///
/// The bar has one neutral colour and turns red only when the rounded
/// percentage is over 100 (`.pax-bar-fill.is-overload`); the reference has
/// no other load levels.
public struct TrainLoadInfo: Equatable, Hashable, Sendable {
    public let passengerCount: Int64
    /// The rated capacity, as the train has it (never adjusted for display).
    public let capacity: Int64
    /// The load in whole percent, rounded half up; 0 when the capacity is 0.
    public let percentage: Int

    public init(passengerCount: Int64, capacity: Int64) {
        self.passengerCount = passengerCount
        self.capacity = capacity
        self.percentage = Self.percentage(passengers: passengerCount, capacity: capacity)
    }

    /// The reference's `Math.round(pax / cap * 100)`, in integers (half up,
    /// as `Math.round` for these non-negative values), and 0 for a capacity
    /// of 0 or less (`e.cap ? … : 0`).
    public static func percentage(passengers: Int64, capacity: Int64) -> Int {
        guard capacity > 0 else { return 0 }
        return Int((200 * max(passengers, 0) + capacity) / (2 * capacity))
    }

    /// How much of the bar is filled, 0…1: the percentage clamped to
    /// 0…100 (`Math.min(100, Math.max(0, u))`).
    public var barFraction: Double {
        Double(min(100, max(0, percentage))) / 100
    }

    /// Whether the bar shows as overloaded (`is-overload`): only when the
    /// rounded percentage is over 100, as the reference decides it.
    public var isOverload: Bool {
        percentage > 100
    }
}


extension CompanyAccounts {
    /// What the company owes and what it costs (decision 67): "Loan
    /// $1,000,000 · $139 a day in interest", or "No loan".
    public func loanText(in language: DisplayLanguage) -> String {
        guard loan > .zero else { return language.text("No loan", "沒有貸款") }
        let interest = GameWorld.dailyLoanInterest(on: loan).moneyText
        return language.text("Loan \(loan.moneyText) · \(interest) a day in interest", "貸款 \(loan.moneyText) · 每日利息 \(interest)")
    }

    /// The terms: "$100,000 at a time, up to $5,000,000, at 5% a year".
    public static func loanTermsText(in language: DisplayLanguage) -> String {
        let rate = "\(interestBasisPoints / 100)%"
        return language.text(
            "\(loanStep.moneyText) at a time, up to \(maximumLoan.moneyText), at \(rate) a year, paid daily",
            "每次 \(loanStep.moneyText)，最多 \(maximumLoan.moneyText)，年利率 \(rate)，每日支付"
        )
    }
}
