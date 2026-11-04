import Foundation
@testable import GameCore
import XCTest

/// Tourists by ferry (decision 589): a sight no station serves on foot,
/// within 800 m of a pier, is reached by train to the station within 800 m
/// of another pier of the route and on by boat; a cableway that reaches it
/// goes first, a ferry before a bus, a station within reach keeps it, and
/// the tourists' crossings join the route's riders. A cell is 4,096 units
/// (64 m).
final class FerryTourismTests: XCTestCase {
    private static let track = TestLine(tiles: 256, row: 33)
    private let cell = Land.cellLength
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let sight = AttractionID(rawValue: 1)

    private func at(_ column: Int, row: Int = 8) -> CellPosition {
        CellPosition(row: row, column: column)
    }

    /// BusTourismTests' world (A in cell (8, 5), B in (8, 60), a train
    /// between them, a three-star mountain in cell (8, `sightColumn`)), with
    /// water all along row 10, so that the land cells of row 9 are on the
    /// shore.
    private func world(sightColumn: Int) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 128 * cell, height: 16 * cell),
                              economy: fixtureEconomy(balance: 1_000_000_000, costs: testCosts))
        try Self.track.build(in: &world)
        try Self.track.buildStation(named: "A", beside: 21, at: 33, in: &world)
        try Self.track.buildStation(named: "B", beside: 241, at: 33, in: &world)
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0),
                           LandCell(row: 8, column: 59, use: .residential, residents: 1_000, jobs: 0),
                           LandCell(row: 8, column: 60, use: .office, residents: 0, jobs: 1_000)])
        world.setLandDemand(true)
        try world.setWater((0..<128).map { at($0, row: 10) })
        let line = try world.createLine(named: "Main", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: Self.track.at(21, facingEast: true))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: line)
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        world.setTourism([Attraction(id: sight, name: "山", englishName: "Hill",
                                     point: GameWorld.middle(of: at(sightColumn)), kind: .mountain, baseStars: 300)])
        return world
    }

    private func flows(_ world: GameWorld, onDay day: Int64) -> (flows: TouristFlows, arrivals: [AttractionID: Int64]) {
        let counted = world.touristFlows(onDay: day) { world.reaches(from: $0, to: $1, graph: nil) }
        return (counted.flows, counted.arrivals)
    }

    /// A pier by A (cell (9, 10)) and one by the sight (9, 30), 1.6 km
    /// from A and 1.9 km from B: its tourists
    /// ride from B to A and cross by boat, there and back; with no boat
    /// none come.
    func testASightByAPierSendsItsTouristsOnByBoat() throws {
        var world = try world(sightColumn: 30)
        XCTAssertNil(world.attractionStation(of: sight))
        let route = try world.createFerryRoute(piers: [at(10, row: 9), at(30, row: 9)], service: .every(minutes: 15), boats: 0)
        XCTAssertNil(world.attractionStation(of: sight), "no boat")
        XCTAssertTrue(flows(world, onDay: 1).flows.isEmpty)
        try world.setFerryBoats(route.id, to: 2)
        XCTAssertEqual(world.attractionStation(of: sight), a)
        let tuesday = flows(world, onDay: 1)
        let tourists = try XCTUnwrap(tuesday.arrivals[sight])
        XCTAssertGreaterThan(tourists, 0)
        XCTAssertEqual(tuesday.flows.pairs[b]?[a]?.outbound, tourists)
        XCTAssertEqual(tuesday.flows.pairs[a]?[b]?.back, tourists)
        XCTAssertEqual(tuesday.flows.feederRides, [.ferry(route.id): 2 * tourists], "there and back")

        // The crossings join the boats' riders of the day.
        world.countFeederRides(tuesday.flows.feederRides)
        XCTAssertEqual(world.ferryRoute(id: route.id)?.ridersToday, 2 * tourists)
    }

    /// The pier by the station does not count (from there they would
    /// walk), and the station may be up to 800 m from a pier: a station
    /// 900 m away is not.
    func testThePierByTheStationDoesNotCountAndTheWalkIsASightsWalk() throws {
        var near = try world(sightColumn: 18)
        try near.createFerryRoute(piers: [at(12, row: 9), at(40, row: 9)], service: .every(minutes: 15), boats: 2)
        XCTAssertNil(near.attractionStation(of: sight), "only the pier by A is within 800 m of the sight")

        var far = try world(sightColumn: 40)
        try far.createFerryRoute(piers: [at(19, row: 9), at(40, row: 9)], service: .every(minutes: 15), boats: 2)
        XCTAssertNil(far.attractionStation(of: sight), "the pier at (9, 19) is some 900 m from A")
        var reached = try world(sightColumn: 40)
        try reached.createFerryRoute(piers: [at(16, row: 9), at(40, row: 9)], service: .every(minutes: 15), boats: 2)
        XCTAssertEqual(reached.attractionStation(of: sight), a, "the pier at (9, 16) is some 710 m from A")
    }

    /// A sight a station reaches on foot stays the station's: the boats
    /// carry none of its tourists.
    func testASightAStationReachesStaysTheStations() throws {
        var world = try world(sightColumn: 14)
        let before = flows(world, onDay: 1)
        XCTAssertEqual(world.attractionStation(of: sight), a)
        try world.createFerryRoute(piers: [at(6, row: 9), at(14, row: 9)], service: .every(minutes: 15), boats: 2)
        let after = flows(world, onDay: 1)
        XCTAssertTrue(after.flows.feederRides.isEmpty)
        XCTAssertEqual(after.arrivals, before.arrivals)
    }

    /// A ferry goes before a bus reaching the same sight (the order the
    /// land is shared in, decision 585); two routes alike: the lower one.
    func testAFerryGoesBeforeABusAndTheLowerRouteThen() throws {
        var world = try world(sightColumn: 30)
        world.enableRoads()
        try world.setRoads((0..<128).map { at($0) }, in: (0..<8).map { LandBlock(row: 0, column: $0) })
        try world.createBusRoute(to: a, stops: [at(30)], service: .every(minutes: 10), buses: 4)
        let first = try world.createFerryRoute(piers: [at(10, row: 9), at(30, row: 9)], service: .every(minutes: 15), boats: 2)
        try world.createFerryRoute(piers: [at(10, row: 9), at(30, row: 9)], service: .every(minutes: 15), boats: 2)
        XCTAssertEqual(Array(flows(world, onDay: 1).flows.feederRides.keys), [.ferry(first.id)])
    }

    /// No ferry, no change: the access is `nil` at once.
    func testWithoutFerriesNothingChanges() throws {
        let world = try world(sightColumn: 30)
        XCTAssertNil(world.ferryAccess(to: GameWorld.middle(of: at(30)), onDay: 1))
    }
}
