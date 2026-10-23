import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 304: the real railways' trains drawn on a
/// real-world map where their bundled timetables put them at the game's
/// time, and the station card's next trains.
@MainActor
final class RealTrainMotionTests: XCTestCase {
    /// One line from 甲 to 乙, about 10 km due east, its one segment run in
    /// 120 seconds; weekdays run set W, weekends S, holidays H.
    private func testOperations(headwayOnly: Bool = false) -> RealRailwayOperations {
        let line = """
        {"system":"T","lines":[{"id":"L","name":"測試線（甲–乙）","color":"#FF0000","peakHeadwaySec":600,"offpeakHeadwaySec":1200,
        "stations":[{"name":"甲","lat":25.0,"lon":121.5,"d":0},{"name":"乙","lat":25.0,"lon":121.6,"d":99}],
        "shape":[[25.0,121.5],[25.0,121.55],[25.0,121.6]],"segs":[{"run":120}]}]}
        """
        let times = """
        {"system":"T","lines":{"L":{"days":["S","W","W","W","W","W","S"],"holiday":"H",
        "sets":{"W":[[0,28800,1,29400],[0,86000,1,87000]],"S":[[1,28800,0,29400]],"H":[[0,36000,1,36600]]}}}}
        """
        return RealRailwayOperations(
            systems: ["trtc": Data(line.utf8)],
            timetables: headwayOnly ? [:] : ["trtc": Data(times.utf8)]
        )
    }

    private let weekday = RealServiceDay(weekday: 3)
    private let friday = RealServiceDay(weekday: 5)
    private let saturday = RealServiceDay(weekday: 6)

    private func onlyLine(_ operations: RealRailwayOperations) throws -> (RealTrainTraffic, RealTrainTraffic.Line) {
        let traffic = RealTrainTraffic(operations: operations) { _ in true }
        return (traffic, try XCTUnwrap(traffic.lines.first))
    }

    func testAShapeIsMeasuredAsTheSiteMeasuresIt() throws {
        let a = RealRailways.Coordinate(latitude: 25, longitude: 121.5)
        let b = RealRailways.Coordinate(latitude: 25, longitude: 121.6)
        let shape = try XCTUnwrap(RealLineShape([a, b]))
        // The site's sphere: 0.1° of longitude at 25° N is 10.08 km.
        XCTAssertEqual(shape.lengthKm, 2 * 6_371 * asin(cos(25 * Double.pi / 180) * sin(0.05 * Double.pi / 180)), accuracy: 1e-9)
        XCTAssertEqual(shape.coordinate(atKm: -1), a)
        XCTAssertEqual(shape.coordinate(atKm: 99), b)
        XCTAssertEqual(shape.coordinate(atKm: shape.lengthKm / 2).longitude, 121.55, accuracy: 1e-9)
        XCTAssertNil(RealLineShape([a]))
    }

    func testATrainRunsBetweenItsCallsThenWaitsForTheNext() throws {
        let (_, line) = try onlyLine(testOperations())
        let length = line.shape.lengthKm
        // Its station beyond the shape's end is held at the end.
        XCTAssertEqual(line.stationKm, [0, length])
        let runs = try XCTUnwrap({ () -> RealTrainRun? in
            guard case .sets(_, let sets) = line.schedule else { return nil }
            return sets["W"]?.runs.first
        }())
        // Leaves 甲 at 08:00, runs the segment's 120 s, waits at 乙 till 08:10.
        XCTAssertEqual(runs.stops, [
            RealTrainRun.Stop(km: 0, arrival: 28_800, departure: 28_800),
            RealTrainRun.Stop(km: length, arrival: 28_920, departure: 29_400),
        ])
        XCTAssertNil(runs.place(at: 28_799))
        XCTAssertEqual(try XCTUnwrap(runs.place(at: 28_860)).km, length / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(runs.place(at: 29_000)).km, length)
        XCTAssertEqual(try XCTUnwrap(runs.place(at: 29_400)).km, length)
        XCTAssertNil(runs.place(at: 29_401))
        // Heading on past the last stop the way it came.
        XCTAssertGreaterThan(try XCTUnwrap(runs.place(at: 29_000)).towardKm, length)

        // Without a run time, the whole gap.
        let plain = RealOperationLine(id: "P", name: "P", stations: [
            RealOperationStation(name: "a", latitude: 25, longitude: 121.5), RealOperationStation(name: "b", latitude: 25, longitude: 121.6),
        ])
        let trip = RealTimetableTrip(calls: [.init(stationIndex: 0, second: 100), .init(stationIndex: 1, second: 700)])
        let run = try XCTUnwrap(RealTrainRun(trip: trip, line: plain, stationKm: [0, 10]))
        // Halfway in time, a little short of halfway: a metro speeds up
        // more gently than it brakes (the site's 3.6 and 4.3 km/h a second).
        XCTAssertEqual(try XCTUnwrap(run.place(at: 400)).km, 4.988_08, accuracy: 1e-5)
        XCTAssertNil(RealTrainRun(trip: trip, line: plain, stationKm: [0]), "a station the line does not have")
    }

