import Foundation
@testable import GameCore
import XCTest

/// Weather, typhoons and the fuel price (decision 162): drawn from the
/// disruptions' seed and the day, lowering demand or changing the day's
/// energy cost, on the switch and level of decision 154.
final class WeatherTests: XCTestCase {
    private let ids = (1...4).map { StationID(rawValue: $0) }

    /// Four stations on a line with demand, Taiwan's disruptions at
    /// `level` with `seed`, starting at game day `day`.
    private func world(seed: UInt32? = 7, level: DisruptionLevel = .standard, country: String = "TW", day: Int64 = 0) throws -> GameWorld {
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
        world.setDisruptions(Disruptions(level: level, country: country, seed: seed))
        world.setSpeed(.normal)
        return world
    }

    private func trips(_ world: GameWorld, from id: StationID) -> Int64 {
        world.dailyDemand(from: id).reduce(0) { $0 + $1.trips }
    }

    /// The first day from `from` whose weather is `weather`.
    private func firstDay(with weather: Weather, seed: UInt32 = 7, from: Int64 = 30) -> Int64 {
        let disruptions = Disruptions(level: .standard, country: "TW", seed: seed)!
        return (from...(from + 3_600)).first { disruptions.weather(onDay: $0) == weather }!
    }

    func testWithoutASeedThereAreOnlyHolidays() throws {
        let plain = Disruptions(level: .standard, country: "TW")!
        XCTAssertNil(plain.seed)
        for day in Int64(0)..<720 {
            XCTAssertEqual(plain.weather(onDay: day), .clear)
            XCTAssertNil(plain.fuelSpell(onDay: day))
        }
        XCTAssertTrue(plain.typhoons(ofYear: 0, in: try WorldBounds(width: 1_024, height: 1_024)).isEmpty)
        // A world without a seed saves as decision 154 did.
        let world = try world(seed: nil)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains(#""disruptions":{"#))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains("seed"))
    }

    func testTheWeatherIsTheSeedsAndTheDaysAndCalmAtFirst() {
        let a = Disruptions(level: .standard, country: "TW", seed: 7)!, b = Disruptions(level: .light, country: "JP", seed: 7)!
        let other = Disruptions(level: .standard, country: "TW", seed: 8)!
        // The first 30 days are clear.
        XCTAssertTrue((0..<Disruptions.calmDays).allSatisfy { a.weather(onDay: $0) == .clear })
        // The same seed and day give the same weather, whatever the level
        // or the country; another seed other weather.
        let year = (Int64(360)..<720)
        XCTAssertEqual(year.map(a.weather(onDay:)), year.map(b.weather(onDay:)))
        XCTAssertNotEqual(year.map(a.weather(onDay:)), year.map(other.weather(onDay:)))
        // Rain about as often as each month's chances: the plum rains of
        // May and June, afternoon thunderstorms in July and August, none in
        // winter.
        func share(_ weather: Weather, month: Int64) -> Int64 {
            // Ten years of that month, in thousandths.
            let days = (0..<10).flatMap { y in (0..<30).map { 360 * (y + 1) + month * 30 + Int64($0) } }
            return Int64(days.count { a.weather(onDay: $0) == weather }) * 1_000 / Int64(days.count)
        }
        XCTAssertTrue((350...550).contains(share(.rain, month: 4)), "May: \(share(.rain, month: 4))")
        XCTAssertTrue((180...320).contains(share(.thunderstorm, month: 6)), "July: \(share(.thunderstorm, month: 6))")
        XCTAssertEqual(share(.thunderstorm, month: 0), 0)
    }

    func testRainLowersTheWholeNetworksDemand() throws {
        let rain = firstDay(with: .rain), storm = firstDay(with: .thunderstorm)
        for (day, standard, light) in [(rain, Int64(900), Int64(950)), (storm, 800, 900)] {
            let calm = try world(seed: nil, day: day)
            let wet = try world(day: day), lighter = try world(level: .light, day: day)
            XCTAssertNil(calm.holiday(onDay: day), "the test wants a day without a holiday")
            XCTAssertEqual(wet.weatherMultiplier, standard)
            XCTAssertEqual(lighter.weatherMultiplier, light)
            for id in ids {
                XCTAssertEqual(trips(wet, from: id), (trips(calm, from: id) * standard + 500) / 1_000, "\(day) \(id)")
            }
        }
    }

    /// A seed whose second year has one typhoon, over station S1 and not
    /// S3, and the typhoon.
    private func typhoonOverS1() throws -> (seed: UInt32, typhoon: Typhoon) {
        let world = try world()
        let point = world.station(id: ids[1])!.point
        for seed in UInt32(1)...500 {
            let disruptions = Disruptions(level: .standard, country: "TW", seed: seed)!
            // The year's only typhoon, so no other blows round it.
            let typhoons = disruptions.typhoons(ofYear: 1, in: world.bounds)
            if typhoons.count == 1, let typhoon = typhoons.first, typhoon.covers(point), !typhoon.covers(world.station(id: ids[3])!.point) {
                return (seed, typhoon)
            }
        }
        throw XCTSkip("no seed to 500 has a typhoon over S1 alone")
    }

    func testTyphoonsComeInTheSeasonWithNotice() throws {
        let bounds = try WorldBounds(width: 1_048_576, height: 524_288)
        var count = 0, light = 0
        for seed in UInt32(1)...200 {
            let standard = Disruptions(level: .standard, country: "TW", seed: seed)!
            for (year, typhoons) in (0..<3).map({ ($0, standard.typhoons(ofYear: Int64($0), in: bounds)) }) {
                count += typhoons.count
                XCTAssertLessThanOrEqual(typhoons.count, 3)
                XCTAssertEqual(typhoons.map(\.start), typhoons.map(\.start).sorted())
                for typhoon in typhoons {
                    XCTAssertTrue(Disruptions.typhoonSeason.contains(typhoon.start - Int64(year) * 360))
                    XCTAssertTrue((1...3).contains(typhoon.start - typhoon.announced))
                    XCTAssertTrue((1...2).contains(typhoon.end - typhoon.start))
                    XCTAssertTrue((0...bounds.width).contains(typhoon.centre.x) && (0...bounds.height).contains(typhoon.centre.y))
                    XCTAssertTrue((bounds.width * 3 / 10...bounds.width * 6 / 10).contains(typhoon.radius))
                    XCTAssertEqual(typhoon.drop, 800)
                }
            }
            light += Disruptions(level: .light, country: "TW", seed: seed)!.typhoons(ofYear: 1, in: bounds).count
            // No typhoon where none comes.
            XCTAssertTrue(Disruptions(level: .standard, country: "GB", seed: seed)!.typhoons(ofYear: 1, in: bounds).isEmpty)
        }
        // Three chances of a half each: about 1.5 a year.
        XCTAssertTrue((700...1_100).contains(count), "\(count) in 600 years")
        // Half as likely at the light level, and half as strong.
        XCTAssertTrue((100...200).contains(light), "\(light) in 200 years")
        XCTAssertTrue(Disruptions(level: .light, country: "TW", seed: 3)!.typhoons(ofYear: 1, in: bounds).allSatisfy { $0.drop == 400 })
    }

    func testATyphoonCutsTheDemandOfTheStationsItCovers() throws {
        let (seed, typhoon) = try typhoonOverS1()
        // Announced, then blowing.
        let before = try world(seed: seed, day: typhoon.announced - 1)
        XCTAssertFalse(before.typhoons(onDay: typhoon.announced - 1).contains(typhoon))
        XCTAssertTrue(try world(seed: seed, day: typhoon.announced).typhoons(onDay: typhoon.announced).contains(typhoon))
        let blowing = try world(seed: seed, day: typhoon.start)
        let plain = try world(seed: nil, day: typhoon.start)
        XCTAssertEqual(blowing.typhoonMultiplier(at: ids[1]), 200)
        XCTAssertEqual(blowing.typhoonMultiplier(at: ids[3]), 1_000)
        // S1 sets out with a fifth of its trips (and today's weather), and
        // draws a fifth as many to it.
        let weather = blowing.weatherMultiplier
        let holiday = blowing.holidayMultiplier
        let expected = (trips(plain, from: ids[1]) * 200 * holiday * weather / 1_000 + 500_000) / 1_000_000
        XCTAssertTrue(abs(trips(blowing, from: ids[1]) - expected) <= 1, "\(trips(blowing, from: ids[1])) against \(expected)")
        let share = { (world: GameWorld) in world.dailyDemand(from: self.ids[0]).first { $0.destination == self.ids[1] }!.trips * 1_000 / max(1, self.trips(world, from: self.ids[0])) }
        XCTAssertLessThan(share(blowing), share(plain))
        // Over, it is gone.
        XCTAssertEqual(try world(seed: seed, day: typhoon.end).typhoonMultiplier(at: ids[1]), 1_000)
    }

    func testFuelSpellsComeAfterSixWeeksAndChangeTheDaysEnergy() throws {
        let standard = Disruptions(level: .standard, country: "TW", seed: 7)!, light = Disruptions(level: .light, country: "TW", seed: 7)!
        XCTAssertTrue((0..<42).allSatisfy { standard.fuelSpell(onDay: $0) == nil })
        let spells = (Int64(0)..<3_600).compactMap(standard.fuelSpell(onDay:))
        XCTAssertFalse(spells.isEmpty)
        for spell in Set(spells) {
            XCTAssertTrue((7...14).contains(spell.end - spell.start))
            XCTAssertTrue((1_120...1_320).contains(spell.index) || (880...960).contains(spell.index), "\(spell.index)")
            // Half as far from 1 at the light level.
            XCTAssertEqual(light.fuelSpell(onDay: spell.start)?.index, 1_000 + (spell.index - 1_000) / 2)
        }
        // A managed day in a spell pays its index of the day's energy.
        let spell = spells.first!
        var managed = try world(day: spell.start)
        var plain = try world(seed: nil, day: spell.start)
        for index in [0, 1] {
            var world = index == 0 ? managed : plain
            // A train in service, so the day has energy to pay.
            try world.setLineTrainsInService(world.lines[0].id, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
            world.setEconomyMode(.management)
            if index == 0 { managed = world } else { plain = world }
        }
        // The day is settled at the next midnight's first minute.
        try managed.advance(ticks: 1_441)
        try plain.advance(ticks: 1_441)
        let energy = { (world: GameWorld) in world.accounts.days.first { $0.day == spell.start }!.energyCost.amount }
        XCTAssertNotEqual(energy(plain), 0)
        // Each part is rounded to whole dollars: within a dollar of each.
        XCTAssertTrue(abs(energy(managed) * 1_000 - energy(plain) * spell.index) <= 2 * 100 * 1_000, "\(energy(managed)) against \(energy(plain)) × \(spell.index)")
    }

    func testBatchesMatchMinuteStepsThroughATyphoonAndSavesContinue() throws {
        let (seed, typhoon) = try typhoonOverS1()
        var batched = try world(seed: seed, day: typhoon.announced - 1)
        var stepped = batched
        let minutes = Int((typhoon.end - typhoon.announced + 2) * 1_440 + 7)
        try batched.advance(ticks: minutes)
        for _ in 0..<minutes { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        try loaded.advance(ticks: 1_440 * 3)
        try batched.advance(ticks: 1_440 * 3)
        XCTAssertEqual(loaded, batched)
        for station in batched.stations {
            let ledger = batched.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        }
    }

    func testTheSeedIsSavedAndAWrongOneRefused() throws {
        let world = try world(seed: 4_000_000_000)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""disruptions":{"country":"TW","level":"standard","seed":4000000000}"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        for bad in [#""seed":-1"#, #""seed":4294967296"#, #""seed":"7""#] {
            let broken = String(decoding: data, as: UTF8.self).replacingOccurrences(of: #""seed":4000000000"#, with: bad)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
    }

    /// Version 41 (decision 162): Taiwan's disruptions with seed 7 at the
    /// standard level, the first rainy day after the calm days, its first
    /// half hour. It saves byte for byte and is the world this build makes.
    func testVersionFortyOneKeepsTheSeed() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v41-weather.json")
        var made = try world(day: firstDay(with: .rain))
        try made.advance(ticks: 30)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["WEATHER_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 41)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.disruptions?.seed, 7)
        XCTAssertEqual(world.weather(onDay: firstDay(with: .rain)), .rain)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 41,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
