import Foundation
@testable import GameCore
import XCTest

/// A real line bought (ARCHITECTURE decision 315): the app lays the line
/// with the commands it has, then records the purchase, which pays for the
/// line's riders and starts its runs on the first service day.
final class LineAcquisitionTests: XCTestCase {
    private let track = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let blue = TrainID(rawValue: 1)
    private let pingxi = "tra:PINGXI"

    /// Alpha → Gamma leaving at 06:10, Beta 06:15–06:16, Gamma 06:20;
    /// every day.
    private let out = LineRun(from: 0, to: 2, times: [
        LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_500, departure: 22_560), LineRunTime(arrival: 22_800, departure: 22_800),
    ])

    /// `LineRunsTests`' Alpha, Beta and Gamma, the line Main with the run
    /// out and Blue at Alpha, laid at `minutes` past midnight on day 0 in a
    /// managed company with `balance`.
    private func world(at minutes: Int = 300, balance: Money = 10_000_000) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: balance, costs: testCosts))
        world.setEconomyMode(.management)
        // A tick a minute; nothing stands yet, so nothing runs.
        world.setSpeed(.normal)
        try world.advance(ticks: minutes)
        try track.build(in: &world)
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        _ = try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        _ = try world.purchaseTrain(named: "Blue")
        try world.placeTrain(blue, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(blue, to: 1_024)
        try world.assignTrain(blue, to: main)
        try world.setLineRuns(main, to: [out])
        return world
    }

    // MARK: - Buying

    /// Bought at 05:00, the line pays $10,000 for each of its 2 riders, books
    /// it as an asset, and runs from the next day: the run out does not go
    /// at 06:10 today, and goes at 06:10 tomorrow.
    func testABoughtLineIsPaidForAndRunsFromTheNextDay() throws {
        var world = try world()
        let before = world.economy.balance
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)

        XCTAssertEqual(world.economy.balance, before - Money(2_000_000))
        XCTAssertEqual(world.acquisitions, [LineAcquisition(realLine: pingxi, line: main, day: 0, value: Money(2_000_000))])
        XCTAssertEqual(world.acquisition(of: pingxi)?.line, main)
        XCTAssertNil(world.acquisition(of: "tra:JIJI"))
        let asset = try XCTUnwrap(world.accounts.assets.last)
        XCTAssertEqual(asset.kind, .acquiredLine)
        XCTAssertEqual(asset.owner, main.rawValue)
        XCTAssertEqual(asset.cost, Money(2_000_000))
        XCTAssertEqual(world.line(id: main)?.runDays, [0])

        // 06:10 today: not sent.
        try world.advance(ticks: 80)
        XCTAssertNil(world.train(id: blue)?.execution)
        // 06:06 tomorrow: sent for the run out.
        try world.advance(ticks: 24 * 60 - 4)
        XCTAssertNotNil(world.train(id: blue)?.execution)
        XCTAssertEqual(world.line(id: main)?.runDays, [1])
    }

    /// Bought before 04:00, the line runs today's timetable.
    func testABoughtLineBefore4RunsToday() throws {
        var world = try world(at: 200)
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 0)
        XCTAssertEqual(world.line(id: main)?.runDays, [nil])
        XCTAssertEqual(world.acquisitions.first?.value, .zero)
        try world.advance(ticks: 166)
        XCTAssertNotNil(world.train(id: blue)?.execution)
    }

    func testFirstServiceDay() {
        XCTAssertEqual(LineAcquisition.firstServiceDay(at: GameTime(seconds: 0)), 0)
        XCTAssertEqual(LineAcquisition.firstServiceDay(at: GameTime(seconds: 4 * 3_600 - 1)), 0)
        XCTAssertEqual(LineAcquisition.firstServiceDay(at: GameTime(seconds: 4 * 3_600)), 1)
        XCTAssertEqual(LineAcquisition.firstServiceDay(at: GameTime(seconds: 86_400 + 4 * 3_600)), 2)
    }

    /// Free play keeps no accounts: the line is paid for but not booked.
    func testFreePlayBooksNoAsset() throws {
        var world = try world()
        world.setEconomyMode(.free)
        let assets = world.accounts.assets
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 1)
        XCTAssertEqual(world.accounts.assets, assets)
        XCTAssertEqual(world.acquisitions.count, 1)
    }

    // MARK: - Refusals

    /// Each refusal leaves the world as it was.
    func testRefusalsLeaveTheWorldUnchanged() throws {
        let world = try world()
        /// What buying throws after `prepare`, the world left as `prepare`
        /// made it.
        func refusal(after prepare: (inout GameWorld) throws -> Void = { _ in }, _ buy: (inout GameWorld) throws -> Void) -> GameError? {
            var prepared = world
            do { try prepare(&prepared) } catch { XCTFail("\(error)"); return nil }
            var copy = prepared
            do {
                try buy(&copy)
                return nil
            } catch {
                XCTAssertEqual(copy, prepared, "\(error)")
                return error as? GameError
            }
        }
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: LineID(rawValue: 9), realLine: pingxi, dailyRiders: 1) }, .unknownLine(LineID(rawValue: 9)))
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: "", dailyRiders: 1) }, .invalidAcquisition)
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: String(repeating: "x", count: 65), dailyRiders: 1) }, .invalidAcquisition)
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: -1) }, .invalidAcquisition)
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 200_001) }, .invalidAcquisition)
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 100_000) },
                       .insufficientFunds(required: Money(100_000_000_000), available: world.economy.balance))
        XCTAssertEqual(refusal(after: { try $0.setLineRuns(main, to: []) }) {
            try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 1)
        }, .invalidAcquisition, "a line without runs")
        XCTAssertEqual(refusal(after: { try $0.advance(ticks: 75) }) {
            try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 1)
        }, .invalidAcquisition, "a line that has run")
        XCTAssertEqual(refusal(after: { try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 1) }) {
            try $0.recordLineAcquisition(line: main, realLine: "tra:JIJI", dailyRiders: 1)
        }, .lineAlreadyAcquired, "the line")
        XCTAssertEqual(refusal(after: {
            try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 1)
            _ = try $0.createLine(named: "Other", stops: [alpha, gamma])
        }) {
            try $0.recordLineAcquisition(line: LineID(rawValue: 2), realLine: pingxi, dailyRiders: 1)
        }, .lineAlreadyAcquired, "the real line")
    }

    // MARK: - Removing

    /// A bought line removed writes its asset off; the purchase stays, so
    /// the real line cannot be bought again.
    func testRemovingABoughtLineWritesItOff() throws {
        var world = try world()
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)
        try world.removeLine(main)
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .acquiredLine })
        XCTAssertEqual(world.acquisitions.map(\.realLine), [pingxi])
        let other = try world.createLine(named: "Other", stops: [alpha, gamma]).id
        XCTAssertThrowsError(try world.recordLineAcquisition(line: other, realLine: pingxi, dailyRiders: 1))
    }

    /// A bought line that loses its stations, so that it is removed with
    /// them, writes its asset off as removing the line does, and the save
    /// loads: before, the asset named a line that was gone.
    func testABoughtLineRemovedWithItsStationsWritesItOff() throws {
        var world = try world()
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)
        try world.removeStation(beta)
        try world.removeStation(gamma)
        XCTAssertNil(world.line(id: main))
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .acquiredLine })
        XCTAssertEqual(world.acquisitions.map(\.realLine), [pingxi])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    // MARK: - Saving

    /// A world without purchases writes no key; one with them round-trips,
    /// and a hand-made save with a bad purchase is refused.
    func testPurchasesAreSavedAndChecked() throws {
        var world = try world()
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(plain["acquisitions"])
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        func decodes(_ change: (inout [String: Any]) -> Void) -> Bool {
            var edited = object
            change(&edited)
            guard let data = try? JSONSerialization.data(withJSONObject: edited) else { return false }
            return (try? JSONDecoder().decode(GameWorld.self, from: data)) != nil
        }
        let good: [String: Any] = ["realLine": pingxi, "line": 1, "day": 0, "value": 2_000_000]
        XCTAssertTrue(decodes { $0["acquisitions"] = [good] })
        XCTAssertTrue(decodes { $0["acquisitions"] = nil })
        XCTAssertFalse(decodes { $0["acquisitions"] = [] }, "an empty list is not written")
        XCTAssertFalse(decodes { $0["acquisitions"] = [good, good] }, "bought once")
        XCTAssertFalse(decodes { $0["acquisitions"] = [good.merging(["line": 9]) { $1 }] }, "a line ID not handed out")
        XCTAssertFalse(decodes { $0["acquisitions"] = [good.merging(["realLine": ""]) { $1 }] })
        XCTAssertFalse(decodes { $0["acquisitions"] = [good.merging(["day": -1]) { $1 }] })
        XCTAssertFalse(decodes { $0["acquisitions"] = [good.merging(["value": -1]) { $1 }] })
    }

    /// Version 66 (decision 315): Main bought as Pingxi at 05:00 for $20,000
    /// (2 riders) and run to tomorrow's 06:06, its train sent out; it saves byte
    /// for byte and is the world this build makes.
    func testVersionSixtySixKeepsTheLineBought() throws {
        var world = try world()
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)
        try world.advance(ticks: 24 * 60 + 76)

        let url = SavedGameTests.fixtures.appendingPathComponent("v66-line-acquisition.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["LINE_ACQUISITION_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 66)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.acquisition(of: pingxi)?.value, Money(2_000_000))
        XCTAssertNotNil(loaded.train(id: blue)?.execution)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 66,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
