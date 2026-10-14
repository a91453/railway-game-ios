import Foundation
@testable import GameCore
import XCTest

/// Station commerce (ARCHITECTURE decision 222): shops in a station, three
/// levels, taking in from the people through it each day.
final class StationCommerceTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let spare = StationID(rawValue: 4)

    /// `LineAccountsTests`' two lines, A–B and B–C, the people of A and C
    /// going to each other, every trip changing at B; and a station D on
    /// the same track that no line calls at. Managed, with line accounts,
    /// and money for a mall.
    private func build(accounts: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5), ("D", 6)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
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
        world.setEconomyMode(.management)
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        world.economy.earn(Money(2_000_000_000))
        return world
    }

    private func roundTrip(_ world: GameWorld) throws -> GameWorld {
        try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
    }

    private func records(_ world: GameWorld, of station: StationID) -> [AssetRecord] {
        world.accounts.assets.filter { $0.kind == .stationCommerce && $0.owner == station.rawValue }
    }

    // MARK: - The takings

    /// `m × P × H ÷ (P + H)`, whole dollars: the calibration's figures
    /// (`docs/research/STATION_COMMERCE_2026-10-14.md` §2.3).
    func testTakingsNearEachLevelsMost() {
        XCTAssertEqual(StationCommerceLevel.convenienceStore.takings(people: 0), .zero)
        XCTAssertEqual(StationCommerceLevel.convenienceStore.takings(people: 4_000), Money(42_800))
        XCTAssertEqual(StationCommerceLevel.arcade.takings(people: 60_000), Money(450_000))
        XCTAssertEqual(StationCommerceLevel.mall.takings(people: 60_000), Money(1_620_000))
        XCTAssertEqual(StationCommerceLevel.mall.takings(people: 90_000), Money(2_025_000))
        // However many pass, never the level's most.
        for level in StationCommerceLevel.allCases {
            let most = Money(level.centsPerPerson * level.halfPeople)
            XCTAssertLessThan(level.takings(people: StationCommerceDay.maximumPeople), most)
            XCTAssertLessThan(level.takings(people: .max), most, "no overflow")
            XCTAssertEqual(level.takings(people: -5), .zero)
        }
        XCTAssertEqual(StationCommerceLevel.allCases.map(\.price.amount).reduce(0, +), 1_600_000_000)
    }

    // MARK: - Commands

    func testBuildUpgradeAndDemolish() throws {
        var world = try build()
        let before = world.economy.balance
        try world.buildStationCommerce(at: b)
        XCTAssertEqual(world.station(id: b)?.commerce, .convenienceStore)
        XCTAssertEqual(world.economy.balance, before - Money(35_000_000))
        XCTAssertThrowsGameError(try world.buildStationCommerce(at: b), .stationCommerceMaxedOut)
        try world.upgradeStationCommerce(at: b)
        try world.upgradeStationCommerce(at: b)
        XCTAssertEqual(world.station(id: b)?.commerce, .mall)
        XCTAssertEqual(world.economy.balance, before - Money(1_600_000_000))
        XCTAssertEqual(records(world, of: b).map(\.cost.amount), [35_000_000, 315_000_000, 1_250_000_000], "a record a level")
        XCTAssertThrowsGameError(try world.upgradeStationCommerce(at: b), .stationCommerceMaxedOut)
        XCTAssertEqual(try roundTrip(world), world)

        let paid = world.economy.balance
        try world.demolishStationCommerce(at: b)
        XCTAssertNil(world.station(id: b)?.commerce)
        XCTAssertEqual(world.economy.balance, paid, "nothing comes back")
        XCTAssertTrue(records(world, of: b).isEmpty)
        XCTAssertThrowsGameError(try world.demolishStationCommerce(at: b), .noStationCommerce(b))
        XCTAssertThrowsGameError(try world.upgradeStationCommerce(at: b), .noStationCommerce(b))
        XCTAssertThrowsGameError(try world.buildStationCommerce(at: StationID(rawValue: 99)), .unknownStation(StationID(rawValue: 99)))
        XCTAssertEqual(try roundTrip(world), world)
    }

    /// A refused command leaves the world as it was.
    func testWithoutTheMoneyNothingChanges() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: Money(35_000_000 - 1))
        try TestLine(tiles: 7).build(in: &world)
        try TestLine(tiles: 7).buildStation(named: "A", beside: 1, at: 1, in: &world)
        let id = try XCTUnwrap(world.stations.first?.id)
        let before = world
        XCTAssertThrowsError(try world.buildStationCommerce(at: id))
        XCTAssertEqual(world, before)
    }

    /// A depot has no shops, and a station with shops cannot become one.
    func testDepotsHaveNoShops() throws {
        var world = try build()
        try world.setStationDepot(spare, to: true)
        XCTAssertThrowsGameError(try world.buildStationCommerce(at: spare), .stationIsDepot(spare))
        try world.setStationDepot(spare, to: false)
        try world.buildStationCommerce(at: spare)
        XCTAssertThrowsGameError(try world.setStationDepot(spare, to: true), .stationHasCommerce(spare))
        XCTAssertEqual(world.station(id: spare)?.isDepot, false)
    }

    /// Removing a station takes its shops and their records with it.
    func testRemovingAStationTakesItsShops() throws {
        var world = try build()
        try world.buildStationCommerce(at: spare)
        try world.upgradeStationCommerce(at: spare)
        XCTAssertEqual(records(world, of: spare).count, 2)
        try world.removeStation(spare)
        XCTAssertTrue(records(world, of: spare).isEmpty)
        XCTAssertEqual(try roundTrip(world), world, "the save reads back")
    }

    // MARK: - The day

    /// Each midnight one row: the takings of the people through the
    /// station that day, a change counted once, less the upkeep.
    func testAMidnightSettlesTheShops() throws {
        var world = try build()
        try world.buildStationCommerce(at: b)
        try world.buildStationCommerce(at: spare)
        try world.advance(ticks: 1_440 + 10)
        let day = world.dayIndex(of: world.clock.now) - 1
        let flow = try XCTUnwrap(world.stationFlow(b, onDay: day))
        XCTAssertGreaterThan(flow.transferred, 0, "the passengers change at B")
        let atB = world.stationCommerceDay(of: b, onDay: day)
        XCTAssertEqual(atB.people, flow.boarded + flow.alighted - flow.transferred)
        XCTAssertEqual(atB.takings, StationCommerceLevel.convenienceStore.takings(people: atB.people))
        XCTAssertGreaterThan(atB.takings, .zero)
        let atSpare = world.stationCommerceDay(of: spare, onDay: day)
        XCTAssertEqual(atSpare.people, 0, "nobody passes a station no line calls at")
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyStationCommerce })
        XCTAssertEqual(row.breakdown.map(\.amount), [atB.takings, .zero - Money(2 * 6_000)])
        XCTAssertEqual(row.amount, atB.net + atSpare.net)
        XCTAssertEqual(try roundTrip(world), world)
    }

    /// A closed station takes nothing, though those put off there count.
    func testAClosedStationTakesNothing() throws {
        var world = try build()
        try world.buildStationCommerce(at: b)
        try world.advance(ticks: 600)
        try world.setStationOperationMode(b, to: .closed)
        try world.advance(ticks: 1_440)
        let day = world.dayIndex(of: world.clock.now) - 1
        XCTAssertEqual(world.stationCommercePeople(of: b, onDay: day), 0)
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyStationCommerce })
        XCTAssertEqual(row.amount, .zero - Money(6_000), "the upkeep alone")
    }

    /// Without line accounts the shops count twice the station's trips.
    func testWithoutLineAccountsTheTripsCount() throws {
        var world = try build(accounts: false)
        try world.buildStationCommerce(at: a)
        let day = world.dayIndex(of: world.clock.now)
        XCTAssertEqual(world.stationCommercePeople(of: a, onDay: day), 3_000)
        XCTAssertEqual(world.stationCommercePeople(of: b, onDay: day), 0, "B has no trips of its own")
    }

    /// A world without shops writes no row and no new key: as before.
    func testNoShopsNoRow() throws {
        var world = try build()
        try world.advance(ticks: 1_440 + 10)
        XCTAssertFalse(world.accounts.entries.contains { $0.kind == .dailyStationCommerce })
        let json = String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertFalse(json.contains("\"commerce\""))
    }

    // MARK: - Saves

    /// A save with shops written by hand at a depot, or at a level that
    /// does not exist, is refused.
    func testABadSaveIsRefused() throws {
        var world = try build()
        try world.buildStationCommerce(at: spare)
        let good = String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertTrue(good.contains("\"commerce\":1"))
        for bad in [good.replacingOccurrences(of: "\"commerce\":1", with: "\"commerce\":4"),
                    good.replacingOccurrences(of: "\"commerce\":1", with: "\"commerce\":1,\"depot\":true")] {
            XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(bad.utf8)))
        }
    }

    /// Version 57 (decision 222): B with a mall, its changes counted.
    func testVersionFiftySevenKeepsStationCommerce() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v57-station-commerce.json")
        var made = try build()
        try made.buildStationCommerce(at: b)
        try made.upgradeStationCommerce(at: b)
        try made.upgradeStationCommerce(at: b)
        try made.advance(ticks: 1_440 + 20)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["STATION_COMMERCE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 57)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.station(id: b)?.commerce, .mall)
        XCTAssertGreaterThan(world.stationFlow(b, onDay: world.dayIndex(of: world.clock.now) - 1)?.transferred ?? 0, 0)
        var carried = world
        var straight = made
        try carried.advance(ticks: 40)
        try straight.advance(ticks: 40)
        XCTAssertEqual(carried, straight)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 57,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
