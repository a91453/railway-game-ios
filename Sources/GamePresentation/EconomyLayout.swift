import GameCore

/// Decision 717: the pages of the company's figures, which cover the whole
/// screen. Each answers one question: how the company is doing, what it
/// owes, what a ride costs, and where the money went.
public enum EconomyPage: String, CaseIterable, Hashable, Sendable {
    case overview, loans, fares, reports

    /// The page's name on the control that picks it.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .overview: language.text("Overview", "總覽")
        case .loans: language.text("Loans", "借款")
        case .fares: language.text("Fares", "票價")
        case .reports: language.text("Reports", "報表")
        }
    }
}

/// One block of a page (decision 717), a section of its list.
public enum EconomySection: String, CaseIterable, Hashable, Sendable {
    /// The cash in hand, the map's tiles and the fuel price.
    case balance
    /// Today's fares, costs and result so far.
    case today
    /// The challenge being played.
    case goals
    /// The growth charts.
    case trend
    /// The week's punctuality.
    case punctuality
    /// The fleet overview and the last month's report.
    case shortcuts
    /// Free play or management, and the switch to free play.
    case mode
    /// The loan in steps (decision 67).
    case loan
    /// The term loans (decision 715).
    case termLoans
    case fares
    case dayPass
    /// The income or cash flow statement of a period, and its donuts.
    case report
    case lastHour
    case balanceSheet
    case closedYears
    case ledger
}

/// Decision 717: which pages the company's figures have, what each holds,
/// and whether a page stands in two columns. The same sections at every
/// size; only where they stand changes.
public struct EconomyLayout: Equatable, Sendable {
    /// What of the world decides the sections.
    public struct Facts: Equatable, Sendable {
        /// Decision 200: nothing to borrow for, and no cash to sheet.
        public var unlimitedFunds: Bool
        /// ``GameWorld/showsTermLoans``.
        public var showsTermLoans: Bool
        /// Whether there is a day's account (``TodayAccount``): a managed
        /// company's, not free play's.
        public var hasToday: Bool
        public var hasScenario: Bool
        /// Whether the week has trips enough to say how many were on time.
        public var hasPunctuality: Bool

        public init(unlimitedFunds: Bool, showsTermLoans: Bool, hasToday: Bool, hasScenario: Bool, hasPunctuality: Bool) {
            self.unlimitedFunds = unlimitedFunds
            self.showsTermLoans = showsTermLoans
            self.hasToday = hasToday
            self.hasScenario = hasScenario
            self.hasPunctuality = hasPunctuality
        }

        public init(world: GameWorld) {
            self.init(
                unlimitedFunds: world.economy.unlimitedFunds, showsTermLoans: world.showsTermLoans,
                hasToday: world.todayAccount() != nil, hasScenario: world.scenario != nil,
                hasPunctuality: world.companyWeeklyPunctuality() != nil
            )
        }
    }

    /// A page's sections: the leading column's, then the trailing one's.
    /// In one column the trailing sections follow the leading ones.
    public struct Columns: Equatable, Sendable {
        public var leading: [EconomySection]
        public var trailing: [EconomySection]

        public var all: [EconomySection] { leading + trailing }

        /// Side by side only when both have something.
        public var isSplit: Bool { !leading.isEmpty && !trailing.isEmpty }
    }

    /// The least width that holds two columns side by side, in points (as
    /// the term loans' screen, decision 715).
    public static let twoColumnWidth: Double = 640

    public let facts: Facts

    public init(_ facts: Facts) {
        self.facts = facts
    }

    public init(world: GameWorld) {
        self.init(Facts(world: world))
    }

    /// The pages, in the order shown. A page with nothing on it is left
    /// out: the loans, with unlimited funds and no term loan to pay back.
    public var pages: [EconomyPage] {
        EconomyPage.allCases.filter { !columns(of: $0).all.isEmpty }
    }

    /// What `page` holds.
    public func columns(of page: EconomyPage) -> Columns {
        switch page {
        case .overview:
            Columns(
                leading: [.balance] + (facts.hasToday ? [.today] : []) + (facts.hasScenario ? [.goals] : []) + [.shortcuts, .mode],
                trailing: [.trend] + (facts.hasPunctuality ? [.punctuality] : [])
            )
        case .loans:
            Columns(
                leading: facts.unlimitedFunds ? [] : [.loan],
                trailing: facts.showsTermLoans ? [.termLoans] : []
            )
        case .fares:
            Columns(leading: [.fares], trailing: [.dayPass])
        case .reports:
            Columns(
                leading: [.report],
                trailing: [.lastHour] + (facts.unlimitedFunds ? [] : [.balanceSheet]) + [.closedYears, .ledger]
            )
        }
    }

    /// The page of `section`.
    public func page(of section: EconomySection) -> EconomyPage? {
        pages.first { columns(of: $0).all.contains(section) }
    }

    /// The page the screen opens at: the one asked for (the insolvency
    /// bubble asks for the loans, decision 336) when there is one, else
    /// the overview.
    public func opening(at focus: EconomyPage?) -> EconomyPage {
        if let focus, pages.contains(focus) { return focus }
        return .overview
    }

    /// The page shown when `page` was picked and the world has changed
    /// since: itself while it still exists, else the overview.
    public func showing(_ page: EconomyPage) -> EconomyPage {
        opening(at: page)
    }

    /// Whether `page` stands in two columns in a window `width` points
    /// wide: not in a narrow one, nor with text of an accessibility size,
    /// nor when one column would be empty.
    public func isSplit(_ page: EconomyPage, width: Double, accessibilitySize: Bool) -> Bool {
        width >= Self.twoColumnWidth && !accessibilitySize && columns(of: page).isSplit
    }
}
