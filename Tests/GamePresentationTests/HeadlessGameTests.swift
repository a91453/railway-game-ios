import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 260: the game with no screen. A new game, a save
/// or a problem report's log in; commands, game time and a JSON summary
/// out; and GameSim's command line, which refuses what it does not know.
@MainActor
final class HeadlessGameTests: XCTestCase {
    /// A new game (seed 1) with a line between its first two towns, its
    /// train running all day.
    private func lineWorld() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    private func lineGame() throws -> HeadlessGame {
        HeadlessGame(world: try lineWorld())
    }

    func testAdvancingRunsTheGameAndTheSummaryReadsIt() throws {
        let game = try lineGame()
        let balance = game.world.economy.balance
        let advanced = game.advance(seconds: 2 * GameTime.secondsPerDay)
        XCTAssertEqual(advanced.seconds, 2 * GameTime.secondsPerDay)
        XCTAssertEqual(advanced.day, 2)
        XCTAssertEqual(advanced.balanceChange, (game.world.economy.balance - balance).amount / 100)

        let summary = game.summary()
        XCTAssertEqual(summary.clock.day, 2)
        let day = try XCTUnwrap(summary.economy?.lastDay)
        XCTAssertEqual(day.day, 1)
        XCTAssertGreaterThan(day.trips, 0, "the line carried passengers")
        XCTAssertGreaterThan(day.fares, 0)
        XCTAssertEqual(summary.lines?.count, 1)
        XCTAssertEqual(summary.lines?.first?.trains, 1)
        XCTAssertEqual(summary.lines?.first?.stops.count, 2)
        let train = try XCTUnwrap(summary.trains?.first)
        XCTAssertTrue(["atStop", "running"].contains(train.state), train.state)
        XCTAssertEqual(train.line, summary.lines?.first?.id)
        XCTAssertFalse(train.deadlocked)
        XCTAssertEqual(summary.deadlocked, [])
        XCTAssertEqual(summary.stations?.count, 2)
        XCTAssertNil(summary.goals, "no challenge")

        let economyOnly = game.summary([.economy])
        XCTAssertNotNil(economyOnly.economy)
        XCTAssertNil(economyOnly.trains)
        XCTAssertNil(economyOnly.deadlocked)
    }

