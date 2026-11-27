/// The language of the player-facing text (Stage L1): English, Traditional
/// Chinese as written in Taiwan, or Japanese (decision 1034).
///
/// The app picks it from the localization iOS chose for it at launch (the
/// same one its String Catalog uses) and hands it to the ``GameSession``.
/// Every text function here takes it explicitly, so the text stays a pure
/// function of the world and the language, and every language can be tested
/// anywhere GameCore runs.
///
/// Japanese has no sentences of its own at the call sites: `text(english,
/// chinese)` looks the English sentence up in its ``TranslationTable`` and
/// shows the English when the table has no Japanese for it; a later
/// language gets a table of its own the same way. So Japanese
/// behaves as English everywhere else (numbers, money, which name a place
/// shows), and only the sentences the table holds change.
public enum DisplayLanguage: CaseIterable, Hashable, Sendable, Codable {
    case english
    case traditionalChinese
    case japanese

    /// The language for a localization identifier such as "zh-Hant", "ja"
    /// or "en": Chinese for any "zh" identifier (the app has only the
    /// Traditional Chinese one), Japanese for "ja", English for anything
    /// else.
    public init(localization: String) {
        let language = localization.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased()
        switch language {
        case "zh": self = .traditionalChinese
        case "ja": self = .japanese
        default: self = .english
        }
    }

    /// The language whose rules Japanese follows outside its table:
    /// English for Japanese, the language itself otherwise. Code that
    /// chooses between an English and a Chinese way (a number's grouping, a
    /// name's script) asks this rather than comparing with `.english`.
    public var base: DisplayLanguage {
        self == .japanese ? .english : self
    }

    /// `english` in English, `chinese` in Traditional Chinese, and in
    /// Japanese the table's Japanese for `english`'s sentence, or `english`
    /// when the table has none.
    public func text(_ english: @autoclosure () -> DisplayTextTemplate, _ chinese: @autoclosure () -> String) -> String {
        switch self {
        case .english: english().text
        case .traditionalChinese: chinese()
        case .japanese: TranslationTable.japanese.translate(english())
        }
    }

    /// The same for an English sentence that is not written out at the call
    /// (a name from data, a sentence built elsewhere): Japanese looks the
    /// finished sentence up.
    @_disfavoredOverload
    public func text(_ english: @autoclosure () -> String, _ chinese: @autoclosure () -> String) -> String {
        switch self {
        case .english: english()
        case .traditionalChinese: chinese()
        case .japanese: TranslationTable.japanese.translate(english())
        }
    }
}

/// The English argument of ``DisplayLanguage/text(_:_:)``: the finished
/// English, plus the key Japanese is looked up by, the literal with each
/// interpolation written `{0}`, `{1}`, ... in order, and the interpolations'
/// text, which the Japanese puts where its own `{n}` stand (decision 1034).
public struct DisplayTextTemplate: ExpressibleByStringInterpolation, Sendable {
    /// The English as the player reads it.
    public let text: String
    /// The literal with `{n}` for the n-th interpolation.
    public let key: String
    /// Each interpolation's text, in order.
    public let arguments: [String]

    public init(stringLiteral value: String) {
        text = value
        key = value
        arguments = []
    }

    public init(stringInterpolation: Interpolation) {
        text = stringInterpolation.text
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    /// A finished sentence with no interpolations: its key is itself.
    public init(verbatim value: String) {
        self.init(stringLiteral: value)
    }

    public struct Interpolation: StringInterpolationProtocol {
        var text = ""
        var key = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
            key.reserveCapacity(literalCapacity + interpolationCount * 3)
            arguments.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
            key += literal
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            let shown = String(describing: value)
            text += shown
            key += "{"
            key += String(arguments.count)
            key += "}"
            arguments.append(shown)
        }
    }
}
