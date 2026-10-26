import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 45, later: the autosave on leaving the app, the periodic one
/// and the player's own saves are encoded and written off the main thread,
/// from a copy of the world taken the moment the game is saved. The files
/// are the same JSON a save written at once makes; saves are written one
/// after another, and whatever reads the folder waits for them.
///
/// The same JSON, not the same bytes: `JSONEncoder` writes an object's keys
/// in no fixed order, so two saves of one world written at once already
/// differ in their order (the encoder is left as it is, so the files stay
/// what this build has always written). ``canonical(_:)`` puts the keys
/// in order before comparing.
final class BackgroundSaveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundSaveTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }

    /// `data`'s JSON with every object's keys sorted.
    private func canonical(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
    }

    private var autosaveFile: URL {
        directory.appendingPathComponent("autosave.json")
    }

    @MainActor
    func testTheFileIsTheBytesOfASaveWrittenAtOnce() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        session.selectTool(.network)
        let world = session.worldToSave
        await launcher.autosaveInBackground(at: date(0))?.value
        XCTAssertEqual(try canonical(Data(contentsOf: autosaveFile)), try canonical(SaveLibrary.encode(world, at: date(0))))
        XCTAssertFalse(try SaveLibrary.decode(Data(contentsOf: autosaveFile)).clock.isPaused, "the world to save, not the tool's pause")

        let other = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundSaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: other) }
        try SaveLibrary(directory: other).save(world, news: session.news, as: .autosave, at: date(0))
        XCTAssertEqual(try canonical(Data(contentsOf: autosaveFile)), try canonical(Data(contentsOf: other.appendingPathComponent("autosave.json"))))
        XCTAssertEqual(
            try canonical(Data(contentsOf: directory.appendingPathComponent("autosave.news.json"))),
            try canonical(Data(contentsOf: other.appendingPathComponent("autosave.news.json"))),
            "the news log too"
        )

        await launcher.saveCurrentGame(at: date(60)).value
        let manual = try XCTUnwrap(launcher.otherSaves.first)
        XCTAssertEqual(try canonical(Data(contentsOf: directory.appendingPathComponent(manual.id))), try canonical(SaveLibrary.encode(world, at: date(60))))
    }

    /// Saved twice before either is written, the later one is what is
    /// left, whole.
    @MainActor
    func testTheLaterOfTwoSavesIsKept() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        let first = launcher.autosaveInBackground(at: date(0))
        session.advance(realElapsed: .seconds(10))
        let later = session.worldToSave
        XCTAssertNotEqual(later, DemoWorld.make(in: .english))
        let second = launcher.autosaveInBackground(at: date(1))
        await first?.value
        await second?.value
        XCTAssertEqual(try SaveLibrary.decode(Data(contentsOf: autosaveFile)), later)
        XCTAssertEqual(try canonical(Data(contentsOf: autosaveFile)), try canonical(SaveLibrary.encode(later, at: date(1))))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names.filter { $0.hasSuffix(".json") && !$0.hasSuffix(".news.json") }, ["autosave.json"], "no file left half written")
    }

    /// The game goes on while it is saved; the save is the moment it was
    /// saved at.
    @MainActor
    func testTheSaveIsTheMomentItWasTaken() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        let saved = session.worldToSave
        let written = launcher.autosaveInBackground(at: date(0))
        session.advance(realElapsed: .seconds(10))
        XCTAssertNotEqual(session.world, saved, "the game went on")
        await written?.value
        XCTAssertEqual(try SaveLibrary.decode(Data(contentsOf: autosaveFile)), saved)
    }

    /// The list of saves, continuing and loading wait for the saves still
    /// being written, and read the latest.
    @MainActor
    func testTheListAndContinueReadTheLatest() async throws {
        let library = SaveLibrary(directory: directory)
        let launcher = GameLauncher(library: library, language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        session.advance(realElapsed: .seconds(10))
        let saved = session.worldToSave
        launcher.setActive(true)
        launcher.setActive(false)
        launcher.refresh()
        XCTAssertEqual(launcher.autosave?.summary, SaveSummary(world: saved), "listed once written")

        launcher.saveCurrentGame(at: date(60))
        launcher.refresh()
        XCTAssertEqual(launcher.otherSaves.count, 1, "the player's save, written before the list is read")

        launcher.returnToStart()
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.session?.world, saved)
    }

    /// A save that cannot be written is reported on the game's status
    /// line, as when it was written at once.
    @MainActor
    func testAFailedSaveIsReported() async throws {
        // A file where the save folder should be: every save fails.
        try Data("x".utf8).write(to: directory)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        await launcher.autosaveInBackground(at: date(0))?.value
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: SaveError.fileSystem.playerMessage(in: .english)))
        let serial = session.messageSerial
        await launcher.saveCurrentGame(at: date(0)).value
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertNotEqual(session.messageSerial, serial, "reported again")
        XCTAssertNotNil(launcher.session, "the game goes on")
    }
}
