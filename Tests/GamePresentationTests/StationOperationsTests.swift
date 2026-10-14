import GameCore
@testable import GamePresentation
import XCTest

/// Decision 224: the station's operations page, its platforms seen from
/// above with the train at each and how busy it has been, and the weather.
final class StationOperationsTests: XCTestCase {
    private func central(in world: GameWorld) throws -> StationID {
        try XCTUnwrap(world.stations.first { $0.name == "Central" }).id
    }

    func testThePlatformsAreNumberedAsThePanelNumbersThemAndShowTheTrainStandingThere() throws {
        var world = DemoWorld.make(in: .english)
        var use = PlatformUse()
        var sawTrain = false
        for _ in 0..<120 {
            try world.advance(ticks: 1)
            use.record(world)
            for station in world.stations {
                let page = StationOperations(world: world, station: station.id, use: use)
                XCTAssertEqual(page.platforms.map(\.platform), world.trackPlatforms(of: station.id))
                XCTAssertEqual(page.platforms.map(\.number), Array((0..<page.platforms.count).map { $0 + 1 }))
                for row in page.platforms {
                    if let train = row.train {
                        sawTrain = true
                        XCTAssertTrue(world.trackPlatformsAlongWholeTrain(train).contains(row.platform))
                        XCTAssertNotNil(row.trainName)
                    } else {
                        XCTAssertEqual(row.trainText(lineName: nil, in: .traditionalChinese), "空著")
                    }
                    if let percent = row.busyPercent {
                        XCTAssertTrue((0...100).contains(percent))
                        XCTAssertGreaterThan(row.sampledMinutes, 0)
                    }
                }
            }
        }
        XCTAssertTrue(sawTrain, "the demo's trains stand at platforms")
    }

    func testPlatformUseKeepsTheLastHourAndStartsAgainWhenTheClockGoesBack() throws {
        var world = DemoWorld.make(in: .english)
        let start = world
        var use = PlatformUse()
        while world.clock.now.seconds - start.clock.now.seconds < 3 * 3600 {
            try world.advance(ticks: 1)
            use.record(world)
        }
        let platform = try XCTUnwrap(world.stations.flatMap { world.trackPlatforms(of: $0.id) }.first)
        let seen = use.use(of: platform, now: world.clock.now)
        XCTAssertLessThanOrEqual(Int64(seen.sampled), PlatformUse.window)
        XCTAssertGreaterThan(seen.sampled, 0)
        XCTAssertLessThanOrEqual(seen.taken, seen.sampled)

        use.record(start)
        XCTAssertEqual(use.use(of: platform, now: world.clock.now).sampled, 0, "a game loaded with an earlier clock starts again")
        XCTAssertEqual(use.use(of: platform, now: start.clock.now).sampled, 1)
    }

    /// At a high speed a game minute is not sampled every minute: the page
    /// names the minutes the samples span, not how many there are.
    func testTheMinutesNamedAreThoseSpannedNotTheSamples() throws {
        var world = DemoWorld.make(in: .english)
        let station = try central(in: world)
        var use = PlatformUse()
        use.record(world)
        let start = world.clock.now.seconds
        while world.clock.now.seconds < start + 30 * 60 {
            try world.advance(ticks: 1)
        }
        XCTAssertEqual(world.clock.now.seconds, start + 30 * 60)
        use.record(world)
        let row = try XCTUnwrap(StationOperations(world: world, station: station, use: use).platforms.first)
        XCTAssertEqual(row.sampledMinutes, 31)
    }

    func testBusynessSteps() {
        XCTAssertEqual(StationOperations.Busyness(percent: 0), .quiet)
        XCTAssertEqual(StationOperations.Busyness(percent: 49), .quiet)
        XCTAssertEqual(StationOperations.Busyness(percent: 50), .busy)
        XCTAssertEqual(StationOperations.Busyness(percent: 80), .packed)
        XCTAssertEqual(StationOperations.Busyness.packed.text(in: .traditionalChinese), "擠")
        XCTAssertEqual(StationOperations.grouped(4_000), "4,000")
        XCTAssertEqual(StationOperations.grouped(128), "128")
    }

    func testTheWeatherCardFollowsTheForecastAndTheTyphoonsOverTheStation() throws {
        var world = DemoWorld.make(in: .english)
        world.setDisruptions(Disruptions(level: .standard, country: "TW", seed: 1))
        let station = try central(in: world)
        let page = StationOperations(world: world, station: station, use: PlatformUse())
        XCTAssertEqual(page.days.count, StationOperations.forecastDays)
        XCTAssertTrue(page.days[0].isToday)
        XCTAssertEqual(page.days.map(\.date.day), world.forecast(days: StationOperations.forecastDays).map(\.date.day))
        for day in page.days {
            XCTAssertEqual(day.weatherDropPercent, Int(world.weatherDrop(onDay: day.date.day) / 10))
        }

        world.setDisruptions(nil)
        XCTAssertTrue(StationOperations(world: world, station: station, use: PlatformUse()).days.isEmpty)
    }

    func testTheDaysWords() {
        func day(_ weather: Weather, today: Bool = false, drop: Int = 0, typhoon: Int = 0) -> StationOperations.Day {
            StationOperations.Day(date: GameDate(day: 3), isToday: today, weather: weather, typhoon: typhoon > 0,
                                  weatherDropPercent: drop, typhoonDropPercent: typhoon)
        }
        XCTAssertEqual(day(.clear, today: true).dayText(in: .traditionalChinese), "今天")
        XCTAssertNil(day(.clear).effectText(in: .traditionalChinese))
        XCTAssertEqual(day(.rain, drop: 10).effectText(in: .traditionalChinese), "乘客 −10%")
        XCTAssertEqual(day(.rain, drop: 10).weatherText(in: .traditionalChinese), "下雨")
        XCTAssertEqual(day(.rain, drop: 10, typhoon: 50).effectText(in: .traditionalChinese), "這站乘客 −55%")
        XCTAssertEqual(day(.clear, typhoon: 50).weatherText(in: .traditionalChinese), "颱風")
    }

    func testThePlatformsWords() throws {
        let world = DemoWorld.make(in: .english)
        let platform = try XCTUnwrap(world.stations.flatMap { world.trackPlatforms(of: $0.id) }.first)
        func row(train: Bool, destination: String?, percent: Int?, minutes: Int) -> StationOperations.Platform {
            StationOperations.Platform(number: 1, platform: platform, train: train ? TrainID(rawValue: 1) : nil, trainName: train ? "Train 1" : nil,
                                       line: nil, lineColor: nil, cars: 4, destination: destination, busyPercent: percent, sampledMinutes: minutes)
        }
        XCTAssertEqual(row(train: true, destination: "East", percent: 82, minutes: 60).trainText(lineName: "Line 1", in: .traditionalChinese), "Line 1・往 East")
        XCTAssertEqual(row(train: true, destination: nil, percent: 82, minutes: 60).trainText(lineName: nil, in: .english), "Train 1, ends here")
        XCTAssertEqual(row(train: true, destination: nil, percent: 82, minutes: 60).busyText(in: .traditionalChinese), "82%")
        XCTAssertEqual(row(train: false, destination: nil, percent: 38, minutes: 20).busyText(in: .traditionalChinese), "38%（最近 20 分）")
        XCTAssertNil(row(train: false, destination: nil, percent: nil, minutes: 0).busyText(in: .english))
    }
}
