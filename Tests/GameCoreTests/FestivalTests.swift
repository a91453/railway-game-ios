import Foundation
@testable import GameCore
import XCTest

/// Taiwan's named festivals (decision 576): lunar dates worked out year by
/// year, announced at the stations round their place.
final class FestivalTests: XCTestCase {
    private func day(_ mmdd: Int, _ year: Int64) -> Int64 { TaiwanHolidays.day(mmdd, inYear: year) }

    func testTheDatesFollowTheLunarCalendarYearByYear() {
        // 2026: the Lantern Festival 3 March, the Dajia pilgrimage's start
        // 17 April (Dajia Jenn Lann Temple's announcement), Mid-Autumn 25 Sep.
        XCTAssertEqual(FestivalKind.lanternFestival.start(inGameYear: 0), day(303, 0))
        XCTAssertEqual(FestivalKind.mazuProcession.start(inGameYear: 0), day(417, 0))
        XCTAssertEqual(FestivalKind.midAutumn.start(inGameYear: 0), day(925, 0))
        XCTAssertEqual(FestivalKind.newYearsEve.start(inGameYear: 0), day(1_231, 0))
        // 2027: they have moved.
        XCTAssertEqual(FestivalKind.lanternFestival.start(inGameYear: 1), day(220, 1))
        XCTAssertEqual(FestivalKind.mazuProcession.start(inGameYear: 1), day(407, 1))
        XCTAssertNotEqual(FestivalKind.lanternFestival.start(inGameYear: 1) - 360, FestivalKind.lanternFestival.start(inGameYear: 0))
        // Past the table (2100) the years come round every 19 years.
        XCTAssertEqual(FestivalKind.lanternFestival.start(inGameYear: 2_101 - 2_026) % 360, FestivalKind.lanternFestival.start(inGameYear: 2_082 - 2_026) % 360)
        XCTAssertTrue(FestivalKind.lanternFestival.starts(onDay: day(303, 0)))
        XCTAssertFalse(FestivalKind.lanternFestival.starts(onDay: day(303, 0) + 1))
    }

    func testEveryFestivalHasADateInEveryYear() {
        for kind in FestivalKind.allCases {
            for year in Int64(-30)...Int64(160) {
                let start = kind.start(inGameYear: year)
                XCTAssertEqual(CompanyAccounts.floorDivide(start, 360), year, "\(kind) \(year)")
                XCTAssertTrue((1...30).contains(kind.days) && (1...2_000).contains(kind.boost) && (0...30).contains(kind.notice))
            }
        }
    }

    func world() throws -> GameWorld {
        var world = try makeWorld(width: 65_536, height: 4_096, balance: 100_000_000)
        let track = TestLine(tiles: 30)
        try track.build(in: &world)
        for (index, x) in [1, 3, 5, 25].enumerated() {
            try track.buildStation(named: "S\(index)", beside: x, at: 1, in: &world)
        }
        let ids = world.stations.map(\.id)
        let line = try world.createLine(named: "L", stops: ids).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.assignTrain(world.purchaseTrain(named: "T").id, to: line)
        for id in ids {
            try world.setStationDemand(id, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        }
        world.setDemandEvents(seed: 42)
        world.setSpeed(.normal)
        return world
    }

    func testAFestivalIsAnnouncedAtTheNearestStationsItsNoticeAhead() throws {
        var world = try world()
        let near = world.stations[0]
        world.setFestivalSites([FestivalSite(kind: .lanternFestival, point: near.point)])
        XCTAssertEqual(world.demandEvents?.sites.count, 1)
        let notice = FestivalKind.lanternFestival.notice
        let start = FestivalKind.lanternFestival.start(inGameYear: 0)
        var announced: [DemandEvent] = []
        for _ in 0..<Int(start - notice + 1) {
            try world.advance(ticks: 1_440)
            announced += world.demandEvents!.events.filter { $0.festival != nil && !announced.contains($0) }
        }
        XCTAssertFalse(announced.isEmpty)
        XCTAssertTrue(announced.allSatisfy { $0.kind == .festival && $0.festival == .lanternFestival && $0.start == start && $0.end == start + 3 && $0.boost == 1_000 })
        XCTAssertEqual(announced.first?.station, near.id, "the nearest first")
        XCTAssertLessThanOrEqual(announced.count, FestivalKind.stationsPerSite)
        XCTAssertFalse(announced.contains { $0.station == world.stations[3].id }, "the far station is out of reach")
        XCTAssertEqual(announced.first?.announced, start - notice)
        XCTAssertNil(world.demandEventProblem())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testSitesNeedDemandEventsAndStayOnTheMap() throws {
        var world = try world()
        world.setFestivalSites([FestivalSite(kind: .midAutumn, point: PlanPoint(x: 1, y: 1)), FestivalSite(kind: .newYearsEve, point: PlanPoint(x: -5, y: 0))])
        XCTAssertEqual(world.demandEvents?.sites.map(\.kind), [.midAutumn], "a place off the map is left out")
        world.setDemandEvents(seed: 7)
        XCTAssertEqual(world.demandEvents?.sites.map(\.kind), [.midAutumn], "a new schedule keeps the places")
        world.setDemandEvents(seed: nil)
        world.setFestivalSites([FestivalSite(kind: .midAutumn, point: PlanPoint(x: 1, y: 1))])
        XCTAssertNil(world.demandEvents)
    }

    func testAScenarioFestivalCanFollowTheLunarDate() throws {
        let fixed = ScenarioEvent(station: StationID(rawValue: 1), dayOfYear: 62, days: 3, boost: 1_500, notice: 7)
        XCTAssertNil(fixed.follows)
        let moving = ScenarioEvent(station: StationID(rawValue: 1), dayOfYear: 62, days: 3, boost: 1_500, notice: 7, follows: .lanternFestival)
        XCTAssertEqual(try JSONDecoder().decode(ScenarioEvent.self, from: JSONEncoder().encode(moving)), moving)
        // A scenario saved before version 84 has no "follows".
        let old = Data(#"{"station":1,"dayOfYear":62,"days":3,"boost":1500,"notice":7}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ScenarioEvent.self, from: old).follows, nil)
    }

    func testAScheduleWithoutSitesReadsAsBefore() throws {
        let schedule = DemandEventSchedule(seed: 5, from: 0)
        let data = try JSONEncoder().encode(schedule)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("sites"), "an older save's bytes are the same")
        XCTAssertEqual(try JSONDecoder().decode(DemandEventSchedule.self, from: data), schedule)
    }

    /// The version 84 save: four festival places and the Lantern Festival
    /// announced at the stations round the first.
    func testTheVersion84SaveKeepsItsFestivals() throws {
        let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent("v84-festivals.json"))
        let game = try JSONDecoder().decode(SavedGame.self, from: data)
        let schedule = try XCTUnwrap(game.world.demandEvents)
        XCTAssertEqual(schedule.sites.map(\.kind), [.mazuProcession, .lanternFestival, .newYearsEve, .midAutumn])
        let lanterns = schedule.events.filter { $0.festival == .lanternFestival }
        XCTAssertEqual(lanterns.map(\.start), Array(repeating: FestivalKind.lanternFestival.start(inGameYear: 0), count: lanterns.count))
        XCTAssertFalse(lanterns.isEmpty)
        XCTAssertNil(game.world.demandEventProblem())
    }
}
