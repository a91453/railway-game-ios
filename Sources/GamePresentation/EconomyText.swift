import GameCore

// What the economy panel, the HUD and the inspector show of G1c
// (ARCHITECTURE decision 36): money in the reference's dollars, ledger rows,
// the last hour by item, and the passengers waiting at a station and riding
// a train, in English or Traditional Chinese (see ``DisplayLanguage``). All
// of it is read from the world; nothing here is kept.

extension Money {
    /// The sign every amount of money the game shows begins with. Every
    /// amount is written by the functions here (``moneyText``,
    /// ``wholeText``, ``centsText``, ``signedText``,
    /// ``TrainRoster/shortMoney(_:in:)``), never with a `$` of its own, so
    /// the currency changes in one place (`MoneyTextSourceTests`).
    /// New Taiwan dollars: the currency of where the map is (decisions 499
    /// and 523).
    public static let currencySymbol = "NT$"

    /// New Taiwan dollars to one US dollar, for the rough reference the
    /// English interface shows beside large amounts (decision 523). A
    /// round figure, not a live rate.
    public static let usDollarReferenceRate: Int64 = 30

    /// The smallest amount, either way, that gets the US dollar
    /// reference: NT$1,000. Fares, a day pass and other small amounts
    /// are read in New Taiwan dollars alone.
    public static let usDollarReferenceMinimum = Money(100_000)

    /// "≈ US$300,000" beside a large amount in the English interface, the
    /// New Taiwan dollars ÷ ``usDollarReferenceRate`` to the nearest whole
    /// US dollar (half up, as ``moneyText`` rounds); `nil` in Chinese and
    /// for an amount under ``usDollarReferenceMinimum`` (decision 523).
    /// Only shown: every amount the player enters stays in NT$. The space
    /// after "≈" does not break, so a wrapped line keeps the two together.
    public func usDollarReferenceText(in language: DisplayLanguage) -> String? {
        guard language == .english, amount.magnitude >= Self.usDollarReferenceMinimum.amount.magnitude else { return nil }
        let centsPerDollar = Self.usDollarReferenceRate * 100
        let remainder = amount % centsPerDollar + centsPerDollar / 2
        let dollars = amount / centsPerDollar + (remainder >= centsPerDollar ? 1 : remainder < 0 ? -1 : 0)
        return "≈\u{00A0}US$" + dollars.groupedText
    }

    /// ``moneyText`` with the US dollar reference after it where there is
    /// one: "NT$ 9,000,000 (≈ US$300,000)" in English, "NT$ 9,000,000" in
    /// Chinese (decision 523).
    public func moneyTextWithReference(in language: DisplayLanguage) -> String {
        usDollarReferenceText(in: language).map { "\(moneyText) (\($0))" } ?? moneyText
    }

    /// The amount as the Chinese interface writes it where room is short
    /// or the figure is large (decision 523, continued): from NT$10,000
    /// in 萬 to one decimal ("NT$ 900 萬", "NT$ 1,234.6 萬"), from 1 億
    /// in 億 to two ("NT$ 1.23 億"), rounded half away from zero, with no
    /// trailing zero after the point; below NT$10,000, and in English,
    /// ``moneyText``. The cash in the status bar, the economy panel's
    /// balance, the price of a build and the new game's starting cash;
    /// the ledger and the statements keep every dollar.
    public func compactText(in language: DisplayLanguage) -> String {
        let dollars = wholeDollars
        let size = dollars.magnitude
        guard language == .traditionalChinese, size >= 10_000 else { return moneyText }
        let sign = dollars < 0 ? "-" : ""
        // Thousands are tenths of 萬; a figure that rounds up to 10,000
        // 萬 is written as 1 億.
        let thousands = (size + 500) / 1_000
        let figure = thousands < 100_000
            ? Self.decimalText(thousands, places: 1) + " 萬"
            : Self.decimalText((size + 500_000) / 1_000_000, places: 2) + " 億"
        return Self.currencySymbol + " " + sign + figure
    }

    /// ``compactText(in:)`` with the US dollar reference after it in
    /// English (``moneyTextWithReference(in:)``): the new game's starting
    /// cash.
    public func compactTextWithReference(in language: DisplayLanguage) -> String {
        usDollarReferenceText(in: language).map { "\(moneyText) (\($0))" } ?? compactText(in: language)
    }

