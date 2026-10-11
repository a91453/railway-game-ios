import GameCore
@testable import GamePresentation
import XCTest

/// Decision 162: weather, typhoons and the fuel price in the station
/// panel's and the station master's words, and a new game's seed.
final class WeatherTextTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)

    /// Two stations on a line with a running train, Taiwan's disruptions
    /// with `seed`, starting at game day `day`.
    private func world(seed: UInt32?, level: DisruptionLevel = .standard, day: Int64, managed: Bool = false) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 32_768, height: 4_096), economy: GameEconomy(balance: 10_000_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: day * GameTime.secondsPerDay))
        )
        let tile = Int64(1_024), platform = 4 * Train.carLength
        let west = try world.buildTrackNode(at: WorldCoordinate(x: tile, y: 2_048))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 29 * tile, y: 2_048))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for (name, middle) in [("Alpha", tile + platform / 2), ("Beta", 27 * tile - platform / 2)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: tile + middle, y: 2_048)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        let line = try world.createLine(named: "Main", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .residential, dailyTrips: 200))
        try world.setStationDemand(Self.beta, to: StationDemand(kind: .office, dailyTrips: 200))
        if managed { world.setEconomyMode(.management) }
        world.setDisruptions(Disruptions(level: level, country: "TW", seed: seed))
        world.setSpeed(.normal)
        return world
    }

    /// A seed whose second year has one typhoon, over Alpha, and it.
    private func typhoonOverAlpha() throws -> (seed: UInt32, typhoon: Typhoon) {
        let world = try world(seed: nil, day: 0)
        let point = world.station(id: Self.alpha)!.point
        for seed in UInt32(1)...500 {
            let typhoons = Disruptions(level: .standard, country: "TW", seed: seed)!.typhoons(ofYear: 1, in: world.bounds)
            if typhoons.count == 1, typhoons[0].covers(point) {
                return (seed, typhoons[0])
            }
        }
        throw XCTSkip("no seed to 500 has a typhoon over Alpha alone")
    }

    func testANewGameDrawsItsWeatherFromItsSeedAndChallengesKeepNone() {
        XCTAssertEqual(GameWorld.newGame(eventSeed: 99).disruptions, Disruptions(level: .light, country: "TW", seed: 99))
        XCTAssertNil(GameWorld.newGame(challenge: .threeTowns, eventSeed: 99).disruptions)
    }

    func testThePanelSaysTodaysRainAndATyphoonOnItsWay() throws {
        let disruptions = Disruptions(level: .standard, country: "TW", seed: 7)!
        let rain = (Int64(30)...400).first { disruptions.weather(onDay: $0) == .rain && $0 != 43 }!
        XCTAssertTrue(try world(seed: 7, day: rain).weatherTexts(at: Self.alpha, in: .traditionalChinese).contains("今天下雨：全線需求 −10%"))
        XCTAssertTrue(try world(seed: 7, level: .light, day: rain).weatherTexts(at: Self.alpha, in: .english).contains("Rain today: −5% demand on every line"))
        XCTAssertEqual(try world(seed: nil, day: rain).weatherTexts(at: Self.alpha, in: .english), [])
        let (seed, typhoon) = try typhoonOverAlpha()
        let announced = try world(seed: seed, day: typhoon.announced)
        let wait = typhoon.start - typhoon.announced, days = typhoon.end - typhoon.start
        XCTAssertTrue(announced.weatherTexts(at: Self.alpha, in: .traditionalChinese).contains("颱風：這站需求 −80%，\(wait) 天後來襲，持續 \(days) 天"))
        let blowing = try world(seed: seed, day: typhoon.start)
        XCTAssertTrue(blowing.weatherTexts(at: Self.alpha, in: .traditionalChinese).contains("颱風：這站需求 −80%，還有 \(days) 天"))
        if !typhoon.covers(blowing.station(id: Self.beta)!.point) {
            XCTAssertFalse(blowing.weatherTexts(at: Self.beta, in: .traditionalChinese).contains { $0.hasPrefix("颱風") })
        }
    }

    func testTheStationMasterWarnsOfATyphoonFirst() throws {
        let (seed, typhoon) = try typhoonOverAlpha()
        let coming = try XCTUnwrap(StationMasterAdvice(world: try world(seed: seed, day: typhoon.announced)))
        guard case .typhoonComing(let days, let stations, 80) = coming else { return XCTFail("\(coming)") }
        XCTAssertEqual(days, typhoon.start - typhoon.announced)
        XCTAssertTrue((1...2).contains(stations))
        XCTAssertTrue(coming.isWorry)
        XCTAssertEqual(
            StationMasterAdvice.typhoonComing(days: 2, stations: 3, percent: 80).text(in: .traditionalChinese),
            "颱風 2 天後來襲，影響 3 個車站，那裡的旅客會少約 80%。可以減少班次，或先把車站封站。"
        )
        XCTAssertEqual(StationMasterAdvice(world: try world(seed: seed, day: typhoon.start)), .typhoonComing(days: 0, stations: stations, percent: 80))
        XCTAssertEqual(
            StationMasterAdvice.typhoonComing(days: 0, stations: 1, percent: 40).text(in: .english),
            "A typhoon is blowing over 1 of our station: about 40% fewer passengers there today."
        )
    }

    func testTheStationMasterTellsOfAFuelSpellOnItsFirstDay() throws {
        let disruptions = Disruptions(level: .standard, country: "TW", seed: 7)!
        let spell = try XCTUnwrap((Int64(0)..<3_600).lazy.compactMap(disruptions.fuelSpell(onDay:)).first { $0.start > 60 })
        let world = try world(seed: 7, day: spell.start, managed: true)
        // Not on a day a typhoon, a holiday or its review speaks first.
        guard world.typhoons(onDay: spell.start).isEmpty, world.holidays(from: spell.start, through: spell.start + 3).isEmpty else {
            throw XCTSkip("seed 7's first spell meets another notice")
        }
        XCTAssertEqual(StationMasterAdvice(world: world), .fuelSpell(percent: (spell.index - 1_000) / 10, days: spell.end - spell.start))
        XCTAssertNil(StationMasterAdvice(world: try self.world(seed: 7, day: spell.start + 1, managed: true)), "once")
        XCTAssertEqual(StationMasterAdvice.fuelSpell(percent: 18, days: 11).text(in: .traditionalChinese), "油電價格上漲 18%，持續 11 天。少開一兩列車可以省能源費。")
        XCTAssertEqual(StationMasterAdvice.fuelSpell(percent: -8, days: 9).text(in: .english), "Fuel and power cost 8% less for 9 days.")
    }

    @MainActor
    func testTheSettingsKeepTheSeedOrTakeTheEvents() throws {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 42))
        session.setDisruptionLevel(.standard)
        XCTAssertEqual(session.world.disruptions?.seed, 42)
        session.setDisruptionLevel(nil)
        session.setDisruptionLevel(.light)
        XCTAssertEqual(session.world.disruptions?.seed, 42, "the demand events' seed")
        // Decision 154's disruptions, without a seed, take the events' on a
        // change of level.
        var old = GameWorld.newGame(eventSeed: 5)
        old.setDisruptions(Disruptions(level: .light, country: "TW"))
        let earlier = GameSession(world: old)
        earlier.setDisruptionLevel(.standard)
        XCTAssertEqual(earlier.world.disruptions, Disruptions(level: .standard, country: "TW", seed: 5))
    }
}
