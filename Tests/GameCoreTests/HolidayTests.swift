import Foundation
@testable import GameCore
import XCTest

/// Public holidays (decision 154): each country's holidays on the same days
/// of every game year, Taiwan's worked out for each year (decision 211),
/// raising the whole network's demand while they run.
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
        // Day, the Dragon Boat and Mid-Autumn festivals, Teachers' Day,
        // National Day, Retrocession Day and Constitution Day (decision 208).
        XCTAssertEqual(HolidayCalendar.countries["TW"]!.map(\.kind), [
            .newYear, .springFestival, .peaceMemorial, .qingming, .labourDay, .dragonBoat, .midAutumn, .teachersDay,
            .nationalDay, .retrocessionDay, .constitutionDay,
        ])
        XCTAssertEqual(HolidayCalendar.countries["TW"]!.map(\.days), [1, 9, 1, 4, 1, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(HolidayCalendar.countries["TW"]!.map(\.dayOfYear), [0, 43, 57, 92, 120, 168, 264, 267, 279, 294, 354])
    }

    func testTaiwansHolidaysFollowTheLawOnTheGamesOwnWeek() throws {
        let world = try world()
        func run(_ day: Int64) -> (HolidayKind, Int64, Int64)? {
            world.holiday(onDay: day).map { ($0.holiday.kind, $0.start, $0.end) }
        }
        // Game year 0 is 2026; day 0, 1 January, is a Monday, so New Year's
        // Day joins the weekend before it.
        XCTAssertEqual(StationDemand.weekday(ofDay: 0), 1)
        XCTAssertTrue(run(0)! == (.newYear, -2, 1))
        XCTAssertEqual(world.holiday(onDay: 0)?.boost, 50)
        XCTAssertNil(run(1))
        // The Lunar New Year (17 February 2026, day 46): from the day before
        // New Year's Eve (day 44, a Wednesday) to the third day (Sunday),
        // and the Saturday's and Sunday's made up on Monday and Tuesday.
        XCTAssertNil(run(43))
        for day in Int64(44)...50 {
            XCTAssertTrue(run(day)! == (.springFestival, 44, 51), "\(day)")
            XCTAssertEqual(world.holiday(onDay: day)?.boost, 200)
        }
        XCTAssertNil(run(51))
        // 28 February is a Tuesday: one day.
        XCTAssertTrue(run(57)! == (.peaceMemorial, 57, 58))
        // Children's Day (4 April) and Qingming (5 April in 2026): Wednesday
        // and Thursday.
        XCTAssertTrue(run(93)! == (.qingming, 93, 95))
        // The Mid-Autumn Festival (25 September) is a Saturday: made up on
        // the Friday before. Teachers' Day (28 September) is a Tuesday.
        XCTAssertTrue(run(264)! == (.midAutumn, 263, 266))
        XCTAssertTrue(run(267)! == (.teachersDay, 267, 268))
        // National Day (10 October) is a Sunday: made up on the Monday.
        XCTAssertEqual(StationDemand.weekday(ofDay: 279), 0)
        XCTAssertTrue(run(279)! == (.nationalDay, 278, 281))
        // A year later (2027) the week has moved three days and the lunar
        // dates their own way: National Day is a Wednesday, the Lunar New
        // Year (6 February) starts on day 393.
        XCTAssertTrue(run(360 + 279)! == (.nationalDay, 639, 640))
        XCTAssertTrue(run(395)! == (.springFestival, 393, 400))
        // And a year before the game began (2025), National Day is a Thursday.
        XCTAssertTrue(run(-81)! == (.nationalDay, -81, -80))
        // The runs on any of some days, by start.
        XCTAssertEqual(world.holidays(from: 40, through: 120).map(\.holiday.kind), [.springFestival, .peaceMemorial, .qingming, .labourDay])
        XCTAssertEqual(world.holidays(from: 50, through: 50).map(\.holiday.kind), [.springFestival])
        XCTAssertEqual(world.holidays(from: 359, through: 361).map(\.start), [360])
        XCTAssertTrue(world.holidays(from: 5, through: 4).isEmpty)
        // Light disruptions add half.
        var light = world
        light.setDisruptions(Disruptions(level: .light, country: "TW"))
        XCTAssertEqual(light.holiday(onDay: 44)?.boost, 100)
        XCTAssertEqual(light.holiday(onDay: 0)?.boost, 25)
        // Another country keeps its own days, the same every year.
        var china = world
        china.setDisruptions(Disruptions(level: .standard, country: "CN"))
        XCTAssertEqual(china.holiday(onDay: 270)?.holiday.kind, .nationalDay)
        XCTAssertEqual(china.holiday(onDay: 360 + 270)?.start, 360 + 270)
        XCTAssertNil(china.holiday(onDay: 279))
        // Without disruptions there are none.
        var off = world
        off.setDisruptions(nil)
        XCTAssertNil(off.holiday(onDay: 0))
        XCTAssertEqual(off.holidayMultiplier, 1_000)
    }

    func testEveryTaiwaneseYearHasItsHolidaysOnce() {
        // From 2024 to well past the table's end (2100), where the dates
        // come round every 19 years.
        for year in Int64(-2)...Int64(120) {
            let runs = TaiwanHolidays.runs(from: year * 360, through: year * 360 + 359, level: .standard)
            // By start, never overlapping, each with a day off.
            for (earlier, later) in zip(runs, runs.dropFirst()) {
                XCTAssertLessThanOrEqual(earlier.end, later.start, "\(year)")
            }
            let days = TaiwanHolidays.daysOff(inYear: year)
            XCTAssertEqual(Set(days.map(\.day)).count, days.count, "a day off is taken once, \(year)")
            // The Lunar New Year's five days and as many more as fell on a
            // weekend; every other holiday one day (Children's Day and
            // Qingming two), on the day or made up.
            XCTAssertGreaterThanOrEqual(days.filter { $0.kind == .springFestival }.count, 5, "\(year)")
            XCTAssertLessThanOrEqual(days.filter { $0.kind == .springFestival }.count, 7, "\(year)")
            for kind in [HolidayKind.newYear, .peaceMemorial, .labourDay, .dragonBoat, .midAutumn, .teachersDay, .nationalDay, .retrocessionDay, .constitutionDay] {
                XCTAssertLessThanOrEqual(days.filter { $0.kind == kind }.count, 1, "\(kind) \(year)")
            }
            XCTAssertLessThanOrEqual(days.filter { $0.kind == .qingming }.count, 2, "\(year)")
            // No day off is a weekend's: those are made up.
            XCTAssertTrue(days.allSatisfy { !StationDemand.isWeekend(day: $0.day) || $0.kind == .springFestival }, "\(year)")
            // Each run is in the year's holidays (weekly, a run holds no
            // more than a week and a half).
            XCTAssertTrue(runs.allSatisfy { $0.end - $0.start <= 11 }, "\(year)")
        }
        // Outside the table a year takes the dates of one 19 years away.
        XCTAssertEqual(TaiwanHolidays.lunarDates(ofRealYear: 2101), TaiwanHolidays.lunarDates(ofRealYear: 2082))
        XCTAssertEqual(TaiwanHolidays.lunarDates(ofRealYear: 2024), TaiwanHolidays.lunarDates(ofRealYear: 2043))
        XCTAssertEqual(TaiwanHolidays.lunarDates(ofRealYear: 2026), [217, 405, 619, 925])
    }

    /// The rules on the real calendar give the owner's reference's days off
    /// (`Railway/site_archive_clean/index.html`, `TW_DAYTYPE`: Taiwan's days
    /// off of 2026 and 2027, the 31 December of 2027 being 2028's New
    /// Year's Day made up), counting the days that are not weekends.
    func testOnTheRealCalendarTheRulesGiveTheReferencesDaysOff() {
        // Days since 1 January 2026 (a Thursday), for the real calendar.
        @Sendable func days(_ year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
            let y = month <= 2 ? year - 1 : year
            let era = (y >= 0 ? y : y - 399) / 400
            let yoe = y - era * 400
            let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return era * 146_097 + doe - 719_468 - 20_454
        }
        let real = TaiwanHolidays.Week(
            day: { mmdd, year in days(2026 + year, Int64(mmdd / 100), Int64(mmdd % 100)) },
            weekday: { day in Int(((day + 4) % 7 + 7) % 7) }
        )
        XCTAssertEqual(days(2026, 1, 1), 0)
        XCTAssertEqual(days(2027, 1, 1), 365)
        let reference: [Int64: [String]] = [
            2026: ["01-01", "02-15", "02-16", "02-17", "02-18", "02-19", "02-20", "02-27", "02-28", "04-03", "04-04", "04-05",
                   "04-06", "05-01", "06-19", "09-25", "09-28", "10-09", "10-10", "10-25", "10-26", "12-25"],
            2027: ["01-01", "02-04", "02-05", "02-06", "02-07", "02-08", "02-09", "02-10", "02-28", "03-01", "04-04", "04-05",
                   "04-06", "04-30", "05-01", "06-09", "09-15", "09-28", "10-10", "10-11", "10-25", "12-24", "12-25", "12-31"],
        ]
        let off = (0...2).flatMap { TaiwanHolidays.daysOff(inYear: $0, on: real).map(\.day) }
        for (year, dates) in reference {
            let expected = Set(dates.map { days(year, Int64($0.prefix(2))!, Int64($0.suffix(2))!) }.filter { !real.isWeekend($0) })
            let start = days(year, 1, 1), end = days(year + 1, 1, 1)
            XCTAssertEqual(Set(off.filter { (start..<end).contains($0) && !real.isWeekend($0) }), expected, "\(year)")
        }
    }

    func testChildrensDayAndQingmingOnOneDay() {
        // In 2025 (game year -1) Qingming is 4 April, Children's Day too:
        // Children's Day is the day before, or the day after when 4 April is
        // a Thursday (both made up when on a weekend).
        XCTAssertEqual(TaiwanHolidays.lunarDates(ofRealYear: 2025)[1], 404)
        let fourth = TaiwanHolidays.day(404, inYear: -1)
        let days = TaiwanHolidays.daysOff(inYear: -1).filter { $0.kind == .qingming }.map(\.day)
        XCTAssertEqual(days.count, 2)
        if StationDemand.weekday(ofDay: fourth) == 4 {
            XCTAssertTrue(days.contains(fourth + 1))
        } else if !StationDemand.isWeekend(day: fourth - 1) {
            XCTAssertTrue(days.contains(fourth - 1))
        }
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
        var with = try world(day: 44)
        var without = try world(nil, day: 44)
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
