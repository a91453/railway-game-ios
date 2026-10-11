import Foundation
@testable import GameCore
import XCTest

/// Freight (ARCHITECTURE decision 155): industry makes cargo at a station's
/// freight facility, the trains of a freight line carry it to the next
/// facility and are paid by the ton and the kilometre.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class FreightTests: XCTestCase {
    private let track = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 2)
    private let main = LineID(rawValue: 1)
    private let blue = TrainID(rawValue: 1)
    /// The line plans with a crawl at 1 km/h, about a link a minute, as the
    /// dispatch tests' lines do (Stage W2c): four links take four minutes.
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    /// Alpha and Gamma on a straight track four links (64 m) apart, a
    /// factory of `jobs` jobs by Alpha (the cell at row 0, column 0, nearer
    /// it) and none by Gamma, a managed company, freight on, a yard at each,
    /// the line Goods between them as a freight line, and `trains` one-car
    /// trains on it, at Alpha.
    private func world(jobs: Int64 = 100, yards: Bool = true, freightLine: Bool = true, trains: Int = 1,
                       mode: EconomyMode = .management) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts)
        )
        try track.build(in: &world)
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.setLand([LandCell(row: 0, column: 0, use: .industrial, residents: 0, jobs: jobs)])
        world.setEconomyMode(mode)
        world.enableFreight()
        if yards {
            try world.buildFreightFacility(at: alpha)
            try world.buildFreightFacility(at: gamma)
        }
        try world.createLine(named: "Goods", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .allDay)
        if freightLine { try world.setLineFreight(main, to: true) }
        try world.setLineTrainsInService(main, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
        for index in 0..<trains {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: track.at(1, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1_024)
            try world.assignTrain(train.id, to: main)
        }
        world.setSpeed(.normal)
        return world
    }

    private func hours(_ count: Int, _ world: inout GameWorld) throws {
        try world.advance(ticks: 60 * count)
    }

    // MARK: - The rules

    func testFareIsTonsByKilometresAtFiveDollars() {
        // 40 t over 10 km: 400 t-km at $5 is $2,000.
        XCTAssertEqual(Freight.fare(tons: 40, distance: 10_000 * WorldCoordinate.unitsPerMetre), Money(200_000))
        // 40 t over 64 m: 1,280 cents, to the nearest dollar $13.
        XCTAssertEqual(Freight.fare(tons: 40, distance: 4_096), Money(1_300))
        // 1 t over 64 m: 32 cents, which is under half a dollar.
        XCTAssertEqual(Freight.fare(tons: 1, distance: 4_096), Money(0))
    }

    /// 100 jobs make 100 × 0.5 = 50 t a day: 2,083 thousandths of a ton an
    /// hour (50,000 ÷ 24), kept as thousandths until a whole ton is made.
    func testIndustryMakesHalfATonAJobADay() throws {
        var world = try world(trains: 0)
        XCTAssertEqual(world.freightSupply(at: alpha), 50)
        XCTAssertEqual(world.freightSupply(at: gamma), 0, "the factory's cell is nearer Alpha")
        try hours(1, &world)
        var state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.facilities.map(\.stock), [2, 0], "50,000 thousandths an hour is 2 t and 1,999 thousandths over")
        XCTAssertEqual(state.facilities.first?.accrual, 2_000)
        try hours(23, &world)
        state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.facilities.map(\.stock), [50, 0], "a day makes exactly 50 t")
        XCTAssertEqual(state.produced, 50)
        XCTAssertTrue(state.isConserved)
    }

    /// A facility holds 2,000 t; cargo made beyond that is spilled.
    func testAFullYardSpillsCargo() throws {
        var world = try world(jobs: 40_000, trains: 0)
        // 40,000 jobs make 20,000 t a day: 833 t an hour.
        try hours(4, &world)
        let state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.facilities.first?.stock, Freight.stockLimit)
        XCTAssertEqual(state.produced, 3_333, "four hours of 833.33 t")
        XCTAssertEqual(state.spilled, 3_333 - 2_000)
        XCTAssertTrue(state.isConserved)
    }

    /// The nearer facility has the industry; a port makes cargo besides.
    func testPortsMakeCargoAndTheNearestYardGetsTheJobs() throws {
        var world = try world(trains: 0)
        world.setOutsideConnections(true)
        XCTAssertTrue(world.isOutsideConnection(alpha) && world.isOutsideConnection(gamma), "the whole small map lies by its edge")
        XCTAssertEqual(world.freightSupply(at: alpha), 250, "50 t of industry and a port's 200 t")
        XCTAssertEqual(world.freightSupply(at: gamma), 200)
        try hours(24, &world)
        XCTAssertEqual(world.freight?.facilities.map(\.stock), [250, 200])
    }

    // MARK: - Carrying it

    /// A train on the freight line loads at Alpha, lets its cargo off and
    /// is paid at Gamma, and every ton stays accounted for.
    func testATrainCarriesCargoToTheNextYardAndIsPaid() throws {
        var world = try world(jobs: 40_000)
        var sawLoad = false
        for _ in 0..<(12 * 60) {
            try world.advance(ticks: 1)
            let state = try XCTUnwrap(world.freight)
            XCTAssertTrue(state.isConserved, "at \(world.clock.now)")
            if let load = state.loads.first {
                sawLoad = true
                XCTAssertEqual(load.tons, 40, "one car carries 40 t")
                XCTAssertEqual(load.groups.map(\.origin), [alpha])
            }
        }
        XCTAssertTrue(sawLoad)
        let state = try XCTUnwrap(world.freight)
        XCTAssertGreaterThan(state.delivered, 0)
        XCTAssertEqual(state.delivered % 40, 0, "whole loads are let off")
        // Each 40 t over 64 m pays $13, in the hour's freight row.
        let rows = world.accounts.entries.filter { $0.kind == .hourlyFreight }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.amount > .zero && $0.amount.amount % 1_300 == 0 })
        let paid = rows.reduce(Int64(0)) { $0 + $1.amount.amount }
        XCTAssertEqual(paid + state.pendingRevenue.amount, state.delivered / 40 * 1_300, "every load let off paid $13")
        XCTAssertEqual(world.financeReport(.day).current.freightRevenue.amount, paid)
        XCTAssertEqual(world.financeReport(.day).current.operatingProfit.amount,
                       world.financeReport(.day).current.fareRevenue.amount + paid
                           - world.financeReport(.day).current.totalCost.amount)
        XCTAssertNil(world.accountsProblem())
    }

    /// Cargo is let off at the first yard but its origin, never carried past:
    /// a train that loaded at Gamma is paid at Alpha.
    func testCargoMovesBothWays() throws {
        var world = try world(jobs: 40_000)
        // Industry by Gamma too: the cell at column 1 is nearer Gamma.
        try world.setLand([
            LandCell(row: 0, column: 0, use: .industrial, residents: 0, jobs: 40_000),
            LandCell(row: 0, column: 1, use: .industrial, residents: 0, jobs: 40_000),
        ])
        var origins: Set<StationID> = []
        for _ in 0..<(12 * 60) {
            try world.advance(ticks: 1)
            for group in world.freight?.loads.flatMap(\.groups) ?? [] { origins.insert(group.origin) }
        }
        XCTAssertEqual(origins, [alpha, gamma])
        XCTAssertTrue(try XCTUnwrap(world.freight).isConserved)
    }

    /// Free play keeps no accounts: the cargo moves and is let off, and
    /// nothing is paid.
    func testFreePlayCarriesCargoButPaysNothing() throws {
        var world = try world(jobs: 40_000, mode: .free)
        let balance = world.economy.balance
        try hours(12, &world)
        let state = try XCTUnwrap(world.freight)
        XCTAssertGreaterThan(state.delivered, 0)
        XCTAssertEqual(state.pendingRevenue, .zero)
        XCTAssertTrue(world.accounts.entries.isEmpty)
        XCTAssertEqual(world.economy.balance, balance, "free play settles nothing")
    }

    func testNoPassengerRidesAFreightLine() throws {
        let passenger = try world(freightLine: false)
        XCTAssertNotNil(passenger.passengerTrip(from: alpha, to: gamma))
        let freight = try world()
        XCTAssertNil(freight.passengerTrip(from: alpha, to: gamma))
    }

    /// Without a yard a freight line's train goes through and carries
    /// nothing.
    func testNoYardNoCargo() throws {
        var world = try world(jobs: 40_000, yards: false)
        try hours(6, &world)
        let state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state, FreightState())
    }

    /// Advancing many minutes at once makes the cargo exactly as minute by
    /// minute does, whether or not the minutes are skipped.
    func testLongBatchesMatchSingleTicks() throws {
        var once = try world(jobs: 40_000)
        var stepped = once
        try once.advance(ticks: 6 * 60 + 17)
        for _ in 0..<(6 * 60 + 17) { try stepped.advance(ticks: 1) }
        XCTAssertEqual(once, stepped)
        // A line with no train out skips idle minutes; the yards still make
        // their cargo every hour.
        var idle = try world(trains: 0)
        var minutes = idle
        try idle.advance(ticks: 5 * 60 + 3)
        for _ in 0..<(5 * 60 + 3) { try minutes.advance(ticks: 1) }
        XCTAssertEqual(idle, minutes)
        // An hour's cargo is made as each hour begins, the first at the start:
        // six of them, 50,000 thousandths of a ton each.
        XCTAssertEqual(idle.freight?.produced, 12)
    }

    // MARK: - Commands

    func testCommandsAreCheckedInOrder() throws {
        var off = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        try track.build(in: &off)
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &off)
        try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &off)
        try off.createLine(named: "Goods", stops: [alpha, gamma])
        let before = off
        XCTAssertNil(off.freight)
        XCTAssertThrowsGameError(try off.buildFreightFacility(at: alpha), .freightNotEnabled)
        XCTAssertThrowsGameError(try off.removeFreightFacility(at: alpha), .freightNotEnabled)
        XCTAssertThrowsGameError(try off.setLineFreight(main, to: true), .freightNotEnabled)
        XCTAssertEqual(off, before, "refused commands change nothing")

        var world = try world(yards: false)
        XCTAssertThrowsGameError(try world.buildFreightFacility(at: StationID(rawValue: 9)), .unknownStation(StationID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.removeFreightFacility(at: alpha), .noFreightFacility(alpha))
        let rich = world.economy.balance
        let spent = world.financeReport(.day).current.capitalSpending
        try world.buildFreightFacility(at: alpha)
        XCTAssertEqual(world.economy.balance.amount, rich.amount - Freight.facilityCost.amount)
        XCTAssertEqual(world.financeReport(.day).current.capitalSpending - spent, Freight.facilityCost)
        XCTAssertThrowsGameError(try world.buildFreightFacility(at: alpha), .freightFacilityExists(alpha))
        // A line with trains on it cannot change what it carries.
        XCTAssertThrowsGameError(try world.setLineFreight(main, to: false), .trainOnLine(TrainID(rawValue: 1)))
        try world.unassignTrain(blue)
        try world.setLineFreight(main, to: false)
        XCTAssertEqual(world.line(id: main)?.isFreight, false)
        try world.setLineFreight(main, to: false)

        // A company that cannot pay is refused, and keeps its money.
        var poor = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try track.build(in: &poor)
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &poor)
        poor.enableFreight()
        let kept = poor
        let available = poor.economy.balance
        XCTAssertThrowsGameError(try poor.buildFreightFacility(at: alpha), .insufficientFunds(required: Freight.facilityCost, available: available))
        XCTAssertEqual(poor, kept)
    }

    func testRemovingAYardLosesItsCargo() throws {
        var world = try world(trains: 0)
        try hours(3, &world)
        try world.removeFreightFacility(at: alpha)
        let state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.facilities.map(\.station), [gamma])
        XCTAssertEqual(state.lost, 6)
        XCTAssertTrue(state.isConserved)
    }

    func testRemovingAStationLosesItsCargoAndWhatItLoaded() throws {
        var world = try world(trains: 0)
        try hours(5, &world)
        try world.removeStation(alpha)
        let state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.facilities.map(\.station), [gamma])
        XCTAssertEqual(state.lost, 10)
        XCTAssertTrue(state.isConserved)
        XCTAssertNil(world.freightProblem())
    }

    /// A train that leaves its freight line loses what it carries at the
    /// next hour.
    func testCargoOfATrainOffItsLineIsLost() throws {
        var world = try world(jobs: 40_000)
        while (world.freight?.loads.isEmpty ?? true) && world.clock.now.seconds < 6 * 3_600 {
            try world.advance(ticks: 1)
        }
        let carried = try XCTUnwrap(world.freight?.onBoard)
        XCTAssertGreaterThan(carried, 0)
        let lostBefore = try XCTUnwrap(world.freight?.lost)
        try world.unassignTrain(blue)
        try world.advance(ticks: 60)
        let state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.onBoard, 0)
        XCTAssertEqual(state.lost, lostBefore + carried)
        XCTAssertTrue(state.isConserved)
    }

    // MARK: - Saving

    /// A world without freight writes none of it; a world with it keeps it
    /// all, and the version says so.
    func testSavingKeepsFreightAndAWorldWithoutItWritesNone() throws {
        var plain = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000, costs: testCosts))
        try track.build(in: &plain)
        let text = String(decoding: try JSONEncoder().encode(SavedGame(world: plain)), as: UTF8.self)
        XCTAssertFalse(text.contains("freight"), "a world with no freight is what it was")
        XCTAssertEqual(SavedGame.currentVersion, 38)

        var world = try world(jobs: 40_000)
        try hours(5, &world)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let text2 = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text2.contains(#""freight""#) && text2.contains("hourlyFreight") && text2.contains(#""freight":true"#))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        // And it goes on the same.
        var a = world, b = loaded
        try a.advance(ticks: 3 * 60)
        try b.advance(ticks: 3 * 60)
        XCTAssertEqual(a, b)
    }

    func testASaveWhoseTonsDoNotAddUpIsRefused() throws {
        var world = try world(trains: 0)
        try hours(3, &world)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        var inner = try XCTUnwrap(json["world"] as? [String: Any])
        var freight = try XCTUnwrap(inner["freight"] as? [String: Any])
        freight["produced"] = 1_000
        inner["freight"] = freight
        json["world"] = inner
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: data))
        // A facility that is not there is refused too.
        freight["produced"] = 6
        var facilities = try XCTUnwrap(freight["facilities"] as? [[String: Any]])
        facilities[0]["station"] = 7
        freight["facilities"] = facilities
        inner["freight"] = freight
        json["world"] = inner
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    /// Version 38 (decision 155): `world(jobs: 40_000)` run five hours and on
    /// to a minute when its train carries cargo. It saves byte for byte and
    /// is the world this build makes.
    func testVersionThirtyEightKeepsItsFreight() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v38-freight.json")
        var made = try world(jobs: 40_000)
        try hours(5, &made)
        while made.freight?.loads.isEmpty ?? true { try made.advance(ticks: 1) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["FREIGHT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 38)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        let state = try XCTUnwrap(loaded.freight)
        XCTAssertEqual(state.onBoard, 40, "the train carries a load")
        XCTAssertTrue(state.isConserved)
        XCTAssertTrue(loaded.lines[0].isFreight)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 38,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        // And it goes on: the load is let off and paid for.
        try loaded.advance(ticks: 30)
        XCTAssertGreaterThan(try XCTUnwrap(loaded.freight).delivered, state.delivered)
    }
}
