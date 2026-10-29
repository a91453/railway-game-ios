import GameCore

/// Decision 481: the lines panel in two levels, a short list of the lines
/// and, pushed over it, one line's own page (its trains, depots, stops,
/// settings, operations and services). The pages the panel's navigation
/// stack can show over the list; the line page shows ``GameSession/openedLine``,
/// so going to the line before or after it changes what the page shows,
/// not the stack.
public enum LinesPanelPage: Hashable, Sendable {
    /// The opened line's own page.
    case line
    /// The switches for every line: traffic control, how passengers route
    /// and the service day.
    case network
    /// The real lines this map sells (decision 315).
    case forSale

    /// The stack the panel shows, from the one it shows now: the line page
    /// alone over the list while a line is opened, and without it once
    /// none is (another page stays as it was).
    public static func path(_ path: [LinesPanelPage], opened: Bool) -> [LinesPanelPage] {
        if opened { return path == [.line] ? path : [.line] }
        return path.filter { $0 != .line }
    }
}

extension GameSession {
    /// Decision 196: the lines come first once there are some, unless a
    /// new line is being picked or the tutorial leads (its steps point at
    /// the form for a new line at the top, and at the selected line's
    /// buttons under it). Decision 481: only then does a line open on a
    /// page of its own; otherwise the panel stays one form, as before.
    public var linesPanelListsLinesFirst: Bool {
        !world.lines.isEmpty && !isPickingLineStops && lineDraft.isEmpty && tutorial == nil
    }

    /// The line whose own page the lines panel shows, or `nil` for the
    /// list: none while the panel is one form
    /// (``linesPanelListsLinesFirst``), or once the line is gone.
    public var openedLine: ServiceLine? {
        guard linesPanelListsLinesFirst, let id = openedLineID else { return nil }
        return world.line(id: id)
    }

    /// Selects line `id` and opens its own page in the lines panel: a row
    /// of the list, the map, a station's chips, a report. Never changes the
    /// world; an ID the world does not have is ignored.
    public func openLine(_ id: LineID) {
        guard world.line(id: id) != nil else { return }
        selectLine(id)
        openedLineID = id
    }

    /// Back to the list of lines; the line stays selected.
    public func closeLineDetails() {
        openedLineID = nil
    }

    /// The panel's stack was changed by the player (Back, or a page
    /// pushed): leaving the line page closes it.
    public func linesPanelPathChanged(to path: [LinesPanelPage]) {
        if !path.contains(.line), openedLineID != nil { closeLineDetails() }
    }
}

/// Decision 481: the lines before and after the opened one, for the line
/// page's arrows: in the order the list shows them (sorted, searched and
/// filtered), or in every line's order when the list leaves the opened
/// line out.
public enum LineNeighbours {
    public static func around(_ id: LineID, shown: [LineID], all: [LineID]) -> (previous: LineID?, next: LineID?) {
        let order = shown.contains(id) ? shown : all
        guard let index = order.firstIndex(of: id) else { return (nil, nil) }
        return (
            index > order.startIndex ? order[index - 1] : nil,
            index + 1 < order.endIndex ? order[index + 1] : nil
        )
    }

    /// "Line 3 of 12"; "第 3 條，共 12 條": where the opened line is in
    /// the order its arrows follow.
    public static func positionText(_ id: LineID, shown: [LineID], all: [LineID], in language: DisplayLanguage) -> String? {
        let order = shown.contains(id) ? shown : all
        guard let index = order.firstIndex(of: id), order.count > 1 else { return nil }
        return language.text("Line \(index + 1) of \(order.count)", "第 \(index + 1) 條，共 \(order.count) 條")
    }

    public static func previousTitle(in language: DisplayLanguage) -> String {
        language.text("Previous Line", "上一條線")
    }

    public static func nextTitle(in language: DisplayLanguage) -> String {
        language.text("Next Line", "下一條線")
    }
}

extension LineReport {
    /// Decision 481: the second line of a line's row in the short list,
    /// "Yesterday 12,340 riders · profit $ -4,200": who rode and whether
    /// it paid. A new line says what it carried today so far; fares,
    /// the peak and the rest are on the line's own page (``rowText(in:)``).
    public func compactRowText(in language: DisplayLanguage) -> String {
        guard let yesterday else {
            guard let today else {
                return language.text("No record of yesterday yet", "昨日還沒有紀錄")
            }
            return language.text("Today so far \(Money(today.riders).displayText) riders", "今日至今 \(Money(today.riders).displayText) 人次")
        }
        return [
            language.text("Yesterday \(Money(yesterday.riders).displayText) riders", "昨日 \(Money(yesterday.riders).displayText) 人次"),
            language.text("profit \(yesterday.profit.moneyText)", "損益 \(yesterday.profit.moneyText)"),
        ].joined(separator: " · ")
    }

    /// Whether the row's text is a loss, drawn in the warning colour.
    public var lostMoneyYesterday: Bool {
        yesterday.map { $0.profit < .zero } ?? false
    }
}

extension NetworkSwitches {
    /// Decision 481: the network page's row in the list, what it holds as
    /// set now: "Traffic control on · network routes · standard service
    /// day".
    public static func summary(of world: GameWorld, in language: DisplayLanguage) -> String {
        [
            world.isTrafficControlEnabled
                ? language.text("Traffic control on", "行車控制開")
                : language.text("Traffic control off", "行車控制關"),
            world.passengerRoutingMode == .network
                ? language.text("network routes", "跨線轉乘")
                : language.text("direct routes only", "只坐直達"),
            AdvancedDetails.networkSummary(of: world, in: language).lowercased(),
        ].joined(separator: " · ")
    }

    /// "Lines for sale (2)": the row that opens the real lines for sale.
    public static func forSaleTitle(count: Int, in language: DisplayLanguage) -> String {
        count > 0
            ? language.text("Real lines for sale (\(count))", "可收購的真實路線（\(count)）")
            : language.text("Real lines for sale", "可收購的真實路線")
    }
}
