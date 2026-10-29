import GameCore

// Decision 481, later: a long list of lines in groups by kind, each group
// folded or not, and the lines that need a look marked.

/// The kind of line a group of the lines list holds, in the list's order.
public enum LineGroup: String, CaseIterable, Hashable, Sendable {
    /// Passenger lines the player built.
    case own
    /// Real lines bought (decisions 315, 336).
    case acquired
    /// High-speed lines (decision 168).
    case highSpeed
    /// Freight lines.
    case freight

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .own: language.text("Your lines", "自建路線")
        case .acquired: language.text("Bought lines", "收購的路線")
        case .highSpeed: language.text("High-speed rail", "高鐵")
        case .freight: language.text("Freight", "貨運")
        }
    }

    /// The folded groups kept in a setting, as their names joined by
    /// commas; a name it does not know is left out.
    public static func folded(from stored: String) -> Set<LineGroup> {
        Set(stored.split(separator: ",").compactMap { LineGroup(rawValue: String($0)) })
    }

    /// `groups` as a setting, in the list's order.
    public static func stored(_ groups: Set<LineGroup>) -> String {
        allCases.filter(groups.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// One group of the lines list: its kind and its lines.
public struct LineGroupRows: Identifiable, Sendable {
    public let group: LineGroup
    public let lines: [ServiceLine]

    public var id: LineGroup { group }
}

/// Why a line needs a look (``GameWorld/lineAttention(_:)``).
public enum LineAttention: Hashable, Sendable {
    /// A passenger line that lost money yesterday.
    case losing
    /// Its fullest train carried more than its seats and standing room
    /// (yesterday, or today so far before a day is on record).
    case overfull
    /// No train runs it.
    case noTrains

    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .losing: language.text("Lost money yesterday", "昨日虧損")
        case .overfull: language.text("A train was over full", "有列車超載")
        case .noTrains: language.text("No trains", "沒有列車")
        }
    }

    /// The reasons as one phrase, for the row's mark; `nil` for none.
    public static func label(_ reasons: [LineAttention], in language: DisplayLanguage) -> String? {
        guard !reasons.isEmpty else { return nil }
        let joined = reasons.map { $0.text(in: language).lowercased() }.joined(separator: language.text(", ", "、"))
        return language.text("Needs attention: \(joined)", "需要注意：\(joined)")
    }
}

extension GameWorld {
    /// The group `line` is listed under: freight first, then high-speed,
    /// then a bought line, else the player's own.
    public func lineGroup(of line: ServiceLine) -> LineGroup {
        if line.isFreight { return .freight }
        if line.isHighSpeed { return .highSpeed }
        if acquisitions.contains(where: { $0.line == line.id }) { return .acquired }
        return .own
    }

    /// `lines` in groups, in ``LineGroup``'s order, each keeping the order
    /// given; groups with no line are left out.
    public func lineGroups(_ lines: [ServiceLine]) -> [LineGroupRows] {
        var byGroup: [LineGroup: [ServiceLine]] = [:]
        for line in lines {
            byGroup[lineGroup(of: line), default: []].append(line)
        }
        return LineGroup.allCases.compactMap { group in
            byGroup[group].map { LineGroupRows(group: group, lines: $0) }
        }
    }

    /// Why `line` needs a look, in a fixed order; empty when it does not:
    /// no train runs it, its fullest train was over 100%, or (a passenger
    /// line) it lost money yesterday.
    public func lineAttention(_ line: ServiceLine) -> [LineAttention] {
        lineAttention(line, report: line.isFreight ? nil : lineReport(line.id))
    }

    /// ``lineAttention(_:)`` with the line's report already read (the
    /// list's row reads it for its second line).
    public func lineAttention(_ line: ServiceLine, report: LineReport?) -> [LineAttention] {
        var reasons: [LineAttention] = []
        if line.trains.isEmpty && line.patterns.allSatisfy({ $0.trains.isEmpty }) {
            reasons.append(.noTrains)
        }
        if !line.isFreight, let report {
            if let gauge = report.loadGauge, gauge.percent > 100 {
                reasons.append(.overfull)
            }
            if let yesterday = report.yesterday, yesterday.profit < .zero {
                reasons.append(.losing)
            }
        }
        return reasons
    }
}
