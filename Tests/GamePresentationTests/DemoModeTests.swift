import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 351: the demo mode. Only a test build has it,
/// behind five taps on the version row; while on, every lesson is open, a
/// new game has unlimited funds and the whole map, and its games count
/// nothing, as a demo.
@MainActor
final class DemoModeTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DemoModeTests-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The App Store's build has none, whatever the switch says.
    func testOnlyATestBuildsSwitchTurnsItOn() {
        XCTAssertTrue(DemoMode.isOn(testBuild: true, switchOn: true))
        XCTAssertFalse(DemoMode.isOn(testBuild: true, switchOn: false))
        XCTAssertFalse(DemoMode.isOn(testBuild: false, switchOn: true))
    }

    /// Five taps in a row show the switch; a pause starts the count again.
    func testFiveTapsInARowShowTheSwitch() {
        let start = Date(timeIntervalSince1970: 0)
        var reveal = DemoMode.Reveal()
        for second in 0..<4 {
            XCTAssertFalse(reveal.tap(at: start + Double(second)))
        }
        XCTAssertFalse(reveal.tap(at: start + 10), "a pause starts again")
        XCTAssertEqual(reveal.taps, 1)
        for tap in 1..<4 {
            XCTAssertFalse(reveal.tap(at: start + 10 + Double(tap) * 0.5))
        }
        XCTAssertTrue(reveal.tap(at: start + 12.5), "the fifth tap in a row")
        XCTAssertTrue(reveal.isRevealed)
        XCTAssertFalse(reveal.tap(at: start + 13), "shown once")
        XCTAssertTrue(reveal.isRevealed)
    }

    func testEveryLessonIsOpen() {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertEqual(Lesson.all.map(launcher.isOpen), [true] + Array(repeating: false, count: Lesson.all.count - 1))
        launcher.isDemoMode = true
        XCTAssertTrue(Lesson.all.allSatisfy(launcher.isOpen))
        XCTAssertEqual(launcher.lessonStarTotal, 0, "nothing is passed")
    }

    /// A new blank map: unlimited funds, the whole map, and a demo. Off
    /// again, the next new game is as ever.
    func testANewGameHasUnlimitedFundsAndTheWholeMap() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.isDemoMode = true
        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session)
        XCTAssertTrue(session.world.economy.unlimitedFunds)
        XCTAssertNil(session.world.mapExpansion, "nothing to buy")
        XCTAssertTrue(session.news.isDemo)
        XCTAssertEqual(session.world.accounts.mode, .management, "fares and costs as ever")

        launcher.isDemoMode = false
        launcher.startNewGame()
        let normal = try XCTUnwrap(launcher.session)
        XCTAssertFalse(normal.world.economy.unlimitedFunds)
        XCTAssertNotNil(normal.world.mapExpansion)
        XCTAssertFalse(normal.news.isDemo)

        launcher.isDemoMode = true
        launcher.startWholeTaiwan()
        XCTAssertTrue(try XCTUnwrap(launcher.session).world.economy.unlimitedFunds)
    }

    /// A place of Taiwan: the island-wide world of a game bought tile by
    /// tile, with no tile to buy, its land read in as it is needed.
    func testARealPlaceIsTheWholeIslandWithNoTileToBuy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        let data = GameLauncher.NewWorldData(population: population, places: nil, water: nil, coverage: nil, heights: nil)
        let taipei = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219))
        let expansion = try XCTUnwrap(RealWorldExpansion(around: taipei))
        var options = NewGameOptions()
        options.seed = 7

        let normal = GameLauncher.newWorld(at: taipei, options: options, data: data)
        let demo = GameLauncher.newWorld(at: taipei, options: options, data: data, demo: true)
        XCTAssertNotNil(normal.mapExpansion)
        XCTAssertNil(demo.mapExpansion)
        XCTAssertEqual(demo.bounds, normal.bounds)
        XCTAssertEqual(demo.bounds, expansion.bounds)
        XCTAssertEqual(demo.geoAnchor, normal.geoAnchor)
        XCTAssertEqual(demo.landBlocks, [], "read in round the stations")
        XCTAssertTrue(demo.economy.unlimitedFunds)
        XCTAssertFalse(normal.economy.unlimitedFunds)
    }

    /// A lesson started in the demo mode is a demo: its stars and
    /// achievements are not kept, nor are its station stamps.
    func testItsGamesCountNothing() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.isDemoMode = true
        launcher.startLesson(Lesson.all[4])
        let session = try XCTUnwrap(launcher.session)
        XCTAssertEqual(session.lesson?.number, 5)
        XCTAssertTrue(session.news.isDemo)
        XCTAssertFalse(session.world.economy.unlimitedFunds, "a lesson plays as made")

        // Passed: as a demo, nothing is kept.
        var world = session.world
        world.scenario?.outcome = .completed(day: 1, rating: .gold)
        let passed = GameSession(world: world, language: .english)
        passed.news.isDemo = true
        launcher.recordResult(of: passed)
        XCTAssertEqual(launcher.stars(of: Lesson.all[4]), 0, "no stars kept")
        XCTAssertTrue(launcher.records.best.isEmpty)
        launcher.checkAchievements(of: passed)
        XCTAssertEqual(launcher.achievements.count, 0)
        launcher.checkStationStamps(of: passed)
        XCTAssertEqual(launcher.stationStamps.count, 0)

        // The same game outside the demo mode keeps its stars.
        passed.news.isDemo = false
        launcher.recordResult(of: passed)
        XCTAssertEqual(launcher.stars(of: Lesson.all[4]), 3)
    }
}
