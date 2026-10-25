import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 397: the saves kept in step with the player's iCloud, so a game
/// goes on on another device. Two devices' save folders and one folder for
/// iCloud, all on disk: a round copies what changed on one side, and when a
/// save changed on both, keeps both, never one over the other.
final class SaveSyncTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SaveSyncTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_942_400 + seconds)
    }

    /// A device: its saves and what its last round left.
    private final class Device {
        let library: SaveLibrary
        var state = SaveSync.State()

        init(_ directory: URL) {
            library = SaveLibrary(directory: directory)
        }

        var folder: DirectorySaveFolder { DirectorySaveFolder(directory: library.directory) }

        func files() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: library.directory.path)) ?? []).sorted()
        }
    }

    private func device(_ name: String) -> Device {
        Device(root.appendingPathComponent(name, isDirectory: true))
    }

    private var cloudDirectory: URL { root.appendingPathComponent("iCloud", isDirectory: true) }

    @discardableResult
    private func sync(_ device: Device, with cloud: (any SaveSyncFolder)? = nil, mode: SaveSync.Mode = .full, at seconds: TimeInterval = 0) -> SaveSync.Outcome {
        SaveSync.run(
            local: device.folder, cloud: cloud ?? DirectorySaveFolder(directory: cloudDirectory), state: &device.state,
            mode: mode, language: .english, now: date(seconds)
        )
    }

    /// What `outcome` copied, deleted or kept twice, without where the saves
    /// stand after it.
    private func copies(_ outcome: SaveSync.Outcome) -> SaveSync.Outcome {
        var copies = outcome
        copies.marks = [:]
        copies.downloading = 0
        copies.needsUpdate = 0
        return copies
    }

    /// The files in iCloud but its mark.
    private func cloudFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: cloudDirectory.path)) ?? []).filter { $0 != SaveSync.markFileName }.sorted()
    }

    /// The cash of every save on `device`, the least first: each test's
    /// worlds are told apart by it.
    private func cash(on device: Device) throws -> [Int64] {
        try device.library.entries().map { try device.library.load($0).economy.balance.amount }.sorted()
    }

    /// A new game with `cash` cents.
    private func world(cash: Int64) throws -> GameWorld {
        GameWorld.newGame(balance: Money(cash))
    }

    func testAGameGoesOnOnAnotherDevice() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), news: NewsLog(), as: .autosave, at: date(0))
        try phone.library.save(world(cash: 30), as: .manual, at: date(10), named: "Taipei loop")
        let up = sync(phone)
        XCTAssertEqual(Set(up.uploaded), ["autosave", "save-2026-10-02 120010"])
        XCTAssertFalse(up.isIncomplete)
        XCTAssertEqual(cloudFiles(), ["autosave.json", "autosave.news.json", "save-2026-10-02 120010.json", "save-2026-10-02 120010.name"])

        let down = sync(pad)
        XCTAssertEqual(Set(down.downloaded), ["autosave", "save-2026-10-02 120010"])
        XCTAssertEqual(pad.files(), phone.files())
        let autosave = try XCTUnwrap(pad.library.newestAutosave())
        XCTAssertEqual(try pad.library.load(autosave), try world(cash: 60))
        XCTAssertEqual(pad.library.entries().compactMap(\.name), ["Taipei loop"], "with its name")

        // Played on on the pad, back on the phone.
        try pad.library.save(world(cash: 120), as: .autosave, at: date(100))
        XCTAssertEqual(sync(pad).uploaded, ["autosave"])
        XCTAssertEqual(sync(phone).downloaded, ["autosave"])
        XCTAssertEqual(try phone.library.load(XCTUnwrap(phone.library.newestAutosave())), try world(cash: 120))

        // Nothing changed: nothing to do.
        let idle = sync(phone)
        XCTAssertEqual(copies(idle), SaveSync.Outcome())
    }

    func testASaveChangedOnBothDevicesIsKeptTwice() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        sync(phone)
        sync(pad)
        // Both play on before either hears of the other.
        try phone.library.save(world(cash: 300), as: .autosave, at: date(200))
        try pad.library.save(world(cash: 400), as: .autosave, at: date(300))
        XCTAssertEqual(sync(phone).uploaded, ["autosave"], "the first to come back has nothing to compare with")

        let pads = sync(pad, at: 500)
        XCTAssertEqual(pads.keptBoth, ["save-2026-10-02 120320-other.json"], "named by when the phone saved it")
        XCTAssertEqual(pads.uploaded, ["autosave"])
        XCTAssertEqual(try pad.library.load(XCTUnwrap(pad.library.newestAutosave())), try world(cash: 400), "the pad goes on with its own")
        let copy = try XCTUnwrap(pad.library.entries().first { $0.kind == .manual })
        XCTAssertEqual(copy.name, "From another device")
        XCTAssertEqual(try pad.library.load(copy), try world(cash: 300), "the phone's is kept beside it")

        // The phone then gets both: neither game is lost on either device.
        let phones = sync(phone)
        XCTAssertEqual(Set(phones.downloaded), ["autosave", "save-2026-10-02 120320-other"])
        XCTAssertTrue(phones.keptBoth.isEmpty)
        XCTAssertEqual(try cash(on: phone), [300, 400])
        XCTAssertEqual(try cash(on: pad), [300, 400])
        XCTAssertEqual(copies(sync(pad)), SaveSync.Outcome(), "and the two are in step")
    }

    func testTheFirstRoundOfTwoDevicesWithGamesKeepsBoth() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        try pad.library.save(world(cash: 90), as: .autosave, at: date(5))
        try pad.library.rename(pad.library.save(world(cash: 10), as: .manual, at: date(1)), to: "Mine")
        sync(phone)
        let outcome = sync(pad)
        XCTAssertEqual(outcome.keptBoth.count, 1)
        XCTAssertEqual(try cash(on: pad), [10, 60, 90])
        sync(phone)
        XCTAssertEqual(try cash(on: phone), [10, 60, 90])
        XCTAssertEqual(phone.library.entries().compactMap(\.name).sorted(), ["From another device", "Mine"])
    }

    func testTheSameSaveOnBothIsLeftAlone() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        try FileManager.default.createDirectory(at: pad.library.directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: phone.library.directory.appendingPathComponent("autosave.json"), to: pad.library.directory.appendingPathComponent("autosave.json")
        )
        sync(phone)
        XCTAssertEqual(copies(sync(pad)), SaveSync.Outcome())
        XCTAssertEqual(pad.files(), ["autosave.json"])
    }

    func testASaveDeletedOnAnotherDeviceStaysHere() throws {
        let phone = device("phone"), pad = device("pad")
        let kept = try phone.library.save(world(cash: 30), as: .manual, at: date(0), named: "Old")
        let changed = try phone.library.save(world(cash: 40), as: .manual, at: date(1))
        sync(phone)
        sync(pad)
        XCTAssertEqual(pad.library.entries().count, 2)

        // Deleted on the phone: gone from iCloud, kept on the pad (only the
        // player deletes a save on a device), and not copied back.
        try phone.library.delete(kept)
        XCTAssertEqual(sync(phone).deleted, ["save-2026-10-02 120000"])
        XCTAssertEqual(copies(sync(pad)), SaveSync.Outcome())
        XCTAssertEqual(try cash(on: pad), [30, 40])
        XCTAssertEqual(copies(sync(pad)), SaveSync.Outcome(), "nor later")
        XCTAssertFalse(cloudFiles().contains("save-2026-10-02 120000.json"))

        // Renamed on the pad, deleted on the phone: the pad's is kept.
        try pad.library.rename(XCTUnwrap(pad.library.entries().first { $0.name == nil }), to: "Keep me")
        try phone.library.delete(changed)
        sync(phone)
        let outcome = sync(pad)
        XCTAssertEqual(outcome.uploaded, ["save-2026-10-02 120001"])
        XCTAssertEqual(sync(phone).downloaded, ["save-2026-10-02 120001"], "and comes back to the phone")
        XCTAssertEqual(phone.library.entries().map(\.name), ["Keep me"])
    }

    func testAGameOpenIsNeverWrittenOverOrDeleted() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        let manual = try phone.library.save(world(cash: 5), as: .manual, at: date(1))
        sync(phone)
        sync(pad)
        try pad.library.save(world(cash: 200), as: .autosave, at: date(100))
        try pad.library.delete(XCTUnwrap(pad.library.entries().first { $0.kind == .manual }))
        try pad.library.save(world(cash: 7), as: .manual, at: date(2))
        sync(pad)
        _ = manual

        // The phone is in a game: the pad's autosave and deletion wait; its
        // new save comes at once.
        let open = sync(phone, mode: .keepingDevice)
        XCTAssertEqual(open.downloaded, ["save-2026-10-02 120002"])
        XCTAssertTrue(open.deleted.isEmpty)
        XCTAssertEqual(try cash(on: phone), [5, 7, 60])
        // Back on the start screen.
        let start = sync(phone)
        XCTAssertEqual(start.downloaded, ["autosave"])
        XCTAssertTrue(start.deleted.isEmpty, "the pad's deletion leaves the phone's")
        XCTAssertEqual(try cash(on: phone), [5, 7, 200])

        // Saved in the game meanwhile instead: both are kept.
        let other = device("other")
        sync(other)
        try other.library.save(world(cash: 900), as: .autosave, at: date(900))
        sync(other)
        try phone.library.save(world(cash: 260), as: .autosave, at: date(950))
        let saved = sync(phone, mode: .keepingDevice)
        XCTAssertEqual(saved.keptBoth.count, 1)
        XCTAssertEqual(try phone.library.load(XCTUnwrap(phone.library.newestAutosave())), try world(cash: 260))
        XCTAssertEqual(try cash(on: phone), [5, 7, 260, 900])
    }

    func testASaveOnItsWayFromICloudWaits() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), news: NewsLog(), as: .autosave, at: date(0))
        try phone.library.save(world(cash: 5), as: .manual, at: date(1))
        sync(phone)
        sync(pad)
        try phone.library.save(world(cash: 120), news: NewsLog(), as: .autosave, at: date(100))
        sync(phone)
        // iCloud lists the pad the phone's new news log, its autosave still
        // on the way (a stand-in), and the manual save's file as not there yet.
        let cloud = TestFolder(directory: cloudDirectory)
        try FileManager.default.moveItem(
            at: cloudDirectory.appendingPathComponent("autosave.json"), to: cloudDirectory.appendingPathComponent(".autosave.json.icloud")
        )
        cloud.unavailable = ["save-2026-10-02 120001.json"]
        let waiting = sync(pad, with: cloud)
        XCTAssertEqual(copies(waiting), SaveSync.Outcome(), "neither taken for deleted, nor half copied")
        XCTAssertEqual(waiting.marks, ["autosave": .downloading, "save-2026-10-02 120001": .downloading])
        XCTAssertEqual(try cash(on: pad), [5, 60])
        XCTAssertEqual(pad.files(), ["autosave.json", "autosave.news.json", "save-2026-10-02 120001.json"])

        try FileManager.default.moveItem(
            at: cloudDirectory.appendingPathComponent(".autosave.json.icloud"), to: cloudDirectory.appendingPathComponent("autosave.json")
        )
        cloud.unavailable = []
        XCTAssertEqual(sync(pad, with: cloud).downloaded, ["autosave"], "once it is there")
        XCTAssertEqual(try cash(on: pad), [5, 120])
    }

    func testWhatICloudKeptTwiceIsKeptAsASave() throws {
        let phone = device("phone")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        sync(phone)
        let cloud = TestFolder(directory: cloudDirectory)
        cloud.versions = [
            "autosave.json": [try SaveLibrary.encode(world(cash: 75), at: date(30))],
        ]
        // Only a name written at the same moment: forgotten too.
        try phone.library.save(world(cash: 1), as: .manual, at: date(1), named: "Named")
        sync(phone)
        cloud.versions["save-2026-10-02 120001.name"] = [Data("Other".utf8)]
        let outcome = sync(phone, with: cloud)
        XCTAssertEqual(outcome.keptBoth, ["save-2026-10-02 120030-other.json"])
        XCTAssertTrue(cloud.versions.isEmpty, "then forgotten by iCloud")
        XCTAssertEqual(try cash(on: phone), [1, 60, 75])
        XCTAssertTrue(cloudFiles().contains("save-2026-10-02 120030-other.json"))
    }

    func testAnEmptyICloudOrAnotherAccountsDeletesNothingHere() throws {
        let phone = device("phone")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        try phone.library.save(world(cash: 5), as: .manual, at: date(1), named: "Mine")
        sync(phone)

        // The account's iCloud data deleted (or a backup put back before
        // iCloud lists the saves): the folder is empty, and the saves here
        // are put back there, not deleted.
        try FileManager.default.removeItem(at: cloudDirectory)
        let emptied = sync(phone)
        XCTAssertTrue(emptied.deleted.isEmpty)
        XCTAssertEqual(Set(emptied.uploaded), ["autosave", "save-2026-10-02 120001"])
        XCTAssertEqual(try cash(on: phone), [5, 60])

        // Another account, whose iCloud has another device's autosave: the
        // two are kept, not one copied over the other.
        let first = TestFolder(directory: cloudDirectory)
        first.owner = 1
        sync(phone, with: first)
        let otherDirectory = root.appendingPathComponent("other iCloud", isDirectory: true)
        let pad = device("pad")
        try pad.library.save(world(cash: 500), as: .autosave, at: date(50))
        _ = SaveSync.run(
            local: pad.folder, cloud: DirectorySaveFolder(directory: otherDirectory), state: &pad.state,
            language: .english, now: date(50)
        )
        let second = TestFolder(directory: otherDirectory)
        second.owner = 2
        let switched = sync(phone, with: second, at: 60)
        XCTAssertTrue(switched.deleted.isEmpty)
        XCTAssertTrue(switched.downloaded.isEmpty)
        XCTAssertEqual(switched.keptBoth.count, 1)
        XCTAssertEqual(try phone.library.load(XCTUnwrap(phone.library.newestAutosave())), try world(cash: 60))
        XCTAssertEqual(try cash(on: phone), [5, 60, 500])
        XCTAssertEqual(phone.state.owner, 2)
    }

    func testAnEmptiedICloudFilledByAnOlderDeviceFirst() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        sync(phone)
        sync(pad)
        try phone.library.save(world(cash: 700), as: .autosave, at: date(100))
        try phone.library.save(world(cash: 5), as: .manual, at: date(101), named: "Mine")
        sync(phone)
        // The account's iCloud data deleted; the pad, left since, first.
        try FileManager.default.removeItem(at: cloudDirectory)
        XCTAssertEqual(sync(pad, at: 200).uploaded, ["autosave"])
        let outcome = sync(phone, at: 300)
        XCTAssertTrue(outcome.deleted.isEmpty)
        XCTAssertTrue(outcome.downloaded.isEmpty)
        XCTAssertEqual(outcome.keptBoth.count, 1)
        XCTAssertEqual(try phone.library.load(XCTUnwrap(phone.library.newestAutosave())), try world(cash: 700))
        XCTAssertEqual(try cash(on: phone), [5, 60, 700])
    }

    func testAGameStartedWhileTheRoundRunsIsNotWrittenUnder() throws {
        let phone = device("phone"), pad = device("pad")
        try pad.library.save(world(cash: 60), as: .autosave, at: date(0))
        try pad.library.save(world(cash: 5), as: .manual, at: date(1))
        sync(pad)
        let outcome = SaveSync.run(
            local: phone.folder, cloud: DirectorySaveFolder(directory: cloudDirectory), state: &phone.state,
            language: .english, now: date(0), isGameOpen: { true }
        )
        XCTAssertEqual(outcome.downloaded, ["save-2026-10-02 120001"])
        XCTAssertNil(phone.library.newestAutosave())
    }

    func testASaveHalfWrittenToAFullDeviceIsPutBack() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), news: NewsLog(), as: .autosave, at: date(0))
        sync(phone)
        sync(pad)
        let before = try pad.files().map { try Data(contentsOf: pad.library.directory.appendingPathComponent($0)) }
        try phone.library.save(world(cash: 120), as: .autosave, at: date(100))
        try Data("another news log".utf8).write(to: phone.library.directory.appendingPathComponent("autosave.news.json"))
        sync(phone)
        // The pad's folder takes the news log, then is full.
        let full = TestFolder(directory: pad.library.directory)
        full.failsWritesOf = ["autosave.json"]
        let outcome = SaveSync.run(
            local: full, cloud: DirectorySaveFolder(directory: cloudDirectory), state: &pad.state, language: .english, now: date(0)
        )
        XCTAssertTrue(outcome.isIncomplete)
        XCTAssertEqual(try pad.files().map { try Data(contentsOf: pad.library.directory.appendingPathComponent($0)) }, before)
        XCTAssertEqual(sync(pad).downloaded, ["autosave"], "and comes whole next time")
    }

    func testWhileAGameIsOpenNoAutosaveIsTakenWhereThereIsNone() throws {
        let phone = device("phone"), pad = device("pad")
        try pad.library.save(world(cash: 60), as: .autosave, at: date(0))
        sync(pad)

        // A new game on the phone, not saved yet: the pad's autosave would
        // be written over by the phone's next one, and that copied back.
        XCTAssertTrue(sync(phone, mode: .keepingDevice).downloaded.isEmpty)
        XCTAssertNil(phone.library.newestAutosave())
        XCTAssertEqual(sync(phone).downloaded, ["autosave"], "on the start screen")

        // Its autosave deleted on the phone, changed on the pad: the same.
        try phone.library.delete(XCTUnwrap(phone.library.entries().first { $0.kind == .autosave }))
        try pad.library.save(world(cash: 90), as: .autosave, at: date(90))
        sync(pad)
        XCTAssertTrue(sync(phone, mode: .keepingDevice).downloaded.isEmpty)
        XCTAssertNil(phone.library.newestAutosave())
        XCTAssertEqual(sync(phone).downloaded, ["autosave"])
        XCTAssertEqual(try cash(on: phone), [90])
    }

    func testAFullICloudLeavesTheSavesOnTheDevice() throws {
        let phone = device("phone")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        let full = TestFolder(directory: cloudDirectory)
        full.failsWrites = true
        let outcome = sync(phone, with: full)
        XCTAssertTrue(outcome.isIncomplete)
        XCTAssertTrue(outcome.uploaded.isEmpty)
        XCTAssertEqual(phone.files(), ["autosave.json"])
        XCTAssertEqual(try cash(on: phone), [60])

        // And a folder that cannot be listed changes nothing.
        let gone = TestFolder(directory: cloudDirectory)
        gone.failsListing = true
        XCTAssertTrue(sync(phone, with: gone).isIncomplete)

        // With room again, the next round copies it.
        XCTAssertEqual(sync(phone).uploaded, ["autosave"])
    }

    func testTheAutosavesTakenInTurnStayOnTheDevice() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        try phone.library.saveAutosaveSlot(world(cash: 50), at: date(1))
        try phone.library.saveAutosaveSlot(world(cash: 55), at: date(2))
        XCTAssertEqual(sync(phone).uploaded, ["autosave"])
        XCTAssertEqual(cloudFiles(), ["autosave.json"], "only the latest goes")
        sync(pad)
        XCTAssertEqual(try cash(on: pad), [60])
        // The pad's own, numbered as the phone's are, never meet them.
        try pad.library.saveAutosaveSlot(world(cash: 70), at: date(3))
        XCTAssertEqual(copies(sync(pad)), SaveSync.Outcome())
        XCTAssertEqual(try cash(on: phone), [50, 55, 60])
    }

    /// `world` saved as a later build would: a save version this build
    /// does not read.
    private func laterBuildsSave(_ world: GameWorld, at seconds: TimeInterval) throws -> Data {
        var file = try XCTUnwrap(JSONSerialization.jsonObject(with: SaveLibrary.encode(world, at: date(seconds))) as? [String: Any])
        var game = try XCTUnwrap(file["game"] as? [String: Any])
        game["saveVersion"] = SavedGame.currentVersion + 1
        file["game"] = game
        return try JSONSerialization.data(withJSONObject: file)
    }

    func testALaterBuildsSaveIsNeverWrittenOverHereNorWritesOverOne() throws {
        let phone = device("phone"), pad = device("pad")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        sync(phone)
        sync(pad)
        // The phone is updated and saves in the later version.
        let later = try laterBuildsSave(world(cash: 900), at: 100)
        try later.write(to: phone.library.directory.appendingPathComponent("autosave.json"))
        try laterBuildsSave(world(cash: 800), at: 90).write(to: phone.library.directory.appendingPathComponent("save-later.json"))
        sync(phone)

        // The pad, not updated, keeps going with its own autosave; the
        // phone's own save comes, listed as needing an update.
        let waiting = sync(pad)
        XCTAssertEqual(waiting.downloaded, ["save-later"])
        XCTAssertEqual(try pad.library.load(XCTUnwrap(pad.library.newestAutosave())), try world(cash: 60))
        let listed = try XCTUnwrap(pad.library.entries().first { $0.id == "save-later.json" })
        XCTAssertEqual(listed.problem, .newerVersion(SavedGame.currentVersion + 1))
        XCTAssertTrue(listed.problem?.playerMessage(in: .traditionalChinese).contains("請更新 App") == true)
        let again = sync(pad)
        XCTAssertEqual(copies(again), SaveSync.Outcome(), "and waits, round after round")
        // Said as needing an update, not as waiting to go up: being online
        // would not bring it.
        XCTAssertEqual(again.marks["autosave"], .needsUpdate)
        XCTAssertEqual(again.waiting, 0)
        XCTAssertEqual(CloudSaves.after(again, at: date(150)), .waiting(uploads: 0, downloads: 0, needsUpdate: 1))
        XCTAssertEqual(
            CloudSaves.after(again, at: date(150)).footnote(in: .traditionalChinese),
            "另一台裝置的 1 個存檔來自較新版本的遊戲，請更新 App 後再同步。"
        )

        // The pad plays on: the later game is kept beside it, never lost.
        try pad.library.save(world(cash: 70), as: .autosave, at: date(200))
        let kept = sync(pad)
        XCTAssertEqual(kept.keptBoth.count, 1)
        let copy = try XCTUnwrap(pad.library.entries().first { $0.name == "From another device" })
        XCTAssertEqual(copy.problem, .newerVersion(SavedGame.currentVersion + 1))
        sync(phone)
        // (In this test the phone is this build too, so the later saves
        // are compared byte for byte instead of loaded.)
        XCTAssertEqual(try phone.library.load(XCTUnwrap(phone.library.newestAutosave())), try world(cash: 70))
        let files = try phone.files().filter { $0.hasSuffix(".json") }.map { try Data(contentsOf: phone.library.directory.appendingPathComponent($0)) }
        XCTAssertTrue(files.contains(later), "the later game is on the phone still: none was written over")
        XCTAssertEqual(phone.library.entries().filter { $0.problem == .newerVersion(SavedGame.currentVersion + 1) }.count, 2)
    }

    @MainActor
    func testContinueOnABuildThatCannotReadTheAutosave() async throws {
        try FileManager.default.createDirectory(at: cloudDirectory, withIntermediateDirectories: true)
        try laterBuildsSave(world(cash: 900), at: 100).write(to: cloudDirectory.appendingPathComponent("autosave.json"))
        let cloud = cloudDirectory
        let pad = GameLauncher(library: SaveLibrary(directory: root.appendingPathComponent("pad")), language: .english)
        pad.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        await pad.syncSaves()?.value
        XCTAssertNil(pad.autosave, "not taken as the autosave")
        pad.continueGame()
        XCTAssertNil(pad.session)
        XCTAssertNotNil(pad.message)
    }

    func testOnlySavesAreCopied() throws {
        let phone = device("phone")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        for name in [GameLauncher.preferencesFileName, "challenge-records.data", SaveSync.stateFileName, "notes.txt"] {
            try Data("x".utf8).write(to: phone.library.directory.appendingPathComponent(name))
        }
        sync(phone)
        XCTAssertEqual(cloudFiles(), ["autosave.json"])
    }

    func testTheStateIsKeptBetweenLaunches() throws {
        let file = root.appendingPathComponent("state.data")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(SaveSync.State.read(from: file), SaveSync.State(), "none yet")
        let state = SaveSync.State(synced: ["autosave": 42])
        try state.write(to: file)
        XCTAssertEqual(SaveSync.State.read(from: file), state)
        try Data("damaged".utf8).write(to: file)
        XCTAssertEqual(SaveSync.State.read(from: file), SaveSync.State(), "a damaged one is read as none: saves are kept twice at worst")
    }

    func testTheWords() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertNil(CloudSaves.off.footnote(in: language), "nothing is said in a build without iCloud")
            for status in [CloudSaves.iCloudOff, .syncing, .synced(at: date(0)), .waiting(uploads: 1, downloads: 0), .waiting(uploads: 0, downloads: 2), .waiting(uploads: 0, downloads: 0, needsUpdate: 1), .incomplete] {
                XCTAssertFalse(status.footnote(in: language, now: date(60))?.isEmpty ?? true, "\(status)")
                XCTAssertNotNil(status.systemImage)
            }
            for mark in [CloudSaveMark.onlyOnDevice, .inICloud, .waiting, .downloading, .needsUpdate] {
                XCTAssertFalse(mark.text(in: language).isEmpty)
            }
            XCTAssertFalse(CloudSaves.keptTwiceText(1, in: language).isEmpty)
            XCTAssertTrue(CloudSaves.keptTwiceText(3, in: language).contains("3"))
        }
        XCTAssertTrue(CloudSaves.keptTwiceText(1, in: .traditionalChinese).contains("另一台裝置的進度"))
        XCTAssertEqual(
            CloudSaves.synced(at: date(0)).footnote(in: .traditionalChinese, now: date(300)),
            "存檔已放進你的 iCloud（5 分鐘前同步），換一台 iPhone 或 iPad 都能接著玩。"
        )
        XCTAssertTrue(CloudSaves.iCloudOff.footnote(in: .traditionalChinese)?.contains("設定 › 你的名字 › iCloud") ?? false, "says where to turn it on")
        XCTAssertEqual(
            CloudSaves.waiting(uploads: 2, downloads: 1).footnote(in: .traditionalChinese),
            "2 個存檔等待上傳到 iCloud，連上網路後會自動上傳。另一台裝置的 1 個存檔正在下載。"
        )
    }

    // MARK: - Where each save stands (decision 397, later)

    func testAFileWhoseUploadCannotBeToldIsNotTakenAsUp() throws {
        XCTAssertFalse(SaveSyncFolderFile.inICloud(isCurrent: true, isUploaded: nil).isUploaded, "never said synced when not known")
        XCTAssertTrue(SaveSyncFolderFile.inICloud(isCurrent: true, isUploaded: true).isUploaded)
        XCTAssertFalse(SaveSyncFolderFile.inICloud(isCurrent: false, isUploaded: true).isAvailable)
        // A save in iCloud whose state cannot be read waits, not synced.
        let phone = device("phone")
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        let cloud = UnknownUploadFolder(directory: cloudDirectory)
        let round = sync(phone, with: cloud)
        XCTAssertEqual(round.marks, ["autosave": .waiting])
        XCTAssertEqual(CloudSaves.after(round, at: date(10)), .waiting(uploads: 1, downloads: 0))
    }

    func testEachSaveSaysWhereItStands() throws {
        let phone = device("phone"), pad = device("pad")
        let cloud = TestFolder(directory: cloudDirectory)
        try phone.library.save(world(cash: 60), as: .autosave, at: date(0))
        try phone.library.save(world(cash: 30), as: .manual, at: date(10), named: "Taipei loop")
        let manual = "save-2026-10-02 120010"
        // Written to iCloud's folder, but not yet up (offline): another
        // device does not see them yet.
        cloud.notUploaded = ["autosave.json", manual + ".json", manual + ".name"]
        var round = sync(phone, with: cloud)
        XCTAssertEqual(round.marks, ["autosave": .waiting, manual: .waiting])
        XCTAssertEqual(CloudSaves.after(round, at: date(20)), .waiting(uploads: 2, downloads: 0))
        // Up now.
        cloud.notUploaded = []
        round = sync(phone, with: cloud)
        XCTAssertEqual(round.marks, ["autosave": .inICloud, manual: .inICloud])
        XCTAssertEqual(CloudSaves.after(round, at: date(30)), .synced(at: date(30)))

        // On the iPad, a save iCloud has not brought down yet: counted as
        // on its way, not as gone.
        cloud.unavailable = [manual + ".json"]
        round = sync(pad, with: cloud)
        XCTAssertEqual(round.marks, ["autosave": .inICloud])
        XCTAssertEqual(round.downloading, 1)
        XCTAssertEqual(CloudSaves.after(round, at: date(40)), .waiting(uploads: 0, downloads: 1))
        // Brought down: the next round (Sync Now) takes it.
        cloud.unavailable = []
        round = sync(pad, with: cloud)
        XCTAssertEqual(round.marks, ["autosave": .inICloud, manual: .inICloud])
        XCTAssertEqual(CloudSaves.after(round, at: date(50)), .synced(at: date(50)))

        // The phone changes its autosave while the iPad's newer one is on
        // its way: the phone's waits.
        try pad.library.save(world(cash: 70), as: .autosave, at: date(60))
        sync(pad, with: cloud)
        cloud.unavailable = ["autosave.json"]
        round = sync(phone, with: cloud)
        XCTAssertEqual(round.marks["autosave"], .downloading)
        XCTAssertEqual(CloudSaves.after(round, at: date(70)), .waiting(uploads: 0, downloads: 1))
        cloud.unavailable = []

        // Deleted on the iPad: the phone keeps its own, on it alone.
        try pad.library.delete(XCTUnwrap(pad.library.entries().first { $0.kind == .manual }))
        sync(pad, with: cloud)
        round = sync(phone, with: cloud)
        XCTAssertEqual(round.marks[manual], .onlyOnDevice)

        // A new save iCloud would not take: on this device only, and said.
        try phone.library.save(world(cash: 90), as: .manual, at: date(80))
        cloud.failsWrites = true
        round = sync(phone, with: cloud)
        XCTAssertEqual(round.marks["save-2026-10-02 120120"], .onlyOnDevice)
        XCTAssertEqual(CloudSaves.after(round, at: date(90)), .incomplete)
        XCTAssertEqual(CloudSaves.after(nil, at: date(90)), .iCloudOff)
    }

    // MARK: - The launcher

    @MainActor
    func testTheLauncherKeepsItsSavesInICloud() async throws {
        let cloud = cloudDirectory
        let phone = GameLauncher(library: SaveLibrary(directory: root.appendingPathComponent("phone")), language: .english)
        XCTAssertNil(phone.syncSaves(), "no iCloud: nothing runs")
        XCTAssertEqual(phone.cloudSaves, .off)

        phone.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        phone.startNewGame()
        let played = try XCTUnwrap(phone.session).worldToSave
        phone.returnToStart()
        let round = phone.syncSaves(at: date(100))
        XCTAssertEqual(phone.cloudSaves, .syncing, "said while it runs")
        XCTAssertFalse(phone.cloudSaves.canSyncNow)
        await round?.value
        XCTAssertEqual(phone.cloudSaves, .synced(at: date(100)))
        XCTAssertEqual(phone.autosave.flatMap(phone.cloudMark(of:)), .inICloud)
        XCTAssertTrue(cloudFiles().contains("autosave.json"))

        let pad = GameLauncher(library: SaveLibrary(directory: root.appendingPathComponent("pad")), language: .traditionalChinese)
        pad.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        XCTAssertNil(pad.autosave)
        await pad.syncSaves()?.value
        XCTAssertNotNil(pad.autosave, "the list is read again")
        pad.continueGame()
        XCTAssertEqual(try XCTUnwrap(pad.session).world, played)

        // iCloud turned off: the saves stay on the device, and the line
        // says where to turn it on; no message comes up.
        pad.returnToStart()
        pad.cloudSaveFolder = { nil }
        await pad.syncSaves()?.value
        XCTAssertEqual(pad.cloudSaves, .iCloudOff)
        XCTAssertTrue(pad.cloudMarks.isEmpty)
        XCTAssertNil(pad.message)
        XCTAssertNotNil(pad.autosave)
        // Turned on again: Sync Now finds it at once.
        pad.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        await pad.syncNow(at: date(200))?.value
        XCTAssertEqual(pad.cloudSaves, .synced(at: date(200)))
    }

    @MainActor
    func testSyncNowRunsOneRoundAtATime() async throws {
        let cloud = cloudDirectory
        let phone = GameLauncher(library: SaveLibrary(directory: root.appendingPathComponent("phone")), language: .english)
        XCTAssertNil(phone.syncNow(), "a build without iCloud has no Sync Now")
        phone.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        let first = phone.syncNow(at: date(0))
        XCTAssertNotNil(first)
        XCTAssertNil(phone.syncNow(at: date(1)), "not again while one runs")
        await first?.value
        // Two rounds asked for (going to the background, then back): the
        // first's end does not say synced while the second runs.
        // Whichever ends first, only the last says how things stand.
        let a = phone.syncSaves(at: date(10)), b = phone.syncSaves(at: date(11))
        await a?.value
        XCTAssertNotEqual(phone.cloudSaves, .synced(at: date(10)))
        await b?.value
        XCTAssertEqual(phone.cloudSaves, .synced(at: date(11)))
    }

    @MainActor
    func testTheLauncherTellsOfASaveKeptTwice() async throws {
        let cloud = cloudDirectory
        let other = Device(root.appendingPathComponent("other"))
        try other.library.save(world(cash: 500), as: .autosave, at: date(0))
        sync(other)
        let phone = GameLauncher(library: SaveLibrary(directory: root.appendingPathComponent("phone")), language: .english)
        phone.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        phone.startNewGame()
        // In the game: the other device's autosave is not taken over this
        // one's, and the player hears of both on the start screen.
        phone.autosaveCurrentGame()
        await phone.syncSaves()?.value
        XCTAssertNil(phone.message, "not in the game")
        phone.returnToStart()
        XCTAssertEqual(phone.message?.text, CloudSaves.keptTwiceText(1, in: .english))
        XCTAssertEqual(phone.otherSaves.map(\.name), ["From another device"])
    }
}

