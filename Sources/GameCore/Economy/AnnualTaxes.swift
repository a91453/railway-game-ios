// The annual taxes (ARCHITECTURE decision 734, ANNUAL-FINANCE AF-1;
// `docs/research/ANNUAL_FINANCE_DESIGN_2026-11-13.md` §3.1, §3.6, §3.9). The
// shape is the owner's earlier desktop game's (`FinanceEngine`: the year's
// corporate tax charged as the year closes, owed as a liability and paid
// months later); the rates are Taiwan's, not that game's.
//
// With ``GameWorld/annualTaxes`` on, the company pays no tax at each
// midnight (decision 131). As a year closes, its profit before tax is
// charged the profit-seeking enterprise income tax (所得稅法 §5): nothing
// up to NT$120,000; above it 20 % of the whole profit, but never more than
// half of what is above NT$120,000. The tax is owed
// (``CompanyAccounts/incomeTaxPayable``, on the balance sheet as
// ``BalanceSheet/taxPayable``) until the midnight that ends the next year's
// fifth month (day 149 of the year, 30-day months), when it is paid in
// cash, whatever the balance (it may go below zero, as every cost may).
// Whole New Taiwan dollars, rounded down.
//
// Decision 736 (AF-2; design §3.3–§3.5): as the year closes, the house tax
// (房屋稅條例 §5, business use, 3 %) is charged on the stations' and the
// company's buildings' book value less the land under the buildings, and
// the land tax (土地稅法 §16, the basic rate, 1 %) on the land the company
// bought (the buildings' land and the map's tiles), instead of each day's
// land tax (decision 94). The house tax is paid with the income tax, the
// land tax at the midnight that ends the next year's eleventh month (day
// 329). Track and trains are not taxed, as in Taiwan. With the annual taxes
// the stations also pay an upkeep each day by the length of their
// platforms.

extension CompanyAccounts {
    /// Decision 734: the share of a year's profit before tax paid as income
    /// tax, in per cent (所得稅法 §5: 20 %).
    public static let annualIncomeTaxPercent: Int64 = 20
    /// A year's profit before tax up to this is not taxed: NT$120,000.
    public static let annualIncomeTaxThreshold: Money = 12_000_000
    /// Above ``annualIncomeTaxThreshold`` the tax is never more than this
    /// share of what is above it, in per cent: half.
    public static let annualIncomeTaxCapPercent: Int64 = 50
    /// The day of the year (from 0) whose midnight pays the tax the year
    /// before was charged: the last of the fifth month, as Taiwan's annual
    /// return is filed and paid in May.
    public static let incomeTaxDueDay: Int64 = 149
    /// Decision 736: the house tax, in per cent of the houses' book value
    /// (房屋稅條例 §5: 3 % to 5 % for business use; the lowest).
    public static let houseTaxPercent: Int64 = 3
    /// The land tax, in per cent of what the land cost (土地稅法 §16: the
    /// basic rate, 10 ‰).
    public static let landTaxPercent: Int64 = 1
    /// The day of the year (from 0) whose midnight pays the land tax the
    /// year before was charged: the last of the eleventh month, as Taiwan's
    /// land tax is collected in November.
    public static let landTaxDueDay: Int64 = 329
    /// A station's upkeep a day for each metre of its platforms, with the
    /// annual taxes: NT$3 (NT$300 for 100 m).
    public static let platformUpkeepPerMetre: Money = 300
}

extension GameWorld {
    // MARK: - Commands

    /// Turns on or off whether the income tax is settled once a year
    /// (decision 734). Tax already owed stays owed and is paid when due.
    public mutating func setAnnualTaxes(_ enabled: Bool) {
        annualTaxes = enabled
    }

    // MARK: - Queries

    /// The income tax on a year's profit before tax `profit` (decision
    /// 734): nothing up to ``CompanyAccounts/annualIncomeTaxThreshold``;
    /// above it ``CompanyAccounts/annualIncomeTaxPercent`` of the whole,
    /// but at most ``CompanyAccounts/annualIncomeTaxCapPercent`` of what is
    /// above the threshold; whole dollars, rounded down.
    public static func annualIncomeTax(on profit: Money) -> Money {
        guard profit > CompanyAccounts.annualIncomeTaxThreshold else { return .zero }
        let dollars = profit.amount / 100
        let above = dollars - CompanyAccounts.annualIncomeTaxThreshold.amount / 100
        let full = dollars * CompanyAccounts.annualIncomeTaxPercent / 100
        let capped = above * CompanyAccounts.annualIncomeTaxCapPercent / 100
        return Money(min(full, capped) * 100)
    }

    /// The house tax on houses worth `base` (decision 736):
    /// ``CompanyAccounts/houseTaxPercent`` of it, whole dollars rounded
    /// down; nothing on nothing.
    public static func annualHouseTax(on base: Money) -> Money {
        percent(CompanyAccounts.houseTaxPercent, of: base)
    }

