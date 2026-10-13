import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 195 (TestFlight 54.1): what the train card says to
/// do next, the menus that give a train a line, and the warning for single
/// track that holds a line to fewer trains under traffic control.
@MainActor
final class LineGuidanceTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let main = LineID(rawValue: 1)

    /// Alpha, Beta, Gamma and Delta along one single track, a line calling
    /// at all four, running all day, and an unplaced train.
    private func lineWorld() throws -> (GameWorld, TrainID) {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000, speed: .normal)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        try world.setLineServiceWindow(Self.main, to: .allDay)
        let train = try world.purchaseTrain(named: "Train 1").id
        return (world, train)
    }

    private func placed() throws -> (GameWorld, TrainID) {
        var (world, train) = try lineWorld()
        try world.placeTrain(train, at: XCTUnwrap(world.lineJourney(Self.main)).start)
        return (world, train)
    }

    func testAnUnplacedTrainIsToldToBePlaced() throws {
        let (world, train) = try lineWorld()
        XCTAssertEqual(
            world.trainNextStepText(of: train, in: .english),
            "Next: select a station with a free platform, then tap Place Train 1 Here."
        )
        XCTAssertEqual(
            world.trainNextStepText(of: train, in: .traditionalChinese),
            "下一步：選一個月台空著的車站，按「把 Train 1 放在這裡」。"
        )
        XCTAssertNil(world.trainNextStepText(of: TrainID(rawValue: 99), in: .english))
    }

    func testAPlacedTrainWithoutALineIsToldToGetOne() throws {
        var (world, train) = try placed()
        XCTAssertEqual(
            world.trainNextStepText(of: train, in: .english),
            "Next: give it a line with Assign to a Line below or in the Lines panel, or select a station and tap Send Train 1 Here."
        )
        XCTAssertEqual(
            world.trainNextStepText(of: train, in: .traditionalChinese),
            "下一步：用下方的「配屬路線」或在路線面板配屬路線，或選一個車站按「派 Train 1 到這裡」。"
        )
        XCTAssertEqual(world.trainPathStatusText(of: train, in: .english), "Not assigned to a line")
        XCTAssertEqual(world.trainPathStatusText(of: train, in: .traditionalChinese), "未配屬路線")
        XCTAssertEqual(world.train(id: train)?.pathText(in: .english), "No path ahead", "the train's own path text is unchanged")

        try world.assignTrain(train, to: Self.main)
        XCTAssertNil(world.trainNextStepText(of: train, in: .english), "a train with a line needs nothing")
        XCTAssertNotEqual(world.trainPathStatusText(of: train, in: .english), "Not assigned to a line")
    }

    func testTheMenusListTheLinesAndTheTrainsOnTheTrackWithoutALine() throws {
        var (world, train) = try placed()
        let unplaced = try world.purchaseTrain(named: "Train 2").id
        let session = GameSession(world: world)
        XCTAssertEqual(session.lineMenuChoices, [MenuChoice(id: Self.main, title: "Main")])
        XCTAssertEqual(session.unassignedTrainMenuChoices, [MenuChoice(id: train, title: "Train 1")],
                       "the unplaced \(unplaced) is left out: it would never leave")

        session.assignTrain(train, toLine: Self.main)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.assignedLine(of: train), Self.main)
        XCTAssertEqual(session.unassignedTrainMenuChoices, [], "a train on a line is left out")

        // Refused: already on the line; nothing changes.
        let before = session.world
        session.assignTrain(train, toLine: Self.main)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, before)
        session.assignTrain(train, toLine: LineID(rawValue: 9))
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, before)
    }

    /// Decision 61's short single track (`SingleTrackCapacityTests.short`):
    /// two stations with no passing, two trains without traffic control and
    /// one with it.
    private func shortSingleTrack() throws -> (GameWorld, LineID) {
        var world = try GameWorld(bounds: .init(width: 8192, height: 8192), economy: .init(balance: 1_000_000, costs: .init(track: 0, station: 0, train: 0, car: 0)), clock: .init(speed: .normal))
        for x: Int64 in [1024, 3072, 5120] { try world.buildTrackNode(at: .init(x: x, y: 4096)) }
        try world.buildTrackEdge(from: .node(1), to: .node(2))
        try world.buildTrackEdge(from: .node(2), to: .node(3))
        let west = try world.buildStation(named: "W", at: .init(x: 2048, y: 6144)).id
        let east = try world.buildStation(named: "E", at: .init(x: 4096, y: 6144)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 512, to: 1024)
        try world.addTrackPlatform(east, on: .edge(2), from: 512, to: 1024)
        let id = try world.createLine(named: "Single", stops: [west, east]).id
        return (world, id)
    }

    func testSingleTrackUnderTrafficControlWarnsInBothLanguages() throws {
        var (world, main) = try shortSingleTrack()
        XCTAssertNil(world.lineCapacityWarning(main, in: .english), "no warning without traffic control")
        try world.setTrafficControl(true)
        let most = try XCTUnwrap(world.lineMaximumTrains(main))
        let roundTrip = try XCTUnwrap(world.lineJourney(main)).roundTripMinutes
        XCTAssertLessThan(Int64(most), roundTrip / ServiceLine.minimumHeadwayMinutes, "the test needs single track to limit the line")
        let trains = most == 1 ? "train" : "trains"
        XCTAssertEqual(
            world.lineCapacityWarning(main, in: .english),
            "Single track with no passing station: under traffic control the line runs at most \(most) \(trains). Add a second platform track at a station on the way, or double the track."
        )
        XCTAssertEqual(
            world.lineCapacityWarning(main, in: .traditionalChinese),
            "單線又沒有會車站，交通管制下只能跑 \(most) 列：在中間站加第二股月台，或改成雙線。"
        )
        XCTAssertNil(world.lineCapacityWarning(LineID(rawValue: 9), in: .english))

        let session = GameSession(world: world)
        let memo = LinePanelMemo()
        XCTAssertEqual(memo.capacityWarning(main, of: session), world.lineCapacityWarning(main, in: .english))
    }
}
