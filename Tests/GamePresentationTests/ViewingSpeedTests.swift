import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 195: watching at a true speed. How fast game time
/// really runs (``GameSpeedMeter``, read by the session from its ticks),
/// the followed train's speed (``TrainSpeedometer``), what the status pill
/// says of them in both languages, the follow bar's 1× and 10× through the
/// session's own speed (logged, decision 193), and the help guide's entry.
@MainActor
final class ViewingSpeedTests: XCTestCase {
    private static let tick = GameSession.tickInterval

    /// A small world running at `speed`, with nothing to slow its ticks.
    private func runningSession(_ speed: GameSpeed = .normal, language: DisplayLanguage = .english) throws -> GameSession {
        GameSession(world: try makeWorld(speed: speed), language: language)
    }

    /// `count` steps of `elapsed` real time each.
    private func run(_ session: GameSession, _ count: Int, of elapsed: Duration = tick) {
        for _ in 0..<count { session.advance(realElapsed: elapsed) }
    }

    // MARK: How fast the game really runs

    func testAGameThatKeepsUpReadsAsItsSpeed() throws {
        let session = try runningSession()
        run(session, 9)
        XCTAssertNil(session.viewingSpeed.actualTenths, "under a second: no reading yet")
        XCTAssertNil(session.viewingSpeed.actualText(in: .english))
        run(session, 30)
        let viewing = session.viewingSpeed
        XCTAssertEqual(viewing.speed, .normal)
        XCTAssertEqual(viewing.actualTenths, 6_000)
        XCTAssertFalse(viewing.isBehind)
        XCTAssertEqual(viewing.actualText(in: .english), "actual ×600")
        XCTAssertEqual(viewing.actualText(in: .traditionalChinese), "實際 ×600")
        XCTAssertNil(viewing.lagText(in: .traditionalChinese), "keeping up: no dot on the board")
        XCTAssertNil(viewing.trainSpeedText, "following no train")
    }

    func testAGameThatFallsBehindSaysSo() throws {
        let session = try runningSession()
        // A second at a time: a step turns at most half a second into ticks
        // (``GameSession/maximumStepDuration``), so half the game time runs.
        run(session, 5, of: .seconds(1))
        let viewing = session.viewingSpeed
        XCTAssertTrue(viewing.isBehind)
        XCTAssertEqual(viewing.actualTenths, 3_000)
        XCTAssertEqual(viewing.actualText(in: .english), "actual ×300 (falling behind)")
        XCTAssertEqual(viewing.actualText(in: .traditionalChinese), "實際 ×300（跟不上）")
        XCTAssertTrue(viewing.accessibilityText(in: .traditionalChinese).contains("跟不上"))
        // Decision 226: the board's dot, tapped.
        XCTAssertEqual(viewing.lagText(in: .traditionalChinese), "遊戲現在只跑得到 ×300，比設定的 ×600 慢。")
        XCTAssertEqual(viewing.lagText(in: .english), "The game is running at ×300, slower than ×600.")
        // Keeping up again, the last three seconds read as the speed.
        run(session, 40)
        XCTAssertEqual(session.viewingSpeed.actualTenths, 6_000)
        XCTAssertFalse(session.viewingSpeed.isBehind)
    }

    func testAPausedGameHasNoReading() throws {
        let session = try runningSession()
        run(session, 20)
        XCTAssertNotNil(session.viewingSpeed.actualTenths)
        session.togglePause()
        XCTAssertNil(session.viewingSpeed.actualTenths, "paused at once")
        run(session, 30)
        XCTAssertNil(session.viewingSpeed.actualTenths, "nor while it stays paused")
        XCTAssertEqual(session.viewingSpeed.speed, .paused)
        XCTAssertNil(session.viewingSpeed.actualText(in: .english))
        // Going on, it reads afresh: the paused time is not time it failed to run.
        session.togglePause()
        run(session, 5)
        XCTAssertNil(session.viewingSpeed.actualTenths)
        run(session, 10)
        XCTAssertEqual(session.viewingSpeed.actualTenths, 6_000)
        XCTAssertFalse(session.viewingSpeed.isBehind)
    }

    func testANewSpeedReadsAfresh() throws {
        let session = try runningSession()
        run(session, 20)
        session.setSpeed(.x10)
        XCTAssertEqual(session.viewingSpeed.speed, .x10)
        XCTAssertNil(session.viewingSpeed.actualTenths, "600× is not 10×'s reading")
        run(session, 15)
        XCTAssertEqual(session.viewingSpeed.actualTenths, 100)
        XCTAssertEqual(session.viewingSpeed.actualText(in: .english), "actual ×10")
        session.setSpeed(.x1)
        run(session, 15)
        XCTAssertEqual(session.viewingSpeed.actualText(in: .traditionalChinese), "實際 ×1")
    }

