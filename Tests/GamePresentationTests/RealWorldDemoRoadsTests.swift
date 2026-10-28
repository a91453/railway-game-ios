import GameCore
import XCTest

@testable import GamePresentation

/// The real-world demo reads its roads off the main actor, as the High
/// Speed Rail and Yilan Line demos do, and opens the same game.
final class RealWorldDemoRoadsTests: XCTestCase {
    @MainActor
    func testTheDemoOpensWithItsRoadsReadAndTheSameWorldAsReadingThemWhenItBegins() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RealWorldDemoRoadsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let railways = try BundledRealData.railways()
        let baseMap = try BaseMapTiles(
            data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped)
        )
        try XCTSkipIf(HighSpeedDemoTests.population == nil, "The population file is not here.")
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.population = HighSpeedDemoTests.population
        launcher.places = HighSpeedDemoTests.places
        launcher.baseMap = baseMap
        let task = launcher.openRealWorldDemo(railways: railways)
        XCTAssertNil(launcher.openRealWorldDemo(railways: railways), "one build at a time")
        XCTAssertTrue(launcher.isOpeningADemo)
        XCTAssertNil(launcher.session, "still on the start screen while the roads are read")
        await task?.value
        XCTAssertFalse(launcher.isOpeningADemo)
        let opened = try XCTUnwrap(launcher.session)
        let start = try XCTUnwrap(opened.commandLog.start)
        XCTAssertFalse(try XCTUnwrap(start.roads?.readBlocks).isEmpty, "the game begins with its roads read")

        // The world as reading them in ``begin`` made it.
        let built = RealWorldDemo.make(
            in: .english, railways: railways, land: launcher.land(at: RealWorldDemo.anchor), water: launcher.water(at: RealWorldDemo.anchor),
            steep: launcher.steep(at: RealWorldDemo.anchor), heights: nil
        )
        let reference = GameSession(world: built, language: .english)
        reference.baseMap = baseMap
        reference.population = launcher.population
        reference.places = launcher.places
        reference.railways = railways
        reference.readLandRoundStations(roads: nil)
        XCTAssertEqual(opened.world.roads, reference.world.roads)
        XCTAssertEqual(opened.world.stations, reference.world.stations)
    }
}
