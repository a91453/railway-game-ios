import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 192, later: Continue falls back to the next autosave that loads
/// when the newest is damaged, and keeps the damaged one. Decision 175,
/// later: an exported save carries the game's news log, which a build before
/// it skips.
final class SaveRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SaveRecoveryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }

    private func world(after ticks: Int) throws -> GameWorld {
        var world = GameWorld.newGame()
        try world.advance(ticks: ticks)
        return world
    }

    /// Spoils the world in save file `name`, keeping its header: the list
    /// shows it as loadable, but the game cannot be read back.
    private func damageWorld(in name: String, of folder: URL? = nil) throws {
        let url = (folder ?? directory).appendingPathComponent(name)
        var file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var game = try XCTUnwrap(file["game"] as? [String: Any])
        game["world"] = ["damaged": true]
        file["game"] = game
        try JSONSerialization.data(withJSONObject: file).write(to: url)
    }

    // MARK: - Continue

    @MainActor
    func testContinueFallsBackToTheNextAutosaveThatLoads() async throws {
        for language in DisplayLanguage.allCases {
            let folder = directory.appendingPathComponent("\(language)", isDirectory: true)
            let library = SaveLibrary(directory: folder)
            try library.saveAutosaveSlot(world(after: 1), at: date(0))
            try library.saveAutosaveSlot(world(after: 2), at: date(900))
            try library.save(world(after: 3), as: .autosave, at: date(1_200))
            try damageWorld(in: "autosave.json", of: folder)
            try damageWorld(in: "autosave-2.json", of: folder)
            let damaged = try ["autosave.json", "autosave-2.json"].map { try Data(contentsOf: folder.appendingPathComponent($0)) }

            let launcher = GameLauncher(library: library, language: language)
            XCTAssertEqual(launcher.autosave?.id, "autosave.json", "its header reads")
            launcher.continueGame()
            XCTAssertEqual(launcher.session?.world, try world(after: 1), "the newest that loads")
            let clock = SaveLibrary.clockText(date(0))
            XCTAssertEqual(launcher.session?.message, StatusMessage(kind: .failure, text: language.text(
                "The newest save could not be loaded. Continued from the save of \(clock).",
                "最新的存檔讀不了，已從 \(clock) 的存檔繼續。"
            )))
            XCTAssertNil(launcher.message)
            await launcher.savesWritten()

            // The damaged files are kept, for a problem report.
            let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
                .map { try Data(contentsOf: folder.appendingPathComponent($0)) }
            for file in damaged {
                XCTAssertTrue(kept.contains(file), "a damaged autosave is not deleted")
            }
            XCTAssertEqual(try library.load(XCTUnwrap(library.autosaves().first)), try world(after: 1), "Continue goes on with it next time")
        }
    }

    @MainActor
    func testContinueReportsWhenNoAutosaveLoads() throws {
        let library = SaveLibrary(directory: directory)
        try library.saveAutosaveSlot(world(after: 1), at: date(0))
        try library.save(world(after: 2), as: .autosave, at: date(60))
        try damageWorld(in: "autosave.json")
        try damageWorld(in: "autosave-1.json")
        for language in DisplayLanguage.allCases {
            let launcher = GameLauncher(library: library, language: language)
            launcher.continueGame()
            XCTAssertNil(launcher.session)
            XCTAssertEqual(launcher.message, StatusMessage(kind: .failure, text: language.text(
                "None of the autosaves can be loaded.", "所有自動存檔都讀不了。"
            )))
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("autosave") }), ["autosave.json", "autosave-1.json"], "none deleted")
    }

    @MainActor
    func testContinueWithTheNewestLoadableSaysNothing() throws {
        let library = SaveLibrary(directory: directory)
        try library.save(world(after: 2), as: .autosave, at: date(60))
        let launcher = GameLauncher(library: library, language: .english)
        launcher.continueGame()
        XCTAssertEqual(launcher.session?.world, try world(after: 2))
        XCTAssertNil(launcher.session?.message)
    }

    // MARK: - The news log in an exported save

    private func news() -> NewsLog {
        var log = NewsLog()
        log.add(day: 3, .success, english: "The first line opened.", chinese: "第一條路線開通了。")
        log.add(day: 5, .monthly, english: "Monthly report.", chinese: "月報。")
        return log
    }

    @MainActor
    func testAnExportedSaveBringsItsNewsBack() throws {
        let world = try world(after: 30)
        let log = news()
        let url = try SaveLibrary.exportFile(for: world, news: log, at: date(0))
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let read = try SaveLibrary.decodeWithNews(data)
        XCTAssertEqual(read.world, world)
        XCTAssertEqual(read.news, log)

        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.importSave(reading: { data })
        XCTAssertEqual(launcher.session?.world, world)
        XCTAssertEqual(launcher.session?.news.items, log.items)
    }

    func testASaveWithoutNewsOrWithUnreadableNewsStillLoads() throws {
        let world = try world(after: 30)
        let plain = try SaveLibrary.encode(world, at: date(0))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains(#""news""#), "a save in the folder is written as before")
        XCTAssertNil(try SaveLibrary.decodeWithNews(plain).news)

        var file = try XCTUnwrap(JSONSerialization.jsonObject(with: SaveLibrary.encode(world, news: news(), at: date(0))) as? [String: Any])
        file["news"] = ["items": "not a log"]
        let spoiled = try SaveLibrary.decodeWithNews(JSONSerialization.data(withJSONObject: file))
        XCTAssertEqual(spoiled.world, world, "the news log never stops the game loading")
        XCTAssertNil(spoiled.news)
    }

    /// A build before this one reads a save file as this struct (`SaveFile`
    /// on `main` before decision 175's later part, and its `Header`):
    /// decoding an exported file with the news log must not fail there.
    private struct EarlierSaveFile: Decodable {
        let app: String
        let savedAt: Date
        let summary: SaveSummary
        let game: SavedGame
    }

    private struct EarlierHeader: Decodable {
        struct Game: Decodable { let saveVersion: Int }
        let app: String
        let savedAt: Date
        let summary: SaveSummary
        let game: Game
    }

    func testAnEarlierBuildSkipsTheNewsLog() throws {
        let world = try world(after: 30)
        let data = try SaveLibrary.encode(world, news: news(), at: date(0))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""news""#))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(EarlierHeader.self, from: data)
        XCTAssertEqual(header.app, SaveLibrary.appName)
        XCTAssertEqual(header.game.saveVersion, SavedGame.currentVersion, "the save version is unchanged")
        XCTAssertEqual(header.savedAt, date(0))
        XCTAssertEqual(try decoder.decode(EarlierSaveFile.self, from: data).game.world, world)
    }
}
