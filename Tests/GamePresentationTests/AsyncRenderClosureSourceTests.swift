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
///
/// CRASHSWEEP-2 adds the other places SwiftUI builds views as it lays
/// them out rather than when a `body` runs: a lazy stack's or grid's
/// cells (built as they come into the laid-out area), read the same way
/// from each `LazyVGrid`, `LazyHGrid`, `LazyVStack` and `LazyHStack`; and
/// every `GeometryReader`, whose closure SwiftUI calls again whenever its
/// size changes, as an animated layout does frame by frame. The readers
/// not yet changed are listed in ``geometryReadersLeft``, a list that
/// only shrinks.
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

    /// CRASHSWEEP-2: the `GeometryReader`s still written as main-actor
    /// code, by file, and why each waits. Each stands where its size moves
    /// only with the window, the screen or a sheet (no recorded crash has
    /// come from one in 100 releases); the next sweeps change them, and
    /// take them off here. A new reader is sendable from the start.
    private static let geometryReadersLeft = [
        "ContentView.swift": 1, // the whole screen's layout
        "MapView.swift": 1, // the 2D map's viewport
        "Map3D/Map3DPreviewScreen.swift": 1, // the 3D station tag's viewport
        "TutorialOverlay.swift": 1, // the lesson card's viewport
        "TrainRosterView.swift": 1, // the roster's table height
        "TrainDiagramView.swift": 1, // the diagram's canvas
        "RealWorldPicker.swift": 1, // the sheet's turn to landscape
        "RealWorldLoadingView.swift": 1, // the loading screen
        "PostcardView.swift": 1, // the postcard sheet's scale
        "SharedNetworkViews.swift": 1, // a shared postcard's scale
        "StationStampPassportView.swift": 1, // a passport page
        "PromotionLineView.swift": 1, // the promotion sheet's line
        "RollingStockCatalogView.swift": 1, // a catalog card's train
    ]

    func testNoMainActorClosureIsMeasuredOffTheMainThread() throws {
        let sources = try Self.readViews()
        let found = Self.scan(sources)
        XCTAssertGreaterThan(found.measured, 20, "the scan finds the app's ViewThatFits")
        XCTAssertEqual(found.problems, [], """
            a closure SwiftUI keeps and calls later stands in a ViewThatFits: \
            make it @Sendable and build a view of its own there (CRASH101)
            """)
    }

    /// CRASHSWEEP-2: a lazy grid's or stack's cells, and what they make.
    func testNoMainActorClosureIsBuiltInALazyContainer() throws {
        let sources = try Self.readViews()
        let found = Self.scan(sources, roots: Self.lazyContainers)
        XCTAssertGreaterThanOrEqual(found.measured, 6, "the scan finds the app's lazy grids")
        XCTAssertEqual(found.problems, [], """
            a closure SwiftUI keeps and calls later stands in a lazy grid or \
            stack, which builds its cells as it lays them out: make it \
            @Sendable and build a view of its own there (CRASHSWEEP-2)
            """)
    }

    /// CRASHSWEEP-2: every `GeometryReader` is sendable, but those left.
    func testGeometryReadersAreSendable() throws {
        let sources = try Self.readViews()
        var left: [String: Int] = [:]
        for (file, text) in sources {
            let count = Self.matches(#"\bGeometryReader\s*\{(?!\s*@Sendable)"#, in: text).count
            if count > 0 { left[file] = count }
        }
        XCTAssertEqual(left, Self.geometryReadersLeft, """
            a GeometryReader's closure runs again whenever its size changes, \
            which the asynchronous renderer may do off the main thread: make \
            a new one @Sendable and build a view of its own there; when one \
            on the list is changed, take it off (CRASHSWEEP-2)
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

    /// The scan reads lazy grids' cells, and what they make, as it reads
    /// a ViewThatFits.
    func testTheScanFindsALazyGridsCells() {
        let sources = ["Grid.swift": Self.strip("""
            struct Grid: View {
                var body: some View {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                        ForEach(kinds, id: \\.self) { kind in Text(kind) }
                        ForEach(kinds, id: \\.self) { @Sendable kind in Cell(kind: kind) }
                    }
                }
            }
            struct Cell: View {
                var body: some View {
                    Canvas { context, size in }
                    Canvas { @Sendable context, size in }
                }
            }
            """)]
        let found = Self.scan(sources, roots: Self.lazyContainers)
        XCTAssertEqual(found.measured, 1)
        XCTAssertEqual(found.problems, ["Grid.swift:3 Canvas", "Grid.swift:3 ForEach(kinds, id: \\.self)"])
    }

    // MARK: - Reading the sources

    private static func readViews() throws -> [String: String] {
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: views.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted()
        var sources: [String: String] = [:]
        for file in files {
            sources[file] = strip(try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8))
        }
        return sources
    }

    /// Where a container's content opens: the `{` after its arguments, if
    /// any (which may hold brackets of their own, as a grid's columns do).
    private typealias Roots = @Sendable (String, [UInt16]) -> [Int]

    private static let viewThatFits: Roots = { text, _ in
        matches(#"ViewThatFits\([^)]*\)\s*\{"#, in: text).map { $0.range.upperBound - 1 }
    }

    private static let lazyContainers: Roots = { text, utf16 in
        matches(#"\bLazy[VH](?:Grid|Stack)\b"#, in: text).compactMap { match in
            var index = match.range.upperBound
            while index < utf16.count, utf16[index] == 32 || utf16[index] == 10 { index += 1 }
            if index < utf16.count, utf16[index] == UInt16(UInt8(ascii: "(")) {
                index = close(utf16, from: index, "(", ")") + 1
                while index < utf16.count, utf16[index] == 32 || utf16[index] == 10 { index += 1 }
            }
            return index < utf16.count && utf16[index] == UInt16(UInt8(ascii: "{")) ? index : nil
        }
    }

    private struct TypeBlock {
        let name: String
        let file: String
        let range: Range<Int>
    }

    private static func scan(_ sources: [String: String], roots: Roots = viewThatFits) -> (measured: Int, problems: [String]) {
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
            for open in roots(text, utf16) {
                guard let block = scope(file, open) else { continue }
                measured += 1
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
                let line = text.utf16.prefix(open).filter { $0 == 10 }.count + 1
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
            (#"\bCanvas\s*(?:\([^)]*\))?\s*\{(?!\s*@Sendable)"#, "Canvas"),
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
