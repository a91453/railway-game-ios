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
    private static func grid(columns: Int, rows: Int) throws -> GameWorld {
        let spacing: Int64 = 4_096
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

        // A day of service levels, one call a minute: each call's kept plan
        // is the current level's.
        for minute in 0..<(24 * 60) {
            try world.advance(ticks: 1)
            if minute % 60 == 0 { expectCurrent(world, "minute \(minute)") }
        }
        expectCurrent(world, "a day later")
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
}
