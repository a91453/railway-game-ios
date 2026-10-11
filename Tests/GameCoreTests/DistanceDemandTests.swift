import Foundation
@testable import GameCore
import XCTest

/// Demand by distance and the outside connections (ARCHITECTURE decision
/// 137). Every expectation is worked out by hand from the rules.
final class DistanceDemandTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let d = StationID(rawValue: 4)

    // MARK: - The share by distance

    func testTheShareGrowsFromATenthAtHalfAKilometreToAllAtTwo() {
        func share(_ units: Int64) -> Int64 { DistanceDemand.share(squaredDistance: units * units) }
        XCTAssertEqual(share(0), 100)
        XCTAssertEqual(share(32_000), 100, "500 m")
        XCTAssertEqual(share(32_001), 100, "900 × 1 / 96000 rounds down")
        XCTAssertEqual(share(32_106), 100)
        XCTAssertEqual(share(32_107), 101, "the first unit of a thousandth more")
        XCTAssertEqual(share(80_000), 550, "1.25 km, half way")
        XCTAssertEqual(share(112_000), 850, "1.75 km")
        XCTAssertEqual(share(127_999), 999)
        XCTAssertEqual(share(128_000), 1_000, "2 km")
        XCTAssertEqual(share(1_000_000), 1_000)
        // The distance is the square root rounded down.
        XCTAssertEqual(DistanceDemand.share(squaredDistance: 80_000 * 80_000 - 1), 549)
    }

    // MARK: - Demand by distance

    /// A at x = 10,000; B 400 m east of it, D 1.75 km and C 4 km; a line
    /// A–B–D–C. A sends 1,000 trips a day, the others draw 1,000 each.
    private func corridor() throws -> GameWorld {
        var world = try makeWorld(width: 300_000, height: 20_000, balance: 100_000)
        for x: Int64 in [10_000, 35_600, 266_000, 122_000] {
            try world.buildStation(named: "S\(x)", at: PlanPoint(x: x, y: 10_000))
        }
        try world.createLine(named: "Line", stops: [a, b, d, c])
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        for station in [b, c, d] {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 1_000))
        }
        return world
    }

    func testEachPairKeepsTheShareOfItsDistance() throws {
        var world = try corridor()
        // Off, as before decision 137: 1,000 shared equally, B first.
        XCTAssertFalse(world.distanceDemand)
        XCTAssertEqual([b, c, d].map { world.dailyDemand(from: a, to: $0) }, [334, 333, 333])

        world.setDistanceDemand(true)
        XCTAssertTrue(world.distanceDemand)
        // 334 × 100‰ = 33.4, 333 × 1000‰, 333 × 850‰ = 283.05.
        XCTAssertEqual([b, c, d].map { world.dailyDemand(from: a, to: $0) }, [33, 333, 283])
        XCTAssertEqual(world.dailyDemands(from: a), [b: 33, c: 333, d: 283])

        // The plan releases what the queries give.
        let plan = try XCTUnwrap(world.makePassengerPlan())
        for (index, flow) in plan.flows.enumerated() where flow.origin == a {
            let day = plan.hourly[index * 24..<(index + 1) * 24].reduce(0, +)
            XCTAssertEqual(day, world.dailyDemand(from: a, to: flow.destination))
        }

        world.setDistanceDemand(false)
        XCTAssertEqual([b, c, d].map { world.dailyDemand(from: a, to: $0) }, [334, 333, 333])
    }

    // MARK: - Outside connections

    private static let middle: Int64 = 524_288

    /// A managed world of the standard bounds with demand from land: a cell
    /// of 1,000 residents in the middle with the station Town on it, and the
    /// stations West, 30,000 units from the west edge, and East, 60,000 from
    /// the east edge (both within 1 km), on no land.
    private func edgeWorld() throws -> GameWorld {
        var world = GameWorld(bounds: .standard, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 128, column: 128, use: .residential, residents: 1_000, jobs: 0)])
        world.setLandDemand(true)
        try world.buildStation(named: "Town", at: PlanPoint(x: Self.middle + 2_048, y: Self.middle + 2_048))
        try world.buildStation(named: "West", at: PlanPoint(x: 30_000, y: Self.middle))
        try world.buildStation(named: "East", at: PlanPoint(x: WorldBounds.standard.width - 60_000, y: Self.middle))
        return world
    }

    func testTheStationsByTheEdgeShareTheOutsidesTrips() throws {
        var world = try edgeWorld()
        let town = a, west = b, east = c
        XCTAssertFalse(world.outsideConnections)
        XCTAssertFalse(world.isOutsideConnection(west))
        XCTAssertNil(world.stationDemand(of: west))
        XCTAssertEqual(world.stationDemand(of: town), StationDemand(kind: .residential, dailyTrips: 400))

        world.setOutsideConnections(true)
        XCTAssertEqual([town, west, east].map(world.isOutsideConnection), [false, true, true])
        XCTAssertEqual(world.stationDemand(of: west), StationDemand(kind: .residential, dailyTrips: 3_000))
        XCTAssertEqual(world.stationDemand(of: east), StationDemand(kind: .residential, dailyTrips: 3_000))
        XCTAssertEqual(world.stationDemand(of: town), StationDemand(kind: .residential, dailyTrips: 400))

        // A closed station is no connection's share: West has all of it.
        try world.setStationOperationMode(east, to: .closed)
        XCTAssertEqual(world.stationDemand(of: west), StationDemand(kind: .residential, dailyTrips: 6_000))
        XCTAssertNil(world.stationDemand(of: east))

        // A fourth by the north edge, exactly 1 km from it, is one too; the
        // three open ones share 6,000 equally.
        try world.setStationOperationMode(east, to: .normalFlow)
        try world.buildStation(named: "North", at: PlanPoint(x: Self.middle, y: DistanceDemand.outsideMargin - 1))
        XCTAssertTrue(world.isOutsideConnection(d))
        XCTAssertEqual([west, east, d].map { world.stationDemand(of: $0)?.dailyTrips }, [2_000, 2_000, 2_000])
        let south = try world.buildStation(named: "South", at: PlanPoint(x: Self.middle, y: WorldBounds.standard.height - DistanceDemand.outsideMargin - 1)).id
        XCTAssertFalse(world.isOutsideConnection(south), "just over 1 km from the edge")

        world.setOutsideConnections(false)
        XCTAssertNil(world.stationDemand(of: west))
        XCTAssertFalse(world.isOutsideConnection(west))
    }

    func testAnOutsideConnectionsLandAddsToTheOutside() throws {
        var world = try edgeWorld()
        // Offices by West: 300 residents, 900 jobs, so 480 trips of offices.
        try world.setLand([
            LandCell(row: 128, column: 128, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 128, column: 7, use: .office, residents: 300, jobs: 900),
        ])
        world.setOutsideConnections(true)
        XCTAssertEqual(world.stationDemand(of: b), StationDemand(kind: .office, dailyTrips: 3_480))
    }

    func testTripsToAndFromAnOutsideConnectionPayTheLongDistanceFareAndKeepAllTheirTrips() throws {
        var world = try edgeWorld()
        let town = a, west = b, east = c
        try world.createLine(named: "Across", stops: [west, town, east])
        world.setDistanceDemand(true)
        // The standard fare, $5, as the company has set no fares; the
        // world's baseline is the reference's $0.75.
        XCTAssertEqual(world.tripFare(from: town, to: west), Money(500))
        world.setOutsideConnections(true)
        XCTAssertEqual(world.outsideFare, Money(75))
        XCTAssertEqual(world.tripFare(from: town, to: west), Money(575))
        XCTAssertEqual(world.tripFare(from: west, to: town), Money(575))
        XCTAssertEqual(world.tripFare(from: west, to: east), Money(575), "one surcharge however many ends are outside")
        try world.setFareBaseline(Money(500))
        XCTAssertEqual(world.outsideFare, Money(500))
        XCTAssertEqual(world.tripFare(from: town, to: east), Money(1_000))

        // The pairs with an outside connection keep all their trips: Town's
        // 400 shared by the two connections' 3,000 each, 200 each.
        XCTAssertEqual(world.dailyDemand(from: town, to: west), 200)
        XCTAssertEqual(world.dailyDemand(from: town, to: east), 200)
        // West's 3,000 shared by Town's 400 and East's 3,000: 352.9 and
        // 2,647.1, the one left over to Town's larger remainder.
        XCTAssertEqual(world.dailyDemand(from: west, to: town), 353)
        XCTAssertEqual(world.dailyDemand(from: west, to: east), 2_647)
    }

    /// Two outside connections side by side are not a long-distance trip:
    /// only a pair with one end outside goes beyond the map, so a pair with
    /// both keeps the share of its distance (decision 148). A shuttle 300 m
    /// along the edge no longer carries all of both connections' visitors.
    func testTwoOutsideConnectionsSideBySideKeepTheShareOfTheirDistance() throws {
        var world = try edgeWorld()
        let town = a, west = b
        // 300 m north of West, by the same edge.
        let north = try world.buildStation(named: "North", at: PlanPoint(x: 30_000, y: Self.middle + 19_200)).id
        try world.createLine(named: "Shuttle", stops: [west, north])
        try world.createLine(named: "Town", stops: [town, west])
        world.setDistanceDemand(true)
        world.setOutsideConnections(true)
        XCTAssertTrue(world.isOutsideConnection(west))
        XCTAssertTrue(world.isOutsideConnection(north))
        // The outside's 6,000 shared by three connections, 2,000 each.
        // West's, shared by what it reaches, Town's 400 and North's 2,000:
        // 333.3 and 1,666.7, rounded to 333 and 1,667; North's keeps a
        // tenth (300 m), 166.7 rounded half up. North reaches only West:
        // its 2,000 keep 200. Town's pair keeps all, one end outside.
        XCTAssertEqual(world.dailyDemand(from: west, to: north), 167)
        XCTAssertEqual(world.dailyDemand(from: north, to: west), 200)
        XCTAssertEqual(world.dailyDemand(from: west, to: town), 333)
    }

    func testBoardingAtAnOutsideConnectionChargesTheLongDistanceFare() throws {
        var world = try edgeWorld()
        world.setOutsideConnections(true)
        let before = world.accounts.pending.fareRevenue
        world.chargeFares(3, from: a, to: b)
        // 3 × $5.75 = $17.25, rounded to $17.
        XCTAssertEqual(world.accounts.pending.fareRevenue - before, Money(1_700))
        XCTAssertEqual(world.accounts.pending.fareTrips, 3)
    }

    // MARK: - Saving

    func testBothSaveOnlyWhenOn() throws {
        var world = try edgeWorld()
        let off = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(off.contains("distanceDemand"))
        XCTAssertFalse(off.contains("outsideConnections"))
        world.setDistanceDemand(true)
        world.setOutsideConnections(true)
        let data = try JSONEncoder().encode(world)
        let on = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(on.contains(#""distanceDemand":true"#))
        XCTAssertTrue(on.contains(#""outsideConnections":true"#))
        let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
        XCTAssertEqual(loaded, world)
        XCTAssertTrue(loaded.distanceDemand)
        XCTAssertTrue(loaded.outsideConnections)
        XCTAssertEqual(loaded.stationDemand(of: b)?.dailyTrips, 3_000)
    }

    /// Version 31 (decision 137): `edgeWorld()` with both on, a line from
    /// West through Town to East, run ten minutes. It saves byte for byte
    /// and is the world this build makes.
    func testVersionThirtyOneKeepsDistanceDemandAndTheOutsideConnections() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v31-distance-demand.json")
        var made = try edgeWorld()
        made.setDistanceDemand(true)
        made.setOutsideConnections(true)
        try made.createLine(named: "Across", stops: [b, a, c])
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DISTANCE_DEMAND_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 31)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertTrue(world.distanceDemand)
        XCTAssertTrue(world.outsideConnections)
        XCTAssertEqual(world.stationDemand(of: b)?.dailyTrips, 3_000)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 31,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
