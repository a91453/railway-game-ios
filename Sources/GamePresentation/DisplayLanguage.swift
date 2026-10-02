/// The language of the player-facing text (Stage L1): English, or
/// Traditional Chinese as written in Taiwan.
///
/// The app picks it from the localization iOS chose for it at launch (the
/// same one its String Catalog uses) and hands it to the ``GameSession``.
/// Every text function here takes it explicitly, so the text stays a pure
/// function of the world and the language, and both languages can be tested
/// anywhere GameCore runs.
public enum DisplayLanguage: CaseIterable, Hashable, Sendable {
    case english
    case traditionalChinese

    /// The language for a localization identifier such as "zh-Hant" or
    /// "en": Chinese for any "zh" identifier (the app has only the
    /// Traditional Chinese one), English for anything else.
    public init(localization: String) {
        let language = localization.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        self = language?.lowercased() == "zh" ? .traditionalChinese : .english
    }

    /// `english` in English, `chinese` in Traditional Chinese.
    func text(_ english: @autoclosure () -> String, _ chinese: @autoclosure () -> String) -> String {
        switch self {
        case .english: english()
        case .traditionalChinese: chinese()
        }
    }
}
