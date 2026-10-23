import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// PLAYER_FEEDBACK 80.1 #1, the network tool's half: the double-track
/// preview froze an iPad because it was worked out again at every tick
/// (``DoubleTrackUpgradeTests``). The network tool's previews (the track,
/// a passing loop, a depot, a platform's levelling) were kept the same way,
/// until the world changed; the tool pauses the game, but a player who
/// presses play with a draft open had each one worked out at every tick.
/// Game time moving on now leaves them as they are, and ✓ plans the build
/// once more on the world it builds in.
@MainActor
final class BuildPreviewTickTests: XCTestCase {
    /// Reads `preview` while 30 ticks run at 10×: it is worked out once,
    /// not at every tick, and ✓ still builds.
    private func assertKeptWhileTimeRuns<Preview>(
        _ session: GameSession, preview: (GameSession) -> Preview?, build: (GameSession) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        session.setSpeed(.x10)
        XCTAssertNotNil(preview(session), file: file, line: line)
        let workedOut = session.buildPreviewsWorkedOut
        let start = session.world.clock.now
        for _ in 0..<30 {
            session.advance(ticks: 1)
            XCTAssertNotNil(preview(session), file: file, line: line)
        }
        XCTAssertGreaterThan(session.world.clock.now, start, "game time ran", file: file, line: line)
        XCTAssertEqual(session.buildPreviewsWorkedOut, workedOut, "worked out once, not at every tick", file: file, line: line)
        build(session)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "", file: file, line: line)
    }

    /// A straight single track with stations at its ends.
    private func singleTrack() throws -> GameWorld {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 29_696, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 4_096)
        try world.addTrackPlatform(east, on: edge, from: 26_624, to: 29_696)
        return world
    }

    func testTheTrackPreviewIsKeptWhileTimeRuns() throws {
        let session = GameSession(world: try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused))
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 16)
        assertKeptWhileTimeRuns(session, preview: { $0.networkPreview }, build: { $0.buildNetworkTrack() })
    }

    func testThePassingLoopPreviewIsKeptWhileTimeRuns() throws {
        let session = GameSession(world: try singleTrack())
        session.selectTool(.network)
        session.setNetworkMode(.passingLoop)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        assertKeptWhileTimeRuns(session, preview: { $0.networkLoopPreview }, build: { $0.addPassingLoop() })
    }

    /// The cash a tick brings in or pays out crossing the price works it
    /// out once more, so ✓ opens once the cash covers it and the preview
    /// says why not once it does not.
    func testCashCrossingThePriceWorksItOutAgain() throws {
        let session = GameSession(world: try singleTrack())
        session.selectTool(.network)
        session.setNetworkMode(.passingLoop)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.setSpeed(.x10)
        let price = try XCTUnwrap(session.networkLoopPreview?.cost)
        XCTAssertNil(session.networkLoopPreview?.problem)
        let workedOut = session.buildPreviewsWorkedOut

        try tick(session, cash: Money(price.amount - 100))
        XCTAssertNotNil(session.networkLoopPreview?.problem, "short of cash now")
        XCTAssertEqual(session.buildPreviewsWorkedOut, workedOut + 1)
        try tick(session, cash: Money(price.amount - 50))
        XCTAssertNotNil(session.networkLoopPreview?.problem)
        XCTAssertEqual(session.buildPreviewsWorkedOut, workedOut + 1, "still short: kept")

        try tick(session, cash: Money(price.amount + 100))
        XCTAssertNil(session.networkLoopPreview?.problem, "the cash covers it again")
        XCTAssertEqual(session.buildPreviewsWorkedOut, workedOut + 2)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
    }

    /// One tick of the game loop, after which the cash in hand is `cash`.
    private func tick(_ session: GameSession, cash: Money) throws {
        let tick = try XCTUnwrap(session.beginLoopTick())
        var step = try GameSession.advanced(tick.world, by: 1, listening: false)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(step.world)) as? [String: Any])
        var economy = try XCTUnwrap(json["economy"] as? [String: Any])
        economy["balance"] = cash.amount
        json["economy"] = economy
        step.world = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(session.finish(tick, with: .success(step)))
        XCTAssertEqual(session.world.economy.balance, cash)
    }

    func testTheDepotPreviewIsKeptWhileTimeRuns() throws {
        var world = try makeWorld(width: 65_536, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        try world.buildTrackEdge(from: a, to: b)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        session.tapNetwork(at: PlanPoint(x: 16_400, y: 8_200), reach: 64)
        assertKeptWhileTimeRuns(session, preview: { $0.networkDepotPreview }, build: { $0.addDepotYard() })
    }

    func testThePlatformLevellingIsKeptWhileTimeRuns() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000), costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        let heights = (0..<side).flatMap { _ in (0..<side).map { Int16($0 == 0 ? 10 : 15) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 9_216, y: 2_048), reach: 16)
        session.stationName = "Dazhi"
        assertKeptWhileTimeRuns(session, preview: { $0.networkPlatformLevelling?.cost }, build: { $0.addNetworkPlatform() })
    }
}
