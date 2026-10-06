import Foundation
import GameCore
import GamePresentation
import XCTest

/// Stage C4: the start screen's actions. New game, the demo map, continue,
/// load and import; saving, the autosave on returning to the start screen
/// and on leaving the foreground; and the autosave kept before another
/// game starts, as the `Ci/` reference archives its draft.
final class GameLauncherTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("GameLauncherTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testANewGameIsAutosavedAndContinued() async throws {
        let library = SaveLibrary(directory: directory)
        try await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            XCTAssertNil(launcher.session, "the start screen")
            XCTAssertNil(launcher.autosave)
            launcher.continueGame()
            XCTAssertEqual(launcher.message, StatusMessage(kind: .failure, text: "There is no game to continue."))

            launcher.startNewGame()
            let session = try XCTUnwrap(launcher.session)
            XCTAssertEqual(session.world, .newGame())
            XCTAssertNil(launcher.message)
            session.setSpeed(.double)
            launcher.returnToStart()
            XCTAssertNil(launcher.session)
            XCTAssertNotNil(launcher.autosave)
            XCTAssertEqual(launcher.otherSaves, [])

            launcher.continueGame()
            XCTAssertEqual(launcher.session?.world.clock.speed, .double, "the game as it was left")
            XCTAssertEqual(launcher.otherSaves, [], "continuing keeps no extra copy")
        }
    }

    /// Starting another game keeps the autosave as a save of the player's
    /// own, so the last game is never written over.
    func testAnotherGameKeepsTheAutosave() async throws {
        let library = SaveLibrary(directory: directory)
        try await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            launcher.startNewGame()
            launcher.returnToStart()
            launcher.openDemo()
            XCTAssertEqual(launcher.session?.world, DemoWorld.make(in: .english))
            XCTAssertNil(launcher.autosave, "moved aside")
            XCTAssertEqual(launcher.otherSaves.count, 1)
            XCTAssertEqual(try library.load(launcher.otherSaves[0]), .newGame())

            launcher.returnToStart()
            launcher.load(launcher.otherSaves[0])
            XCTAssertEqual(launcher.session?.world, .newGame())
            XCTAssertEqual(launcher.otherSaves.count, 2, "the demo's autosave kept too")
        }
    }

    func testTheGameIsSavedAndASaveLoadedOrImported() async throws {
        let library = SaveLibrary(directory: directory)
        try await MainActor.run {
            let launcher = GameLauncher(library: library, language: .traditionalChinese)
            launcher.openDemo()
            launcher.saveCurrentGame(at: Date(timeIntervalSince1970: 1_790_942_400))
            XCTAssertEqual(launcher.session?.message, StatusMessage(kind: .success, text: "已儲存遊戲。"))
            XCTAssertEqual(launcher.otherSaves.map(\.id), ["save-2026-10-02 120000.json"])
            launcher.returnToStart()

            launcher.importSave(Data("not a save".utf8))
            XCTAssertNil(launcher.session)
            XCTAssertEqual(launcher.message, StatusMessage(kind: .failure, text: "這個檔案不是《沿線》的存檔。"))
            launcher.importSave(reading: { throw CocoaError(.fileReadNoPermission) })
            XCTAssertEqual(launcher.message, StatusMessage(kind: .failure, text: "無法讀寫存檔，請再試一次。"))

            let exported = try SaveLibrary.encode(DemoWorld.make(in: .english), at: Date())
            launcher.importSave(reading: { exported })
            XCTAssertEqual(launcher.session?.world, DemoWorld.make(in: .english))
            XCTAssertNil(launcher.message)

            launcher.returnToStart()
            let save = try XCTUnwrap(launcher.otherSaves.first { $0.id == "save-2026-10-02 120000.json" })
            launcher.delete(save)
            XCTAssertFalse(launcher.otherSaves.contains(save))
        }
    }

    func testAnUnloadableSaveIsReported() async throws {
        let library = SaveLibrary(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let newer = String(decoding: try SaveLibrary.encode(.newGame(), at: Date()), as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion":\#(SavedGame.currentVersion)"#, with: #""saveVersion":\#(SavedGame.currentVersion + 1)"#)
        try Data(newer.utf8).write(to: directory.appendingPathComponent("autosave.json"))
        await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            XCTAssertNil(launcher.autosave, "it cannot be continued")
            XCTAssertEqual(launcher.otherSaves.map(\.problem), [.newerVersion(SavedGame.currentVersion + 1)])
            launcher.load(launcher.otherSaves[0])
            XCTAssertNil(launcher.session)
            XCTAssertEqual(launcher.message?.text, SaveError.newerVersion(SavedGame.currentVersion + 1).playerMessage(in: .english))
        }
    }

    /// The game loop runs only in the foreground; leaving it autosaves.
    func testLeavingTheForegroundStopsTheGameAndAutosaves() async throws {
        let library = SaveLibrary(directory: directory)
        await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            launcher.setActive(true)
            XCTAssertFalse(launcher.autosaveCurrentGame(), "no game yet")
            launcher.startNewGame()
            XCTAssertEqual(launcher.session?.isGameLoopRunning, true, "a game started in the foreground runs")
            launcher.setActive(false)
            XCTAssertEqual(launcher.session?.isGameLoopRunning, false)
            XCTAssertNotNil(launcher.autosave)
            launcher.setActive(true)
            XCTAssertEqual(launcher.session?.isGameLoopRunning, true)
            launcher.returnToStart()
            launcher.setActive(false)
            XCTAssertEqual(GameLauncher.autosaveInterval, .seconds(900), "the reference's AUTOSAVE_INTERVAL_MS")
        }
    }
}
