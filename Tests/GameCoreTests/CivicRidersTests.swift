import Foundation
@testable import GameCore
import XCTest

/// Decision 533: the company's schools bring students and its hospitals
/// patients, who ride the trains there and home again. Every expectation
/// is worked out by hand from the rules.
final class CivicRidersTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)
    /// Within 800 m of Foot, as `ParksAndTemplesTests`' temple.
    private let site = PlanPoint(x: 31_000, y: 26_768)

    /// Home and Foot with a train in a managed company with cash, no city
    /// and no tourism: Home's 10,000 trips a day are the students' and
    /// patients' weight, Foot draws no trips of its own.
    private func world() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 32_768))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 30_000, y: 32_768))
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .civic, dailyTrips: 0))
        return world
    }

    func testTheDaysEachKindIsOpen() throws {
        let world = try world()
        // Day 0 is a Monday of the first month.
        XCTAssertEqual(world.civicRidersExpected(.school, at: site, onDay: 0), 500)
        XCTAssertEqual(world.civicRidersExpected(.school, at: site, onDay: 4), 500, "Friday")
        XCTAssertEqual(world.civicRidersExpected(.school, at: site, onDay: 5), 0, "Saturday")
        XCTAssertEqual(world.civicRidersExpected(.school, at: site, onDay: 6), 0, "Sunday")
        // Day 182 (a Monday) is in the seventh month: the summer holiday.
        XCTAssertEqual(StationDemand.weekday(ofDay: 182), 1)
        XCTAssertEqual(world.civicRidersExpected(.school, at: site, onDay: 182), 0)
        XCTAssertEqual(world.civicRidersExpected(.school, at: site, onDay: 245), 500, "September, a Monday")
        XCTAssertEqual(world.civicRidersExpected(.hospital, at: site, onDay: 0), 300)
        XCTAssertEqual(world.civicRidersExpected(.hospital, at: site, onDay: 5), 150, "Saturday: half")
        XCTAssertEqual(world.civicRidersExpected(.hospital, at: site, onDay: 6), 60, "Sunday: a fifth")
        XCTAssertEqual(world.civicRidersExpected(.hospital, at: site, onDay: 182), 300, "no summer holiday")
        XCTAssertEqual(world.civicRidersExpected(.park, at: site, onDay: 0), 0)
    }

    func testASchoolBringsStudentsInTheMorningAndHomeInTheAfternoon() throws {
        var world = try world()
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 0, "Foot draws no one of its own")
        XCTAssertEqual(world.civicRiders(at: foot), [])
        try world.placeBuilding(.school, at: site)
        // 10,000 trips at Home, one student for 40: 250, fewer than 500.
        XCTAssertEqual(world.civicRiders(at: foot), [CivicRiders(kind: .school, riders: 250)])
        XCTAssertEqual(world.civicRiders(at: home), [], "the school's station is Foot")
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 250)
        let there = world.hourlyDemand(from: home, to: foot)
        // 250 shared 2 : 7 : 1 over 6, 7 and 8 o'clock.
        XCTAssertEqual(Array(there[6...8]), [50, 175, 25])
        XCTAssertEqual(there.reduce(0, +), 250)
        // Home again: 1 : 1 : 4 : 3 : 1 : 1 over 12, 15, 16, 17, 18 and 21 o'clock
        // (25, 25, 91, 69, 20, 20 by largest remainder), on top of Home's
        // own trips to Foot's nothing.
        let back = world.hourlyDemand(from: foot, to: home)
        XCTAssertEqual(back.reduce(0, +), 250)
        XCTAssertEqual(back[7], 0, "nobody leaves school in the morning")
        XCTAssertEqual(back[16], 91)
    }

    func testAHospitalBringsFewerFromAWiderReach() throws {
        var world = try world()
        try world.placeBuilding(.hospital, at: site)
        // One patient for 80 residents: 125.
        XCTAssertEqual(world.civicRiders(at: foot), [CivicRiders(kind: .hospital, riders: 125)])
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 125)
        try world.placeBuilding(.school, at: PlanPoint(x: 26_000, y: 26_768))
        XCTAssertEqual(world.civicRiders(at: foot), [CivicRiders(kind: .school, riders: 250), CivicRiders(kind: .hospital, riders: 125)])
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 375)
    }

    func testSchoolsNearOneAnotherShareTheirStudents() throws {
        var world = try world()
        try world.placeBuilding(.school, at: site)
        try world.placeBuilding(.school, at: PlanPoint(x: 26_000, y: 26_768))
        XCTAssertEqual(world.civicRiders(at: foot), [CivicRiders(kind: .school, riders: 250)], "125 each")
    }

    func testAStationBeyondTheReachSendsNoOne() throws {
        // A school 12 km and a little from Home (768,000 units), beside a
        // station of its own on the line.
        let far = PlanPoint(x: 10_000 + 768_100, y: 32_768)
        var world = try GameWorld(bounds: WorldBounds(width: 1_048_576, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 32_768))
        try world.buildStation(named: "Far", at: far)
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .civic, dailyTrips: 0))
        try world.placeBuilding(.school, at: PlanPoint(x: far.x, y: far.y - 6_000))
        XCTAssertEqual(world.civicRiders(at: foot), [], "too far to come to school")
        try world.placeBuilding(.hospital, at: PlanPoint(x: far.x + 4_000, y: far.y - 6_000))
        XCTAssertEqual(world.civicRiders(at: foot), [CivicRiders(kind: .hospital, riders: 125)], "a hospital's reach is 25 km")
    }

    func testNoStudentsOnASaturday() throws {
        var world = try world()
        try world.placeBuilding(.school, at: site)
        try world.placeBuilding(.hospital, at: PlanPoint(x: 26_000, y: 26_768))
        world.setSpeed(.normal)
        try world.advance(ticks: 5 * 1_440 + 2)
        XCTAssertEqual(world.dayIndex(of: world.clock.now), 5)
        XCTAssertEqual(world.civicRiders(at: foot), [CivicRiders(kind: .hospital, riders: 125)], "half of 300 is more than the 125 Home can send")
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 125)
    }

    func testTheStudentsSetOutForSchool() throws {
        func released(with kind: PlacedBuildingKind?) throws -> Int64 {
            var world = try world()
            if let kind { try world.placeBuilding(kind, at: site) }
            world.setSpeed(.normal)
            try world.advance(ticks: 1_440)
            // Home's only trips are those to Foot: the students'. (This
            // world's train has no track, so they wait.)
            return world.passengerLedger(of: home).released
        }
        XCTAssertEqual(try released(with: nil), 0)
        XCTAssertEqual(try released(with: .school), 250)
        XCTAssertEqual(try released(with: .hospital), 125)
    }

    func testASchoolBuiltOrSoldMidDayRunsAsIfLoaded() throws {
        var world = try world()
        world.setSpeed(.normal)
        try world.advance(ticks: 300)
        func continuesAsLoaded(_ label: String) throws {
            var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
            var running = world
            try running.advance(ticks: 600)
            try loaded.advance(ticks: 600)
            XCTAssertEqual(running, loaded, label)
        }
        let school = try world.placeBuilding(.school, at: site)
        try continuesAsLoaded("built")
        try world.advance(ticks: 120)
        try world.sellPlacedBuilding(school.id)
        try continuesAsLoaded("sold")
    }
}
