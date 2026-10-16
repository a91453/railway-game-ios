import GameCore

/// The game menu's rows (☰, ``GameMenu`` in the app), in their order, and
/// what each shows. The view draws the rows this lists; which row stands
/// where is decided here, where a Linux test reads it.
///
/// Decision 226, later (2026-10-16): the tutorial, the postcard and the
/// achievements stand side by side in one row of the first level (a
/// compact control group), rather than the postcard under More and the
/// achievements under More → Goals. The first level keeps to six rows
/// (``rowsInReach``), with Back to Start third: on a phone on its side
/// the menu shows about six, and an eighth row put Settings out of reach.
public struct GameMenuLayout: Equatable, Sendable {
    /// A row of the menu's first level.
    public enum Row: String, CaseIterable, Sendable {
        case saveGame, saveOptions, backToStart
        /// The ``shortcuts``, side by side in one row.
        case shortcuts
        case more
        case settings
    }

    /// One of the shortcuts side by side in the first level.
    public enum Shortcut: String, CaseIterable, Sendable {
        case tutorial, postcard, achievements
    }

    /// A row under More.
    public enum MoreRow: String, CaseIterable, Sendable {
        case goals, tourism, help, report
    }

    /// How many rows of the first level a phone on its side shows without
    /// scrolling (TestFlight 54.1).
    public static let rowsInReach = 6

    /// The first level, section by section (a divider between two).
    public let sections: [[Row]]
    /// The shortcuts' row, in order.
    public let shortcuts: [Shortcut]
    /// The rows under More.
    public let moreRows: [MoreRow]

    /// `showsGoals`: a game with a challenge or the city's requests
    /// (decisions 86 and 183); `showsTourism`: one with sights (decision
    /// 174).
    public init(showsGoals: Bool, showsTourism: Bool) {
        sections = [
            [.saveGame, .saveOptions, .backToStart],
            [.shortcuts, .more],
            [.settings],
        ]
        shortcuts = [.tutorial, .postcard, .achievements]
        var more: [MoreRow] = []
        if showsGoals { more.append(.goals) }
        if showsTourism { more.append(.tourism) }
        more += [.help, .report]
        moreRows = more
    }

    /// Decision 200: why a game with unlimited funds counts no
    /// achievements, at the top of their list; `nil` otherwise.
    public static func achievementsNote(unlimitedFunds: Bool, in language: DisplayLanguage) -> String? {
        guard unlimitedFunds else { return nil }
        return language.text("Not counted with unlimited funds.", "資金無限的局不計成就。")
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