    /// The land tax on land that cost `base` (decision 736):
    /// ``CompanyAccounts/landTaxPercent`` of it, whole dollars rounded down.
    public static func annualLandTax(on base: Money) -> Money {
        percent(CompanyAccounts.landTaxPercent, of: base)
    }

    private static func percent(_ percent: Int64, of base: Money) -> Money {
        guard base > .zero else { return .zero }
        return Money(base.amount / 100 * percent / 100 * 100)
    }

    /// What the house tax is on now (decision 736): the stations' book
    /// value and the company's buildings', less what the land under its
    /// buildings cost (that is the land tax's).
    public func houseTaxBase() -> Money {
        let land = placedBuildings.reduce(Money.zero) { $0 + $1.landCost }
        let buildings = accounts.assetBalance(.buildings).bookValue
        return accounts.assetBalance(.stations).bookValue + max(.zero, buildings - land)
    }

    /// What the land tax is on now (decision 736): what the land under the
    /// company's buildings cost and the map's tiles bought, at book value.
    public func landTaxBase() -> Money {
        placedBuildings.reduce(Money.zero) { $0 + $1.landCost } + accounts.assetBalance(.land).bookValue
    }

    /// The stations' upkeep a day by their platforms (decision 736):
    /// ``CompanyAccounts/platformUpkeepPerMetre`` for each metre of every
    /// platform, whole dollars rounded up; nothing without the annual
    /// taxes.
    public func dailyStationUpkeep() -> Money {
        guard annualTaxes else { return .zero }
        let length = network.platforms.reduce(Int64(0)) { $0 + $1.length }
        let perMetre = CompanyAccounts.platformUpkeepPerMetre.amount / 100
        let units = WorldCoordinate.unitsPerMetre
        return Money((length * perMetre + units - 1) / units * 100)
    }

    /// The house and land taxes this year would be charged if it closed
    /// now (decision 736): zero without the annual taxes.
    public func estimatedPropertyTaxes() -> (house: Money, land: Money) {
        guard annualTaxes else { return (.zero, .zero) }
        return (Self.annualHouseTax(on: houseTaxBase()), Self.annualLandTax(on: landTaxBase()))
    }

    /// The income tax this year would be charged if it closed now, from
    /// its profit before tax so far (decision 734): zero without the annual
    /// taxes.
    public func estimatedIncomeTax() -> Money {
        guard annualTaxes else { return .zero }
        return Self.annualIncomeTax(on: accounts.report(.year, day: dayIndex(of: clock.now)).current.profitBeforeTax)
    }

    // MARK: - Settlement

    /// Pays the taxes owed that fall due as day `day`, which just ended,
    /// closes: the income tax (decision 734) and the house tax (decision
    /// 736) on the year's ``CompanyAccounts/incomeTaxDueDay``, the land tax
    /// on its ``CompanyAccounts/landTaxDueDay``.
    mutating func payTaxesDue(day: Int64, time: GameTime) {
        let year = FinancePeriod.year.days
        let dayOfYear = day - CompanyAccounts.floorDivide(day, year) * year
        if dayOfYear == CompanyAccounts.incomeTaxDueDay {
            let income = accounts.incomeTaxPayable
            if income > .zero {
                accounts.incomeTaxPayable = .zero
                write(LedgerEntry(
                    kind: .annualIncomeTax, time: time, amount: .zero - income,
                    breakdown: [LedgerLine(item: .incomeTax, amount: .zero - income)]
                ), day: day)
            }
            let house = accounts.houseTaxPayable
            if house > .zero {
                accounts.houseTaxPayable = .zero
                write(LedgerEntry(
                    kind: .annualHouseTax, time: time, amount: .zero - house,
                    breakdown: [LedgerLine(item: .houseTax, amount: .zero - house)]
                ), day: day)
            }
        }
        if dayOfYear == CompanyAccounts.landTaxDueDay {
            let land = accounts.landTaxPayable
            if land > .zero {
                accounts.landTaxPayable = .zero
                write(LedgerEntry(
                    kind: .annualLandTax, time: time, amount: .zero - land,
                    breakdown: [LedgerLine(item: .propertyTax, amount: .zero - land)]
                ), day: day)
            }
        }
    }

    /// Pays day `day`'s upkeep of the stations' platforms (decision 736).
    mutating func settleStationUpkeep(day: Int64, time: GameTime) {
        let upkeep = dailyStationUpkeep()
        guard upkeep > .zero else { return }
        write(LedgerEntry(
            kind: .dailyStationUpkeep, time: time, amount: .zero - upkeep,
            breakdown: [LedgerLine(item: .stationUpkeep, amount: .zero - upkeep)]
        ), day: day)
    }
}