    /// The site's `buildProfile` worked by hand: 10 km in 600 s at a
    /// metro's 1 m/s² up and 1.194 m/s² down solves to 17.115 m/s.
    func testATrainSpeedsUpOutOfAStationAndBrakesIntoTheNext() throws {
        let run = try XCTUnwrap(RealTrainRun(stops: [
            .init(km: 0, arrival: 0, departure: 100), .init(km: 10, arrival: 700, departure: 730),
        ], performance: .metro))
        let profile = try XCTUnwrap(RealRunProfile.site(km: 10, seconds: 600, acceleration: 3.6, braking: 4.3, topSpeed: 80, coast: nil))
        let a = 1.0, b = 4.3 / 3.6, d = 1 / (2 * a) + 1 / (2 * b)
        let cruise = (600 - (600 * 600 - 4 * d * 10_000).squareRoot()) / (2 * d)
        XCTAssertEqual(profile.cruise, cruise, accuracy: 1e-9)
        XCTAssertEqual(profile.cruise * 3.6, 61.6, accuracy: 0.05)
        XCTAssertEqual(profile.accelerating, cruise / a, accuracy: 1e-9)
        XCTAssertEqual(profile.accelerating + profile.running + cruise / b, 600, accuracy: 1e-9)

        // Standing, then off at 0.5 m in its first second, not 16.7 m.
        XCTAssertEqual(try XCTUnwrap(run.place(at: 100)).km, 0)
        XCTAssertEqual(try XCTUnwrap(run.place(at: 101)).km * 1_000, 0.5, accuracy: 1e-9)
        // Braking into the next: 0.6 m short a second before it stops.
        XCTAssertEqual((10 - (try XCTUnwrap(run.place(at: 699)).km)) * 1_000, b / 2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(run.place(at: 700)).km, 10)
        XCTAssertEqual(try XCTUnwrap(run.place(at: 730)).km, 10)

        // Never backwards, never past the speed it solved for, and no jump
        // anywhere (each second's way within the speed it can reach).
        var last = 0.0, fastest = 0.0
        for tenth in 1_000...7_000 {
            let km = try XCTUnwrap(run.place(at: Double(tenth) / 10)).km
            XCTAssertGreaterThanOrEqual(km, last)
            fastest = max(fastest, (km - last) * 1_000 * 10)
            last = km
        }
        XCTAssertEqual(fastest, cruise, accuracy: 0.01)

        // Without a performance, one speed as before.
        let plain = try XCTUnwrap(RealTrainRun(stops: run.stops))
        XCTAssertEqual(try XCTUnwrap(plain.place(at: 101)).km * 1_000, 10_000.0 / 600, accuracy: 1e-9)
    }

