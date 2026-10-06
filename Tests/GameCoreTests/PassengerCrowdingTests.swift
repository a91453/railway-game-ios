@testable import GameCore
import XCTest

/// Phase 5F: crowding in network route choice and the generalized cost's
/// effect on demand (`PassengerCrowding`). Native rules: the reference has
/// none to port (see the file's header).
final class PassengerCrowdingTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let c = StationID(rawValue: 2)

    func testDemandKeepsItsTripsUpToHalfAnHourAndFallsBeyond() {
        XCTAssertEqual(PassengerCrowding.decayed(1_000, minutes: 1), 1_000)
        XCTAssertEqual(PassengerCrowding.decayed(1_000, minutes: 30), 1_000)
        XCTAssertEqual(PassengerCrowding.decayed(1_000, minutes: 60), 500)
        XCTAssertEqual(PassengerCrowding.decayed(1_000, minutes: 31), 967, "1000 × 967‰")
        XCTAssertEqual(PassengerCrowding.decayed(3, minutes: 45), 2, "3 × 666‰ = 1.998, rounded half up")
        XCTAssertEqual(PassengerCrowding.decayed(1, minutes: 90), 0)
        XCTAssertEqual(PassengerCrowding.decayed(0, minutes: 90), 0)
    }

    func testCrowdingFollowsTheBureauOfPublicRoadsCurve() {
        XCTAssertEqual(PassengerCrowding.crowdingSeconds(600, load: 0), 0)
        XCTAssertEqual(PassengerCrowding.crowdingSeconds(600, load: 500), 5, "600 × 0.15 × 0.5⁴ = 5.6")
        XCTAssertEqual(PassengerCrowding.crowdingSeconds(600, load: 1_000), 90)
        XCTAssertEqual(PassengerCrowding.crowdingSeconds(600, load: 2_000), 1_440)
        XCTAssertEqual(PassengerCrowding.crowdingSeconds(600, load: 9_000), 1_440, "the ratio is capped at 2")
    }

    /// Two lines A–C with the same headway: the one with one-car trains
    /// fills, so the plan gives it the smaller share.
    private func world(smallCars: Int, bigCars: Int) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 10_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        try track.buildStation(named: "C", beside: 5, at: 1, in: &world)
        for (name, cars) in [("Small", smallCars), ("Big", bigCars)] {
            let line = try world.createLine(named: name, stops: [a, c]).id
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTargetHeadways(line, to: TargetHeadways(peak: 10, offPeak: 10, low: 10))
            let train = try world.purchaseTrain(named: name).id
            try world.setTrainCars(train, to: cars)
            try world.assignTrain(train, to: line)
        }
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: StationDemand.maximumDailyTrips))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: StationDemand.maximumDailyTrips))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    private func weights(_ world: inout GameWorld) throws -> [LineID: Int64] {
        try world.advance(ticks: 1)
        let plan = try XCTUnwrap(world.passengerPlan.plan.flatMap { $0 })
        let flow = try XCTUnwrap(plan.flows.first { $0.origin == a && $0.destination == c })
        return Dictionary(uniqueKeysWithValues: flow.choices.map { ($0.journey.leg.line, $0.weight) })
    }

    func testAFullerLineGetsASmallerShare() throws {
        var even = try world(smallCars: 8, bigCars: 8)
        let same = try weights(&even)
        XCTAssertEqual(same.count, 2)
        XCTAssertEqual(same[LineID(rawValue: 1)], same[LineID(rawValue: 2)])

        var uneven = try world(smallCars: 1, bigCars: 8)
        let split = try weights(&uneven)
        XCTAssertLessThan(try XCTUnwrap(split[LineID(rawValue: 1)]), try XCTUnwrap(split[LineID(rawValue: 2)]))
        let fresh = try XCTUnwrap(uneven.makePassengerPlan())
        XCTAssertEqual(fresh.flows.map { $0.choices.map(\.weight) },
                       uneven.passengerPlan.plan.flatMap { $0 }?.flows.map { $0.choices.map(\.weight) })
    }

    func testDailyDemandAgreesWithThePlanAndFallsWithTime() throws {
        var world = try world(smallCars: 8, bigCars: 8)
        let daily = world.dailyDemand(from: a, to: c)
        XCTAssertGreaterThan(daily, 0)
        try world.advance(ticks: 1)
        let plan = try XCTUnwrap(world.passengerPlan.plan.flatMap { $0 })
        let index = try XCTUnwrap(plan.flows.firstIndex { $0.origin == a && $0.destination == c })
        XCTAssertEqual(plan.hourly[(24 * index)..<(24 * index + 24)].reduce(0, +), world.dailyDemand(from: a, to: c))

        // The same pair in direct mode keeps the day's trips whatever the
        // time: the decay is network routing's.
        var direct = world
        direct.setPassengerRoutingMode(.direct)
        XCTAssertEqual(direct.dailyDemand(from: a, to: c), StationDemand.maximumDailyTrips)
        let minutes = try XCTUnwrap(world.passengerRoutes(from: a, to: c).map(\.totalMinutes).min())
        XCTAssertEqual(world.dailyDemand(from: a, to: c),
                       PassengerCrowding.decayed(StationDemand.maximumDailyTrips, minutes: minutes))
    }

    func testCrowdedPlansMatchAcrossBatchesAndSaves() throws {
        var batched = try world(smallCars: 1, bigCars: 8)
        var stepped = batched
        try batched.advance(ticks: 40)
        for _ in 0..<40 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
    }
}
