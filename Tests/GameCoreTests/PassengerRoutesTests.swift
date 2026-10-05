import GameCore
import XCTest

final class PassengerRoutesTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let d = StationID(rawValue: 4)

    private func network() throws -> GameWorld {
        var world = try makeWorld(width: 20_480, height: 20_480)
        for (index, point) in [PlanPoint(x: 1_000, y: 1_000), PlanPoint(x: 4_000, y: 1_000),
                               PlanPoint(x: 7_000, y: 1_000), PlanPoint(x: 10_000, y: 1_000)].enumerated() {
            try world.buildStation(named: "S\(index)", at: point)
        }
        return world
    }

    private func run(_ world: inout GameWorld, _ line: LineID, headway: Int64? = nil) throws {
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        if let headway {
            try world.setLineTargetHeadways(line, to: TargetHeadways(peak: headway, offPeak: headway, low: headway))
        }
    }

    func testTwoLinesJoinAtAStationAndTheServiceGraphChangesImmediately() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        try run(&world, first)
        try run(&world, second)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].legs.map(\.line), [first, second])
        XCTAssertEqual(routes[0].legs.map(\.from), [a, b])
        XCTAssertEqual(routes[0].legs.map(\.to), [b, c])
        XCTAssertEqual(routes[0].transfers, 1)
        XCTAssertEqual(routes[0].transferMinutes, 4)
        XCTAssertEqual(routes[0].totalMinutes,
                       routes[0].rideMinutes + routes[0].waitMinutes + routes[0].transferMinutes)
        XCTAssertNil(world.passengerTrip(from: a, to: c))

        try world.setLineTrainsInService(second, to: .none)
        XCTAssertEqual(world.passengerRoutes(from: a, to: c), [])
        try run(&world, second)
        XCTAssertEqual(world.passengerRoutes(from: c, to: a).first?.legs.map(\.line), [second, first])
        try world.setLineServiceWindow(second, to: .standard)
        XCTAssertEqual(world.passengerRoutes(from: a, to: c), [])
        XCTAssertEqual(world.passengerRoutes(from: a, to: d), [])
    }

    func testWaitCanMakeATransferQuickerThanADirectTrain() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        let direct = try world.createLine(named: "Direct", stops: [a, c]).id
        try run(&world, first)
        try run(&world, second)
        try run(&world, direct, headway: 60)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertEqual(routes.first?.legs.map(\.line), [first, second])
        XCTAssertTrue(routes.contains { $0.legs.map(\.line) == [direct] })
        XCTAssertEqual(routes.map(\.totalMinutes), routes.map(\.totalMinutes).sorted())
        XCTAssertEqual(world.passengerRoutes(from: a, to: c, limit: 1).count, 1)
        XCTAssertEqual(world.passengerRoutes(from: a, to: a), [])
    }

    func testEqualDirectServicesUseLineOrder() throws {
        var world = try network()
        let first = try world.createLine(named: "First", stops: [a, b, c]).id
        let second = try world.createLine(named: "Second", stops: [a, b, c]).id
        try run(&world, first)
        try run(&world, second)

        let routes = world.passengerRoutes(from: a, to: c)
        XCTAssertEqual(routes.prefix(2).map { $0.legs.map(\.line) }, [[first], [second]])
        XCTAssertEqual(routes[0].totalMinutes, routes[1].totalMinutes)
        XCTAssertEqual(routes[0].legs[0].from, a)
        XCTAssertEqual(routes[0].legs[0].to, c)
    }
}
