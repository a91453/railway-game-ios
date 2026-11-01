import GameCore

// Decision 480: what a finance report's period earned and spent, by kind,
// for the economy panel's two donuts (income, costs). Read from the
// period's ``FinanceSummary``, the report's own categories: the ledger's
// rows by item are kept for two days only (``CompanyAccounts/keptEntries``),
// the summaries for the report's whole month and year. Small kinds fold
// into "Other" so a ring has at most six slices (dataviz: a donut shows
// part-to-whole at a glance, six segments at most).

/// One period's income and costs by kind.
public struct FinanceComposition: Hashable, Sendable {
    /// What a slice is: one of the report's categories, or the small ones
    /// together.
    public enum Category: String, CaseIterable, Hashable, Sendable {
        // Income.
        case fares, freight, sideBusiness
        // Costs.
        case operating, maintenance, energy, staff, sideBusinessCost, interest, depreciation, tax
        /// The kinds under ``FinanceComposition/minimumPerMille`` of their
        /// ring, together.
        case other

        public static let income: [Category] = [.fares, .freight, .sideBusiness]
        public static let costs: [Category] = [.operating, .maintenance, .energy, .staff, .sideBusinessCost, .interest, .depreciation, .tax]

        /// Its chart colour: a categorical slot, 1 to 8, fixed for the
        /// category whatever else is shown, so a colour always means the
        /// same kind; 0 for ``other``, drawn in a neutral grey.
        public var colorSlot: Int {
            switch self {
            case .other: 0
            default: (Self.income.firstIndex(of: self) ?? Self.costs.firstIndex(of: self) ?? 0) + 1
            }
        }

        public func displayName(in language: DisplayLanguage) -> String {
            switch self {
            case .fares: LedgerItem.fareRevenue.displayName(in: language)
            case .freight: LedgerItem.freightRevenue.displayName(in: language)
            case .sideBusiness: language.text("Rent and side businesses", "租金與附屬事業")
            case .operating: LedgerItem.operatingCost.displayName(in: language)
            case .maintenance: LedgerItem.maintenanceCost.displayName(in: language)
            case .energy: language.text("Energy", "能源費用")
            case .staff: language.text("Staff", "員工費用")
            case .sideBusinessCost: language.text("Buildings and side businesses", "建物與附屬事業支出")
            case .interest: LedgerItem.loanInterest.displayName(in: language)
            case .depreciation: language.text("Depreciation and write-offs", "折舊與報廢")
            case .tax: LedgerItem.incomeTax.displayName(in: language)
            case .other: language.text("Other", "其他")
            }
        }
    }

    /// One slice of a ring.
    public struct Slice: Identifiable, Hashable, Sendable {
        public let category: Category
        /// Never negative.
        public let amount: Money
        /// For ``Category/other``, the kinds in it, in category order;
        /// empty for any other slice.
        public let folded: [Category]

        public var id: Category { category }
    }

    /// Income or costs.
    public enum Side: Hashable, Sendable {
        case income, costs
    }

    /// One donut: its slices, largest first and "Other" last.
    public struct Ring: Hashable, Sendable {
        public let side: Side
        public let slices: [Slice]
        /// The slices together: every category of the side.
        public let total: Money
        /// Each slice's share in whole percent, in slice order, adding up
        /// to 100 (``wholePercents(of:)``).
        public let percents: [Int64]
        /// Whether the company keeps any accounts yet: without, an empty
        /// ring reads "—", not $ 0 (zero and no data are not the same).
        public let hasRecords: Bool

        /// Nothing earned (or spent): no ring is drawn, only its total and
        /// a sentence in its place.
        public var isEmpty: Bool { total == .zero }

        public func title(in language: DisplayLanguage) -> String {
            switch side {
            case .income: language.text("Income", "收入")
            case .costs: language.text("Costs", "支出")
            }
        }

        /// A slice's share of the ring in whole percent, the shares adding
        /// up to 100; "<1%" for a slice too small to show as 1%.
        public func percentText(of slice: Slice) -> String {
            guard let index = slices.firstIndex(of: slice) else { return "0%" }
            let percent = percents[index]
            return percent == 0 && slice.amount > .zero ? "<1%" : "\(percent)%"
        }

        /// The slice at `value` dollars round the ring from its start, as
        /// Swift Charts' angle selection gives it; `nil` past the end.
        public func slice(atDollars value: Double) -> Slice? {
            var end = 0.0
            for slice in slices {
                end += Double(slice.amount.amount) / 100
                if value < end { return slice }
            }
            return nil
        }

        /// What the centre says under the title: the total, or "—" while
        /// there are no accounts.
        public var totalText: String { hasRecords ? total.moneyText : "—" }

        /// ``totalText`` short enough for the middle of the ring, which is
        /// narrow on an iPhone: 萬／億 in Chinese, k／M in English, with no
        /// spaces ("NT$294.5萬", "NT$2.9M"); the exact figure is in the
        /// listing and the spoken summary.
        public func centreText(in language: DisplayLanguage) -> String {
            hasRecords ? TrainRoster.shortMoney(total, in: language) : "—"
        }

        /// A touched slice, spelled out: "Fares · $ 12,000 · 72%"; for
        /// "Other", the kinds in it after its name.
        public func detailText(of slice: Slice, in language: DisplayLanguage) -> String {
            var name = slice.category.displayName(in: language)
            if !slice.folded.isEmpty {
                let names = slice.folded.map { $0.displayName(in: language) }
                name += language.text(" (\(names.joined(separator: ", ")))", "（\(names.joined(separator: "、"))）")
            }
            return "\(name) · \(slice.amount.moneyText) · \(percentText(of: slice))"
        }

