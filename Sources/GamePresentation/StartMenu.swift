// ARCHITECTURE decision 381: the start screen's six buttons and two
// capsules. Saved Games and Import a Save became one Saves button, which
// always shows (importing is in its list); Challenges moved into New Game,
// Language into Settings, and Data Sources into Help (and the foot of
// Settings).

/// A button on the start screen, in the order it lists them.
public enum StartMenuEntry: String, CaseIterable, Sendable {
    /// The latest autosave, when there is one.
    case continueGame
    /// The new game's page: a blank map, a real place or a challenge.
    case newGame
    /// The lessons (decision 266).
    case lessons
    /// The demos (decision 135).
    case demoMap
    /// The saves, and importing one from a file.
    case saves
    /// What the player has done across games (decision 181).
    case achievements

    /// The buttons the start screen shows: Continue only with an autosave
    /// to continue; every other one always.
    public static func entries(hasAutosave: Bool) -> [StartMenuEntry] {
        allCases.filter { $0 != .continueGame || hasAutosave }
    }

    /// The button's identifier, the same in every language, for the UI
    /// tests.
    public var identifier: String {
        switch self {
        case .continueGame: "start.continue"
        case .newGame: "start.newGame"
        case .lessons: "start.lessons"
        case .demoMap: "start.demoMap"
        case .saves: "start.saves"
        case .achievements: "start.achievements"
        }
    }

    /// The Saves button's title.
    public static func savesTitle(in language: DisplayLanguage) -> String {
        language.text("Saves", "存檔")
    }

    /// What the Saves button says under its title: how many saves there
    /// are (the player's own and the earlier autosaves), or, with none,
    /// that one can be imported.
    public static func savesDetail(count: Int, in language: DisplayLanguage) -> String {
        switch count {
        case ...0:
            language.text("Import a save from Files or another device", "從檔案或另一台裝置匯入存檔")
        case 1:
            language.text("1 save, or import one from a file", "1 個存檔，也可以從檔案匯入")
        default:
            language.text("\(count) saves, or import one from a file", "\(count) 個存檔，也可以從檔案匯入")
        }
    }
}

/// A capsule under the start screen's buttons.
public enum StartMenuChip: String, CaseIterable, Sendable {
    /// The help guide, with the data sources and licences in it.
    case help
    /// The settings, with the language at the top.
    case settings

    /// The capsule's identifier, for the UI tests.
    public var identifier: String {
        "start.\(rawValue)"
    }
}

/// The saves' list: its title, and its row that imports a save file.
public enum SaveListText {
    /// The list's title.
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Saves", "存檔")
    }

    /// The import row's title.
    public static func importTitle(in language: DisplayLanguage) -> String {
        language.text("Import from Files", "從檔案匯入")
    }

    /// Under the import row: where a save file comes from, and that it
    /// opens at once.
    public static func importDetail(in language: DisplayLanguage) -> String {
        language.text(
            "A save exported from this or another device. It opens as soon as it is read.",
            "從這台或另一台裝置匯出的存檔，讀取後馬上開始。"
        )
    }

    /// The import row's identifier, for the UI tests.
    public static let importIdentifier = "saves.import"

    /// What VoiceOver says of a row's "⋯" button, which holds what the
    /// row's swipe and long press do.
    public static func rowMenuLabel(in language: DisplayLanguage) -> String {
        language.text("Save Options", "存檔選項")
    }

    /// The row menu's choices: rename (the player's own saves only),
    /// export, and delete, which asks first.
    public enum RowAction: CaseIterable, Sendable {
        case rename, export, delete

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .rename: language.text("Rename", "重新命名")
            case .export: language.text("Export", "匯出")
            case .delete: language.text("Delete", "刪除")
            }
        }

        /// The SF Symbol beside the title.
        public var systemImage: String {
            switch self {
            case .rename: "pencil"
            case .export: "square.and.arrow.up"
            case .delete: "trash"
            }
        }

        /// The choices for `entry`: a save that cannot be read can only be
        /// deleted; an autosave has no name of its own to change.
        public static func available(for entry: SaveLibrary.Entry) -> [RowAction] {
            if entry.problem != nil { return [.delete] }
            return entry.kind == .manual ? [.rename, .export, .delete] : [.export, .delete]
        }
    }

    /// A row's "⋯" button's identifier, for the UI tests.
    public static func rowMenuIdentifier(of entry: SaveLibrary.Entry) -> String {
        "saves.menu.\(entry.id)"
    }
}

/// The way to the data sources and licences (``DataSourceCredits``): a row
/// at the top of Help and one in Settings, since the start screen's Data
/// Sources capsule went (decision 381).
public enum DataSourcesEntry {
    /// The row's title.
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Data Sources and Licences", "資料來源與授權")
    }

    /// Under the row's title in Help.
    public static func detail(in language: DisplayLanguage) -> String {
        language.text(
            "Where the maps, railways and places come from, and the licences they are used under",
            "地圖、鐵路與地名從哪裡來，以及使用的授權"
        )
    }

    /// The row's identifier in Help, for the UI tests.
    public static let helpIdentifier = "help.dataSources"
    /// The row's identifier in Settings, for the UI tests.
    public static let settingsIdentifier = "settings.dataSources"

    /// Whether Help's search, `query`, shows the row: with no search, and
    /// with a search for one of its words in either language.
    public static func shows(matching query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !words.isEmpty else { return true }
        let haystack = [
            title(in: .english), title(in: .traditionalChinese),
            detail(in: .english), detail(in: .traditionalChinese),
            "OpenStreetMap OSM ODbL credits copyright attribution 版權 出處 開放資料",
        ].joined(separator: "\n").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
