import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The network tool's planned edits as commands (ARCHITECTURE decision 193,
/// later): the X crossover, the platform track beside a platform and the
/// platform that levels its stretch. Each is logged with its plan, keeps
/// its form through the log's file, and a replay builds the same.
@MainActor
final class NetworkPlanCommandTests: XCTestCase {
    /// Logged without an unrecorded entry, the last entry the command
    /// `matches` takes; kept through the file; replayed to the same world.
    private func assertLoggedAndReplayed(
        _ session: GameSession, _ matches: (PlayerCommand) -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let entries = session.commandLog.entries
        XCTAssertFalse(entries.contains { if case .unrecorded = $0.action { true } else { false } }, "\(entries)", file: file, line: line)
        guard case .command(let command)? = entries.last?.action else { return XCTFail("\(entries)", file: file, line: line) }
        XCTAssertTrue(matches(command), "\(command.name)", file: file, line: line)
        XCTAssertEqual(entries.last?.refused, false, file: file, line: line)
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "57", data: [:]).encoded()
        )
        XCTAssertEqual(report.entries, entries, "the plan keeps its form through the file", file: file, line: line)
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason, file: file, line: line)
        XCTAssertEqual(replay.session.world, session.world, file: file, line: line)
    }

    func testAnXCrossoverIsLoggedWithItsPlan() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        for y in [Int64(4_096), 4_416] {
            let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: y))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: y))
            try world.buildTrackEdge(from: west, to: east)
        }
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsScissors = true
        session.tapNetwork(at: PlanPoint(x: 10_240, y: 4_096), reach: 128)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 4_416), reach: 128)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 2 * 3 + 4)
        try assertLoggedAndReplayed(session) { if case .buildCrossover = $0 { true } else { false } }
    }

    func testADoubleTrackIsLoggedWithItsParallel() throws {
        let world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 2)
        try assertLoggedAndReplayed(session) { if case .buildDoubleTrack = $0 { true } else { false } }
    }

    func testAPassingLoopIsLoggedWithItsPlan() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        try world.buildTrackEdge(from: west, to: east)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.passingLoop)
        session.networkLoopSide = .right
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        try assertLoggedAndReplayed(session) { if case .addPassingLoop = $0 { true } else { false } }
    }

    func testAPlatformTrackIsLoggedWithItsPlan() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 16_384, y: 8_704)).id
        try world.addTrackPlatform(station, on: edge, from: 12_288, to: 18_432)
        let platform = try XCTUnwrap(world.trackPlatforms(of: station).first)
        let session = GameSession(world: world)
        session.addPlatformTrack(beside: platform, layout: .island, side: .right)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.trackPlatforms(of: station).count, 2)
        try assertLoggedAndReplayed(session) { if case .addPlatformTrack = $0 { true } else { false } }
    }

    /// Decision 190's levelling: a stretch on a grade, levelled in the same
    /// edit as the station and its platform.
    func testALevelledPlatformIsLoggedWithItsLevelling() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        let columns = [10, 15]
        let heights = (0..<side).flatMap { _ in (0..<side).map { Int16(columns[min($0, columns.count - 1)]) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 9_216, y: 2_048), reach: 16)
        XCTAssertNotNil(session.networkPlatformGrade, "on a grade")
        let metres = NetworkBuilding.lengthText(try XCTUnwrap(session.networkPlatformLevelling).length, in: .english)
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.contains(" Levelled \(metres) of track for it, for ") == true, session.message?.text ?? "")
        try assertLoggedAndReplayed(session) { command in
            if case .addPlatform(let addition) = command { addition.levelling != nil } else { false }
        }
    }
}