    func testTheHighSpeedRailCoastsBeforeItBrakes() throws {
        // About 板橋 to 桃園: 30 km in 12 minutes.
        let profile = try XCTUnwrap(RealRunProfile.make(km: 30, seconds: 720, performance: .highSpeed))
        XCTAssertEqual(profile.acceleration, 1.4 / 3.6, accuracy: 1e-12, "the usual, not the spare")
        XCTAssertEqual(profile.coasting, 0.45 / 3.6, accuracy: 1e-12)
        XCTAssertGreaterThan(profile.coastSeconds, 0)
        XCTAssertEqual(profile.brakeFrom / profile.cruise, 0.45, accuracy: 1e-12, "brakes from 45% of its speed")
        XCTAssertLessThanOrEqual(profile.cruise * 3.6, 300)
        XCTAssertEqual(profile.progress(after: 720), 1)
        XCTAssertEqual(profile.progress(after: 719.999), 1, accuracy: 1e-6)

        // Too short a time for 1.4 and 1.5: the site's spare 2.0 and 2.7.
        // First the spare braking alone, then both.
        XCTAssertNil(RealRunProfile.site(km: 6, seconds: 230, acceleration: 1.4, braking: 1.5, topSpeed: 300, coast: (0.45, 0.45)))
        let hurried = try XCTUnwrap(RealRunProfile.make(km: 6, seconds: 230, performance: .highSpeed))
        XCTAssertEqual(hurried.acceleration * 3.6, 1.4, accuracy: 1e-12)
        XCTAssertEqual(hurried.braking * 3.6, 2.7, accuracy: 1e-12)
        let rushed = try XCTUnwrap(RealRunProfile.make(km: 6, seconds: 210, performance: .highSpeed))
        XCTAssertEqual(rushed.acceleration * 3.6, 2.0, accuracy: 1e-12)
        XCTAssertEqual(rushed.braking * 3.6, 2.7, accuracy: 1e-12)
    }

    /// Mini Tokyo 3D's `trainRepeat` where the site's curve has no answer.
    func testWhereTheSitesCurveHasNoAnswerMiniTokyo3DsDoes() throws {
        // 5 km in 200 s needs 90 km/h on average, past a metro's 80: speed
        // up and brake alike at 1 m/s², running at 100 − √5,000 m/s.
        XCTAssertNil(RealRunProfile.site(km: 5, seconds: 200, acceleration: 3.6, braking: 4.3, topSpeed: 80, coast: nil))
        let fast = try XCTUnwrap(RealRunProfile.make(km: 5, seconds: 200, performance: .metro))
        XCTAssertEqual(fast.cruise, 100 - 5_000.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(fast.acceleration, 1, accuracy: 1e-12)
        XCTAssertEqual(fast.braking, 1, accuracy: 1e-12)
        XCTAssertEqual(fast.progress(after: 100), 0.5, accuracy: 1e-12)
        XCTAssertEqual(fast.progress(after: 200), 1)

        // 10 km in 120 s cannot be done at 1 m/s² at all: half the time
        // speeding up, half braking, at 2 × 10,000 / 120 m/s at the top.
        let impossible = try XCTUnwrap(RealRunProfile.make(km: 10, seconds: 120, performance: .metro))
        XCTAssertEqual(impossible.cruise, 2 * 10_000.0 / 120, accuracy: 1e-9)
        XCTAssertEqual(impossible.running, 0, accuracy: 1e-9)
        XCTAssertEqual(impossible.progress(after: 60), 0.5, accuracy: 1e-12)

        // 150 m in 40 s, too short to reach 80 km/h: the same, gently.
        let short = try XCTUnwrap(RealRunProfile.fallback(km: 0.15, seconds: 40, acceleration: 3.6, topSpeed: 80))
        XCTAssertEqual(short.acceleration, 4 * 150 / (40.0 * 40), accuracy: 1e-12)
        XCTAssertEqual(short.accelerating, 20, accuracy: 1e-9)

        XCTAssertNil(RealRunProfile.make(km: 0, seconds: 60, performance: .metro))
        XCTAssertNil(RealRunProfile.make(km: 1, seconds: 0, performance: .metro))
    }

    func testEachSystemsTrainsRunAsTheSiteSays() throws {
        XCTAssertEqual(RealTrainPerformance.of(system: "thsr"), .highSpeed)
        XCTAssertEqual(RealTrainPerformance.of(system: "tra"), .local)
        for system in ["trtc", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt"] {
            XCTAssertEqual(RealTrainPerformance.of(system: system), .metro, system)
        }
        XCTAssertNotEqual(RealTrainPerformance.metro, .local)

        // A metro's timetable and its headways both run as a metro.
        let (_, line) = try onlyLine(testOperations())
        guard case .sets(_, let sets) = line.schedule else { return XCTFail("\(line.schedule)") }
        XCTAssertEqual(sets.values.flatMap(\.runs).map(\.performance), Array(repeating: .metro, count: sets.values.map(\.runs.count).reduce(0, +)))
        let (_, headway) = try onlyLine(testOperations(headwayOnly: true))
        guard case .headway(let round, _) = headway.schedule else { return XCTFail("\(headway.schedule)") }
        XCTAssertEqual(round.performance, .metro)

        // The bundled High Speed Rail and Taiwan Railway.
        let operations = try XCTUnwrap(try BundledRealData.railways().operations)
        let traffic = RealTrainTraffic(operations: operations) { _ in true }
        let hsr = try XCTUnwrap(traffic.lines.first { $0.system == "thsr" })
        guard case .daily(let runs) = hsr.schedule else { return XCTFail("\(hsr.schedule)") }
        XCTAssertFalse(runs.runs.isEmpty)
        XCTAssertTrue(runs.runs.allSatisfy { $0.performance == .highSpeed })
        let tra = try XCTUnwrap(traffic.lines.first { $0.system == "tra" })
        guard case .headway(let local, _) = tra.schedule else { return XCTFail("\(tra.schedule)") }
        XCTAssertEqual(local.performance, .local)
    }

    func testARingTakesTheShorterWayRound() throws {
        let run = try XCTUnwrap(RealTrainRun(stops: [
            .init(km: 9, arrival: 0, departure: 0), .init(km: 1, arrival: 100, departure: 100),
        ]))
        // Round a 10 km ring, 9 → 1 is 2 km forward through 0.
        XCTAssertEqual(try XCTUnwrap(run.place(at: 25, ringKm: 10)).km, 9.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(run.place(at: 75, ringKm: 10)).km, 0.5, accuracy: 1e-9)
        // Not a ring: straight back along the line.
        XCTAssertEqual(try XCTUnwrap(run.place(at: 50)).km, 5, accuracy: 1e-9)

        // Speeding up and braking over the 2 km the shorter way round.
        let metro = try XCTUnwrap(RealTrainRun(stops: run.stops, performance: .metro))
        let profile = try XCTUnwrap(RealRunProfile.make(km: 2, seconds: 100, performance: .metro))
        XCTAssertEqual(try XCTUnwrap(metro.place(at: 25, ringKm: 10)).km, 9 + 2 * profile.progress(after: 25), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metro.place(at: 75, ringKm: 10)).km, 2 * profile.progress(after: 75) - 1, accuracy: 1e-9)
    }

