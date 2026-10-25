import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 415: the "What's New" card shows once, the first time an
/// updated app opens, never on a new install, and its news is written in
/// both languages.
final class WhatsNewTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WhatsNewTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor private func launch() -> GameLauncher {
        GameLauncher(library: SaveLibrary(directory: directory), language: .english)
    }

    /// Writes the preferences an older app left: launched before, the card
    /// seen as `seen` (`nil`: an app from before the card).
    private func writePreferences(seen: String?) throws {
        var preferences = LauncherPreferences()
        preferences.hasLaunched = true
        preferences.whatsNewSeen = seen
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: directory.appendingPathComponent(GameLauncher.preferencesFileName))
    }

    /// A new install has nothing new: no card, then or later.
    @MainActor func testANewInstallDoesNotShowTheCard() {
        XCTAssertTrue(launch().isFirstLaunch)
        XCTAssertFalse(launch().showsWhatsNew)
        XCTAssertFalse(launch().showsWhatsNew)
    }

    /// An app updated from one without the card shows it once; closed, it
    /// stays closed in the next launches.
    @MainActor func testAnUpdateShowsTheCardOnce() throws {
        try writePreferences(seen: nil)
        let launcher = launch()
        XCTAssertFalse(launcher.isFirstLaunch)
        XCTAssertTrue(launcher.showsWhatsNew)
        XCTAssertTrue(launch().showsWhatsNew, "until it is closed")
        launcher.dismissWhatsNew()
        XCTAssertFalse(launcher.showsWhatsNew)
        XCTAssertFalse(launch().showsWhatsNew)
    }

    /// An app that saw an earlier build's news shows the newest; one that
    /// saw the newest does not.
    @MainActor func testANewerEntryShowsTheCardAgain() throws {
        try writePreferences(seen: "an earlier build")
        XCTAssertTrue(launch().showsWhatsNew)
        try writePreferences(seen: WhatsNew.edition)
        XCTAssertFalse(launch().showsWhatsNew)
    }

    /// Preferences written before the card, without its key, still read,
    /// with nothing seen.
    func testPreferencesFromBeforeTheCardStillRead() throws {
        var preferences = LauncherPreferences()
        preferences.tutorialCompleted = true
        preferences.whatsNewSeen = "an earlier build"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "whatsNewSeen"))
        let read = try JSONDecoder().decode(LauncherPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(read.whatsNewSeen)
        XCTAssertTrue(read.tutorialCompleted)
    }

    /// Every entry has an id of its own and news in both languages, each
    /// line a sentence or so; the newest is the edition.
    func testTheNewsIsInBothLanguages() {
        XCTAssertFalse(WhatsNew.entries.isEmpty)
        XCTAssertEqual(WhatsNew.edition, WhatsNew.entries.first?.id)
        XCTAssertEqual(Set(WhatsNew.entries.map(\.id)).count, WhatsNew.entries.count)
        for entry in WhatsNew.entries {
            XCTAssertFalse(entry.items.isEmpty, entry.id)
            for line in entry.items + entry.fixes {
                XCTAssertFalse(line.english.isEmpty)
                XCTAssertFalse(line.chinese.isEmpty)
                XCTAssertNotEqual(line.english, line.chinese)
                XCTAssertLessThanOrEqual(line.chinese.count, 60, line.chinese)
                XCTAssertEqual(line.text(in: .traditionalChinese), line.chinese)
                XCTAssertEqual(line.text(in: .english), line.english)
            }
        }
    }

    /// Help's search finds the row by its name in either language and by
    /// the newest news.
    func testHelpsSearchFindsTheRow() {
        XCTAssertTrue(WhatsNew.shows(matching: ""))
        XCTAssertTrue(WhatsNew.shows(matching: "what's new"))
        XCTAssertTrue(WhatsNew.shows(matching: "這版新增"))
        XCTAssertTrue(WhatsNew.shows(matching: "更新"))
        if let line = WhatsNew.entries.first?.items.first {
            XCTAssertTrue(WhatsNew.shows(matching: String(line.chinese.prefix(2))))
        }
        XCTAssertFalse(WhatsNew.shows(matching: "zzzz"))
    }
}
