import Foundation
@testable import GameCore
import XCTest

/// Weekly demand (item 4 of the author's order): the reference's weekday
/// factors scale each day's trips, and weekends follow its weekend hours.
final class WeeklyDemandTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)

    private func world(weekly: Bool = true, trips: Int64 = 1_000) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        try track.buildStation(named: "B", beside: 5, at: 1, in: &world)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: trips))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: trips))
        world.setWeeklyDemand(weekly)
        world.setSpeed(.normal)
        return world
    }

    func testTheReferenceWeekAndWeekendHours() {
        XCTAssertEqual(StationDemand.weekdayFactors.reduce(0, +), 7_000, "A week is seven days' trips")
        XCTAssertEqual((0..<7).map { StationDemand.weekday(ofDay: $0) }, [1, 2, 3, 4, 5, 6, 0], "Day 0 is a Monday")
        XCTAssertEqual(StationDemand.weekday(ofDay: -1), 0)
        XCTAssertEqual((0..<7).map { StationDemand.isWeekend(day: $0) }, [false, false, false, false, false, true, true])
        let demand = StationDemand(kind: .office, dailyTrips: 1_000)
        XCTAssertEqual((0..<7).map { demand.trips(onDay: $0) }, [1_040, 1_020, 1_020, 1_040, 1_120, 920, 840])
        XCTAssertEqual(StationDemand(kind: .office, dailyTrips: 1).trips(onDay: 6), 1, "0.84 rounds to 1")
        // The weekend shape is the weekday shape times the reference's
        // H_FACTOR_WE / H_FACTOR_WD, in thousandths of those factors.
        let weekday: [Int64] = [15, 8, 6, 5, 8, 40, 100, 180, 170, 100, 70, 70, 80, 70, 70, 80, 120, 170, 150, 110, 90, 70, 40, 20]
        let weekend: [Int64] = [10, 6, 5, 4, 6, 15, 30, 50, 70, 90, 110, 130, 130, 120, 120, 110, 110, 120, 120, 110, 90, 70, 50, 30]
        for hour in 0..<24 {
            let exact = 2 * StationDemand.dayShape[hour] * weekend[hour]
            XCTAssertEqual(StationDemand.weekendShape[hour], (exact / weekday[hour] + 1) / 2, "hour \(hour)")
        }
    }

    func testEachDayReleasesItsOwnTripsExactly() throws {
        var world = try world()
        let factors: [Int64] = [1_040, 1_020, 1_020, 1_040, 1_120, 920, 840]
        var released: Int64 = 0
        for day in 0..<7 {
            try world.advance(ticks: 1_440)
            released += factors[day]
            XCTAssertEqual(world.passengerLedger(of: a).released, released, "day \(day)")
        }
        XCTAssertEqual(released, 7_000, "A week releases a week's trips")
        // Without weekly demand every day is the same.
        var flat = try self.world(weekly: false)
        try flat.advance(ticks: 1_440 * 7)
        XCTAssertEqual(flat.passengerLedger(of: a).released, 7_000)
        XCTAssertNotEqual(flat.passengers, world.passengers, "The days differ")
    }

    func testWeekendsFollowTheWeekendHours() throws {
        var world = try world()
        try world.advance(ticks: 1_440 * 5)
        XCTAssertTrue(StationDemand.isWeekend(day: world.dayIndex(of: world.clock.now)))
        XCTAssertEqual(world.hourlyDemand(from: a, to: b), GameWorld.hourly(920, from: .residential, to: .office, weekend: true))
        XCTAssertEqual(world.dailyDemand(from: a, to: b), 920)
        // A weekday morning is busier than a Saturday morning.
        XCTAssertGreaterThan(GameWorld.hourly(1_000, from: .residential, to: .office)[7],
                             GameWorld.hourly(1_000, from: .residential, to: .office, weekend: true)[7])
    }

    func testBatchesMatchMinuteStepsAcrossMidnightAndTheWeekend() throws {
        var batched = try world(trips: 50_000)
        try batched.advance(ticks: 1_440 * 4 + 1_380)
        var stepped = batched
        try batched.advance(ticks: 180)
        for _ in 0..<180 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        XCTAssertTrue(loaded.weeklyDemand)
        var continued = loaded
        try continued.advance(ticks: 1_440)
        try batched.advance(ticks: 1_440)
        XCTAssertEqual(continued, batched)
    }

    func testSavesWithoutWeeklyDemandStayAsTheyWere() throws {
        let world = try world(weekly: false)
        let data = try JSONEncoder().encode(world)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("weeklyDemand"))
        XCTAssertFalse(try JSONDecoder().decode(GameWorld.self, from: data).weeklyDemand)
        XCTAssertFalse(GameWorld(bounds: try WorldBounds(width: 1_024, height: 1_024), economy: GameEconomy(balance: .zero)).weeklyDemand)
    }
}
