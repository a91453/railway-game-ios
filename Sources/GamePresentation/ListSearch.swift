import Foundation
import GameCore

// Searching the station, line and train lists by name (ARCHITECTURE
// decision 184). The reference's lists have no search (the simulator's
// station list and MapBuilder's route list are short), so this is the
// project's own: a name matches when it contains what was typed, whatever
// the case, width or accents, and with 臺 and 台 the same, as Taiwan
// writes both.

/// What the player typed in a list's search field.
public struct ListSearch: Equatable, Sendable {
    public var query: String

    public init(_ query: String = "") {
        self.query = query
    }

    /// Whether anything but spaces was typed: an empty search keeps every
    /// row.
    public var isActive: Bool {
        !Self.folded(query).isEmpty
    }

    /// Whether any of `names` contains the query (every name does when the
    /// search is empty).
    public func matches(_ names: [String]) -> Bool {
        let wanted = Self.folded(query)
        guard !wanted.isEmpty else { return true }
        return names.contains { Self.folded($0).contains(wanted) }
    }

    /// `text` as compared: trimmed, without case, accents or full-width
    /// forms, and 臺 written 台.
    static func folded(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "臺", with: "台")
    }
}

/// Which lines the lines list shows (decision 184).
public enum LineFilter: String, CaseIterable, Hashable, Sendable {
    /// Every line.
    case all
    /// Passenger lines that lost money yesterday (decision 179's report;
    /// needs line accounts).
    case losing
    /// Freight lines only.
    case freight

    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .all: language.text("All lines", "全部路線")
        case .losing: language.text("Losing money", "只看虧損")
        case .freight: language.text("Freight only", "只看貨運")
        }
    }
}

extension GameWorld {
    /// The stations whose name matches `search`, in the world's order.
    public func stations(matching search: ListSearch) -> [Station] {
        stations.filter { search.matches([$0.name]) }
    }

    /// The filters that mean something in this world: losing money needs
    /// line accounts, freight needs a freight line.
    public var lineFilters: [LineFilter] {
        LineFilter.allCases.filter { filter in
            switch filter {
            case .all: true
            case .losing: lineAccounts != nil
            case .freight: lines.contains(where: \.isFreight)
            }
        }
    }

    /// `lines`, in their order, kept where `filter` allows and the line's
    /// name, or a stop's, matches `search` (so "Taipei" finds the lines
    /// calling there).
    public func lines(_ lines: [ServiceLine], matching search: ListSearch, filter: LineFilter = .all) -> [ServiceLine] {
        lines.filter { line in
            switch filter {
            case .all:
                break
            case .losing:
                guard !line.isFreight, let day = lineReport(line.id)?.yesterday, day.profit < .zero else { return false }
            case .freight:
                guard line.isFreight else { return false }
            }
            return search.matches([line.name] + line.stops.compactMap { station(id: $0)?.name })
        }
    }

    /// `trains`, in their order, whose name or line's name matches
    /// `search`.
    public func trains(_ trains: [Train], matching search: ListSearch) -> [Train] {
        guard search.isActive else { return trains }
        return trains.filter { train in
            let lineName = assignedLine(of: train.id).flatMap { line(id: $0)?.name }
            return search.matches([train.name] + (lineName.map { [$0] } ?? []))
        }
    }
}
