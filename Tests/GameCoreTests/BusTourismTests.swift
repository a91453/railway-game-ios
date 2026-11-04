import Foundation
@testable import GameCore
import XCTest

/// Tourists by bus (decision 587): a sight no station serves on foot is
/// reached by train to the station a bus route brings riders to, then on
/// by bus; a cableway that reaches it goes first, a station within reach
/// keeps it, and the tourists' rides join the route's riders, no more than
/// its buses hold. A cell is 4,096 units (64 m).
final class BusTourismTests: XCTestCase {
    private static let track = TestLine(tiles: 256, row: 33)
    private let cell = Land.cellLength
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let sight = AttractionID(rawValue: 1)

    private func at(_ column: Int) -> CellPosition {
        CellPosition(row: 8, column: column)
    }

    /// CityBusTripsTests' world: a managed world of 128 × 16 cells with
    /// land demand, A in cell (8, 5) with 1,000 residents and B in cell
    /// (8, 60) with 1,000 residents beside it (so tourists set out from
    /// there) and 1,000 office jobs, a train between them, a road all along
    /// row 8; and a three-star mountain at the middle of cell (8,
    /// `sightColumn`). A minute a tick.
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
        world.enableRoads()
        try world.setRoads((0..<128).map(at), in: (0..<8).map { LandBlock(row: 0, column: $0) })
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

    /// A sight by the stop of a route feeding A, 1.6 km from A and 1.9 km
    /// from B: no station serves it on foot, so its tourists ride from B to
    /// A and on by bus, there and back; with no bus running none come.
    func testASightByAFeedersStopSendsItsTouristsOnByBus() throws {
        var world = try world(sightColumn: 30)
        XCTAssertNil(world.attractionStation(of: sight))
        XCTAssertTrue(flows(world, onDay: 1).flows.isEmpty, "no station serves it")
        let route = try world.createBusRoute(to: a, stops: [at(30)], service: .every(minutes: 10), buses: 0)
        XCTAssertNil(world.attractionStation(of: sight), "no bus runs")
        try world.setBusCount(route.id, to: 4)
        XCTAssertEqual(world.attractionStation(of: sight), a)
        let tuesday = flows(world, onDay: 1)
        let tourists = try XCTUnwrap(tuesday.arrivals[sight])
        XCTAssertGreaterThan(tourists, 0)
        XCTAssertEqual(tuesday.flows.pairs[b]?[a]?.outbound, tourists)
        XCTAssertEqual(tuesday.flows.pairs[a]?[b]?.back, tourists)
        XCTAssertEqual(tuesday.flows.feederRides, [.bus(route.id): 2 * tourists], "there and back")
        let monday = flows(world, onDay: 0)
        XCTAssertEqual(monday.flows.feederRides[.bus(route.id)].map { $0 > 0 }, true, "buses run on Monday too")
    }

    /// A city route meeting A at its stop by (8, 7) takes the sight's
    /// tourists on from A as a feeder does; its stop that meets A does
    /// not count, so a sight only that stop reaches gets none by bus.
    func testACityRouteMeetingAStationTakesThemOn() throws {
        var world = try world(sightColumn: 30)
        let route = try world.createBusRoute(to: nil, stops: [at(7), at(30)], service: .every(minutes: 10), buses: 4)
        XCTAssertEqual(world.busRoute(id: route.id)?.transfer, BusTransfer(station: a, stop: 0))
        XCTAssertEqual(world.attractionStation(of: sight), a)
        let tourists = try XCTUnwrap(flows(world, onDay: 1).arrivals[sight])
        XCTAssertEqual(flows(world, onDay: 1).flows.feederRides, [.bus(route.id): 2 * tourists])

        // A sight 1 km east of A (8, 21): the stop at (8, 7) is 896 m
        // away, out of reach, and the stop that meets A does not count
        // anyway; the stop at (8, 30) is 576 m away and takes it.
        var far = try self.world(sightColumn: 21)
        let other = try far.createBusRoute(to: nil, stops: [at(7), at(30)], service: .every(minutes: 10), buses: 4)
        XCTAssertEqual(Array(flows(far, onDay: 1).flows.feederRides.keys), [.bus(other.id)])
        var near = try self.world(sightColumn: 18)
        try near.createBusRoute(to: nil, stops: [at(7), at(40)], service: .every(minutes: 10), buses: 4)
        XCTAssertNil(near.attractionStation(of: sight), "only the stop meeting A is within 800 m (704 m), and it does not count")
    }

