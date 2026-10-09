import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 109: bubbles on the map for what needs the player:
/// a station half full of waiting passengers or full, and a line with no
/// train, over its first stop. Worked out from the world, so a bubble goes
/// when its cause does; a tap goes to the station or the line.
@MainActor
final class MapAlertsTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let main = LineID(rawValue: 1)

    private func twoStations() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        return world
    }

    func testAQuietWorldHasNoBubbles() throws {
        XCTAssertEqual(try twoStations().mapAlerts(), [])
    }

    func testALineWithoutTrainsShowsOverItsFirstStop() throws {
        var world = try twoStations()
        try world.createLine(named: "Main", stops: [Self.beta, Self.alpha])
        let alerts = world.mapAlerts()
        XCTAssertEqual(alerts.map(\.kind), [.lineWithoutTrains(Self.main)])
        XCTAssertEqual(alerts.first?.station, Self.beta)
        XCTAssertEqual(alerts.first?.location, world.station(id: Self.beta)?.location)
        XCTAssertEqual(alerts.first?.text(in: .english, lineName: "Main"), "Main: no trains")

        let train = try world.purchaseTrain(named: "T1")
        try world.assignTrain(train.id, to: Self.main, pattern: nil)
        XCTAssertEqual(world.mapAlerts(), [], "a train on the line: the bubble goes")
    }

    func testAStationFullOfWaitingPassengersShows() throws {
        var world = try twoStations()
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(Self.beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        world.setSpeed(.normal)
        try world.advance(ticks: 480)
        let waiting = world.waitingPassengers(at: Self.alpha).reduce(Int64(0)) { $0 + $1.count }
        let expected: MapAlert.Kind = waiting >= StationPassengers.capacity ? .full(waiting: waiting) : .crowded(waiting: waiting)
        XCTAssertGreaterThanOrEqual(waiting * 2, StationPassengers.capacity, "the test needs a crowded station")
        XCTAssertEqual(world.mapAlerts().first { $0.station == Self.alpha && $0.kind != .lineWithoutTrains(Self.main) }?.kind, expected)
    }

    func testATapGoesToTheStationOrTheLine() throws {
        var world = try twoStations()
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        let session = GameSession(world: world)
        let line = try XCTUnwrap(world.mapAlerts().first)
        XCTAssertTrue(session.respond(to: line), "the line panel opens")
        XCTAssertEqual(session.selectedLineID, Self.main)
        let crowded = MapAlert(kind: .crowded(waiting: 2_500), station: Self.beta, location: PlanPoint(x: 0, y: 0))
        XCTAssertFalse(session.respond(to: crowded))
        XCTAssertEqual(session.selectedStationID, Self.beta)
        XCTAssertEqual(session.world, world, "never changes the world")
    }
}
