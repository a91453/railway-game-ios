import Foundation
@testable import GameCore
import XCTest

/// Line accounts (ARCHITECTURE decision 179): each line's records add up to
/// the company's books, day by day.
final class LineAccountsTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let first = LineID(rawValue: 1)
    private let second = LineID(rawValue: 2)

    /// `PassengerTransferTests`' two lines, A–B and B–C, with the people of
    /// A and C going to each other: every trip changes at B.
    private func build(accounts: Bool = true, managed: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        try world.createLine(named: "First", stops: [a, b])
        try world.createLine(named: "Second", stops: [b, c])
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: track.at(1, facingEast: true))
        try world.placeTrain(two, at: track.at(3, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_500))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 1_500))
        world.setPassengerRoutingMode(.network)
        if managed { world.setEconomyMode(.management) }
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        return world
    }

    private func days(_ world: GameWorld) -> [Int64] {
        world.accounts.days.map(\.day)
    }

    /// The invariant: on every settled day, the lines' fares, operating,
    /// maintenance, energy and staff cost add up to the company's.
    func testLinesAddUpToTheCompanyEachDay() throws {
        var world = try build()
        try world.advance(ticks: 3 * 1_440 + 30)
        let settled = days(world).filter { $0 < world.dayIndex(of: world.clock.now) }
        XCTAssertEqual(settled.count, 3)
        var sawFares = false
        for day in settled {
            let company = try XCTUnwrap(world.accounts.days.first { $0.day == day })
            let tallies = [first, second].compactMap { id in world.lineDays(id).first { $0.day == day }?.tally }
            func sum(_ value: (LineTally) -> Money) -> Money { tallies.reduce(.zero) { $0 + value($1) } }
            XCTAssertEqual(sum(\.fareRevenue), company.fareRevenue, "fares, day \(day)")
            XCTAssertEqual(sum(\.operatingCost), company.operatingCost, "operating, day \(day)")
            XCTAssertEqual(sum(\.maintenanceCost), company.maintenanceCost, "maintenance, day \(day)")
            XCTAssertEqual(sum(\.energyCost), company.energyCost, "energy, day \(day)")
            XCTAssertEqual(sum(\.staffCost), company.staffCost, "staff, day \(day)")
            sawFares = sawFares || company.fareRevenue > .zero
        }
        XCTAssertTrue(sawFares, "the scenario earns fares")
    }

    /// A passenger who changes at B rides both lines, and pays both.
    func testATransferRidesAndPaysBothLines() throws {
        var world = try build()
        try world.advance(ticks: 2 * 1_440)
        let one = world.lineDays(first).reduce(LineTally()) { var t = $0; t.add($1.tally); return t }
        let two = world.lineDays(second).reduce(LineTally()) { var t = $0; t.add($1.tally); return t }
        XCTAssertGreaterThan(one.boardings, 0)
        XCTAssertGreaterThan(two.boardings, 0)
        XCTAssertGreaterThan(one.fareRevenue, .zero)
        XCTAssertGreaterThan(two.fareRevenue, .zero)
        XCTAssertGreaterThan(one.departures, 0)
        XCTAssertGreaterThan(one.trainDistance, 0)
        XCTAssertTrue((1...1_000).contains(one.peakLoad), "\(one.peakLoad)")
        XCTAssertEqual(one.deadheadDistance, 0)
        XCTAssertEqual(one.profit, one.fareRevenue - one.totalCost)
    }

    func testStationFlowsOfYesterday() throws {
        var world = try build()
        try world.advance(ticks: 1_440 + 600)
        let at = world.stationFlowYesterday(a)
        XCTAssertGreaterThan(at.boarded, 0)
        let atB = world.stationFlowYesterday(b)
        XCTAssertGreaterThan(atB.alighted, 0)
        XCTAssertGreaterThan(atB.boarded, 0)
        XCTAssertEqual(world.stationFlowYesterday(StationID(rawValue: 99)).boarded, 0)
    }

    func testOnlyAManagedCompanyWithTheSwitchRecords() throws {
        var free = try build(managed: false)
        try free.advance(ticks: 1_500)
        XCTAssertEqual(free.lineAccounts?.lines.flatMap(\.days), [])
        XCTAssertEqual(free.lineAccounts?.flows, [])
        var off = try build(accounts: false)
        try off.advance(ticks: 1_500)
        XCTAssertNil(off.lineAccounts)
        XCTAssertEqual(off.lineDays(first), [])
        XCTAssertNil(off.lineYesterday(first))
    }

    func testBatchMatchesMinuteStepsAndSavesRoundTrip() throws {
        var batched = try build()
        var stepped = batched
        try batched.advance(ticks: 1_500)
        for _ in 0..<1_500 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        XCTAssertNotNil(loaded.lineAccounts)
        XCTAssertEqual(loaded.lineAccounts?.lines.count, 2)
    }

    /// A line's records go with it; the other's stay, and add up to what
    /// they were.
    func testRemovingALineDropsItsRecords() throws {
        var world = try build()
        try world.advance(ticks: 1_500)
        let kept = world.lineDays(second)
        XCTAssertFalse(world.lineDays(first).isEmpty)
        try world.removeLine(first)
        XCTAssertEqual(world.lineDays(first), [])
        XCTAssertEqual(world.lineDays(second), kept)
        XCTAssertEqual(world.lineAccounts?.lines.map(\.line), [second])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// Removing a station takes the line records of a line it leaves with
    /// one stop, and its own flows: otherwise the world saved next would
    /// not load.
    func testRemovingAStationLeavesNoRecordsOfIt() throws {
        for station in [a, c] {
            var world = try build()
            try world.advance(ticks: 1_500)
            XCTAssertGreaterThan(world.stationFlowYesterday(station).boarded + world.stationFlowYesterday(station).alighted, 0)
            for train in world.trains.map(\.id) {
                try? world.stopTrainService(train)
                try world.unassignTrain(train)
                try world.unplaceTrain(train)
            }
            try world.removeStation(station)
            XCTAssertEqual(world.stationFlowYesterday(station).boarded, 0)
            XCTAssertNil(world.lineAccounts?.flows.first { $0.station == station })
            let ids = Set(world.lines.map(\.id))
            XCTAssertTrue(world.lineAccounts?.lines.allSatisfy { ids.contains($0.line) } ?? false)
            XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "station \(station)")
        }
    }

    func testOnlyThirtyDaysAreKept() throws {
        var world = try build()
        try world.advance(ticks: 31 * 1_440)
        let recorded = world.lineDays(first)
        XCTAssertEqual(recorded.count, LineAccounts.keptDays)
        XCTAssertEqual(recorded.map(\.day), recorded.map(\.day).sorted())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testApportionmentAddsUpExactly() {
        for total in [0, 1, 7, 100, 12_345] as [Int64] {
            for weights in [[1, 1, 1], [5, 0, 3], [1_000_000_000_000, 3, 7], [0, 0], [2, 3]] as [[Int64]] {
                let shares = LineAccounts.apportion(total, by: weights)
                XCTAssertEqual(shares.count, weights.count)
                let expected: Int64 = weights.reduce(0, +) == 0 ? 0 : total
                XCTAssertEqual(shares.reduce(0, +), expected, "\(total) by \(weights)")
                XCTAssertTrue(zip(shares, weights).allSatisfy { $1 > 0 || $0 == 0 })
            }
        }
        XCTAssertEqual(LineAccounts.apportion(10, by: [1, 1, 1]), [4, 3, 3])
    }

    func testARecordForAMissingLineIsRefused() throws {
        var world = try build()
        try world.advance(ticks: 1_500)
        var book = try XCTUnwrap(world.lineAccounts)
        XCTAssertTrue(book.isValid(lines: [first, second], stations: [a, b, c]))
        XCTAssertFalse(book.isValid(lines: [first], stations: [a, b, c]))
        book.lines[0].pending.boardings = -1
        XCTAssertFalse(book.isValid(lines: [first, second], stations: [a, b, c]))
    }

    /// A save of version 48: two lines on a transfer network, managed, run a
    /// day and a few minutes, so that each has a day of records, the fares
    /// of the hour in progress and the stations' flows. It saves byte for
    /// byte and is the world this build makes.
    func testVersionFortyEightKeepsLineAccounts() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v48-line-accounts.json")
        var made = try build()
        try made.advance(ticks: 1_500 + 20)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["LINE_ACCOUNTS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 48)
        XCTAssertNotNil((object["world"] as? [String: Any])?["lineAccounts"])
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        // Decision 222 counts the changes at B, which version 48 did not.
        XCTAssertEqual(world, Self.withoutChanges(made))
        XCTAssertEqual(world.lineAccounts?.lines.count, 2)
        XCTAssertFalse(world.lineDays(first).isEmpty)
        // It goes on to be the same world as one that never was saved.
        var carried = world
        var straight = made
        try carried.advance(ticks: 40)
        try straight.advance(ticks: 40)
        XCTAssertEqual(Self.withoutChanges(carried), Self.withoutChanges(straight))
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 48,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    /// `world` with no changes counted at its stations (decision 222), and
    /// no trip log (decision 223).
    private static func withoutChanges(_ world: GameWorld) -> GameWorld {
        var world = world
        world.tripLog = []
        let flows: [StationFlowDay] = (world.lineAccounts?.flows ?? []).map { flow in
            var flow = flow
            flow.transferred = 0
            return flow
        }
        world.lineAccounts?.flows = flows
        return world
    }

    /// Decision 222: each passenger changing at B is counted there once as
    /// a change, and got off and on there.
    func testChangesAreCountedWhereTheyWait() throws {
        var world = try build()
        try world.advance(ticks: 1_440 + 600)
        let yesterday = world.dayIndex(of: world.clock.now) - 1
        let atB = try XCTUnwrap(world.stationFlow(b, onDay: yesterday))
        XCTAssertGreaterThan(atB.transferred, 0)
        XCTAssertLessThanOrEqual(atB.transferred, atB.alighted)
        XCTAssertEqual(atB.people, atB.boarded + atB.alighted - atB.transferred)
        XCTAssertEqual(world.stationFlow(a, onDay: yesterday)?.transferred, 0, "nobody changes at an end")
    }

    /// A world from before the accounts has none, and records nothing.
    func testAnOlderSaveHasNoLineAccounts() throws {
        let old = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v45-flex-dispatch.json")))
        XCTAssertNil(old.world.lineAccounts)
        var world = old.world
        try world.advance(ticks: 10)
        XCTAssertNil(world.lineAccounts)
    }
}
