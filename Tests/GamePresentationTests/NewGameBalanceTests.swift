import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 46: a new game's prices and starting money. A
/// first line pays for itself in about ten days of its fares less its
/// running costs, and the starting money builds it with some to spare.
final class NewGameBalanceTests: XCTestCase {
    /// Three stations of the city's ridership on 28 tiles of surface track
    /// across a new game's map, and a train of four cars running all day:
    /// $44,800 of track, $600,000 of stations and $270,000 for the train.
    func testAFirstLinePaysForItselfInAboutTenDays() throws {
        var world = GameWorld.newGame()
        // The test layout's spacing: 1024 units, 16 m (the world has no cells).
        let tile = Int64(1_024)
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 2 * tile, y: 12 * tile))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 30 * tile, y: 12 * tile))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for middle in [tile + platform / 2, 14 * tile, 27 * tile - platform / 2] {
            let station = try world.buildStation(named: "S\(stops.count)", at: PlanPoint(x: 2 * tile + middle, y: 12 * tile)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            try world.setStationDemand(station, to: .cityDefault)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)

        let cost = GameWorld.startingBalance - world.economy.balance
        XCTAssertEqual(cost, Money(91_480_000), "$914,800")
        XCTAssertLessThan(cost.amount * 2, GameWorld.startingBalance.amount, "with more than half the money to spare")

        // The second whole day, its hours and its day settled.
        try world.advance(ticks: 1 + 2 * 1_440)
        let day = world.financeReport(.day).previous
        XCTAssertGreaterThan(day.operatingProfit, .zero)
        let payback = Double(cost.amount) / Double(day.operatingProfit.amount)
        XCTAssertTrue((7...14).contains(payback), "pays for itself in \(payback) days")
    }

    /// The demo map is built with a new game's money and prices, and leaves
    /// enough to build the tutorial's first line beside it: two stations
    /// and a train.
    func testTheDemoMapFitsTheStartingMoney() {
        let demo = DemoWorld.make(in: .english)
        let costs = ConstructionCosts.newGame
        XCTAssertEqual(demo.economy.costs, costs)
        XCTAssertEqual(GameWorld.startingBalance - demo.economy.balance, Money(229_120_000), "$2,291,200")
        XCTAssertGreaterThan(demo.economy.balance.amount, 2 * costs.station.amount + costs.train.amount)
    }
}