    func testAPausedGameIsResumedAndAGoalMetDoesNotStopIt() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000), clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        try world.startScenario(Scenario(id: "custom.1", goals: [.equity(Money(1))], goldDays: 1, silverDays: 5, deadlineDays: 9))
        world.pause()
        let game = HeadlessGame(world: world)
        XCTAssertEqual(game.advance(seconds: 3 * GameTime.secondsPerDay).seconds, 3 * GameTime.secondsPerDay)
        let goals = try XCTUnwrap(game.summary([.goals]).goals)
        XCTAssertEqual(goals.scenario, "custom.1")
        XCTAssertEqual(goals.goals.first?.metOnDay, 1)
        XCTAssertEqual(goals.outcome, "completed")
    }

    func testASaveFileRoundTrips() throws {
        let game = try lineGame()
        _ = game.advance(seconds: GameTime.secondsPerHour)
        let loaded = try HeadlessGame.load(game.saveFile())
        XCTAssertEqual(loaded.world, game.world)
        XCTAssertThrowsError(try HeadlessGame.load(Data("{}".utf8)))
    }

    func testCommandsAreMadeNowAndRefusalsCounted() throws {
        let game = HeadlessGame(world: try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000))
        let applied = try game.apply(JSONEncoder().encode([
            PlayerCommand.edit(.purchaseTrain(name: "A")),
            PlayerCommand.edit(.sellTrain(TrainID(rawValue: 99))),
            PlayerCommand.edit(.purchaseTrain(name: "C")),
        ]))
        XCTAssertEqual(applied, HeadlessGame.Applied(applied: 3, refused: 1))
        XCTAssertEqual(game.world.trains.map(\.name), ["A", "C"])
        XCTAssertThrowsError(try game.apply(Data("{\"not\": \"commands\"}".utf8)))
    }

    /// A problem report's log loaded from its start and applied comes to
    /// the device's world, as ``CommandLogReplay`` does.
    func testAReportReplaysToTheDevicesWorld() throws {
        let session = GameSession(world: try lineWorld())
        session.setSpeed(.normal)
        for _ in 0..<30 { session.advance(ticks: 5) }
        session.togglePause()
        _ = session.perform(.edit(.purchaseTrain(name: "Late"))) { _, _, _ in "" }
        let data = try session.commandLogReport(version: "test", build: "0", data: [:]).encoded()

        let game = try HeadlessGame.load(data)
        let applied = try game.apply(data)
        XCTAssertNil(applied.stopReason)
        XCTAssertEqual(applied.applied, session.commandLog.entries.count)
        XCTAssertEqual(game.world, session.world)

        // Applied again, its times are past: it stops at the first entry.
        let again = try game.apply(data)
        XCTAssertEqual(again.stoppedAt, 0)
    }

    // MARK: - The command line

    func testTheCommandLineParsesOperationsJoinedByThen() throws {
        let line = try HeadlessCommandLine(arguments: [
            "--state", "game.json", "new-game", "--seed", "7", "--buys-map", "then", "advance", "--days", "2", "then", "dump", "--sections", "economy",
        ])
        XCTAssertEqual(line.state, "game.json")
        XCTAssertEqual(line.steps.map(\.name), ["new-game", "advance", "dump"])
        XCTAssertEqual(line.steps[0].options, ["seed": "7", "buys-map": ""])
        XCTAssertEqual(line.steps[2].options, ["sections": "economy"])
    }

    func testTheCommandLineRefusesWhatItDoesNotKnow() {
        func refusal(_ arguments: [String]) -> String {
            do {
                _ = try HeadlessCommandLine(arguments: arguments)
                return "accepted"
            } catch {
                return error.description
            }
        }
        XCTAssertEqual(refusal(["advance", "--weeks", "2"]), "advance does not take --weeks; it takes --days, --hours, --minutes, --seconds")
        XCTAssertTrue(refusal(["fly"]).hasPrefix("unknown operation fly; known: new-game, load"))
        XCTAssertEqual(refusal(["load"]), "load needs a file")
        XCTAssertEqual(refusal(["dump", "extra"]), "dump does not take extra")
        XCTAssertEqual(refusal(["new-game", "--seed"]), "new-game --seed needs a value")
        XCTAssertTrue(refusal(["new-game", "then"]).hasPrefix("an empty operation"))
        XCTAssertEqual(refusal(["--verbose", "dump"]), "unknown option --verbose before the first operation; known: --data, --state")
    }

    func testTheCommandLineRunsAndKeepsItsState() throws {
        var files: [String: Data] = [:]
        var printed: [String] = []
        func run(_ arguments: [String]) throws -> Bool {
            try HeadlessCommandLine(arguments: arguments).run(
                print: { printed.append($0) },
                read: { name in
                    guard let data = files[name] else { throw HeadlessGameError("no file \(name)") }
                    return data
                },
                write: { files[$0] = $1 }
            )
        }
        XCTAssertTrue(try run(["--state", "s.json", "new-game", "--seed", "3", "then", "advance", "--hours", "2", "then", "dump", "--sections", "economy"]))
        XCTAssertEqual(printed.count, 3)
        let receipts = try printed.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(receipts.map { $0["op"] as? String }, ["new-game", "advance", "dump"])
        XCTAssertEqual(receipts.map { $0["ok"] as? Bool }, [true, true, true])
        XCTAssertEqual((receipts[1]["result"] as? [String: Any])?["seconds"] as? Int, 7_200)
        XCTAssertNotNil(files["s.json"], "the state is kept")

        // The next run goes on from the state.
        printed = []
        XCTAssertTrue(try run(["--state", "s.json", "dump", "--sections", "economy"]))
        XCTAssertTrue(printed[0].contains("\"seconds\":7200"), printed[0])

        // A failure answers with the error and stops.
        printed = []
        XCTAssertFalse(try run(["load", "missing.json", "then", "dump"]))
        XCTAssertEqual(printed.count, 1)
        XCTAssertTrue(printed[0].hasPrefix("{\"error\":\"no file missing.json\",\"ok\":false,\"op\":\"load\""), printed[0])
        printed = []
        XCTAssertFalse(try run(["advance", "--days", "1"]), "no game")
        XCTAssertTrue(printed[0].contains("no game"), printed[0])
    }
}
