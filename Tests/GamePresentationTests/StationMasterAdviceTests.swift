import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 118: the station master's one sentence, the most
/// pressing first: debt, a full station, a line no one rides, a crowded
/// station, then the next step of a first line.
final class StationMasterAdviceTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let main = LineID(rawValue: 1)

    func testAFirstLineStepByStep() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        XCTAssertEqual(StationMasterAdvice(world: world), .buildTrack)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 1_536))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 6_656, y: 1_536))
        try world.buildTrackEdge(from: west, to: east)
        XCTAssertEqual(StationMasterAdvice(world: world), .buildStation)
        try world.buildStation(named: "Alpha", at: TestLine.centre(1, 0))
        XCTAssertEqual(StationMasterAdvice(world: world), .buildSecondStation)
        try world.buildStation(named: "Beta", at: TestLine.centre(3, 0))
        XCTAssertEqual(StationMasterAdvice(world: world), .createLine)
        XCTAssertEqual(StationMasterAdvice.createLine.text(in: .english), "Stations ready. Open Lines and join them into a line.")
        XCTAssertEqual(StationMasterAdvice.allWellText(in: .traditionalChinese), "一切順利，繼續保持！")
        XCTAssertFalse(StationMasterAdvice.createLine.isWorry)

        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        XCTAssertEqual(StationMasterAdvice(world: world), .lineWithoutTrains(line: Self.main, name: "Main"))
        XCTAssertEqual(StationMasterAdvice(world: world)?.text(in: .traditionalChinese), "「Main」還沒有列車。打開路線幫它配車。")
        let train = try world.purchaseTrain(named: "T1")
        try world.assignTrain(train.id, to: Self.main, pattern: nil)
        XCTAssertNil(StationMasterAdvice(world: world), "all runs well")
    }

    func testDebtComesFirstInAManagedCompanyOnly() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: -1)
        XCTAssertEqual(StationMasterAdvice(world: world), .buildTrack, "free play has no debt to worry about")
        world.setEconomyMode(.management)
        XCTAssertEqual(StationMasterAdvice(world: world), .inDebt)
        XCTAssertTrue(StationMasterAdvice.inDebt.isWorry)
    }

    func testAFullStationBeforeALineWithoutTrains() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(Self.beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        world.setSpeed(.normal)
        try world.advance(ticks: 480)
        let waiting = world.waitingPassengers(at: Self.alpha).reduce(Int64(0)) { $0 + $1.count }
        XCTAssertGreaterThanOrEqual(waiting * 2, StationPassengers.capacity, "the test needs a crowded station")
        let expected: StationMasterAdvice = waiting >= StationPassengers.capacity
            ? .stationFull(station: Self.alpha, name: "Alpha")
            : .lineWithoutTrains(line: Self.main, name: "Main")
        XCTAssertEqual(StationMasterAdvice(world: world), expected)
    }
}
