import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 409: a network a friend sent, read as untrusted input, opened
/// as a new game with money of the player's own or only looked at, and
/// never written over a save of the player's.
final class SharedNetworkTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SharedNetworkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_791_000_000 + seconds)
    }

    /// The demo's network, run for a while, with a loan and unlimited
    /// funds: a sender's game with money of its own.
    private func sendersWorld() throws -> GameWorld {
        var world = DemoWorld.make(in: .english)
        try world.borrow(Money(CompanyAccounts.loanStep.amount * 3))
        world.setUnlimitedFunds(true)
        // Past the first hour, so the ledger has its rows.
        try world.advance(ticks: 3_700)
        return world
    }

    /// The player's own game: a blank map with a loan, quick to make.
    private func ownWorld() throws -> GameWorld {
        var world = GameWorld.newGame()
        try world.borrow(CompanyAccounts.loanStep)
        try world.advance(ticks: 60)
        return world
    }

    // MARK: - The file

    func testTheExportIsTheGamesOwnTypeAndCarriesTheCompanyName() throws {
        let world = DemoWorld.make(in: .english)
        let url = try SaveLibrary.exportFile(for: world, company: "  台北\n捷運  ", at: date(0))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, SharedNetwork.fileExtension)
        let network = try SharedNetwork(contentsOf: url)
        XCTAssertEqual(network.world, world)
        XCTAssertEqual(network.company, "台北 捷運")
        XCTAssertEqual(network.postcard(in: .english).title, "台北 捷運")
        // The file is a save as before: the start screen's import reads it.
        XCTAssertEqual(try SaveLibrary.decode(Data(contentsOf: url)), world)
    }

    func testAFileWithoutACompanyNameIsAFriendsNetwork() throws {
        let data = try SaveLibrary.encode(DemoWorld.make(in: .english), at: date(0))
        let network = try SharedNetwork(data: data)
        XCTAssertNil(network.company)
        XCTAssertEqual(network.postcard(in: .english).title, "Friend's Network")
        XCTAssertEqual(network.postcard(in: .traditionalChinese).title, "朋友的路網")
    }

    func testAnUntrustedCompanyNameIsCleanedAndCut() {
        XCTAssertEqual(SharedNetwork.cleanCompany("\u{202E}abc\u{0007}"), "abc", "no right-to-left override or control character")
        XCTAssertEqual(SharedNetwork.cleanCompany(String(repeating: "鐵", count: 100))?.count, NetworkPostcard.nameLimit)
        XCTAssertNil(SharedNetwork.cleanCompany(" \n\u{200B} "))
    }

    func testAFileTooLargeIsRefusedBeforeItIsRead() throws {
        let url = directory.appendingPathComponent("huge.\(SharedNetwork.fileExtension)")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SharedNetwork.maximumBytes) + 1)
        try handle.close()
        XCTAssertThrowsError(try SharedNetwork(contentsOf: url)) { XCTAssertEqual($0 as? SaveError, .tooLarge) }
        XCTAssertThrowsError(try SharedNetwork(data: Data(count: SharedNetwork.maximumBytes + 1))) {
            XCTAssertEqual($0 as? SaveError, .tooLarge)
        }
    }

    func testFilesThatAreNotSavesAreRefusedWithTheirReason() throws {
        XCTAssertThrowsError(try SharedNetwork(data: Data("not json".utf8))) { XCTAssertEqual($0 as? SaveError, .notASave) }
        XCTAssertThrowsError(try SharedNetwork(data: Data(#"{"app":"Other"}"#.utf8))) { XCTAssertEqual($0 as? SaveError, .notASave) }
        XCTAssertThrowsError(try SharedNetwork(data: Data())) { XCTAssertEqual($0 as? SaveError, .notASave) }

        var file = try XCTUnwrap(JSONSerialization.jsonObject(with: SaveLibrary.encode(DemoWorld.make(in: .english), at: date(0))) as? [String: Any])
        var game = try XCTUnwrap(file["game"] as? [String: Any])
        game["saveVersion"] = SavedGame.currentVersion + 1
        file["game"] = game
        XCTAssertThrowsError(try SharedNetwork(data: JSONSerialization.data(withJSONObject: file))) {
            XCTAssertEqual($0 as? SaveError, .newerVersion(SavedGame.currentVersion + 1))
        }
        game["saveVersion"] = SavedGame.currentVersion
        game["world"] = ["stations": "spoiled"]
        file["game"] = game
        XCTAssertThrowsError(try SharedNetwork(data: JSONSerialization.data(withJSONObject: file))) {
            XCTAssertEqual($0 as? SaveError, .damaged)
        }
        XCTAssertThrowsError(try SharedNetwork(contentsOf: directory.appendingPathComponent("missing.alongtheline"))) {
            XCTAssertEqual($0 as? SaveError, .fileSystem)
        }
    }

    // MARK: - A new game from the network

    func testANewGameKeepsTheNetworkAndStartsTheMoneyAgain() throws {
        let sent = try sendersWorld()
        XCTAssertGreaterThan(sent.accounts.loan, .zero)
        XCTAssertFalse(sent.accounts.entries.isEmpty)
        XCTAssertTrue(sent.economy.unlimitedFunds)

        let world = try SharedNetwork(data: SaveLibrary.encode(sent, at: date(0))).newGameWorld()
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance)
        XCTAssertFalse(world.economy.unlimitedFunds)
        XCTAssertEqual(world.accounts.loan, .zero)
        XCTAssertEqual(world.accounts.entries, [])
        XCTAssertEqual(world.accounts.days, [])
        XCTAssertEqual(world.accounts.years, [])
        XCTAssertEqual(world.accounts.capitalDays, [])
        XCTAssertEqual(world.accounts.pending, .empty)
        XCTAssertNil(world.scenario)
        // The friend's lines, stations, trains and timetables, and the rules.
        XCTAssertEqual(world.stations, sent.stations)
        XCTAssertEqual(world.lines, sent.lines)
        XCTAssertEqual(world.trains, sent.trains)
        XCTAssertEqual(world.network, sent.network)
        XCTAssertEqual(world.clock.now, sent.clock.now)
        XCTAssertEqual(world.accounts.mode, sent.accounts.mode)
        XCTAssertEqual(world.accounts.fareRules, sent.accounts.fareRules)
        XCTAssertEqual(world.accounts.assets, sent.accounts.assets)
        XCTAssertEqual(world.economy.costs, sent.economy.costs)

        // It plays on and saves like any game.
        var played = world
        try played.advance(ticks: 3_600)
        XCTAssertEqual(try SaveLibrary.decode(SaveLibrary.encode(played, at: date(0))), played)
    }

    @MainActor
    func testANewGameFromAChallengeLeavesItsGoalsBehind() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startChallenge(Challenge.threeTowns)
        let sent = try XCTUnwrap(launcher.session?.world)
        XCTAssertNotNil(sent.scenario)
        let world = try SharedNetwork(data: SaveLibrary.encode(sent, at: date(0))).newGameWorld()
        XCTAssertNil(world.scenario)
        XCTAssertEqual(world.stations, sent.stations)
    }

    // MARK: - The launcher

    @MainActor
    func testOpeningANewGameKeepsThePlayersGameAsASave() async throws {
        let library = SaveLibrary(directory: directory)
        let own = try ownWorld()
        try library.save(own, as: .autosave, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.session?.world, own)

        launcher.receiveNetwork(try SaveLibrary.encode(DemoWorld.make(in: .english), at: date(10)))
        let network = try XCTUnwrap(launcher.receivedNetwork)
        let opening = launcher.play(network, as: .newGame)
        XCTAssertNil(launcher.receivedNetwork)
        XCTAssertTrue(launcher.isReadingReceivedNetwork, "its money is worked out off the main actor")
        await opening.value
        XCTAssertFalse(launcher.isReadingReceivedNetwork)
        let session = try XCTUnwrap(launcher.session)
        XCTAssertEqual(session.world.economy.balance, GameWorld.startingBalance)
        XCTAssertEqual(session.world.stations, DemoWorld.make(in: .english).stations)
        XCTAssertTrue(session.news.isDemo, "a friend's network unlocks no achievements")
        XCTAssertFalse(launcher.isLookingAtSharedNetwork)

        // The player's own game was kept as a save of theirs.
        let kept = library.entries().filter { $0.kind == .manual }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try library.load(kept[0]), own)

        // The new game saves as any game does.
        XCTAssertTrue(launcher.autosaveCurrentGame())
        let autosave = try XCTUnwrap(library.entries().first { $0.kind == .autosave })
        XCTAssertEqual(try library.load(autosave).economy.balance, session.worldToSave.economy.balance)
    }

    @MainActor
    func testLookingWritesNothingAndTheAutosaveStaysThePlayersGame() async throws {
        let library = SaveLibrary(directory: directory)
        let own = try ownWorld()
        try library.save(own, as: .autosave, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.continueGame()?.value

        let sent = DemoWorld.make(in: .english)
        launcher.receiveNetwork(try SaveLibrary.encode(sent, at: date(10)))
        // The player's game is autosaved as it was, then nothing more.
        launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look)
        await launcher.savesWritten()
        let before = try directoryContents()
        XCTAssertTrue(launcher.isLookingAtSharedNetwork)
        XCTAssertEqual(launcher.session?.world, sent, "looked at as the friend left it")
        XCTAssertEqual(launcher.session?.news.isDemo, true)

        // Every way the game saves does nothing.
        XCTAssertTrue(launcher.autosaveCurrentGame(), "so going back to the start is not held up")
        XCTAssertNil(launcher.autosaveInBackground())
        XCTAssertNil(launcher.autosaveSlotInBackground())
        await launcher.saveCurrentGame().value
        XCTAssertEqual(launcher.session?.message?.kind, .failure)
        await launcher.savesWritten()
        XCTAssertEqual(try directoryContents(), before)
        let autosave = try XCTUnwrap(library.entries().first { $0.kind == .autosave })
        XCTAssertEqual(try library.load(autosave), own)

        launcher.returnToStart()
        XCTAssertNil(launcher.session)
        XCTAssertFalse(launcher.isLookingAtSharedNetwork)
        await launcher.savesWritten()
        XCTAssertEqual(try library.load(XCTUnwrap(library.entries().first { $0.kind == .autosave })), own)

        // Continue goes on with the player's own game.
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.session?.world, own)
        XCTAssertTrue(launcher.autosaveCurrentGame())
    }

    @MainActor
    func testGoingBackToAnAutosaveWhileLookingDoesNotSaveTheLookedAtNetwork() async throws {
        let library = SaveLibrary(directory: directory)
        let older = try ownWorld()
        var newer = older
        try newer.advance(ticks: 60)
        try library.saveAutosaveSlot(older, at: date(0))
        try library.saveAutosaveSlot(newer, at: date(900))
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.session?.world, newer)

        let sent = DemoWorld.make(in: .english)
        launcher.receiveNetwork(try SaveLibrary.encode(sent, at: date(1_000)))
        launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look)
        await launcher.savesWritten()
        let back = try XCTUnwrap(library.entries().first { $0.kind == .autosave && (try? library.load($0)) == older })

        // The game menu's "go back to an earlier autosave".
        await launcher.load(back, at: date(1_100))?.value
        await launcher.savesWritten()
        XCTAssertEqual(launcher.session?.world, older)
        XCTAssertFalse(launcher.isLookingAtSharedNetwork)
        let saved = try library.entries().map { try library.load($0) }
        XCTAssertFalse(saved.contains(sent), "the network looked at was saved as the player's")
        XCTAssertTrue(saved.contains(newer), "the player's newest game was pushed out")
    }

    @MainActor
    func testASaveSharedWhileLookingCarriesTheFriendsNameNotThePlayers() async throws {
        let library = SaveLibrary(directory: directory)
        try library.save(try ownWorld(), as: .autosave, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.continueGame()?.value
        XCTAssertEqual(launcher.companyNameToShare(own: "My Railway"), "My Railway")

        let world = DemoWorld.make(in: .english)
        launcher.receiveNetwork(try SaveLibrary.encode(world, company: "Friend Lines", at: date(10)))
        launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look)
        XCTAssertEqual(launcher.companyNameToShare(own: "My Railway"), "Friend Lines")
        launcher.receiveNetwork(try SaveLibrary.encode(world, at: date(20)))
        launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look)
        XCTAssertNil(launcher.companyNameToShare(own: "My Railway"), "a file that names none")

        // A new game from it is the player's own company.
        launcher.receiveNetwork(try SaveLibrary.encode(world, company: "Friend Lines", at: date(30)))
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .newGame).value
        XCTAssertEqual(launcher.companyNameToShare(own: "My Railway"), "My Railway")
        launcher.receiveNetwork(try SaveLibrary.encode(world, at: date(40)))
        launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look)
        launcher.returnToStart()
        XCTAssertEqual(launcher.companyNameToShare(own: "My Railway"), "My Railway")
    }

    @MainActor
    func testANewGameWhileLookingDoesNotSaveTheLookedAtNetwork() async throws {
        let library = SaveLibrary(directory: directory)
        let own = try ownWorld()
        try library.save(own, as: .autosave, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)
        await launcher.continueGame()?.value
        let data = try SaveLibrary.encode(DemoWorld.make(in: .english), at: date(10))
        launcher.receiveNetwork(data)
        launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look)
        launcher.receiveNetwork(data)
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .newGame).value
        XCTAssertFalse(launcher.isLookingAtSharedNetwork)
        // The player's own autosave, not the network looked at, was kept.
        let kept = library.entries().filter { $0.kind == .manual }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try library.load(kept[0]), own)
    }

    @MainActor
    func testAFileThatCannotBeReadChangesNothing() async throws {
        let library = SaveLibrary(directory: directory)
        let own = try ownWorld()
        try library.save(own, as: .autosave, at: date(0))
        let launcher = GameLauncher(library: library, language: .english)

        // On the start screen.
        launcher.receiveNetwork(Data("{".utf8))
        XCTAssertNil(launcher.receivedNetwork)
        XCTAssertEqual(launcher.message?.kind, .failure)
        XCTAssertNil(launcher.session)

        // In a game, read off the main actor from a file.
        await launcher.continueGame()?.value
        let url = directory.appendingPathComponent("bad.\(SharedNetwork.fileExtension)")
        try Data("not a save".utf8).write(to: url)
        await launcher.receiveNetwork(at: url).value
        XCTAssertFalse(launcher.isReadingReceivedNetwork)
        XCTAssertNil(launcher.receivedNetwork)
        XCTAssertEqual(launcher.session?.message?.text, SaveError.notASave.playerMessage(in: .english))
        XCTAssertEqual(launcher.session?.world, own)
        XCTAssertEqual(try library.load(XCTUnwrap(library.entries().first { $0.kind == .autosave })), own)
    }

    @MainActor
    func testAFileIsReadOffTheMainActorAndOffered() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let url = try SaveLibrary.exportFile(for: DemoWorld.make(in: .english), company: "Friend", at: date(0))
        defer { try? FileManager.default.removeItem(at: url) }
        let reading = launcher.receiveNetwork(at: url)
        XCTAssertTrue(launcher.isReadingReceivedNetwork)
        await reading.value
        XCTAssertEqual(launcher.receivedNetwork?.company, "Friend")
        launcher.dismissReceivedNetwork()
        XCTAssertNil(launcher.receivedNetwork)
        XCTAssertNil(launcher.session, "putting it away opens nothing")
    }

    func testTheChoicesSayWhatTheyDoInBothLanguages() {
        XCTAssertEqual(SharedNetworkChoice.allCases, [.newGame, .look])
        for choice in SharedNetworkChoice.allCases {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(choice.title(in: language).isEmpty)
                XCTAssertFalse(choice.detail(in: language).isEmpty)
            }
        }
        XCTAssertEqual(SharedNetworkChoice.newGame.title(in: .traditionalChinese), "從這張路網開新的一局")
        XCTAssertEqual(SharedNetworkChoice.look.title(in: .traditionalChinese), "只看")
    }

    /// Every file in the save folder and its bytes.
    private func directoryContents() throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            contents[name] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        return contents
    }
}