    func testTheDaysSetFollowsTheWeekdayAndHolidays() throws {
        let (traffic, line) = try onlyLine(testOperations())
        let at = 28_860.0
        XCTAssertEqual(traffic.places(of: line, at: at, on: weekday, dayBefore: weekday).count, 1)
        // Saturday's 08:00 runs the other way.
        let saturdays = traffic.places(of: line, at: at, on: saturday, dayBefore: friday)
        XCTAssertEqual(saturdays.count, 1)
        XCTAssertEqual(try XCTUnwrap(saturdays.first).towardKm, 0)
        // A holiday runs its own set, which has nothing at 08:01.
        XCTAssertTrue(traffic.places(of: line, at: at, on: RealServiceDay(weekday: 3, isHoliday: true), dayBefore: weekday).isEmpty)
        XCTAssertEqual(traffic.places(of: line, at: 36_300, on: RealServiceDay(weekday: 3, isHoliday: true), dayBefore: weekday).count, 1)

        // The game's calendar: day 0 is a Monday.
        let world = GameWorld(bounds: GameWorld.newGameBounds, economy: GameEconomy(balance: 0))
        XCTAssertEqual(RealServiceDay(world: world, day: 0), RealServiceDay(weekday: 1))
        XCTAssertEqual(RealServiceDay(world: world, day: 5).weekday, 6)
    }

