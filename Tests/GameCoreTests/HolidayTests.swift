import Foundation
@testable import GameCore
import XCTest

/// Public holidays (decision 154): each country's holidays on the same days
/// of every game year, raising the whole network's demand while they run.
final class HolidayTests: XCTestCase {
    private let ids = (1...4).map { StationID(rawValue: $0) }

    /// Four stations on a line, with demand, starting at game day `day`.
    private func world(_ disruptions: Disruptions? = Disruptions(level: .standard, country: "TW"), weekly: Bool = true, day: Int64 = 0) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 16_384, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: day * GameTime.secondsPerDay))
        )
        let track = TestLine(tiles: 14)
        try track.build(in: &world)
        for (index, x) in [1, 5, 9, 13].enumerated() {
            try track.buildStation(named: "S\(index)", beside: x, at: 1, in: &world)
        }
        let line = try world.createLine(named: "L", stops: ids).id
        try world.setLineServiceWindow(line, to: .allDay)
        for (index, id) in ids.enumerated() {
            try world.setStationDemand(id, to: StationDemand(kind: index % 2 == 0 ? .residential : .office, dailyTrips: Int64(1_000 * (index + 1))))
        }
        world.setWeeklyDemand(weekly)
        world.setDisruptions(disruptions)
        world.setSpeed(.normal)
        return world
    }

    private func total(_ world: GameWorld) -> Int64 {
        ids.reduce(0) { sum, id in sum + world.dailyDemand(from: id).reduce(0) { $0 + $1.trips } }
    }

    func testEveryCountrysHolidaysFitTheGameYear() {
        XCTAssertNotNil(HolidayCalendar.countries[HolidayCalendar.home])
        XCTAssertEqual(HolidayCalendar.countries.count, 24)
        for (country, holidays) in HolidayCalendar.countries {
            XCTAssertEqual(country.count, 2, country)
            XCTAssertFalse(holidays.isEmpty, country)
            var taken = Set<Int64>()
            for holiday in holidays {
                XCTAssertTrue((1...12).contains(holiday.month) && (1...30).contains(holiday.day), "\(country) \(holiday)")
                XCTAssertTrue((1...9).contains(holiday.days), "\(country) \(holiday)")
                XCTAssertTrue((1...200).contains(holiday.boost), "\(country) \(holiday)")
                // Within its year, and on days no other holiday of its
                // country has.
                XCTAssertLessThanOrEqual(holiday.dayOfYear + holiday.days, FinancePeriod.year.days, "\(country) \(holiday)")
                for day in holiday.dayOfYear..<(holiday.dayOfYear + holiday.days) {
                    XCTAssertTrue(taken.insert(day).inserted, "\(country) \(holiday)")
                }
            }
            // Listed by the day they start.
            XCTAssertEqual(holidays.map(\.dayOfYear), holidays.map(\.dayOfYear).sorted(), country)
        }
        // Taiwan's are TW_DAYTYPE's: New Year, nine days of the Spring
        // Festival, 228, four days of Children's Day and Qingming, Labour
        // Day, the Dragon Boat and Mid-Autumn festivals and National Day.
        XCTAssertEqual(HolidayCalendar.countries["TW"]!.map(\.kind), [
            .newYear, .springFestival, .peaceMemorial, .qingming, .labourDay, .dragonBoat, .midAutumn, .nationalDay,
        ])
        XCTAssertEqual(HolidayCalendar.countries["TW"]!.map(\.days), [1, 9, 1, 4, 1, 1, 1, 1])
    }

    func testAHolidayComesOnTheSameDaysEveryYear() throws {
        let world = try world()
        // 1 January is day 0; the Spring Festival runs from 14 February
        // (day 43) for nine days; 10 October is day 279.
        XCTAssertEqual(world.holiday(onDay: 0)?.holiday.kind, .newYear)
        XCTAssertEqual(world.holiday(onDay: 0)?.boost, 50)
        XCTAssertNil(world.holiday(onDay: 1))
        XCTAssertNil(world.holiday(onDay: 42))
        for day in Int64(43)...51 {
            let run = try XCTUnwrap(world.holiday(onDay: day))
            XCTAssertEqual(run.holiday.kind, .springFestival)
            XCTAssertEqual(run.start, 43)
            XCTAssertEqual(run.end, 52)
            XCTAssertEqual(run.boost, 200)
        }
        XCTAssertNil(world.holiday(onDay: 52))
        XCTAssertEqual(world.holiday(onDay: 279)?.holiday.kind, .nationalDay)
        // A year later, and a year before the game began.
        XCTAssertEqual(world.holiday(onDay: 360 + 47)?.start, 360 + 43)
        XCTAssertEqual(world.holiday(onDay: -360 + 279)?.holiday.kind, .nationalDay)
        // The runs on any of some days, by start.
        XCTAssertEqual(world.holidays(from: 40, through: 120).map(\.holiday.kind), [.springFestival, .peaceMemorial, .qingming, .labourDay])
        XCTAssertEqual(world.holidays(from: 50, through: 50).map(\.holiday.kind), [.springFestival])
        XCTAssertEqual(world.holidays(from: 359, through: 361).map(\.start), [360])
        XCTAssertTrue(world.holidays(from: 5, through: 4).isEmpty)
        // Light disruptions add half.
        var light = world
        light.setDisruptions(Disruptions(level: .light, country: "TW"))
        XCTAssertEqual(light.holiday(onDay: 43)?.boost, 100)
        XCTAssertEqual(light.holiday(onDay: 0)?.boost, 25)
        // Another country keeps its own.
        var china = world
        china.setDisruptions(Disruptions(level: .standard, country: "CN"))
        XCTAssertEqual(china.holiday(onDay: 270)?.holiday.kind, .nationalDay)
        XCTAssertNil(china.holiday(onDay: 279))
        // Without disruptions there are none.
        var off = world
        off.setDisruptions(nil)
        XCTAssertNil(off.holiday(onDay: 0))
        XCTAssertEqual(off.holidayMultiplier, 1_000)
    }

    func testAHolidayRaisesTheNetworksDemandAndFollowsTheWeekendsHours() throws {
        let plain = try world(nil)
        let with = try world()
        // Day 0 is New Year's Day, +5%: each origin's trips, rounded half up.
        XCTAssertEqual(with.holidayMultiplier, 1_050)
        for id in ids {
            let before = plain.dailyDemand(from: id).reduce(0) { $0 + $1.trips }
            XCTAssertEqual(with.dailyDemand(from: id).reduce(0) { $0 + $1.trips }, (before * 1_050 + 500) / 1_000, "\(id)")
        }
        // A day without a holiday is as before.
        XCTAssertEqual(total(try world(day: 1)), total(try world(nil, day: 1)))
        // On a holiday the day follows the weekend's hours: day 120, Labour
        // Day, is a Tuesday.
        XCTAssertEqual(StationDemand.weekday(ofDay: 120), 2)
        let holiday = try world(day: 120), weekday = try world(nil, day: 120)
        XCTAssertTrue(holiday.isDemandWeekend)
        XCTAssertFalse(weekday.isDemandWeekend)
        XCTAssertNotEqual(holiday.hourlyDemand(from: ids[0], to: ids[1]).map { $0 * 1_000 / max(1, holiday.dailyDemand(from: ids[0], to: ids[1])) },
                          weekday.hourlyDemand(from: ids[0], to: ids[1]).map { $0 * 1_000 / max(1, weekday.dailyDemand(from: ids[0], to: ids[1])) })
        // Without weekly demand the hours stay the day's.
        XCTAssertFalse(try world(weekly: false, day: 120).isDemandWeekend)
    }

    func testHolidaysMoveDemandWithEventsRoundedOnce() throws {
        var world = try world()
        world.setDemandEvents(seed: 1)
        let station = ids[2]
        world.demandEvents!.events = [DemandEvent(kind: .exhibition, station: station, announced: 0, start: 0, end: 3, boost: 333)]
        var plain = world
        plain.setDisruptions(nil)
        plain.demandEvents = nil
        let before = plain.dailyDemand(from: station).reduce(0) { $0 + $1.trips }
        // 1.333 × 1.05, rounded half up once.
        XCTAssertEqual(world.dailyDemand(from: station).reduce(0) { $0 + $1.trips }, (before * 1_333 * 1_050 + 500_000) / 1_000_000)
    }

    func testBatchesMatchMinuteStepsAcrossAHolidayAndSavesContinue() throws {
        var batched = try world()
        try batched.advance(ticks: 1_440 * 41)
        var stepped = batched
        // Through the first three days of the Spring Festival.
        try batched.advance(ticks: 1_440 * 5 + 7)
        for _ in 0..<(1_440 * 5 + 7) { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        try loaded.advance(ticks: 1_440 * 8)
        try batched.advance(ticks: 1_440 * 8)
        XCTAssertEqual(loaded, batched)
        for station in batched.stations {
            let ledger = batched.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        }
    }

    func testAHolidayReleasesMorePassengersThanTheSameDayWithout() throws {
        var with = try world(day: 43)
        var without = try world(nil, day: 43)
        try with.advance(ticks: 1_440)
        try without.advance(ticks: 1_440)
        let released = { (world: GameWorld) in self.ids.reduce(Int64(0)) { $0 + world.passengerLedger(of: $1).released } }
        XCTAssertGreaterThan(released(with), released(without))
    }

    func testSavedOnlyWhenOnAndAnUnknownCountryIsRefused() throws {
        XCTAssertNil(Disruptions(level: .light, country: "XX"))
        XCTAssertNil(Disruptions(level: .light, country: "tw"))
        let off = try world(nil)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(off), as: UTF8.self).contains("disruptions"))
        let on = try world(Disruptions(level: .light, country: "JP"))
        // Sorted keys, so the text to look for has one order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(on)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""disruptions":{"country":"JP","level":"light"}"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), on)
        for bad in [#""disruptions":{"country":"XX","level":"light"}"#, #""disruptions":{"country":"JP","level":"severe"}"#] {
            let broken = String(decoding: data, as: UTF8.self).replacingOccurrences(of: #""disruptions":{"country":"JP","level":"light"}"#, with: bad)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
        // Turning them off forgets them.
        var world = on
        world.setDisruptions(nil)
        XCTAssertNil(world.disruptions)
    }

    /// Version 37 (decision 154): Taiwan's holidays at the standard level,
    /// the first half hour of New Year's Day. It saves
    /// byte for byte and is the world this build makes.
    func testVersionThirtySevenKeepsTheHolidays() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v37-holidays.json")
        var made = try world()
        try made.advance(ticks: 30)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["HOLIDAYS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 37)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.disruptions, Disruptions(level: .standard, country: "TW"))
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 37,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
