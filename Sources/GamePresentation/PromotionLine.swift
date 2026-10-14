import GameCore

// Decision 224, option 1C: the company's titles (decision 181) as the
// stations of a line, the company's train standing between the title it
// holds and the next, as far along as its score has come; and the seven
// measures of the rank as the cars of a train, each filled as far as its
// points go.

/// The titles as a line, and where the company stands on it.
public struct PromotionLine: Equatable, Sendable {
    /// Every title, the lowest first.
    public let titles: [CompanyTitle]
    /// Where the train stands, from 0 (the first title) to
    /// `titles.count - 1` (the top): the index of the title held plus how
    /// far its score has come towards the next.
    public let position: Double

    public init(rank: CompanyRank) {
        titles = CompanyTitle.allCases
        let index = titles.firstIndex(of: rank.title) ?? 0
        position = Double(index) + (rank.title.next == nil ? 0 : StationMasterTitleProgress.progress(score: rank.score, title: rank.title))
    }

    /// Whether title `index` has been reached.
    public func isReached(_ index: Int) -> Bool {
        Double(index) <= position + 1e-9
    }
}

/// How far a score has come from its title to the next, 0 to 1.
enum StationMasterTitleProgress {
    static func progress(score: Int, title: CompanyTitle) -> Double {
        guard let next = title.next else { return 1 }
        let span = max(1, next.minimumScore - title.minimumScore)
        return min(1, max(0, Double(score - title.minimumScore) / Double(span)))
    }
}

extension CompanyRank.Part {
    /// How many of a car's `cells` squares its points fill, rounded to the
    /// nearest: a full part fills them all, any points at least one.
    public func filledCells(of cells: Int) -> Int {
        guard maximum > 0, points > 0 else { return 0 }
        return min(cells, max(1, Int((Double(points) / Double(maximum) * Double(cells)).rounded())))
    }
}
