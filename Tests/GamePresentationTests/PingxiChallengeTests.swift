import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 90: the Pingxi Line challenge on the real-world demo's map, its
/// goals and its Sky Lantern Festival at Shifen and Pingxi.
final class PingxiChallengeTests: XCTestCase {
    private static func bundledRailways() throws -> RealRailways {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        return try RealRailways(lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"))
    }

    /// Built once: building the demo takes seconds in a debug build.
    private static let built: Result<GameWorld, Error> = Result {
        PingxiChallenge.make(in: .traditionalChinese, railways: try bundledRailways())
    }

    func testTheChallengeIsTheDemosLinesWithItsGoalsAndFestival() throws {
        let world = try Self.built.get()
        let state = try XCTUnwrap(world.scenario)
        XCTAssertEqual(state.scenario.id, "history.pingxi")
        XCTAssertEqual(state.scenario.goals, [.dailyRiders(PingxiChallenge.ridersTarget), .annualNetProfit(PingxiChallenge.profitTarget)])
        XCTAssertEqual(world.lines.map(\.name), ["平溪線", "宜蘭線", "深澳線"])
        let festival = state.scenario.events.map { world.station(id: $0.station)?.name }
        XCTAssertEqual(festival, ["十分", "平溪"])
        // When and how the festival is announced and runs is GameCore's
        // (`GoalsTests.testAFestivalComesBackOnItsDayEveryYear`): playing
        // the demo 38 days to see it takes too long in a debug build.
        XCTAssertTrue(state.scenario.events.allSatisfy { $0.dayOfYear == 45 && $0.days == 3 && $0.boost == 1_500 && $0.notice == 7 })
        XCTAssertEqual(world.scenarioTitle(in: .traditionalChinese), "平溪線：天燈之鄉")
        XCTAssertEqual(Challenge.named("history.pingxi")?.map, .pingxi)
        XCTAssertTrue(Challenge.pingxi.story(in: .traditionalChinese).contains("1921"))
        XCTAssertEqual(PingxiChallenge.festivalText(in: .traditionalChinese), "天燈節：每年第 46 天起 3 天，十分與平溪湧入人潮")
        // It saves and loads as it is.
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    @MainActor
    func testTheLauncherWaitsForTheRealRailways() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Pingxi-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        launcher.startChallenge(Challenge.pingxi)
        XCTAssertNil(launcher.session)
        XCTAssertEqual(launcher.message?.text, "實景資料還沒準備好。")
        launcher.railways = try Self.bundledRailways()
        launcher.startChallenge(Challenge.pingxi)
        XCTAssertEqual(launcher.session?.world.scenario?.scenario.id, "history.pingxi")
    }
}
