/// One language's sentences beside English (decision 1034): a table from each
/// English sentence's key (``DisplayTextTemplate/key``) to the language's
/// sentence, in which `{0}`, `{1}`, ... stand for the English sentence's
/// interpolations, in any order, any number of times or not at all (an
/// English plural ending has no place in Japanese).
///
/// Each language has its own generated file in this folder (Japanese.swift
/// for ``japanese``), written by tools/translations/merge.py. A new language
/// is a new ``DisplayLanguage`` case, a new file and a new static table here;
/// no call site changes. English and Traditional Chinese stay at the call
/// sites, `text(english, chinese)`.
public struct TranslationTable: Sendable {
    /// One piece of a translated sentence: words, or the n-th interpolation.
    enum Piece: Equatable, Sendable {
        case words(String)
        case argument(Int)
    }

    let entries: [String: [Piece]]

    /// The table in `source`'s `key<TAB>sentence` lines; `\\`, `\t` and `\n`
    /// stand for a backslash, a tab and a line break.
    init(source: String) {
        entries = Self.parse(source)
    }

    /// The Japanese, read once.
    public static let japanese = TranslationTable(source: japaneseSource)

    /// How many sentences the table has.
    public var count: Int { entries.count }

    /// Whether the table has this English sentence.
    public func has(_ english: DisplayTextTemplate) -> Bool {
        entries[english.key] != nil
    }

    /// The sentence for `english`, or `english`'s own text when the table
    /// has none or its sentence names an interpolation the English has not.
    public func translate(_ english: DisplayTextTemplate) -> String {
        guard let pieces = entries[english.key] else { return english.text }
        return Self.render(pieces, english.arguments) ?? english.text
    }

    /// The sentence for a finished English sentence (one with no
    /// interpolations of its own), or the sentence itself.
    public func translate(_ english: String) -> String {
        guard let pieces = entries[english] else { return english }
        return Self.render(pieces, []) ?? english
    }

    static func render(_ pieces: [Piece], _ arguments: [String]) -> String? {
        var out = ""
        for piece in pieces {
            switch piece {
            case .words(let words): out += words
            case .argument(let n):
                guard arguments.indices.contains(n) else { return nil }
                out += arguments[n]
            }
        }
        return out
    }

    static func parse(_ source: String) -> [String: [Piece]] {
        var table: [String: [Piece]] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let key = unescape(line[..<tab])
            let sentence = unescape(line[line.index(after: tab)...])
            table[key] = pieces(of: sentence)
        }
        return table
    }

    static func unescape(_ text: Substring) -> String {
        guard text.contains("\\") else { return String(text) }
        var out = ""
        var escaping = false
        for character in text {
            if escaping {
                switch character {
                case "t": out.append("\t")
                case "n": out.append("\n")
                case "\\": out.append("\\")
                default: out.append("\\"); out.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                out.append(character)
            }
        }
        if escaping { out.append("\\") }
        return out
    }

    /// Splits a sentence at its `{n}`; a brace not followed by digits and
    /// `}` is words.
    static func pieces(of sentence: String) -> [Piece] {
        var pieces: [Piece] = []
        var words = ""
        var rest = Substring(sentence)
        while let open = rest.firstIndex(of: "{") {
            words += rest[..<open]
            let after = rest[rest.index(after: open)...]
            let digits = after.prefix { $0.isASCII && $0.isNumber }
            if !digits.isEmpty, let n = Int(digits), after[digits.endIndex...].first == "}" {
                if !words.isEmpty { pieces.append(.words(words)); words = "" }
                pieces.append(.argument(n))
                rest = after[after.index(after: digits.endIndex)...]
            } else {
                words += "{"
                rest = after
            }
        }
        words += rest
        if !words.isEmpty { pieces.append(.words(words)) }
        return pieces
    }
}
