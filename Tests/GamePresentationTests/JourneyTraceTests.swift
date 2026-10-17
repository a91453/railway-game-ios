import GameCore
@testable import GamePresentation
import XCTest

/// Decision 220: the journey trace, the busiest trips of a held station as
/// arcs on the map (after the `Ci/` reference's station OD layer).
final class JourneyTraceTests: XCTestCase {
    private let traced = StationID(rawValue: 1)

    /// The five busiest pairs, both ways added, busiest first; ties go to
    /// the lower station, and a pair with no trips is never drawn.
    func testTheFiveBusiestPairsBusiestFirst() {
        let pairs = [
            StationDemandPair(station: StationID(rawValue: 2), outbound: 100, inbound: 100),
            StationDemandPair(station: StationID(rawValue: 3), outbound: 900, inbound: 100),
            StationDemandPair(station: StationID(rawValue: 4), outbound: 0, inbound: 0),
            StationDemandPair(station: StationID(rawValue: 5), outbound: 300, inbound: 0),
            StationDemandPair(station: StationID(rawValue: 6), outbound: 0, inbound: 500),
            StationDemandPair(station: StationID(rawValue: 7), outbound: 250, inbound: 250),
            StationDemandPair(station: StationID(rawValue: 8), outbound: 10, inbound: 0),
        ]
        let trace = JourneyTrace(station: traced, pairs: pairs)
        XCTAssertEqual(trace.station, traced)
        XCTAssertEqual(trace.arcs.map(\.station.rawValue), [3, 6, 7, 5, 2])
        XCTAssertEqual(trace.arcs.map(\.trips), [1_000, 500, 500, 300, 200])
        XCTAssertEqual(trace.arcs[0].outbound, 900)
        XCTAssertEqual(trace.arcs[0].inbound, 100)
        for (width, expected) in zip(trace.arcs.map(\.width), [6.3, 3.55, 3.55, 2.45, 2.0]) {
            XCTAssertEqual(width, expected, accuracy: 1e-9)
        }

        XCTAssertEqual(JourneyTrace(station: traced, pairs: []).arcs, [])
        XCTAssertEqual(JourneyTrace(station: traced, pairs: [pairs[2]]).arcs, [], "no trips, no arc")
    }

    /// The reference's `0.8 + 5.5 × v / max`, never narrower than 2 points.
    func testTheWidthFollowsTheTrips() {
        XCTAssertEqual(JourneyTrace.width(of: 1_000, largest: 1_000), 6.3, accuracy: 1e-9)
        XCTAssertEqual(JourneyTrace.width(of: 500, largest: 1_000), 3.55, accuracy: 1e-9)
        XCTAssertEqual(JourneyTrace.width(of: 1, largest: 1_000), JourneyTrace.narrowest)
        XCTAssertEqual(JourneyTrace.width(of: 0, largest: 0), JourneyTrace.narrowest)
        XCTAssertEqual(JourneyTrace.width(of: 2_000, largest: 1_000), 6.3, accuracy: 1e-9, "never wider than the busiest")
    }

    /// Each arc bends to the left of its way on the screen (y grows down),
    /// a fifth of its chord off the middle, so the arcs of a trace fan out.
    func testTheArcsBendToTheLeftOfTheirWay() {
        let start = ScreenPoint(x: 0, y: 0)
        XCTAssertEqual(JourneyTrace.control(from: start, to: ScreenPoint(x: 100, y: 0)), ScreenPoint(x: 50, y: -20))
        XCTAssertEqual(JourneyTrace.control(from: start, to: ScreenPoint(x: 0, y: 100)), ScreenPoint(x: 20, y: 50))
        XCTAssertEqual(JourneyTrace.apex(from: start, to: ScreenPoint(x: 100, y: 0)), ScreenPoint(x: 50, y: -10))
        XCTAssertEqual(JourneyTrace.control(from: start, to: start), start, "a station on top of another: no bend")
    }

    /// Drawn out in eight steps over 0.4 seconds; at once with Reduce Motion.
    func testTheArcsDrawOutUnlessMotionIsReduced() {
        XCTAssertEqual(JourneyTrace.progress(elapsed: 0, reduceMotion: false), 0.125)
        XCTAssertEqual(JourneyTrace.progress(elapsed: 0.2, reduceMotion: false), 0.625)
        XCTAssertEqual(JourneyTrace.progress(elapsed: 0.4, reduceMotion: false), 1)
        XCTAssertEqual(JourneyTrace.progress(elapsed: 5, reduceMotion: false), 1)
        XCTAssertEqual(JourneyTrace.progress(elapsed: -1, reduceMotion: false), 0.125)
        for elapsed in [0, 0.1, 0.3] {
            XCTAssertEqual(JourneyTrace.progress(elapsed: elapsed, reduceMotion: true), 1)
        }
        let steps = stride(from: 0.0, to: 0.45, by: 0.01).map { JourneyTrace.progress(elapsed: $0, reduceMotion: false) }
        XCTAssertEqual(steps, steps.sorted(), "it only grows")
        XCTAssertEqual(Set(steps).count, JourneyTrace.drawSteps)
    }

