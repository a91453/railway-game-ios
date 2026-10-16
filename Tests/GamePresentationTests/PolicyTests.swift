import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 261: scripted play. A policy's actions run on
/// their day, a refusal for want of money waits for the money, and the
/// player notes what went wrong; GameSim plays a policy by name.
@MainActor
final class PolicyTests: XCTestCase {
    private struct Refused: Error {}

    func testActionsRunOnTheirDayAndChangeTheWorldOnlyWhenTheySucceed() throws {
        var ran: [String] = []
        let policy = Policy(name: "test", actions: [
            Policy.Action(day: 0) { world, _ in
                ran.append("a")
                _ = try world.purchaseTrain(named: "A")
            },
            Policy.Action(day: 2) { world, _ in
                ran.append("b")
                _ = try world.purchaseTrain(named: "B")
            },
        ])
        var player = PolicyPlayer(world: try makeWorld(balance: 1_000_000, speed: .normal), policy: policy)
        try player.playDay()
        XCTAssertEqual(ran, ["a"])
        try player.playDay()
        XCTAssertEqual(ran, ["a"], "b is due on day 2")
        try player.playDay()
        XCTAssertEqual(ran, ["a", "b"])
        XCTAssertEqual(player.world.trains.map(\.name), ["A", "B"])
        XCTAssertEqual(player.day, 3)
        XCTAssertTrue(player.pending.isEmpty)

        // A refusal other than money is thrown, and leaves the world as it was.
        var failing = PolicyPlayer(world: try makeWorld(balance: 1_000_000), policy: Policy(name: "bad", actions: [
            Policy.Action(day: 0, waitsForMoney: true) { world, _ in
                _ = try world.purchaseTrain(named: "Half")
                throw Refused()
            },
        ]))
        XCTAssertThrowsError(try failing.runDue())
        XCTAssertTrue(failing.world.trains.isEmpty)
    }

    func testARefusalForWantOfMoneyWaitsAndHoldsTheActionsAfterIt() throws {
        var paid = false
        let policy = Policy(name: "test", actions: [
            Policy.Action(day: 0, waitsForMoney: true) { world, _ in
                guard paid else { throw GameError.insufficientFunds(required: Money(100), available: .zero) }
                _ = try world.purchaseTrain(named: "Dear")
            },
            Policy.Action(day: 0) { world, _ in _ = try world.purchaseTrain(named: "Cheap") },
        ])
        var player = PolicyPlayer(world: try makeWorld(balance: 1_000_000, speed: .normal), policy: policy)
        try player.playDay()
        XCTAssertTrue(player.world.trains.isEmpty, "the second waits behind the first")
        XCTAssertEqual(player.pending.count, 2)
        paid = true
        try player.playDay()
        XCTAssertEqual(player.world.trains.map(\.name), ["Dear", "Cheap"])

        // Without waiting, want of money stops the play.
        var strict = PolicyPlayer(world: try makeWorld(), policy: Policy(name: "strict", actions: [
            Policy.Action(day: 0) { _, _ in throw GameError.insufficientFunds(required: Money(100), available: .zero) },
        ]))
        XCTAssertThrowsError(try strict.runDue())
    }

    /// A line whose train cannot move, between stations no one lives near:
    /// no trips, the train stands still, and the cash runs out.
    func testThePlayerNotesWhatWentWrong() throws {
        var world = try newGameLine(through: [PlanPoint(x: 40_000, y: 40_000), PlanPoint(x: 120_000, y: 40_000)], in: try makeWorld(
            width: 262_144, height: 131_072, balance: 1_000_000, speed: .normal
        ))
        world.setEconomyMode(.management)
        let train = try XCTUnwrap(world.trains.first).id
        try world.setTrainMovementRate(train, to: 0)
        var player = PolicyPlayer(world: world, policy: .none)
        for _ in 0..<3 { try player.playDay() }
        let kinds = Set(player.anomalies.map(\.kind))
        XCTAssertTrue(kinds.contains(.zeroTrips), "\(player.anomalies)")
        XCTAssertEqual(player.anomalies.first { $0.kind == .zeroTrips }?.day, 2, "the first day starts from an empty network")
        XCTAssertEqual(player.anomalies.first { $0.kind == .trainStopped }?.trains, [train.rawValue])
        XCTAssertFalse(kinds.contains(.deadlock))
        XCTAssertEqual(player.anomalyDays[.zeroTrips], 2)
    }

    func testAPlayedLineBetweenTwoTownsGoesWell() throws {
        let game = HeadlessGame.newGame(seed: 1)
        let played = try game.play(try XCTUnwrap(Policy.named("two-towns", seed: 1, bounds: game.world.bounds)), days: 2)
        XCTAssertEqual(played.policy, "two-towns")
        XCTAssertEqual(played.days.map(\.day), [1, 2])
        XCTAssertGreaterThan(played.days[1].trips, 0)
        XCTAssertEqual(played.anomalies, [])
        XCTAssertEqual(played.unbuilt, 0)
        XCTAssertEqual(game.world.lines.count, 1, "the session goes on from the world played")
        XCTAssertEqual(game.world.clock.now.seconds, 2 * GameTime.secondsPerDay)
    }

