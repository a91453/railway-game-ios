import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 46: a new game's prices and starting money. A
/// first line pays for itself in about ten days of its fares less its
/// running costs, and the starting money builds it with some to spare;
/// since decision 137 a first line that pays links two towns, or a town
/// and the map's edge.
final class NewGameBalanceTests: XCTestCase {
    /// Decision 137: a first line from the first town to the second (seed
    /// 1, 5.4 km), a station at each town's middle and a train of four cars
    /// running all day, pays for itself in about five days, and the starting
    /// money builds it with more than half to spare. Before decision 137 a
    /// 448 m line through the first town did (decision 73); now its pairs
    /// walk (``testAShortLineThroughOneTownDoesNotPay()``).
    func testALineBetweenTwoTownsPaysForItselfInAboutFiveDays() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        XCTAssertTrue(world.stations.allSatisfy { (world.stationDemand(of: $0.id)?.dailyTrips ?? 0) > 0 }, "both towns give their station ridership")

        let cost = GameWorld.startingBalance - world.economy.balance
        XCTAssertEqual(cost, Money(122_840_000), "$1,228,400")
        XCTAssertLessThan(cost.amount * 2, GameWorld.startingBalance.amount, "with more than half the money to spare")

        // The second whole day, its hours and its day settled.
        try world.advance(ticks: 1 + 2 * 1_440)
        let day = world.financeReport(.day).previous
        XCTAssertGreaterThan(day.operatingProfit, .zero)
        let payback = Double(cost.amount) / Double(day.operatingProfit.amount)
        XCTAssertTrue((4...10).contains(payback), "pays for itself in \(payback) days")
    }

    /// Decision 137: a first line from the first town to the map's edge, on
    /// from the second town through the first (some 10 km), pays for itself
    /// in about as long: its far station is an outside connection, which
    /// brings the outside's trips and charges the long-distance fare.
    func testALineToTheEdgePaysForItselfInAboutFiveDaysToo() throws {
        let bounds = GameWorld.newGameBounds
        let towns = Land.townCentres(seed: 1, in: bounds)
        let first = towns[0], second = towns[1]
        let edgeX = second.x > first.x ? 40_000 : bounds.width - 40_000
        let edge = PlanPoint(x: edgeX, y: first.y + (first.y - second.y) * (edgeX - first.x) / (first.x - second.x))
        var world = try newGameLine(through: [first, edge])
        let far = world.stations[1].id
        XCTAssertTrue(world.isOutsideConnection(far))
        XCTAssertEqual(world.stationDemand(of: far), StationDemand(kind: .residential, dailyTrips: DistanceDemand.outsideTrips))
        XCTAssertEqual(world.tripFare(from: world.stations[0].id, to: far), FareRules.standardFare + FareRules.standardFare)

        // Some 10 km of track: $1,695,600, more than half the starting money.
        let cost = GameWorld.startingBalance - world.economy.balance
        XCTAssertEqual(cost, Money(169_560_000), "$1,695,600")
        try world.advance(ticks: 1 + 2 * 1_440)
        let day = world.financeReport(.day).previous
        XCTAssertGreaterThan(day.operatingProfit, .zero)
        let payback = Double(cost.amount) / Double(day.operatingProfit.amount)
        XCTAssertTrue((4...10).contains(payback), "pays for itself in \(payback) days")
    }

    /// Decision 137: the first line decision 73 measured, three stations
    /// through the middle of the first town on 448 m of track, no longer
    /// pays: its stations are 224 m apart, so its pairs keep a tenth of
    /// their trips and the rest walk (the balance report's item 3).
    func testAShortLineThroughOneTownDoesNotPay() throws {
        var world = GameWorld.newGame()
        // The test layout's spacing: 1024 units, 16 m (the world has no cells).
        let tile = Int64(1_024)
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        let x = GameWorld.newGameBounds.width / 2 - 16 * tile, y = GameWorld.newGameBounds.height / 2
        let west = try world.buildTrackNode(at: WorldCoordinate(x: x + 2 * tile, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: x + 30 * tile, y: y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for middle in [tile + platform / 2, 14 * tile, 27 * tile - platform / 2] {
            let station = try world.buildStation(named: "S\(stops.count)", at: PlanPoint(x: x + 2 * tile + middle, y: y)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        XCTAssertTrue(stops.allSatisfy { (world.stationDemand(of: $0)?.dailyTrips ?? 0) > 0 }, "the town gives every station ridership")
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        XCTAssertEqual(GameWorld.startingBalance - world.economy.balance, Money(91_480_000), "$914,800")
        // Each pair keeps a tenth of what it had before decision 137.
        var walking = world
        walking.setDistanceDemand(false)
        for (from, to) in [(0, 1), (0, 2), (1, 2)] {
            let before = walking.dailyDemand(from: stops[from], to: stops[to])
            XCTAssertGreaterThan(before, 0)
            XCTAssertEqual(world.dailyDemand(from: stops[from], to: stops[to]), (before * DistanceDemand.nearShare + 500) / 1_000)
        }

        try world.advance(ticks: 1 + 2 * 1_440)
        XCTAssertLessThan(world.financeReport(.day).previous.operatingProfit, .zero)
    }

    /// ARCHITECTURE decision 78: the demo map's stations draw their
    /// ridership from its city, as a new game's do, and its three lines and
    /// four trains pay for themselves in about eight days, as a new game's
    /// first line does (decision 73).
    func testTheDemoMapPaysForItselfInAboutEightDays() throws {
        var world = DemoWorld.make(in: .english)
        let cost = GameWorld.startingBalance - world.economy.balance
        XCTAssertTrue(world.landDemand)
        XCTAssertTrue(world.stations.allSatisfy { (world.stationDemand(of: $0.id)?.dailyTrips ?? 0) > 0 }, "the city gives every station ridership")

        // The first whole day, its hours and its day settled: the demo
        // carries some 110,000 passengers a day, so a day takes long in a
        // debug build.
        try world.advance(ticks: 1 + 1_440)
        let day = world.financeReport(.day).previous
        XCTAssertGreaterThan(day.operatingProfit, .zero)
        let payback = Double(cost.amount) / Double(day.operatingProfit.amount)
        XCTAssertTrue((7...10).contains(payback), "pays for itself in \(payback) days")
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
