import Foundation
@testable import GameCore
import XCTest

/// Town growth (item 5): a managed company's served stations grow each
/// midnight from yesterday's service and the stations their passengers
/// reach; unserved ones shrink back towards where they started.
final class TownGrowthTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)

    func testTheRate() {
        XCTAssertEqual(TownGrowth.growth(served: .max / 2, trips: 1_000, reached: 0), 10, "More than the trips is whole")
        XCTAssertEqual(TownGrowth.growth(served: 0, trips: 1_000, reached: 3), -2)
        XCTAssertEqual(TownGrowth.growth(served: 1_000, trips: 1_000, reached: 0), 10)
        XCTAssertEqual(TownGrowth.growth(served: 500, trips: 1_000, reached: 1), 6)
        XCTAssertEqual(TownGrowth.growth(served: 2_000, trips: 1_000, reached: 9), 15, "At most 1 % and five stations")
    }

    /// A and B on one line with a train, both with demand, managed.
    private func world(trips: Int64 = 1_000, train: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        try track.buildStation(named: "B", beside: 5, at: 1, in: &world)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        if train {
            let id = try world.purchaseTrain(named: "T").id
            try world.placeTrain(id, at: track.at(1, facingEast: true))
            try world.setTrainMovementRate(id, to: 1024)
            try world.assignTrain(id, to: line)
        }
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: trips))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: trips))
        world.setEconomyMode(.management)
        world.setTownGrowth(true)
        return world
    }

    func testServedStationsGrowAndUnservedOnesDoNot() throws {
        var world = try world()
        // The game starts at midnight, which only takes note of the stations.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.townGrowth(of: a)?.base, 1_000)
        XCTAssertEqual(world.townGrowth(of: a)?.lastGrowth, 0)
        XCTAssertEqual(world.stationDemand(of: a)?.dailyTrips, 1_000)
        try world.advance(ticks: 1_440)
        let grown = try XCTUnwrap(world.stationDemand(of: a)?.dailyTrips)
        XCTAssertGreaterThan(grown, 1_000, "A served day grows the town")
        XCTAssertLessThanOrEqual(grown, 1_015)
        XCTAssertEqual(world.townGrowth(of: a)?.lastGrowth, grown - 1_000)
        try world.advance(ticks: 1_440)
        let again = try XCTUnwrap(world.stationDemand(of: a)?.dailyTrips)
        XCTAssertGreaterThan(again, grown)
        XCTAssertLessThanOrEqual(again, grown + grown * 15 / 1_000 + 1)
        XCTAssertEqual(world.townGrowth(of: a)?.base, 1_000, "The start stays")

        // Without a train nothing is served: no growth, and never below the start.
        var idle = try self.world(train: false)
        try idle.advance(ticks: 1_440 * 4 + 1)
        XCTAssertEqual(idle.stationDemand(of: a)?.dailyTrips, 1_000)
        XCTAssertEqual(idle.townGrowth(of: a)?.lastGrowth, 0)
    }

    func testGrowthStopsAtFourTimesTheStart() throws {
        var world = try world(trips: 10)
        try world.advance(ticks: 1_441)
        for index in world.passengers.indices {
            world.passengers[index].demand = world.passengers[index].demand.map { StationDemand(kind: $0.kind, dailyTrips: 39) }
        }
        try world.advance(ticks: 1_440 * 3)
        XCTAssertEqual(world.stationDemand(of: a)?.dailyTrips, 40)
    }

    func testFreePlayAndWorldsWithoutGrowthStayAsSet() throws {
        var free = try world()
        free.setEconomyMode(.free)
        try free.advance(ticks: 1_440 * 3 + 1)
        XCTAssertEqual(free.stationDemand(of: a)?.dailyTrips, 1_000)
        XCTAssertNil(free.townGrowth(of: a))

        var off = try world()
        off.setTownGrowth(false)
        XCTAssertNil(off.townGrowth)
        let data = try JSONEncoder().encode(off)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("townGrowth"))
    }

    func testBatchesMatchMinuteStepsAndSavesContinue() throws {
        var batched = try world()
        try batched.advance(ticks: 1_440 * 2)
        var stepped = batched
        try batched.advance(ticks: 1_440 + 30)
        for _ in 0..<(1_440 + 30) { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        try loaded.advance(ticks: 1_440 * 2)
        try batched.advance(ticks: 1_440 * 2)
        XCTAssertEqual(loaded, batched)
        XCTAssertNil(loaded.townGrowthProblem())
        for station in batched.stations {
            let ledger = batched.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        }
    }

    /// A line closed at 23:00 leaves 23:59 quiet: a call that handles 23:59
    /// and goes on skips the idle minutes from midnight, which must still
    /// stop at midnight for the town to grow.
    func testAQuietMidnightIsNotSkipped() throws {
        var batched = try world()
        try batched.setLineServiceWindow(batched.lines[0].id, to: .hours(open: 360, close: 1_380))
        try batched.advance(ticks: 1_440 * 2 - 1)
        var stepped = batched
        try batched.advance(ticks: 1_440 + 2)
        for _ in 0..<(1_440 + 2) { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched.townGrowth, stepped.townGrowth)
        XCTAssertEqual(batched, stepped)
    }

    /// Demand set by the player is the new start: growth neither pulls it
    /// back up to the old start nor records growth out of range.
    func testSetDemandStartsGrowthAgain() throws {
        var world = try world()
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.townGrowth(of: a)?.base, 1_000)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100))
        XCTAssertNil(world.townGrowth(of: a))
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.townGrowth(of: a)?.base, 100)
        XCTAssertEqual(world.stationDemand(of: a)?.dailyTrips, 100)
        try world.advance(ticks: 1_440)
        XCTAssertLessThanOrEqual(try XCTUnwrap(world.stationDemand(of: a)?.dailyTrips), 102)
        XCTAssertNil(world.townGrowthProblem())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testBadGrowthIsRefused() throws {
        var world = try world()
        try world.advance(ticks: 1_441)
        let good = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: good), world)
        var broken = world
        broken.townGrowth!.places = broken.townGrowth!.places.reversed()
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(broken)))
        broken = world
        broken.townGrowth!.places = [TownGrowth.Place(station: StationID(rawValue: 99), base: 10, counted: 0)]
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(broken)))
    }
}
