import GameCore
import GamePresentation
import XCTest

/// Stages S3 and S4: the continuous track network on the prototype map, a
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
        XCTAssertTrue(MapScale.center(of: WorldCoordinate(centreOf: GridPosition(x: 3, y: 2)), tileSize: 32) == (112, 80), "a tile's centre")
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

    func testTrainsOffTheGroundAreDrawnWhereTheyAreSeenFromAbove() throws {
        var world = try makeWorld(width: 8, height: 6, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 1_536, z: 512))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_656, y: 1_536, z: 512))
        let viaduct = try world.buildTrackEdge(from: a, to: b, structure: .elevated)
        let train = try world.purchaseTrain(named: "High")
        try world.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: viaduct, direction: .forward), offset: 1_024))
        let position = try XCTUnwrap(world.train(id: train.id)?.position)
        // Height does not move a point seen from above.
        XCTAssertTrue(MapScale.center(of: position, in: world, tileSize: 32) == (48, 48))
        XCTAssertTrue(MapScale.center(of: WorldCoordinate(x: 1_536, y: 1_536, z: 512), tileSize: 32) == (48, 48))
    }

    func testNetworkPositionsAndRefusalsReadInWords() throws {
        let (world, _, id) = try makeNetworkWorld()
        XCTAssertEqual(world.train(id: id)?.positionText(in: .english), "Edge #2 forward, 1024 units along")
        XCTAssertEqual(GameError.unknownTrackNode(.node(7)).playerMessage(in: .english), "Node #7 is not a node of the track network.")
        XCTAssertEqual(GameError.unknownTrackEdge(.edge(3)).playerMessage(in: .english), "Edge #3 is not an edge of the track network.")
        XCTAssertEqual(GameError.trackNodeInUse(.node(2)).playerMessage(in: .english), "Track still ends at node #2. Remove that track first.")
        XCTAssertEqual(GameError.trackEdgeInUse(.edge(2)).playerMessage(in: .english), "A train is on edge #2. Take the train off the track first.")
        XCTAssertFalse(GameError.invalidTrackGeometry.playerMessage(in: .english).isEmpty)
        // Stage S4: grades, structures, clearance and platforms.
        XCTAssertEqual(GameError.trackConflict(.edge(4)).playerMessage(in: .english), "That track would cross edge #4 without 8 m between them. Pass over or under it, or cross at a shared node.")
        XCTAssertEqual(GameError.trackEdgeHasPlatform(.edge(5)).playerMessage(in: .english), "A station has a platform on edge #5. Remove the platform first.")
        // Stage F2: the track spacing.
        XCTAssertEqual(GameError.trackTooClose(.edge(6)).playerMessage(in: .english), "That track would run less than 4 m beside edge #6. Keep parallel tracks 4 m apart, centre to centre, or pass 8 m over or under.")
        XCTAssertEqual(GameError.trackTooClose(.edge(6)).playerMessage(in: .traditionalChinese), "這段軌道與軌段 #6並行時距離不到 4 公尺。平行的軌道中心之間至少要 4 公尺，或上下相差 8 公尺。")
        XCTAssertEqual(GameError.tracksWouldBeTooClose(.edge(6), .edge(7)).playerMessage(in: .english), "Without that track, edge #6 and edge #7 would run less than 4 m apart with no junction near. Remove one of them first.")
        for error in [GameError.trackTooSteep, .invalidTrackStructure, .invalidPlatform] {
            XCTAssertFalse(error.playerMessage(in: .english).isEmpty)
        }
        XCTAssertEqual(TrackNodeID.node(1).displayText(in: .english), "Node #1")
        XCTAssertEqual(TrackEdgeID.edge(2).displayText(in: .english), "Edge #2")
    }
}
