@testable import GameCore
@testable import GamePresentation
import XCTest

/// The station panel's shops (ARCHITECTURE decision 222).
@MainActor
final class StationCommerceCardTests: XCTestCase {
    /// Decision 137's line between the first two towns of seed 1, managed
    /// with line accounts (a new game's), run two days, with money for a
    /// mall.
    private func world() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(Money(2_000_000_000))
        try world.advance(ticks: 2 * 1_440 + 10)
        return world
    }

    func testAStationWithoutShopsOffersAConvenienceStore() throws {
        let world = try world()
        let station = world.stations[0].id
        let card = try XCTUnwrap(StationCommerceCard(station: station, in: world))
        XCTAssertNil(card.level)
        XCTAssertGreaterThan(card.people, 0, "the line carries people")
        XCTAssertEqual(card.yesterday, .zero)
        let offer = try XCTUnwrap(card.offer)
        XCTAssertEqual(offer.level, .convenienceStore)
        XCTAssertEqual(offer.price, Money(35_000_000))
        XCTAssertEqual(offer.extraPerDay, StationCommerceLevel.convenienceStore.takings(people: card.people) - StationCommerceLevel.convenienceStore.upkeep)
        XCTAssertTrue(offer.affordable)
        XCTAssertNotNil(offer.paybackTenths)
        XCTAssertEqual(card.offerTitle(in: .traditionalChinese), "蓋便利商店")
        XCTAssertEqual(card.offerTitle(in: .english), "Build a convenience store")
        let text = try XCTUnwrap(card.offerText(in: .traditionalChinese))
        XCTAssertTrue(text.hasPrefix("每天約多賺 "), text)
        XCTAssertTrue(text.hasSuffix(" 年回本"), text)
    }

    /// The player's text says what the shops do, not how they are worked
    /// out (#600).
    func testThePlayersTextHasNoFormula() throws {
        let world = try world()
        let card = try XCTUnwrap(StationCommerceCard(station: world.stations[0].id, in: world))
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let texts = [StationCommerceCard.explanation(in: language), card.offerText(in: language) ?? "", card.yesterdayText(in: language)]
            for text in texts {
                for word in ["÷", "×", "decision", "決策", "%"] {
                    XCTAssertFalse(text.contains(word), "\(word) in \(text)")
                }
            }
        }
    }

    /// Years to pay back, in tenths, rounded up; none when it would not.
    func testPayback() {
        XCTAssertEqual(StationCommerceCard.paybackTenths(price: Money(36_000), perDay: Money(100)), 10, "360 days: a year")
        XCTAssertEqual(StationCommerceCard.paybackTenths(price: Money(36_100), perDay: Money(100)), 11, "361 days: rounded up")
        XCTAssertNil(StationCommerceCard.paybackTenths(price: Money(36_000), perDay: .zero))
        XCTAssertNil(StationCommerceCard.paybackTenths(price: Money(36_000), perDay: Money(-5)))
    }

    func testTheButtonsBuildUpgradeAndDemolish() throws {
        let session = GameSession(world: try world())
        let station = session.world.stations[0].id
        let before = session.world.economy.balance
        session.buildNextStationCommerce(at: station)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.station(id: station)?.commerce, .convenienceStore)
        XCTAssertEqual(before - session.world.economy.balance, Money(35_000_000))
        session.buildNextStationCommerce(at: station)
        session.buildNextStationCommerce(at: station)
        XCTAssertEqual(session.world.station(id: station)?.commerce, .mall)
        let card = try XCTUnwrap(session.stationCommerceCard(of: station))
        XCTAssertNil(card.offer, "a mall is the top")
        XCTAssertNil(card.offerTitle(in: .english))
        session.demolishStationCommerce(at: station)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertNil(session.world.station(id: station)?.commerce)
        session.demolishStationCommerce(at: station)
        XCTAssertEqual(session.message?.kind, .failure, "nothing left to demolish")
    }

    func testYesterdaysText() throws {
        var world = try world()
        let station = world.stations[0].id
        try world.buildStationCommerce(at: station)
        try world.advance(ticks: 1_440)
        let card = try XCTUnwrap(StationCommerceCard(station: station, in: world))
        XCTAssertEqual(card.level, .convenienceStore)
        XCTAssertEqual(card.yesterday, StationCommerceLevel.convenienceStore.takings(people: card.people) - StationCommerceLevel.convenienceStore.upkeep)
        XCTAssertTrue(card.yesterdayText(in: .traditionalChinese).hasPrefix("昨天 +$ "), card.yesterdayText(in: .traditionalChinese))
        XCTAssertEqual(card.offer?.level, .arcade)
        XCTAssertEqual(card.offerTitle(in: .traditionalChinese), "升級成站內商店街")
    }

    func testADepotHasNoOffer() throws {
        var world = try world()
        let depot = try world.buildStation(named: "Yard", at: PlanPoint(x: 10_000, y: 10_000)).id
        try world.setStationDepot(depot, to: true)
        let card = try XCTUnwrap(StationCommerceCard(station: depot, in: world))
        XCTAssertFalse(card.allowed)
        XCTAssertNil(card.offer)
    }
}
