import GameCore

/// The game menu's rows (☰, ``GameMenu`` in the app), in their order, and
/// what each shows. The view draws the rows this lists; which row stands
/// where is decided here, where a Linux test reads it.
///
/// Decision 226, later (2026-10-16): the postcard and the achievements
/// stand in the first level, beside the tutorial, rather than under More
/// (postcard) and More → Goals (achievements). Back to Start stays the
/// third row, in reach on a phone on its side.
public struct GameMenuLayout: Equatable, Sendable {
    /// A row of the menu's first level.
    public enum Row: String, CaseIterable, Sendable {
        case saveGame, saveOptions, backToStart
        case tutorial, postcard, achievements, more
        case settings
    }

    /// A row under More.
    public enum MoreRow: String, CaseIterable, Sendable {
        case goals, tourism, help, report
    }

    /// The first level, section by section (a divider between two).
    public let sections: [[Row]]
    /// The rows under More.
    public let moreRows: [MoreRow]

    /// `showsGoals`: a game with a challenge or the city's requests
    /// (decisions 86 and 183); `showsTourism`: one with sights (decision
    /// 174).
    public init(showsGoals: Bool, showsTourism: Bool) {
        sections = [
            [.saveGame, .saveOptions, .backToStart],
            [.tutorial, .postcard, .achievements, .more],
            [.settings],
        ]
        var more: [MoreRow] = []
        if showsGoals { more.append(.goals) }
        if showsTourism { more.append(.tourism) }
        more += [.help, .report]
        moreRows = more
    }

    /// The achievements row's title and, in a game with unlimited funds,
    /// why it counts none (decision 200); `isEnabled` is false then, and
    /// the row is greyed.
    public static func achievementsRow(
        unlocked: Int, total: Int = Achievement.all.count, unlimitedFunds: Bool, in language: DisplayLanguage
    ) -> (title: String, subtitle: String?, isEnabled: Bool) {
        let title = language.text("Achievements \(unlocked)/\(total)", "成就 \(unlocked)/\(total)")
        guard unlimitedFunds else { return (title, nil, true) }
        return (title, language.text("Not counted with unlimited funds", "資金無限的局不計成就"), false)
    }
}

/// Decision 229, later (2026-10-16): the map's own button that opens this
/// game's 3D map, beside the zoom buttons, so it is one tap away rather
/// than in the settings.
public enum Map3DShortcut {
    /// Whether the button shows: with the zoom buttons (they give way
    /// beside a wide card on a phone, and it with them), and not while the
    /// tutorial runs, whose steps would be left behind under the 3D map.
    public static func isShown(zoomButtonsShow: Bool, tutorialRuns: Bool) -> Bool {
        zoomButtonsShow && !tutorialRuns
    }
}
