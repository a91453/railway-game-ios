import GameCore
@testable import GamePresentation
import XCTest

/// The economy panel's day-pass card (decision 324): what it offers and
/// says, and the session's command behind its buttons.
@MainActor
final class DayPassCardTests: XCTestCase {
    /// A managed company with one line and a 3-star town at its far end,
    /// whose tourists come from the near end, by the map's edge.
    private func world() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 262_144, height: 262_144), economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        let home = try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 131_072)).id
        let foot = try world.buildStation(named: "Foot", at: PlanPoint(x: 100_000, y: 131_072)).id
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 0))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "老街", englishName: "Old Street",
                                     point: PlanPoint(x: 101_000, y: 131_072), kind: .town, baseStars: 300)])
        return world
    }

    func testWithoutSightsNothingSells() throws {
        let card = DayPassCard(world: GameWorld(bounds: try WorldBounds(width: 65_536, height: 65_536), economy: GameEconomy(balance: 0, costs: testCosts)))
        XCTAssertFalse(card.isAvailable)
        XCTAssertNotNil(card.unavailableText(in: .english))
        XCTAssertEqual(card.statusText(in: .english), "Not on sale")
        XCTAssertEqual(card.suggestedPrice, Money(1_500), "three $5 fares")
        XCTAssertNil(card.todayText(in: .english))
    }

    func testTheSessionSellsAndStops() throws {
        let session = GameSession(world: try world())
        XCTAssertTrue(DayPassCard(world: session.world).isAvailable)
        session.setDayPass(Money(800))
        XCTAssertEqual(session.world.accounts.dayPass, Money(800))
        XCTAssertEqual(session.message?.text, "Day passes on sale at $ 8.00.")
        let card = DayPassCard(world: session.world)
        XCTAssertEqual(card.statusText(in: .traditionalChinese), "販售中 · $ 8.00")
        XCTAssertEqual(card.suggestedPrice, Money(800), "the price on sale")
        // Worth $10 there and back: at $8 a fifth of the 240 buy, $2 under.
        XCTAssertEqual(card.today.sold, 48)
        XCTAssertEqual(card.todayText(in: .english), "Today about 48 sold: -$ 96 against what their trips would have paid, and 0 extra rides.")

        session.setDayPass(Money(1_000))
        XCTAssertEqual(DayPassCard(world: session.world).todayText(in: .english), "Nobody buys at this price today.")
        session.setDayPass(nil)
        XCTAssertNil(session.world.accounts.dayPass)
        XCTAssertEqual(session.message?.text, "Day passes are no longer sold.")
        XCTAssertNil(DayPassCard(world: session.world).todayText(in: .english))
    }

    func testABadPriceIsRefused() throws {
        let session = GameSession(world: try world())
        session.setDayPass(Money(150))
        XCTAssertNil(session.world.accounts.dayPass)
        XCTAssertEqual(session.message?.kind, .failure)
    }

    /// The card's first price is one the game sells at and its stepper
    /// holds: the editor's distance steps' $0.55 makes three of them
    /// $1.65, which the pass refuses (whole dollars only).
    func testTheSuggestedPriceSells() throws {
        for rules in [FareRules.distance(FareRules.standardBands), .flat(Money(20_000))] {
            var world = try world()
            try world.setFareRules(rules)
            let session = GameSession(world: world)
            let card = DayPassCard(world: session.world)
            XCTAssertTrue(DayPassCard.priceRange.contains(card.suggestedPrice.amount), "\(rules)")
            session.setDayPass(card.suggestedPrice)
            XCTAssertEqual(session.world.accounts.dayPass, card.suggestedPrice, "\(rules)")
        }
    }
}
