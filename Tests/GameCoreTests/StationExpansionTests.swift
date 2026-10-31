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
        world.economy.earn(StationExpansion.allCases.map(\.price).reduce(.zero, +))
        return world
    }

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
        try world.advance(ticks: 1_440)
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
        try world.advance(ticks: 1_440)
        try world.economy.spend(world.economy.balance - StationExpansion.concourse.price + Money(1))
        before = world
        XCTAssertThrowsError(try world.expandStation(at: a))
        XCTAssertEqual(world, before)
    }

    /// A depot is never expanded, and an expanded station cannot become
    /// one; taking the station down takes its expansions off the books.
    func testDepotsAndRemoval() throws {
        var world = try makeCorridor()
        try world.setStationDepot(d, to: true)
        XCTAssertNil(world.nextStationExpansion(of: d))
        XCTAssertThrowsGameError(try world.expandStation(at: d), .stationIsDepot(d))
        try world.advance(ticks: 1_440)
        try world.expandStation(at: a)
        XCTAssertThrowsGameError(try world.setStationDepot(a, to: true), .stationIsExpanded(a))
        XCTAssertFalse(records(world, of: a).isEmpty)
        try world.removeLine(try XCTUnwrap(world.lines.first?.id))
        try world.removeStation(a)
        XCTAssertTrue(records(world, of: a).isEmpty)
        XCTAssertNil(world.assetsProblem())
    }

    // MARK: - The room

    /// An expanded station lets twice, then four times, as many wait
    /// before turning the rest away.
    func testAnExpandedStationHoldsMore() throws {
        var world = try makeCorridor()
        try world.advance(ticks: 1_440)
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
        try world.advance(ticks: 1_440)
        try world.expandStation(at: a)
        try world.advance(ticks: 60)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""expansion":1"#))
        XCTAssertEqual(text.components(separatedBy: #""expansion""#).count - 1, 1, "only the expanded station says so")
        // Taking the expansion off leaves 8,000 waiting where 4,000 fit.
        text = text.replacingOccurrences(of: #","expansion":1"#, with: "")
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(text.utf8)))
    }

    func testVersionSeventyEightKeepsTheExpansion() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v78-station-expansion.json")
        var made = try makeCorridor()
        try made.advance(ticks: 1_440)
        try made.expandStation(at: a)
        try made.expandStation(at: a)
        try made.advance(ticks: 60)
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
