import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// DEMAND-HOURS DH-2: the station master reminds the player of a crowd
/// surge with hours (decision 730), when it is held and when its crowd
/// leaves, and the news keeps the reminder once when it is announced and
/// once on its day.
final class CrowdSurgeAdviceTests: XCTestCase {
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

    private let station = StationID(rawValue: 1)

    func testAComingSurgeSaysItsHoursAndWhenItsCrowdLeaves() throws {
        let world = try world(with: [
            DemandEvent(kind: .exhibition, station: station, announced: 0, start: 0, end: 4, boost: 300),
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 2, end: 3, boost: 700, opens: 1_140, closes: 1_320),
        ])
        let advice = try XCTUnwrap(StationMasterAdvice.crowdSurge(in: world))
        XCTAssertEqual(advice, .crowdSurgeComing(station: station, name: "Arena", days: 2, percent: 70, opens: 1_140, closes: 1_320))
        XCTAssertEqual(advice.text(in: .english),
                       "Crowd surge at Arena in 2 days, 19:00–22:00: 70% more passengers, crowds leave around 22:00. Add trains before it.")
        XCTAssertEqual(advice.text(in: .traditionalChinese), "2 天後Arena有大量人潮事件 19:00–22:00，旅客會多 70%，散場人潮約 22:00。先加開列車吧。")
        XCTAssertEqual(advice.station, station, "A tap on the bubble goes to the station")
        XCTAssertFalse(advice.isWorry)
        XCTAssertEqual(advice.newsEntry?.category, .holiday)
        XCTAssertEqual(advice.newsEntry?.key, "crowdSurge:1:soon")
        XCTAssertEqual(advice.newsEntry?.target, .station(1))
    }

    func testOnItsDayItSaysToday() throws {
        let world = try world(with: [
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 0, end: 2, boost: 550, opens: 1_050, closes: 1_230),
        ])
        let advice = try XCTUnwrap(StationMasterAdvice.crowdSurge(in: world))
        XCTAssertEqual(advice, .crowdSurgeComing(station: station, name: "Arena", days: 0, percent: 55, opens: 1_050, closes: 1_230))
        XCTAssertEqual(advice.text(in: .english), "Crowd surge at Arena today, 17:30–20:30: crowds leave around 20:30. Run more trains then.")
        XCTAssertEqual(advice.text(in: .traditionalChinese), "今天Arena有大量人潮事件 17:30–20:30，散場人潮約 20:30，那時多開幾班吧。")
        XCTAssertEqual(advice.newsEntry?.key, "crowdSurge:1:today", "The day's reminder is a card of its own")
    }

    func testOnlySurgesWithHoursAreReminded() throws {
        let world = try world(with: [
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 1, end: 2, boost: 800),
            DemandEvent(kind: .exhibition, station: station, announced: 0, start: 1, end: 3, boost: 300),
        ])
        XCTAssertNil(StationMasterAdvice.crowdSurge(in: world), "A surge of a save before version 98 runs all day and has no hours to say")
    }

    func testTheSoonestSurgeIsReminded() throws {
        let world = try world(with: [
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 4, end: 5, boost: 900, opens: 1_020, closes: 1_140),
            DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 3, end: 4, boost: 600, opens: 1_080, closes: 1_290),
        ])
        XCTAssertEqual(StationMasterAdvice.crowdSurge(in: world),
                       .crowdSurgeComing(station: station, name: "Arena", days: 3, percent: 60, opens: 1_080, closes: 1_290))
    }

    /// The screenshot scenes' seed draws what they say: a crowd surge
    /// 19:00–21:00 on day 5, announced at the third midnight.
    func testTheScreenshotScenesHaveTheirSurge() throws {
        let world = ScreenshotScene.crowdSurge.make(in: .traditionalChinese)
        XCTAssertEqual(world.clock.now.seconds, 3 * GameTime.secondsPerDay + 8 * 3_600)
        let advice = try XCTUnwrap(StationMasterAdvice.crowdSurge(in: world))
        guard case .crowdSurgeComing(_, _, let days, _, let opens, let closes) = advice else { return XCTFail("\(advice)") }
        XCTAssertEqual(days, 2)
        XCTAssertEqual(opens, 1_140)
        XCTAssertEqual(closes, 1_260)
    }
}
