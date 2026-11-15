import GameCore

/// Decision 776 (the owner, 2026-11-15: 「路線詳情…要滑太多 應該可以改成跟
/// 資料類似」): the pages of a line's own page, which covers the whole
/// screen (decision 745), as the company's figures have theirs (decision
/// 717). Each answers one question: how the line is doing, what runs on
/// it, where it stops, and what it is called.
public enum LineDetailPage: String, CaseIterable, Hashable, Sendable {
    case overview, trains, stops, settings

    /// The page's name on the control that picks it.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .overview: language.text("Overview", "總覽")
        case .trains: language.text("Trains", "列車")
        case .stops: language.text("Stops", "停靠站")
        case .settings: language.text("Settings", "設定")
        }
    }
}

/// One block of a line's page (decision 776), one or more sections of its
/// list, as the one long form had them (decision 481).
public enum LineDetailSection: String, CaseIterable, Hashable, Sendable {
    /// Its stops in full, whether it runs now, its figures and trend.
    case summary
    /// How well its trains fit and who waits at its ends (decision 274),
    /// and the riders who take a scooter or a car instead (decision 332).
    case feedback
    /// Its operations: the charts, riders who gave up, why it loses money.
    case operations
    /// Riders between stops.
    case load
    /// Trains that cannot pass (decision 264), then the trains to start
    /// with or the headway and its trains.
    case trains
    /// The depots its trains belong to.
    case depots
    /// The stops, the diagram and the roster.
    case stops
    /// The stopping patterns and the button that adds one.
    case services
    /// Its name, code, colour, hours, freight and the rest.
    case settings
    /// Rebuilding a bought line as the real one.
    case realRebuild
}

/// Decision 776: which pages a line's page has, what each holds, and
/// whether a page stands in two columns. The same sections as the one
/// long form; only where they stand changes.
public struct LineDetailLayout: Equatable, Sendable {
    /// What of the line decides the sections.
    public struct Facts: Equatable, Sendable {
        /// A freight line has no riders' charts.
        public var isFreight: Bool
        /// Whether the line has a report (its operations' charts).
        public var hasReport: Bool
        /// Whether the trains' controls show: not on a ring, nor in a
        /// lesson before more trains are taught.
        public var showsTrains: Bool
        /// Whether the depots' section has anything to show.
        public var showsDepots: Bool
        /// Whether the line can be rebuilt as the real one.
        public var rebuildsAsReal: Bool
        /// Whether it has a stopping pattern, or the button to add one.
        public var hasServices: Bool

        public init(isFreight: Bool, hasReport: Bool, showsTrains: Bool, showsDepots: Bool, rebuildsAsReal: Bool, hasServices: Bool) {
            self.isFreight = isFreight
            self.hasReport = hasReport
            self.showsTrains = showsTrains
            self.showsDepots = showsDepots
            self.rebuildsAsReal = rebuildsAsReal
            self.hasServices = hasServices
        }
    }

    /// A page's sections: the leading column's, then the trailing one's.
    /// In one column the trailing sections follow the leading ones.
    public struct Columns: Equatable, Sendable {
        public var leading: [LineDetailSection]
        public var trailing: [LineDetailSection]

        public var all: [LineDetailSection] { leading + trailing }

        /// Side by side only when both have something.
        public var isSplit: Bool { !leading.isEmpty && !trailing.isEmpty }
    }

    /// The least width that holds two columns side by side, in points (as
    /// the company's figures, decision 717).
    public static let twoColumnWidth: Double = EconomyLayout.twoColumnWidth

    public let facts: Facts

    public init(_ facts: Facts) {
        self.facts = facts
    }

    /// The pages, in the order shown. A page with nothing on it is left
    /// out: the trains of a ring.
    public var pages: [LineDetailPage] {
        LineDetailPage.allCases.filter { !columns(of: $0).all.isEmpty }
    }

    /// What `page` holds.
    public func columns(of page: LineDetailPage) -> Columns {
        switch page {
        case .overview:
            Columns(
                leading: [.summary, .feedback],
                trailing: facts.isFreight ? [] : (facts.hasReport ? [.operations] : []) + [.load]
            )
        case .trains:
            // A ring's depots, with no trains' controls to stand beside,
            // go to its settings.
            facts.showsTrains
                ? Columns(leading: [.trains], trailing: facts.showsDepots ? [.depots] : [])
                : Columns(leading: [], trailing: [])
        case .stops:
            Columns(leading: [.stops], trailing: facts.hasServices ? [.services] : [])
        case .settings:
            Columns(
                leading: [.settings],
                trailing: (!facts.showsTrains && facts.showsDepots ? [.depots] : []) + (facts.rebuildsAsReal ? [.realRebuild] : [])
            )
        }
    }

    /// The page of `section`.
    public func page(of section: LineDetailSection) -> LineDetailPage? {
        pages.first { columns(of: $0).all.contains(section) }
    }

    /// The page shown when `page` was picked and the line has changed
    /// since (another line, or the same one changed): itself while it
    /// still exists, else the overview.
    public func showing(_ page: LineDetailPage) -> LineDetailPage {
        pages.contains(page) ? page : .overview
    }

    /// Whether `page` stands in two columns in a window `width` points
    /// wide: not in a narrow one, nor with text of an accessibility size,
    /// nor when one column would be empty.
    public func isSplit(_ page: LineDetailPage, width: Double, accessibilitySize: Bool) -> Bool {
        width >= Self.twoColumnWidth && !accessibilitySize && columns(of: page).isSplit
    }
}
