// The company's fixed assets, depreciation, balance sheet and year-end
// closing (Phase 7a, ARCHITECTURE decision 85).
//
// The owner's `Ci/` reference
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`) builds three
// statements for its finance dashboard: an income statement
// (`flowDashboardBuildModeIncomeStatement`), a cash flow statement with
// operating and investing activities (`flowDashboardBuildModeCashFlowStatement`)
// and a balance sheet of cash, quotas and an asset valuation it leaves at 0
// (`balanceSheet: {cash, metroQuotas, …, assetValuation: 0}`). It has no
// cost of an asset, no depreciation and no closing of a year; those are
// native here: every track edge, station, train and car bought keeps what
// was paid for it, written down straight-line over its life, and every
// 360-day year closes into a statement with the balance sheet at its end.
// Every amount is whole cents (decision 36).

/// What a fixed asset is, for the balance sheet.
public enum AssetClass: String, CaseIterable, Codable, Sendable {
    /// Track and its structures.
    case track
    case stations
    /// Trains and the cars added to them.
    case rollingStock
    /// The company's buildings, with the right to use the land under them
    /// (decision 94).
    case buildings

    /// The days an asset of the class is written down over, to nothing:
    /// track and stations 20 of the finance report's 360-day years, trains
    /// and cars 10 (native, Phase 7a), buildings 30 (decision 94).
    public var lifeDays: Int64 {
        switch self {
        case .track, .stations: 20 * FinancePeriod.year.days
        case .rollingStock: 10 * FinancePeriod.year.days
        case .buildings: 30 * FinancePeriod.year.days
        }
    }
}

/// One thing the company bought, at the price it paid (Phase 7a).
public struct AssetRecord: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        /// A track edge, ``owner`` its number.
        case track
        /// A station, ``owner`` its ID.
        case station
        /// A train with its first car, ``owner`` its ID.
        case train
        /// Cars added to train ``owner`` at once (``cars`` of them).
        case cars
        /// A building the player placed, ``owner`` its ID (decision 94).
        case building

        public var assetClass: AssetClass {
            switch self {
            case .track: .track
            case .station: .stations
            case .train, .cars: .rollingStock
            case .building: .buildings
            }
        }
    }

    public let kind: Kind
    /// The edge's number, the station's or the train's ID.
    public let owner: Int
    /// How many cars a ``Kind/cars`` record holds; 0 for the others.
    public internal(set) var cars: Int
    /// When it was bought.
    public let acquired: GameTime
    /// What was paid for it (its part, after a split edge or cars taken off).
    public internal(set) var cost: Money
    /// How much of ``cost`` has been written down.
    public internal(set) var depreciation: Money
    /// The days it has been written down for: only managed days count.
    public internal(set) var days: Int64

    init(kind: Kind, owner: Int, cars: Int = 0, acquired: GameTime, cost: Money) {
        self.kind = kind
        self.owner = owner
        self.cars = cars
        self.acquired = acquired
        self.cost = cost
        depreciation = .zero
        days = 0
    }

    /// What is left of the cost on the books.
    public var bookValue: Money {
        cost - depreciation
    }

    /// Writes the asset down for one more day and returns the day's charge:
    /// straight-line, so that after `d` days of a life of `L` the written
    /// down total is `cost × d ÷ L` rounded down, and all of it at the end.
    /// A part of a split edge can be a cent ahead of its own schedule; it
    /// is then charged nothing until the schedule catches up.
    mutating func depreciateOneDay() -> Money {
        let life = kind.assetClass.lifeDays
        guard days < life else { return .zero }
        days += 1
        let due = Self.share(of: cost, numerator: days, denominator: life)
        guard due > depreciation else { return .zero }
        let charge = due - depreciation
        depreciation = due
        return charge
    }

    /// `amount × numerator ÷ denominator`, rounded down, exactly: for
    /// `0 <= numerator <= denominator` and a non-negative amount.
    static func share(of amount: Money, numerator: Int64, denominator: Int64) -> Money {
        let product = amount.amount.multipliedFullWidth(by: numerator)
        return Money(denominator.dividingFullWidth((high: product.high, low: product.low)).quotient)
    }
}

/// What the company's assets of one class cost and how far they are
/// written down.
public struct AssetClassBalance: Hashable, Codable, Sendable {
    public let cost: Money
    public let depreciation: Money

    public init(cost: Money, depreciation: Money) {
        self.cost = cost
        self.depreciation = depreciation
    }

    public static let zero = AssetClassBalance(cost: .zero, depreciation: .zero)

    public var bookValue: Money {
        cost - depreciation
    }
}

/// The company's balance sheet (the reference's `balanceSheet`, with the
/// asset valuation it leaves at 0 filled in from the asset records): its
/// cash, its fixed assets at book value, its loan and what is left, its
/// equity. `totalAssets == loan + equity` always.
public struct BalanceSheet: Hashable, Sendable {
    /// The balance, which may be below zero.
    public let cash: Money
    public let track: AssetClassBalance
    public let stations: AssetClassBalance
    public let rollingStock: AssetClassBalance
    /// The company's buildings (decision 94).
    public let buildings: AssetClassBalance
    public let loan: Money

    public init(
        cash: Money, track: AssetClassBalance, stations: AssetClassBalance, rollingStock: AssetClassBalance,
        buildings: AssetClassBalance = .zero, loan: Money
    ) {
        self.cash = cash
        self.track = track
        self.stations = stations
        self.rollingStock = rollingStock
        self.buildings = buildings
        self.loan = loan
    }

    public subscript(assetClass: AssetClass) -> AssetClassBalance {
        switch assetClass {
        case .track: track
        case .stations: stations
        case .rollingStock: rollingStock
        case .buildings: buildings
        }
    }

    /// The fixed assets at book value.
    public var fixedAssets: Money {
        track.bookValue + stations.bookValue + rollingStock.bookValue + buildings.bookValue
    }

    public var totalAssets: Money {
        cash + fixedAssets
    }

    /// What the company is worth: its assets less what it owes.
    public var equity: Money {
        totalAssets - loan
    }
}

/// A closed year (Phase 7a): its income statement, cash flows and the
/// balance sheet at its end. The finance report keeps only two years of
/// days, so a year's closing is kept as it was.
public struct AnnualStatement: Hashable, Codable, Sendable {
    /// The year's index: day ÷ 360, rounded down.
    public let year: Int64
    public let income: FinanceSummary
    public let closing: BalanceSheet

    public init(year: Int64, income: FinanceSummary, closing: BalanceSheet) {
        self.year = year
        self.income = income
        self.closing = closing
    }
}

/// One day's movements that are not the running ledger's (Phase 7a): the
/// assets written down and off, what was spent on new ones, and what was
/// borrowed and repaid. All non-negative.
public struct CapitalDay: Hashable, Sendable {
    /// The day's index, as ``DayAccount/day``.
    public let day: Int64
    /// Assets written down, by the day's depreciation.
    public internal(set) var depreciation: Money = .zero
    /// The book value of assets removed (track or stations demolished,
    /// cars taken off): nothing is refunded, so it is a loss.
    public internal(set) var writeOff: Money = .zero
    /// Cash paid for track, stations, trains and cars.
    public internal(set) var capitalSpending: Money = .zero
    public internal(set) var borrowed: Money = .zero
    public internal(set) var repaid: Money = .zero

    public init(day: Int64) {
        self.day = day
    }

    var amounts: [Money] {
        [depreciation, writeOff, capitalSpending, borrowed, repaid]
    }
}

extension CompanyAccounts {
    /// Two years of capital days, as of ledger days.
    public static let keptCapitalDays = keptDays
    /// The reference's yearly report goes back 50 years
    /// (`FLOW_DASHBOARD_FINANCE_BUCKETS`, `max: 50`).
    public static let keptYears = 50
    /// The most the asset records may have cost together, far beyond any
    /// game: small enough that the balance sheet's sums never overflow.
    public static let maximumAssetCost: Int64 = GameWorld.maximumAccrued

    /// Adds `change` to day `day`'s capital movements, each total stopping
    /// at the most a save holds, keeping the latest days.
    mutating func bookCapital(day: Int64, _ change: (inout CapitalDay) -> Void) {
        let index: Int
        if let known = capitalDays.firstIndex(where: { $0.day == day }) {
            index = known
        } else {
            index = capitalDays.firstIndex { $0.day > day } ?? capitalDays.count
            capitalDays.insert(CapitalDay(day: day), at: index)
        }
        change(&capitalDays[index])
        let limit = Money(GameWorld.maximumAccrued)
        capitalDays[index].depreciation = min(capitalDays[index].depreciation, limit)
        capitalDays[index].writeOff = min(capitalDays[index].writeOff, limit)
        capitalDays[index].capitalSpending = min(capitalDays[index].capitalSpending, limit)
        capitalDays[index].borrowed = min(capitalDays[index].borrowed, limit)
        capitalDays[index].repaid = min(capitalDays[index].repaid, limit)
        capitalDays.removeAll { $0.day <= day - Int64(Self.keptCapitalDays) }
    }

    /// What the asset records cost together.
    var totalAssetCost: Int64 {
        assets.reduce(0) { $0 + $1.cost.amount }
    }

    /// The asset records' totals by class.
    func assetBalance(_ assetClass: AssetClass) -> AssetClassBalance {
        var cost = Money.zero
        var depreciation = Money.zero
        for record in assets where record.kind.assetClass == assetClass {
            cost = cost + record.cost
            depreciation = depreciation + record.depreciation
        }
        return AssetClassBalance(cost: cost, depreciation: depreciation)
    }
}

extension GameWorld {
    // MARK: - Queries

    /// The balance sheet now.
    public func balanceSheet() -> BalanceSheet {
        BalanceSheet(
            cash: economy.balance, track: accounts.assetBalance(.track), stations: accounts.assetBalance(.stations),
            rollingStock: accounts.assetBalance(.rollingStock), buildings: accounts.assetBalance(.buildings), loan: accounts.loan
        )
    }

    /// How many track edges, stations and trains have no asset record: built
    /// before save version 16 kept what they cost, or in free play, so they
    /// are on the balance sheet at nothing (Phase 7a).
    public func unrecordedAssetCount() -> Int {
        var recorded: [AssetRecord.Kind: Set<Int>] = [:]
        for record in accounts.assets where record.kind != .cars {
            recorded[record.kind, default: []].insert(record.owner)
        }
        let edges = network.edges.count { !(recorded[.track]?.contains($0.id.networkNumber ?? 0) ?? false) }
        let stations = stations.count { !(recorded[.station]?.contains($0.id.rawValue) ?? false) }
        let trains = trains.count { !(recorded[.train]?.contains($0.id.rawValue) ?? false) }
        return edges + stations + trains
    }

    // MARK: - Recording

    /// Records an asset a managed company bought now for `cost`, and the
    /// cash paid for it. Free play keeps no accounts (the reference's
    /// creative mode "does not compute finances"), so what it builds has no
    /// record. The records' total stops at
    /// ``CompanyAccounts/maximumAssetCost``.
    mutating func acquireAsset(_ kind: AssetRecord.Kind, owner: Int, cars: Int = 0, cost: Money) {
        guard accounts.mode == .management else { return }
        let room = CompanyAccounts.maximumAssetCost - accounts.totalAssetCost
        let recorded = Money(max(0, min(cost.amount, room)))
        accounts.assets.append(AssetRecord(kind: kind, owner: owner, cars: cars, acquired: clock.now, cost: recorded))
        if cost > .zero {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + cost }
        }
    }

    /// Removes the record of the track edge or station gone, writing off
    /// its book value for a managed company: removal refunds nothing.
    mutating func disposeAsset(_ kind: AssetRecord.Kind, owner: Int) {
        var lost = Money.zero
        accounts.assets.removeAll { record in
            guard record.kind == kind, record.owner == owner else { return false }
            lost = lost + record.bookValue
            return true
        }
        writeOff(lost)
    }

    /// Splits the record of edge `edge` between its parts `first` and
    /// `second`, by their lengths: each part keeps its share of the cost and
    /// of the depreciation, rounded down for the first, the rest to the
    /// second, and the days and purchase time of the whole.
    mutating func splitTrackAsset(_ edge: Int, into first: (edge: Int, length: Int64), _ second: (edge: Int, length: Int64)) {
        guard let index = accounts.assets.firstIndex(where: { $0.kind == .track && $0.owner == edge }) else { return }
        let whole = accounts.assets[index]
        let total = first.length + second.length
        func part(_ owner: Int, cost: Money, depreciation: Money) -> AssetRecord {
            var record = AssetRecord(kind: .track, owner: owner, acquired: whole.acquired, cost: cost)
            record.depreciation = depreciation
            record.days = whole.days
            return record
        }
        let firstCost = AssetRecord.share(of: whole.cost, numerator: first.length, denominator: total)
        let firstDepreciation = AssetRecord.share(of: whole.depreciation, numerator: first.length, denominator: total)
        accounts.assets.replaceSubrange(index...index, with: [
            part(first.edge, cost: firstCost, depreciation: firstDepreciation),
            part(second.edge, cost: whole.cost - firstCost, depreciation: whole.depreciation - firstDepreciation),
        ])
    }

    /// Takes `count` cars off train `train`'s records, the latest bought
    /// first, writing off their share of each record's book value.
    mutating func removeCarAssets(of train: Int, count: Int) {
        var left = count
        var lost = Money.zero
        for index in accounts.assets.indices.reversed() where left > 0 {
            let record = accounts.assets[index]
            guard record.kind == .cars, record.owner == train else { continue }
            let taken = min(left, record.cars)
            left -= taken
            let cost = AssetRecord.share(of: record.cost, numerator: Int64(taken), denominator: Int64(record.cars))
            let depreciation = AssetRecord.share(of: record.depreciation, numerator: Int64(taken), denominator: Int64(record.cars))
            lost = lost + cost - depreciation
            accounts.assets[index].cars -= taken
            accounts.assets[index].cost = record.cost - cost
            accounts.assets[index].depreciation = record.depreciation - depreciation
        }
        accounts.assets.removeAll { $0.kind == .cars && $0.cars == 0 }
        writeOff(lost)
    }

    private mutating func writeOff(_ amount: Money) {
        guard accounts.mode == .management, amount > .zero else { return }
        accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.writeOff = $0.writeOff + amount }
    }

    /// Books cash borrowed or repaid for a managed company.
    mutating func bookLoan(borrowed: Money = .zero, repaid: Money = .zero) {
        guard accounts.mode == .management else { return }
        accounts.bookCapital(day: dayIndex(of: clock.now)) {
            $0.borrowed = $0.borrowed + borrowed
            $0.repaid = $0.repaid + repaid
        }
    }

    // MARK: - Settlement

    /// Writes every asset down for day `day`, which just ended.
    mutating func depreciateAssets(day: Int64) {
        var charge = Money.zero
        for index in accounts.assets.indices {
            charge = charge + accounts.assets[index].depreciateOneDay()
        }
        guard charge > .zero else { return }
        accounts.bookCapital(day: day) { $0.depreciation = $0.depreciation + charge }
    }

    /// Closes the year that ended with day `day`, when it was a year's last:
    /// its income statement and the balance sheet now, keeping the latest
    /// ``CompanyAccounts/keptYears``.
    mutating func closeYear(endingWith day: Int64) {
        let year = FinancePeriod.year.days
        guard CompanyAccounts.floorDivide(day + 1, year) * year == day + 1 else { return }
        let statement = AnnualStatement(
            year: CompanyAccounts.floorDivide(day, year), income: accounts.report(.year, day: day).current, closing: balanceSheet()
        )
        accounts.years.append(statement)
        if accounts.years.count > CompanyAccounts.keptYears {
            accounts.years.removeFirst(accounts.years.count - CompanyAccounts.keptYears)
        }
    }

    // MARK: - Validation

    /// Why the asset records, capital days or closed years break a Phase 7a
    /// rule, or `nil`.
    func assetsProblem() -> String? {
        var owners: Set<String> = []
        var carsByTrain: [Int: Int] = [:]
        var total: Int64 = 0
        for record in accounts.assets {
            let exists = switch record.kind {
            case .track: network.edge(.edge(record.owner)) != nil
            case .station: station(id: StationID(rawValue: record.owner)) != nil
            case .train, .cars: train(id: TrainID(rawValue: record.owner)) != nil
            case .building: placedBuilding(id: PlacedBuildingID(rawValue: record.owner)) != nil
            }
            guard exists else { return "An asset record names a \(record.kind.rawValue) that does not exist." }
            if record.kind == .cars {
                guard record.cars >= 1 else { return "A record of cars must hold at least one." }
                carsByTrain[record.owner, default: 0] += record.cars
            } else {
                guard record.cars == 0, owners.insert("\(record.kind.rawValue) \(record.owner)").inserted else {
                    return "Each track edge, station and train has at most one asset record."
                }
            }
            guard record.acquired <= clock.now, (0...record.kind.assetClass.lifeDays).contains(record.days),
                  record.cost >= .zero, (.zero...record.cost).contains(record.depreciation) else {
                return "An asset record's cost, depreciation, days or purchase time is out of range."
            }
            let (sum, overflow) = total.addingReportingOverflow(record.cost.amount)
            guard !overflow, sum <= CompanyAccounts.maximumAssetCost else { return "The asset records cost more than they may." }
            total = sum
        }
        for (owner, cars) in carsByTrain {
            guard let train = train(id: TrainID(rawValue: owner)), cars <= train.cars - Train.minimumCars else {
                return "A train's records hold more cars than it has."
            }
        }
        let days = accounts.capitalDays
        guard days.count <= CompanyAccounts.keptCapitalDays,
              zip(days, days.dropFirst()).allSatisfy({ $0.day < $1.day }),
              days.last.map({ $0.day <= dayIndex(of: clock.now) }) ?? true,
              days.allSatisfy({ $0.amounts.allSatisfy { (0...Self.maximumAccrued).contains($0.amount) } })
        else { return "Capital days must be listed once each, by ascending day, none after today, and within bounds." }
        let years = accounts.years
        let currentYear = CompanyAccounts.floorDivide(dayIndex(of: clock.now), FinancePeriod.year.days)
        guard years.count <= CompanyAccounts.keptYears,
              zip(years, years.dropFirst()).allSatisfy({ $0.year < $1.year }),
              years.last.map({ $0.year < currentYear }) ?? true,
              years.allSatisfy(Self.isWithinBounds)
        else { return "Closed years must be listed once each, by ascending year, each before this one, and within bounds." }
        return nil
    }

    private static func isWithinBounds(_ statement: AnnualStatement) -> Bool {
        let income = statement.income
        let closing = statement.closing
        let flows = [
            income.fareRevenue, income.operatingCost, income.maintenanceCost, income.energyCost, income.staffCost, income.interestCost,
            income.depreciationCost, income.writeOffCost, income.capitalSpending, income.loanBorrowed, income.loanRepaid,
            income.propertyRevenue, income.propertyCost, income.taxCost,
        ]
        let classes = [closing.track, closing.stations, closing.rollingStock, closing.buildings]
        return income.index == statement.year
            && flows.allSatisfy { (0...maximumAccrued).contains($0.amount) }
            && classes.allSatisfy { (0...CompanyAccounts.maximumAssetCost).contains($0.cost.amount) && (.zero...$0.cost).contains($0.depreciation) }
            && (-maximumBalance...maximumBalance).contains(closing.cash.amount)
            && (.zero...CompanyAccounts.maximumLoan).contains(closing.loan)
    }
}

// MARK: - Codable

extension BalanceSheet: Codable {
    private enum CodingKeys: String, CodingKey {
        case cash, track, stations, rollingStock, buildings, loan
    }

    /// Decodes a closing balance sheet; one without the company's
    /// buildings (every year before save version 22) has no `"buildings"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cash = try container.decode(Money.self, forKey: .cash)
        track = try container.decode(AssetClassBalance.self, forKey: .track)
        stations = try container.decode(AssetClassBalance.self, forKey: .stations)
        rollingStock = try container.decode(AssetClassBalance.self, forKey: .rollingStock)
        buildings = try container.decodeIfPresent(AssetClassBalance.self, forKey: .buildings) ?? .zero
        loan = try container.decode(Money.self, forKey: .loan)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cash, forKey: .cash)
        try container.encode(track, forKey: .track)
        try container.encode(stations, forKey: .stations)
        try container.encode(rollingStock, forKey: .rollingStock)
        if buildings != .zero {
            try container.encode(buildings, forKey: .buildings)
        }
        try container.encode(loan, forKey: .loan)
    }
}