    /// `value` with its last `places` digits after a point, thousands
    /// grouped, trailing zeros after the point dropped: "1,234.6", "900".
    static func decimalText(_ value: UInt64, places: Int) -> String {
        var unit: UInt64 = 1
        for _ in 0..<places { unit *= 10 }
        var fraction = String(value % unit)
        fraction = String(repeating: "0", count: places - fraction.count) + fraction
        while fraction.last == "0" { fraction.removeLast() }
        return (value / unit).groupedText + (fraction.isEmpty ? "" : "." + fraction)
    }

    /// What the English interface says once about the currency, beside
    /// the balance; `nil` in Chinese (decision 523).
    public static func currencyNoteText(in language: DisplayLanguage) -> String? {
        language == .english ? "Prices are in New Taiwan dollars (NT$); the US$ figures are a rough guide." : nil
    }

    /// The amount in whole dollars, as the reference shows money
    /// (`metroEconomyMoneyText`: `"$ " + Math.round(dollars)` with thousands
    /// separators), such as "$ 12,345" or "$ -1,428". `Money` counts cents;
    /// half a dollar rounds up, as `Math.round` does.
    public var moneyText: String {
        Self.currencySymbol + " " + wholeDollars.groupedText
    }

    /// The amount in whole dollars written into a sentence, with no space
    /// after the sign, such as "$5,000,000" or "$-1,428": the targets and
    /// starting cash in achievements, challenges and help.
    public var wholeText: String {
        Self.currencySymbol + wholeDollars.groupedText
    }

    /// The amount with its sign in front of the currency, as a ledger row
    /// shows it: "+$ 1,200", "-$ 1,428"; a loss under half a dollar is
    /// still "-$ 0".
    public var signedText: String {
        let dollars = wholeDollars
        let sign = dollars < 0 || amount < 0 ? "-" : "+"
        return sign + Self.currencySymbol + " " + dollars.magnitude.groupedText
    }

    /// A round amount in words, for the targets a story names: "$300
    /// million" or "3 億"; ``wholeText`` when it is not that round.
    public func roundText(in language: DisplayLanguage) -> String {
        let dollars = wholeDollars
        let english = dollars != 0 && dollars % 1_000_000 == 0
            ? "\(Self.currencySymbol)\(dollars / 1_000_000) million" : wholeText
        let chinese = dollars != 0 && dollars % 100_000_000 == 0
            ? "\(dollars / 100_000_000) 億" : dollars != 0 && dollars % 10_000 == 0 ? "\(dollars / 10_000) 萬" : wholeText
        return language.text(english, chinese)
    }

    /// The whole dollars, `floor((amount + 50) / 100)` as `Math.round`
    /// takes them, without overflowing near `Int64.max`.
    var wholeDollars: Int64 {
        let remainder = amount % 100 + 50
        return amount / 100 + (remainder >= 100 ? 1 : remainder < 0 ? -1 : 0)
    }

    /// The exact amount in dollars and cents, such as "$ 0.55" or
    /// "$ 5.00": for fares, and where rounding to dollars would hide a
    /// difference (not enough cash, ``shortfallTexts(required:available:)``).
    public var centsText: String {
        let cents = amount.magnitude % 100
        return Self.currencySymbol + " \(amount < 0 ? "-" : "")\((amount.magnitude / 100).groupedText).\(cents < 10 ? "0" : "")\(cents)"
    }

