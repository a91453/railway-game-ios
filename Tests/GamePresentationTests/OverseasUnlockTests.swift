import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1010: the maps unlock. One map is free, the one of the first
/// new game on a real map; a new game on any other needs the purchase, or
/// the gift of a player who first downloaded a free version (a build before
/// ``OverseasUnlock/firstLockedBuild``).
@MainActor
final class OverseasUnlockTests: XCTestCase {
    // MARK: - Who has the gift

    /// Every build before the first locked one is a gift, the first locked
    /// one and later are not, and a re-run's ".2" does not move it.
    func testABuildBeforeTheLockIsAGift() {
        func gift(_ version: String) -> Bool {
            OverseasUnlock.isFreeVersionPlayer(originalVersion: version, environment: .production, firstLockedBuild: 150)
        }
        XCTAssertTrue(gift("1"))
        XCTAssertTrue(gift("148"))
        XCTAssertTrue(gift("149"))
        XCTAssertTrue(gift("149.2"))
        XCTAssertTrue(gift(" 149 "))
        XCTAssertFalse(gift("150"))
        XCTAssertFalse(gift("150.3"))
        XCTAssertFalse(gift("151"))
        XCTAssertFalse(gift("1203"))
    }

    /// The sandbox (TestFlight) always answers "1.0", and Xcode's testing
    /// says nothing of a first download: neither is a gift, so a tester
    /// sees the purchase.
    func testOnlyTheAppStoresAnswerCounts() {
        XCTAssertFalse(OverseasUnlock.isFreeVersionPlayer(originalVersion: "1.0", environment: .sandbox, firstLockedBuild: 150))
        XCTAssertFalse(OverseasUnlock.isFreeVersionPlayer(originalVersion: "1", environment: .xcode, firstLockedBuild: 150))
        XCTAssertTrue(OverseasUnlock.isFreeVersionPlayer(originalVersion: "1.0", environment: .production, firstLockedBuild: 150))
    }

    /// A version that is not a build number is not a gift.
    func testAVersionThatIsNotANumberIsNoGift() {
        for version in ["", ".", "a148", "abc", "١٢", "-3", "+3"] {
            XCTAssertFalse(OverseasUnlock.isFreeVersionPlayer(originalVersion: version, environment: .production, firstLockedBuild: 150), version)
        }
        XCTAssertEqual(OverseasUnlock.buildNumber("148.2"), 148)
        XCTAssertNil(OverseasUnlock.buildNumber("v148"))
    }

    /// The lock is past every build uploaded so far (147 on 2026-11-26),
    /// so no player of a free version loses a map.
    func testTheLockIsPastTheFreeBuilds() {
        XCTAssertGreaterThan(OverseasUnlock.firstLockedBuild, 147)
    }

    func testTheStateOpensWithEitherWay() {
        XCTAssertFalse(OverseasUnlock.State.locked.isOpen)
        XCTAssertTrue(OverseasUnlock.State(purchased: true).isOpen)
        XCTAssertTrue(OverseasUnlock.State(freeVersionPlayer: true).isOpen)
        XCTAssertTrue(OverseasUnlock.State.open.isOpen)
    }

    // MARK: - The launcher

    private func launcher(in directory: URL) async -> GameLauncher {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.loadRealWorldData {
            RealWorldData.load(overseas: [.hongKong, .rovaniemi], pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        }.value
        return launcher
    }

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OverseasUnlockTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Where no App Store answers (the tests, the headless game, a Debug
    /// build) nothing is sold: no free map is chosen and the maps open as
    /// decision 712 opens them.
    func testNothingIsSoldWithoutAnAppStore() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        XCTAssertNil(launcher.overseasUnlock)
        XCTAssertFalse(launcher.sellsAllMaps)
        XCTAssertFalse(launcher.choosesFreeMap)
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy { !$0.needsPurchase })
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertNil(launcher.freeMap)
    }

