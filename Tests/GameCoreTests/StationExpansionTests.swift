import Foundation
@testable import GameCore
import XCTest

/// Station expansion (decision 506): a station holds 4,000 waiting; paid
/// for, once busy enough, 8,000 and then 16,000.
final class StationExpansionTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let d = StationID(rawValue: 4)

    /// `PassengerDemandTests`' corridor: four stations, a line A–B–C with
    /// no train, so whoever is released at A waits there; D on no line.
    /// Money for both expansions.
    private func makeCorridor(busy trips: Int64 = 1_000_000) throws -> GameWorld {
        var world = try makeWorld(width: 20_480, height: 5_120, balance: 100_000)
        for x in [2, 6, 10, 14] {
            try world.buildStation(named: "S\(x)", at: TestLine.centre(x, 2))
        }
        try world.createLine(named: "Line", stops: [a, b, c])
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: trips))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: trips))
        world.setSpeed(.normal)
        world.setEconomyMode(.management)
        // Both expansions and a day's running costs.
        world.economy.earn(StationExpansion.allCases.map(\.price).reduce(Money(100_000_000), +))
        return world
    }

    /// The minutes of the days a station must be full on before it can
    /// expand (decision 534): the corridor's A fills every day.
    private let fullDays = 1_440 * Int(StationExpansion.fullDaysNeeded)

    private func roundTrip(_ world: GameWorld) throws -> GameWorld {
        try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
    }

    private func records(_ world: GameWorld, of station: StationID) -> [AssetRecord] {
        world.accounts.assets.filter { $0.kind == .stationExpansion && $0.owner == station.rawValue }
    }

    // MARK: - The steps

    func testEachStepDoublesTheRoom() {
        XCTAssertEqual(StationPassengers.capacity, 4_000)
        XCTAssertEqual(StationExpansion.allCases.map(\.capacity), [8_000, 16_000])
        XCTAssertEqual(StationPassengers.maximumCapacity, 16_000)
        XCTAssertEqual(StationExpansion.first, .concourse)
        XCTAssertEqual(StationExpansion.concourse.next, .hall)
        XCTAssertNil(StationExpansion.hall.next)
        XCTAssertLessThan(StationExpansion.concourse.threshold, StationExpansion.hall.threshold)
        XCTAssertLessThan(StationExpansion.concourse.price, StationExpansion.hall.price)
    }

    // MARK: - Commands

    /// Not before the station is busy enough; then a step at a time, each
    /// paid and kept as an asset, up to the second.
    func testExpandingOnceBusyEnough() throws {
        var world = try makeCorridor()
        XCTAssertEqual(world.stationCapacity(of: a), 4_000)
        XCTAssertEqual(world.nextStationExpansion(of: a), .concourse)
        // No day behind it yet.
        XCTAssertThrowsGameError(try world.expandStation(at: a),
            .stationTooQuietToExpand(needed: StationExpansion.concourse.threshold))
        try world.advance(ticks: fullDays)
        XCTAssertGreaterThanOrEqual(world.stationExpansionPeople(of: a), StationExpansion.hall.threshold)
        let before = world.economy.balance
        try world.expandStation(at: a)
        XCTAssertEqual(world.station(id: a)?.expansion, .concourse)
        XCTAssertEqual(world.stationCapacity(of: a), 8_000)
        XCTAssertEqual(world.economy.balance, before - StationExpansion.concourse.price)
        try world.expandStation(at: a)
        XCTAssertEqual(world.station(id: a)?.expansion, .hall)
        XCTAssertEqual(world.stationCapacity(of: a), 16_000)
        XCTAssertNil(world.nextStationExpansion(of: a))
        XCTAssertEqual(records(world, of: a).map(\.cost), StationExpansion.allCases.map(\.price), "a record a step")
        XCTAssertEqual(records(world, of: a).first.map { $0.kind.assetClass }, .stations)
        XCTAssertThrowsGameError(try world.expandStation(at: a), .stationExpansionMaxedOut)
        XCTAssertThrowsGameError(try world.expandStation(at: StationID(rawValue: 99)), .unknownStation(StationID(rawValue: 99)))
        XCTAssertEqual(try roundTrip(world), world)
    }

    /// A quiet station stays as it is, and a refused command changes
    /// nothing.
    func testAQuietStationOrNoMoneyChangesNothing() throws {
        var world = try makeCorridor(busy: StationExpansion.concourse.threshold / 4)
        try world.advance(ticks: 1_440)
        XCTAssertLessThan(world.stationExpansionPeople(of: a), StationExpansion.concourse.threshold)
        var before = world
        XCTAssertThrowsGameError(try world.expandStation(at: a), .stationTooQuietToExpand(needed: StationExpansion.concourse.threshold))
        XCTAssertEqual(world, before)

        world = try makeCorridor()
        try world.advance(ticks: fullDays)
        try world.economy.spend(world.economy.balance - StationExpansion.concourse.price + Money(100))
        before = world
        XCTAssertThrowsError(try world.expandStation(at: a))
        XCTAssertEqual(world, before)
    }

    /// A busy station must have turned passengers away for want of room
    /// on 4 of the last 7 days, today included (decision 534; decision 506
    /// took one day, and a new game's one peak opened it). A save keeps
    /// the full days and rejects ones no count backs, still to come, or
    /// not ending on the last full day.
    func testOnlyAStationOftenFullLatelyExpands() throws {
        XCTAssertEqual(StationExpansion.fullDaysWindow, 7)
        XCTAssertEqual(StationExpansion.fullDaysNeeded, 4)
        var world = try makeCorridor()
        try world.advance(ticks: 1_440)
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        var today = world.clock.now.seconds / 86_400
        XCTAssertEqual(world.passengers[index].lastFullDay, today - 1, "A was full yesterday morning (no one comes at midnight)")
        XCTAssertEqual(world.passengers[index].fullDays, 1)
        XCTAssertEqual(world.stationFullDays(of: a), 1)
        XCTAssertFalse(world.stationWasFullLately(a), "one full day is a peak, not often")
        XCTAssertThrowsGameError(try world.expandStation(at: a), .stationNotFullToExpand)

        try world.advance(ticks: 1_440 * 3)
        today = world.clock.now.seconds / 86_400
        XCTAssertEqual(world.passengers[index].fullDays, 0b1111, "four days in a row")
        XCTAssertEqual(world.stationFullDays(of: a), 4)
        XCTAssertTrue(world.stationWasFullLately(a))
        XCTAssertEqual(try roundTrip(world), world, "a save keeps the full days")

        // Full on days 0, 1 and 3, not 2: three of the last seven.
        world.passengers[index].fullDays = 0b1011
        XCTAssertEqual(world.stationFullDays(of: a), 3)
        let before = world
        XCTAssertThrowsGameError(try world.expandStation(at: a), .stationNotFullToExpand)
        XCTAssertEqual(world, before)
        // Four, but the first falls out of the seven days once it is old.
        world.passengers[index].fullDays = 0b1111
        world.passengers[index].lastFullDay = today - 3
        XCTAssertEqual(world.stationFullDays(of: a), 4, "days − 6 to − 3 are within the seven")
        world.passengers[index].lastFullDay = today - 4
        XCTAssertEqual(world.stationFullDays(of: a), 3, "day − 7 is not")
        world.passengers[index].lastFullDay = today - 1
        try world.expandStation(at: a)
        XCTAssertEqual(world.station(id: a)?.expansion, .concourse)

        world.passengers[index].lastFullDay = today + 1
        XCTAssertThrowsError(try roundTrip(world), "a full day still to come")
        world.passengers[index].lastFullDay = today - 1
        world.passengers[index].fullDays = 0b1110
        XCTAssertThrowsError(try roundTrip(world), "full days not ending on the last one")
        world.passengers[index].fullDays = 1 << StationPassengers.fullDaysKept | 1
        XCTAssertThrowsError(try roundTrip(world), "more days than are kept")
        var empty = try makeCorridor()
        try empty.advance(ticks: 1)
        let quiet = try XCTUnwrap(empty.passengers.firstIndex { $0.overflowed == 0 })
        empty.passengers[quiet].lastFullDay = 0
        empty.passengers[quiet].fullDays = 1
        XCTAssertThrowsError(try roundTrip(empty), "a full day with no one turned away")
        empty.passengers[quiet].lastFullDay = nil
        empty.passengers[quiet].fullDays = 0b11
        XCTAssertThrowsError(try roundTrip(empty), "full days with no last full day")
    }

    /// The days kept move with the last full day: a gap shifts them, a gap
    /// longer than the days kept forgets them, and the same day is counted
    /// once (decision 534).
    func testTheFullDaysMoveForward() {
        var record = StationPassengers(station: a)
        XCTAssertEqual(record.fullDayCount(endingOn: 10, window: 7), 0)
        record.markFull(on: 10)
        record.markFull(on: 10)
        XCTAssertEqual(record.fullDays, 1)
        record.markFull(on: 12)
        XCTAssertEqual(record.fullDays, 0b101)
        XCTAssertEqual(record.lastFullDay, 12)
        XCTAssertEqual(record.fullDayCount(endingOn: 12, window: 7), 2)
        XCTAssertEqual(record.fullDayCount(endingOn: 16, window: 7), 2, "day 10 is the seventh day ending on 16")
        XCTAssertEqual(record.fullDayCount(endingOn: 17, window: 7), 1)
        XCTAssertEqual(record.fullDayCount(endingOn: 11, window: 7), 0, "asked before its last full day, it counts none")
        record.markFull(on: 9)
        XCTAssertEqual(record.lastFullDay, 12, "days only move forward")
        record.markFull(on: 18)
        XCTAssertEqual(record.fullDays, 0b100_0001, "day 10 falls past the eight days kept, day 12 does not")
        XCTAssertEqual(record.fullDayCount(endingOn: 18, window: 7), 2)
        record.markFull(on: 19)
        XCTAssertEqual(record.fullDays, 0b1000_0011)
        record.markFull(on: 40)
        XCTAssertEqual(record.fullDays, 1, "a gap of more than eight days forgets the rest")
    }

    /// A depot is never expanded, and an expanded station cannot become
    /// one; taking the station down takes its expansions off the books.
    func testDepotsAndRemoval() throws {
        var world = try makeCorridor()
        try world.setStationDepot(d, to: true)
        XCTAssertNil(world.nextStationExpansion(of: d))
        XCTAssertThrowsGameError(try world.expandStation(at: d), .stationIsDepot(d))
        try world.advance(ticks: fullDays)
        try world.expandStation(at: a)
        XCTAssertFalse(records(world, of: a).isEmpty)
        try world.removeLine(try XCTUnwrap(world.lines.first?.id))
        XCTAssertThrowsGameError(try world.setStationDepot(a, to: true), .stationIsExpanded(a))
        try world.removeStation(a)
        XCTAssertTrue(records(world, of: a).isEmpty)
        XCTAssertNil(world.assetsProblem())
    }

    // MARK: - The room

    /// An expanded station lets twice, then four times, as many wait
    /// before turning the rest away.
    func testAnExpandedStationHoldsMore() throws {
        var world = try makeCorridor()
        // To the morning peak of day 1, when an hour brings more than the
        // largest station holds.
        try world.advance(ticks: fullDays + 8 * 60)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 4_000)
        try world.expandStation(at: a)
        try world.advance(ticks: 60)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 8_000)
        try world.expandStation(at: a)
        try world.advance(ticks: 60)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 16_000)
        XCTAssertEqual(world.passengerLedger(of: b).waiting, 4_000, "B is not expanded")
        let ledger = world.passengerLedger(of: a)
        XCTAssertEqual(ledger.released, ledger.waiting + ledger.overflowed + ledger.abandoned)
        XCTAssertEqual(try roundTrip(world), world, "a save keeps the 16,000")
    }

    /// The platform's part of the crowd at the doors is the waiting over
    /// what that station holds.
    func testTheCrowdAtTheDoorsIsOverWhatTheStationHolds() {
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 100, waiting: 4_000), 1_000)
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 100, waiting: 4_000, holds: 8_000), 500)
        XCTAssertEqual(DoorCrowding.crowd(riders: 0, rated: 100, waiting: 16_000, holds: 16_000), 1_000)
    }

    // MARK: - Saves

    /// A save says how far a station is expanded; one that says a depot
    /// is, or that more wait than the station holds, does not load.
    func testASaveHoldsTheStationToItsRoom() throws {
        var world = try makeCorridor()
        try world.advance(ticks: fullDays + 8 * 60)
        try world.expandStation(at: a)
        try world.advance(ticks: 60)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""expansion":1"#))
        XCTAssertEqual(text.components(separatedBy: #""expansion""#).count - 1, 1, "only the expanded station says so")
        // Taking the expansion off leaves 8,000 waiting where 4,000 fit.
        let stripped = text.replacingOccurrences(of: #","expansion":1"#, with: "").replacingOccurrences(of: #""expansion":1,"#, with: "")
        XCTAssertNotEqual(stripped, text)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 8_000)
        text = stripped
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(text.utf8)))
    }

    func testVersionSeventyEightKeepsTheExpansion() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v78-station-expansion.json")
        // Made under decision 506's rule, one full day: decision 534 asks
        // for more, so the steps are taken as the command takes them.
        var made = try makeCorridor()
        try made.advance(ticks: 1_440 + 8 * 60)
        let index = try XCTUnwrap(made.stations.firstIndex { $0.id == a })
        for step in StationExpansion.allCases {
            try made.economy.spend(step.price)
            made.setStationExpansion(step, at: index)
            made.acquireAsset(.stationExpansion, owner: a.rawValue, cost: step.price)
        }
        try made.advance(ticks: 60)
        // A save before decision 534 knows only the last full day.
        for record in made.passengers.indices where made.passengers[record].lastFullDay != nil {
            made.passengers[record].fullDays = 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["STATION_EXPANSION_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 78)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertEqual(loaded.station(id: a)?.expansion, .hall)
        XCTAssertEqual(loaded.passengerLedger(of: a).waiting, 16_000)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 78,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