extension AssetRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, owner, cars, acquired, cost, depreciation, days
    }

    /// Decodes a record; one that is not of cars has no `"cars"`. That it
    /// names something that exists and is within bounds is checked by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        owner = try container.decode(Int.self, forKey: .owner)
        cars = container.contains(.cars) ? try container.decode(Int.self, forKey: .cars) : 0
        acquired = try container.decode(GameTime.self, forKey: .acquired)
        cost = try container.decode(Money.self, forKey: .cost)
        depreciation = try container.decode(Money.self, forKey: .depreciation)
        days = try container.decode(Int64.self, forKey: .days)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(owner, forKey: .owner)
        if cars != 0 {
            try container.encode(cars, forKey: .cars)
        }
        try container.encode(acquired, forKey: .acquired)
        try container.encode(cost, forKey: .cost)
        try container.encode(depreciation, forKey: .depreciation)
        try container.encode(days, forKey: .days)
    }
}

extension CapitalDay: Codable {
    private enum CodingKeys: String, CodingKey {
        case day, depreciation, writeOff, capitalSpending, borrowed, repaid
    }

    /// Decodes a day; an amount of 0 is not written.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func amount(_ key: CodingKeys) throws -> Money {
            container.contains(key) ? try container.decode(Money.self, forKey: key) : .zero
        }
        day = try container.decode(Int64.self, forKey: .day)
        depreciation = try amount(.depreciation)
        writeOff = try amount(.writeOff)
        capitalSpending = try amount(.capitalSpending)
        borrowed = try amount(.borrowed)
        repaid = try amount(.repaid)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        for (key, value) in [(CodingKeys.depreciation, depreciation), (.writeOff, writeOff), (.capitalSpending, capitalSpending),
                             (.borrowed, borrowed), (.repaid, repaid)] where value != .zero {
            try container.encode(value, forKey: key)
        }
    }
}