    /// The first new game on a real map makes it the free map, kept on the
    /// device; every other map then needs the unlock, Taiwan too, and a
    /// refused one is not chosen. A blank map is always free.
    func testTheFirstNewGameChoosesTheFreeMap() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        XCTAssertTrue(launcher.sellsAllMaps)
        XCTAssertTrue(launcher.choosesFreeMap)
        XCTAssertNil(launcher.taiwanClosed(in: .english), "any map can be the free one")
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy { $0.closed == nil })

        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertEqual(launcher.freeMap, OverseasMap.hongKong.rawValue)
        XCTAssertFalse(launcher.choosesFreeMap)
        let locked = OverseasUnlock.lockedText(in: .english)
        XCTAssertEqual(launcher.overseasMapRows(in: .english), [
            OverseasMapRow(city: .hongKong, closed: nil),
            OverseasMapRow(city: .rovaniemi, closed: locked, needsPurchase: true),
        ])
        XCTAssertEqual(launcher.taiwanClosed(in: .english), locked)
        launcher.message = nil
        XCTAssertFalse(launcher.startOverseasMap(.rovaniemi, wholeMap: true))
        XCTAssertEqual(launcher.message?.text, OverseasUnlock.refusedText(freeMap: "香港", in: .traditionalChinese))
        XCTAssertFalse(launcher.takeMap(AirMap.taiwan.id), "Taiwan is not the free map")
        XCTAssertEqual(launcher.freeMap, OverseasMap.hongKong.rawValue)
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), "the free map again")

        // A blank map is no real map's: free, and chooses nothing.
        launcher.startNewGame()
        XCTAssertNotNil(launcher.session, launcher.message?.text ?? "")

        // Kept on the device.
        let again = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        again.overseasUnlock = .locked
        XCTAssertEqual(again.freeMap, OverseasMap.hongKong.rawValue)
        XCTAssertEqual(again.taiwanClosed(in: .english), locked)
    }

    /// Taiwan as the free map: Hong Kong needs the unlock as well.
    func testTaiwanAsTheFreeMapLocksHongKong() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        XCTAssertTrue(launcher.takeMap(AirMap.taiwan.id))
        XCTAssertEqual(launcher.freeMap, AirMap.taiwan.id)
        XCTAssertNil(launcher.taiwanClosed(in: .english))
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy(\.needsPurchase))
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))
        XCTAssertEqual(launcher.message?.text, OverseasUnlock.refusedText(freeMap: "台灣", in: .traditionalChinese))
        XCTAssertNil(launcher.session)
    }

    /// Bought, every map opens at once, with no flights to wait for
    /// (Hong Kong's would otherwise stay closed after a first map of
    /// Taiwan), and nothing more is chosen.
    func testTheUnlockOpensEveryMapAtOnce() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        XCTAssertTrue(launcher.takeMap(AirMap.taiwan.id))
        launcher.overseasUnlock = OverseasUnlock.State(purchased: true, price: "NT$170")
        XCTAssertTrue(launcher.allMapsOpen)
        XCTAssertFalse(launcher.sellsAllMaps)
        XCTAssertEqual(launcher.overseasMapRows(in: .english), [
            OverseasMapRow(city: .hongKong, closed: nil),
            OverseasMapRow(city: .rovaniemi, closed: nil),
        ])
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertTrue(launcher.startOverseasMap(.rovaniemi), launcher.message?.text ?? "")
    }

    /// A friend's network on a real map: a new game on it is a new game
    /// there (the free map's, or needing the unlock); looking needs
    /// nothing; bought, it starts.
    func testAFriendsNetworkIsANewGameOnItsMap() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        XCTAssertTrue(launcher.takeMap(AirMap.taiwan.id))
        let hongKong = try SaveLibrary.encode(GameWorld.newOverseasGame(try HongKongMapTests.ground()), at: Date(timeIntervalSince1970: 0))

        launcher.receiveNetwork(hongKong)
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .newGame).value
        XCTAssertNil(launcher.session)
        XCTAssertEqual(launcher.message?.text, OverseasUnlock.refusedText(freeMap: "台灣", in: .traditionalChinese))

        launcher.receiveNetwork(hongKong)
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .look).value
        XCTAssertNotNil(launcher.session, "looking needs no unlock")
        XCTAssertTrue(launcher.isLookingAtSharedNetwork)

        launcher.receiveNetwork(try SaveLibrary.encode(DemoWorld.make(in: .traditionalChinese), at: Date(timeIntervalSince1970: 0)))
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .newGame).value
        XCTAssertFalse(launcher.isLookingAtSharedNetwork, "Taiwan's network starts on the free map")

        launcher.overseasUnlock = OverseasUnlock.State(purchased: true)
        launcher.receiveNetwork(hongKong)
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .newGame).value
        XCTAssertEqual(launcher.session?.world.stations, GameWorld.newOverseasGame(try HongKongMapTests.ground()).stations)
        XCTAssertFalse(launcher.isLookingAtSharedNetwork)
    }

    /// Where the unlock is sold, flights open no map: a player whose
    /// flights had opened only Taiwan can still choose Hong Kong free, and
    /// a game counts no flights towards a map.
    func testFlightsOpenNoMapWhereTheUnlockIsSold() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.setAirMapsForScreenshot(AirMap.taiwan.id)
        XCTAssertFalse(launcher.airRoutes.canStart(OverseasMap.hongKong.rawValue), "decision 712 without an App Store")
        launcher.overseasUnlock = .locked
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertEqual(launcher.freeMap, OverseasMap.hongKong.rawValue)
        let session = try XCTUnwrap(launcher.session)
        launcher.checkAirRoutes(of: session)
        XCTAssertTrue(session.airRoutes.routes.isEmpty)
        XCTAssertNil(session.onAirRouteBought)
    }

    /// A friend's network as the first new game makes its map the free one.
    func testAFriendsNetworkCanChooseTheFreeMap() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        launcher.receiveNetwork(try SaveLibrary.encode(GameWorld.newOverseasGame(try HongKongMapTests.ground()), at: Date(timeIntervalSince1970: 0)))
        await launcher.play(try XCTUnwrap(launcher.receivedNetwork), as: .newGame).value
        XCTAssertNotNil(launcher.session, launcher.message?.text ?? "")
        XCTAssertEqual(launcher.freeMap, OverseasMap.hongKong.rawValue)
    }

    /// A reinstall loses the device's preferences, but the saves come back
    /// from iCloud: the oldest real-map save names the free map again, so
    /// the player cannot choose a second one.
    func testTheSavesNameTheFreeMapAfterAReinstall() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        try library.save(GameWorld.newOverseasGame(try HongKongMapTests.ground()), as: .manual, at: Date(timeIntervalSince1970: 100))
        try library.save(DemoWorld.make(in: .traditionalChinese), as: .manual, at: Date(timeIntervalSince1970: 200))

        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        XCTAssertTrue(launcher.choosesFreeMap)
        launcher.settleFreeMap()
        XCTAssertEqual(launcher.freeMap, OverseasMap.hongKong.rawValue, "the oldest real-map save")
        XCTAssertFalse(launcher.takeMap(AirMap.taiwan.id))
        XCTAssertEqual(launcher.freeMap, OverseasMap.hongKong.rawValue)
    }

    /// Without an App Store, or once bought, the saves choose nothing.
    func testTheSavesChooseNothingWhereNothingIsSold() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        try SaveLibrary(directory: directory).save(GameWorld.newOverseasGame(try HongKongMapTests.ground()), as: .manual, at: Date(timeIntervalSince1970: 100))
        let launcher = await launcher(in: directory)
        launcher.settleFreeMap()
        XCTAssertNil(launcher.freeMap)
        launcher.overseasUnlock = OverseasUnlock.State(purchased: true)
        launcher.settleFreeMap()
        XCTAssertNil(launcher.freeMap)
    }

    /// The free map kept off the device (the app's keychain) is taken back
    /// once, and only a map's name; it never replaces a chosen one.
    func testAKeptFreeMapIsTakenBack() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        var told: [String] = []
        launcher.onFreeMapChosen = { told.append($0) }
        launcher.adoptFreeMap("nowhere")
        XCTAssertNil(launcher.freeMap)
        launcher.adoptFreeMap(AirMap.taiwan.id)
        XCTAssertEqual(launcher.freeMap, AirMap.taiwan.id)
        launcher.adoptFreeMap(OverseasMap.hongKong.rawValue)
        XCTAssertEqual(launcher.freeMap, AirMap.taiwan.id)
        XCTAssertTrue(told.isEmpty, "taken back, not chosen")
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))

        let fresh = await self.launcher(in: folder())
        fresh.overseasUnlock = .locked
        fresh.onFreeMapChosen = { told.append($0) }
        XCTAssertTrue(fresh.startOverseasMap(.hongKong), fresh.message?.text ?? "")
        XCTAssertEqual(told, [OverseasMap.hongKong.rawValue], "a choice is told, to be kept")
    }

    /// The gift opens the maps as the purchase does.
    func testTheGiftOpensTheMaps() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = OverseasUnlock.State(freeVersionPlayer: true)
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy { $0.closed == nil })
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertTrue(launcher.startOverseasMap(.rovaniemi), launcher.message?.text ?? "")
        XCTAssertNil(launcher.freeMap)
    }

    /// The demo mode (a test build's) opens every map, as it opens every
    /// lesson.
    func testTheDemoModeOpensTheMaps() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        launcher.isDemoMode = true
        XCTAssertTrue(launcher.allMapsOpen)
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy { !$0.needsPurchase })
    }

    // MARK: - Text

    func testTheTextNamesThePrice() {
        XCTAssertEqual(OverseasUnlock.buyTitle(price: "NT$170", in: .traditionalChinese), "購買 · NT$170")
        XCTAssertEqual(OverseasUnlock.buyTitle(price: nil, in: .english), "Buy")
        XCTAssertNil(OverseasUnlock.Outcome.cancelled.text(in: .english))
        XCTAssertEqual(OverseasUnlock.openText(OverseasUnlock.State(purchased: true), in: .traditionalChinese), "已解鎖，謝謝支持！")
        XCTAssertEqual(OverseasUnlock.openText(OverseasUnlock.State(freeVersionPlayer: true), in: .english), "Unlocked as a gift: you downloaded the game while it was free.")
        XCTAssertEqual(OverseasUnlock.title(in: .traditionalChinese), "全地圖解鎖")
        XCTAssertEqual(OverseasUnlock.refusedText(freeMap: "香港", in: .traditionalChinese), "你的免費地區是香港。在其他地區開新局，需要「全地圖解鎖」。")
    }
}
