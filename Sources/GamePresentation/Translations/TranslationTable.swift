import Foundation

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
    /// The sentences with interpolations, to find a finished English
    /// sentence's key by its words (``translate(_:)-(String)``).
    let patterns: PatternIndex
    private let cache = Cache()

    /// The table in `source`'s `key<TAB>sentence` lines; `\\`, `\t` and `\n`
    /// stand for a backslash, a tab and a line break.
    init(source: String) {
        entries = Self.parse(source)
        patterns = PatternIndex(entries)
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

    /// The sentence for a finished English sentence, or the sentence
    /// itself. A sentence written out at a call with interpolations reaches
    /// here finished too: Swift takes a string literal as a `String`
    /// wherever a `String` overload exists, so `text("\(n) trains", ...)`
    /// arrives as "3 trains". So when the table has no sentence of exactly
    /// these words, the sentence is matched against the keys with `{n}`,
    /// their words in place and anything where an interpolation stands
    /// (the key with the most words of its own wins), and the Japanese gets
    /// what stood there.
    public func translate(_ english: String) -> String {
        if let pieces = entries[english] {
            return Self.render(pieces, []) ?? english
        }
        if let known = cache[english] { return known }
        var shown = english
        if let (pattern, arguments) = patterns.match(english) {
            shown = Self.render(pattern.sentence, arguments) ?? english
        }
        cache[english] = shown
        return shown
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

/// The keys with interpolations, by the words they start with, for
/// ``TranslationTable/translate(_:)-(String)``.
struct PatternIndex: Sendable {
    /// One key: its words between the interpolations (one more than
    /// these), which interpolation stands after each, and the sentence.
    struct Pattern: Sendable {
        let words: [String]
        let arguments: [Int]
        let sentence: [TranslationTable.Piece]
        /// How many characters of words the key has, to prefer the most
        /// particular key when several fit.
        let weight: Int
    }

    /// The keys by their first words' first characters (one, two or three).
    let byStart: [String: [Pattern]]
    /// The keys that begin with an interpolation, by their last character.
    let byEnd: [Character: [Pattern]]
    /// The keys that begin and end with one, tried for every sentence.
    let open: [Pattern]
    static let startLength = 3

    init(_ entries: [String: [TranslationTable.Piece]]) {
        var byStart: [String: [Pattern]] = [:]
        var byEnd: [Character: [Pattern]] = [:]
        var open: [Pattern] = []
        for (key, sentence) in entries {
            guard let pattern = Self.pattern(key, sentence) else { continue }
            if let first = pattern.words.first, !first.isEmpty {
                byStart[String(first.prefix(Self.startLength)), default: []].append(pattern)
            } else if let last = pattern.words.last?.last {
                byEnd[last, default: []].append(pattern)
            } else {
                open.append(pattern)
            }
        }
        self.byStart = byStart
        self.byEnd = byEnd
        self.open = open
    }

    /// The key as words and interpolations, or nil when it has no
    /// interpolation, two stand side by side (nothing tells where one ends)
    /// or its words hold no letter (a key such as "{0} · {1}" would only
    /// reorder English); one that begins and ends with an interpolation
    /// needs four characters of words, so that " at " fits but " " not.
    static func pattern(_ key: String, _ sentence: [TranslationTable.Piece]) -> Pattern? {
        var words = [""]
        var arguments: [Int] = []
        for piece in TranslationTable.pieces(of: key) {
            switch piece {
            case .words(let text): words[words.count - 1] += text
            case .argument(let n):
                if arguments.count > 0, words[words.count - 1].isEmpty { return nil }
                arguments.append(n)
                words.append("")
            }
        }
        let weight = words.reduce(0) { $0 + $1.count }
        guard !arguments.isEmpty, words.contains(where: { $0.contains(where: \.isLetter) }) else { return nil }
        guard !words.first!.isEmpty || !words.last!.isEmpty || weight >= 4 else { return nil }
        return Pattern(words: words, arguments: arguments, sentence: sentence, weight: weight)
    }

    /// The key that fits `english` with the most words of its own, and the
    /// text where each of its interpolations stands, by number.
    func match(_ english: String) -> (Pattern, [String])? {
        var best: (Pattern, [String])?
        func consider(_ candidates: [Pattern]?) {
            for pattern in candidates ?? [] where pattern.weight > best?.0.weight ?? -1 && pattern.weight < english.count {
                if let found = Self.fit(pattern, english) { best = (pattern, found) }
            }
        }
        for length in 1...Self.startLength {
            let start = english.prefix(length)
            guard start.count == length else { break }
            consider(byStart[String(start)])
        }
        if let last = english.last { consider(byEnd[last]) }
        consider(open)
        return best
    }

    /// The text where each of `pattern`'s interpolations stands in
    /// `english`, by interpolation number, or nil when it does not fit.
    /// The first words begin it, the last end it, and the words between
    /// are found in order, trying each place one can stand.
    static func fit(_ pattern: Pattern, _ english: String) -> [String]? {
        let words = pattern.words
        guard english.hasPrefix(words.first!), english.hasSuffix(words.last!) else { return nil }
        let start = english.index(english.startIndex, offsetBy: words.first!.count)
        let end = english.index(english.endIndex, offsetBy: -words.last!.count)
        guard start <= end else { return nil }
        var taken: [Substring] = []
        func place(_ i: Int, from: String.Index) -> Bool {
            // i: the words after interpolation i - 1 (1 ... words.count - 2).
            if i == words.count - 1 {
                taken.append(english[from..<end])
                return true
            }
            var searchFrom = from
            while searchFrom <= end,
                  let range = english.range(of: words[i], range: searchFrom..<end) {
                taken.append(english[from..<range.lowerBound])
                if place(i + 1, from: range.upperBound) { return true }
                taken.removeLast()
                guard range.lowerBound < end else { break }
                searchFrom = english.index(after: range.lowerBound)
            }
            return false
        }
        guard place(1, from: start) else { return nil }
        let count = (pattern.arguments.max() ?? -1) + 1
        var arguments = Array(repeating: "", count: count)
        for (n, text) in zip(pattern.arguments, taken) { arguments[n] = String(text) }
        return arguments
    }
}

/// Finished sentences already looked up, so a screen drawn again does not
/// match its sentences again; emptied when it grows past a few thousand.
private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var shown: [String: String] = [:]
    static let limit = 20_000

    subscript(english: String) -> String? {
        get { lock.withLock { shown[english] } }
        set {
            lock.withLock {
                if shown.count >= Self.limit { shown.removeAll(keepingCapacity: true) }
                shown[english] = newValue
            }
        }
    }
}