    /// A city route whose nearest station takes no tourists (C, beside
    /// the track, where no line calls: as a bought line's depot) brings
    /// them to the nearest that does, A, 256 m from its first stop.
    func testACityRouteBringsThemToAStationTakingThem() throws {
        var world = try world(sightColumn: 30)
        try Self.track.buildStation(named: "C", beside: 37, at: 33, in: &world)
        let c = try XCTUnwrap(world.stations.first { $0.name == "C" }).id
        let route = try world.createBusRoute(to: nil, stops: [at(9), at(30)], service: .every(minutes: 10), buses: 4)
        XCTAssertEqual(world.busRoute(id: route.id)?.transfer?.station, c, "the riders' own transfer is the nearest station")
        XCTAssertFalse(world.takesTourists(c))
        XCTAssertEqual(world.busTouristTransfer(of: try XCTUnwrap(world.busRoute(id: route.id))), BusTransfer(station: a, stop: 0))
        XCTAssertEqual(world.attractionStation(of: sight), a)
        let tourists = try XCTUnwrap(flows(world, onDay: 1).arrivals[sight])
        XCTAssertEqual(flows(world, onDay: 1).flows.feederRides, [.bus(route.id): 2 * tourists])
    }

    /// A sight a station reaches on foot stays the station's: the bus
    /// carries none of its tourists.
    func testASightAStationReachesStaysTheStations() throws {
        var world = try world(sightColumn: 14)
        let before = flows(world, onDay: 1)
        XCTAssertEqual(world.attractionStation(of: sight), a)
        try world.createBusRoute(to: a, stops: [at(14)], service: .every(minutes: 10), buses: 4)
        let after = flows(world, onDay: 1)
        XCTAssertTrue(after.flows.feederRides.isEmpty)
        XCTAssertEqual(after.arrivals, before.arrivals)
        XCTAssertEqual(after.flows.pairs[b]?[a]?.outbound, before.flows.pairs[b]?[a]?.outbound)
    }

    /// A cableway that reaches the sight goes first, even with a bus stop
    /// nearer (on the sight, the cableway's stop 128 m off); on a Monday,
    /// when the rope stands still, the bus takes them. Two routes reaching
    /// it alike: the lower route.
    func testACablewayGoesFirstAndTheLowerRouteThen() throws {
        var world = try world(sightColumn: 28)
        let first = try world.createBusRoute(to: a, stops: [at(28)], service: .every(minutes: 10), buses: 4)
        try world.createBusRoute(to: a, stops: [at(28)], service: .every(minutes: 10), buses: 4)
        XCTAssertEqual(Array(flows(world, onDay: 1).flows.feederRides.keys), [.bus(first.id)], "the lower route")
        let cableway = try world.createCableway(stops: [
            CablewayStop(cell: CellPosition(row: 8, column: 6)),
            CablewayStop(cell: CellPosition(row: 4, column: 16), boards: false),
            CablewayStop(cell: CellPosition(row: 8, column: 26)),
        ])
        let tuesday = flows(world, onDay: 1)
        let tourists = try XCTUnwrap(tuesday.arrivals[sight])
        XCTAssertEqual(tuesday.flows.feederRides, [.cableway(cableway.id): 2 * tourists])
        let monday = flows(world, onDay: 0)
        let mondays = try XCTUnwrap(monday.arrivals[sight])
        XCTAssertEqual(monday.flows.feederRides, [.bus(first.id): 2 * mondays], "the rope stands still on Monday")
    }

    /// The tourists' rides join the route's riders of the day they rode,
    /// no more than its buses hold: one bus every 720 minutes, two
    /// departures each way, 280 riders a day.
    func testTheTouristsRidesAreBookedUpToWhatTheBusesHold() throws {
        var touring = try world(sightColumn: 30)
        let route = try touring.createBusRoute(to: a, stops: [at(30)], service: .every(minutes: 720), buses: 1)
        XCTAssertEqual(touring.busRoute(id: route.id)?.dailyCapacity, 280)
        let rides = try XCTUnwrap(flows(touring, onDay: 1).flows.feederRides[.bus(route.id)])
        XCTAssertGreaterThan(rides, 280)
        var plain = touring
        plain.setTourism(nil)
        try touring.advance(ticks: 2 * 1_440 + 30)
        try plain.advance(ticks: 2 * 1_440 + 30)
        let toured = try XCTUnwrap(touring.busRoute(id: route.id)).days
        let days = try XCTUnwrap(plain.busRoute(id: route.id)).days
        XCTAssertLessThan(days[1].riders, 280, "without the tourists")
        XCTAssertEqual(toured[1].riders, 280, "the rest stay off")
        XCTAssertEqual(toured[1].fares, Money(280 * 1_500))
    }
}
