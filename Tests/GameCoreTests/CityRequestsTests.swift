import Foundation
@testable import GameCore
import XCTest

/// The city's requests and subsidies (ARCHITECTURE decision 183). Every
/// expectation is worked out by hand from the rules.
final class CityRequestsTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)

    /// `LineAccountsTests`' two lines, A–B and B–C, a train each, A and C
    /// with 1,500 trips a day: a managed company with the city's requests
    /// from seed 7.
    private func build(managed: Bool = true, requests: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
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
        if managed { world.setEconomyMode(.management) }
        world.setSpeed(.normal)
        if requests { world.setCityRequests(seed: 7) }
        return world
    }

    /// A request in hand of `kind`, accepted today, put straight into the
    /// world.
    private func hand(_ world: inout GameWorld, _ kind: CityRequestKind, point: PlanPoint? = nil, station: StationID? = nil,
                      target: Int64, reward: Money = Money(10_000_000), days: Int64 = 90) {
        var request = CityRequest(id: world.cityRequests!.nextID, kind: kind, point: point, station: station, baseline: 0,
                                  target: target, reward: reward, days: days, offeredDay: 0)
        request.acceptedDay = world.dayIndex(of: world.clock.now)
        world.cityRequests!.active.append(request)
        world.cityRequests!.nextID += 1
    }

    // MARK: - Offers

    func testTheFirstOffersAreDrawnAtOnce() throws {
        let world = try build()
        let requests = try XCTUnwrap(world.cityRequests)
        XCTAssertEqual(requests.trust, 1)
        XCTAssertEqual(requests.capacity, 1, "1 + ⌊1 / 2⌋")
        // No land, no sights, no freight and no day carried yet: only a
        // station's riders can be asked for. A and C have 1,500 trips each.
        XCTAssertEqual(requests.offers.map(\.kind), [.stationRiders])
        let offer = requests.offers[0]
        XCTAssertTrue([a, c].contains(offer.station!))
        XCTAssertEqual(offer.baseline, 1_500)
        XCTAssertEqual(offer.target, 2_100, "⌈1,500 × 1.4⌉")
        XCTAssertEqual(offer.reward, Money(20_000_000), "$40 × 600 is $24,000, below the $200,000 floor")
        XCTAssertEqual(offer.days, 60)
        XCTAssertEqual(offer.offeredDay, 0)
        XCTAssertNil(offer.acceptedDay)
        XCTAssertEqual(try build().cityRequests, requests, "the same seed draws the same")
    }

    func testOffersHaveDifferentKindsAndAtMostThree() throws {
        var world = try build()
        // A best day of 1,000 riders: the network can be asked for more.
        world.cityRequests!.bestDayTrips = 1_000
        world.drawCityRequests(month: 1, day: 30)
        let offers = world.cityRequests!.offers
        XCTAssertEqual(Set(offers.map(\.kind)), [.stationRiders, .networkRiders])
        let network = try XCTUnwrap(offers.first { $0.kind == .networkRiders })
        XCTAssertEqual(network.target, 1_250, "⌈1,000 × 1.25⌉")
        XCTAssertEqual(network.reward, Money(20_000_000), "$20 × 250 is $5,000, below the floor")
        XCTAssertEqual(network.days, 90)
        for seed in UInt32(1)...40 {
            world.cityRequests = CityRequests(seed: seed)
            world.cityRequests!.bestDayTrips = 1_000
            for month in Int64(0)..<6 {
                world.drawCityRequests(month: month, day: month * 30)
                let kinds = world.cityRequests!.offers.map(\.kind)
                XCTAssertLessThanOrEqual(kinds.count, CityRequests.maximumOffers)
                XCTAssertEqual(Set(kinds).count, kinds.count, "seed \(seed), month \(month)")
            }
        }
    }

    func testTheLargestSettlementWithoutAStationIsAsked() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 400_000, height: 200_000), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        // Two towns of 9 cells: the west one 9 × (300 + 100) = 3,600
        // people, the east 9 × 500 = 4,500 with a station in it, and a
        // hamlet of 2,000 far away.
        var cells: [LandCell] = []
        for row in 4..<7 {
            for column in 4..<7 { cells.append(LandCell(row: row, column: column, use: .residential, residents: 300, jobs: 100)) }
            for column in 60..<63 { cells.append(LandCell(row: row, column: column, use: .residential, residents: 500, jobs: 0)) }
        }
        cells.append(LandCell(row: 40, column: 80, use: .residential, residents: 2_000, jobs: 0))
        try world.setLand(cells)
        try world.buildStation(named: "East", at: PlanPoint(x: 61 * 4_096 + 2_048, y: 5 * 4_096 + 2_048))
        let place = try XCTUnwrap(world.largestUnservedSettlement(avoiding: []))
        XCTAssertEqual(place.point, PlanPoint(x: 5 * 4_096 + 2_048, y: 5 * 4_096 + 2_048), "the middle of the west town")
        XCTAssertEqual(place.people, 3_600)
        world.setCityRequests(seed: 3)
        let offer = try XCTUnwrap(world.cityRequests?.offers.first { $0.kind == .newStation })
        XCTAssertEqual(offer.point, place.point)
        XCTAssertEqual(offer.target, 10)
        XCTAssertEqual(offer.reward, Money(48_000_000), "$300,000 + $50 × 3,600")
        XCTAssertNil(world.largestUnservedSettlement(avoiding: [place.point]), "the hamlet is too small")
    }

    // MARK: - In hand

    func testTheTrustLimitsTheRequestsInHand() throws {
        var world = try build()
        world.cityRequests!.bestDayTrips = 1_000
        world.drawCityRequests(month: 0, day: 0)
        let ids = world.cityRequests!.offers.map(\.id)
        XCTAssertEqual(ids.count, 2)
        try world.acceptRequest(ids[0])
        XCTAssertEqual(world.cityRequests!.active.map(\.id), [ids[0]])
        XCTAssertEqual(world.cityRequests!.active[0].acceptedDay, 0)
        XCTAssertThrowsError(try world.acceptRequest(ids[1])) { XCTAssertEqual($0 as? GameError, .cityRequestLimitReached(limit: 1)) }
        XCTAssertThrowsError(try world.acceptRequest(999)) { XCTAssertEqual($0 as? GameError, .unknownCityRequest(999)) }
        // Turning an offer down: it goes, the trust stays.
        try world.declineRequest(ids[1])
        XCTAssertTrue(world.cityRequests!.offers.isEmpty)
        XCTAssertEqual(world.cityRequests!.trust, 1)
        // Giving one up in hand fails it.
        try world.declineRequest(ids[0])
        XCTAssertTrue(world.cityRequests!.active.isEmpty)
        XCTAssertEqual(world.cityRequests!.trust, 0)
        XCTAssertEqual(world.cityRequests!.results.map(\.succeeded), [false])
        var off = try build(requests: false)
        XCTAssertThrowsError(try off.acceptRequest(1)) { XCTAssertEqual($0 as? GameError, .cityRequestsNotEnabled) }
        XCTAssertThrowsError(try off.declineRequest(1)) { XCTAssertEqual($0 as? GameError, .cityRequestsNotEnabled) }
        XCTAssertEqual(CityRequests.capacity(trust: 0), 1)
        XCTAssertEqual(CityRequests.capacity(trust: 3), 2)
        XCTAssertEqual(CityRequests.capacity(trust: 5), 3)
    }

    func testAMetRequestIsPaidOnTheFirstOfTheNextMonth() throws {
        var world = try build()
        let offer = try XCTUnwrap(world.cityRequests?.offers.first)
        try world.acceptRequest(offer.id)
        try world.setStationDemand(offer.station!, to: StationDemand(kind: .residential, dailyTrips: 2_100))
        // A day and the minute of midnight, which settles it.
        try world.advance(ticks: 1_441)
        var requests = try XCTUnwrap(world.cityRequests)
        XCTAssertTrue(requests.active.isEmpty)
        XCTAssertEqual(requests.results.map(\.succeeded), [true])
        XCTAssertEqual(requests.results[0].day, 0)
        XCTAssertEqual(requests.results[0].request.progress, 2_100)
        XCTAssertEqual(requests.trust, 2)
        XCTAssertEqual(requests.owed, Money(20_000_000))
        XCTAssertFalse(world.accounts.entries.contains { $0.kind == .monthlySubsidy }, "not paid before the month is out")
        try world.advance(ticks: 29 * 1_440)
        requests = try XCTUnwrap(world.cityRequests)
        XCTAssertEqual(requests.owed, .zero)
        XCTAssertEqual(requests.paid, Money(20_000_000))
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .monthlySubsidy })
        XCTAssertEqual(row.amount, Money(20_000_000))
        XCTAssertEqual(row.breakdown, [LedgerLine(item: .subsidy, amount: Money(20_000_000))])
        XCTAssertEqual(row.time, GameTime(seconds: 30 * 86_400 - 60), "the last minute of day 29")
        // Taxable: in the day's profit, booked as non-railway revenue.
        let day = try XCTUnwrap(world.accounts.days.first { $0.day == 29 })
        XCTAssertGreaterThanOrEqual(day.propertyRevenue, Money(20_000_000))
        XCTAssertGreaterThan(day.taxCost, .zero, "half of what the day made beyond $100,000")
        // The second month's offers, drawn on day 30.
        XCTAssertTrue(requests.offers.allSatisfy { $0.offeredDay == 30 })
        XCTAssertFalse(requests.offers.isEmpty)
    }

    func testARequestPastItsDeadlineCostsAStarAndNoMoney() throws {
        var world = try build()
        hand(&world, .stationRiders, station: a, target: 1_000_000, days: 2)
        let balance = world.economy.balance
        var plain = world
        plain.cityRequests = nil
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.cityRequests!.active.count, 1, "a day left")
        try world.advance(ticks: 1_440)
        try plain.advance(ticks: 2 * 1_440 + 1)
        XCTAssertTrue(world.cityRequests!.active.isEmpty)
        XCTAssertEqual(world.cityRequests!.results.map(\.succeeded), [false])
        XCTAssertEqual(world.cityRequests!.results[0].day, 1, "its deadline, day 0 + 2 − 1")
        XCTAssertEqual(world.cityRequests!.trust, 0)
        XCTAssertEqual(world.economy.balance, plain.economy.balance, "no fine")
        XCTAssertNotEqual(world.economy.balance, balance)
    }

    /// A request taken at the minute of midnight, before that midnight has
    /// settled the day before, is not judged on that day: it was taken
    /// after it (decision 183: met on any day from the day it is taken).
    func testARequestTakenAtAnUnsettledMidnightIsNotJudgedOnTheDayBefore() throws {
        var world = try build()
        let id = world.cityRequests!.nextID
        world.cityRequests!.offers.append(CityRequest(id: id, kind: .networkRiders, baseline: 0, target: 1,
                                                      reward: Money(20_000_000), days: 90, offeredDay: 0))
        world.cityRequests!.nextID += 1
        try world.advance(ticks: 1_440)
        try world.acceptRequest(id)
        XCTAssertEqual(world.cityRequest(id: id)?.acceptedDay, 1)
        try world.advance(ticks: 1)
        XCTAssertGreaterThanOrEqual(world.accounts.days.first { $0.day == 0 }?.fareTrips ?? 0, 1, "day 0 carried riders")
        XCTAssertTrue(world.cityRequests!.results.isEmpty, "day 0 was before it was taken")
        XCTAssertEqual(world.cityRequests!.active.map(\.id), [id])
        XCTAssertEqual(world.cityRequests!.owed, .zero)
    }

    func testTrainsCallingNearASettlementCount() throws {
        var world = try build()
        // The whole little world lies within 800 m of the point.
        hand(&world, .newStation, point: PlanPoint(x: 1_536, y: 1_536), target: 10)
        try world.advance(ticks: 600)
        let calls = world.cityRequests!.active[0].callsToday
        XCTAssertFalse(calls.isEmpty)
        XCTAssertTrue(Set(calls.keys).isSubset(of: [a, b, c]))
        try world.advance(ticks: 841)
        let result = try XCTUnwrap(world.cityRequests!.results.first)
        XCTAssertTrue(result.succeeded)
        XCTAssertGreaterThanOrEqual(result.request.progress, 10)
        XCTAssertTrue(result.request.callsToday.isEmpty, "cleared at midnight")
    }

    func testMaterialsBroughtByRailCount() throws {
        var world = try build()
        hand(&world, .materials, station: b, target: 300)
        world.countRequestMaterials(120, at: b)
        world.countRequestMaterials(50, at: a)
        XCTAssertEqual(world.cityRequests!.active[0].progress, 120)
        world.countRequestMaterials(180, at: b)
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.cityRequests!.results.map(\.succeeded), [true])
        XCTAssertEqual(CityRequests.days(of: .materials), 45)
        XCTAssertEqual(GameWorld.dailyMaterialsNeed, Freight.newCellMaterials + 2 * Freight.materials(toRaise: .d1))
    }

    func testAFreeCompanyIsNotJudged() throws {
        var world = try build(managed: false)
        hand(&world, .stationRiders, station: a, target: 1, days: 1)
        try world.advance(ticks: 3 * 1_440)
        XCTAssertEqual(world.cityRequests!.active.count, 1)
        XCTAssertTrue(world.cityRequests!.results.isEmpty)
    }

    func testOneBatchIsMinuteByMinute() throws {
        var batch = try build()
        hand(&batch, .newStation, point: PlanPoint(x: 1_536, y: 1_536), target: 1_000)
        var steps = batch
        try batch.advance(ticks: 1_500)
        for _ in 0..<1_500 { try steps.advance(ticks: 1) }
        XCTAssertEqual(batch.cityRequests, steps.cityRequests)
        XCTAssertEqual(batch.cityRequests!.active[0].progress, steps.cityRequests!.active[0].progress)
    }

    // MARK: - Saves

    func testASaveKeepsTheRequests() throws {
        var world = try build()
        hand(&world, .newStation, point: PlanPoint(x: 1_536, y: 1_536), target: 1_000)
        try world.advance(ticks: 600)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.cityRequests, world.cityRequests)
    }

    func testABrokenSaveIsRefused() throws {
        var world = try build()
        world.cityRequests!.trust = 9
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: data))
        world.cityRequests!.trust = 1
        world.cityRequests!.offers.append(world.cityRequests!.offers[0])
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))))
    }

    /// A settlement asked for lies on the map: one far off it is refused
    /// on load, not measured into an overflow by the next train calling.
    func testASettlementOffTheMapIsRefused() throws {
        var world = try build()
        hand(&world, .newStation, point: PlanPoint(x: 1 << 62, y: 1_536), target: 10)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))))
    }

    /// A station a request asks about is taken down: the save still reads
    /// back, the request measures nothing and lapses at its deadline.
    func testARemovedStationsRequestStillSavesAndLapses() throws {
        var world = try build()
        world.cityRequests!.offers = []
        hand(&world, .stationRiders, station: c, target: 2_000, days: 2)
        // C's line goes first, then C, with no one riding to or from it.
        try world.setStationDemand(c, to: nil)
        try world.removeLine(LineID(rawValue: 2))
        try world.removeStation(c)
        XCTAssertNil(world.station(id: c))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.measure(loaded.cityRequests!.active[0]), 0)
        world = loaded
        try world.advance(ticks: 2 * 1_440 + 1)
        XCTAssertTrue(world.cityRequests!.active.isEmpty)
        XCTAssertEqual(world.cityRequests!.results.map(\.succeeded), [false])
        XCTAssertNil(world.location(of: world.cityRequests!.results[0].request), "nowhere to show")
    }

    func testAnEarlierSaveHasNoRequests() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v48-line-accounts.json")
        let world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: url)).world
        XCTAssertNil(world.cityRequests)
    }

    /// The save fixture of version 50: a request met (owed), one in hand
    /// with the day's calls, an offer and a result.
    func testVersionFiftyKeepsTheRequests() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v50-city-requests.json")
        var made = try build()
        let offer = try XCTUnwrap(made.cityRequests?.offers.first)
        try made.acceptRequest(offer.id)
        try made.setStationDemand(offer.station!, to: StationDemand(kind: .residential, dailyTrips: 2_100))
        try made.advance(ticks: 1_441)
        hand(&made, .newStation, point: PlanPoint(x: 1_536, y: 1_536), target: 1_000)
        try made.advance(ticks: 300)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CITY_REQUESTS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 50)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        let requests = try XCTUnwrap(loaded.cityRequests)
        XCTAssertEqual(requests.trust, 2)
        XCTAssertEqual(requests.owed, Money(20_000_000))
        XCTAssertEqual(requests.results.map(\.succeeded), [true])
        XCTAssertEqual(requests.active.map(\.kind), [.newStation])
        XCTAssertFalse(requests.active[0].callsToday.isEmpty)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 50,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
