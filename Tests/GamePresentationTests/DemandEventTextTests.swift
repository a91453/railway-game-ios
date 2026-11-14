import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 730: the station panel says when an event with hours is held
/// and when its crowd leaves.
final class DemandEventTextTests: XCTestCase {
    /// One station, game day 0, with `events` at it.
    private func world(with events: [DemandEvent]) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 10_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: 0))
        )
        _ = try world.buildStation(named: "Arena", at: PlanPoint(x: 2_048, y: 2_048))
        world.setDemandEvents(seed: 1)
        // The events are drawn, not set: put them into the save instead.
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var schedule = try XCTUnwrap(object["demandEvents"] as? [String: Any])
        schedule["events"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(events))
        object["demandEvents"] = schedule
        return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testAnEventWithHoursSaysThemAndWhenItsCrowdLeaves() throws {
        let station = StationID(rawValue: 1)
        let world = try world(with: [
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 2, end: 3, boost: 700, opens: 1_140, closes: 1_320),
            DemandEvent(kind: .exhibition, station: station, announced: 0, start: 0, end: 4, boost: 300),
        ])
        XCTAssertEqual(world.demandEventTexts(at: station, in: .english), [
            "Crowd surge 19:00–22:00: +70% demand, starts in 2 days, lasts 1 day, crowds leave around 22:00",
            "Exhibition: +30% demand, 4 more days",
        ])
        XCTAssertEqual(world.demandEventTexts(at: station, in: .traditionalChinese), [
            "大量人潮事件 19:00–22:00：需求 +70%，2 天後開始，持續 1 天，散場人潮約 22:00",
            "大型展覽：需求 +30%，還有 4 天",
        ])
        let running = try self.world(with: [
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 0, end: 2, boost: 550, opens: 1_050, closes: 1_230),
        ])
        XCTAssertEqual(running.demandEventTexts(at: station, in: .traditionalChinese), ["大量人潮事件 17:30–20:30：需求 +55%，還有 2 天，散場人潮約 20:30"])
    }
}
