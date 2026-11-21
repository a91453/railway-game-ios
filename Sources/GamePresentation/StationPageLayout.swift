// Decision 911 (STATION-PAGES, UI-UX audit 2026-11-20, item 1 and item
// 12): the station panel over the whole screen (decision 746) in pages,
// one for each of its groups (decision 472), as the company's figures
// (decision 717) and a line's own page (decision 779) have theirs; two
// columns side by side where the window is wide, and one column of a
// readable width, in the middle, where it is wide but the text is large.
// Beside the map, in a lesson, the panel keeps its one folding list.

/// Decision 911: which pages the station panel has over the whole screen,
/// what each holds, and whether a page stands in two columns. The same
/// sections, in the same order, as the one list; only where they stand
/// changes.
public struct StationPageLayout: Equatable, Sendable {
    /// What of the game decides the sections.
    public struct Facts: Equatable, Sendable {
        /// Whether the freight yard's section shows (decision 271: in a
        /// lesson, from lesson 8). Without it the last page holds only the
        /// removal, in one column.
        public var showsFreight: Bool

        public init(showsFreight: Bool) {
            self.showsFreight = showsFreight
        }
    }

    /// A page's sections: the leading column's, then the trailing one's.
    /// In one column the trailing sections follow the leading ones, in
    /// the one list's order.
    public struct Columns: Equatable, Sendable {
        public var leading: [StationPanelPart]
        public var trailing: [StationPanelPart]

        public var all: [StationPanelPart] { leading + trailing }

        /// Side by side only when both have something.
        public var isSplit: Bool { !leading.isEmpty && !trailing.isEmpty }
    }

    /// The least width that holds two columns side by side, in points (as
    /// the company's figures and a line's page).
    public static let twoColumnWidth: Double = EconomyLayout.twoColumnWidth

    /// The widest one column stands, in points: wider, a row's label and
    /// its value sit too far apart to read as one (an iPad with text of an
    /// accessibility size). The column stands in the middle.
    public static let oneColumnMaxWidth: Double = 700

    public let facts: Facts

    public init(_ facts: Facts) {
        self.facts = facts
    }

    /// The pages, in the order shown: every group, since each has a
    /// section that always shows (the platforms, the trips by hour, the
    /// shops, the removal).
    public var pages: [StationPanelGroup] {
        StationPanelGroup.allCases
    }

    /// What `page` holds. The everyday rows (the line on sale, the
    /// platforms and weather, the trains due, the way to another station)
    /// lead; what is set once (the platforms' tracks, transfers, sounds)
    /// trails. Riders: what the day looks like leads, what can be changed
    /// about it trails. Surroundings: the station and the people round it
    /// lead, the land, roads and buses trail.
    public func columns(of page: StationPanelGroup) -> Columns {
        switch page {
        case .operations:
            Columns(
                leading: [.buyLine, .operations, .departureBoard, .journey, .rename, .operationMode],
                trailing: [.depot, .transfer, .platforms, .sounds]
            )
        case .riders:
            Columns(leading: [.tripsByHour, .passengers], trailing: [.expansion, .demand, .events, .tripsByStation])
        case .area:
            Columns(leading: [.commerce, .realStation, .catchment], trailing: [.land, .road, .bus])
        case .freight:
            facts.showsFreight
                ? Columns(leading: [.freight], trailing: [.removal])
                : Columns(leading: [.removal], trailing: [])
        }
    }

    /// The page of `part`.
    public func page(of part: StationPanelPart) -> StationPanelGroup {
        part.group
    }

    /// The page holding the tutorial's panel button `target`, or `nil`
    /// for one not in the panel.
    public func page(holding target: TutorialTarget) -> StationPanelGroup? {
        StationPanelGroup.holding(target)
    }

    /// The page the panel opens at: the one asked for (a map bubble's,
    /// decision 477), else the first.
    public func opening(at focus: StationPanelGroup?) -> StationPanelGroup {
        focus ?? .operations
    }

    /// Whether `page` stands in two columns in a window `width` points
    /// wide: not in a narrow one, nor with text of an accessibility size,
    /// nor when one column would be empty.
    public func isSplit(_ page: StationPanelGroup, width: Double, accessibilitySize: Bool) -> Bool {
        width >= Self.twoColumnWidth && !accessibilitySize && columns(of: page).isSplit
    }

    /// The width one column stands at in a window `width` points wide: the
    /// window's, up to ``oneColumnMaxWidth``.
    public static func oneColumnWidth(in width: Double) -> Double {
        min(width, oneColumnMaxWidth)
    }
}

extension StationPanelGroup {
    /// Its name on the control that picks the page: short enough for four
    /// to stand on a phone held upright.
    public func pageTitle(in language: DisplayLanguage) -> String {
        switch self {
        case .operations: language.text("Operations", "營運")
        case .riders: language.text("Riders", "旅客與運量")
        case .area: language.text("Area", "周邊與土地")
        case .freight: language.text("Freight", "貨運與拆除")
        }
    }
}
