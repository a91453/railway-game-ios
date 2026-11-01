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
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: fixtureEconomy(balance: balance, costs: testCosts))
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

    /// Bought at 05:00, the line pays NT$30,000 for each of its 2 riders, books
    /// it as an asset, and runs from the next day: the run out does not go
    /// at 06:10 today, and goes at 06:10 tomorrow.
    func testABoughtLineIsPaidForAndRunsFromTheNextDay() throws {
        var world = try world()
        let before = world.economy.balance
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)

        XCTAssertEqual(world.economy.balance, before - Money(6_000_000))
        XCTAssertEqual(world.acquisitions, [LineAcquisition(realLine: pingxi, line: main, day: 0, value: Money(6_000_000))])
        XCTAssertEqual(world.acquisition(of: pingxi)?.line, main)
        XCTAssertNil(world.acquisition(of: "tra:JIJI"))
        let asset = try XCTUnwrap(world.accounts.assets.last)
        XCTAssertEqual(asset.kind, .acquiredLine)
        XCTAssertEqual(asset.owner, main.rawValue)
        XCTAssertEqual(asset.cost, Money(6_000_000))
        XCTAssertEqual(world.line(id: main)?.runDays, [0])

        // 06:10 today: not sent.
        try world.advance(ticks: 80)
        XCTAssertNil(world.train(id: blue)?.execution)
        // 06:06 tomorrow: sent for the run out.
        try world.advance(ticks: 24 * 60 - 4)
        XCTAssertNotNil(world.train(id: blue)?.execution)
        XCTAssertEqual(world.line(id: main)?.runDays, [1])
    }

    /// Decision 400 (10j-3): a metro line's riders cost its tier's value
    /// each (NT$300, a light rail's NT$210), recorded as the value paid; a
    /// purchase without a tier is a branch line's, NT$30,000 a rider.
    func testABoughtLinesRidersCostItsTiersValue() throws {
        XCTAssertEqual(LineAcquisition.value(ofDailyRiders: 3), Money(9_000_000))
        XCTAssertEqual(LineAcquisition.value(ofDailyRiders: 3, tier: .branch), Money(9_000_000))
        XCTAssertEqual(LineAcquisition.value(ofDailyRiders: 3, tier: .lightRail), Money(63_000))
        XCTAssertEqual(LineAcquisition.value(ofDailyRiders: 3, tier: .metro), Money(90_000))
        var world = try world(balance: Money(1_000_000_000_000_000))
        let before = world.economy.balance
        try world.recordLineAcquisition(line: main, realLine: "trtc:R_XBT", dailyRiders: LineAcquisition.maximumDailyRiders, tier: .metro)
        let value = Money(60_000_000_000)
        XCTAssertEqual(world.economy.balance, before - value)
        XCTAssertEqual(world.acquisitions.first?.value, value)
        XCTAssertEqual(world.accounts.assets.last?.cost, value)
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
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2_000_001) }, .invalidAcquisition)
        XCTAssertEqual(refusal { try $0.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 100_000) },
                       .insufficientFunds(required: Money(300_000_000_000), available: world.economy.balance))
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

    /// A bought line removed writes its asset off and drops its purchase,
    /// so the real line can be bought again (decision 528), paid for
    /// again.
    func testRemovingABoughtLineWritesItOffAndPutsItOnSaleAgain() throws {
        var world = try world(balance: 100_000_000)
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)
        try world.removeLine(main)
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .acquiredLine })
        XCTAssertEqual(world.acquisitions, [])
        XCTAssertNil(world.acquisition(of: pingxi))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        let other = try world.createLine(named: "Other", stops: [alpha, gamma]).id
        try world.setLineRuns(other, to: [LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_800, departure: 22_800)])])
        let balance = world.economy.balance
        try world.recordLineAcquisition(line: other, realLine: pingxi, dailyRiders: 2)
        XCTAssertEqual(world.acquisition(of: pingxi)?.line, other)
        XCTAssertEqual(world.economy.balance, balance - LineAcquisition.value(ofDailyRiders: 2))
    }

    /// Decision 528: a save from before it, holding the purchase of a line
    /// since removed, loads without it, so the real line is on sale again.
    func testASavedPurchaseOfARemovedLineIsDropped() throws {
        var world = try world()
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2)
        let bought = try XCTUnwrap(world.acquisitions.first)
        try world.removeLine(main)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        object["acquisitions"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([bought]))
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(loaded.acquisitions, [])
        XCTAssertEqual(loaded, world)
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
        XCTAssertEqual(world.acquisitions, [], "decision 528: on sale again")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// Decision 528: a purchase keeps the track it laid; the line removed
    /// leaves what of it stands, which the same real line bought again
    /// forgets. The track left saves and loads.
    func testABoughtLineRemovedLeavesItsTrack() throws {
        var world = try world(balance: 100_000_000)
        let laid = world.network.edges.map(\.id)
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2, track: laid)
        XCTAssertEqual(world.acquisition(of: pingxi)?.track, laid)
        XCTAssertEqual(world.trackLeft(by: pingxi), [], "nothing left while it runs")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        try world.removeLine(main)
        XCTAssertEqual(world.leftTrack, [LeftTrack(realLine: pingxi, edges: laid)])
        XCTAssertEqual(world.trackLeft(by: pingxi), laid)
        XCTAssertEqual(world.trackLeft(by: "tra:JIJI"), [])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        // An edge taken up is no longer left.
        let free = try XCTUnwrap(laid.last)
        for platform in world.network.platforms(on: free) {
            try world.removeTrackPlatform(platform.station, on: free, from: platform.start)
        }
        try world.removeTrackEdge(free)
        XCTAssertEqual(world.trackLeft(by: pingxi), laid.filter { $0 != free })
        // Bought again, the track it left is forgotten.
        let other = try world.createLine(named: "Other", stops: [alpha, beta]).id
        try world.setLineRuns(other, to: [LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_500, departure: 22_500)])])
        try world.recordLineAcquisition(line: other, realLine: pingxi, dailyRiders: 2)
        XCTAssertEqual(world.leftTrack, [])
        XCTAssertEqual(world.trackLeft(by: pingxi), [])
    }

    /// A purchase naming track that is not there, or an edge twice, is
    /// refused and changes nothing.
    func testAPurchaseWithTrackNotThereIsRefused() throws {
        var world = try world()
        let before = world
        let edge = try XCTUnwrap(world.network.edges.first?.id)
        XCTAssertThrowsGameError(try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2, track: [.edge(999)]), .invalidAcquisition)
        XCTAssertThrowsGameError(try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2, track: [edge, edge]), .invalidAcquisition)
        XCTAssertThrowsGameError(try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2, track: []), .invalidAcquisition)
        XCTAssertEqual(world, before)
    }

    /// A hand-made save with bad track left is refused.
    func testTrackLeftIsChecked() throws {
        var world = try world(balance: 100_000_000)
        let laid = world.network.edges.map(\.id)
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2, track: laid)
        try world.removeLine(main)
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["leftTrack"])
        func decodes(_ change: (inout [String: Any]) -> Void) -> Bool {
            var edited = object
            change(&edited)
            guard let data = try? JSONSerialization.data(withJSONObject: edited) else { return false }
            return (try? JSONDecoder().decode(GameWorld.self, from: data)) != nil
        }
        let good: [String: Any] = ["realLine": pingxi, "edges": [(laid[0].networkNumber ?? -1)]]
        XCTAssertTrue(decodes { $0["leftTrack"] = [good] })
        XCTAssertTrue(decodes { $0["leftTrack"] = nil })
        XCTAssertFalse(decodes { $0["leftTrack"] = [] }, "an empty list is not written")
        XCTAssertFalse(decodes { $0["leftTrack"] = [good, good] }, "a line leaves track once")
        XCTAssertFalse(decodes { $0["leftTrack"] = [good.merging(["edges": []]) { $1 }] })
        XCTAssertFalse(decodes { $0["leftTrack"] = [good.merging(["edges": [(laid[0].networkNumber ?? -1), (laid[0].networkNumber ?? -1)]]) { $1 }] })
        XCTAssertFalse(decodes { $0["leftTrack"] = [good.merging(["edges": [9_999]]) { $1 }] }, "an edge not handed out")
        XCTAssertFalse(decodes { $0["leftTrack"] = [good.merging(["realLine": ""]) { $1 }] })
    }

    /// Version 79 (decision 528): Main bought as Pingxi with the track it
    /// laid, then removed, leaving that track; it saves byte for byte and
    /// is the world this build makes.
    func testVersionSeventyNineKeepsTheTrackLeft() throws {
        var world = try world(balance: 100_000_000)
        try world.recordLineAcquisition(line: main, realLine: pingxi, dailyRiders: 2, track: world.network.edges.map(\.id))
        try world.removeLine(main)
        try world.advance(ticks: 60)

        let url = SavedGameTests.fixtures.appendingPathComponent("v79-track-left.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TRACK_LEFT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 79)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.trackLeft(by: pingxi).count, 6)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 79,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
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

    /// Version 66 (decision 315): Main bought as Pingxi at 05:00 for $20,000 (NT$60,000)
    /// (2 riders) and run to tomorrow's 06:06, its train sent out; it saves byte
    /// for byte and is the world this build makes.
    func testVersionSixtySixKeepsTheLineBought() throws {
        var world = try NTScale.$factor.withValue(3) { try world() }
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
        try XCTAssertSameButRounding(loaded, world, cents: 2_500)
        XCTAssertEqual(loaded.acquisition(of: pingxi)?.value, Money(6_000_000))
        XCTAssertNotNil(loaded.train(id: blue)?.execution)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(newTaiwanDollars(ofSaveText: String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 66,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#)).utf8))
    }
}
