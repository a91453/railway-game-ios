import GameCore
import GamePresentation
import XCTest

/// Trains of several cars through the session (Stage S2): each action is
/// one `GameWorld` command, and the texts are derived from the world.
/// Stage F3c moved them onto the track network; growing a station onto a
/// tile went with the grid.
final class StationFacilitySessionTests: XCTestCase {
    //   row 0:        .  W  .  .  C  .
    //   row 1:  o - o - o - o - o ---- o      nodes 1–6 at columns 0–4 and 6
    //
    // Edges 1–4 join columns 0 to 4, 1024 each; edge 5 runs from column 4
    // to 6, 2048 long. West (W) has a platform along all of edge 3, Central
    // (C) one along all of edge 5.
    private static func makeLine() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 7_168, height: 3_072), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        for x in [0, 1, 2, 3, 4, 6] {
            let centre = TestLine.centre(x, 1)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
        for node in 1...5 {
            try world.buildTrackEdge(from: .node(node), to: .node(node + 1))
        }
        let west = try world.buildStation(named: "West", at: TestLine.centre(2, 0)).id
        try world.addTrackPlatform(west, on: .edge(3), from: 0, to: 1_024)
        let central = try world.buildStation(named: "Central", at: TestLine.centre(5, 0)).id
        try world.addTrackPlatform(central, on: .edge(5), from: 0, to: 2_048)
        return world
    }

    func testCarsAreSetOffTheTrackAndALongTrainIsSentToAPlatformItFits() async throws {
        let world = try Self.makeLine()
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.purchaseTrain()
            XCTAssertEqual(session.selectedTrain?.carsText(in: .english), "1 car")

            session.setSelectedTrainCars(2)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Train 1 now has 2 cars."))
            XCTAssertEqual(session.selectedTrain?.carsText(in: .english), "2 cars")
            session.setSelectedTrainCars(17)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "A train has 1 to 16 cars."))

            // Facing east at West: its head at the end of edge 3, its
            // second car at the start of edge 3, the whole of it on the
            // platform.
            session.setPlacementHeading(.east)
            session.selectStation(StationID(rawValue: 1))
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Placed Train 1 at West, on edge #3 going forward."))
            XCTAssertEqual(session.selectedTrain?.position, .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 1_024))
            XCTAssertEqual(session.selectedTrain?.trailEdges, [])
            session.setSelectedTrainCars(3)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Train #1 is already on the track."))

            // To Central: along edge 4, then all of edge 5, so both cars
            // stand on its platform.
            session.selectStation(StationID(rawValue: 2))
            session.applyTool()
            XCTAssertEqual(session.selectedTrain?.movement.edges, [.edge(4), .edge(5)])
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Sent Train 1 to Central, 3072 units along the track. Set a rate to start."))
        }
    }

    func testAStopTellsWhenThePlatformIsTooShort() throws {
        var world = try Self.makeLine()
        let id = try world.purchaseTrain(named: "Long").id
        // Three cars, 2048 from head to tail: West's platform holds half.
        try world.setTrainCars(id, to: 3)
        try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 1_024))
        XCTAssertEqual(world.stationStopText(of: id, in: .english), "Stopped at West · the platform is too short for all its cars")

        try world.unplaceTrain(id)
        try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(5), direction: .forward), offset: 2_048))
        XCTAssertEqual(world.stationStopText(of: id, in: .english), "Stopped at Central")
    }

    /// The body is drawn from the head along the edges to the tail.
    func testTheBodyIsDrawnBackToTheTail() throws {
        var world = try Self.makeLine()
        let id = try world.purchaseTrain(named: "Long").id
        XCTAssertTrue(MapScale.bodyPoints(of: try XCTUnwrap(world.train(id: id)), in: world, referenceSize: 10).isEmpty)
        try world.setTrainCars(id, to: 3)
        // 1024 along edge 5: the head at x 5632, the node at 4608, and the
        // tail 2048 back at the node at 3584.
        try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(5), direction: .forward), offset: 1_024))
        let points = MapScale.bodyPoints(of: try XCTUnwrap(world.train(id: id)), in: world, referenceSize: 10)
        XCTAssertEqual(points.map(\.x), [55, 45, 35])
        XCTAssertEqual(points.map(\.y), [15, 15, 15])
    }
}