    /// Read from the world's daily demand: the station panel's pairs, the
    /// busiest of them, with their names for VoiceOver.
    func testAWorldsTraceIsItsBusiestDemandPairs() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        let alpha = StationID(rawValue: 1), beta = StationID(rawValue: 2), gamma = StationID(rawValue: 3), delta = StationID(rawValue: 4)
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 3_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 3_000))
        try world.setStationDemand(delta, to: StationDemand(kind: .office, dailyTrips: 9_000))

        let trace = world.journeyTrace(of: alpha)
        let pairs = world.stationDemandPairs(of: alpha)
        XCTAssertEqual(Set(trace.arcs.map(\.station)), Set(pairs.map(\.station)))
        XCTAssertFalse(trace.arcs.contains { $0.station == delta }, "no line reaches Delta")
        XCTAssertEqual(trace.arcs.map(\.station), [gamma, beta])
        for arc in trace.arcs {
            let pair = try XCTUnwrap(pairs.first { $0.station == arc.station })
            XCTAssertEqual(arc.outbound, pair.outbound)
            XCTAssertEqual(arc.inbound, pair.inbound)
        }
        let names = trace.arcs.map { "\(world.station(id: $0.station)!.name) \(Money($0.trips).displayText)" }
        XCTAssertEqual(trace.summary(in: world, language: .english), "Busiest trips: \(names.joined(separator: ", ")) a day")
        XCTAssertEqual(trace.summary(in: world, language: .traditionalChinese), "最多人往返：\(names.joined(separator: "、"))（每天）")
        XCTAssertNil(world.journeyTrace(of: delta).summary(in: world, language: .english))
    }

    /// Decision 276: a line's trace is the busiest pairs of its stops,
    /// each from the earlier stop, with the trips the station panel's pairs
    /// give; a station off the line is not in it.
    func testALinesTraceIsTheBusiestPairsOfItsStops() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        let alpha = StationID(rawValue: 1), beta = StationID(rawValue: 2), gamma = StationID(rawValue: 3), delta = StationID(rawValue: 4)
        let main = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 3_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 3_000))
        try world.setStationDemand(delta, to: StationDemand(kind: .office, dailyTrips: 9_000))

        let trace = try XCTUnwrap(world.journeyTrace(ofLine: main))
        XCTAssertNil(trace.station)
        XCTAssertEqual(trace.line, main)
        XCTAssertFalse(trace.arcs.isEmpty)
        let order: [StationID] = [alpha, beta, gamma]
        for arc in trace.arcs {
            XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: arc.from)), try XCTUnwrap(order.firstIndex(of: arc.station)), "from the earlier stop")
            let pair = try XCTUnwrap(world.stationDemandPairs(of: arc.from).first { $0.station == arc.station })
            XCTAssertEqual([arc.outbound, arc.inbound], [pair.outbound, pair.inbound])
        }
        XCTAssertFalse(trace.arcs.contains { $0.station == delta || $0.from == delta }, "Delta is not on the line")
        XCTAssertEqual(trace.arcs.map(\.trips), trace.arcs.map(\.trips).sorted(by: >), "busiest first")
        let first = try XCTUnwrap(trace.arcs.first)
        let name = { (id: StationID) in world.station(id: id)!.name }
        XCTAssertTrue(trace.summary(in: world, language: .english)?.hasPrefix(
            "Busiest trips: \(name(first.from))–\(name(first.station)) \(Money(first.trips).displayText)"
        ) == true, trace.summary(in: world, language: .english) ?? "")
        XCTAssertNil(world.journeyTrace(ofLine: LineID(rawValue: 99)))
    }

    /// Decision 276: on the demo map, holding a line's track where no
    /// station is selects the line the map draws there (the lowest
    /// numbered where several share it); off the lines, nothing.
    @MainActor
    func testHoldingALinesTrackSelectsIt() throws {
        let world = DemoWorld.make(in: .english)
        let session = GameSession(world: world, language: .english)
        let map = LineMap(world: world)
        func middle(of stretch: LineMap.Stretch) -> PlanPoint? {
            world.trackGeometry(of: stretch.edge)?.location(at: (stretch.start + stretch.end) / 2).position.plan
        }
        // Track well away from any station, where a hold finds no station.
        let stretch = try XCTUnwrap(map.stretches.first { stretch in
            middle(of: stretch).map { world.station(near: $0, within: 2_048) == nil } ?? false
        })
        let point = try XCTUnwrap(middle(of: stretch))
        let on = map.stretches.filter { $0.edge == stretch.edge && $0.start <= (stretch.start + stretch.end) / 2 && (stretch.start + stretch.end) / 2 <= $0.end }
        let held = session.holdLine(at: point, reach: 64)
        XCTAssertEqual(held, on.map(\.line).min())
        XCTAssertEqual(session.selectedLineID, held)
        XCTAssertNotNil(session.world.journeyTrace(ofLine: try XCTUnwrap(held)))
        XCTAssertNil(session.lineHeld(at: PlanPoint(x: 1, y: 1), reach: 64), "no line in the corner")
    }

    /// On the demo map, with network routing: never more than five arcs,
    /// and they are the busiest of the station's pairs.
    func testTheDemoMapsTracesAreTheBusiestPairs() {
        let world = DemoWorld.make(in: .english)
        var traced = 0
        for station in world.stations {
            let trace = world.journeyTrace(of: station.id)
            let pairs = world.stationDemandPairs(of: station.id).filter { $0.outbound + $0.inbound > 0 }
            XCTAssertLessThanOrEqual(trace.arcs.count, JourneyTrace.limit)
            XCTAssertEqual(trace.arcs.count, min(pairs.count, JourneyTrace.limit), station.name)
            let fewest = trace.arcs.last?.trips ?? 0
            let left = pairs.filter { pair in !trace.arcs.contains { $0.station == pair.station } }
            XCTAssertTrue(left.allSatisfy { $0.outbound + $0.inbound <= fewest }, station.name)
            if !trace.arcs.isEmpty { traced += 1 }
        }
        XCTAssertGreaterThan(traced, 0)
        // The UI test holds Central and reads the trace from the map.
        let central = world.stations.first { $0.name == "Central" }
        XCTAssertFalse(central.map { world.journeyTrace(of: $0.id).arcs.isEmpty } ?? true, "Central has trips to trace")
    }
}