    func testTheMeterCountsTicksAgainstRealTime() {
        var meter = GameSpeedMeter()
        XCTAssertNil(meter.permilleOfSpeed)
        // 1.5 s at 10 ticks a second, all put in place.
        for step in 0...15 { meter.record(real: .milliseconds(step * 100), ticks: Int64(step), speed: .normal) }
        XCTAssertEqual(meter.permilleOfSpeed, 1_000)
        // Then 3 s with 9 ticks in 10 due: 90%, over the last three seconds.
        for step in 1...30 { meter.record(real: .milliseconds(1_500 + step * 100), ticks: 15 + Int64(step * 9 / 10), speed: .normal) }
        XCTAssertEqual(meter.permilleOfSpeed, 900)
        let shown = ViewingSpeed(speed: .normal, permille: meter.permilleOfSpeed, trainKilometresPerHour: nil)
        XCTAssertFalse(shown.isBehind, "90% is slower, not falling behind")
        XCTAssertEqual(shown.actualText(in: .english), "actual ×540")
        // Another speed, a pause or time running back starts again.
        meter.record(real: .milliseconds(4_600), ticks: 41, speed: .x10)
        XCTAssertNil(meter.permilleOfSpeed)
        meter.record(real: .milliseconds(5_700), ticks: 52, speed: .x10)
        XCTAssertEqual(meter.permilleOfSpeed, 1_000)
        meter.record(real: .milliseconds(5_800), ticks: 53, speed: .paused)
        XCTAssertNil(meter.permilleOfSpeed)
        meter.record(real: .milliseconds(100), ticks: 1, speed: .x10)
        meter.record(real: .milliseconds(50), ticks: 2, speed: .x10)
        XCTAssertNil(meter.permilleOfSpeed)
    }

    // MARK: Text

    func testTheSpeedReadsAsAPlayerReadsIt() {
        XCTAssertEqual(ViewingSpeed.twoFigures(5_870), 5_900)
        XCTAssertEqual(ViewingSpeed.twoFigures(45), 45)
        XCTAssertEqual(ViewingSpeed.twoFigures(12_340), 12_000)
        XCTAssertEqual(ViewingSpeed.timesText(5_900), "×590")
        XCTAssertEqual(ViewingSpeed.timesText(45), "×4.5")
        // Within 5% of the speed it reads as the speed; under 80% it is
        // falling behind.
        XCTAssertEqual(ViewingSpeed(speed: .normal, permille: 960, trainKilometresPerHour: nil).actualTenths, 6_000)
        XCTAssertEqual(ViewingSpeed(speed: .normal, permille: 940, trainKilometresPerHour: nil).actualTenths, 5_600)
        XCTAssertFalse(ViewingSpeed(speed: .normal, permille: 800, trainKilometresPerHour: nil).isBehind)
        XCTAssertTrue(ViewingSpeed(speed: .normal, permille: 799, trainKilometresPerHour: nil).isBehind)
        XCTAssertEqual(ViewingSpeed(speed: .x1, permille: 500, trainKilometresPerHour: nil).actualText(in: .english), "actual ×0.5 (falling behind)")
        XCTAssertNil(ViewingSpeed(speed: .paused, permille: 1_000, trainKilometresPerHour: nil).actualTenths)
        // The train's speed.
        let following = ViewingSpeed(speed: .x1, permille: nil, trainKilometresPerHour: 285)
        XCTAssertEqual(following.trainSpeedText, "285 km/h")
        XCTAssertEqual(ViewingSpeed(speed: .x1, permille: nil, trainKilometresPerHour: 1_200).trainSpeedText, "1,200 km/h")
        XCTAssertEqual(following.accessibilityText(in: .english), "the train runs at 285 km/h")
        XCTAssertEqual(following.accessibilityText(in: .traditionalChinese), "列車時速 285 公里")
        let both = ViewingSpeed(speed: .x1, permille: 1_000, trainKilometresPerHour: 90)
        XCTAssertEqual(both.accessibilityText(in: .english), "The game runs 1 times real time, the train runs at 90 km/h")
        XCTAssertEqual(both.accessibilityText(in: .traditionalChinese), "遊戲以真實時間的 1 倍進行，列車時速 90 公里")
        // The speed set reads on the speed menu, as it did.
        XCTAssertEqual(GameSpeed.normal.label(in: .english), "600×")
        XCTAssertEqual(GameSpeed.x1.accessibilityName(in: .traditionalChinese), "真實時間")
    }

    // MARK: The followed train

    /// The line between two towns (decision 137's, 5.4 km), its one train
    /// followed.
    private func followedTrain(realisticOperation: Bool = true) throws -> (GameSession, TrainID) {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.setRealisticOperation(realisticOperation)
        let session = GameSession(world: world)
        let train = try XCTUnwrap(session.world.trains.first?.id)
        session.followTrain(train)
        XCTAssertTrue(session.isFollowingTrain)
        return (session, train)
    }

