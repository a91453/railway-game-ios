import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 184: the player names, renames and orders their
/// saves. The name lies beside the save in a file of its own, never in the
/// save (`SavedGame` is unchanged); the list shows each save's game date
/// and funds.
final class SaveNamingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SaveNamingTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }

    func testASaveIsNamedRenamedAndUnnamed() throws {
        let library = SaveLibrary(directory: directory)
        let named = try library.save(.newGame(), as: .manual, at: date(0), named: "  My\nfirst line  ")
        XCTAssertEqual(named.name, "My first line", "one line, trimmed")
        let plain = try library.save(.newGame(), as: .manual, at: date(60))
        XCTAssertNil(plain.name)
        XCTAssertEqual(library.entries().map(\.name), [nil, "My first line"])

        let renamed = try library.rename(plain, to: "臺北環線")
        XCTAssertEqual(renamed.name, "臺北環線")
        XCTAssertEqual(library.entries().map(\.name), ["臺北環線", "My first line"])
        XCTAssertEqual(try library.load(library.entries()[0]), .newGame(), "the save itself is untouched")

        try library.rename(renamed, to: "   ")
        XCTAssertEqual(library.entries().map(\.name), [nil, "My first line"], "an empty name names it by its date again")

        // The name is no save, and goes with the save it names.
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["save-2026-10-02 120000.json", "save-2026-10-02 120000.name", "save-2026-10-02 120100.json"])
        try library.delete(named)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["save-2026-10-02 120100.json"])
    }

    func testTheAutosaveHasNoName() throws {
        let library = SaveLibrary(directory: directory)
        let autosave = try library.save(.newGame(), as: .autosave, at: date(0), named: "ignored")
        XCTAssertNil(autosave.name)
        XCTAssertThrowsError(try library.rename(autosave, to: "No")) { XCTAssertEqual($0 as? SaveError, .fileSystem) }
        XCTAssertNil(library.entries()[0].name)
    }

    func testALongNameIsCut() {
        XCTAssertEqual(SaveLibrary.cleanName(String(repeating: "線", count: 100))?.count, SaveLibrary.maximumNameLength)
        XCTAssertNil(SaveLibrary.cleanName("\n \t"))
    }

    func testTheOrders() throws {
        let library = SaveLibrary(directory: directory)
        try library.save(.newGame(), as: .manual, at: date(0), named: "beta")
        try library.save(.newGame(), as: .manual, at: date(60))
        try library.save(.newGame(), as: .manual, at: date(120), named: "Alpha")
        try library.save(.newGame(), as: .autosave, at: date(30))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let entries = library.entries()
        func names(_ order: SaveLibrary.Order) -> [String] {
            SaveLibrary.sorted(entries, by: order).map { $0.kind == .autosave ? "auto" : ($0.name ?? $0.id) }
        }
        XCTAssertEqual(names(.newest), ["auto", "Alpha", "save-2026-10-02 120100.json", "beta", "broken.json"])
        XCTAssertEqual(names(.oldest), ["auto", "beta", "save-2026-10-02 120100.json", "Alpha", "broken.json"])
        XCTAssertEqual(names(.name), ["auto", "Alpha", "beta", "save-2026-10-02 120100.json", "broken.json"])
        for order in SaveLibrary.Order.allCases {
            XCTAssertFalse(order.displayName(in: .traditionalChinese).isEmpty)
        }
    }

    func testTheListShowsTheGameDateAndTheFunds() {
        let summary = SaveSummary(world: DemoWorld.make(in: .english))
        XCTAssertEqual(summary.dateAndFundsText(in: .english), "Year 1 · Jan 1 (Mon) 00:00 · Funds $ 708,800")
        XCTAssertEqual(summary.dateAndFundsText(in: .traditionalChinese), "第 1 年 1 月 1 日（一）00:00 · 資金 $ 708,800")
        XCTAssertEqual(summary.networkText(in: .english), "5 stations · 3 lines · 4 trains")
        XCTAssertEqual(summary.networkText(in: .traditionalChinese), "5 座車站 · 3 條路線 · 4 列列車")
    }

    @MainActor
    func testTheLauncherSavesWithANameAndRenames() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        launcher.startNewGame()
        launcher.saveCurrentGame(at: date(0), named: "週末")
        XCTAssertEqual(launcher.session?.message, StatusMessage(kind: .success, text: "已儲存遊戲：「週末」。"))
        let save = try XCTUnwrap(launcher.otherSaves.first { $0.kind == .manual })
        XCTAssertEqual(save.name, "週末")
        launcher.rename(save, to: "平日")
        XCTAssertEqual(launcher.otherSaves.first { $0.kind == .manual }?.name, "平日")
        launcher.session?.stopGameLoop()
    }
}