    /// What a refusal for want of cash says `required` and `available`
    /// are: whole dollars, as the cash and the ✓ price show them
    /// (``moneyText``), unless rounding would make the two look enough,
    /// when both are in cents (``centsText``).
    public static func shortfallTexts(required: Money, available: Money) -> (required: String, available: String) {
        required.wholeDollars > available.wholeDollars
            ? (required.moneyText, available.moneyText)
            : (required.centsText, available.centsText)
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

extension GameEconomy {
    /// The cash as the HUD and the economy panel show it: the balance, or
    /// "∞" with free play's unlimited funds (decision 200).
    public var cashText: String {
        unlimitedFunds ? "∞" : balance.moneyText
    }

    /// ``cashText`` in 萬／億 in Chinese (``Money/compactText(in:)``): the
    /// status bar and the economy panel's balance (decision 523, continued).
    public func cashText(in language: DisplayLanguage) -> String {
        unlimitedFunds ? "∞" : balance.compactText(in: language)
    }

    /// Whether the cash is shown as in the red: never with unlimited funds.
    public var showsInTheRed: Bool {
        !unlimitedFunds && balance < .zero
    }

    /// Why a game with unlimited funds has no achievements or rank.
    public static func uncountedText(in language: DisplayLanguage) -> String {
        language.text("Games with unlimited funds do not count for achievements or the company rank.", "資金無限的局不計成就與公司評等。")
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
        case .dailyProperty: language.text("Buildings (daily)", "建物收支（日結）")
        case .buildingDemolition: language.text("Building demolished", "拆除建物")
        case .dailyTax: language.text("Income tax (daily)", "營利事業所得稅（日結）")
        case .hourlyFreight: language.text("Freight (hourly)", "貨運收入（小時）")
        case .dailySubsidiary: language.text("Subsidiaries (daily)", "子公司營業（日結）")
        case .dailyTourism: language.text("Souvenir shops (daily)", "名產店收支（日結）")
        case .monthlySubsidy: language.text("City subsidies (monthly)", "城市補助金（月初）")
        case .dailyDepot: language.text("Depots (daily)", "機廠維護（日結）")
        case .dailyStationCommerce: language.text("Station shops (daily)", "車站商業收支（日結）")
        case .dailyDayPass: language.text("Day passes (daily)", "一日週遊券（日結）")
        case .dailyBuses: language.text("Buses (daily)", "公車（日結）")
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
        case .propertyRent: language.text("Rent", "租金收入")
        case .propertyUpkeep: language.text("Building upkeep", "建物維護")
        case .propertyTax: language.text("Land tax", "土地資產稅")
        case .propertyDemolition: language.text("Demolition", "拆除費")
        case .incomeTax: language.text("Income tax", "營利事業所得稅")
        case .freightRevenue: language.text("Freight", "貨運收入")
        case .subsidiarySales: language.text("Subsidiary sales", "子公司營業收入")
        case .subsidiaryCost: language.text("Subsidiary costs", "子公司營業成本")
        case .tourismRevenue: language.text("Souvenir sales", "名產店收入")
        case .tourismUpkeep: language.text("Souvenir shop upkeep", "名產店維護")
        case .subsidy: language.text("City subsidies", "城市補助金")
        case .depotUpkeep: language.text("Depot sidings", "機廠停車線維護")
        case .stationCommerceRevenue: language.text("Station shop takings", "車站商業收入")
        case .stationCommerceUpkeep: language.text("Station shop upkeep", "車站商業維護")
        case .dayPassSales: language.text("Day pass sales", "週遊券收入")
        case .dayPassFares: language.text("Fares the passes covered", "週遊券抵用的車資")
        case .busFares: language.text("Bus fares", "公車票收")
        case .busRunning: language.text("Bus running costs", "公車營運成本")
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
        amount.signedText
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
        amount.signedText
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

    /// Decision 471 (UI health check K, 3-21): the last `count` ledger
    /// rows, newest first, each with an ID that stays the row's while newer
    /// rows come in above it (``LedgerRow/ID``), so the economy panel's
    /// list keeps each row, and VoiceOver's place in it, when one is added.
    public func recentLedgerRows(_ count: Int = 12) -> [LedgerRow] {
        // How many rows of each time and kind came before.
        var before: [LedgerRow.ID: Int] = [:]
        let rows = accounts.entries.map { entry -> LedgerRow in
            let first = LedgerRow.ID(time: entry.time, kind: entry.kind, ordinal: 0)
            let ordinal = before[first, default: 0]
            before[first] = ordinal + 1
            return LedgerRow(id: LedgerRow.ID(time: entry.time, kind: entry.kind, ordinal: ordinal), entry: entry)
        }
        return Array(rows.suffix(count).reversed())
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

    /// Who waits at station `id` for the inspector card, one line each so a
    /// narrow card wraps none of them away: "waiting" first, then up to
    /// `maxGroups` of ``waitingText(at:in:)`` (the busiest are not sorted
    /// out: lines by ID), and "+2 more" if there are more (the station
    /// panel lists them all). Empty if nobody waits.
    public func waitingLines(at id: StationID, maxGroups: Int = 3, in language: DisplayLanguage) -> [String] {
        let groups = waitingText(at: id, in: language)
        guard !groups.isEmpty else { return [] }
        var lines = [language.text("Waiting", "候車")] + groups.prefix(maxGroups)
        if groups.count > maxGroups {
            let rest = groups.count - maxGroups
            lines.append(language.text("+\(rest) more", "還有 \(rest) 項"))
        }
        return lines
    }

    /// Whether train `id`'s load is tons: it is on a freight line, or was
    /// and still has cargo on board, which is lost at the next whole hour
    /// (decision 155); for that hour it read "riding 0".
    func carriesFreight(_ id: TrainID) -> Bool {
        isFreightTrain(id) || cargoOnBoard(of: id) > 0
    }

    /// How full train `id` is, such as "640 riding · 33%": riders over its
    /// rated capacity (cars × 320), rounded half up, as the reference's
    /// load (``TrainLoadInfo/percentage(passengers:capacity:)``). `nil` if
    /// nobody rides it (or there is no such train).
    public func loadText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let load = trainLoadInfo(of: id), load.passengerCount > 0 else { return nil }
        // Decision 155: a freight train's load is its tons.
        if carriesFreight(id) {
            return language.text("\(load.passengerCount) t aboard · \(load.percentage)%", "載貨 \(load.passengerCount) 噸 · \(load.percentage)%")
        }
        return language.text("\(load.passengerCount) riding · \(load.percentage)%", "載客 \(load.passengerCount) 人 · \(load.percentage)%")
    }

    /// How full train `id` is, for the load bar: its riders and its rated
    /// capacity (cars × 320, the reference's `cap`). `nil` for an unknown ID.
    public func trainLoadInfo(of id: TrainID) -> TrainLoadInfo? {
        guard let train = train(id: id) else { return nil }
        // Decision 155: a freight train's tons over its cars' tons.
        if carriesFreight(id) {
            return TrainLoadInfo(passengerCount: cargoOnBoard(of: id), capacity: Self.freightCapacity(cars: train.cars), isFreight: true)
        }
        let count = riders(of: id).reduce(Int64(0)) { $0 + $1.count }
        return TrainLoadInfo(passengerCount: count, capacity: train.ratedCapacity)
    }

    /// How full the trains on the track are together, for the fleet
    /// overview's average load: the riders of every placed train over their
    /// rated capacities. A train off the track carries nobody and is not in
    /// service, so it counts in neither. `nil` when no train is placed.
    public func fleetLoadInfo() -> TrainLoadInfo? {
        // Decision 155: freight trains carry tons, not riders.
        let placed = trains.filter { $0.position != nil && !carriesFreight($0.id) }
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
    /// The riders, or a freight train's tons aboard (``isFreight``).
    public let passengerCount: Int64
    /// The rated capacity, as the train has it (never adjusted for display):
    /// riders, or a freight train's tons.
    public let capacity: Int64
    /// The load in whole percent, rounded half up; 0 when the capacity is 0.
    public let percentage: Int
    /// Whether this is a freight train's cargo in tons (decision 155), not
    /// riders.
    public let isFreight: Bool

    public init(passengerCount: Int64, capacity: Int64, isFreight: Bool = false) {
        self.passengerCount = passengerCount
        self.capacity = capacity
        self.percentage = Self.percentage(passengers: passengerCount, capacity: capacity)
        self.isFreight = isFreight
    }

    /// The bar's title: "Load Factor", or "Cargo Load" for a freight train.
    public func titleText(in language: DisplayLanguage) -> String {
        isFreight ? language.text("Cargo Load", "載貨率") : language.text("Load Factor", "載客率")
    }

    /// The caption under the bar, the reference's rated capacity and current
    /// passengers rows (`#pt-cap`, `#pt-pax`) as one line; a freight train's
    /// in tons.
    public func detailText(in language: DisplayLanguage) -> String {
        isFreight
            ? language.text(
                "Current cargo \(passengerCount) t · Rated load \(capacity) t",
                "當前載貨 \(passengerCount) 噸 · 額定載重 \(capacity) 噸"
            )
            : language.text(
                "Current passengers \(passengerCount) · Rated capacity \(capacity)",
                "當前載客 \(passengerCount) · 額定載客 \(capacity)"
            )
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

    /// The tax (decision 131): "Income tax: 50% of each day's profit
    /// before tax beyond $ 100,000, paid at midnight".
    public static func taxTermsText(in language: DisplayLanguage) -> String {
        language.text(
            "Income tax: \(taxPercent)% of each day's profit before tax beyond \(taxFreeProfit.moneyText), paid at midnight",
            "營利事業所得稅：每天的稅前淨利超過 \(taxFreeProfit.moneyText) 的部分課 \(taxPercent)%，午夜支付"
        )
    }
}

/// A ledger row with a stable ID (``GameWorld/recentLedgerRows(_:)``).
public struct LedgerRow: Identifiable, Hashable, Sendable {
    /// The row's time and kind, and how many kept rows of the same time and
    /// kind come before it (several demolitions in one moment). Rows are
    /// written in time order and only the oldest are let go, so a row's ID
    /// changes only if a row of its own time and kind is let go before it.
    public struct ID: Hashable, Sendable {
        public let time: GameTime
        public let kind: LedgerEntry.Kind
        public let ordinal: Int
    }

    public let id: ID
    public let entry: LedgerEntry
}
