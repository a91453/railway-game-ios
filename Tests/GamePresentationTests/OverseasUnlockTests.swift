import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1010: the overseas maps unlock. Taiwan is free; a new game on
/// a map outside it needs the purchase, or the gift of a player who first
/// downloaded a free version (a build before ``OverseasUnlock/firstLockedBuild``).
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

    /// Without the unlock every overseas row is closed with the way to buy
    /// it, a new game there is refused and remembers no first map, and
    /// Taiwan still starts; bought, the rows are as before.
    func testLockedMapsDoNotStartAndTaiwanDoes() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        XCTAssertTrue(launcher.overseasMapsOpen, "open where there is no App Store")
        launcher.overseasUnlock = .locked
        XCTAssertFalse(launcher.overseasMapsOpen)
        let locked = OverseasUnlock.lockedText(in: .english)
        XCTAssertEqual(launcher.overseasMapRows(in: .english), [
            OverseasMapRow(city: .hongKong, closed: locked, needsPurchase: true),
            OverseasMapRow(city: .rovaniemi, closed: locked, needsPurchase: true),
        ])
        XCTAssertEqual(launcher.overseasStartRows(for: launcher.overseasMapRows(in: .english)[0], in: .english).count, 1)
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))
        XCTAssertEqual(launcher.message?.text, OverseasUnlock.refusedText(in: .traditionalChinese))
        XCTAssertFalse(launcher.startOverseasMap(.rovaniemi, wholeMap: true))
        XCTAssertNil(launcher.session)
        XCTAssertEqual(launcher.preferences.airRoutesOpened ?? [], [], "a refused map is not the first one")

        launcher.overseasUnlock = OverseasUnlock.State(purchased: true, price: "NT$170")
        XCTAssertEqual(launcher.overseasMapRows(in: .english), [
            OverseasMapRow(city: .hongKong, closed: nil),
            OverseasMapRow(city: .rovaniemi, closed: nil),
        ])
        XCTAssertTrue(launcher.startOverseasMap(.rovaniemi), launcher.message?.text ?? "")
    }

    /// The gift opens the maps as the purchase does.
    func testTheGiftOpensTheMaps() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = OverseasUnlock.State(freeVersionPlayer: true)
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy { $0.closed == nil })
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
    }

    /// The demo mode (a test build's) opens every map, as it opens every
    /// lesson.
    func testTheDemoModeOpensTheMaps() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = await launcher(in: directory)
        launcher.overseasUnlock = .locked
        launcher.isDemoMode = true
        XCTAssertTrue(launcher.overseasMapsOpen)
        XCTAssertTrue(launcher.overseasMapRows(in: .english).allSatisfy { !$0.needsPurchase })
    }

    // MARK: - Text

    func testTheTextNamesThePrice() {
        XCTAssertEqual(OverseasUnlock.buyTitle(price: "NT$170", in: .traditionalChinese), "購買 · NT$170")
        XCTAssertEqual(OverseasUnlock.buyTitle(price: nil, in: .english), "Buy")
        XCTAssertNil(OverseasUnlock.Outcome.cancelled.text(in: .english))
        XCTAssertEqual(OverseasUnlock.openText(OverseasUnlock.State(purchased: true), in: .traditionalChinese), "已解鎖，謝謝支持！")
        XCTAssertEqual(OverseasUnlock.openText(OverseasUnlock.State(freeVersionPlayer: true), in: .english), "Unlocked as a gift: you downloaded the game while it was free.")
    }
}
