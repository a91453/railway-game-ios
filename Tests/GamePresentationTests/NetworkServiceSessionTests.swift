import GameCore
import GamePresentation
import XCTest

/// Stage S5 in the app: a train on the track network is sent to a station
/// along `GameWorld.path(from:toStation:length:)`, committed unchanged, and
/// its path, stop, service and line read in words from GameCore's queries,
/// just as on the grid.
///
/// Each test compares the session's world with the same commands applied to
/// GameCore directly.
final class NetworkServiceSessionTests: XCTestCase {
    // Two straight edges east along y = 3072:
    //
    //   a ------- e1 (8192) ------- b ----- e2 (6144) ----- c
    //        [West 1024–5120]           [Halt 0–512][East 2048–5120]
    //
    // West stands at (2560, 3584), East at (12800, 3584), Halt at
    // (9728, 3584); Depot, at (5632, 5632), has no platform on the network.
    // Tram has two cars (1024 long) and stands at West's berth going east:
    // 5120 along e1.
    private static let west = StationID(rawValue: 1)
    private static let east = StationID(rawValue: 2)
    private static let halt = StationID(rawValue: 3)
    private static let depot = StationID(rawValue: 4)
    private static let tram = TrainID(rawValue: 1)
    private static let e1 = TrackEdgeID.edge(1)
    private static let e2 = TrackEdgeID.edge(2)

