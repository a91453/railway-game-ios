@testable import GameCore
@testable import GamePresentation
import XCTest

/// The station panel's size section (decision 506).
@MainActor
final class StationExpansionCardTests: XCTestCase {
    /// Decision 137's line between the first two towns of seed 1, managed
    /// with line accounts (a new game's), run two days, with money for
    /// both expansions.
    private func world() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(StationExpansion.allCases.map(\.price).reduce(.zero, +))
        try world.advance(ticks: 2 * 1_440 + 10)
        return world
    }

    /// A new line's station is busy enough for the first expansion, not
    /// yet for the second: the offer then says how busy it must get, and
    /// the button cannot be pressed.
    func testTheSecondStepWaitsForABusierStation() throws {
        let world = try world()
        let station = world.stations[0].id
        var card = try XCTUnwrap(StationExpansionCard(station: station, in: world))
        XCTAssertNil(card.expansion)
        XCTAssertEqual(card.capacity, 4_000)
        XCTAssertEqual(card.people, world.stationExpansionPeople(of: station))
        var offer = try XCTUnwrap(card.offer)
        XCTAssertEqual(offer.expansion, .concourse)
        XCTAssertEqual(offer.price, StationExpansion.concourse.price)
        XCTAssertEqual(offer.open, card.people >= StationExpansion.concourse.threshold)
        XCTAssertEqual(card.capacityText(in: .traditionalChinese), "可容納 4,000 人候車・目前 \(card.waiting.groupedText) 人")
        XCTAssertGreaterThanOrEqual(card.people, StationExpansion.concourse.threshold, "the first line's town station is busy")
        XCTAssertLessThan(card.people, StationExpansion.hall.threshold, "but not a city's main station")
        XCTAssertTrue(card.canExpand)
        XCTAssertEqual(card.offerTitle(in: .traditionalChinese), "擴建：擴大站廳・\(StationExpansion.concourse.price.moneyText)")
        XCTAssertEqual(card.offerText(in: .traditionalChinese), "可容納 8,000 人候車，客滿時少流失一些旅客。")

        let session = GameSession(world: world)
        session.expandStation(at: station)
        card = try XCTUnwrap(session.stationExpansionCard(of: station))
        XCTAssertEqual(card.expansion, .concourse)
        XCTAssertEqual(card.capacity, 8_000)
        offer = try XCTUnwrap(card.offer)
        XCTAssertEqual(offer.expansion, .hall)
        XCTAssertFalse(offer.open)
        XCTAssertFalse(card.canExpand)
        let text = try XCTUnwrap(card.offerText(in: .traditionalChinese))
        XCTAssertTrue(text.hasPrefix("每日進出達 100,000 人次才能擴建（昨天 "), text)
    }

    /// After both, the section says it is at its largest.
    func testTheLargestStation() throws {
        var world = try world()
        let station = world.stations[0].id
        world.setStationExpansion(.hall, at: 0)
        let card = try XCTUnwrap(StationExpansionCard(station: station, in: world))
        XCTAssertEqual(card.expansion, .hall)
        XCTAssertEqual(card.capacity, 16_000)
        XCTAssertNil(card.offer)
        XCTAssertNil(card.offerTitle(in: .english))
        XCTAssertFalse(card.canExpand)
        XCTAssertEqual(card.offerText(in: .english), "The station is at its largest.")
    }

    /// A depot has no size section.
    func testADepotHasNone() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try TestLine(tiles: 7).build(in: &world)
        try TestLine(tiles: 7).buildStation(named: "D", beside: 1, at: 1, in: &world)
        let id = try XCTUnwrap(world.stations.first?.id)
        try world.setStationDepot(id, to: true)
        XCTAssertNil(StationExpansionCard(station: id, in: world))
    }

    /// The player's text says what an expansion does, not how it is
    /// worked out (#600).
    func testThePlayersTextHasNoFormula() throws {
        let world = try world()
        let card = try XCTUnwrap(StationExpansionCard(station: world.stations[0].id, in: world))
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let texts = [StationExpansionCard.explanation(in: language), card.offerText(in: language) ?? "",
                         card.capacityText(in: language), card.offerTitle(in: language) ?? ""]
            for text in texts {
                for word in ["÷", "×", "decision", "決策", "%", "threshold"] {
                    XCTAssertFalse(text.contains(word), "\(word) in \(text)")
                }
            }
        }
    }
}
