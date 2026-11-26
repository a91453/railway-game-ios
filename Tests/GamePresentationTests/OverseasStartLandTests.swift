import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 992: a new game on Hong Kong's map starts with the four tiles
/// with the most people and buys the rest; Hong Kong's and Japan's maps can
/// be opened whole instead, counting no achievements; Rovaniemi stays
/// whole and counted; an old Hong Kong game stays whole and counted.
///
/// SPLIT-HOTSPOTS-2: each map's tests are in a file of its own,
/// ``OverseasStartLandHongKongTests``, ``OverseasStartLandJapanTests`` and
/// ``OverseasStartLandRovaniemiTests``; what every map shares stays here.
@MainActor
final class OverseasStartLandTests: XCTestCase {
    // MARK: - Achievements

    /// A map opened whole counts no achievements, and their list says so;
    /// the same network on a map bought tile by tile counts them.
    func testAWholeMapCountsNoAchievements() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OverseasStartLand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var counted = try newGameLine(through: [towns[0], towns[1]])
        try counted.advance(ticks: 2 * 1_440)
        var whole = counted
        try whole.openWholeMap()
        launcher.checkAchievements(of: GameSession(world: whole, language: .english))
        XCTAssertEqual(launcher.achievements.count, 0, "a whole map earns nothing")
        launcher.checkAchievements(of: GameSession(world: counted, language: .english))
        XCTAssertTrue(launcher.achievements.unlocked.keys.contains("firstFare"))

        XCTAssertEqual(
            GameMenuLayout.achievementsNote(unlimitedFunds: false, wholeMap: true, in: .traditionalChinese), "整張全開的地圖不計成就。"
        )
        XCTAssertNil(GameMenuLayout.achievementsNote(unlimitedFunds: false, wholeMap: false, in: .english))
    }
}