/// A folder on disk that can be told to be iCloud on a bad day.
private final class TestFolder: SaveSyncFolder, @unchecked Sendable {
    let base: DirectorySaveFolder
    var unavailable: Set<String> = []
    var failsWrites = false
    var failsWritesOf: Set<String> = []
    var failsListing = false
    var versions: [String: [Data]] = [:]
    var notUploaded: Set<String> = []
    var owner: UInt64?

    struct Refused: Error {}

    init(directory: URL) {
        base = DirectorySaveFolder(directory: directory)
    }

    func files() throws -> [String: SaveSyncFolderFile] {
        if failsListing { throw Refused() }
        var files = try base.files()
        for name in unavailable where files[name] != nil {
            files[name] = SaveSyncFolderFile(isAvailable: false)
        }
        for name in notUploaded where files[name] != nil {
            files[name]?.isUploaded = false
        }
        return files
    }

    func read(_ name: String) throws -> Data {
        try base.read(name)
    }

    func write(_ data: Data, to name: String) throws {
        if failsWrites || failsWritesOf.contains(name) { throw Refused() }
        try base.write(data, to: name)
    }

    func remove(_ name: String) throws {
        if failsWrites { throw Refused() }
        try base.remove(name)
    }

    func otherVersions(of name: String) -> [Data] {
        versions[name] ?? []
    }

    func discardOtherVersions(of name: String) {
        versions[name] = nil
    }
}

/// iCloud's folder on a device that cannot tell whether its files are up,
/// as the app lists it.
private struct UnknownUploadFolder: SaveSyncFolder {
    let base: DirectorySaveFolder

    init(directory: URL) {
        base = DirectorySaveFolder(directory: directory)
    }

    func files() throws -> [String: SaveSyncFolderFile] {
        try base.files().mapValues { _ in .inICloud(isCurrent: true, isUploaded: nil) }
    }

    func read(_ name: String) throws -> Data { try base.read(name) }
    func write(_ data: Data, to name: String) throws { try base.write(data, to: name) }
    func remove(_ name: String) throws { try base.remove(name) }
    func otherVersions(of name: String) -> [Data] { [] }
    func discardOtherVersions(of name: String) {}
}
