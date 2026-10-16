/// The start screen's language menu (ARCHITECTURE decision 247): follow the
/// iPhone's languages, or always English, or always Traditional Chinese.
///
/// iOS shows an app's language row in Settings only when the device lists
/// two or more languages, so the game offers the choice itself. The choice
/// is the app's own `AppleLanguages` override, the same value iOS Settings
/// writes there; iOS reads it when the app launches, so it takes effect from
/// the next launch.
public enum LanguageChoice: CaseIterable, Hashable, Sendable {
    case system
    case english
    case traditionalChinese

    /// The choice an app's `AppleLanguages` override (nil when it has none)
    /// stands for.
    public init(appleLanguages: [String]?) {
        guard let first = appleLanguages?.first else {
            self = .system
            return
        }
        self = DisplayLanguage(localization: first) == .traditionalChinese ? .traditionalChinese : .english
    }

    /// The app's `AppleLanguages` override for this choice; nil removes it,
    /// so the app follows the iPhone again.
    public var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .traditionalChinese: ["zh-Hant"]
        }
    }

    /// The menu's name for the choice: each language in itself, so a player
    /// who cannot read the current one still finds theirs.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .system: language.text("Same as iPhone", "跟隨 iPhone")
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        }
    }

    /// Whether choosing this, in place of `current` while the game shows
    /// `shown`, may change the language, so the player is told to reopen
    /// the game.
    public func needsRestart(from current: LanguageChoice, showing shown: DisplayLanguage) -> Bool {
        guard self != current else { return false }
        switch self {
        case .system: return true
        case .english: return shown != .english
        case .traditionalChinese: return shown != .traditionalChinese
        }
    }

    /// What the player is told after choosing this: the game changes
    /// language the next time it opens.
    public func restartNote(in language: DisplayLanguage) -> String {
        switch self {
        case .system:
            language.text(
                "The game will use the iPhone's language the next time it opens. Close it from the app switcher and open it again.",
                "下次開啟遊戲時會跟隨 iPhone 的語言。請從多工畫面關掉遊戲，再重新開啟。"
            )
        case .english, .traditionalChinese:
            language.text(
                "The game will be in \(title(in: language)) the next time it opens. Close it from the app switcher and open it again.",
                "下次開啟遊戲時會換成\(title(in: language))。請從多工畫面關掉遊戲，再重新開啟。"
            )
        }
    }
}