    func testATripPastMidnightRunsOnTheDayBeforesSet() throws {
        let (traffic, line) = try onlyLine(testOperations())
        // Friday's 23:53 trip, at 23:55 on Friday …
        XCTAssertEqual(traffic.places(of: line, at: 86_100, on: friday, dayBefore: weekday).map(\.key), ["W#1"])
        // … and at 00:02 on Saturday, from Friday's set.
        let after = traffic.places(of: line, at: 120, on: saturday, dayBefore: friday)
        XCTAssertEqual(after.map(\.key), ["-W#1"])
        // Saturday's own set has no such trip: after Saturday, nothing.
        XCTAssertTrue(traffic.places(of: line, at: 120, on: RealServiceDay(weekday: 0), dayBefore: saturday).isEmpty)
        // Halfway: the run leaves 甲 at 86,000 and arrives at 86,120.
        let halfway = traffic.places(of: line, at: 86_060, on: friday, dayBefore: weekday)
        XCTAssertEqual(try XCTUnwrap(halfway.first).km, line.shape.lengthKm / 2, accuracy: 1e-9)
    }

    func testAHeadwayLineRunsAsManyTrainsAsItsHeadwayGives() throws {
        let (traffic, line) = try onlyLine(testOperations(headwayOnly: true))
        guard case .headway(let round, let period) = line.schedule else { return XCTFail("\(line.schedule)") }
        // There (120 s) and back (120 s), 25 s at each of three stops.
        XCTAssertEqual(period, 120 + 120 + 3 * 25)
        XCTAssertEqual(round.stops.map(\.km), [0, line.shape.lengthKm, 0])
        // 315 s over a 10-minute peak headway: one train; over 20 off-peak: one.
        XCTAssertEqual(traffic.places(of: line, at: 8 * 3_600, on: weekday, dayBefore: weekday).count, 1)
        // None between midnight and 05:00.
        XCTAssertTrue(traffic.places(of: line, at: 3 * 3_600, on: weekday, dayBefore: weekday).isEmpty)
        XCTAssertEqual(traffic.places(of: line, at: 5 * 3_600, on: weekday, dayBefore: weekday).count, 1)
    }