    func testTheFollowedTrainsSpeed() throws {
        // Without realistic operation (decision 207) a leg is planned at its
        // least time, so the train runs up to its top speed (the line's
        // standard 110 km/h) and runs at it between the towns. With it, the
        // leg has a 4 % recovery margin: a train on time cruises a little
        // below its top speed, and keeps the rest for when it is late.
        for realistic in [false, true] {
            let (session, _) = try followedTrain(realisticOperation: realistic)
            session.setSpeed(.x60)
            // Six game seconds a tick.
            var fastest: Int64 = 0
            var sawStanding = false
            for _ in 0..<400 {
                session.advance(realElapsed: Self.tick)
                guard let speed = session.viewingSpeed.trainKilometresPerHour else { continue }
                fastest = max(fastest, speed)
                sawStanding = sawStanding || speed == 0
            }
            if realistic {
                XCTAssertTrue((95...107).contains(fastest), "below its top speed, on time with a margin: \(fastest)")
            } else {
                XCTAssertTrue((108...111).contains(fastest), "its top speed, 110 km/h: \(fastest)")
            }
            XCTAssertTrue(sawStanding, "and 0 standing at a platform")
            XCTAssertNotNil(session.viewingSpeed.trainSpeedText)
            // Following none, none.
            session.stopFollowingTrain()
            XCTAssertNil(session.viewingSpeed.trainKilometresPerHour)
            XCTAssertNil(session.viewingSpeed.trainSpeedText)
        }
    }

    func testTheTrackCoveredAlongTheWay() throws {
        let world = try newGameLine(through: Land.townCentres(seed: 1, in: GameWorld.newGameBounds).prefix(2).map { $0 })
        let edge = try XCTUnwrap(world.network.edges.first)
        let length = try XCTUnwrap(world.trackGeometry(of: edge.id)?.length)
        let forward = TrackTraversal(edge: edge.id, direction: .forward)
        XCTAssertEqual(GameWorld.trackDistance(from: .onEdge(forward, offset: 100), along: [], to: .onEdge(forward, offset: 1_100), in: world), 1_000)
        XCTAssertNil(GameWorld.trackDistance(from: .onEdge(forward, offset: 1_100), along: [], to: .onEdge(forward, offset: 100), in: world), "behind it")
        XCTAssertNil(GameWorld.trackDistance(from: .onEdge(forward, offset: 100), along: [], to: .onEdge(TrackTraversal(edge: edge.id, direction: .backward), offset: length - 2_000), in: world), "turned round")
    }

    // MARK: The follow bar's 1× and 10×

    func testTheFollowBarsSpeedsAreTheGamesOwnAndLogged() throws {
        let (session, _) = try followedTrain()
        XCTAssertEqual(FollowBarInfo.speedShortcuts, [.x1, .x10])
        XCTAssertEqual(FollowBarInfo.speedShortcuts.map { $0.label(in: .english) }, ["1×", "10×"])
        for speed in FollowBarInfo.speedShortcuts {
            session.setSpeed(speed)
            XCTAssertEqual(session.world.clock.speed, speed)
            XCTAssertEqual(session.commandLog.entries.last?.action, .setSpeed(speed), "the command log has it (decision 193)")
            XCTAssertTrue(session.isFollowingTrain, "the camera keeps following")
        }
        // Paused, 1× runs at real time.
        session.togglePause()
        session.setSpeed(.x1)
        XCTAssertEqual(session.world.clock.speed, .x1)
        XCTAssertFalse(session.world.clock.isPaused)
        XCTAssertEqual(session.commandLog.entries.last?.action, .setSpeed(.x1))
        // Following stops; the speed stays as the player chose it.
        let entries = session.commandLog.entries.count
        session.stopFollowingTrain()
        XCTAssertFalse(session.isFollowingTrain)
        XCTAssertEqual(session.world.clock.speed, .x1)
        XCTAssertEqual(session.commandLog.entries.count, entries, "nothing set back")
    }

    // MARK: The help guide

    func testTheHelpGuideSaysWhat600TimesIs() throws {
        let entry = try XCTUnwrap(HelpGuide.entries.first { $0.id == "timeScale" })
        XCTAssertEqual(entry.topic, .running)
        XCTAssertTrue(entry.answer(in: .english).contains("50 km of map in a second"))
        XCTAssertTrue(entry.answer(in: .traditionalChinese).contains("畫面上每秒跑過 50 公里"))
        for query in ["600×", "real time", "真實時間", "跟不上", "km/h"] {
            XCTAssertTrue(HelpGuide.entries(matching: query).contains(entry), query)
        }
    }
}
