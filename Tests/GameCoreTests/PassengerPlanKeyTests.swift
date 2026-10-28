@testable import GameCore
import XCTest

/// The kept network release plan (`PassengerPlanKey`, ported from the T1
/// work onto Phase 5F's shared graph and route memo): a kept plan is always
/// the plan the world would work out afresh, and a large network does not
/// work it out again on every call of `advance(ticks:)`.
final class PassengerPlanKeyTests: XCTestCase {
    /// A grid of `columns × rows` stations, 64 m apart: a line along every
    /// row and every column, each station on one row line and one column
    /// line, so most pairs need a transfer.
    private static func grid(columns: Int, rows: Int, spacing: Int64 = 4_096) throws -> GameWorld {
        // From 07:00, when every kind of station sends passengers.
        var world = GameWorld(bounds: try WorldBounds(width: spacing * Int64(columns + 1), height: spacing * Int64(rows + 1)),
                              economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                              clock: GameClock(now: GameTime(minutes: 420)))
        var nodes: [[TrackNodeID]] = []
        for y in 0..<rows {
            nodes.append(try (0..<columns).map { x in
                try world.buildTrackNode(at: WorldCoordinate(x: spacing * Int64(x + 1), y: spacing * Int64(y + 1)))
            })
        }
        var east: [[TrackEdgeID]] = []
        var south: [[TrackEdgeID]] = []
        for y in 0..<rows {
            east.append(try (0..<(columns - 1)).map { try world.buildTrackEdge(from: nodes[y][$0], to: nodes[y][$0 + 1]) })
        }
        for x in 0..<columns {
            south.append(try (0..<(rows - 1)).map { try world.buildTrackEdge(from: nodes[$0][x], to: nodes[$0 + 1][x]) })
        }
        var stations: [[StationID]] = []
        for y in 0..<rows {
            stations.append(try (0..<columns).map { x in
                let id = try world.buildStation(named: "S\(x)-\(y)",
                    at: PlanPoint(x: spacing * Int64(x + 1), y: spacing * Int64(y + 1))).id
                if x + 1 < columns {
                    try world.addTrackPlatform(id, on: east[y][x], from: 0, to: 1_024)
                } else {
                    try world.addTrackPlatform(id, on: east[y][x - 1], from: spacing - 1_024, to: spacing)
                }
                if y + 1 < rows {
                    try world.addTrackPlatform(id, on: south[x][y], from: 0, to: 1_024)
                } else {
                    try world.addTrackPlatform(id, on: south[x][y - 1], from: spacing - 1_024, to: spacing)
                }
                return id
            })
        }
        var lines: [LineID] = []
        for y in 0..<rows {
            lines.append(try world.createLine(named: "Row \(y)", stops: stations[y]).id)
        }
        for x in 0..<columns {
            lines.append(try world.createLine(named: "Column \(x)", stops: stations.map { $0[x] }).id)
        }
        for line in lines {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 1, low: 1))
        }
        for (index, id) in stations.joined().enumerated() {
            let kinds: [StationDemandKind] = [.residential, .office, .shopping, .scenic]
            try world.setStationDemand(id, to: StationDemand(kind: kinds[index % kinds.count], dailyTrips: 5_000))
        }
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    private func assertSamePlan(_ kept: GameWorld.PassengerPlan?, _ fresh: GameWorld.PassengerPlan?, _ step: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(kept?.flows.map(\.origin), fresh?.flows.map(\.origin), step, file: file, line: line)
        XCTAssertEqual(kept?.flows.map(\.destination), fresh?.flows.map(\.destination), step, file: file, line: line)
        XCTAssertEqual(kept?.flows.map(\.record), fresh?.flows.map(\.record), step, file: file, line: line)
        XCTAssertEqual(kept?.flows.map(\.trip), fresh?.flows.map(\.trip), step, file: file, line: line)
        XCTAssertEqual(kept?.flows.map { $0.choices.map(\.journey) }, fresh?.flows.map { $0.choices.map(\.journey) },
                       step, file: file, line: line)
        XCTAssertEqual(kept?.flows.map { $0.choices.map(\.weight) }, fresh?.flows.map { $0.choices.map(\.weight) },
                       step, file: file, line: line)
        XCTAssertEqual(kept?.hourly, fresh?.hourly, step, file: file, line: line)
    }

    private func expectCurrent(_ world: GameWorld, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(world.passengerPlan.plan != nil, step, file: file, line: line)
        assertSamePlan(world.passengerPlan.plan.flatMap { $0 }, world.makePassengerPlan(), step, file: file, line: line)
    }

    /// 40 stations on 13 lines: the plan is worked out once, then kept for
    /// later calls while nothing it reads changes, and is the plan a fresh
    /// graph gives.
    func testAManyStationNetworkKeepsItsPlanBetweenCalls() throws {
        var world = try Self.grid(columns: 8, rows: 5)
        XCTAssertEqual(world.stations.count, 40)
        let clock = ContinuousClock()
        let first = try clock.measure { try world.advance(ticks: 1) }
        let flows = try XCTUnwrap(world.passengerPlan.plan.flatMap { $0 }).flows
        XCTAssertEqual(flows.count, 40 * 39, "every pair is reachable with at most one transfer")
        XCTAssertTrue(flows.contains { $0.choices.contains { $0.journey.legs.count == 2 } })
        let key = world.passengerPlan.key
        XCTAssertNotNil(key)

        // A plan worked out again would fill the route memo again.
        world.passengerRouteMemo = PassengerRouteMemo()
        var later = Duration.zero
        for _ in 0..<30 {
            later += try clock.measure { try world.advance(ticks: 1) }
        }
        XCTAssertNil(world.passengerRouteMemo.graph, "the plan was kept, not worked out again")
        XCTAssertEqual(world.passengerPlan.key, key, "the same plan throughout")
        expectCurrent(world, "30 calls later")
        XCTAssertLessThan(later, first, "30 calls that keep the plan cost less than working it out once")
        XCTAssertGreaterThan(world.passengers.reduce(Int64(0)) { $0 + $1.released }, 0)
    }

    /// Every change the plan reads forgets it or changes its key.
    func testTheKeptNetworkPlanFollowsEveryChange() throws {
        var world = try Self.grid(columns: 4, rows: 3)
        try world.advance(ticks: 1)
        expectCurrent(world, "first")

        try world.setStationDemand(StationID(rawValue: 2), to: StationDemand(kind: .office, dailyTrips: 9_000))
        try world.advance(ticks: 1)
        expectCurrent(world, "demand")

        try world.setLineTrainsInService(LineID(rawValue: 1), to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.advance(ticks: 1)
        expectCurrent(world, "trains in service")

        let row = world.lines[0].stops
        try world.setLineStops(LineID(rawValue: 1), to: Array(row.prefix(3)))
        try world.advance(ticks: 1)
        expectCurrent(world, "stops")

        try world.setLineServiceWindow(LineID(rawValue: 2), to: .hours(open: 60, close: 1_440))
        try world.advance(ticks: 1)
        expectCurrent(world, "window")

        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        expectCurrent(world, "traffic control")

        world.setEconomyMode(.management)
        try world.setFareRules(FareRules.standard)
        try world.advance(ticks: 1)
        expectCurrent(world, "fares")

        try world.setStationOperationMode(world.stations[1].id, to: .flowControl)
        try world.advance(ticks: 1)
        expectCurrent(world, "operation mode")

        // Decision 137: demand by distance and the outside connections.
        world.setDistanceDemand(true)
        try world.advance(ticks: 1)
        expectCurrent(world, "distance demand")
        world.setOutsideConnections(true)
        try world.advance(ticks: 1)
        expectCurrent(world, "outside connections")

        // A day of service levels, one call a minute: each call's kept plan
        // is the current level's.
        for minute in 0..<(24 * 60) {
            try world.advance(ticks: 1)
            if minute % 60 == 0 { expectCurrent(world, "minute \(minute)") }
        }
        expectCurrent(world, "a day later")
    }

    /// A line sending a train out changes when it last sent one, which no
    /// plan reads: the plan is kept, not worked out again after every
    /// departure, and is the plan a fresh graph gives; batches, single
    /// minutes and a world without a kept plan still give the same world.
    func testATrainSentOutKeepsThePlan() throws {
        var world = try Self.grid(columns: 4, rows: 3)
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 1_024))
        try world.setTrainContinuation(train, along: [], stoppingAt: 1_024)
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: LineID(rawValue: 1))
        var kept = world, stepped = world, fresh = world

        try world.advance(ticks: 1)
        XCTAssertNotNil(world.line(id: LineID(rawValue: 1))?.lastDispatch, "the line sent its train out")
        world.passengerRouteMemo = PassengerRouteMemo()
        try world.advance(ticks: 1)
        XCTAssertNil(world.passengerRouteMemo.graph, "the plan was kept, not worked out again")
        expectCurrent(world, "after a departure")

        try kept.advance(ticks: 90)
        for _ in 0..<90 {
            try stepped.advance(ticks: 1)
            fresh.passengerPlan = GameWorld.PassengerPlanCache()
            fresh.passengerRouteMemo = PassengerRouteMemo()
            try fresh.advance(ticks: 1)
        }
        XCTAssertGreaterThan(stepped.passengerLedger(of: StationID(rawValue: 1)).arrived + stepped.riderCount(of: train), 0, "the train carried passengers")
        XCTAssertEqual(stepped, fresh)
        XCTAssertEqual(stepped.passengers, fresh.passengers)
        XCTAssertEqual(kept, stepped)
        XCTAssertEqual(kept.riders, stepped.riders)
    }

    /// Batches, single minutes and a world without a kept plan give the
    /// same world: the plan is not game state.
    func testKeptAndFreshPlansGiveTheSameWorld() throws {
        var kept = try Self.grid(columns: 4, rows: 3)
        var stepped = kept
        var fresh = kept
        try kept.advance(ticks: 90)
        for _ in 0..<90 {
            try stepped.advance(ticks: 1)
            fresh.passengerPlan = GameWorld.PassengerPlanCache()
            fresh.passengerRouteMemo = PassengerRouteMemo()
            try fresh.advance(ticks: 1)
        }
        XCTAssertEqual(stepped, fresh)
        XCTAssertEqual(stepped.passengers, fresh.passengers)
        XCTAssertEqual(kept, stepped)
        XCTAssertEqual(kept.passengers, stepped.passengers)
        XCTAssertEqual(kept.riders, stepped.riders)
    }

    /// 派工單 BK: a plan worked out at night, when no line runs, has a graph
    /// of its own; going back to the day's graph keeps the day's routes
    /// instead of working each one out again (92.1: 14 s at every 06:00).
    func testTheNightsEmptyGraphKeepsTheDaysRoutes() throws {
        var world = try Self.grid(columns: 4, rows: 3)
        try world.advance(ticks: 1)
        let day = PassengerRouteGraph(world: world)
        XCTAssertFalse(day.paths.isEmpty)
        let pair = PassengerRouteMemo.Pair(origin: world.stations[0].id, destination: world.stations[11].id)
        let choices = world.passengerRouteChoices(from: pair.origin, to: pair.destination, graph: day)
        XCTAssertFalse(choices.isEmpty)
        var memo = PassengerRouteMemo()
        memo.use(day)
        memo[pair] = choices
        memo.use(PassengerRouteGraph(paths: []))
        XCTAssertNil(memo[pair], "the night's graph has routes of its own")
        memo.use(day)
        XCTAssertEqual(memo[pair], choices, "the day's routes are kept through the night")
        XCTAssertEqual(memo.graph, day)
        // Kept for the graphs before it; more drop the day's.
        for _ in 0..<PassengerRouteMemo.generations {
            memo.use(PassengerRouteGraph(paths: []))
            memo.use(PassengerRouteGraph(paths: Array(day.paths.prefix(1))))
        }
        memo.use(day)
        XCTAssertNil(memo[pair])
    }

    /// Decision 470: the routes from a station depend only on the part of
    /// the graph it is joined to, and not on the trains' daily capacity, so
    /// a change elsewhere or to the capacity keeps them.
    func testAChangeElsewhereKeepsAPartsRoutes() throws {
        let ids = (1...6).map { StationID(rawValue: $0) }
        func path(_ line: Int, _ stations: ArraySlice<StationID>, headway: Int64 = 600, capacity: Int64 = 0) -> PassengerRouteGraph.ServicePath {
            PassengerRouteGraph.ServicePath(line: LineID(rawValue: line), pattern: nil, direction: .outbound,
                                            stations: Array(stations), runSeconds: Array(repeating: 120, count: stations.count - 1),
                                            headway: headway, isRing: false, dailyCapacity: capacity)
        }
        let north = path(1, ids[0..<3]), south = path(2, ids[3..<6])
        let graph = PassengerRouteGraph(paths: [north, south])
        XCTAssertEqual(PassengerRouteMemo.components(of: graph).parts.count, 2)
        let up = PassengerRouteMemo.Pair(origin: ids[0], destination: ids[2])
        let down = PassengerRouteMemo.Pair(origin: ids[3], destination: ids[5])
        let found = [PassengerRouteChoice(route: PassengerRoute(legs: [], rideMinutes: 4, waitMinutes: 5, transferSeconds: 0, walkSeconds: 0), weight: 1)]
        var memo = PassengerRouteMemo()
        memo.use(graph)
        memo[up] = found
        memo[down] = found
        memo.use(PassengerRouteGraph(paths: [north, path(2, ids[3..<6], headway: 300)]))
        XCTAssertNotNil(memo[up], "the north line's part is unchanged")
        XCTAssertNil(memo[down], "the south line's headway changed")
        memo.use(PassengerRouteGraph(paths: [path(1, ids[0..<3], capacity: 9_000), south]))
        XCTAssertNotNil(memo[up], "a daily capacity is not read by a search")
        XCTAssertNotNil(memo[down], "the first graph's south part is kept")
        // Joined into one part, both are worked out again.
        memo.use(PassengerRouteGraph(paths: [north, south, path(3, ids[2..<4])]))
        XCTAssertNil(memo[up])
        XCTAssertNil(memo[down])
        // Another memo's routes are taken in for the parts it worked out.
        var other = PassengerRouteMemo()
        other.use(graph)
        other[up] = found
        var taker = PassengerRouteMemo()
        taker.use(graph)
        taker.absorb(other)
        XCTAssertEqual(taker[up], other[up])
        XCTAssertNil(taker[down])
    }

    /// Decision 470: a world whose routes are kept part by part through
    /// edits to one of two separate networks is the world whose routes are
    /// worked out afresh at every tick.
    func testRoutesKeptThroughEditsElsewhereGiveTheSameWorld() throws {
        // 640 m apart: too far to walk between the rows.
        var kept = try Self.grid(columns: 4, rows: 3, spacing: 40_960)
        // Only the rows run: three networks apart.
        for line in kept.lines where line.name.hasPrefix("Column") {
            try kept.removeLine(line.id)
        }
        let rows = kept.lines.map(\.id)
        XCTAssertEqual(rows.count, 3)
        var fresh = kept
        var reused = 0
        let stations = kept.lines.map { $0.stops }
        var changed = 0
        for tick in 0..<120 {
            if tick % 20 == 10 {
                // An edit to one row's trains changes its headways.
                let before = PassengerRouteMemo.components(of: PassengerRouteGraph(world: kept)).parts
                let trains = TrainsInService(peak: 1 + tick / 20 % 2, offPeak: 1 + tick / 20 % 2, low: 1)
                try kept.setLineTrainsInService(rows[tick / 20 % 3], to: trains)
                try fresh.setLineTrainsInService(rows[tick / 20 % 3], to: trains)
                let after = PassengerRouteMemo.components(of: PassengerRouteGraph(world: kept)).parts
                XCTAssertEqual(after.count, 3)
                changed += zip(before, after).filter { $0 != $1 }.count
            }
            try kept.advance(ticks: 1)
            if tick % 20 == 10 {
                // The rows not edited kept their routes.
                let other = stations[(tick / 20 + 1) % 3]
                if kept.passengerRouteMemo[PassengerRouteMemo.Pair(origin: other[0], destination: other[3])] != nil { reused += 1 }
            }
            fresh.passengerPlan = GameWorld.PassengerPlanCache()
            fresh.passengerRouteMemo = PassengerRouteMemo()
            try fresh.advance(ticks: 1)
        }
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(PassengerRouteMemo.components(of: PassengerRouteGraph(world: kept)).parts.count, 3)
        XCTAssertEqual(reused, 6)
        XCTAssertGreaterThan(kept.passengers.reduce(Int64(0)) { $0 + $1.released }, 0)
        XCTAssertEqual(kept, fresh)
        XCTAssertEqual(kept.passengers, fresh.passengers)
        XCTAssertEqual(kept.riders, fresh.riders)
    }

    /// Decision 470: the routes of the plan a tick works out when it
    /// crosses 06:00, worked out before the tick on the graph of that
    /// minute, give the same world, and the tick works out none itself.
    func testRoutesWorkedOutAheadOfTheMorningGiveTheSameWorld() throws {
        var world = try Self.grid(columns: 4, rows: 3)
        for line in world.lines {
            try world.setLineServiceWindow(line.id, to: .standard)
        }
        // Three seconds off the minutes, as 92.1's game was: the ticks
        // after cross each whole minute partway.
        world.setSpeed(.x10)
        try world.advance(ticks: 3)
        world.setSpeed(.fast)
        var found: PassengerRoutesToWorkOut?
        for _ in 0..<(2 * 144) {
            // The day's routes are kept through the night: none to work out.
            world.passengerRouteMemo = PassengerRouteMemo()
            if let work = world.passengerRoutesToWorkOut(), work.time.seconds > world.clock.now.seconds {
                found = work
                break
            }
            try world.advance(ticks: 1)
        }
        let work = try XCTUnwrap(found, "a tick that crosses the morning")
        XCTAssertEqual(work.time.seconds % GameTime.secondsPerDay % GameTime.secondsPerHour, 0)
        var given = world
        given.takePassengerRoutes(world.workingOutPassengerRoutes(work))
        let pairs = given.passengerRouteCache.pairs
        try world.advance(ticks: 1)
        try given.advance(ticks: 1)
        XCTAssertEqual(given, world)
        XCTAssertEqual(given.passengers, world.passengers)
        XCTAssertEqual(given.riders, world.riders)
        XCTAssertEqual(given.passengerRouteCache.pairs, pairs, "the tick worked out no route itself")
        XCTAssertGreaterThan(pairs, 0)
        XCTAssertEqual(world.passengerRouteCache.pairs, pairs, "the plain tick worked out the same routes")
    }

    /// The same world, its routes kept through nights or worked out afresh
    /// at every call, across two days of lines that stop at midnight.
    func testRoutesKeptThroughTheNightGiveTheSameWorld() throws {
        var kept = try Self.grid(columns: 4, rows: 3)
        for line in kept.lines {
            try kept.setLineServiceWindow(line.id, to: .standard)
        }
        kept.setSpeed(.fast)
        var fresh = kept
        for _ in 0..<(2 * 144) {
            try kept.advance(ticks: 1)
            fresh.passengerPlan = GameWorld.PassengerPlanCache()
            fresh.passengerRouteMemo = PassengerRouteMemo()
            try fresh.advance(ticks: 1)
        }
        XCTAssertGreaterThan(kept.passengers.reduce(Int64(0)) { $0 + $1.released }, 0)
        XCTAssertEqual(kept, fresh)
        XCTAssertEqual(kept.passengers, fresh.passengers)
        XCTAssertEqual(kept.riders, fresh.riders)
    }
}
