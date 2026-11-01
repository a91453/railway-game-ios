import Foundation
@testable import GameCore
import XCTest

/// Decision 515: mountain track, steeper than 40 in 1000 up to 70, laid
/// only as a real mountain line is traced, run only by a mountain train
/// and no faster than its grade allows.
final class MountainTrackTests: XCTestCase {
    private let line = LineID(rawValue: 1)

    private func makeWorld() throws -> GameWorld {
        try GameWorld(
            bounds: WorldBounds(width: 65_536, height: 65_536),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
    }

    private func refused(_ expected: GameError, in world: GameWorld, file: StaticString = #filePath, line: UInt = #line, _ body: (inout GameWorld) throws -> Void) {
        var copy = world
        do {
            try body(&copy)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GameError, expected, file: file, line: line)
            XCTAssertEqual(copy, world, "a refused command changes nothing", file: file, line: line)
        }
    }

    /// Station A on 64 m of level track, 64 m climbing 4 m (62.5 in 1000,
    /// the Alishan Forest Railway's ruling grade) on a viaduct, station B
    /// on 64 m of level viaduct at the top, and line A–B all day. As
    /// ordinary track, the climb is 2.5 m (39 in 1000).
    private func build(mountain: Bool = true) throws -> (world: GameWorld, climb: TrackEdgeID, first: TrackEdgeID) {
        var world = try makeWorld()
        let top: Int64 = mountain ? 256 : 160
        let points = [
            WorldCoordinate(x: 2_048, y: 2_048), WorldCoordinate(x: 6_144, y: 2_048),
            WorldCoordinate(x: 10_240, y: 2_048, z: top), WorldCoordinate(x: 14_336, y: 2_048, z: top),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        let climb = try world.buildTrackEdge(from: nodes[1], to: nodes[2], structure: .elevated, mountain: mountain)
        let last = try world.buildTrackEdge(from: nodes[2], to: nodes[3], structure: .elevated)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 4_096, y: 2_560)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 12_288, y: 2_560)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Mountain", stops: [a, b])
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        return (world, climb, first)
    }

    // MARK: - Building

    func testTracingAnAlishanGradeLaysMountainTrack() throws {
        let (world, climb, first) = try build()
        let edge = try XCTUnwrap(world.network.edge(climb))
        XCTAssertTrue(edge.mountain)
        XCTAssertEqual(world.trackGeometry(of: climb)?.steepestGrade, TrackGrade(rise: 1, run: 16))
        XCTAssertEqual(edge.maximumGrade, TrackProfile.maximumMountainGrade)
        XCTAssertEqual(world.network.edge(first)?.mountain, false)
        XCTAssertTrue(world.lineRunsOnMountainTrack(line))
    }

    func testAPlayerDrawnAlishanGradeIsRefused() throws {
        var world = try makeWorld()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048, z: 256))
        refused(.trackTooSteep, in: world) { _ = try $0.buildTrackEdge(from: a, to: b, structure: .elevated) }
        refused(.trackTooSteep, in: world) { _ = try $0.buildTrackEdges([TrackEdgePlan(from: a, to: b, structure: .elevated)]) }
        _ = try world.buildTrackEdges([TrackEdgePlan(from: a, to: b, structure: .elevated, mountain: true)])
    }

    func testMountainTrackStopsAtSeventyInAThousand() throws {
        var world = try makeWorld()
        // 288 over 4096 is 70.3 in 1000; 286 is 69.8.
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048, z: 288))
        refused(.trackTooSteep, in: world) { _ = try $0.buildTrackEdge(from: a, to: b, structure: .elevated, mountain: true) }
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 3_072, z: 286))
        _ = try world.buildTrackEdge(from: a, to: c, structure: .elevated, mountain: true)
    }

    func testAMountainEdgeSplitsOnlyWhereATurnoutMayStand() throws {
        let (world, climb, _) = try build()
        // A turnout stands on no more than 25 in 1000 (decision 233).
        refused(.turnoutTooSteep, in: world) { _ = try $0.splitTrackEdge(climb, at: 2_048) }
    }

    // MARK: - Speed

    func testTheGradeSetsTheSpeedLimit() {
        XCTAssertEqual(MountainTrack.speed(grade: .level), 85)
        XCTAssertEqual(MountainTrack.speed(grade: TrackProfile.maximumGrade), 45)
        XCTAssertEqual(MountainTrack.speed(grade: TrackGrade(rise: 50, run: 1_000)), 35)
        XCTAssertEqual(MountainTrack.speed(grade: TrackGrade(rise: 625, run: 10_000)), 20)
        XCTAssertEqual(MountainTrack.speed(grade: TrackGrade(rise: -625, run: 10_000)), 20, "down as up")
        XCTAssertEqual(MountainTrack.speed(grade: TrackProfile.maximumMountainGrade), 15)
        XCTAssertEqual(MountainTrack.speed(grade: TrackGrade(rise: 1, run: 1)), CurveSpeedLimit.lowest)
    }

    func testAMountainEdgeIsLimitedOverItsLength() throws {
        let (world, climb, first) = try build()
        let length = try XCTUnwrap(world.trackGeometry(of: climb)?.length)
        XCTAssertEqual(world.network.edge(climb)?.speedLimits, [TrackSpeedLimit(start: 0, end: length, speed: 20)])
        XCTAssertEqual(world.network.edge(first)?.speedLimits, [])
    }

    // MARK: - Trains

    func testOnlyAMountainTrainRunsOnTheLine() throws {
        var (world, _, first) = try build()
        let ordinary = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(ordinary, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        refused(.trainCannotClimb(ordinary), in: world) { try $0.assignTrain(ordinary, to: line) }

        let alishan = try world.purchaseTrain(named: "Alishan", as: .alishan).id
        XCTAssertTrue(try XCTUnwrap(world.train(id: alishan)).climbsMountains)
        try world.assignTrain(alishan, to: line)
        // Unplaced, it may change type, but not to one that cannot climb.
        refused(.trainCannotClimb(alishan), in: world) { try $0.setTrainType(alishan, to: nil) }
        refused(.trainCannotClimb(alishan), in: world) { try $0.setTrainType(alishan, to: .a) }
    }

    func testAnyTrainRunsOnAnOrdinaryLine() throws {
        var (world, _, first) = try build(mountain: false)
        XCTAssertFalse(world.lineRunsOnMountainTrack(line))
        let ordinary = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(ordinary, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.assignTrain(ordinary, to: line)
    }

    // Decision 515 continued (ALISHAN2): placing, sending and lines whose
    // way moves onto mountain track.

    func testATrainThatCannotClimbIsNotPlacedOnMountainTrack() throws {
        var (world, climb, _) = try build()
        let ordinary = try world.purchaseTrain(named: "Blue").id
        refused(.trainCannotClimb(ordinary), in: world) {
            try $0.placeTrain(ordinary, at: .onEdge(TrackTraversal(edge: climb, direction: .forward), offset: 2_048))
        }
        // Its head past the top, the body of its three cars still on the climb.
        try world.setTrainCars(ordinary, to: 3)
        let last = try XCTUnwrap(world.network.edges.last?.id)
        refused(.trainCannotClimb(ordinary), in: world) {
            try $0.placeTrain(ordinary, at: .onEdge(TrackTraversal(edge: last, direction: .forward), offset: 1))
        }
        let alishan = try world.purchaseTrain(named: "Alishan", as: .alishan).id
        try world.placeTrain(alishan, at: .onEdge(TrackTraversal(edge: climb, direction: .forward), offset: 2_048))
    }

    func testATrainThatCannotClimbIsNotSentOntoMountainTrack() throws {
        var (world, climb, first) = try build()
        let ordinary = try world.purchaseTrain(named: "Blue").id
        let alishan = try world.purchaseTrain(named: "Alishan", as: .alishan).id
        try world.placeTrain(ordinary, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 2_048))
        try world.placeTrain(alishan, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        let up = TrackTraversal(edge: climb, direction: .forward)
        refused(.trainCannotClimb(ordinary), in: world) { try $0.setTrainContinuation(ordinary, along: [up]) }
        try world.setTrainContinuation(ordinary, along: [], stoppingAt: 3_072)
        try world.setTrainContinuation(alishan, along: [up])
    }

    func testALineMovedOntoMountainTrackKeepsOnlyItsMountainTrains() throws {
        var world = try makeWorld()
        let points = [
            WorldCoordinate(x: 2_048, y: 2_048), WorldCoordinate(x: 6_144, y: 2_048),
            WorldCoordinate(x: 10_240, y: 2_048, z: 256), WorldCoordinate(x: 14_336, y: 2_048, z: 256),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        let last = try world.buildTrackEdge(from: nodes[2], to: nodes[3], structure: .elevated)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 4_096, y: 2_560)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 12_288, y: 2_560)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Mountain", stops: [a, b])
        // A and B are not joined yet: any train may be given the line.
        XCTAssertFalse(world.lineRunsOnMountainTrack(line))
        let ordinary = try world.purchaseTrain(named: "Blue").id
        let alishan = try world.purchaseTrain(named: "Alishan", as: .alishan).id
        try world.assignTrain(ordinary, to: line)
        try world.assignTrain(alishan, to: line)
        XCTAssertEqual(world.line(id: line)?.trains, [ordinary, alishan])

        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2], structure: .elevated, mountain: true)
        XCTAssertTrue(world.lineRunsOnMountainTrack(line))
        XCTAssertEqual(world.line(id: line)?.trains, [alishan], "the train that cannot climb is taken off")
        XCTAssertNil(world.assignedLine(of: ordinary))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "the world still loads")
    }

    // MARK: - Saving

    func testMountainTrackIsSavedOnlyWhereItIs() throws {
        let (world, _, _) = try build()
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "\"mountain\":true").count, 2, "only the climbing edge says so")
        XCTAssertFalse(text.contains("\"mountain\":false"))
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertEqual(loaded, world)

        let plain = String(decoding: try JSONEncoder().encode(try build(mountain: false).world), as: UTF8.self)
        XCTAssertFalse(plain.contains("mountain"), "a world before decision 515 reads the same")
    }

    func testASavedSteepEdgeWithoutTheMarkIsRejected() throws {
        let (world, _, _) = try build()
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
            .replacingOccurrences(of: "\"mountain\":true", with: "\"mountain\":false")
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)))
    }

    /// Save version 77: the world of ``build(mountain:)`` with an Alishan
    /// train placed at A and assigned to the line.
    func testVersionSeventySevenKeepsMountainTrack() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v77-mountain-track.json")
        var (made, climb, first) = try build()
        let train = try made.purchaseTrain(named: "Alishan", as: .alishan).id
        try made.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try made.assignTrain(train, to: line)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MOUNTAIN_TRACK_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 77)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertEqual(loaded.network.edge(climb)?.mountain, true)
        XCTAssertEqual(loaded.network.edge(climb)?.speedLimits.map(\.speed), [20])
        XCTAssertEqual(loaded.train(id: train)?.type, .alishan)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 77,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
