import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 192: the periodic autosave is taken in turn into one of five
/// slots, the autosave on leaving the game stays the latest, the player can
/// go back to an older one (and undo it), a new game keeps the newest and
/// deletes the rest, and a folder of a build before 192 (`autosave.json`
/// alone) reads as before.
final class AutosaveSlotsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutosaveSlotsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// A new game `ticks` ticks on.
    private func world(after ticks: Int) throws -> GameWorld {
        var world = GameWorld.newGame()
        try world.advance(ticks: ticks)
        return world
    }

    // MARK: - The library

    func testSlotsAreTakenInTurnAndTheOldestGoes() throws {
        let library = SaveLibrary(directory: directory)
        var removed: [[String]] = []
        for minute in 1 ... 7 {
            let write = try library.saveAutosaveSlot(world(after: minute), news: NewsLog(), at: date(Double(minute) * 900))
            XCTAssertEqual(write.entry.id, "autosave-\(minute).json")
            XCTAssertEqual(write.entry.slot, minute)
            removed.append(write.removed)
        }
        XCTAssertEqual(removed, [[], [], [], [], [], ["autosave-1.json"], ["autosave-2.json"]])
        XCTAssertEqual(try files(), (3 ... 7).flatMap { ["autosave-\($0).json", "autosave-\($0).news.json"] }.sorted(), "five kept, news logs with them")
        let entries = library.entries()
        XCTAssertEqual(entries.map(\.kind), Array(repeating: .autosave, count: 5))
        XCTAssertEqual(entries.map(\.id), (3 ... 7).reversed().map { "autosave-\($0).json" }, "the newest first")
        XCTAssertEqual(try library.load(entries[0]), try world(after: 7))
        XCTAssertEqual(library.autosaves(), entries)
    }

    func testTheLatestAutosaveIsNotASlot() throws {
        let library = SaveLibrary(directory: directory)
        try library.saveAutosaveSlot(world(after: 1), at: date(0))
        try library.save(world(after: 2), as: .autosave, at: date(60))
        try library.save(world(after: 3), as: .manual, at: date(120))
        let entries = library.entries()
        XCTAssertEqual(entries.map(\.id), ["autosave.json", "autosave-1.json", "save-2026-10-02 120200.json"])
        XCTAssertEqual(entries.map(\.slot), [nil, 1, nil])
        XCTAssertEqual(library.autosaves().map(\.id), ["autosave.json", "autosave-1.json"])
    }

    func testOnlyItsOwnNamesAreSlots() throws {
        let library = SaveLibrary(directory: directory)
        let data = try SaveLibrary.encode(world(after: 1), at: date(0))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = ["autosave-1.json", "autosave-12.json", "autosave-.json", "autosave-x.json", "save-autosave-1.json", "autosave-\u{0661}.json"]
        for name in names {
            try data.write(to: directory.appendingPathComponent(name))
        }
        let slots = Dictionary(uniqueKeysWithValues: library.entries().map { ($0.id, $0.slot ?? 0) })
        XCTAssertEqual(slots, [
            "autosave-1.json": 1, "autosave-12.json": 12,
            "autosave-.json": 0, "autosave-x.json": 0, "save-autosave-1.json": 0, "autosave-\u{0661}.json": 0,
        ])
        XCTAssertEqual(library.autosaves().map(\.id), ["autosave-12.json", "autosave-1.json"], "saved at one moment: the higher number first")
    }

    func testKeepingTheLatestInASlotMovesIt() throws {
        let library = SaveLibrary(directory: directory)
        XCTAssertNoThrow(try library.keepLatestAutosaveInSlot(), "nothing to keep")
        try library.saveAutosaveSlot(world(after: 1), at: date(0))
        try library.save(world(after: 2), news: NewsLog(), as: .autosave, at: date(60))
        try library.keepLatestAutosaveInSlot()
        XCTAssertEqual(try files(), ["autosave-1.json", "autosave-2.json", "autosave-2.news.json"])
        XCTAssertEqual(library.entries().first?.savedAt, date(60), "still the newest, by when it was saved")
    }

    /// The reference's relative time (`city_world`'s `p(e, t)`), rounded
    /// at each step as it is.
    func testHowLongAgo() {
        let now = date(100_000)
        func ago(_ seconds: TimeInterval, _ language: DisplayLanguage = .english) -> String {
            SaveLibrary.agoText(from: now.addingTimeInterval(-seconds), to: now, in: language)
        }
        XCTAssertEqual(ago(-30), "just now", "a clock set back")
        XCTAssertEqual(ago(0), "just now")
        XCTAssertEqual(ago(44.4), "just now")
        XCTAssertEqual(ago(45), "1 min ago")
        XCTAssertEqual(ago(89), "1 min ago")
        XCTAssertEqual(ago(90), "2 min ago")
        XCTAssertEqual(ago(15 * 60), "15 min ago")
        XCTAssertEqual(ago(3_569), "59 min ago")
        XCTAssertEqual(ago(3_570), "1 h ago")
        XCTAssertEqual(ago(5_370), "2 h ago", "89.5 minutes: 90, then 2 hours")
        XCTAssertEqual(ago(23 * 3_600), "23 h ago")
        XCTAssertEqual(ago(23.5 * 3_600), "1 d ago")
        XCTAssertEqual(ago(3 * 86_400), "3 d ago")
        XCTAssertEqual(ago(10, .traditionalChinese), "剛剛")
        XCTAssertEqual(ago(12 * 60, .traditionalChinese), "12 分鐘前")
        XCTAssertEqual(ago(5 * 3_600, .traditionalChinese), "5 小時前")
        XCTAssertEqual(ago(2 * 86_400, .traditionalChinese), "2 天前")
    }

    // MARK: - The launcher

    @MainActor
    func testThePeriodicAutosaveTakesTheNextSlotOnlyWhenTheGameChanged() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        XCTAssertNil(launcher.autosaveSlotInBackground(at: date(0)), "as it began")
        let none = await launcher.autosavesToGoBackTo()
        XCTAssertEqual(none, [])
        XCTAssertEqual(session.message?.kind, .failure, "says when there will be one")
        session.advance(realElapsed: .seconds(10))
        await launcher.autosaveSlotInBackground(at: date(900))?.value
        XCTAssertNil(launcher.autosaveSlotInBackground(at: date(1_800)), "left alone: no slot pushed out")
        session.advance(realElapsed: .seconds(10))
        await launcher.autosaveSlotInBackground(at: date(2_700))?.value
        XCTAssertEqual(library.autosaves().map(\.id), ["autosave-2.json", "autosave-1.json"])
        XCTAssertEqual(try library.load(library.autosaves()[0]), session.worldToSave)
        XCTAssertFalse(try files().contains("autosave.json"), "the latest is written on leaving the game")
    }

    @MainActor
    func testContinueGoesOnWithTheNewestAndTheOthersAreListed() async throws {
        let library = SaveLibrary(directory: directory)
        try library.saveAutosaveSlot(world(after: 1), at: date(0))
        try library.save(world(after: 2), as: .autosave, at: date(60))
        try library.saveAutosaveSlot(world(after: 3), at: date(120))
        let launcher = GameLauncher(library: library, language: .english)
        XCTAssertEqual(launcher.autosave?.id, "autosave-2.json", "newer than the latest left")
        XCTAssertEqual(launcher.olderAutosaves.map(\.id), ["autosave.json", "autosave-1.json"])
        XCTAssertEqual(launcher.otherSaves, [])
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.session?.world, try world(after: 3))
        await launcher.savesWritten()
        XCTAssertEqual(library.autosaves().count, 3, "continuing keeps no extra copy")
    }

    @MainActor
    func testGoingBackInTheGameCanBeUndone() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        session.advance(realElapsed: .seconds(10))
        let before = session.worldToSave
        await launcher.autosaveSlotInBackground(at: date(0))?.value
        session.advance(realElapsed: .seconds(10))
        let mistake = session.worldToSave
        XCTAssertNotEqual(mistake, before)

        let choices = await launcher.autosavesToGoBackTo()
        XCTAssertEqual(choices.map(\.id), ["autosave-1.json"])
        await launcher.load(choices[0], at: date(600))?.value
        await launcher.savesWritten()
        XCTAssertFalse(launcher.session === session)
        XCTAssertEqual(launcher.session?.world, before, "gone back")
        let autosaves = library.autosaves()
        XCTAssertEqual(autosaves.map(\.id), ["autosave.json", "autosave-2.json", "autosave-1.json"])
        XCTAssertEqual(try library.load(autosaves[0]), before, "the latest: Continue goes on with the game gone back to")
        XCTAssertEqual(try library.load(autosaves[1]), mistake, "the game left is kept: going back can be undone")

        // And undone.
        await launcher.load(autosaves[1], at: date(700))?.value
        XCTAssertEqual(launcher.session?.world, mistake)
    }

    @MainActor
    func testGoingBackFromTheStartScreenKeepsTheLatest() async throws {
        let library = SaveLibrary(directory: directory)
        try library.saveAutosaveSlot(world(after: 1), at: date(0))
        try library.save(world(after: 2), as: .autosave, at: date(60))
        let launcher = GameLauncher(library: library, language: .english)
        try await launcher.load(XCTUnwrap(launcher.olderAutosaves.first), at: date(120))?.value
        await launcher.savesWritten()
        XCTAssertEqual(launcher.session?.world, try world(after: 1))
        let autosaves = library.autosaves()
        XCTAssertEqual(autosaves.map(\.id), ["autosave.json", "autosave-2.json", "autosave-1.json"])
        XCTAssertEqual(try library.load(autosaves[0]), try world(after: 1))
        XCTAssertEqual(try library.load(autosaves[1]), try world(after: 2), "the latest, kept in turn")
    }

    @MainActor
    func testANewGameKeepsTheNewestAutosaveAndDeletesTheRest() throws {
        let library = SaveLibrary(directory: directory)
        for minute in 1 ... 3 {
            try library.saveAutosaveSlot(world(after: minute), news: NewsLog(), at: date(Double(minute) * 900))
        }
        try library.save(world(after: 4), news: NewsLog(), as: .autosave, at: date(3_000))
        let unreadable = directory.appendingPathComponent("autosave-9.json")
        try Data("{}".utf8).write(to: unreadable)
        let launcher = GameLauncher(library: library, language: .english)
        XCTAssertEqual(launcher.otherSaves.map(\.id), ["autosave-9.json"], "listed with why")
        launcher.startNewGame()
        let saves = library.entries()
        XCTAssertEqual(saves.filter { $0.kind == .autosave }, [], "the new game's autosaves start afresh")
        XCTAssertEqual(saves.count, 2)
        XCTAssertEqual(try library.load(saves[0]), try world(after: 4), "the last game kept as the player's")
        XCTAssertEqual(saves[1].problem, .notASave, "one that cannot be read is kept too")
        XCTAssertFalse(try files().contains { $0.hasPrefix("autosave") }, "with no news log left behind")
    }

    /// A folder written before decision 192: `autosave.json` alone.
    @MainActor
    func testAnAutosaveOfAnEarlierBuildIsContinued() async throws {
        let library = SaveLibrary(directory: directory)
        try library.save(world(after: 5), as: .autosave, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)
        XCTAssertEqual(launcher.autosave?.id, "autosave.json")
        XCTAssertEqual(launcher.olderAutosaves, [])
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.session?.world, try world(after: 5))
    }
}
