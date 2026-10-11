import GameCore
import GamePresentation
import XCTest

/// Decision 154: public holidays in the station panel's and the station
/// master's words.
final class HolidayTextTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)

    /// Two stations on a line with a running train, Taiwan's holidays at
    /// the standard level, starting at game day `day`.
    private func world(day: Int64, managed: Bool = false) throws -> GameWorld {
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
        world.setDisruptions(Disruptions(level: .standard, country: "TW"))
        world.setSpeed(.normal)
        return world
    }

    func testThePanelAnnouncesAHolidayAWeekAheadAndCountsItDown() throws {
        XCTAssertEqual(try world(day: 35).holidayTexts(in: .english), [])
        XCTAssertEqual(try world(day: 36).holidayTexts(in: .english), ["Lunar New Year: +20% demand on every line, starts in 7 days, lasts 9 days"])
        XCTAssertEqual(try world(day: 42).holidayTexts(in: .traditionalChinese), ["春節：全線需求 +20%，1 天後開始，連續 9 天"])
        XCTAssertEqual(try world(day: 47).holidayTexts(in: .traditionalChinese), ["春節：全線需求 +20%，還有 5 天"])
        XCTAssertEqual(try world(day: 51).holidayTexts(in: .english), ["Lunar New Year: +20% demand on every line, 1 more day", "Peace Memorial Day: +5% demand on every line, starts in 6 days, lasts 1 day"])
        var off = try world(day: 47)
        off.setDisruptions(nil)
        XCTAssertEqual(off.holidayTexts(in: .english), [])
    }

    func testTheStationMasterWarnsThreeDaysAhead() throws {
        XCTAssertNil(StationMasterAdvice(world: try world(day: 39)), "four days ahead, all runs well")
        let advice = try XCTUnwrap(StationMasterAdvice(world: try world(day: 40)))
        XCTAssertEqual(advice, .holidayComing(kind: .springFestival, days: 3, percent: 20))
        XCTAssertFalse(advice.isWorry)
        XCTAssertEqual(advice.text(in: .traditionalChinese), "3 天後是春節，各線旅客約多 20%。先加開列車或加掛車廂吧。")
        XCTAssertEqual(StationMasterAdvice(world: try world(day: 42)), .holidayComing(kind: .springFestival, days: 1, percent: 20))
        XCTAssertNil(StationMasterAdvice(world: try world(day: 43)), "once it has begun, the panel says it")
    }

    func testTheDayAfterAHolidayTheStationMasterReviewsIt() throws {
        var world = try world(day: 34, managed: true)
        try world.advance(ticks: 1_440 * 18)
        XCTAssertEqual(world.clock.now.seconds / GameTime.secondsPerDay, 52)
        let review = try XCTUnwrap(world.holidayReview())
        XCTAssertEqual(review.kind, .springFestival)
        XCTAssertGreaterThan(review.riders, 0)
        XCTAssertEqual(StationMasterAdvice(world: world), .holidayOver(kind: .springFestival, riders: review.riders, percent: review.percent))
        XCTAssertEqual(
            StationMasterAdvice.holidayOver(kind: .springFestival, riders: 1_234, percent: 18).text(in: .traditionalChinese),
            "春節結束了：每天 1,234 人次，比連假前多 18%。"
        )
        XCTAssertEqual(
            StationMasterAdvice.holidayOver(kind: .newYear, riders: 900, percent: -4).text(in: .english),
            "New Year is over: 900 riders a day, 4% fewer than before it. Were the trains full?"
        )
        // A day later there is nothing to review; free play keeps no days.
        try world.advance(ticks: 1_440)
        XCTAssertNil(world.holidayReview())
        XCTAssertNil(try self.world(day: 52).holidayReview())
    }

    @MainActor
    func testTheSettingsSetTheLevelAndKeepTheCountry() throws {
        let session = GameSession(world: GameWorld.newGame(anchor: GeoAnchor(latitude: 356_812_000, longitude: 1_397_671_000)!))
        XCTAssertEqual(session.world.disruptions, Disruptions(level: .light, country: "JP", seed: 1))
        session.setDisruptionLevel(.standard)
        XCTAssertEqual(session.world.disruptions, Disruptions(level: .standard, country: "JP", seed: 1))
        session.setDisruptionLevel(nil)
        XCTAssertNil(session.world.disruptions)
        XCTAssertEqual(session.message?.text, "Holidays and other events off: demand is the same every day of the week.")
        // On again, the map's country; and the change undoes.
        session.setDisruptionLevel(.light)
        XCTAssertEqual(session.world.disruptions, Disruptions(level: .light, country: "JP", seed: 1))
        session.undo()
        XCTAssertNil(session.world.disruptions)
        // A blank map's are Taiwan's; the seed is the new game's (1).
        var blank = GameWorld.newGame()
        blank.setDisruptions(nil)
        let other = GameSession(world: blank, language: .traditionalChinese)
        other.setDisruptionLevel(.standard)
        XCTAssertEqual(other.world.disruptions, Disruptions(level: .standard, country: "TW", seed: 1))
        XCTAssertEqual(other.message?.text, "連假等事件已開啟：標準。")
        XCTAssertEqual(holidayCountryName("TW", in: .traditionalChinese), "台灣")
    }
}
