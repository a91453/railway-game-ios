import Foundation
@testable import GameCore
import XCTest

/// Decision 693: a run driven by hand, settled by the world: its marks by
/// whole-number rules, what a good one earns a managed company, the record
/// kept, and what is refused. Every expectation is worked out by hand from
/// the rules.
final class DrivenRunTests: XCTestCase {
    private let metre = WorldCoordinate.unitsPerMetre

    /// Stations A and B four kilometres apart on one track, a line between
    /// them and its train on the track, in a managed company.
    private func world(managed: Bool = true) throws -> (GameWorld, TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 524_288, height: 65_536),
            economy: fixtureEconomy(balance: 1_000_000_000, costs: testCosts)
        )
        if managed { world.setEconomyMode(.management) }
        let y: Int64 = 8_192
        let nodes = try [8_192, 12_288, 268_288, 272_384].map { try world.buildTrackNode(at: WorldCoordinate(x: Int64($0), y: y)) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let last = try world.buildTrackEdge(from: nodes[2], to: nodes[3])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 10_240, y: y + 512)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 270_336, y: y + 512)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 20_000))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 20_000))
        let line = try world.createLine(named: "Main", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: line)
        world.setSpeed(.normal)
        return (world, train)
    }

    private func run(
        _ train: TrainID, _ outcome: DrivenRun.Outcome = .stopped, offset: Int64 = 0, lateness: Int64 = 0, overspeed: Int64 = 0, emergency: Bool = false
    ) -> DrivenRun {
        DrivenRun(train: train, outcome: outcome, offset: offset, lateness: lateness, overspeed: overspeed, usedEmergency: emergency)
    }

    // MARK: - Marks

    func testTheMarksOfARun() {
        let train = TrainID(rawValue: 1)
        func marks(_ run: DrivenRun) -> [Int] { [run.marks.position, run.marks.time, run.marks.handling] }
        // On the mark, on time, no fault: all of it.
        XCTAssertEqual(marks(run(train)), [50, 30, 20])
        XCTAssertEqual(run(train).marks.grade, .s)
        // Half a metre and five seconds either way are still on it.
        XCTAssertEqual(marks(run(train, offset: -metre / 2, lateness: 5_000)), [50, 30, 20])
        XCTAssertEqual(marks(run(train, offset: metre / 2, lateness: -5_000)), [50, 30, 20])
        // 12.75 m short: half way from 0.5 m to 25 m, 25 marks. The same
        // past: beyond 12.5 m, none.
        XCTAssertEqual(marks(run(train, offset: -(12 * metre + 3 * metre / 4))), [25, 30, 20])
        XCTAssertEqual(marks(run(train, offset: 12 * metre + 3 * metre / 4)), [0, 30, 20])
        // 6.5 m past: half way from 0.5 m to 12.5 m.
        XCTAssertEqual(marks(run(train, offset: 6 * metre + metre / 2)), [25, 30, 20])
        // 32.5 s late or early: half way from 5 s to 60 s, 15 marks; a
        // minute: none.
        XCTAssertEqual(marks(run(train, lateness: 32_500)), [50, 15, 20])
        XCTAssertEqual(marks(run(train, lateness: -32_500)), [50, 15, 20])
        XCTAssertEqual(marks(run(train, lateness: 60_000)), [50, 0, 20])
        // Two marks a second over the limit (2.4 s: 4.8, 5 marks), ten for
        // the emergency brake, and never below none.
        XCTAssertEqual(marks(run(train, overspeed: 2_400)), [50, 30, 15])
        XCTAssertEqual(marks(run(train, emergency: true)), [50, 30, 10])
        XCTAssertEqual(marks(run(train, overspeed: 30_000, emergency: true)), [50, 30, 0])
        // A run that did not stop has no marks.
        XCTAssertEqual(marks(run(train, .passed, offset: 60 * metre)), [0, 0, 0])
        XCTAssertEqual(marks(run(train, .timedOut, offset: -900 * metre, lateness: 180_020)), [0, 0, 0])
        XCTAssertEqual(run(train, .passed, offset: 60 * metre).marks.grade, .d)
        // The grades' edges.
        XCTAssertEqual(run(train, lateness: 14_000).marks.total, 95)
        XCTAssertEqual(run(train, lateness: 14_000).marks.grade, .s)
        XCTAssertEqual(run(train, lateness: 16_000).marks.total, 94)
        XCTAssertEqual(run(train, lateness: 16_000).marks.grade, .a)
    }

    func testWhatARunEarns() {
        // NT$500 and NT$5 a passenger at 100 marks, in proportion to the
        // marks over 50, in whole dollars.
        XCTAssertEqual(DrivenRun.bonus(marks: 100, riders: 0), Money(500_00))
        XCTAssertEqual(DrivenRun.bonus(marks: 100, riders: 300), Money(2_000_00))
        XCTAssertEqual(DrivenRun.bonus(marks: 75, riders: 300), Money(1_000_00))
        XCTAssertEqual(DrivenRun.bonus(marks: 96, riders: 123), Money(1_025_00), "1,115 × 46 ÷ 50 = 1,025.8")
        XCTAssertEqual(DrivenRun.bonus(marks: 51, riders: 0), Money(10_00))
        XCTAssertEqual(DrivenRun.bonus(marks: 50, riders: 1_000), .zero)
        XCTAssertEqual(DrivenRun.bonus(marks: 0, riders: 1_000), .zero)
    }

    // MARK: - Settling

    func testAGoodRunPaysAManagedCompanyAndIsKeptOnRecord() throws {
        var (world, train) = try world()
        try world.advance(ticks: 30)
        let before = world
        let riders = world.riderCount(of: train)
        let settled = try world.settleDrivenRun(run(train, lateness: 14_000))
        XCTAssertEqual(settled.marks.total, 95)
        XCTAssertEqual(settled.riders, riders)
        XCTAssertTrue(settled.keepsAccounts)
        let bonus = DrivenRun.bonus(marks: 95, riders: riders)
        XCTAssertGreaterThanOrEqual(bonus, Money(450_00))
        XCTAssertEqual(settled.bonus, bonus)
        XCTAssertTrue(settled.isBest)
        XCTAssertEqual(world.economy.balance, before.economy.balance + bonus)
        let row = try XCTUnwrap(world.accounts.entries.last)
        XCTAssertEqual(row.kind, .drivenRun)
        XCTAssertEqual(row.amount, bonus)
        XCTAssertEqual(row.breakdown, [LedgerLine(item: .drivingBonus, amount: bonus)])
        XCTAssertEqual(row.time, world.clock.now)
        XCTAssertEqual(world.accounts.entries.count, before.accounts.entries.count + 1)
        XCTAssertEqual(world.driving, DrivingRecord(runs: 1, arrivals: 1, best: 95, earned: bonus, last: world.clock.now.seconds))
        XCTAssertEqual(settled.record, world.driving)
        // The train is left to its timetable, and nothing else changed.
        XCTAssertEqual(world.trains, before.trains)
        XCTAssertEqual(world.riders, before.riders)
        XCTAssertEqual(world.clock, before.clock)
        // The world is still one a save holds.
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testLaterRunsAddToTheRecord() throws {
        var (world, train) = try world()
        try world.advance(ticks: 30)
        let first = try world.settleDrivenRun(run(train, lateness: 32_500))
        XCTAssertEqual(first.marks.total, 85)
        try world.advance(ticks: 1)
        let cash = world.economy.balance, rows = world.accounts.entries.count
        // A run past the stop: counted, no marks, nothing paid, no row.
        let passed = try world.settleDrivenRun(run(train, .passed, offset: 60 * metre))
        XCTAssertEqual(passed.bonus, .zero)
        XCTAssertFalse(passed.isBest)
        XCTAssertEqual(world.economy.balance, cash)
        XCTAssertEqual(world.accounts.entries.count, rows)
        XCTAssertEqual(world.driving?.runs, 2)
        XCTAssertEqual(world.driving?.arrivals, 1)
        XCTAssertEqual(world.driving?.best, 85)
        try world.advance(ticks: 1)
        // A worse run that stopped is not the best; a better one is.
        XCTAssertFalse(try world.settleDrivenRun(run(train, lateness: 60_000)).isBest)
        try world.advance(ticks: 1)
        let best = try world.settleDrivenRun(run(train))
        XCTAssertTrue(best.isBest)
        XCTAssertEqual(best.record.runs, 4)
        XCTAssertEqual(best.record.arrivals, 3)
        XCTAssertEqual(best.record.best, 100)
        XCTAssertEqual(best.record.earned, first.bonus + DrivenRun.bonus(marks: 70, riders: world.riderCount(of: train)) + best.bonus)
    }

    func testACompanyWithoutAccountsIsPaidNothingButKeepsTheRecord() throws {
        var (world, train) = try world(managed: false)
        try world.advance(ticks: 30)
        let cash = world.economy.balance
        let settled = try world.settleDrivenRun(run(train))
        XCTAssertEqual(settled.bonus, .zero)
        XCTAssertFalse(settled.keepsAccounts)
        XCTAssertEqual(world.economy.balance, cash)
        XCTAssertTrue(world.accounts.entries.isEmpty)
        XCTAssertEqual(world.driving, DrivingRecord(runs: 1, arrivals: 1, best: 100, earned: .zero, last: world.clock.now.seconds))
    }

    func testARunTheWorldRefusesChangesNothing() throws {
        var (world, train) = try world()
        try world.advance(ticks: 30)
        let spare = try world.purchaseTrain(named: "Spare").id
        func refused(_ run: DrivenRun, _ error: GameError, file: StaticString = #filePath, line: UInt = #line) {
            let before = world
            XCTAssertThrowsError(try world.settleDrivenRun(run), file: file, line: line) { XCTAssertEqual($0 as? GameError, error, file: file, line: line) }
            XCTAssertEqual(world, before, file: file, line: line)
        }
        refused(run(TrainID(rawValue: 99)), .unknownTrain(TrainID(rawValue: 99)))
        // A train off the track, on no line.
        refused(run(spare), .invalidDrivenRun)
        // Figures no run has: stopped outside its window, more than an hour.
        refused(run(train, offset: 50 * metre + 1), .invalidDrivenRun)
        refused(run(train, offset: -50 * metre - 1), .invalidDrivenRun)
        refused(run(train, lateness: 3_600_001), .invalidDrivenRun)
        refused(run(train, overspeed: -1), .invalidDrivenRun)
        refused(run(train, .passed, offset: 3_600_001), .invalidDrivenRun)
        XCTAssertNil(world.driving)
        // The edges are runs.
        try world.settleDrivenRun(run(train, offset: 50 * metre, lateness: 3_600_000, overspeed: 3_600_000))
        // A second within twenty seconds of the last is refused; then not.
        try world.advance(ticks: 1)
        if world.clock.now.seconds - (world.driving?.last ?? 0) < DrivenRun.shortestSeconds {
            refused(run(train), .invalidDrivenRun)
        }
        while world.clock.now.seconds - (world.driving?.last ?? 0) < DrivenRun.shortestSeconds { try world.advance(ticks: 1) }
        try world.settleDrivenRun(run(train))
        XCTAssertEqual(world.driving?.runs, 2)
    }

    // MARK: - The save

    func testARecordNoSettlementLeavesIsRefused() throws {
        var (world, train) = try world()
        try world.advance(ticks: 30)
        try world.settleDrivenRun(run(train))
        let data = try JSONEncoder().encode(world)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var record = try XCTUnwrap(object["driving"] as? [String: Any])
        XCTAssertEqual(Set(record.keys), ["runs", "arrivals", "best", "earned", "last"])
        for (key, value) in [("runs", 0), ("arrivals", 2), ("best", 101), ("earned", -1), ("last", world.clock.now.seconds + 1)] as [(String, Int64)] {
            var broken = record
            broken[key] = value
            object["driving"] = broken
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object)), key)
        }
        record["best"] = 100
        object["driving"] = record
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object)))
        // A world that has settled none is written without it.
        let (fresh, _) = try self.world()
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh)) as? [String: Any])
        XCTAssertNil(plain["driving"])
    }

    /// `v89-driven-run.json`: this file's world a day in, two runs driven
    /// by hand settled (one of 95 marks paid for, one past the stop).
    /// Written once by the version 89 build (`DRIVEN_RUN_SAVE_NEW=1`).
    func testVersionEightyNineKeepsTheRunsDrivenByHand() throws {
        var (world, train) = try world()
        try world.advance(ticks: 500)
        let first = try world.settleDrivenRun(run(train, lateness: 14_000))
        try world.advance(ticks: 10)
        try world.settleDrivenRun(run(train, .passed, offset: 60 * metre))
        try world.advance(ticks: 2)

        let url = SavedGameTests.fixtures.appendingPathComponent("v89-driven-run.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DRIVEN_RUN_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 89)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        let record = try XCTUnwrap(loaded.driving)
        XCTAssertEqual(record.runs, 2)
        XCTAssertEqual(record.arrivals, 1)
        XCTAssertEqual(record.best, 95)
        XCTAssertEqual(record.earned, first.bonus)
        XCTAssertGreaterThan(record.earned, .zero)
        XCTAssertEqual(loaded.accounts.entries.filter { $0.kind == .drivenRun }.map(\.amount), [first.bonus])
        XCTAssertEqual(loaded, world)
        // It runs on as the game it was saved from.
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded.economy.balance, world.economy.balance)
        XCTAssertEqual(loaded.driving, world.driving)
    }
}
