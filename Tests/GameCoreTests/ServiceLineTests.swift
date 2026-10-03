import Foundation
import GameCore
import XCTest

/// Service lines (Phase 4 Stage Q2a, ARCHITECTURE decision 22): plan data
/// for a line (its stops, performance, service window and trains per
/// service level), the world's service day, and what is derived from them
/// on the map: the service level at a time, the round trip a train would
/// drive, the most trains the minimum headway allows, and the headway.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
///
/// Leg times (Stage W2c, ARCHITECTURE decision 40) are the least whole
/// second a running curve is built for. A link is 1024 units (16 m) and a
/// km/h is 160/9 units a second, so the standard performance (1.5 km/h/s
/// up, 2.5 down) accelerates at 26⅔ and brakes at 44⁴⁄₉ units/s²:
/// 1/a + 1/b = 0.06 s²/unit. A run of L units too short to reach the top
/// speed takes at least √(2L × 0.06) s: 11.09 s for one link (12 s),
/// 15.68 for two (16 s), 19.2 for three (20 s), 22.17 for four (23 s) and
/// 24.79 for five (25 s). The fastest of these, 522 units/s (29 km/h)
/// for eight links, is far below the 110 km/h top speed.
final class ServiceLineTests: XCTestCase {
    // The line of `TrainServiceTests`, dead ends at both ends, on the track
    // network (Stage F3b, see `TestLine`): a node at each tile centre, edges
    // 1 to 6 of 1024 between them, and a platform either side of b, d and
    // f. Delta's platform is the second half of edge 6, touching Gamma's
    // past f at 512 (two stations cannot share a platform on the network);
    // Far has none.
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)        Far(7,3): no platform
    //
    // A line plans its journey from the berth that makes the shortest round
    // trip: the end of its first station's platform past the node going
    // east, 512 on, so its first leg is 512 shorter than from node to node.
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let delta = StationID(rawValue: 4)
    private let far = StationID(rawValue: 5)
    private let ghost = StationID(rawValue: 99)
    private let first = LineID(rawValue: 1)
    private let unknown = LineID(rawValue: 9)

    private func makeLineWorld() throws -> GameWorld {
        var world = try GameWorld(width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let delta = try world.buildStation(named: "Delta", at: TestLine.centre(5, 2)).id
        try world.addTrackPlatform(delta, on: line.edge(6), from: 512, to: 1_024)
        try world.buildStation(named: "Far", at: TestLine.centre(7, 3))
        return world
    }

    private func time(_ minutes: Int64) -> GameTime {
        GameTime(minutes: minutes)
    }

    // MARK: - Creating and editing lines

    func testNewWorldsHaveNoLinesAndTheStandardServiceDay() throws {
        let world = try makeLineWorld()
        XCTAssertEqual(world.lines, [])
        XCTAssertEqual(world.serviceDay, .standard)
        XCTAssertNil(world.line(id: first))
    }

    /// A new line gets the next ID, the standard window, the standard
    /// performance and no trains in service; it changes nothing else.
    func testCreatingALineUsesDefaultsAndChangesNothingElse() throws {
        var world = try makeLineWorld()
        let before = world
        let line = try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        XCTAssertEqual(line.id, first)
        XCTAssertEqual(line.name, "Main")
        XCTAssertEqual(line.stops, [alpha, beta, gamma])
        XCTAssertEqual(line.performance, .standard)
        XCTAssertEqual(line.window, .hours(open: 360, close: 1440))
        XCTAssertEqual(line.trainsInService, TrainsInService(peak: 0, offPeak: 0, low: 0))
        XCTAssertEqual(world.lines, [line])
        XCTAssertEqual(world.economy, before.economy, "lines are free")
        XCTAssertEqual(world.trains, before.trains)
        XCTAssertEqual(world.stations, before.stations)
        XCTAssertEqual(world.map, before.map)

        // A station may come back later, just not twice in a row.
        let loop = try world.createLine(named: "Loop", stops: [alpha, beta, alpha, gamma])
        XCTAssertEqual(loop.id, LineID(rawValue: 2))
        // IDs are never reused.
        try world.removeLine(first)
        XCTAssertEqual(world.lines.map(\.id), [LineID(rawValue: 2)])
        XCTAssertEqual(try world.createLine(named: "Third", stops: [beta, gamma]).id, LineID(rawValue: 3))
    }

    func testCreateChecksRunInTheDocumentedOrder() throws {
        var world = try makeLineWorld()
        let before = world
        XCTAssertThrowsGameError(try world.createLine(named: " ", stops: []), .invalidName)
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [ghost]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: []), .invalidLineStops)
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [alpha]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [alpha, alpha]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [alpha, beta, beta]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [alpha, ghost, StationID(rawValue: 98)]), .unknownStation(ghost))
        XCTAssertEqual(world, before, "refused commands change nothing")
    }

    /// Every edit checks the line first, then its own value; refused edits
    /// change nothing.
    func testEditsCheckTheLineFirstAndChangeOnlyTheirValue() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])

        try world.setLineStops(first, to: [gamma, delta])
        try world.setLinePerformance(first, to: .metro)
        try world.setLineServiceWindow(first, to: .allDay)
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 6, offPeak: 3, low: 1))
        let line = try XCTUnwrap(world.line(id: first))
        XCTAssertEqual(line.stops, [gamma, delta])
        XCTAssertEqual(line.performance, .metro)
        XCTAssertEqual(line.window, .allDay)
        XCTAssertEqual(line.trainsInService, TrainsInService(peak: 6, offPeak: 3, low: 1))
        XCTAssertEqual(line.name, "Main")

        let before = world
        XCTAssertThrowsGameError(try world.setLineStops(unknown, to: []), .unknownLine(unknown))
        XCTAssertThrowsGameError(try world.setLineStops(first, to: [ghost]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.setLineStops(first, to: [alpha, ghost]), .unknownStation(ghost))
        let slow = TrainPerformance(acceleration: 0, braking: 2_500, topSpeed: 110)
        XCTAssertThrowsGameError(try world.setLinePerformance(unknown, to: slow), .unknownLine(unknown))
        for performance in [
            slow, TrainPerformance(acceleration: 1_500, braking: -1, topSpeed: 110),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: RunningCurve.maximumRate + 1),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, alternativeAcceleration: 0, alternativeBraking: 2_700),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 2_500, speedRatio: 450)),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 450, speedRatio: 1_000)),
        ] {
            XCTAssertThrowsGameError(try world.setLinePerformance(first, to: performance), .invalidTrainPerformance)
        }
        XCTAssertThrowsGameError(try world.setLineServiceWindow(unknown, to: .hours(open: -1, close: 0)), .unknownLine(unknown))
        for window: ServiceWindow in [
            .hours(open: -1, close: 100), .hours(open: 1440, close: 1500), .hours(open: 600, close: 600),
            .hours(open: 600, close: 500), .hours(open: 0, close: 1801), .hours(open: 1439, close: .max),
        ] {
            XCTAssertThrowsGameError(try world.setLineServiceWindow(first, to: window), .invalidServiceWindow)
        }
        XCTAssertThrowsGameError(try world.setLineTrainsInService(unknown, to: TrainsInService(peak: -1, offPeak: 0, low: 0)), .unknownLine(unknown))
        for trains in [TrainsInService(peak: -1, offPeak: 0, low: 0), TrainsInService(peak: 0, offPeak: -1, low: 0), TrainsInService(peak: 0, offPeak: 0, low: .min)] {
            XCTAssertThrowsGameError(try world.setLineTrainsInService(first, to: trains), .invalidTrainsInService)
        }
        XCTAssertThrowsGameError(try world.removeLine(unknown), .unknownLine(unknown))
        XCTAssertEqual(world, before, "refused commands change nothing")

        // The widest windows are allowed: open at 23:59, close at 06:00.
        try world.setLineServiceWindow(first, to: .hours(open: 1439, close: 1800))
        try world.setLineServiceWindow(first, to: .hours(open: 0, close: 1))
        try world.setLineTrainsInService(first, to: TrainsInService(peak: .max, offPeak: 0, low: 0))
        let limit = RunningCurve.maximumRate
        try world.setLinePerformance(first, to: TrainPerformance(acceleration: limit, braking: limit, topSpeed: limit))
    }

    // MARK: - The service day

    func testTheServiceLevelFollowsTheDayWhileTheWindowIsOpen() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta])
        // The standard window, 06:00 to midnight, on the standard day.
        let expected: [(Int64, ServiceLevel?)] = [
            (0, nil), (359, nil), (360, .low), (419, .low), (420, .peak), (599, .peak), (600, .offPeak),
            (959, .offPeak), (960, .peak), (1199, .peak), (1200, .offPeak), (1259, .offPeak), (1260, .low), (1439, .low),
            // Day 2, and minutes before minute 0 (the day before).
            (1440 + 420, .peak), (-1, .low), (-1081, nil),
        ]
        for (minute, level) in expected {
            XCTAssertEqual(world.serviceLevel(of: first, at: time(minute)), level, "minute \(minute)")
        }
        XCTAssertNil(world.serviceLevel(of: unknown, at: time(420)))

        // Open until 01:00 the next morning: 00:30 is in service, at its level.
        try world.setLineServiceWindow(first, to: .hours(open: 360, close: 1500))
        XCTAssertEqual(world.serviceLevel(of: first, at: time(30)), .low)
        XCTAssertNil(world.serviceLevel(of: first, at: time(60)))
        XCTAssertEqual(world.serviceLevel(of: first, at: time(1439)), .low)
        try world.setLineServiceWindow(first, to: .allDay)
        XCTAssertEqual(world.serviceLevel(of: first, at: time(0)), .low)
        XCTAssertEqual(world.serviceLevel(of: first, at: time(480)), .peak)
    }

    func testTheServiceDayCanBeChangedButMustCoverTheDay() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta])
        try world.setLineServiceWindow(first, to: .allDay)
        let day = ServiceDay(bands: [ServiceDay.Band(start: 0, level: .offPeak), ServiceDay.Band(start: 480, level: .peak)])
        try world.setServiceDay(day)
        XCTAssertEqual(world.serviceDay, day)
        XCTAssertEqual(world.serviceLevel(of: first, at: time(100)), .offPeak)
        XCTAssertEqual(world.serviceLevel(of: first, at: time(480)), .peak)
        XCTAssertEqual(world.serviceLevel(of: first, at: time(1439)), .peak)

        let before = world
        for bands: [(Int, ServiceLevel)] in [[], [(10, .low)], [(0, .low), (100, .peak), (100, .low)], [(0, .low), (1440, .peak)], [(0, .low), (-5, .peak)]] {
            let invalid = ServiceDay(bands: bands.map { ServiceDay.Band(start: $0.0, level: $0.1) })
            XCTAssertThrowsGameError(try world.setServiceDay(invalid), .invalidServiceDay)
        }
        XCTAssertEqual(world, before)
    }

    // MARK: - Journeys

    /// Alpha to Gamma by Beta and back, with the standard performance, from
    /// the end of Alpha's platform past b (edge 2 forward, 512): the first
    /// leg is 1536 units, √(2 × 1536 × 0.06) = 13.58, so 14 s, and the
    /// others two links, 2048, 16 s; four legs (62 s), a minute at Beta each
    /// way and two at each end (360 s) make 422 s, 8 minutes rounded up.
    /// From b itself (edge 1 forward, 1024), the first berth along the
    /// track, the round trip is 424 s; the shorter wins.
    func testALineRoundTripIsItsLegsAndItsDwells() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        let journey = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(journey.start, .onEdge(TrackTraversal(edge: line.edge(2), direction: .forward), offset: 512))
        XCTAssertEqual(networkLegs(journey), [
            NetworkLeg(from: 0, to: 1, traversals: line.path(from: 2, through: [3]), distance: 1_536, seconds: 14),
            NetworkLeg(from: 1, to: 2, traversals: line.path(from: 3, through: [4, 5]), distance: 2_048, seconds: 16),
            // Turned round at Gamma it stands at f on edge 5 going back.
            NetworkLeg(from: 2, to: 1, traversals: line.path(from: 4, through: [3]), distance: 2_048, seconds: 16),
            NetworkLeg(from: 1, to: 0, traversals: line.path(from: 3, through: [2, 1]), distance: 2_048, seconds: 16),
        ])
        XCTAssertEqual(journey.roundTripSeconds, 422)
        XCTAssertEqual(journey.roundTripMinutes, 8)

        // Other performances, over the same 1536 and 2048 units:
        // - metro (3.96 and 4.68 km/h/s): 1/a + 1/b = 0.02622, √(3072 ×
        //   0.02622) = 8.98 s and √(4096 × 0.02622) = 10.36 s, so 9 and 11 s,
        //   402 s, 7 minutes;
        // - the forest railway (0.7 and 1.1): 0.13149, 20.10 and 23.21 s, so
        //   21 and 24 s, 453 s, 8 minutes;
        // - a top speed of 2 km/h (35⅑ units/s), which it reaches: 1536 ÷
        //   35⅑ = 43.2 s and 2048 ÷ 35⅑ = 57.6 s cruising, plus 35⅑ × 0.06 ÷
        //   2 = 1.07 s lost speeding up and slowing down, 44.27 and 58.67 s,
        //   so 45 and 59 s, 582 s, 10 minutes.
        let crawl = TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 2)
        for (performance, firstLeg, leg, roundTrip): (TrainPerformance, Int64, Int64, Int64) in [(.metro, 9, 11, 7), (.forestRailway, 21, 24, 8), (crawl, 45, 59, 10)] {
            try world.setLinePerformance(first, to: performance)
            XCTAssertEqual(world.lineJourney(first)?.legs.map(\.seconds), [firstLeg, leg, leg, leg], "\(performance)")
            XCTAssertEqual(world.lineJourney(first)?.roundTripMinutes, roundTrip, "\(performance)")
        }

        // Two stops: 3584 out (√430.08 = 20.74, 21 s) and four links back
        // (4096, 23 s), and the two ends: 284 s, 5 minutes.
        try world.setLinePerformance(first, to: .standard)
        try world.setLineStops(first, to: [alpha, gamma])
        XCTAssertEqual(world.lineJourney(first)?.legs.map(\.seconds), [21, 23])
        XCTAssertEqual(world.lineJourney(first)?.roundTripMinutes, 5)
        // Stations whose platforms touch: from the end of Gamma's platform
        // past f (edge 6, 512), where Delta's begins, 512 to the end of
        // Delta's (√61.44 = 7.84, 8 s), turned round there, 1024 back to f,
        // Gamma's berth going back (√122.88 = 11.09, 12 s): 260 s, 5 minutes.
        try world.setLineStops(first, to: [gamma, delta])
        let shared = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(networkLegs(shared), [
            NetworkLeg(from: 0, to: 1, traversals: [], distance: 512, seconds: 8),
            NetworkLeg(from: 1, to: 0, traversals: [], distance: 1_024, seconds: 12),
        ])
        XCTAssertEqual(shared.roundTripSeconds, 260)
        XCTAssertEqual(shared.roundTripMinutes, 5)
        XCTAssertEqual(shared.start, .onEdge(TrackTraversal(edge: line.edge(6), direction: .forward), offset: 512))
    }

    /// A line whose journey cannot be driven has none, nor a maximum,
    /// trains in service or a headway: a station without a platform, track
    /// removed, or an unknown line.
    func testALineThatCannotBeDrivenHasNoJourney() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Far", stops: [alpha, far])
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 3, offPeak: 3, low: 3))
        XCTAssertNil(world.lineJourney(first))
        XCTAssertNil(world.lineMaximumTrains(first))
        XCTAssertNil(world.lineTrainsInService(first, at: .peak))
        XCTAssertNil(world.lineHeadway(first, at: .peak))
        XCTAssertNil(world.lineJourney(unknown))

        let main = LineID(rawValue: 2)
        XCTAssertNotNil(world.lineJourney(main))
        // Edge 4, d to e, carries Beta's platform past d: that goes first.
        try world.removeTrackPlatform(beta, on: line.edge(4), from: 0)
        try world.removeTrackEdge(line.edge(4))
        XCTAssertNil(world.lineJourney(main), "Gamma is cut off")
        // Rebuilt, it is a new edge (7) without the platform. Back from
        // Gamma the train stops at Beta's other platform, 512 short of d
        // (2560, √307.2 = 17.53, 18 s), and goes on 1536 to Alpha (14 s):
        // 14 + 16 + 18 + 14 + 360 = 422 s, 8 minutes again.
        try world.buildTrackEdge(from: line.node(3), to: line.node(4))
        XCTAssertEqual(world.lineJourney(main)?.legs.map(\.seconds), [14, 16, 18, 14])
        XCTAssertEqual(world.lineJourney(main)?.roundTripMinutes, 8, "derived again from the map")
    }

    /// Of the starts that can drive the line, the shortest round trip wins,
    /// even when an earlier start drives it the long way round. Alpha's
    /// platforms are, in order along the track, the one on edge 1 (its
    /// berths at b going east and 512 back from b going west) and the one on
    /// edge 2 (512 past b going east, at b going west). Going west from
    /// either platform the train meets a's dead end; going east, from b on
    /// edge 1, the earlier start, the round trip is 424 s (four legs of
    /// 2048, back to b on Alpha's second platform); from 512 past b, 422 s.
    func testTheShortestRoundTripIsChosen() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        let journey = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(journey.start, .onEdge(TrackTraversal(edge: line.edge(2), direction: .forward), offset: 512))
        XCTAssertEqual(journey.roundTripSeconds, 422)

        // Without the second platform only the first is left: from b, three
        // legs of 2048 (16 s each), and back going west the train stops at
        // the far end of that platform, 512 short of b, 2560 (√307.2 =
        // 17.53, 18 s): 426 s.
        try world.removeTrackPlatform(alpha, on: line.edge(2), from: 0)
        let fromB = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(fromB.start, line.at(1, facingEast: true))
        XCTAssertEqual(fromB.legs.map(\.seconds), [16, 16, 16, 18])
        XCTAssertEqual(fromB.legs.map(\.path.distance), [2_048, 2_048, 2_048, 2_560])
        XCTAssertEqual(fromB.roundTripSeconds, 426)
    }

    // MARK: - Trains and headway

    /// The 8-minute round trip allows 4 trains two minutes apart. A level
    /// runs the trains set for it, up to that; the headway shares the round
    /// trip between them, rounded up.
    func testTrainsInServiceAreCappedByTheMinimumHeadway() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        XCTAssertEqual(world.lineMaximumTrains(first), 4)
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 10, offPeak: 3, low: 0))
        XCTAssertEqual(world.lineTrainsInService(first, at: .peak), 4)
        XCTAssertEqual(world.lineTrainsInService(first, at: .offPeak), 3)
        XCTAssertEqual(world.lineTrainsInService(first, at: .low), 0)
        XCTAssertEqual(world.lineHeadway(first, at: .peak), 2)
        XCTAssertEqual(world.lineHeadway(first, at: .offPeak), 3)
        XCTAssertNil(world.lineHeadway(first, at: .low), "no trains, no headway")
        XCTAssertEqual(world.line(id: first)?.trainsInService.peak, 10, "the count set is kept as it is")

        // A short round trip, 5 minutes (Gamma and Delta, see above), allows
        // two trains, 3 minutes apart (5 ÷ 2 rounded up).
        try world.setLineStops(first, to: [gamma, delta])
        XCTAssertEqual(world.lineJourney(first)?.roundTripMinutes, 5)
        XCTAssertEqual(world.lineMaximumTrains(first), 2)
        try world.setServiceDay(.standard)
        XCTAssertEqual(world.lineHeadway(first, at: .peak), 3)
        XCTAssertEqual(world.lineHeadway(first, at: .offPeak), 3)

        // Slower (a top speed of 2 km/h, see above): 10 minutes allow 5
        // trains; three are 4 minutes apart.
        try world.setLineStops(first, to: [alpha, beta, gamma])
        try world.setLinePerformance(first, to: TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 2))
        XCTAssertEqual(world.lineMaximumTrains(first), 5)
        XCTAssertEqual(world.lineHeadway(first, at: .offPeak), 4)
    }

    // MARK: - Saving

    /// A world without lines and with the standard day saves exactly as
    /// before lines existed; lines, the next line ID and a changed day are
    /// saved only when there are any.
    func testLinesAreSavedOnlyWhenThereAreAny() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var world = try makeLineWorld()
        var text = String(decoding: try encoder.encode(world), as: UTF8.self)
        for key in [#""lines""#, #""nextLineID""#, #""serviceDay""#] {
            XCTAssertFalse(text.contains(key), key)
        }

        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(first, to: .hours(open: 300, close: 1500))
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 4, offPeak: 2, low: 1))
        try world.createLine(named: "All day", stops: [beta, gamma])
        try world.setLineServiceWindow(LineID(rawValue: 2), to: .allDay)
        text = String(decoding: try encoder.encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(
            #""lines":[{"id":1,"name":"Main","stops":[1,2,3],"trainsInService":{"low":1,"offPeak":2,"peak":4},"window":{"close":1500,"open":300}},"#
                + #"{"id":2,"name":"All day","stops":[2,3],"trainsInService":{"low":0,"offPeak":0,"peak":0},"window":"allDay"}]"#
        ), text)
        XCTAssertTrue(text.contains(#""nextLineID":3"#), text)
        XCTAssertFalse(text.contains(#""serviceDay""#), text)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: encoder.encode(world))
        XCTAssertEqual(loaded, world)

        // Every line removed: the next ID is still saved, so IDs are never reused.
        try world.removeLine(first)
        try world.removeLine(LineID(rawValue: 2))
        try world.setServiceDay(ServiceDay(bands: [ServiceDay.Band(start: 0, level: .peak)]))
        text = String(decoding: try encoder.encode(world), as: UTF8.self)
        XCTAssertFalse(text.contains(#""lines""#), text)
        XCTAssertTrue(text.contains(#""nextLineID":3"#), text)
        XCTAssertTrue(text.contains(#""serviceDay":[{"level":"peak","start":0}]"#), text)
        loaded = try JSONDecoder().decode(GameWorld.self, from: encoder.encode(world))
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try loaded.createLine(named: "Next", stops: [alpha, beta]).id, LineID(rawValue: 3))
    }

    /// Bad lines, IDs and days are refused when loading, never repaired.
    func testMalformedLinesAreRejectedNotRepaired() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.createLine(named: "Short", stops: [beta, gamma])
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])

        func decode(_ change: (inout [String: Any]) -> Void) throws -> GameWorld {
            var object = saved
            change(&object)
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }
        func line(_ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
            { object in
                var lines = object["lines"] as! [[String: Any]]
                change(&lines[0])
                object["lines"] = lines
            }
        }

        XCTAssertEqual(try decode { _ in }, world)
        let malformed: [(String, (inout [String: Any]) -> Void)] = [
            ("null lines", { $0["lines"] = NSNull() }),
            ("null next ID", { $0["nextLineID"] = NSNull() }),
            ("null day", { $0["serviceDay"] = NSNull() }),
            ("next ID not above the lines", { $0["nextLineID"] = 2 }),
            ("next ID 0", { $0["nextLineID"] = 0 }),
            ("lines out of order", { object in
                let lines = object["lines"] as! [[String: Any]]
                object["lines"] = Array(lines.reversed())
            }),
            ("a repeated ID", line { $0["id"] = 2 }),
            ("ID 0", line { $0["id"] = 0 }),
            ("a blank name", line { $0["name"] = " " }),
            ("one stop", line { $0["stops"] = [1] }),
            ("a stop twice in a row", line { $0["stops"] = [1, 1, 2] }),
            ("an unknown station", line { $0["stops"] = [1, 99] }),
            ("a null performance", line { $0["performance"] = NSNull() }),
            ("no acceleration", line { $0["performance"] = ["acceleration": 0, "braking": 2_500, "topSpeed": 110] }),
            ("no top speed", line { $0["performance"] = ["acceleration": 1_500, "braking": 2_500] }),
            ("a negative count", line { $0["trainsInService"] = ["peak": -1, "offPeak": 0, "low": 0] }),
            ("a missing count", line { $0["trainsInService"] = ["peak": 1, "offPeak": 0] }),
            ("a window closing at opening", line { $0["window"] = ["open": 600, "close": 600] }),
            ("a window past 06:00", line { $0["window"] = ["open": 600, "close": 1801] }),
            ("a window opening at 24:00", line { $0["window"] = ["open": 1440, "close": 1500] }),
            ("an unknown window", line { $0["window"] = "sometimes" }),
            ("an empty day", { $0["serviceDay"] = [Any]() }),
            ("a day not starting at 0", { $0["serviceDay"] = [["start": 5, "level": "low"]] }),
            ("a day going back", { $0["serviceDay"] = [["start": 0, "level": "low"], ["start": 600, "level": "peak"], ["start": 500, "level": "low"]] }),
            ("an unknown level", { $0["serviceDay"] = [["start": 0, "level": "rush"]] }),
        ]
        for (what, change) in malformed {
            XCTAssertThrowsError(try decode(change), what)
        }
        // Without the keys, a world with no lines and the standard day.
        let bare = try decode { object in
            object["lines"] = nil
            object["nextLineID"] = nil
            object["serviceDay"] = nil
        }
        XCTAssertEqual(bare.lines, [])
        XCTAssertEqual(bare.serviceDay, .standard)
    }

    /// Once the last line ID has been handed out, creating a line is refused.
    func testCreatingALineOnceIDsRunOutIsRefused() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(makeLineWorld())) as? [String: Any])
        object["nextLineID"] = Int.max
        var world = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        let before = world
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [alpha, beta]), .idsExhausted)
        XCTAssertEqual(world, before)
        object["nextLineID"] = Int.max - 1
        world = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(try world.createLine(named: "Last", stops: [alpha, beta]).id, LineID(rawValue: .max - 1))
        XCTAssertThrowsGameError(try world.createLine(named: "L", stops: [alpha, beta]), .idsExhausted)
    }
}

/// A leg of a journey on the track network as these tests read it: the
/// calls it joins, the traversals it enters after the edge it starts on,
/// how far it runs and in how many seconds.
private struct NetworkLeg: Equatable {
    let from: Int
    let to: Int
    let traversals: [TrackTraversal]
    let distance: Int64
    let seconds: Int64
}

private func networkLegs(_ journey: LineJourney) -> [NetworkLeg] {
    journey.legs.map { NetworkLeg(from: $0.from, to: $0.to, traversals: $0.path.traversals, distance: $0.path.distance, seconds: $0.seconds) }
}