    private func makeNetworkWorld(rate: Int64 = 0) throws -> GameWorld {
        var world = try makeWorld(width: 16_384, height: 6_144, balance: 1_000_000, speed: .normal)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_072))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 3_072))
        try world.buildTrackEdge(from: a, to: b)
        try world.buildTrackEdge(from: b, to: c)
        try world.buildStation(named: "West", at: PlanPoint(x: 2_560, y: 3_584))
        try world.buildStation(named: "East", at: PlanPoint(x: 12_800, y: 3_584))
        try world.buildStation(named: "Halt", at: PlanPoint(x: 9_728, y: 3_584))
        try world.buildStation(named: "Depot", at: PlanPoint(x: 5_632, y: 5_632))
        try world.addTrackPlatform(Self.west, on: Self.e1, from: 1_024, to: 5_120)
        try world.addTrackPlatform(Self.east, on: Self.e2, from: 2_048, to: 5_120)
        try world.addTrackPlatform(Self.halt, on: Self.e2, from: 0, to: 512)
        try world.purchaseTrain(named: "Tram")
        try world.setTrainCars(Self.tram, to: 2)
        try world.placeTrain(Self.tram, at: .onEdge(TrackTraversal(edge: Self.e1, direction: .forward), offset: 5_120))
        try world.setTrainContinuation(Self.tram, along: [], stoppingAt: 5_120)
        try world.setTrainMovementRate(Self.tram, to: rate)
        return world
    }

    func testSendingANetworkTrainToAStationCommitsGameCoresPathUnchanged() async throws {
        let world = try makeNetworkWorld()
        let start = try XCTUnwrap(world.train(id: Self.tram)?.position)
        // The rest of e1 (3072), then e2 to East's far end going east (5120).
        let path = try XCTUnwrap(world.path(from: start, toStation: Self.east, length: 1_024))
        XCTAssertEqual(path, TrainPath(traversals: [TrackTraversal(edge: Self.e2, direction: .forward)], end: 5_120, distance: 8_192))
        var expected = world
        try expected.setTrainContinuation(Self.tram, along: path.traversals, stoppingAt: path.end)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.selectTrain(Self.tram)
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "No path ahead")
            XCTAssertEqual(session.world.stationStopText(of: Self.tram, in: .english), "Stopped at West")
            session.selectStation(Self.east)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Tram to East, 8192 units along the track. Set a rate to start.")
            )
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "Path: 1 more edge, Edge #2, stopping 5120 units along it")
            XCTAssertNil(session.world.stationStopText(of: Self.tram, in: .english), "a train with a path left is not stopped")
        }
    }

    func testANetworkTrainRunsToThePlatformAndStopsThere() async throws {
        let world = try makeNetworkWorld(rate: 1_024)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTrain(Self.tram)
            session.selectStation(Self.east)
            session.sendSelectedTrain()
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Sent Tram to East, 8192 units along the track."))
            // Five minutes (a tick is 100 ms): 5120 of the 8192 run, 2048
            // into e2.
            session.advance(realElapsed: .milliseconds(500))
            XCTAssertEqual(session.selectedTrain?.positionText(in: .english), "Edge #2 forward, 2048 units along")
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "Path: stops 3072 units ahead")
            session.advance(realElapsed: .milliseconds(500))
            XCTAssertEqual(session.selectedTrain?.positionText(in: .english), "Edge #2 forward, 5120 units along")
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "No path ahead")
            XCTAssertEqual(session.world.stationStopText(of: Self.tram, in: .english), "Stopped at East")
        }
    }

    func testSendingANetworkTrainToAStationItStandsAtChangesNothing() async throws {
        let world = try makeNetworkWorld(rate: 100)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTrain(Self.tram)
            session.selectStation(Self.west)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world, "already at the berth: the same path, ending where it stands")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Tram stops at West."))
        }
    }

    func testNoRouteOnTheNetworkChangesNothing() async throws {
        let world = try makeNetworkWorld(rate: 64)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTrain(Self.tram)
            // A plain point: a train goes only to stations.
            session.tapMap(at: PlanPoint(x: 7_680, y: 1_536), reach: 0)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select the station to send Tram to."))
            // Halt's platform is shorter than the train; Depot has none on
            // the network.
            for station in [Self.halt, Self.depot] {
                session.selectStation(station)
                session.sendSelectedTrain()
                XCTAssertEqual(session.world, world)
            }
            XCTAssertEqual(
                session.message,
                StatusMessage(
                    kind: .failure,
                    text: "No route for Tram to Depot: it needs a platform on the track network as long as the train, that it can reach without turning back. Its path is unchanged."
                )
            )
        }
    }

    func testANetworkServiceReadsItsNextStopAndPunctuality() throws {
        // Stage W2c: a crawl reaching 1 km/h in 100 s and stopping from it
        // in as long needs 561 s for 8192 units (6414 at 17.8 units a
        // second, 360.8 s, and 200 s speeding up and slowing down).
        let crawl = TrainPerformance(acceleration: 10, braking: 10, topSpeed: 1)
        for (performance, late) in [(TrainPerformance.standard, false), (crawl, true)] {
            var world = try makeNetworkWorld(rate: 1_024)
            try world.setTrainPerformance(Self.tram, to: performance)
            try world.setTrainTimetable(Self.tram, to: [
                ScheduledStop(station: Self.west, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 5)),
                ScheduledStop(station: Self.east, arrival: GameTime(minutes: 13), departure: GameTime(minutes: 15)),
            ])
            try world.startTrainService(Self.tram)
            // Stage W2b: starting counts as arriving, so its doors are opening.
            XCTAssertEqual(
                world.trainServiceStatus(of: Self.tram, in: .english),
                TrainServiceStatus(serviceName: nil, stopText: "At West, leaves 00:05", punctuality: .onTime, dwell: .doorsOpening)
            )
            XCTAssertEqual(world.stationStopText(of: Self.tram, in: .english), "Stopped at West")
            // It leaves at 00:05 and is on its way at 00:06.
            try world.advance(ticks: 6)
            XCTAssertEqual(world.trainServiceStatus(of: Self.tram, in: .english), TrainServiceStatus(serviceName: nil, stopText: "Next: East, due 00:13", punctuality: .onTime))
            XCTAssertNil(world.stationStopText(of: Self.tram, in: .english))
            // 8192 in the 480 s the timetable gives the run: there at 00:13.
            // The crawl needs 561 s, to 00:14:21: still on its way, a minute
            // late at 00:14.
            try world.advance(ticks: late ? 8 : 7)
            if late {
                XCTAssertEqual(world.trainServiceStatus(of: Self.tram, in: .english), TrainServiceStatus(serviceName: nil, stopText: "Next: East, due 00:13", punctuality: .late(minutes: 1)))
            } else {
                XCTAssertEqual(
                    world.trainServiceStatus(of: Self.tram, in: .english),
                    TrainServiceStatus(serviceName: nil, stopText: "At East, last stop", punctuality: .onTime, dwell: .doorsOpening)
                )
                XCTAssertEqual(world.stationStopText(of: Self.tram, in: .english), "Stopped at East")
            }
        }
    }

    func testALineOnTheNetworkReadsItsServiceAndSendsItsTrain() throws {
        var world = try makeNetworkWorld(rate: 1_024)
        let line = try world.createLine(named: "Shuttle", stops: [Self.west, Self.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(Self.tram, to: line)
        // The line's own journey is a train of one car's: out 8192 (32 s,
        // √(2 × 8192 × 0.06) = 31.4, Stage W2c), turned where it stands at
        // East (1024 along e2 going west), back 5120 + 7168 = 12288 (39 s,
        // 38.4) to West's far end going west, and 2 minutes at each end:
        // 311 s, planned as 6 minutes.
        XCTAssertEqual(world.lineJourney(line)?.roundTripSeconds, 311)
        XCTAssertEqual(world.lineJourney(line)?.roundTripMinutes, 6)
        let summaries = world.lineServiceSummaries(line, in: .english)
        XCTAssertEqual(summaries.map(\.title), ["All stops West–East"])
        XCTAssertEqual(summaries.first?.levels.map { $0.text(in: .english) }, ["1 train · Every 6 min", "1 train · Every 6 min", "1 train · Every 6 min"])
        XCTAssertEqual(summaries.first?.assigned, 1)
        XCTAssertEqual(summaries.first?.running, 0)
        XCTAssertEqual(world.lineStatusText(line, at: world.clock.now, in: .english), "Low")
        XCTAssertEqual(world.trainServiceStatus(of: Self.tram, in: .english), TrainServiceStatus(serviceName: "Shuttle", stopText: "Waiting to be sent out", punctuality: nil))
        // Sent out at once, and on its way to East.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.lineServiceSummaries(line, in: .english).first?.running, 1)
        let status = try XCTUnwrap(world.trainServiceStatus(of: Self.tram, in: .english))
        XCTAssertEqual(status.serviceName, "Shuttle")
        XCTAssertTrue(status.stopText.hasPrefix("Next: East, due "), status.stopText)
        XCTAssertEqual(status.punctuality, .onTime)
    }
}
