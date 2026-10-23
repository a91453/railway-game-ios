import GameCore

// ARCHITECTURE decision 316: one way into a new game. The start screen's
// New Game opens a page of the two maps, blank first, then real-world,
// with the new game's options (decision 177) under both, since they apply
// to both: a real-world map was a card of its own, and the options sat
// under the blank map's card as if they were only its.

/// A map a new game can start on, as the new game's page lists them.
public enum NewGameChoice: String, CaseIterable, Sendable {
    /// An empty map to build on (``GameLauncher/startNewGame(at:)``).
    case blank
    /// A map of a real place, chosen in the place picker (decision 312).
    case realWorld

    /// The card's title.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .blank: language.text("Blank Map", "空白地圖")
        case .realWorld: language.text("Real-World Map", "實景地圖")
        }
    }

    /// What the card says under its title: a blank map's starting cash, or
    /// where a real-world map is.
    public func detail(in language: DisplayLanguage, options: NewGameOptions) -> String {
        switch self {
        case .blank:
            options.funds == .unlimited
                ? language.text("An empty map with unlimited funds", "空白地圖，資金無限")
                : language.text("An empty map and \(options.startingBalance.moneyText) to build with", "空白地圖，起始資金 \(options.startingBalance.moneyText)")
        case .realWorld:
            language.text("Build on a map of a real place", "在真實地點的地圖上建造")
        }
    }

    /// The card's SF Symbol: an empty square for a blank map, the globe
    /// the start screen's real-world map card had.
    public var systemImage: String {
        switch self {
        case .blank: "square.dashed"
        case .realWorld: "globe.asia.australia"
        }
    }

    /// The card's identifier, the same in every language, for the UI tests.
    public var identifier: String {
        "newGame.\(rawValue)"
    }

    /// What the start screen's New Game says under its title.
    public static func entryDetail(in language: DisplayLanguage) -> String {
        language.text("A blank map, a real place, or a challenge with goals", "空白地圖、真實地點，或有目標的挑戰")
    }

    /// Decision 381: the page's last card, the challenges (decision 86:
    /// a new game with goals), which used to be a start screen button.
    public static func challengesTitle(in language: DisplayLanguage) -> String {
        language.text("Challenges", "挑戰")
    }

    /// What the challenges' card says under its title.
    public static func challengesDetail(in language: DisplayLanguage) -> String {
        language.text(
            "Goals to reach by a deadline, rated gold, silver or bronze",
            "在期限內達成目標，依完成速度拿金、銀、銅牌"
        )
    }

    /// The challenges' card's identifier, for the UI tests.
    public static let challengesIdentifier = "newGame.challenges"

    /// The options' row: the rules, the difficulty and the cash.
    public static func optionsSummary(_ options: NewGameOptions, in language: DisplayLanguage) -> String {
        let cash = options.funds == .unlimited ? "∞" : options.startingBalance.moneyText
        return language.text(
            "New Game Options · \(options.rules.title(in: language)) · \(options.difficulty.title(in: language)) · \(cash)",
            "新遊戲選項 · \(options.rules.title(in: language))規則 · \(options.difficulty.title(in: language)) · \(cash)"
        )
    }

    /// Under the options' row: that both maps start with them.
    public static func optionsNote(in language: DisplayLanguage) -> String {
        language.text("Both maps start with these options.", "兩種地圖都套用這些選項。")
    }
}
