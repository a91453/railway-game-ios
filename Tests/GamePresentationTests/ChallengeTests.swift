import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 86: the start screen's challenges, the goals panel's words and
/// the session noticing a scenario that ends while it runs.
final class ChallengeTests: XCTestCase {
    func testEveryChallengeStartsAManagedGameWithItsGoals() throws {
        for challenge in Challenge.sandbox {
            let world = GameWorld.newGame(challenge: challenge, eventSeed: 7)
            let state = try XCTUnwrap(world.scenario, challenge.id)
            XCTAssertEqual(state.scenario.id, challenge.id)
            XCTAssertEqual(state.startDay, 0)
            XCTAssertEqual(state.achieved.count, state.scenario.goals.count)
            XCTAssertEqual(Challenge.named(challenge.id), challenge)
            XCTAssertEqual(world.scenarioTitle(in: .traditionalChinese), challenge.title(in: .traditionalChinese))
            XCTAssertFalse(challenge.goalsText(in: .traditionalChinese).isEmpty)
            // It saves and loads as it is: the decoder checks the scenario.
            let data = try JSONEncoder().encode(SavedGame(world: world))
            XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        }
        XCTAssertEqual(Set(Challenge.sandbox.map(\.id)).count, Challenge.sandbox.count)
    }

    /// The three towns' middles are the ones the land was drawn round.
    func testThreeTownsAsksToLinkTheTownsOfItsSeed() throws {
        let world = GameWorld.newGame(challenge: Challenge.sandbox[0], eventSeed: 7)
        guard case .connect(let points, let radius)? = world.scenario?.scenario.goals.first else {
            return XCTFail("the first goal links the towns")
        }
        XCTAssertEqual(points, Land.townCentres(seed: 7, in: world.bounds))
        XCTAssertEqual(points.count, Land.townCount)
        XCTAssertEqual(radius, Land.catchmentRadius)
        for point in points {
            XCTAssertTrue(world.land.cells.contains { $0.row == Int(point.y / 4_096) && $0.column == Int(point.x / 4_096) }, "a town's middle has people")
        }
    }

    func testTheGoalsPanelSaysWhereTheScenarioStands() throws {
        let world = GameWorld.newGame(challenge: Challenge.sandbox[0], eventSeed: 7)
        XCTAssertEqual(world.scenarioStatusText(in: .traditionalChinese), "第 1 天，共 360 天 · 第 180 天前完成可得金牌")
        XCTAssertEqual(world.scenarioStatusText(in: .english), "Day 1 of 360 · gold by day 180")
        XCTAssertEqual(world.scenarioRatingsText(in: .traditionalChinese), "金牌 180 天內 · 銀牌 270 天 · 銅牌 360 天")
        let goals = world.goalProgress(in: .traditionalChinese)
        XCTAssertEqual(goals.map(\.title), ["用鐵路連通全部 3 座城鎮", "每日運量（人次）"])
        XCTAssertEqual(goals[0].detail, "0 / 3 座有路線停靠的車站")
        XCTAssertEqual(goals[1].detail, "0 / 350,000")
        XCTAssertEqual(goals.map(\.metOnDay), [nil, nil])
        XCTAssertEqual(ScenarioRating.gold.displayName(in: .traditionalChinese), "金牌")
        XCTAssertNil(GameWorld.newGame().scenarioStatusText(in: .english))
        XCTAssertEqual(GameSpeed.fast.label(in: .english), "6000×")
    }

    @MainActor
    func testTheSessionNoticesAScenarioThatEndsWhileItRuns() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000), clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        try world.startScenario(Scenario(id: "test", goals: [.equity(Money(1))], goldDays: 1, silverDays: 1, deadlineDays: 1))
        let session = GameSession(world: world)
        XCTAssertFalse(session.scenarioJustEnded)
        // `normal` runs a game minute a 100 ms tick, five a step: 289 steps
        // reach the start of the minute after midnight.
        for _ in 0..<289 {
            session.advance(realElapsed: GameSession.maximumStepDuration)
        }
        XCTAssertEqual(session.world.scenario?.outcome, .completed(day: 0, rating: .gold))
        XCTAssertTrue(session.scenarioJustEnded)
        XCTAssertEqual(session.world.scenarioStatusText(in: .traditionalChinese), "第 1 天完成：金牌")
        session.dismissScenarioEnd()
        XCTAssertFalse(session.scenarioJustEnded)
        XCTAssertFalse(GameSession(world: session.world).scenarioJustEnded, "a loaded game that ended before")
    }
}
