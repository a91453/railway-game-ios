import Foundation
import GameCore
import XCTest

/// Service lines (Phase 4 Stage Q2a, ARCHITECTURE decision 22): plan data
/// for a line (its stops, rate, service window and trains per service
/// level), the world's service day, and what is derived from them on the
/// map: the service level at a time, the round trip a train would drive,
/// the most trains the minimum headway allows, and the headway.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class ServiceLineTests: XCTestCase {
    // The line of `TrainServiceTests`, dead ends at both ends:
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)        Far(7,3): no platform
    private let b = GridPosition(x: 1, y: 1)
    private let c = GridPosition(x: 2, y: 1)
    private let d = GridPosition(x: 3, y: 1)
    private let e = GridPosition(x: 4, y: 1)
    private let f = GridPosition(x: 5, y: 1)
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
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        for tile in [b, c, d, e, f] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 6, y: 1), connections: .west)
        try world.buildStation(named: "Alpha", at: GridPosition(x: 1, y: 0))
        try world.buildStation(named: "Beta", at: GridPosition(x: 3, y: 0))
        try world.buildStation(named: "Gamma", at: GridPosition(x: 5, y: 0))
        try world.buildStation(named: "Delta", at: GridPosition(x: 5, y: 2))
        try world.buildStation(named: "Far", at: GridPosition(x: 7, y: 3))
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

    /// A new line gets the next ID, the standard window, the default rate
    /// (one link a minute) and no trains in service; it changes nothing else.
    func testCreatingALineUsesDefaultsAndChangesNothingElse() throws {
        var world = try makeLineWorld()
        let before = world
        let line = try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        XCTAssertEqual(line.id, first)
        XCTAssertEqual(line.name, "Main")
        XCTAssertEqual(line.stops, [alpha, beta, gamma])
        XCTAssertEqual(line.rate, 1024)
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
        try world.setLineRate(first, to: 700)
        try world.setLineServiceWindow(first, to: .allDay)
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 6, offPeak: 3, low: 1))
        let line = try XCTUnwrap(world.line(id: first))
        XCTAssertEqual(line.stops, [gamma, delta])
        XCTAssertEqual(line.rate, 700)
        XCTAssertEqual(line.window, .allDay)
        XCTAssertEqual(line.trainsInService, TrainsInService(peak: 6, offPeak: 3, low: 1))
        XCTAssertEqual(line.name, "Main")

        let before = world
        XCTAssertThrowsGameError(try world.setLineStops(unknown, to: []), .unknownLine(unknown))
        XCTAssertThrowsGameError(try world.setLineStops(first, to: [ghost]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.setLineStops(first, to: [alpha, ghost]), .unknownStation(ghost))
        XCTAssertThrowsGameError(try world.setLineRate(unknown, to: 0), .unknownLine(unknown))
        for rate: Int64 in [0, -1, .min] {
            XCTAssertThrowsGameError(try world.setLineRate(first, to: rate), .invalidLineRate)
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
        try world.setLineRate(first, to: .max)
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

    /// Alpha to Gamma by Beta and back, at one link a minute: each leg is two
    /// links, so two minutes; four legs, a minute at Beta each way, and two
    /// at each end make 14 minutes. Facing north, east or south at b all
    /// drive it (only west, towards the dead end, cannot); north comes first.
    func testALineRoundTripIsItsLegsAndItsDwells() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        let journey = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(journey.start, .atNode(b, heading: .north))
        XCTAssertEqual(journey.legs, [
            LineLeg(from: 0, to: 1, route: [c, d], minutes: 2),
            LineLeg(from: 1, to: 2, route: [e, f], minutes: 2),
            LineLeg(from: 2, to: 1, route: [e, d], minutes: 2),
            LineLeg(from: 1, to: 0, route: [c, b], minutes: 2),
        ])
        XCTAssertEqual(journey.roundTripMinutes, 14)

        // Legs round up: 2048 units at 700 a minute is 3 minutes; at 3000,
        // 1 minute; at 512, 4 minutes.
        for (rate, roundTrip): (Int64, Int64) in [(700, 18), (3000, 10), (512, 22), (.max, 10)] {
            try world.setLineRate(first, to: rate)
            XCTAssertEqual(world.lineJourney(first)?.roundTripMinutes, roundTrip, "rate \(rate)")
        }

        // Two stops: four links each way, and the two ends.
        try world.setLineRate(first, to: 1024)
        try world.setLineStops(first, to: [alpha, gamma])
        XCTAssertEqual(world.lineJourney(first)?.roundTripMinutes, 12)
        // Stations sharing a platform: no travel, only the ends.
        try world.setLineStops(first, to: [gamma, delta])
        let shared = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(shared.legs, [LineLeg(from: 0, to: 1, route: [], minutes: 0), LineLeg(from: 1, to: 0, route: [], minutes: 0)])
        XCTAssertEqual(shared.roundTripMinutes, 4)
        XCTAssertEqual(shared.start, .atNode(f, heading: .north))
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
        try world.removeTrack(at: e)
        XCTAssertNil(world.lineJourney(main), "Gamma is cut off")
        try world.buildTrack(at: e, connections: [.east, .west])
        XCTAssertEqual(world.lineJourney(main)?.roundTripMinutes, 14, "derived again from the map")
    }

    /// Of the starts that can drive the line, the shortest round trip wins,
    /// even when an earlier start drives it the long way round.
    func testTheShortestRoundTripIsChosen() throws {
        // A ring, with A's platform (1,2) on its west side, running north
        // and south, and B's platform (3,3) on its south-east corner:
        //
        //   (1,1)-(2,1)-(3,1)
        //     |           |
        //  A (1,2)      (3,2)
        //     |           |
        //   (1,3)-(2,3)-(3,3) B
        var world = try GameWorld(width: 5, height: 5, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        let ring: [(Int, Int, TrackConnections)] = [
            (1, 1, [.east, .south]), (2, 1, [.east, .west]), (3, 1, [.west, .south]), (3, 2, [.north, .south]),
            (3, 3, [.north, .west]), (2, 3, [.east, .west]), (1, 3, [.east, .north]), (1, 2, [.north, .south]),
        ]
        for (x, y, connections) in ring {
            try world.buildTrack(at: GridPosition(x: x, y: y), connections: connections)
        }
        try world.buildStation(named: "A", at: GridPosition(x: 0, y: 2))
        try world.buildStation(named: "B", at: GridPosition(x: 4, y: 3))
        try world.createLine(named: "Ring", stops: [StationID(rawValue: 1), StationID(rawValue: 2)])

        // Facing north, the train must go round the top: five links out,
        // three back (turned round at B it may leave west). Facing east it
        // may leave south: three links each way.
        let journey = try XCTUnwrap(world.lineJourney(first))
        XCTAssertEqual(journey.start, .atNode(GridPosition(x: 1, y: 2), heading: .east))
        XCTAssertEqual(journey.legs, [
            LineLeg(from: 0, to: 1, route: [GridPosition(x: 1, y: 3), GridPosition(x: 2, y: 3), GridPosition(x: 3, y: 3)], minutes: 3),
            LineLeg(from: 1, to: 0, route: [GridPosition(x: 2, y: 3), GridPosition(x: 1, y: 3), GridPosition(x: 1, y: 2)], minutes: 3),
        ])
        XCTAssertEqual(journey.roundTripMinutes, 10)
    }

    // MARK: - Trains and headway

    /// The 14-minute round trip allows 7 trains two minutes apart. A level
    /// runs the trains set for it, up to that; the headway shares the round
    /// trip between them, rounded up.
    func testTrainsInServiceAreCappedByTheMinimumHeadway() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        XCTAssertEqual(world.lineMaximumTrains(first), 7)
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 10, offPeak: 3, low: 0))
        XCTAssertEqual(world.lineTrainsInService(first, at: .peak), 7)
        XCTAssertEqual(world.lineTrainsInService(first, at: .offPeak), 3)
        XCTAssertEqual(world.lineTrainsInService(first, at: .low), 0)
        XCTAssertEqual(world.lineHeadway(first, at: .peak), 2)
        XCTAssertEqual(world.lineHeadway(first, at: .offPeak), 5)
        XCTAssertNil(world.lineHeadway(first, at: .low), "no trains, no headway")
        XCTAssertEqual(world.line(id: first)?.trainsInService.peak, 10, "the count set is kept as it is")

        // A round trip shorter than the minimum headway still allows one.
        try world.setLineStops(first, to: [gamma, delta])
        XCTAssertEqual(world.lineJourney(first)?.roundTripMinutes, 4)
        XCTAssertEqual(world.lineMaximumTrains(first), 2)
        try world.setServiceDay(.standard)
        try world.setLineRate(first, to: 1024)
        XCTAssertEqual(world.lineHeadway(first, at: .peak), 2)
        XCTAssertEqual(world.lineHeadway(first, at: .offPeak), 2)

        // Slower: 22 minutes allow 11 trains; three are 8 minutes apart.
        try world.setLineStops(first, to: [alpha, beta, gamma])
        try world.setLineRate(first, to: 512)
        XCTAssertEqual(world.lineMaximumTrains(first), 11)
        XCTAssertEqual(world.lineHeadway(first, at: .offPeak), 8)
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
            #""lines":[{"id":1,"name":"Main","rate":1024,"stops":[1,2,3],"trainsInService":{"low":1,"offPeak":2,"peak":4},"window":{"close":1500,"open":300}},"#
                + #"{"id":2,"name":"All day","rate":1024,"stops":[2,3],"trainsInService":{"low":0,"offPeak":0,"peak":0},"window":"allDay"}]"#
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
            ("rate 0", line { $0["rate"] = 0 }),
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