    func testPoliciesAreFoundByName() {
        let bounds = GameWorld.newGameBounds
        for name in Policy.names {
            XCTAssertEqual(Policy.named(name, seed: 1, bounds: bounds)?.name, name)
        }
        XCTAssertNil(Policy.named("fly", seed: 1, bounds: bounds))
        XCTAssertEqual(Policy.named("third-town", seed: 1, bounds: bounds)?.actions.map(\.day), [0, 3])
        XCTAssertEqual(Policy.named("grown", seed: 1, bounds: bounds)?.actions.map(\.day), [0, 0, 30, 30, 30, 30])
    }

    func testGameSimPlaysAPolicy() throws {
        var printed: [String] = []
        let line = try HeadlessCommandLine(arguments: ["new-game", "--seed", "1", "then", "play", "--policy", "two-towns", "--days", "1"])
        XCTAssertTrue(line.run(print: { printed.append($0) }, read: { _ in Data() }, write: { _, _ in }))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(printed[1].utf8)) as? [String: Any])
        XCTAssertEqual(receipt["op"] as? String, "play")
        let result = try XCTUnwrap(receipt["result"] as? [String: Any])
        XCTAssertEqual((result["days"] as? [Any])?.count, 1)

        printed = []
        XCTAssertFalse(try HeadlessCommandLine(arguments: ["new-game", "then", "play", "--policy", "fly", "--days", "1"]).run(
            print: { printed.append($0) }, read: { _ in Data() }, write: { _, _ in }
        ))
        XCTAssertTrue(printed[1].contains("unknown policy fly; known: none, two-towns"), printed[1])
    }

    func testAnyPolicyPlaysUnderAnyRulesOnAnyMap() throws {
        let plain = try HeadlessGame.newGame(map: .blank(seed: 2), rules: .realistic, preset: .noTrafficControl)
        XCTAssertFalse(plain.world.isTrafficControlEnabled)
        XCTAssertFalse(plain.world.curveSpeedLimits)
        XCTAssertEqual(plain.towns, Land.townCentres(seed: 2, in: plain.world.bounds))
        XCTAssertEqual(plain.seed, 2)
        XCTAssertEqual(try HeadlessGame.newGame(map: .blank(seed: 2), rules: .realistic).world, GameWorld.newGame(eventSeed: 2))

        // A real place: its densest towns, its land read in.
        let files = RealWorldFiles(folder: CommandLogReplay.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld"))
        let place = try HeadlessGame.newGame(map: .place("tra-hsinchu"), files: files)
        XCTAssertGreaterThanOrEqual(place.towns.count, 2)
        XCTAssertFalse(place.world.land.cells.isEmpty)
        XCTAssertNil(place.seed)
        XCTAssertThrowsError(try HeadlessGame.newGame(map: .place("tra-hsinchu")), "the data is needed")
        XCTAssertThrowsError(try HeadlessGame.newGame(map: .place("atlantis"), files: files))

        // A policy needs its towns.
        let bounds = GameWorld.newGameBounds
        XCTAssertNil(Policy.named("third-town", towns: Array(plain.towns.prefix(2)), bounds: bounds))
        XCTAssertNotNil(Policy.named("two-towns", towns: Array(plain.towns.prefix(2)), bounds: bounds))
        XCTAssertNotNil(Policy.named("none", towns: [], bounds: bounds))
    }

    func testTheSharedTableShowsTheSameMeasuresForEveryPlay() throws {
        var minutes = PolicyPlayer(world: try lineWorld(), policy: .none, byMinute: true)
        var days = PolicyPlayer(world: try lineWorld(), policy: .none)
        for _ in 0..<3 {
            try minutes.playDay()
            try days.playDay()
        }
        XCTAssertEqual(minutes.world, days.world, "a minute at a time comes to the same world")
        XCTAssertEqual(minutes.balances, days.balances)
        XCTAssertEqual(minutes.trips, days.trips)
        let table = PlayReport.table([PlayReport(label: "By minute", player: minutes), PlayReport(label: "By day", player: days)], title: "Test")
        let rows = table.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(rows.count, 6)
        XCTAssertTrue(rows[4].hasPrefix("| By minute | $\(minutes.balances[0] / 100) / $\(minutes.balances[2] / 100) / — / — | \(minutes.trips[2]) | 0 (0) | 0 of 1 | none |"), String(rows[4]))
        XCTAssertTrue(rows[5].contains("| — (PLAY_BY_MINUTE=1) |"), String(rows[5]))
    }

    private func lineWorld() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }
}