    func testOnlyTheTrainsInTheVisibleRegionAreDrawn() throws {
        let operations = testOperations()
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 250_000_000, longitude: 1_215_500_000))
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let traffic = RealTrainTraffic(operations: operations, frame: frame, bounds: world.bounds)
        XCTAssertEqual(traffic.lines.count, 1)
        let whole = WorldRegion(bounds: world.bounds)
        // At 08:01 the train is halfway, at the map's middle, heading east.
        let dots = traffic.trains(at: 28_860, on: weekday, dayBefore: weekday, frame: frame, visible: whole)
        let dot = try XCTUnwrap(dots.first)
        XCTAssertEqual(dots.count, 1)
        XCTAssertEqual(dot.x, frame.middleX, accuracy: 64)
        XCTAssertEqual(dot.y, frame.middleY, accuracy: 64)
        XCTAssertEqual(dot.headingX, 1, accuracy: 0.01)
        XCTAssertEqual(dot.color, RealRailways.RGB(red: 255, green: 0, blue: 0))
        // A visible region west of it: nothing drawn.
        let west = WorldRegion(minX: whole.minX, minY: whole.minY, maxX: frame.middleX - 1_000, maxY: whole.maxY)
        XCTAssertTrue(traffic.trains(at: 28_860, on: weekday, dayBefore: weekday, frame: frame, visible: west).isEmpty)
        // Saturday's train heads west.
        let back = try XCTUnwrap(traffic.trains(at: 28_860, on: saturday, dayBefore: friday, frame: frame, visible: whole).first)
        XCTAssertEqual(back.headingX, -1, accuracy: 0.01)

        // A map far from the line has none of it.
        let far = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitude: 230_000_000, longitude: 1_205_000_000)))
        XCTAssertTrue(RealTrainTraffic(operations: operations, frame: try XCTUnwrap(RealWorldFrame(world: far)), bounds: far.bounds).lines.isEmpty)
    }

    func testAStationsNextTrainsEachWay() throws {
        let operations = testOperations()
        // Weekday 07:00 at 甲: the 08:00 to 乙; nothing leaves 乙's end.
        let at甲 = operations.service(atStationNamed: "甲", siteSystem: "mrt", after: 25_200, on: weekday, dayBefore: weekday)
        XCTAssertEqual(at甲, [.next([RealNextTrain(system: "trtc", line: "L", lineName: "測試線", destination: "乙", second: 28_800)])])
        XCTAssertEqual(operations.service(atStationNamed: "乙", siteSystem: "mrt", after: 25_200, on: weekday, dayBefore: weekday), [])
        // After the morning's: the 23:53.
        let late = operations.service(atStationNamed: "甲", siteSystem: "mrt", after: 30_000, on: weekday, dayBefore: weekday)
        XCTAssertEqual(late, [.next([RealNextTrain(system: "trtc", line: "L", lineName: "測試線", destination: "乙", second: 86_000)])])
        // Another system's station of the name is not this line's.
        XCTAssertEqual(operations.service(atStationNamed: "甲", siteSystem: "tra_sched", after: 0, on: weekday, dayBefore: weekday), [])
        // A line with only headways tells how often.
        XCTAssertEqual(
            testOperations(headwayOnly: true).service(atStationNamed: "甲", siteSystem: "mrt", after: 30_000, on: weekday, dayBefore: weekday),
            [.headway(system: "trtc", line: "L", lineName: "測試線", seconds: 600)], "08:20 is the peak"
        )
        // Before 05:00 and from midnight no train of a headway line runs
        // on the map, so its card tells no headway.
        for night in [0, 3 * 3_600, 5 * 3_600 - 1] {
            XCTAssertEqual(
                testOperations(headwayOnly: true).service(atStationNamed: "甲", siteSystem: "mrt", after: night, on: weekday, dayBefore: weekday),
                [], "\(night)"
            )
        }
        XCTAssertEqual(
            testOperations(headwayOnly: true).service(atStationNamed: "甲", siteSystem: "mrt", after: 5 * 3_600, on: weekday, dayBefore: weekday).count, 1,
            "from 05:00"
        )
        XCTAssertEqual(GameSession.realClockText(28_800), "08:00")
        XCTAssertEqual(GameSession.realClockText(87_000), "00:10")
    }

    // MARK: - The bundled data

    /// A real-world game at Taipei Main Station at 08:00 on a weekday, with
    /// the bundled railways.
    private func taipei(language: DisplayLanguage = .traditionalChinese) throws -> (GameSession, PlanPoint) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        // Day 2, a Wednesday, 08:00.
        var world = GameWorld(
            bounds: GameWorld.newGameBounds, economy: GameEconomy(balance: 1_000_000),
            clock: GameClock(now: GameTime(seconds: 2 * GameTime.secondsPerDay + 8 * 3_600))
        )
        world.setGeoAnchor(try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: language)
        session.railways = try BundledRealData.railways()
        return (session, try BundledRealData.point(tra.coordinate, in: world))
    }

    func testTaipeisRealTrainsRunAtEight() throws {
        let (session, _) = try taipei()
        let operations = try XCTUnwrap(session.railways?.operations)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let traffic = RealTrainTraffic(operations: operations, frame: frame, bounds: session.world.bounds)
        let systems = Set(traffic.lines.map(\.system))
        XCTAssertTrue(systems.isSuperset(of: ["trtc", "thsr", "tra", "tymc"]), "\(systems)")
        let whole = WorldRegion(bounds: session.world.bounds)
        let day = RealServiceDay(weekday: 3)
        let all = traffic.trains(at: 8 * 3_600, on: day, dayBefore: day, frame: frame, visible: whole)
        XCTAssertGreaterThan(all.count, 50, "a weekday's morning peak round Taipei")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "each train once")
        XCTAssertTrue(all.contains { $0.id.hasPrefix("thsr|") }, "the High Speed Rail's")
        XCTAssertTrue(all.contains { $0.id.hasPrefix("tra|") }, "Taiwan Railway's")
        // A closer view draws fewer.
        let close = WorldRegion(
            minX: frame.middleX - 500 * 64, minY: frame.middleY - 500 * 64, maxX: frame.middleX + 500 * 64, maxY: frame.middleY + 500 * 64
        )
        let near = traffic.trains(at: 8 * 3_600, on: day, dayBefore: day, frame: frame, visible: close)
        XCTAssertLessThan(near.count, all.count)
        XCTAssertTrue(near.allSatisfy { $0.x >= close.minX && $0.x <= close.maxX && $0.y >= close.minY && $0.y <= close.maxY })
        // The metro rests after its last trains.
        let night = traffic.trains(at: 3 * 3_600, on: day, dayBefore: day, frame: frame, visible: whole)
        XCTAssertTrue(night.allSatisfy { !$0.id.hasPrefix("trtc|") && !$0.id.hasPrefix("tra|") }, "\(night.map(\.id))")
    }

    func testTheStationCardListsTheRealLinesNextTrains() throws {
        let (session, at) = try taipei()
        let id = try session.performEdit { try $0.buildStation(named: "台北", at: at).id }
        let lines = session.realServiceText(of: id)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertLessThanOrEqual(lines.count, GameSession.realServiceLinesShown)
        XCTAssertTrue(lines.contains { $0.hasPrefix("縱貫線北段：約每 10 分一班") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("高鐵 下一班：往") }, "\(lines)")
        let details = session.realStationDetails(of: id)
        XCTAssertTrue(lines.allSatisfy(details.contains), "\(details)")
        // Each next train leaves at or after 08:00.
        for line in lines where line.contains("下一班") {
            for time in line.matches(of: /(\d\d):(\d\d)/) {
                XCTAssertGreaterThanOrEqual(Int(time.output.1)! * 60 + Int(time.output.2)!, 8 * 60, line)
            }
        }
        // Decision 354: each way lists its trains within 15 minutes, or
        // its next one; the metro at Taipei Main has more than one that soon.
        var sawMore = false
        for line in lines where line.contains("下一班") {
            for way in line.split(separator: "；") {
                let times = way.matches(of: /(\d\d):(\d\d)/).map { Int($0.output.1)! * 60 + Int($0.output.2)! }
                XCTAssertFalse(times.isEmpty, line)
                XCTAssertLessThanOrEqual(times.count, RealRailwayOperations.realTrainsPerWay, line)
                XCTAssertEqual(times, times.sorted(), line)
                if times.count > 1 {
                    sawMore = true
                    XCTAssertTrue(times.allSatisfy { $0 <= 8 * 60 + 15 }, line)
                }
            }
        }
        XCTAssertTrue(sawMore, "\(lines)")
        // English names the destinations in English.
        let english = GameSession(world: session.world, language: .english)
        english.railways = session.railways
        let hsr = try XCTUnwrap(english.realServiceText(of: id).first { $0.hasPrefix("高鐵 next: to ") })
        XCTAssertTrue(hsr.contains("Zuoying") || hsr.contains("Nangang"), hsr)

        // A station that is no real one lists none.
        let other = try session.performEdit { try $0.buildStation(named: "我的車站", at: PlanPoint(x: at.x + 3_000 * 64, y: at.y)).id }
        XCTAssertEqual(session.realServiceText(of: other), [])
    }

    /// The cost of a frame (decision 304), only when asked:
    /// `REAL_TRAINS_REPORT=1`. For the busiest places, how many real trains
    /// the map has at the morning and evening peaks, how many a view of
    /// each width shows, and how long working them out takes.
    func testTheClockGlidesFromTheLastTickNeverPastMidnight() {
        func world(_ seconds: Int64) -> GameWorld {
            GameWorld(bounds: GameWorld.newGameBounds, economy: GameEconomy(balance: 0), clock: GameClock(now: GameTime(seconds: seconds)))
        }
        let day = Int64(2 * 86_400)
        let first = RealTrainClock(world: world(day + 28_800), time: 10)
        XCTAssertEqual(first.day, 2)
        XCTAssertEqual(first.second(at: 10), 28_800)
        XCTAssertFalse(first.isMoving)
        // The next tick 0.1 s later, a game minute on: halfway at 0.05 s.
        let next = RealTrainClock(world: world(day + 28_860), previous: first, time: 10.1)
        XCTAssertEqual(next.second(at: 10.1), 28_800)
        XCTAssertEqual(next.second(at: 10.15), 28_830, accuracy: 1e-6)
        XCTAssertEqual(next.second(at: 11), 28_860)
        XCTAssertEqual(next.second(at: 10.1, glides: false), 28_860, "paused or reduced motion: this tick's")
        XCTAssertTrue(next.isMoving)
        // Over midnight: from the new day's 00:00, on its own sets.
        let late = RealTrainClock(world: world(day + 86_370), previous: next, time: 20)
        let midnight = RealTrainClock(world: world(day + 86_430), previous: late, time: 20.1)
        XCTAssertEqual(midnight.day, 3)
        XCTAssertEqual(midnight.second(at: 20.1), 0)
        XCTAssertEqual(midnight.second(at: 30), 30)
        XCTAssertEqual(midnight.today, RealServiceDay(weekday: StationDemand.weekday(ofDay: 3)))
        XCTAssertEqual(midnight.dayBefore, late.today)
        // A jump of days (another game loaded) does not glide.
        let jumped = RealTrainClock(world: world(day + 10 * 86_400 + 600), previous: midnight, time: 21)
        XCTAssertEqual(jumped.second(at: 21), 600)
    }

    func testRealTrainsAreFainterAndSmallerAndHiddenZoomedOut() {
        let look = RealTrainTraffic.look
        XCTAssertLessThan(look.sizeShare, 1)
        XCTAssertLessThan(look.opacity, 1)
        XCTAssertLessThan(look.edgeOpacity, 1)
        XCTAssertGreaterThan(RealTrainTraffic.mostDrawn, 0)
        XCTAssertTrue(RealTrainTraffic.isShown(referenceSize: RealTrainTraffic.shownFromReferenceSize))
        XCTAssertFalse(RealTrainTraffic.isShown(referenceSize: RealTrainTraffic.shownFromReferenceSize * 0.99))
        XCTAssertTrue(RealTrainTraffic.isShown(referenceSize: MapScale.largestSize))
    }

    func testFrameCostReport() throws {
        guard ProcessInfo.processInfo.environment["REAL_TRAINS_REPORT"] != nil else {
            throw XCTSkip("set REAL_TRAINS_REPORT=1 to print the real trains' frame cost")
        }
        let railways = try BundledRealData.railways()
        let operations = try XCTUnwrap(railways.operations)
        var lines = ["| 地方 | 時刻 | 建好（ms） | 整張地圖 | 8 km 寬 | 4 km | 2 km | 每幀（整張地圖，ms） |", "| --- | --- | --: | --: | --: | --: | --: | --: |"]
        for name in ["臺北", "板橋", "高雄", "臺中"] {
            let tra = try BundledRealData.station(name, in: "tra_sched")
            var world = GameWorld(bounds: GameWorld.newGameBounds, economy: GameEconomy(balance: 0))
            world.setGeoAnchor(try XCTUnwrap(tra.anchor))
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let built = Date()
            let traffic = RealTrainTraffic(operations: operations, frame: frame, bounds: world.bounds)
            let buildMs = Date().timeIntervalSince(built) * 1_000
            let day = RealServiceDay(weekday: 3)
            for (label, second) in [("08:00", 8 * 3_600), ("18:00", 18 * 3_600)] {
                func view(_ metres: Double) -> WorldRegion {
                    let half = metres / 2 * Double(WorldCoordinate.unitsPerMetre)
                    return WorldRegion(minX: frame.middleX - half, minY: frame.middleY - half, maxX: frame.middleX + half, maxY: frame.middleY + half)
                }
                let whole = WorldRegion(bounds: world.bounds)
                let counts = [whole, view(8_000), view(4_000), view(2_000)].map {
                    traffic.trains(at: Double(second), on: day, dayBefore: day, frame: frame, visible: $0).count
                }
                let repeats = 200
                let start = Date()
                for frameIndex in 0..<repeats {
                    _ = traffic.trains(at: Double(second) + Double(frameIndex) / 10, on: day, dayBefore: day, frame: frame, visible: whole)
                }
                let frameMs = Date().timeIntervalSince(start) * 1_000 / Double(repeats)
                lines.append("| \(name) | \(label) | \(Int(buildMs.rounded())) | \(counts[0]) | \(counts[1]) | \(counts[2]) | \(counts[3]) | \(String(format: "%.2f", frameMs)) |")
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
