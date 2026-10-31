import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 497 (P2-2): the game menu's Back to Start writes the autosave
/// and reads the list of saves off the main thread, and the start screen
/// comes once it is written; a save that fails keeps the game.
final class ReturnToStartInBackgroundTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReturnToStartInBackgroundTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let date = Date(timeIntervalSince1970: 1_790_942_400)

    /// The tap leaves the game as it is until the autosave is written: the
    /// world of the moment of the tap is saved, then the start screen comes
    /// with the list read again. A second tap meanwhile does nothing.
    @MainActor
    func testTheStartScreenComesOnceTheAutosaveIsWritten() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        let world = session.worldToSave

        let leaving = try XCTUnwrap(launcher.returnToStartInBackground(at: date))
        XCTAssertNotNil(launcher.session, "not saved on the main thread")
        XCTAssertTrue(launcher.isReturningToStart)
        XCTAssertNil(launcher.returnToStartInBackground(at: date), "a second tap waits for the first")

        await leaving.value
        XCTAssertNil(launcher.session)
        XCTAssertFalse(launcher.isReturningToStart)
        XCTAssertEqual(launcher.entries.filter { $0.kind == .autosave }.count, 1, "the list read again")
        let saved = try SaveLibrary.decode(Data(contentsOf: directory.appendingPathComponent("autosave.json")))
        XCTAssertEqual(saved, world)
    }

    /// A save that cannot be written keeps the game, with why on its
    /// status line, as ``GameLauncher/returnToStart()`` does.
    @MainActor
    func testAFailedAutosaveKeepsTheGame() async throws {
        try Data("x".utf8).write(to: directory)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)

        await launcher.returnToStartInBackground(at: date)?.value
        XCTAssertTrue(launcher.session === session, "the game stays")
        XCTAssertFalse(launcher.isReturningToStart)
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: SaveError.fileSystem.playerMessage(in: .english)))
    }

    /// Decision 497 (P2-6): an autosave that cannot be written (a full
    /// phone) offers to leave without saving, on both ways back; leaving
    /// reaches the start screen, and keeping on playing keeps the game.
    @MainActor
    func testAFailedAutosaveOffersToLeaveWithoutSaving() async throws {
        try Data("x".utf8).write(to: directory)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        let session = try XCTUnwrap(launcher.session)
        XCTAssertNil(launcher.unsavedLeaving)

        await launcher.returnToStartInBackground(at: date)?.value
        let offer = try XCTUnwrap(launcher.unsavedLeaving, "the background way back asks")
        XCTAssertEqual(offer.reason, SaveError.fileSystem.playerMessage(in: .english))
        launcher.keepPlayingUnsaved()
        XCTAssertNil(launcher.unsavedLeaving)
        XCTAssertTrue(launcher.session === session, "keeping on playing keeps the game")

        launcher.returnToStart()
        XCTAssertNotNil(launcher.unsavedLeaving, "the immediate way back asks too")
        XCTAssertTrue(launcher.session === session)
        launcher.leaveWithoutSaving()
        XCTAssertNil(launcher.session, "the start screen, unsaved")
        XCTAssertNil(launcher.unsavedLeaving)
        XCTAssertFalse(launcher.isReturningToStart)
        XCTAssertFalse(session.isGameLoopRunning)
    }

    /// Nothing is offered, and nothing left, without a failed save.
    @MainActor
    func testLeavingWithoutSavingNeedsAFailedSave() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo()
        launcher.leaveWithoutSaving()
        XCTAssertNotNil(launcher.session, "not left without the offer")
        launcher.returnToStart()
        XCTAssertNil(launcher.session)
        XCTAssertNil(launcher.unsavedLeaving)
    }

    /// The question says what is lost, in both languages.
    func testTheQuestionSaysWhatIsLost() {
        let offer = UnsavedLeaving(reason: "The phone is full.")
        XCTAssertTrue(offer.message(in: .english).hasPrefix("The phone is full."))
        XCTAssertTrue(offer.message(in: .english).contains("since the last save"))
        XCTAssertTrue(offer.message(in: .traditionalChinese).contains("上次存檔"))
        XCTAssertEqual(UnsavedLeaving.leaveButton(in: .traditionalChinese), "不存檔離開")
    }

    /// The start screen's list read off the main thread; a read in the
    /// background does not put back a list older than one read since.
    @MainActor
    func testTheListIsReadInTheBackgroundAndTheLatestReadWins() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertTrue(launcher.entries.isEmpty)
        launcher.openDemo()
        let world = try XCTUnwrap(launcher.session).worldToSave
        launcher.returnToStart()
        let afterReturn = launcher.entries
        XCTAssertFalse(afterReturn.isEmpty)

        try SaveLibrary(directory: directory).save(world, as: .manual, at: date, named: "Mine")
        await launcher.refreshInBackground().value
        XCTAssertEqual(launcher.entries.count, afterReturn.count + 1)

        let stale = launcher.refreshInBackground()
        try SaveLibrary(directory: directory).save(world, as: .manual, at: date, named: "Later")
        launcher.refresh()
        let latest = launcher.entries
        await stale.value
        XCTAssertEqual(launcher.entries, latest, "the older read dropped")
        XCTAssertEqual(latest.count, afterReturn.count + 2)
    }
}
