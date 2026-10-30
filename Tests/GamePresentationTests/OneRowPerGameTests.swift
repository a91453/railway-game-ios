import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 502: a game is one row of the player's saves. Save Game writes
/// the row again, keeping the versions before it (three in all) to go back
/// to; a new game keeps the last one's autosave in its row, a new row only
/// for a game never saved; saves from before are left as they are; rows
/// are deleted, one or several, all or none, with their versions.
final class OneRowPerGameTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OneRowPerGameTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }

    /// A new game `ticks` ticks on.
    private func world(after ticks: Int) throws -> GameWorld {
        var world = GameWorld.newGame()
        try world.advance(ticks: ticks)
        return world
    }

    private func manualRows(_ library: SaveLibrary) -> [SaveLibrary.Entry] {
        library.entries().filter { $0.kind == .manual }
    }

    // MARK: - The library

    func testSavingIntoARowKeepsTheTwoVersionsBeforeIt() throws {
        let library = SaveLibrary(directory: directory)
        let first = try library.save(world(after: 1), news: NewsLog(), as: .manual, at: date(0), named: "Mine")
        XCTAssertEqual(first.row, first.id)
        XCTAssertEqual(first.earlierVersions, 0)
        for ticks in 2 ... 4 {
            try library.save(world(after: ticks), news: NewsLog(), as: .manual, at: date(Double(ticks) * 60), row: first.id)
        }
        let rows = manualRows(library)
        XCTAssertEqual(rows.map(\.id), [first.id], "one row for the game")
        XCTAssertEqual(rows[0].name, "Mine", "its name stays")
        XCTAssertEqual(rows[0].earlierVersions, SaveLibrary.versionsKept - 1)
        XCTAssertEqual(try library.load(rows[0]), try world(after: 4))
        let versions = library.earlierVersions(of: rows[0])
        XCTAssertEqual(versions.map(\.savedAt), [date(180), date(120)], "the latest first; the first save pushed out")
        XCTAssertEqual(try versions.map { try library.load($0) }, [try world(after: 3), try world(after: 2)])
        XCTAssertTrue(versions.allSatisfy { $0.row == first.id }, "a version belongs to its row")
        XCTAssertEqual(versions.map(\.name), ["Mine", "Mine"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Versions/save-2026-10-02 120000/1.news.json").path),
                      "its news log goes with it")
    }

    func testAVersionIsNeitherListedNorCopiedToICloud() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        XCTAssertEqual(library.entries().map(\.id), [row.id])
        let files = try DirectorySaveFolder(directory: directory).files()
        XCTAssertEqual(Set(SaveSync.saves(in: files).keys), ["save-2026-10-02 120000"])
    }

    func testARowThatIsNoSaveOfThePlayersIsANewRow() throws {
        let library = SaveLibrary(directory: directory)
        try library.save(world(after: 1), as: .autosave, at: date(0))
        for row in ["autosave.json", "autosave-3.json", "../x.json", "Versions/a/1.json", "notes.txt"] {
            let entry = try library.save(world(after: 2), as: .manual, at: date(60), row: row)
            XCTAssertTrue(entry.id.hasPrefix("save-"), row)
        }
        XCTAssertEqual(try library.load(XCTUnwrap(library.entries().first { $0.kind == .autosave })), try world(after: 1))
    }

    /// An autosave names its game's row in its file; one written without
    /// (a build before 502) has none, and a save file shared has none.
    func testTheAutosaveNamesItsRow() throws {
        let library = SaveLibrary(directory: directory)
        try library.save(world(after: 1), as: .autosave, at: date(0), row: "save-a.json")
        XCTAssertEqual(library.entries().first?.row, "save-a.json")
        try library.saveAutosaveSlot(world(after: 2), at: date(60), row: "save-a.json")
        XCTAssertEqual(library.autosaves().map(\.row), ["save-a.json", "save-a.json"])
        try library.save(world(after: 3), as: .autosave, at: date(120))
        XCTAssertNil(library.entries().first?.row)
        let shared = try XCTUnwrap(try JSONSerialization.jsonObject(with: SaveLibrary.encode(world(after: 1), at: date(0))) as? [String: Any])
        XCTAssertNil(shared["row"])
    }

    /// The headers kept for the list (decision 497) keep the row too, in
    /// this launch and the next, without reading the save again.
    func testTheKeptHeadersKeepTheRow() throws {
        let headers = directory.appendingPathExtension("headers")
        defer { try? FileManager.default.removeItem(at: headers) }
        let library = SaveLibrary(directory: directory, headers: headers)
        try library.save(world(after: 1), as: .autosave, at: date(0), row: "save-a.json")
        XCTAssertEqual(library.entries().first?.row, "save-a.json")
        XCTAssertEqual(library.headersRead, 0)
        let nextLaunch = SaveLibrary(directory: directory, headers: headers)
        XCTAssertEqual(nextLaunch.entries().first?.row, "save-a.json")
        XCTAssertEqual(nextLaunch.headersRead, 0)
    }

    func testANewGameKeepsTheAutosaveInItsRow() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), news: NewsLog(), as: .manual, at: date(0), named: "Mine")
        try library.saveAutosaveSlot(world(after: 2), at: date(60), row: row.id)
        try library.save(world(after: 3), news: NewsLog(), as: .autosave, at: date(120), row: row.id)
        try library.archiveAutosave()
        let rows = library.entries()
        XCTAssertEqual(rows.map(\.id), [row.id], "no new row, no autosave left")
        XCTAssertEqual(try library.load(rows[0]), try world(after: 1), "the row stays what the player saved")
        XCTAssertEqual(rows[0].name, "Mine")
        let versions = library.earlierVersions(of: rows[0])
        XCTAssertEqual(try versions.map { try library.load($0) }, [try world(after: 3)], "the game as it was left")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(SaveLibrary.newsFile(of: versions[0].id)).path), "with its news")
        let file = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(versions[0].id))) as? [String: Any])
        XCTAssertNil(file["row"], "a version names no row")
    }

    func testANewGameAfterSavingWithoutAChangeAddsNoVersion() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 1), as: .autosave, at: date(60), row: row.id)
        try library.archiveAutosave()
        XCTAssertEqual(library.entries().map(\.id), [row.id])
        XCTAssertEqual(library.entries()[0].savedAt, date(0))
        XCTAssertEqual(library.entries()[0].earlierVersions, 0)
    }

    func testAGameWhoseRowIsGoneGetsANewRow() throws {
        let library = SaveLibrary(directory: directory)
        try library.save(world(after: 3), as: .autosave, at: date(120), row: "save-gone.json")
        try library.archiveAutosave()
        let rows = library.entries()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .manual)
        XCTAssertNotEqual(rows[0].id, "save-gone.json")
        XCTAssertEqual(try library.load(rows[0]), try world(after: 3))
    }

    func testDeletingARowDeletesItsVersions() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), news: NewsLog(), as: .manual, at: date(0), named: "Mine")
        try library.save(world(after: 2), news: NewsLog(), as: .manual, at: date(60), row: row.id)
        try library.delete(XCTUnwrap(library.entries().first))
        XCTAssertEqual(library.entries(), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "Versions" }, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Versions").path), [])
    }

    func testDeletingSeveralDeletesOnlyThoseAllOrNone() throws {
        var library = SaveLibrary(directory: directory)
        let a = try library.save(world(after: 1), news: NewsLog(), as: .manual, at: date(0), named: "A")
        let b = try library.save(world(after: 2), news: NewsLog(), as: .manual, at: date(60))
        let c = try library.save(world(after: 3), as: .manual, at: date(120))
        try library.save(world(after: 4), as: .manual, at: date(180), row: a.id)
        try library.save(world(after: 5), as: .autosave, at: date(240))
        let before = try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()

        library.failingMoves = [b.id]
        XCTAssertThrowsError(try library.delete([a, b])) { XCTAssertEqual($0 as? SaveError, .fileSystem) }
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted(), before, "nothing deleted")

        library.failingMoves = []
        try library.delete([a, b])
        XCTAssertEqual(library.entries().map(\.id), ["autosave.json", c.id])
        XCTAssertEqual(try library.load(library.entries()[1]), try world(after: 3))
        XCTAssertFalse(try FileManager.default.subpathsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(SaveLibrary.deletingFolder) })
    }

    /// A file that cannot be put back after a failed delete is kept set
    /// aside, never removed (not by a later delete either), and goes back
    /// the next time the saves are listed.
    func testAFileThatCannotGoBackIsNeverLost() throws {
        var library = SaveLibrary(directory: directory)
        let a = try library.save(world(after: 1), news: NewsLog(), as: .manual, at: date(0), named: "A")
        try library.save(world(after: 2), as: .manual, at: date(30), row: a.id)
        let b = try library.save(world(after: 3), as: .manual, at: date(60))
        let c = try library.save(world(after: 4), as: .manual, at: date(120))
        let listed = library.entries()
        library.failingMoves = [b.id]
        library.failingReturns = [a.id, SaveLibrary.versionsPath(of: a.id)]
        XCTAssertThrowsError(try library.delete([a, b]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(a.id).path))

        library.failingMoves = []
        library.failingReturns = []
        try library.delete([c])
        XCTAssertEqual(library.entries(), listed.filter { $0.id != c.id }, "back, with its name and version")
        XCTAssertEqual(try library.load(XCTUnwrap(library.entries().first { $0.id == a.id })), try world(after: 2))
        XCTAssertFalse(try FileManager.default.subpathsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(SaveLibrary.deletingFolder) })
    }

    /// A row deleted on another device leaves no earlier versions behind
    /// for a row of the same name.
    func testTheVersionsOfARowGoneElsewhereGoToo() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(row.id))
        XCTAssertEqual(library.entries(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(SaveLibrary.versionsPath(of: row.id)).path))

        // Written again without a list in between.
        try library.save(world(after: 3), as: .manual, at: date(120), row: row.id)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(row.id))
        let again = try library.save(world(after: 4), as: .manual, at: date(180), row: row.id)
        XCTAssertEqual(again.earlierVersions, 0)
    }

    /// The row's newest version is not kept twice (a save tried again
    /// after its write failed, or the same game saved again).
    func testTheSameGameIsNotKeptTwiceAsAVersion() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        try library.save(world(after: 3), as: .manual, at: date(120), row: row.id)
        let versions = library.earlierVersions(of: try XCTUnwrap(library.entries().first { $0.id == row.id }))
        XCTAssertEqual(try versions.map { try library.load($0) }, [try world(after: 2), try world(after: 1)])
    }

    // MARK: - The launcher

    @MainActor
    func testSaveGameWritesTheSameRow() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session)
        await launcher.saveCurrentGame(at: date(0)).value
        session.advance(realElapsed: .seconds(10))
        await launcher.saveCurrentGame(at: date(60)).value
        let rows = manualRows(library)
        XCTAssertEqual(rows.count, 1, "one row however often it is saved")
        XCTAssertEqual(try library.load(rows[0]), session.worldToSave)
        XCTAssertEqual(rows[0].earlierVersions, 1)
        XCTAssertEqual(launcher.gameRow, rows[0].id)
    }

    @MainActor
    func testSaveAsStartsARowTheGameThenKeepsTo() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session)
        await launcher.saveCurrentGame(at: date(0)).value
        let first = launcher.gameRow
        session.advance(realElapsed: .seconds(10))
        await launcher.saveCurrentGame(at: date(60), named: "Branch").value
        XCTAssertNotEqual(launcher.gameRow, first)
        session.advance(realElapsed: .seconds(10))
        await launcher.saveCurrentGame(at: date(120)).value
        let rows = manualRows(library)
        XCTAssertEqual(rows.count, 2)
        let branch = try XCTUnwrap(rows.first { $0.name == "Branch" })
        XCTAssertEqual(branch.id, launcher.gameRow)
        XCTAssertEqual(try library.load(branch), session.worldToSave)
        XCTAssertEqual(rows.first { $0.id == first }?.earlierVersions, 0, "the first row as it was")
    }

    /// The whole loop: save, play on, leave, start another game. The last
    /// game is one row, still what was saved, the game as it was left its
    /// newest earlier version.
    @MainActor
    func testANewGameUpdatesTheRowOfTheGameLeft() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session)
        await launcher.saveCurrentGame(at: date(0)).value
        let saved = session.worldToSave
        session.advance(realElapsed: .seconds(10))
        let left = session.worldToSave
        launcher.returnToStart()
        launcher.startNewGame()
        let rows = manualRows(library)
        XCTAssertEqual(rows.count, 1, "no second row for the game left")
        XCTAssertEqual(try library.load(rows[0]), saved)
        XCTAssertEqual(try library.earlierVersions(of: rows[0]).map { try library.load($0) }, [left])
        XCTAssertNil(launcher.gameRow, "the new game has no row yet")
    }

    /// The game menu's Back to Start (decision 497, off the main thread)
    /// names the row too.
    @MainActor
    func testBackToStartInTheBackgroundKeepsTheRow() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        await launcher.saveCurrentGame(at: date(0)).value
        let row = launcher.gameRow
        await launcher.returnToStartInBackground(at: date(60))?.value
        XCTAssertEqual(library.entries().first { $0.kind == .autosave }?.row, row)
    }

    @MainActor
    func testAGameNeverSavedGetsARowWhenAnotherStarts() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        launcher.returnToStart()
        launcher.startNewGame()
        launcher.returnToStart()
        launcher.startNewGame()
        XCTAssertEqual(manualRows(library).count, 2, "one row each, as before")
    }

    /// Continue, then Save Game: the row the autosave names.
    @MainActor
    func testContinuingKeepsTheGamesRow() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.startNewGame()
        await launcher.saveCurrentGame(at: date(0)).value
        let row = launcher.gameRow
        launcher.returnToStart()

        let again = GameLauncher(library: library, language: .english)
        await again.continueGame()?.value
        XCTAssertEqual(again.gameRow, row)
        try XCTUnwrap(again.session).advance(realElapsed: .seconds(10))
        await again.saveCurrentGame(at: date(60)).value
        XCTAssertEqual(manualRows(library).map(\.id), [try XCTUnwrap(row)])
    }

    /// Saves made before 502, several of one game: none deleted or merged;
    /// the one loaded is the row saved into.
    @MainActor
    func testSavesFromBeforeAreLeftAsTheyAre() async throws {
        let library = SaveLibrary(directory: directory)
        let old = try library.save(world(after: 1), as: .manual, at: date(0))
        let older = try library.save(world(after: 2), as: .manual, at: date(60))
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.load(older, at: date(120))?.value
        XCTAssertEqual(launcher.gameRow, older.id)
        try XCTUnwrap(launcher.session).advance(realElapsed: .seconds(10))
        await launcher.saveCurrentGame(at: date(180)).value
        let rows = manualRows(library)
        XCTAssertEqual(Set(rows.map(\.id)), [old.id, older.id])
        XCTAssertEqual(try library.load(XCTUnwrap(rows.first { $0.id == old.id })), try world(after: 1))
        XCTAssertEqual(rows.first { $0.id == older.id }?.earlierVersions, 1)
    }

    /// An earlier version loaded goes on in its row; saving it makes it the
    /// newest, the one it replaced kept.
    @MainActor
    func testGoingBackToAnEarlierVersion() async throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        let launcher = GameLauncher(library: library, language: .english)
        let versions = await launcher.earlierVersions(of: try XCTUnwrap(launcher.otherSaves.first))
        XCTAssertEqual(versions.count, 1)
        await launcher.load(versions[0], at: date(120))?.value
        XCTAssertEqual(launcher.session?.world, try world(after: 1))
        XCTAssertEqual(launcher.gameRow, row.id)
        await launcher.saveCurrentGame(at: date(180)).value
        let rows = manualRows(library)
        XCTAssertEqual(rows.map(\.id), [row.id])
        XCTAssertEqual(try library.load(rows[0]), try world(after: 1))
        XCTAssertEqual(try library.earlierVersions(of: rows[0]).map { try library.load($0) }, [try world(after: 2), try world(after: 1)])
    }

    /// Going back to the oldest version while playing its row: going back
    /// pushes it out of the row, so it is kept as the autosave.
    @MainActor
    func testTheOldestVersionGoneBackToIsKept() async throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        try library.save(world(after: 3), as: .manual, at: date(120), row: row.id)
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.load(try XCTUnwrap(launcher.otherSaves.first), at: date(180))?.value
        launcher.session?.advance(realElapsed: .seconds(10))
        XCTAssertTrue(launcher.autosaveCurrentGame(at: date(240)))
        let versions = await launcher.earlierVersions(of: try XCTUnwrap(manualRows(library).first))
        let oldest = try XCTUnwrap(versions.last)
        await launcher.load(oldest, at: date(300))?.value
        XCTAssertEqual(launcher.session?.world, try world(after: 1))
        let autosave = try XCTUnwrap(library.autosaves().first)
        XCTAssertEqual(try library.load(autosave), try world(after: 1))
        XCTAssertEqual(autosave.row, row.id)
    }

    /// Load a save, play, go back, load it again, several times over: each
    /// time the save is what the player saved, and it stays (the
    /// independent review's must-fix 1).
    @MainActor
    func testRetryingFromACheckpointNeverLosesIt() async throws {
        let library = SaveLibrary(directory: directory)
        let checkpoint = try library.save(world(after: 1), as: .manual, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)
        for round in 1...5 {
            await launcher.load(try XCTUnwrap(manualRows(library).first), at: date(Double(round) * 600))?.value
            XCTAssertEqual(launcher.session?.world, try world(after: 1), "round \(round)")
            launcher.session?.advance(realElapsed: .seconds(10))
            XCTAssertTrue(launcher.autosaveCurrentGame(at: date(Double(round) * 600 + 300)))
            launcher.returnToStart()
        }
        let rows = manualRows(library)
        XCTAssertEqual(rows.map(\.id), [checkpoint.id])
        XCTAssertEqual(try library.load(rows[0]), try world(after: 1))
    }

    /// Two devices save one row differently, then one plays on and saves
    /// again: each device still has its own game (the independent
    /// review's must-fix 2).
    func testAfterAConflictEachDevicesCheckpointStaysOnIt() throws {
        let root = directory.appendingPathComponent("devices", isDirectory: true)
        let cloud = DirectorySaveFolder(directory: root.appendingPathComponent("iCloud", isDirectory: true))
        final class Device {
            let library: SaveLibrary
            var state = SaveSync.State()
            init(_ url: URL) { library = SaveLibrary(directory: url) }
        }
        let phone = Device(root.appendingPathComponent("phone")), pad = Device(root.appendingPathComponent("pad"))
        func sync(_ device: Device) {
            let outcome = SaveSync.run(
                local: DirectorySaveFolder(directory: device.library.directory), cloud: cloud, state: &device.state,
                language: .english, now: date(0), keeping: { try device.library.keepBeforeReplacing($0) }
            )
            XCTAssertFalse(outcome.isIncomplete)
        }
        func holds(_ device: Device, _ wanted: GameWorld) throws -> Bool {
            let games = device.library.entries().filter { $0.kind == .manual }.flatMap { [$0] + device.library.earlierVersions(of: $0) }
            return try games.contains { try device.library.load($0) == wanted }
        }
        let row = try phone.library.save(world(after: 1), as: .manual, at: date(0))
        sync(phone)
        sync(pad)
        try phone.library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        try pad.library.save(world(after: 3), as: .manual, at: date(70), row: row.id)
        sync(phone)
        sync(pad)
        sync(phone)
        try phone.library.save(world(after: 4), as: .manual, at: date(120), row: row.id)
        sync(phone)
        sync(pad)
        XCTAssertTrue(try holds(phone, world(after: 2)), "the phone's game")
        XCTAssertTrue(try holds(pad, world(after: 3)), "the pad's game")
        XCTAssertTrue(try holds(pad, world(after: 4)))
    }

    /// The app stopped while an earlier version was moving in: the next
    /// save finishes the move and loses no version (the review's 3).
    func testAVersionHalfMovedIsFinishedByTheNextSave() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        // As if stopped after the row was written and number 1 moved to 2,
        // before what waited took number 1.
        let folder = directory.appendingPathComponent(SaveLibrary.versionsPath(of: row.id))
        try FileManager.default.moveItem(at: folder.appendingPathComponent("1.json"), to: folder.appendingPathComponent("2.json"))
        try SaveLibrary.encode(world(after: 2), at: date(60)).write(to: folder.appendingPathComponent("incoming.json"))
        try SaveLibrary.encode(world(after: 3), at: date(120)).write(to: directory.appendingPathComponent(row.id))
        try library.save(world(after: 4), as: .manual, at: date(180), row: row.id)
        let entry = try XCTUnwrap(library.entries().first)
        XCTAssertEqual(try library.load(entry), try world(after: 4))
        XCTAssertEqual(try library.earlierVersions(of: entry).map { try library.load($0) }, [try world(after: 3), try world(after: 2)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("incoming.json").path))
    }

    @MainActor
    func testTheLauncherDeletesTheSelection() throws {
        let library = SaveLibrary(directory: directory)
        let a = try library.save(world(after: 1), as: .manual, at: date(0))
        let b = try library.save(world(after: 2), as: .manual, at: date(60))
        let c = try library.save(world(after: 3), as: .manual, at: date(120))
        let launcher = GameLauncher(library: library, language: .english)
        launcher.delete([a, c])
        XCTAssertEqual(launcher.entries.map(\.id), [b.id])
        XCTAssertNil(launcher.message)
    }

    // MARK: - The saves list's words

    func testOnlyThePlayersSavesCanBeChosen() throws {
        let library = SaveLibrary(directory: directory)
        let mine = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .autosave, at: date(60))
        try library.saveAutosaveSlot(world(after: 3), at: date(120))
        XCTAssertEqual(SaveListText.selectable(library.entries()).map(\.id), [mine.id])
    }

    func testTheWarningSaysHowMany() {
        XCTAssertEqual(SaveListText.deleteSelectedQuestion(1, in: .english), "Delete 1 save?")
        XCTAssertEqual(SaveListText.deleteSelectedQuestion(3, in: .english), "Delete 3 saves?")
        XCTAssertEqual(SaveListText.deleteSelectedQuestion(3, in: .traditionalChinese), "要刪除 3 個存檔嗎？")
        XCTAssertEqual(SaveListText.deleteSelectedTitle(0, in: .english), "Delete")
        XCTAssertEqual(SaveListText.deleteSelectedTitle(2, in: .traditionalChinese), "刪除（2）")
        XCTAssertEqual(SaveListText.selectAllTitle(allSelected: false, in: .traditionalChinese), "全選")
        XCTAssertEqual(SaveListText.selectAllTitle(allSelected: true, in: .english), "Deselect All")
    }

    func testAnEarlierVersionReadsHowLongAgoAndTheGame() throws {
        let library = SaveLibrary(directory: directory)
        let row = try library.save(world(after: 1), as: .manual, at: date(0))
        try library.save(world(after: 2), as: .manual, at: date(60), row: row.id)
        let version = try XCTUnwrap(library.earlierVersions(of: row).first)
        let summary = SaveSummary(world: try world(after: 1))
        XCTAssertEqual(SaveListText.versionLabel(of: version, at: date(720), in: .english), "12 min ago · \(summary.dateAndFundsText(in: .english))")
        XCTAssertEqual(SaveListText.versionLabel(of: version, at: date(720), in: .traditionalChinese), "12 分鐘前 · \(summary.dateAndFundsText(in: .traditionalChinese))")
    }
}
