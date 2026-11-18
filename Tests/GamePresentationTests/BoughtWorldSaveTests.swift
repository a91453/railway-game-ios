import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 878 (TICK-REAL): the games a tick is timed in, written as
/// saves. The tick's earlier measurements (decision 703, TICK-L1, TICK-2)
/// were of maps made up for them; a player's heavy game is a real map with
/// every line on sale bought, which takes minutes to lay in a debug build
/// of GamePresentation. So each is laid once here and saved, and
/// `SavedWorldTickReportTests` (GameCoreTests, which builds in a minute
/// after a change to GameCore) plays the save. Run on request:
///
///     BOUGHT_WORLDS=/tmp/worlds swift test --skip-build --filter BoughtWorldSaveTests
///
/// - `BOUGHT_WORLDS`: the directory the saves are written to
///   (`<name>.json`).
/// - `BOUGHT_WORLDS_ONLY=<name>`: one of them (`hk-all-simple`,
///   `hk-all-realistic`, `taiwan-all-simple`, `taiwan-all-realistic`,
///   `rovaniemi-both-simple`, `rovaniemi-both-realistic`).
///
/// Each is the map as the launcher starts it, with the map's people, and
/// every line on sale bought as it is sold (decision 862: the lines
/// sharing a station in one purchase), in the order the game lists them.
@MainActor
final class BoughtWorldSaveTests: XCTestCase {
    private static let rules: [(String, NewGameRules)] = [("simple", .simple), ("realistic", .realistic)]

    /// Buys every line on sale in `session` as it is sold, and says which.
    static func buyEverything(in session: GameSession, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        var bought: [String] = []
        var refused: Set<String> = []
        while let bundle = session.realLineBundles.first(where: { !refused.contains($0.lines[0].id) }) {
            let ids = bundle.lines.map(\.id)
            let offer = session.realLineBundleOffer(for: bundle)
            if session.acquireRealLines(offer) {
                bought += ids
            } else {
                refused.insert(ids[0])
                XCTFail("\(ids) not bought: \(offer.problemText(in: .traditionalChinese) ?? session.message?.text ?? "")", file: file, line: line)
            }
        }
        return bought
    }

    /// A game on the whole of Taiwan as the launcher starts it, with the
    /// app's real-world data (its people, places, water and heights).
    static func wholeTaiwan(rules: NewGameRules) throws -> GameSession {
        let session = try TimetableCheckupAllBoughtTests.wholeTaiwan(rules: rules)
        let data = Map3DOpenEveryStartTests.data
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.coverage = data.coverage
        return session
    }

    func testWritingTheWorlds() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["BOUGHT_WORLDS"] else {
            throw XCTSkip("Set BOUGHT_WORLDS=<directory> to write the bought worlds' saves (decision 878).")
        }
        let only = environment["BOUGHT_WORLDS_ONLY"]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let games: [(String, (NewGameRules) throws -> GameSession)] = [
            ("hk-all", { try TimetableCheckupAllBoughtTests.hongKong(rules: $0) }),
            ("rovaniemi-both", { try TimetableCheckupAllBoughtTests.rovaniemi(rules: $0) }),
            ("taiwan-all", { try Self.wholeTaiwan(rules: $0) }),
        ]
        for (map, open) in games {
            for (label, rules) in Self.rules {
                let name = "\(map)-\(label)"
                if let only, only != name { continue }
                let started = Date()
                let session = try open(rules)
                let bought = Self.buyEverything(in: session)
                let world = session.world
                let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name).json")
                try JSONEncoder().encode(SavedGame(world: world)).write(to: path)
                let text = "BOUGHT_WORLDS \(name): \(bought.count) lines bought \(bought), \(world.stations.count) stations, "
                    + "\(world.lines.count) lines, \(world.trains.count) trains, \(world.network.edges.count) edges; "
                    + String(format: "%.0f s; ", Date().timeIntervalSince(started)) + path.path + "\n"
                FileHandle.standardError.write(Data(text.utf8))
                XCTAssertFalse(bought.isEmpty, name)
            }
        }
    }
}