        /// The sentence before the slices: the total and the largest slice.
        public func summaryText(in language: DisplayLanguage) -> String {
            guard let first = slices.first else {
                guard hasRecords else { return language.text("No accounts yet", "還沒有帳目") }
                return side == .income
                    ? language.text("No income this period", "本期沒有收入")
                    : language.text("No costs this period", "本期沒有支出")
            }
            let name = first.category.displayName(in: language)
            return language.text(
                "\(title(in: language)) \(totalText), most from \(name) (\(percentText(of: first)))",
                "\(title(in: language)) \(totalText)，最多是\(name)（\(percentText(of: first))）"
            )
        }

        /// The ring for VoiceOver's audio graph: one bar a slice, in
        /// dollars.
        public func chart(in language: DisplayLanguage) -> ChartSpec {
            let title = side == .income
                ? language.text("Income by kind", "收入組成")
                : language.text("Costs by kind", "支出組成")
            return ChartSpec(
                title: title, xTitle: language.text("Kind", "類別"),
                xLabels: slices.map { $0.category.displayName(in: language) },
                axis: .money,
                series: [ChartSeries(name: title, mark: .bars, values: slices.map { Double($0.amount.amount) / 100 })],
                summary: summaryText(in: language), language: language
            )
        }
    }

    public let income: Ring
    public let costs: Ring

    /// Both rings empty.
    public var isEmpty: Bool { income.isEmpty && costs.isEmpty }

    /// A slice under this share of its ring, in thousandths, folds into
    /// "Other": 3%.
    public static let minimumPerMille: Int64 = 30
    /// The most slices a ring has, "Other" among them.
    public static let maximumSlices = 6

    /// `summary`'s income and costs. The gain or loss on buildings sold is
    /// not in either (it is neither earned nor spent in running the
    /// company, decision 130), and a kind below zero counts as nothing.
    /// `hasRecords`: whether the company keeps any accounts yet.
    public init(_ summary: FinanceSummary, hasRecords: Bool = true) {
        income = Self.ring(.income, hasRecords: hasRecords, [
            (.fares, summary.fareRevenue),
            (.freight, summary.freightRevenue),
            (.sideBusiness, summary.propertyRevenue),
        ])
        costs = Self.ring(.costs, hasRecords: hasRecords, [
            (.operating, summary.operatingCost),
            (.maintenance, summary.maintenanceCost),
            (.energy, summary.energyCost),
            (.staff, summary.staffCost),
            (.sideBusinessCost, summary.propertyCost),
            (.interest, summary.interestCost),
            (.depreciation, summary.depreciationCost + summary.writeOffCost),
            (.tax, summary.taxCost),
        ])
    }

    static func ring(_ side: Side, hasRecords: Bool, _ amounts: [(Category, Money)]) -> Ring {
        let parts = amounts.filter { $0.1 > .zero }
        let total = parts.reduce(Money.zero) { $0 + $1.1 }
        // Largest first; equal amounts in category order (stable sort).
        var kept = parts.enumerated().sorted { a, b in
            a.element.1 == b.element.1 ? a.offset < b.offset : a.element.1 > b.element.1
        }.map(\.element)
        var small: [(Category, Money)] = []
        kept.removeAll { part in
            let isSmall = part.1.amount * 1_000 < minimumPerMille * total.amount
            if isSmall { small.append(part) }
            return isSmall
        }
        // Too many slices: the smallest kept ones join "Other" too, leaving
        // room for it.
        if kept.count + (small.isEmpty ? 0 : 1) > maximumSlices {
            small = Array(kept[(maximumSlices - 1)...]) + small
            kept.removeLast(kept.count - (maximumSlices - 1))
        }
        var slices = kept.map { Slice(category: $0.0, amount: $0.1, folded: []) }
        if small.count == 1 {
            // One small kind is shown as itself: "Other" would hide its
            // name for nothing.
            slices.append(Slice(category: small[0].0, amount: small[0].1, folded: []))
        } else if !small.isEmpty {
            let order = Category.allCases
            let folded = small.map(\.0).sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
            slices.append(Slice(category: .other, amount: small.reduce(Money.zero) { $0 + $1.1 }, folded: folded))
        }
        return Ring(side: side, slices: slices, total: total, percents: wholePercents(of: slices.map(\.amount)), hasRecords: hasRecords)
    }

    /// `amounts`' shares in whole percent, adding up to 100 (none when
    /// they add up to nothing): each rounded down, then the points left
    /// to the largest remainders, the first on a tie (Hamilton's method),
    /// so the listed shares add up as the ring does.
    static func wholePercents(of amounts: [Money]) -> [Int64] {
        let total = amounts.reduce(Int64(0)) { $0 + $1.amount }
        guard total > 0 else { return amounts.map { _ in 0 } }
        var percents = amounts.map { 100 * $0.amount / total }
        let remainders = amounts.map { 100 * $0.amount % total }
        let left = 100 - percents.reduce(0, +)
        let order = remainders.indices.sorted { remainders[$0] == remainders[$1] ? $0 < $1 : remainders[$0] > remainders[$1] }
        for index in order.prefix(Int(left)) {
            percents[index] += 1
        }
        return percents
    }
}
