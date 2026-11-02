import Foundation
import XCTest

/// CRASH101 and CRASHSWEEP (101.1 on two iPads): SwiftUI's asynchronous
/// renderer measures the layouts of a `ViewThatFits` off the main thread,
/// and builds what they hold as it does. A closure written in a view's
/// `body` is main-actor code in Swift 6, and one that SwiftUI or Charts
/// keeps and calls later (a `ForEach` row, a `GeometryReader`, a chart's
/// marks or background) checks at its first line that it runs on the main
/// thread, and stops the app when it does not (`_dispatch_assert_queue_fail`).
/// So inside a `ViewThatFits` such a closure is `@Sendable`, or not there.
///
/// This reads the app's views as text: each `ViewThatFits`, the helpers it
/// calls in its own type, and the views it makes (their `body`, and their
/// helpers), leaving out what a menu, popover, sheet or dialog shows: that
/// is built when it opens, not measured with the layout (the HUD's game
/// menu, rows and all, stands in each of the HUD's four layouts, which a
/// tick changes every second, and no crash has come from it).
final class AsyncRenderClosureSourceTests: XCTestCase {
    private static let views = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Views")

    /// Views followed by other views in their place, with why.
    private static let followedInstead = [
        // The tool column (ContentView's ToolsColumn) makes only these two
        // arrangements; the others (the details card's) are not in a
        // ViewThatFits.
        "ControlPanel": ["QuickEntries", "BuildEntry"],
    ]

