import GameCore
import GamePresentation
import XCTest

/// Stage S3: the continuous track network on the prototype map, a
/// top-down projection of GameCore's world coordinates, and its messages.
final class NetworkDisplayTests: XCTestCase {
    /// A west–east edge of 2048 along row 1 and a three-car train on it.
    private func makeNetworkWorld() throws -> (GameWorld, TrackEdgeID, TrainID) {
        var world = try makeWorld(width: 8, height: 6, balance: 100_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 1_536))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 2_560, y: 1_536))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 4_608, y: 1_536))
        let ab = try world.buildTrackEdge(from: a, to: b)
        let bc = try world.buildTrackEdge(from: b, to: c)
        let train = try world.purchaseTrain(named: "Loop")
        try world.setTrainCars(train.id, to: 3)
        try world.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: bc, direction: .forward), offset: 1_024))
        return (world, ab, train.id)
    }

    func testWorldPointsAreDrawnATileFor1024Units() {
        XCTAssertTrue(MapScale.center(of: WorldCoordinate(x: 1_536, y: 512), tileSize: 32) == (48, 16))
        XCTAssertTrue(MapScale.center(of: WorldCoordinate(centreOf: GridPosition(x: 3, y: 2)), tileSize: 32) == MapScale.center(of: GridPosition(x: 3, y: 2), tileSize: 32))
    }

    func testTrainsOnTheNetworkAreDrawnWhereGameCoreHasThem() throws {
        let (world, ab, id) = try makeNetworkWorld()
        let train = try XCTUnwrap(world.train(id: id))
        let position = try XCTUnwrap(train.position)
        // 1024 along B–C: (3584, 1536), a tile of 32 points for 1024 units.
        XCTAssertTrue(MapScale.center(of: position, in: world, tileSize: 32) == (112, 48))
        XCTAssertTrue(MapScale.facing(of: position, in: world) == (1, 0))
        // Head, B, then the tail 1024 back along A–B.
        let points = MapScale.bodyPoints(of: train, in: world, tileSize: 32)
        XCTAssertEqual(points.map(\.x), [112, 80, 48])
        XCTAssertEqual(points.map(\.y), [48, 48, 48])
        XCTAssertEqual(train.trailEdges, [ab])
        // Without the world there is nothing to place it by.
        XCTAssertTrue(MapScale.center(of: position, tileSize: 32) == (0, 0))
        XCTAssertTrue(MapScale.facing(of: position) == (1, 0))
    }

    func testNetworkPositionsAndRefusalsReadInWords() throws {
        let (world, _, id) = try makeNetworkWorld()
        XCTAssertEqual(world.train(id: id)?.positionText, "Edge #2 forward, 1024 units along")
        XCTAssertEqual(GameError.unknownTrackNode(.node(7)).playerMessage, "Node #7 is not a node of the track network.")
        XCTAssertEqual(GameError.unknownTrackEdge(.edge(3)).playerMessage, "Edge #3 is not an edge of the track network.")
        XCTAssertEqual(GameError.trackNodeInUse(.node(2)).playerMessage, "Track still ends at node #2. Remove that track first.")
        XCTAssertEqual(GameError.trackEdgeInUse(.edge(2)).playerMessage, "A train is on edge #2. Take the train off the track first.")
        XCTAssertFalse(GameError.invalidTrackGeometry.playerMessage.isEmpty)
        XCTAssertEqual(TrackNodeID.tile(GridPosition(x: 1, y: 2)).displayText, "Tile (1, 2)")
        XCTAssertEqual(TrackEdgeID.link(GridPosition(x: 1, y: 2), GridPosition(x: 2, y: 2)).displayText, "Link (1, 2)–(2, 2)")
    }
}
