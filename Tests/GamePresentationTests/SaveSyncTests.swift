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

    private func cloudFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: cloudDirectory.path)) ?? []).sorted()
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
        XCTAssertEqual(idle, SaveSync.Outcome())
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
        XCTAssertEqual(sync(pad), SaveSync.Outcome(), "and the two are in step")
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
        XCTAssertEqual(sync(pad), SaveSync.Outcome())
        XCTAssertEqual(pad.files(), ["autosave.json"])
    }

    func testADeletedSaveIsDeletedOnTheOtherUnlessItChangedThere() throws {
        let phone = device("phone"), pad = device("pad")
        let kept = try phone.library.save(world(cash: 30), as: .manual, at: date(0), named: "Old")
        let changed = try phone.library.save(world(cash: 40), as: .manual, at: date(1))
        sync(phone)
        sync(pad)
        XCTAssertEqual(pad.library.entries().count, 2)

        try phone.library.delete(kept)
        XCTAssertEqual(sync(phone).deleted, ["save-2026-10-02 120000"])
        XCTAssertEqual(sync(pad).deleted, ["save-2026-10-02 120000"])
        XCTAssertEqual(pad.files(), ["save-2026-10-02 120001.json"], "with its name file")

        // Renamed on the pad, deleted on the phone: the pad's is kept.
        try pad.library.rename(XCTUnwrap(pad.library.entries().first), to: "Keep me")
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
        XCTAssertEqual(start.deleted, ["save-2026-10-02 120001"])
        XCTAssertEqual(try cash(on: phone), [7, 200])

        // Saved in the game meanwhile instead: both are kept.
        let other = device("other")
        sync(other)
        try other.library.save(world(cash: 900), as: .autosave, at: date(900))
        sync(other)
        try phone.library.save(world(cash: 260), as: .autosave, at: date(950))
        let saved = sync(phone, mode: .keepingDevice)
        XCTAssertEqual(saved.keptBoth.count, 1)
        XCTAssertEqual(try phone.library.load(XCTUnwrap(phone.library.newestAutosave())), try world(cash: 260))
        XCTAssertEqual(try cash(on: phone), [7, 260, 900])
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
        XCTAssertEqual(waiting, SaveSync.Outcome(), "neither taken for deleted, nor half copied")
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
        cloud.versions = ["autosave.json": [try SaveLibrary.encode(world(cash: 75), at: date(30))]]
        let outcome = sync(phone, with: cloud)
        XCTAssertEqual(outcome.keptBoth, ["save-2026-10-02 120030-other.json"])
        XCTAssertTrue(cloud.versions.isEmpty, "then forgotten by iCloud")
        XCTAssertEqual(try cash(on: phone), [60, 75])
        XCTAssertTrue(cloudFiles().contains("save-2026-10-02 120030-other.json"))
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
            XCTAssertNil(CloudSaves.off.footnote(in: language), "nothing is asked of a player without iCloud")
            XCTAssertNotNil(CloudSaves.on.footnote(in: language))
            XCTAssertNotNil(CloudSaves.incomplete.footnote(in: language))
            XCTAssertFalse(CloudSaves.keptTwiceText(1, in: language).isEmpty)
            XCTAssertTrue(CloudSaves.keptTwiceText(3, in: language).contains("3"))
        }
        XCTAssertTrue(CloudSaves.keptTwiceText(1, in: .traditionalChinese).contains("另一台裝置的進度"))
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
        await phone.syncSaves()?.value
        XCTAssertEqual(phone.cloudSaves, .on)
        XCTAssertTrue(cloudFiles().contains("autosave.json"))

        let pad = GameLauncher(library: SaveLibrary(directory: root.appendingPathComponent("pad")), language: .traditionalChinese)
        pad.cloudSaveFolder = { DirectorySaveFolder(directory: cloud) }
        XCTAssertNil(pad.autosave)
        await pad.syncSaves()?.value
        XCTAssertNotNil(pad.autosave, "the list is read again")
        pad.continueGame()
        XCTAssertEqual(try XCTUnwrap(pad.session).world, played)

        // iCloud gone: the saves stay on the device, with nothing said.
        pad.returnToStart()
        pad.cloudSaveFolder = { nil }
        await pad.syncSaves()?.value
        XCTAssertEqual(pad.cloudSaves, .off)
        XCTAssertNil(pad.message)
        XCTAssertNotNil(pad.autosave)
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
    var failsListing = false
    var versions: [String: [Data]] = [:]

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
        return files
    }

    func read(_ name: String) throws -> Data {
        try base.read(name)
    }

    func write(_ data: Data, to name: String) throws {
        if failsWrites { throw Refused() }
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
