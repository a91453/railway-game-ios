@testable import GameCore
import XCTest

final class PassengerRoutesTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let d = StationID(rawValue: 4)

    private func network() throws -> GameWorld {
        var world = try makeWorld(width: 20_480, height: 20_480)
        let track = TestLine(tiles: 12)
        try track.build(in: &world)
        for (index, x) in [1, 4, 7, 10].enumerated() {
            try track.buildStation(named: "S\(index)", beside: x, at: 1, in: &world)
        }
        return world
    }

    private func run(_ world: inout GameWorld, _ line: LineID, headway: Int64? = nil) throws {
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        if let headway {
            try world.setLineTargetHeadways(line, to: TargetHeadways(peak: headway, offPeak: headway, low: headway))
        }
    }

    func testTwoLinesJoinAtAStationAndTheServiceGraphChangesImmediately() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        try run(&world, first)
        try run(&world, second)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].legs.map(\.line), [first, second])
        XCTAssertEqual(routes[0].legs.map(\.from), [a, b])
        XCTAssertEqual(routes[0].legs.map(\.to), [b, c])
        XCTAssertEqual(routes[0].transfers, 1)
        XCTAssertEqual(routes[0].transferMinutes, 4)
        XCTAssertEqual(routes[0].legs[0].rideSeconds, try XCTUnwrap(world.lineJourney(first)).legs[0].seconds)
        XCTAssertEqual(routes[0].totalMinutes,
                       routes[0].rideMinutes + routes[0].waitMinutes + routes[0].transferMinutes)
        XCTAssertNil(world.passengerTrip(from: a, to: c))

        try world.setLineTrainsInService(second, to: .none)
        XCTAssertEqual(world.passengerRoutes(from: a, to: c), [])
        try run(&world, second)
        XCTAssertEqual(world.passengerRoutes(from: c, to: a).first?.legs.map(\.line), [second, first])
        try world.setLineServiceWindow(second, to: .standard)
        XCTAssertEqual(world.passengerRoutes(from: a, to: c), [])
        XCTAssertEqual(world.passengerRoutes(from: a, to: d), [])
    }

    func testBrokenPhysicalRouteIsNotPassengerService() throws {
        var world = try network()
        let line = try world.createLine(named: "Broken", stops: [a, b]).id
        try run(&world, line)
        XCTAssertNotNil(world.lineJourney(line))
        XCTAssertNotNil(world.passengerRoutes(from: a, to: b).first)
        try world.removeTrackEdge(.edge(3))
        XCTAssertNil(world.lineJourney(line))
        XCTAssertNil(world.lineHeadway(line, at: .peak))
        XCTAssertEqual(world.passengerRoutes(from: a, to: b), [])
    }

    func testJourneySecondsAreAccumulatedBeforeMinuteRounding() throws {
        var world = try network()
        let line = try world.createLine(named: "Through", stops: [a, b, c]).id
        try run(&world, line)
        let journey = try XCTUnwrap(world.lineJourney(line))
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        let seconds = journey.legs[0].seconds + 60 + journey.legs[1].seconds
        let headway = try XCTUnwrap(world.lineHeadway(line, at: .peak))
        XCTAssertEqual(route.legs[0].rideSeconds, seconds)
        XCTAssertEqual(route.rideMinutes, (seconds + 59) / 60)
        XCTAssertLessThan(route.rideMinutes,
                          (journey.legs[0].seconds + 59) / 60 + 1 + (journey.legs[1].seconds + 59) / 60)
        XCTAssertEqual(route.waitMinutes, (headway + 1) / 2)
        XCTAssertEqual(route.legs[0].pattern, nil)
        XCTAssertEqual(world.passengerRoutes(from: b, to: c).first?.legs[0].rideSeconds,
                       journey.legs[1].seconds, "boarding at B does not include B's dwell twice")
    }

    func testRunningPatternAloneAndExpressAlongsideTheMain() throws {
        var world = try network()
        let line = try world.createLine(named: "Shared", stops: [a, b, c, d]).id
        try world.setLineServiceWindow(line, to: .allDay)
        let short = try world.addLinePattern(line, calling: [1, 2])
        let express = try world.addLinePattern(line, calling: [0, 3])
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2), pattern: short)
        XCTAssertNil(world.lineHeadway(line, at: .peak))
        XCTAssertEqual(world.passengerRoutes(from: b, to: c).first?.legs.first?.pattern, short)
        XCTAssertEqual(world.passengerRoutes(from: a, to: d), [])

        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2), pattern: express)
        let expressRoute = try XCTUnwrap(world.passengerRoutes(from: a, to: d).first)
        XCTAssertEqual(expressRoute.legs.map(\.pattern), [express])
        XCTAssertEqual(expressRoute.legs[0].rideSeconds, try XCTUnwrap(world.lineJourney(line, pattern: express)).legs[0].seconds)

        try world.setLineTrainsInService(line, to: .none, pattern: short)
        try world.setLineTargetHeadways(line, to: TargetHeadways(peak: 30, offPeak: 30, low: 30))
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        let routes = world.passengerRoutes(from: a, to: d)
        XCTAssertNotNil(world.lineHeadway(line, at: .peak, pattern: express))
        XCTAssertTrue(routes.contains { $0.legs.map(\.pattern) == [express] })
        XCTAssertTrue(routes.contains { $0.legs.map(\.pattern) == [nil] })
        assertGraphMatchesServiceQueries(world)
    }

    /// The route graph drives each service once; its headways and running
    /// times must be what `lineHeadway` and `lineJourney` give.
    private func assertGraphMatchesServiceQueries(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        let graph = PassengerRouteGraph(world: world)
        var count = 0
        for serviceLine in world.lines {
            guard let level = world.serviceLevel(of: serviceLine.id, at: world.clock.now) else { continue }
            for service in 0..<serviceLine.serviceCount {
                let pattern = service == 0 ? nil : service - 1
                guard let headway = world.lineHeadway(serviceLine.id, at: level, pattern: pattern),
                      let journey = world.lineJourney(serviceLine.id, pattern: pattern) else { continue }
                let paths = graph.paths.filter { $0.line == serviceLine.id && $0.pattern == pattern }
                XCTAssertEqual(paths.count, 2, file: file, line: line)
                XCTAssertEqual(paths.map(\.headway), [headway, headway], file: file, line: line)
                XCTAssertEqual(paths.flatMap(\.runSeconds), journey.legs.map(\.seconds), file: file, line: line)
                count += 2
            }
        }
        XCTAssertEqual(graph.paths.count, count, file: file, line: line)
    }

    func testCapacityLimitedHeadwayChangesWaitingTime() throws {
        var (world, line) = try SingleTrackCapacityTests.short()
        try world.setLineServiceWindow(line, to: .allDay)
        let west = StationID(rawValue: 1)
        let east = StationID(rawValue: 2)
        let before = try XCTUnwrap(world.passengerRoutes(from: west, to: east).first)
        XCTAssertEqual(before.waitMinutes, (try XCTUnwrap(world.lineHeadway(line, at: .peak)) + 1) / 2)
        try world.setTrafficControl(true)
        let after = try XCTUnwrap(world.passengerRoutes(from: west, to: east).first)
        XCTAssertEqual(after.waitMinutes, (try XCTUnwrap(world.lineHeadway(line, at: .peak)) + 1) / 2)
        XCTAssertGreaterThan(after.waitMinutes, before.waitMinutes)
    }

    func testPhysicalRoutePreferenceChangesPassengerTime() throws {
        var (world, _, line, _) = try LineRoutePreferenceTests.setup(traffic: false)
        let before = try XCTUnwrap(world.passengerRoutes(from: SingleTrackMeet.west, to: SingleTrackMeet.middle).first)
        let oldSeconds = try XCTUnwrap(world.lineJourney(line)).legs[0].seconds
        XCTAssertEqual(before.legs[0].rideSeconds, oldSeconds)

        try world.setLineRoutePreferences(line, to: [LineRoutePreferenceTests.loop(world)])
        let after = try XCTUnwrap(world.passengerRoutes(from: SingleTrackMeet.west, to: SingleTrackMeet.middle).first)
        let newSeconds = try XCTUnwrap(world.lineJourney(line)).legs[0].seconds
        XCTAssertGreaterThan(newSeconds, oldSeconds)
        XCTAssertEqual(after.legs[0].rideSeconds, newSeconds)
    }

    func testWaitCanMakeATransferQuickerThanADirectTrain() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        let direct = try world.createLine(named: "Direct", stops: [a, c]).id
        try run(&world, first)
        try run(&world, second)
        try run(&world, direct, headway: 60)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertEqual(routes.first?.legs.map(\.line), [first, second])
        XCTAssertTrue(routes.contains { $0.legs.map(\.line) == [direct] })
        XCTAssertEqual(routes.map(\.totalMinutes), routes.map(\.totalMinutes).sorted())
        XCTAssertEqual(world.passengerRoutes(from: a, to: c, limit: 1).count, 1)
        XCTAssertEqual(world.passengerRoutes(from: a, to: a), [])
    }

    func testEqualDirectServicesUseLineOrder() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b, c]).id
        let second = try world.createLine(named: "Second", stops: [a, b, c]).id
        try run(&world, first)
        try run(&world, second)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertEqual(routes.prefix(2).map { $0.legs.map(\.line) }, [[first], [second]])
        XCTAssertEqual(routes[0].totalMinutes, routes[1].totalMinutes)
        XCTAssertEqual(routes[0].legs[0].from, a)
        XCTAssertEqual(routes[0].legs[0].to, c)
    }

    func testBoardingStateCanBeatAnEarlierOnboardArrival() throws {
        // At C, staying on the local reaches the stop at 160 seconds but
        // pays another 60-second dwell. Express then local reaches its
        // boarding state at 190 seconds and leaves without that dwell.
        let local = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 1), pattern: nil,
            direction: .outbound, stations: [a, b, c, d], runSeconds: [20, 20, 20], headway: 2, isRing: false)
        let express = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 1), pattern: 0,
            direction: .outbound, stations: [a, c], runSeconds: [70], headway: 2, isRing: false)
        let graph = PassengerRouteGraph(paths: [local, express])

        let route = try XCTUnwrap(graph.shortest(from: a, to: d, banning: [])?.0)
        XCTAssertEqual(route.legs.map(\.pattern), [0, nil])
        XCTAssertEqual(route.legs.map(\.rideSeconds), [70, 20])
        XCTAssertEqual(route.waitMinutes, 2)
        XCTAssertEqual(route.totalMinutes, 4)
    }

    func testWholeMinuteTiePrefersFewerTransfersBeforeRawSeconds() throws {
        let first = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 1), pattern: nil,
            direction: .outbound, stations: [a, b], runSeconds: [1], headway: 2, isRing: false)
        let second = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 2), pattern: nil,
            direction: .outbound, stations: [b, c], runSeconds: [1], headway: 2, isRing: false)
        let direct = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 3), pattern: nil,
            direction: .outbound, stations: [a, c], runSeconds: [350], headway: 2, isRing: false)
        let graph = PassengerRouteGraph(paths: [first, second, direct])

        let route = try XCTUnwrap(graph.shortest(from: a, to: c, banning: [])?.0)
        XCTAssertEqual(route.legs.map(\.line), [LineID(rawValue: 3)])
        XCTAssertEqual(route.totalMinutes, 7)
        XCTAssertEqual(route.transfers, 0)
    }

    func testExactTieUsesWholeRouteOrderNotDestinationServiceOrder() throws {
        // Both paths take the same whole minutes, transfers and raw seconds.
        // Service insertion order favors 2 -> 3 at the destination, while
        // the public route ordering must prefer the lower first line: 1 -> 4.
        let two = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 2), pattern: nil,
            direction: .outbound, stations: [a, c], runSeconds: [10], headway: 2, isRing: false)
        let three = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 3), pattern: nil,
            direction: .outbound, stations: [c, d], runSeconds: [10], headway: 2, isRing: false)
        let one = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 1), pattern: nil,
            direction: .outbound, stations: [a, b], runSeconds: [10], headway: 2, isRing: false)
        let four = PassengerRouteGraph.ServicePath(line: LineID(rawValue: 4), pattern: nil,
            direction: .outbound, stations: [b, d], runSeconds: [10], headway: 2, isRing: false)
        let graph = PassengerRouteGraph(paths: [two, three, one, four])

        let route = try XCTUnwrap(graph.shortest(from: a, to: d, banning: [])?.0)
        XCTAssertEqual(route.legs.map(\.line), [LineID(rawValue: 1), LineID(rawValue: 4)])
        XCTAssertEqual(route.totalMinutes, 7)
        XCTAssertEqual(route.transfers, 1)
    }

    func testRouteAllocationUsesLargestRemaindersAndRouteOrderForTies() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, c]).id
        let second = try world.createLine(named: "Second", stops: [a, c]).id
        try run(&world, first)
        try run(&world, second)

        let allocations = world.passengerRouteAllocations(from: a, to: c, count: 5)
        XCTAssertEqual(allocations.prefix(2).map { $0.route.legs[0].line }, [first, second])
        XCTAssertEqual(allocations.prefix(2).map(\.count), [3, 2])
        XCTAssertEqual(allocations.map(\.count).reduce(0, +), 5)
        XCTAssertEqual(world.passengerRouteAllocations(from: a, to: c, count: 0), [])
        XCTAssertEqual(world.passengerRouteAllocations(from: a, to: a, count: 5), [])

        try world.setLineTargetHeadways(second, to: TargetHeadways(peak: 8, offPeak: 8, low: 8))
        let weighted = world.passengerRouteAllocations(from: a, to: c, count: 101)
        XCTAssertEqual(weighted.map(\.count).reduce(0, +), 101)
        XCTAssertGreaterThan(weighted[1].route.totalMinutes, weighted[0].route.totalMinutes)
        XCTAssertGreaterThan(weighted[0].count, weighted[1].count)
        XCTAssertEqual(weighted, world.passengerRouteAllocations(from: a, to: c, count: 101))
    }

    func testRouteAllocationExcludesExcessivelySlowService() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        let slow = try world.createLine(named: "Slow", stops: [a, c]).id
        try run(&world, first)
        try run(&world, second)
        try run(&world, slow, headway: 60)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertTrue(routes.contains { $0.legs.map(\.line) == [slow] })
        let allocations = world.passengerRouteAllocations(from: a, to: c, count: 101)
        XCTAssertFalse(allocations.contains { $0.route.legs.map(\.line) == [slow] })
        XCTAssertEqual(allocations.map(\.count).reduce(0, +), 101)
        XCTAssertTrue(allocations.allSatisfy { $0.count >= 0 })

        try world.setLineTrainsInService(second, to: .none)
        let changed = world.passengerRouteAllocations(from: a, to: c, count: 101)
        XCTAssertEqual(changed.map(\.count).reduce(0, +), 101)
        XCTAssertEqual(changed.first?.route.legs.map(\.line), [slow])
    }
}