    func testNoMainActorClosureIsMeasuredOffTheMainThread() throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: Self.views.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted()
        var sources: [String: String] = [:]
        for file in files {
            sources[file] = Self.strip(try String(contentsOf: Self.views.appendingPathComponent(file), encoding: .utf8))
        }
        let found = Self.scan(sources)
        XCTAssertGreaterThan(found.measured, 20, "the scan finds the app's ViewThatFits")
        XCTAssertEqual(found.problems, [], """
            a closure SwiftUI keeps and calls later stands in a ViewThatFits: \
            make it @Sendable and build a view of its own there (CRASH101)
            """)
    }

    /// The scan itself: it finds a row closure in a helper and in a view
    /// the layout makes, and lets a sendable one and a menu's rows be.
    func testTheScanFindsWhatItLooksFor() {
        let sources = ["Bar.swift": Self.strip("""
            struct Bar: View {
                var body: some View {
                    ViewThatFits(in: .horizontal) {
                        HStack { speeds; Badge(); menu }
                        speeds
                    }
                }
                private var speeds: some View {
                    ForEach(items, id: \\.self) { item in Text(item) }
                }
                private var fine: some View {
                    ForEach(items, id: \\.self) { @Sendable item in Row(item: item) }
                }
                private var menu: some View {
                    Menu { ForEach(items, id: \\.self) { item in Text(item) } } label: { Text("x") }
                }
            }
            struct Badge: View {
                var body: some View {
                    GeometryReader { proxy in Color.clear }
                }
            }
            """)]
        let found = Self.scan(sources)
        XCTAssertEqual(found.measured, 1)
        XCTAssertEqual(found.problems, ["Bar.swift:3 ForEach(items, id: \\.self)", "Bar.swift:3 GeometryReader"])
    }

    // MARK: - Reading the sources

    private struct TypeBlock {
        let name: String
        let file: String
        let range: Range<Int>
    }

    private static func scan(_ sources: [String: String]) -> (measured: Int, problems: [String]) {
        var types: [TypeBlock] = []
        var helpers: [String: [String: [String]]] = [:]
        for (file, text) in sources {
            let utf16 = Array(text.utf16)
            for match in matches(#"\b(?:struct|extension)\s+(\w+)[^{\n]*\{"#, in: text) {
                let open = match.range.upperBound - 1
                types.append(TypeBlock(name: substring(text, match.range(at: 1)), file: file,
                                       range: open..<close(utf16, from: open, "{", "}")))
            }
        }
        func scope(_ file: String, _ position: Int) -> TypeBlock? {
            types.filter { $0.file == file && $0.range.contains(position) }.max { $0.range.lowerBound < $1.range.lowerBound }
        }
        func key(_ block: TypeBlock) -> String { "\(block.file)#\(block.range.lowerBound)" }
        for (file, text) in sources {
            let utf16 = Array(text.utf16)
            for match in matches(#"(?:func|var)\s+(\w+)\b[^{=\n]*\{"#, in: text) {
                guard let block = scope(file, match.range.location) else { continue }
                let open = match.range.upperBound - 1
                let body = substring(text, NSRange(location: open, length: close(utf16, from: open, "{", "}") - open + 1))
                helpers[key(block), default: [:]][substring(text, match.range(at: 1)), default: []].append(body)
            }
        }
        let typesByName = Dictionary(grouping: types, by: \.name)

        var measured = 0
        var problems: [String] = []
        for file in sources.keys.sorted() {
            let text = sources[file]!
            let utf16 = Array(text.utf16)
            for match in matches(#"ViewThatFits\([^)]*\)\s*\{"#, in: text) {
                guard let block = scope(file, match.range.location) else { continue }
                measured += 1
                let open = match.range.upperBound - 1
                var work = [(substring(text, NSRange(location: open, length: close(utf16, from: open, "{", "}") - open + 1)), key(block))]
                var seen: Set<String> = []
                var reached = ""
                while let (part, owner) = work.popLast() {
                    let shown = cutPresented(part)
                    reached += shown + "\n"
                    for name in Set(matches(#"\b([A-Za-z_]\w*)\b"#, in: shown).map { substring(shown, $0.range(at: 1)) }) {
                        if name != "body", let bodies = helpers[owner]?[name], seen.insert("\(owner).\(name)").inserted {
                            work += bodies.map { ($0, owner) }
                        }
                    }
                    for made in Set(matches(#"\b([A-Z]\w*)\s*\("#, in: shown).map({ substring(shown, $0.range(at: 1)) })) {
                        for name in followedInstead[made] ?? [made] {
                            for type in typesByName[name] ?? [] {
                                let typeKey = key(type)
                                if let bodies = helpers[typeKey]?["body"], seen.insert("\(typeKey).body").inserted {
                                    work += bodies.map { ($0, typeKey) }
                                }
                            }
                        }
                    }
                }
                let line = text.utf16.prefix(match.range.location).filter { $0 == 10 }.count + 1
                problems += kept(in: reached).map { "\(file):\(line) \($0)" }
            }
        }
        return (measured, problems.sorted())
    }

    /// The closures in `text` that SwiftUI or Charts keep and call later,
    /// written as main-actor code.
    private static func kept(in text: String) -> [String] {
        let utf16 = Array(text.utf16)
        var found: [String] = []
        // A ForEach's rows and a data chart's marks: the trailing closure
        // after the arguments.
        for match in matches(#"\b(ForEach|Chart)\("#, in: text) {
            let open = match.range.upperBound - 1
            let end = close(utf16, from: open, "(", ")")
            let after = substring(text, NSRange(location: end + 1, length: min(40, utf16.count - end - 1)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard after.hasPrefix("{") else { continue }
            if !after.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@Sendable") {
                found.append(substring(text, NSRange(location: match.range.location, length: end - match.range.location + 1)))
            }
        }
        for (pattern, name) in [
            (#"\bGeometryReader\s*\{(?!\s*@Sendable)"#, "GeometryReader"),
            (#"\.chartBackground\s*\{(?!\s*@Sendable)"#, "chartBackground"),
            (#"\.chartOverlay\s*\{(?!\s*@Sendable)"#, "chartOverlay"),
            (#"\.alignmentGuide\("#, "alignmentGuide"),
            (#"\bCanvas\s*[({]"#, "Canvas"),
            (#"\bTimelineView\("#, "TimelineView"),
        ] {
            found += matches(pattern, in: text).map { _ in name }
        }
        return found
    }

    /// `text` less what opens over it later: a menu's, popover's, sheet's,
    /// dialog's or context menu's rows.
    private static func cutPresented(_ text: String) -> String {
        var text = text
        for pattern in [#"\bMenu\s*\{"#, #"\.popover\("#, #"\.sheet\("#, #"\.confirmationDialog\("#, #"\.alert\("#, #"\.contextMenu\s*\{"#] {
            while let match = matches(pattern, in: text).first {
                let utf16 = Array(text.utf16)
                guard let open = utf16[(match.range.upperBound - 1)...].firstIndex(of: UInt16(UInt8(ascii: "{"))) else { break }
                let end = close(utf16, from: open, "{", "}")
                text = (text as NSString).replacingCharacters(
                    in: NSRange(location: match.range.location, length: end + 1 - match.range.location), with: "")
            }
        }
        return text
    }

    /// The source less its comments, so a comment naming a ForEach is not
    /// read as one.
    private static func strip(_ source: String) -> String {
        source.components(separatedBy: "\n").map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
            guard let comment = line.range(of: #"\s//\s.*$"#, options: .regularExpression) else { return line }
            return String(line[..<comment.lowerBound])
        }.joined(separator: "\n")
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    /// Where the bracket opened at `open` closes.
    private static func close(_ utf16: [UInt16], from open: Int, _ opening: Unicode.Scalar, _ closing: Unicode.Scalar) -> Int {
        let up = UInt16(opening.value), down = UInt16(closing.value)
        var depth = 0
        var index = open
        while index < utf16.count {
            if utf16[index] == up { depth += 1 }
            if utf16[index] == down {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return utf16.count - 1
    }
}
