import GameCore
import GamePresentation
import XCTest

/// TestFlight 60.1 ("assigned trains never leave"): the train card and the
/// follow bar say why a line does not send a train out, and a line set to
/// run fewer trains than it has offers to run them all.
@MainActor
final class LineDispatchTextTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let main = LineID(rawValue: 1)

    /// Alpha, Beta, Gamma and Delta along one single track, a line calling
    /// at all four, running all day, and two unplaced trains.
    private func lineWorld() throws -> (GameWorld, [StationID], TrainID, TrainID) {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000, speed: .normal)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        try world.setLineServiceWindow(Self.main, to: .allDay)
        let first = try world.purchaseTrain(named: "Train 1").id
        let second = try world.purchaseTrain(named: "Train 2").id
        return (world, stops, first, second)
    }

    func testAnUnplacedLineTrainIsToldToBePlacedAtTheFirstStop() throws {
        var (world, stops, train, _) = try lineWorld()
        try world.assignTrain(train, to: Self.main)
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        XCTAssertEqual(world.lineDispatchHold(of: train), .notPlaced(firstStop: stops[0]))
        XCTAssertEqual(world.trainPathStatusText(of: train, in: .english), "Not on the track: place it at Alpha first")
        XCTAssertEqual(world.trainPathStatusText(of: train, in: .traditionalChinese), "未放上軌道：先放到 Alpha")
        XCTAssertEqual(world.followBarInfo(of: train, in: .traditionalChinese)?.status, .held("未放上軌道：先放到 Alpha"))
        XCTAssertEqual(world.followBarInfo(of: train, in: .traditionalChinese)?.detail(in: .traditionalChinese), "Main　· 尚未發車：未放上軌道：先放到 Alpha")
    }

    func testATrainAwayFromTheFirstStopIsToldToBeSentThere() throws {
        let (world, stops, train, _) = try lineWorld()
        let session = GameSession(world: world)
        session.selectTrain(train)
        session.selectStation(stops[2])
        session.placeSelectedTrain()
        XCTAssertNotNil(session.world.train(id: train)?.position, session.message?.text ?? "")
        session.assignTrain(train, toLine: Self.main)
        XCTAssertEqual(session.world.lineDispatchHold(of: train), .awayFromFirstStop(firstStop: stops[0]))
        XCTAssertEqual(
            session.world.trainPathStatusText(of: train, in: .traditionalChinese),
            "不在首站 Alpha：派它到首站"
        )
        // No control turns flexible dispatch on: the text names only what
        // the player can do.
        XCTAssertEqual(session.world.trainPathStatusText(of: train, in: .english), "Not at the first stop Alpha: send it there")

        // With flexible dispatch the line runs it empty to an end instead.
        var flexible = session.world
        flexible.setFlexDispatch(true)
        XCTAssertNotEqual(flexible.lineDispatchHold(of: train), .awayFromFirstStop(firstStop: stops[0]))
    }

    func testATrainAddedToALineRunningOneIsOfferedToRunBoth() throws {
        let (world, stops, first, second) = try lineWorld()
        let session = GameSession(world: world)
        session.selectStation(stops[0])
        session.selectTrain(first)
        session.placeSelectedTrain()
        session.assignTrain(first, toLine: Self.main)
        XCTAssertEqual(session.world.line(id: Self.main)?.trainsInService, TrainsInService(peak: 1, offPeak: 1, low: 1))

        // The first train leaves Alpha; the second is placed there.
        var running = session.world
        for _ in 0..<60 where running.train(id: first)?.execution == nil || running.stationsStoppedAt(by: first).contains(stops[0]) {
            try running.advance(ticks: 1)
        }
        XCTAssertNotNil(running.train(id: first)?.execution)
        XCTAssertFalse(running.stationsStoppedAt(by: first).contains(stops[0]))
        let later = GameSession(world: running)
        later.selectStation(stops[0])
        later.selectTrain(second)
        later.placeSelectedTrain()
        XCTAssertNotNil(later.world.train(id: second)?.position, later.message?.text ?? "")
        later.assignTrain(second, toLine: Self.main)
        XCTAssertEqual(later.message?.kind, .success, later.message?.text ?? "")
        XCTAssertTrue(later.message?.text.contains("tap Run 2 on the train card") == true, later.message?.text ?? "")
        XCTAssertEqual(later.world.line(id: Self.main)?.trainsInService.peak, 1, "assigning keeps the line's counts")

        XCTAssertEqual(later.world.lineDispatchHold(of: second), .serviceFull(running: 1, planned: 1))
        XCTAssertEqual(later.world.trainPathStatusText(of: second, in: .traditionalChinese), "路線只開 1 列：加開到 2 列")
        let unused = try XCTUnwrap(later.world.lineUnusedTrains(ofTrain: second))
        XCTAssertEqual(unused.target, 2)
        XCTAssertNil(later.world.lineUnusedTrains(ofTrain: TrainID(rawValue: 99)))

        later.runAllAssignedTrains(ofTrain: second)
        XCTAssertEqual(later.message?.kind, .success, later.message?.text ?? "")
        XCTAssertEqual(later.world.line(id: Self.main)?.trainsInService, TrainsInService(peak: 2, offPeak: 2, low: 2))
        XCTAssertNil(later.world.lineUnusedTrains(ofTrain: second))
        XCTAssertNotEqual(later.world.lineDispatchHold(of: second), .serviceFull(running: 1, planned: 1))
    }

    func testALevelSetLowerOnPurposeIsNeitherCountedNorRaised() throws {
        var (world, _, first, second) = try lineWorld()
        try world.assignTrain(first, to: Self.main)
        try world.assignTrain(second, to: Self.main)
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 2, offPeak: 2, low: 0))
        XCTAssertNil(world.lineUnusedTrains(ofTrain: second), "the busiest level runs both")

        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 1, offPeak: 1, low: 0))
        let unused = try XCTUnwrap(world.lineUnusedTrains(ofTrain: second))
        XCTAssertEqual(unused.busiest, 1)
        XCTAssertEqual(unused.raised, TrainsInService(peak: 2, offPeak: 2, low: 0), "the quiet level keeps its 0")
    }

    /// A line run to a headway sets its trains by the headway, not by the
    /// counts: running every train by the counts would change nothing, so
    /// it is not offered.
    func testALineRunToAHeadwayIsNotOfferedToRunMoreByTheCounts() throws {
        var (world, _, first, second) = try lineWorld()
        try world.assignTrain(first, to: Self.main)
        try world.assignTrain(second, to: Self.main)
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        XCTAssertNotNil(world.lineUnusedTrains(ofTrain: second), "by the counts it runs one of two")
        try world.setLineTargetHeadways(Self.main, to: TargetHeadways(peak: 60, offPeak: 60, low: 60), pattern: nil)
        XCTAssertNil(world.lineUnusedTrains(ofTrain: second))
    }

    func testTheTrainCardOffersTheLineMenuOnlyForAPlacedTrainWithoutALine() throws {
        let (world, stops, placed, unplaced) = try lineWorld()
        let session = GameSession(world: world)
        session.selectStation(stops[0])
        session.selectTrain(placed)
        session.placeSelectedTrain()
        XCTAssertTrue(session.offersLineMenu(for: placed))
        XCTAssertFalse(session.offersLineMenu(for: unplaced), "an unplaced train would never leave")
        session.assignTrain(placed, toLine: Self.main)
        XCTAssertFalse(session.offersLineMenu(for: placed), "it has a line")
    }
}
