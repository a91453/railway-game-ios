import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 118: the station master's one sentence, the most
/// pressing first: debt, a full station, a line no one rides, a crowded
/// station, then the next step of a first line, then (decision 128) how
/// the towns grow.
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

    /// Decision 128: once a first line runs through a new game's town, the
    /// station master says how its towns grew at the last midnight: a
    /// station that served too few to grow taller first, else the town
    /// that grew most.
    func testOnceALineRunsItSaysHowTheTownsGrew() throws {
        var world = GameWorld.newGame()
        let tile = Int64(1_024), platform = 4 * Train.carLength
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
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        XCTAssertNil(StationMasterAdvice(world: world), "nothing grew yet")

        try world.advance(ticks: 1 + 2 * 1_440)
        let places = try XCTUnwrap(world.townGrowth?.places)
        let expected: StationMasterAdvice?
        if let short = places.first(where: { $0.lastService > 0 && $0.lastService < LandDemand.upgradeService }) {
            expected = .underserved(station: short.station, name: world.station(id: short.station)!.name, percent: short.lastService / 10)
        } else if let most = places.map(\.lastGrowth).max(), most > 0, let grown = places.first(where: { $0.lastGrowth == most }) {
            expected = .townGrew(station: grown.station, name: world.station(id: grown.station)!.name, tenths: most)
        } else {
            expected = nil
        }
        XCTAssertNotNil(expected, "the line's towns grew or asked for trains")
        XCTAssertEqual(StationMasterAdvice(world: world), expected)
    }

    func testWhatItSaysOfTheTownsGrowth() {
        let grew = StationMasterAdvice.townGrew(station: Self.alpha, name: "Alpha", tenths: 12)
        XCTAssertEqual(grew.text(in: .english), "The town round Alpha grew 1.2% yesterday. Good service keeps it growing.")
        XCTAssertEqual(grew.text(in: .traditionalChinese), "「Alpha」附近的城市昨天成長了 1.2%。服務好，城市就會繼續長大。")
        XCTAssertFalse(grew.isWorry)
        let short = StationMasterAdvice.underserved(station: Self.alpha, name: "Alpha", percent: 64)
        XCTAssertEqual(
            short.text(in: .english),
            "Only 64% of Alpha's passengers got a train yesterday. At 80% the town round it grows taller: run more trains."
        )
        XCTAssertEqual(short.text(in: .traditionalChinese), "昨天「Alpha」只有 64% 的旅客搭上車。到 80% 附近的城市才會長高，加開列車吧。")
        XCTAssertTrue(short.isWorry)
    }
}
