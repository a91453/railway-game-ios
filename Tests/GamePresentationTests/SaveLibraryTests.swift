import Foundation
import GameCore
import GamePresentation
import XCTest

/// Stage C4: the save files. JSON with the app's name, when it was saved,
/// a summary for lists and GameCore's versioned `SavedGame`; the
/// autosave and the player's own saves; files that cannot be loaded are
/// listed with the reason.
final class SaveLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SaveLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSavesAreListedAutosaveFirstThenTheNewest() throws {
        let library = SaveLibrary(directory: directory)
        XCTAssertEqual(library.entries(), [], "no folder yet")
        let demo = DemoWorld.make(in: .english)
        try library.save(.newGame(), as: .manual, at: date(0))
        try library.save(demo, as: .manual, at: date(60))
        try library.save(demo, as: .autosave, at: date(30))
        let entries = library.entries()
        XCTAssertEqual(entries.map(\.kind), [.autosave, .manual, .manual])
        XCTAssertEqual(entries.map(\.savedAt), [date(30), date(60), date(0)])
        XCTAssertEqual(entries[0].id, "autosave.json")
        XCTAssertEqual(entries[1].id, "save-2026-10-02 120100.json", "named by the time, in UTC")
        XCTAssertEqual(entries[1].summary, SaveSummary(world: demo))
        XCTAssertTrue(entries.allSatisfy { $0.problem == nil })
        XCTAssertEqual(try library.load(entries[1]), demo)
        XCTAssertEqual(try library.load(entries[2]), .newGame())

        // The autosave is written over; a second save at the same second gets its own name.
        try library.save(.newGame(), as: .autosave, at: date(90))
        try library.save(.newGame(), as: .manual, at: date(60))
        XCTAssertEqual(library.entries().count, 4)
        XCTAssertTrue(library.entries().contains { $0.id == "save-2026-10-02 120100-2.json" })
        XCTAssertEqual(try library.load(library.entries()[0]), .newGame())
    }

    func testTheFileNamesTheAppTheTimeAndTheVersion() throws {
        let data = try SaveLibrary.encode(DemoWorld.make(in: .english), at: date(0))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["app", "savedAt", "summary", "game"])
        XCTAssertEqual(object["app"] as? String, "RailwayGame")
        XCTAssertEqual(object["savedAt"] as? String, "2026-10-02T12:00:00Z")
        let game = try XCTUnwrap(object["game"] as? [String: Any])
        XCTAssertEqual(game["saveVersion"] as? Int, SavedGame.currentVersion)
        XCTAssertEqual(try SaveLibrary.decode(data), DemoWorld.make(in: .english))
    }

    func testTheSummaryReadsInBothLanguages() {
        let summary = SaveSummary(world: DemoWorld.make(in: .english))
        XCTAssertEqual(summary.text(in: .english), "Day 1 · 00:00 · $ 708,800 · 5 stations · 3 lines · 4 trains")
        XCTAssertEqual(summary.text(in: .traditionalChinese), "第 1 日 · 00:00 · $ 708,800 · 5 座車站 · 3 條路線 · 4 列列車")
        XCTAssertEqual(SaveSummary(world: .newGame()).text(in: .english), "Day 1 · 00:00 · $ 3,000,000 · 0 stations · 0 lines · 0 trains")
    }

    func testFilesThatCannotBeLoadedAreListedWithTheReason() throws {
        let library = SaveLibrary(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String) throws {
            try Data(text.utf8).write(to: directory.appendingPathComponent(name))
        }
        let good = String(decoding: try SaveLibrary.encode(.newGame(), at: date(0)), as: UTF8.self)
        try write("garbage.json", "not json")
        try write("other-app.json", good.replacingOccurrences(of: #""app":"RailwayGame""#, with: #""app":"Other""#))
        let newer = SavedGame.currentVersion + 1
        try write("newer.json", good.replacingOccurrences(of: #""saveVersion":\#(SavedGame.currentVersion)"#, with: #""saveVersion":\#(newer)"#))
        try write("damaged.json", good.replacingOccurrences(of: #""width":\#(GameWorld.newGame().bounds.width)"#, with: #""width":-1"#))
        try write("notes.txt", "ignored")
        let entries = Dictionary(uniqueKeysWithValues: library.entries().map { ($0.id, $0) })
        XCTAssertEqual(Set(entries.keys), ["garbage.json", "other-app.json", "newer.json", "damaged.json"])
        XCTAssertEqual(entries["garbage.json"]?.problem, .notASave)
        XCTAssertEqual(entries["other-app.json"]?.problem, .notASave)
        XCTAssertEqual(entries["newer.json"]?.problem, .newerVersion(newer))
        XCTAssertNil(entries["damaged.json"]?.problem, "the header reads; the world is only checked on loading")
        XCTAssertThrowsError(try library.load(entries["damaged.json"]!)) { XCTAssertEqual($0 as? SaveError, .damaged) }
        XCTAssertThrowsError(try library.load(entries["newer.json"]!)) { XCTAssertEqual($0 as? SaveError, .newerVersion(newer)) }
        XCTAssertEqual(
            library.entries().map(\.id), ["damaged.json", "garbage.json", "newer.json", "other-app.json"],
            "files with a date first, then the unreadable ones by name"
        )

        XCTAssertEqual(SaveError.newerVersion(2).playerMessage(in: .english), "That save comes from a newer version of the game (save format 2). Update the app to load it.")
        XCTAssertEqual(SaveError.damaged.playerMessage(in: .traditionalChinese), "這個存檔已損壞，無法讀取。")
    }

    func testTheAutosaveIsArchivedAndSavesAreDeleted() throws {
        let library = SaveLibrary(directory: directory)
        XCTAssertNoThrow(try library.archiveAutosave(), "nothing to keep")
        try library.save(.newGame(), as: .autosave, at: date(0))
        try library.archiveAutosave()
        let entries = library.entries()
        XCTAssertEqual(entries.map(\.kind), [.manual])
        XCTAssertEqual(entries[0].id, "save-2026-10-02 120000.json", "named by when it was saved")
        XCTAssertEqual(entries[0].savedAt, date(0))
        try library.delete(entries[0])
        XCTAssertEqual(library.entries(), [])
        XCTAssertThrowsError(try library.delete(entries[0])) { XCTAssertEqual($0 as? SaveError, .fileSystem) }
    }

    func testAGameIsExportedAsAFileToShare() throws {
        let url = try SaveLibrary.exportFile(for: DemoWorld.make(in: .english), at: date(0))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "RailwayGame 2026-10-02 120000.json")
        XCTAssertEqual(try SaveLibrary.decode(Data(contentsOf: url)), DemoWorld.make(in: .english))
    }

    /// 2026-10-02 12:00:00 UTC plus `seconds`.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }
}
