import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 204: tap a single track, and a passing loop goes beside it with
/// a signal station, closed to passengers, that has a platform on each
/// track; a line that stops there may run a train each way.
@MainActor
final class PassingLoopSessionTests: XCTestCase {
    /// A straight single track 480 m long west to east, with stations West
    /// and East at its ends.
    private func world() throws -> (GameWorld, west: StationID, east: StationID) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 29_696, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 4_096)
        try world.addTrackPlatform(east, on: edge, from: 26_624, to: 29_696)
        return (world, west, east)
    }

    private func session(_ world: GameWorld) -> GameSession {
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.passingLoop)
        return session
    }

    /// With real car lengths (decision 227) and no train bought yet, the
    /// shortest loop still holds six of the 20 m cars the company will buy.
    func testTheShortestLoopHoldsSixCarsOfTheLengthTrainsWillHave() throws {
        var (world, _, _) = try world()
        XCTAssertEqual(session(world).passingLoopLength, 6 * Train.carLength)
        world.setRealCarLengths(true)
        XCTAssertEqual(session(world).passingLoopLength, 6 * Train.realStandardCarLength)
    }

    func testATapOnSingleTrackAddsALoopAndASignalStation() throws {
        let (world, _, _) = try world()
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        XCTAssertEqual(session.edgeSideText(.left, at: try XCTUnwrap(session.networkEdgePoint)), "north side")
        let preview = try XCTUnwrap(session.networkLoopPreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        let cost = try XCTUnwrap(preview.cost)
        XCTAssertGreaterThan(preview.points.count, 2)
        XCTAssertEqual(session.networkOverlay?.preview, preview.points)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - cost)
        XCTAssertNil(session.networkEdgePoint)

        let after = session.world
        let signal = try XCTUnwrap(after.stations.first { $0.name == "Signal 1" })
        XCTAssertEqual(signal.operationMode, .closed)
        let platforms = after.trackPlatforms(of: signal.id)
        XCTAssertEqual(platforms.count, 2, "one on each track")
        XCTAssertEqual(Set(platforms.map(\.edge)).count, 2)
        for platform in platforms {
            XCTAssertGreaterThanOrEqual(platform.end - platform.start, Int64(PassingLoopPlan.minimumCars) * Train.carLength - 16)
        }
        // The loop: 5 m north, joined by a turnout at each end.
        let loop = try XCTUnwrap(platforms.first { $0.start == 0 })
        let along = try XCTUnwrap(after.network.edge(loop.edge))
        XCTAssertEqual(after.network.node(along.from)?.position.y, 8_192 - 320)
        let turnouts = after.network.nodes.filter { $0.ends.count == 3 }
        XCTAssertEqual(turnouts.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(after)), after)
    }

    /// Handoff §7.1 (PR401_525 §5): the number came from counting closed
    /// stations, so a station the player closed, or a signal station
    /// demolished, gave the next loop a name already in use.
    func testTheSignalStationTakesTheNextNumberNotInUse() throws {
        var (world, west, _) = try world()
        let second = try world.buildStation(named: "Signal 2", at: PlanPoint(x: 9_000, y: 9_000)).id
        try world.setStationOperationMode(second, to: .closed)
        try world.setStationOperationMode(west, to: .closed)
        XCTAssertEqual(session(world).signalStationName(), "Signal 3", "two closed: West and Signal 2")
        var renamed = world
        try renamed.setStationOperationMode(west, to: .normalFlow)
        XCTAssertEqual(session(renamed).signalStationName(), "Signal 3", "Signal 1 was demolished; Signal 2 stands")
        let chinese = GameSession(world: renamed, language: .traditionalChinese)
        XCTAssertEqual(chinese.signalStationName(), "號誌站 3", "either language's names count")
    }

    /// The point of it: a line from West to East keeps one train on the
    /// single track; stopping at the signal station, two (decision 61).
    func testALineThatStopsAtTheSignalStationRunsTwoTrains() throws {
        var (world, west, east) = try world()
        try world.setTrafficControl(true)
        let line = try world.createLine(named: "Single", stops: [west, east]).id
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        XCTAssertEqual(world.lineTrainsInService(line, at: .peak), 1)
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        var after = session.world
        let signal = try XCTUnwrap(after.stations.first { $0.operationMode == .closed }).id
        XCTAssertEqual(after.lineTrainsInService(line, at: .peak), 1, "not a stop yet")
        try after.setLineStops(line, to: [west, signal, east])
        XCTAssertEqual(after.lineTrainsInService(line, at: .peak), 2)
    }

    func testTooShortATrackIsRefused() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 8_192))
        try world.buildTrackEdge(from: a, to: b)
        let session = session(world)
        session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 64)
        XCTAssertNotNil(session.networkLoopPreview?.problem)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)
    }
}
