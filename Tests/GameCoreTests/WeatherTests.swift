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
            bounds: try WorldBounds(width: 16_384, height: 4_096), economy: fixtureEconomy(balance: 1_000_000, costs: testCosts),
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
        let a = Disruptions(level: .standard, country: "TW", seed: 7)!, b = Disruptions(level: .light, country: "GB", seed: 7)!
        let other = Disruptions(level: .standard, country: "TW", seed: 8)!
        // The first 30 days are clear.
        XCTAssertTrue((0..<Disruptions.calmDays).allSatisfy { a.weather(onDay: $0) == .clear })
        // The same seed and day give the same weather, whatever the level,
        // in Taiwan and a country without months of its own (decision
        // 1003); another seed other weather.
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

    /// Decision 1003: Hong Kong, Japan and Finland have their own months,
    /// from their weather offices' figures; every other country Taiwan's.
    func testEachCountryHasItsOwnMonths() {
        for (country, months) in Disruptions.countryRain {
            XCTAssertEqual(months.count, 12, country)
            XCTAssertTrue(months.allSatisfy { $0.rain >= 0 && $0.storm >= 0 && $0.rain + $0.storm <= 1_000 }, country)
            XCTAssertNotNil(HolidayCalendar.countries[country], country)
        }
        XCTAssertEqual(Set(Disruptions.countryRain.keys), ["HK", "JP", "FI"])
        XCTAssertEqual(Disruptions.monthlyRain(of: "TW").map(\.storm), Disruptions.monthlyRain.map(\.storm))
        XCTAssertEqual(Disruptions.monthlyRain(of: "GB").map(\.rain), Disruptions.monthlyRain.map(\.rain))
        /// The share of `month`'s days over forty years with `weather`, in
        /// thousandths.
        func share(_ country: String, _ weather: Weather, month: Int64) -> Int64 {
            let disruptions = Disruptions(level: .standard, country: country, seed: 7)!
            let days = (0..<40).flatMap { y in (0..<30).map { 360 * (y + 1) + month * 30 + Int64($0) } }
            return Int64(days.count { disruptions.weather(onDay: $0) == weather }) * 1_000 / Int64(days.count)
        }
        // Rovaniemi: no thunder from October to April, some in July; Hong
        // Kong: thunderstorms one day in four in August, a dry winter;
        // Fukuoka: the plum rains of June.
        for month in [0, 1, 2, 3, 9, 10, 11] as [Int64] {
            XCTAssertEqual(share("FI", .thunderstorm, month: month), 0, "FI month \(month + 1)")
        }
        XCTAssertTrue((70...180).contains(share("FI", .thunderstorm, month: 6)), "FI July: \(share("FI", .thunderstorm, month: 6))")
        XCTAssertTrue((220...360).contains(share("HK", .thunderstorm, month: 7)), "HK August: \(share("HK", .thunderstorm, month: 7))")
        XCTAssertTrue((60...150).contains(share("HK", .rain, month: 11) + share("HK", .thunderstorm, month: 11)), "HK December")
        XCTAssertTrue((300...480).contains(share("JP", .rain, month: 5) + share("JP", .thunderstorm, month: 5)), "JP June")
        // The same seed gives each country its own days.
        let taiwan = Disruptions(level: .standard, country: "TW", seed: 7)!, finland = Disruptions(level: .standard, country: "FI", seed: 7)!
        let year = Int64(360)..<720
        XCTAssertNotEqual(year.map(taiwan.weather(onDay:)), year.map(finland.weather(onDay:)))
    }

    /// Decision 1004: Taiwan's and Kyushu's weather stations, and the
    /// island keeping the old table over all of them.
    func testTheWeatherStationsShareOutTheirCountrysMonths() {
        XCTAssertEqual(Set(Disruptions.weatherStations.keys), ["TW", "JP"])
        for (country, stations) in Disruptions.weatherStations {
            XCTAssertEqual(Set(stations.map(\.name)).count, stations.count, country)
            for station in stations {
                XCTAssertEqual(station.months.count, 12, station.name)
                XCTAssertTrue(station.months.allSatisfy { $0.rain >= 0 && $0.storm >= 0 && $0.rain + $0.storm <= 1_000 }, station.name)
            }
        }
        let taiwan = Disruptions.weatherStations["TW"]!
        XCTAssertEqual(taiwan.count, 19)
        for month in 0..<12 {
            let rain = taiwan.map { $0.months[month].rain }.reduce(0, +) / Int64(taiwan.count)
            let storm = taiwan.map { $0.months[month].storm }.reduce(0, +) / Int64(taiwan.count)
            XCTAssertTrue(abs(rain - Disruptions.monthlyRain[month].rain) <= 1, "month \(month + 1): \(rain)")
            XCTAssertTrue(abs(storm - Disruptions.monthlyRain[month].storm) <= 1, "month \(month + 1): \(storm)")
        }
        let fukuoka = Disruptions.weatherStations["JP"]!.first { $0.name == "福岡" }!
        XCTAssertEqual(fukuoka.months.map(\.rain), Disruptions.countryRain["JP"]!.map(\.rain))
        XCTAssertEqual(fukuoka.months.map(\.storm), Disruptions.countryRain["JP"]!.map(\.storm))
        XCTAssertEqual(GameWorld.cosineThousandths(ofLatitude: 0), 1_000)
        XCTAssertTrue((904...908).contains(GameWorld.cosineThousandths(ofLatitude: 250_330_000)))
        XCTAssertTrue((397...401).contains(GameWorld.cosineThousandths(ofLatitude: 665_039_000)))
    }

    /// A world of `world(country:)` whose map is round `latitude` and
    /// `longitude` (degrees).
    private func world(country: String, latitude: Double, longitude: Double, day: Int64 = 0) throws -> GameWorld {
        var world = try world(country: country, day: day)
        world.setGeoAnchor(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded()))!)
        return world
    }

    /// The point `north` and `east` metres from `world`'s anchor.
    private func point(_ world: GameWorld, north: Int64, east: Int64) -> PlanPoint {
        let middle = world.weatherAnchorPoint
        return PlanPoint(x: middle.x + east * WorldCoordinate.unitsPerMetre, y: middle.y - north * WorldCoordinate.unitsPerMetre)
    }

    /// Decision 1004: a place takes the weather station nearest it; a map
    /// with no anchor, or of a country with one climate, has the
    /// country's weather everywhere.
    func testAPlaceTakesTheNearestWeatherStation() throws {
        let taipei = try world(country: "TW", latitude: 25.0377, longitude: 121.5149)
        XCTAssertTrue(taipei.hasRegionalWeather)
        XCTAssertEqual(taipei.weatherStation(at: taipei.weatherAnchorPoint)?.name, "臺北")
        // Some 267 km south and 124 km west of Taipei: Kaohsiung.
        XCTAssertEqual(taipei.weatherStation(at: point(taipei, north: -267_000, east: -124_000))?.name, "高雄")
        // 25 km east: Keelung; 13 km north-west: Tamsui.
        XCTAssertEqual(taipei.weatherStation(at: point(taipei, north: 10_000, east: 25_000))?.name, "基隆")
        XCTAssertEqual(taipei.weatherStation(at: point(taipei, north: 13_000, east: -8_000))?.name, "淡水")
        let saga = try world(country: "JP", latitude: 33.2490, longitude: 130.2988)
        XCTAssertEqual(saga.weatherStation(at: saga.weatherAnchorPoint)?.name, "佐賀")
        XCTAssertEqual(saga.weatherStation(at: point(saga, north: 37_000, east: 9_000))?.name, "福岡")
        // One climate, or no place on the Earth: the country's months.
        for world in [try world(country: "HK", latitude: 22.3, longitude: 114.17), try world(country: "TW")] {
            XCTAssertFalse(world.hasRegionalWeather)
            XCTAssertNil(world.weatherStation(at: world.weatherAnchorPoint))
            let disruptions = world.disruptions!
            for day in Int64(0)..<720 {
                XCTAssertEqual(world.weather(onDay: day, at: PlanPoint(x: 0, y: 0)), disruptions.weather(onDay: day))
                XCTAssertEqual(world.weather(onDay: day), disruptions.weather(onDay: day))
            }
        }
        // A map's own weather is its anchor's.
        for day in Int64(0)..<720 {
            XCTAssertEqual(taipei.weather(onDay: day), taipei.weather(onDay: day, at: taipei.weatherAnchorPoint))
        }
    }

    /// Decision 1004: one draw a day for the whole map, so the wetter
    /// place is wet whenever the drier one is: Keelung's winter rains while
    /// Kaohsiung stays dry, and the trips from a station follow its own
    /// weather.
    func testTheNorthRainsWhileTheSouthIsClear() throws {
        let taipei = try world(country: "TW", latitude: 25.0377, longitude: 121.5149)
        let keelung = point(taipei, north: 10_000, east: 25_000), kaohsiung = point(taipei, north: -267_000, east: -124_000)
        var northOnly: Int64?
        var wet = (keelung: 0, kaohsiung: 0)
        for day in Int64(360)..<(360 + 40 * 360) where day % 360 < 30 {
            let north = taipei.weather(onDay: day, at: keelung), south = taipei.weather(onDay: day, at: kaohsiung)
            if south != .clear { XCTAssertNotEqual(north, .clear, "day \(day)") }
            if north != .clear { wet.keelung += 1 }
            if south != .clear { wet.kaohsiung += 1 }
            if north == .rain, south == .clear, taipei.holiday(onDay: day) == nil, northOnly == nil { northOnly = day }
        }
        // January: Keelung's 484 per mille, Kaohsiung's 79, over 1,200 days.
        XCTAssertTrue((520...640).contains(wet.keelung), "\(wet.keelung)")
        XCTAssertTrue((60...140).contains(wet.kaohsiung), "\(wet.kaohsiung)")
        let day = try XCTUnwrap(northOnly)
        let calm = try world(seed: nil, day: day)
        let north = try world(country: "TW", latitude: 25.1333, longitude: 121.7405, day: day)
        let south = try world(country: "TW", latitude: 22.6273, longitude: 120.3014, day: day)
        for id in ids {
            XCTAssertEqual(north.weatherDrop(onDay: day, at: id), 100)
            XCTAssertEqual(south.weatherDrop(onDay: day, at: id), 0)
            XCTAssertEqual(trips(north, from: id), (trips(calm, from: id) * 900 + 500) / 1_000, "\(id)")
            XCTAssertEqual(trips(south, from: id), trips(calm, from: id), "\(id)")
        }
        // A station that is not there has the map's.
        XCTAssertEqual(north.weatherDrop(onDay: day, at: StationID(rawValue: 99)), north.weatherDrop(onDay: day))
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

    /// A seed whose second year has one typhoon, over S0 and S1 and
    /// neither S2 nor S3, on a clear day, and the typhoon: the same day
    /// without it differs only by the typhoon.
    private func clearTyphoonOverS0AndS1() throws -> (seed: UInt32, typhoon: Typhoon) {
        let world = try world()
        let point = { (index: Int) in world.station(id: self.ids[index])!.point }
        for seed in UInt32(1)...5_000 {
            let disruptions = Disruptions(level: .standard, country: "TW", seed: seed)!
            let typhoons = disruptions.typhoons(ofYear: 1, in: world.bounds)
            if typhoons.count == 1, let typhoon = typhoons.first, typhoon.covers(point(0)), typhoon.covers(point(1)),
               !typhoon.covers(point(2)), !typhoon.covers(point(3)), disruptions.weather(onDay: typhoon.start) == .clear {
                return (seed, typhoon)
            }
        }
        XCTFail("no seed to 5,000 has a typhoon over S0 and S1 alone on a clear day")
        throw XCTSkip()
    }

    func testATyphoonCutsTheDemandOfTheStationsItCovers() throws {
        let (seed, typhoon) = try typhoonOverS1()
        // Announced, then blowing.
        let before = try world(seed: seed, day: typhoon.announced - 1)
        XCTAssertFalse(before.typhoons(onDay: typhoon.announced - 1).contains(typhoon))
        XCTAssertTrue(try world(seed: seed, day: typhoon.announced).typhoons(onDay: typhoon.announced).contains(typhoon))
        let blowing = try world(seed: seed, day: typhoon.start)
        XCTAssertEqual(blowing.typhoonMultiplier(at: ids[1]), 200)
        XCTAssertEqual(blowing.typhoonMultiplier(at: ids[3]), 1_000)
        // Before it blows, and over, it cuts nothing.
        XCTAssertTrue(try world(seed: seed, day: typhoon.announced).typhoonMultipliers().isEmpty)
        XCTAssertEqual(try world(seed: seed, day: typhoon.end).typhoonMultiplier(at: ids[1]), 1_000)
    }

    /// The trips that set out from or go to a station a typhoon blows over
    /// keep a fifth, once even when it blows over both ends, and none of
    /// them go elsewhere: the trips between stations it misses are those
    /// of the same day without it (decision 162, as the station's panel
    /// says: "demand −80%").
    func testATyphoonCutsTheTripsToAndFromItsStationsAndSendsNoneElsewhere() throws {
        let (seed, typhoon) = try clearTyphoonOverS0AndS1()
        let blowing = try world(seed: seed, day: typhoon.start)
        // Without a seed: the same day's holiday, no weather, no typhoon.
        let calm = try world(seed: nil, day: typhoon.start)
        XCTAssertEqual(blowing.weatherMultiplier, 1_000)
        let left = blowing.typhoonMultipliers()
        XCTAssertEqual(left, [ids[0]: 200, ids[1]: 200])
        var pairs = (cut: 0, kept: 0)
        for origin in ids {
            let before = calm.dailyDemands(from: origin), after = blowing.dailyDemands(from: origin)
            for destination in ids where destination != origin {
                let multiplier = min(left[origin] ?? 1_000, left[destination] ?? 1_000)
                XCTAssertEqual(after[destination] ?? 0, ((before[destination] ?? 0) * multiplier + 500) / 1_000, "\(origin) to \(destination)")
                if multiplier == 1_000 { pairs.kept += 1 } else { pairs.cut += 1 }
            }
        }
        // S2 and S3 trade as many trips as without the typhoon, and every
        // pair with S0 or S1 at an end is cut.
        XCTAssertEqual(blowing.dailyDemands(from: ids[2])[ids[3]], calm.dailyDemands(from: ids[2])[ids[3]])
        XCTAssertEqual(blowing.dailyDemands(from: ids[3])[ids[2]], calm.dailyDemands(from: ids[3])[ids[2]])
        XCTAssertEqual(pairs.kept, 2)
        XCTAssertEqual(pairs.cut, 10)
        // Where it blows over both ends, a pair keeps a fifth, not a
        // fifth of a fifth.
        let both = try XCTUnwrap(calm.dailyDemands(from: ids[0])[ids[1]])
        XCTAssertEqual(blowing.dailyDemands(from: ids[0])[ids[1]], (both * 200 + 500) / 1_000)
    }

    /// A small station under a typhoon still draws its fifth: the cut is
    /// made on each pair's trips (S0's share for it, some 48 trips on a
    /// clear day, keeps a fifth), not on its pull, which a day of 4 trips
    /// at −80% would round to nothing.
    func testASmallStationUnderATyphoonStillDrawsTravellers() throws {
        let (seed, typhoon) = try typhoonOverS1()
        var world = try world(seed: seed, day: typhoon.start)
        XCTAssertNil(world.demandEvents)
        try world.setStationDemand(ids[1], to: StationDemand(kind: .office, dailyTrips: 4))
        for id in ids[2...] {
            try world.setStationDemand(id, to: StationDemand(kind: .office, dailyTrips: 40))
        }
        XCTAssertEqual(world.typhoonMultiplier(at: ids[1]), 200)
        let toS1 = world.dailyDemand(from: ids[0]).first { $0.destination == ids[1] }?.trips ?? 0
        XCTAssertGreaterThan(toS1, 0)
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
        var made = try NTScale.$factor.withValue(3) { try world(day: firstDay(with: .rain)) }
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
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(newTaiwanDollars(ofSaveText: String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 41,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#)).utf8))
    }
}
