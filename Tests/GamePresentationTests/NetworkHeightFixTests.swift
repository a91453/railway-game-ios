import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 629: the build card's heights. A stretch refused over water
/// gets a fix that raises it onto a bridge and one that takes it into a
/// tunnel, each what ✓ then builds; the +/- moves the new end a metre a
/// tap and the preview's cost follows; a stretch between two nodes says
/// it cannot move.
@MainActor
final class NetworkHeightFixTests: XCTestCase {
    /// Flat ground at 0 m with a lake on cell column 2 of the first row:
    /// track along y = 2,048 from x = 1,024 to 17,408 (256 m) crosses it
    /// between 112 m and 176 m.
    private func lakeSession() throws -> GameSession {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000), costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: Array(repeating: 0, count: side * side))!])
        try world.setWater([CellPosition(row: 0, column: 2)])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.networkSnapsToTrack = false
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        return session
    }

    func testWaterOffersABridgeAndATunnelThatBuild() throws {
        let session = try lakeSession()
        let refused = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(refused.refusal, .trackOverWater)
        XCTAssertNil(refused.cost)
        let card = try XCTUnwrap(session.networkHeightCard)
        XCTAssertEqual(card.adjusts, .end)
        XCTAssertEqual(card.label, "End on the ground")
        XCTAssertEqual(card.fixes.count, 2, "one up, one down")
        let up = try XCTUnwrap(card.fixes.first { $0.change > 0 })
        let down = try XCTUnwrap(card.fixes.first { $0.change < 0 })
        XCTAssertEqual(up.kind, .bridge)
        XCTAssertEqual(down.kind, .tunnel)
        // The whole stretch 4 m up is the cheapest bridge, and 10 m down
        // the only tunnel the grade allows.
        XCTAssertEqual(up.ends, .both)
        XCTAssertEqual(up.change, 4 * WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(down.ends, .both)
        XCTAssertEqual(down.change, -10 * WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(up.title(in: .english), "Raise both ends 4 m: bridge")
        XCTAssertEqual(down.title(in: .traditionalChinese), "兩端降低 10 公尺，走隧道")
        // A phone on its side: the short words beside the arrow.
        XCTAssertEqual(up.shortTitle(in: .english), "4 m, bridge")
        XCTAssertEqual(down.shortTitle(in: .traditionalChinese), "10 公尺，走隧道")
        for fix in card.fixes {
            let trying = try lakeSession()
            trying.applyNetworkHeightFix(fix)
            let preview = try XCTUnwrap(trying.networkPreview)
            XCTAssertNil(preview.problem, "\(fix)")
            XCTAssertEqual(preview.cost, fix.cost, "the card's price is the preview's")
            let balance = trying.world.economy.balance
            trying.buildNetworkTrack()
            XCTAssertEqual(trying.message?.kind, .success, trying.message?.text ?? "")
            XCTAssertEqual(balance.amount - trying.world.economy.balance.amount, fix.cost.amount, "✓ costs what the fix said")
        }
    }

    func testPlusAndMinusMoveTheEndAndThePreviewFollows() throws {
        let session = try lakeSession()
        session.raiseNetworkEnd(by: 1)
        XCTAssertEqual(session.networkEndRaise, WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(session.networkStartRaise, 0)
        XCTAssertEqual(session.networkHeightCard?.label, "End 1 m above the ground")
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(preview.endHeight - preview.startHeight, WorldCoordinate.unitsPerMetre)
        session.raiseNetworkEnd(by: -3)
        XCTAssertEqual(session.networkHeightCard?.label, "End 2 m underground")
        // Picking the end again starts it from the ground.
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 2_048), reach: 16)
        XCTAssertEqual(session.networkEndRaise, 0)
    }

    func testABuildableStretchHasNoFixButKeepsTheControl() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000), costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: Array(repeating: 0, count: side * side))!])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        let card = try XCTUnwrap(session.networkHeightCard)
        XCTAssertNil(session.networkPreview?.problem)
        XCTAssertTrue(card.fixes.isEmpty)
        XCTAssertNil(card.note)
        // Raised 10 m, the stretch costs more (a viaduct at its end).
        let flat = try XCTUnwrap(session.networkPreview?.cost)
        session.raiseNetworkEnd(by: 10)
        let raised = try XCTUnwrap(session.networkPreview?.cost)
        XCTAssertGreaterThan(raised.amount, flat.amount)
    }

    /// Ground climbing 5 m every 64 m: the stretch would be steeper than
    /// track may be, and a fix takes it under or over the hill.
    func testASteepHillOffersAFixThatBuilds() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000), costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        let heights = (0..<side).flatMap { _ in (0..<side).map { Int16(min($0, 4) * 5) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        XCTAssertEqual(session.networkPreview?.refusal, .trackTooSteep)
        let card = try XCTUnwrap(session.networkHeightCard)
        XCTAssertFalse(card.fixes.isEmpty)
        for fix in card.fixes {
            session.applyNetworkHeightFix(fix)
            XCTAssertNil(session.networkPreview?.problem, "\(fix)")
            XCTAssertEqual(session.networkPreview?.cost, fix.cost)
        }
    }

    /// Between two nodes already built no end can move: the card says so.
    func testTwoNodesSayTheyCannotMove() throws {
        let session = try lakeSession()
        // Both ends built on dry land either side of the lake, then the
        // stretch between them drawn.
        var world = session.world
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: 2_048, z: 0))
        let between = GameSession(world: world)
        between.selectTool(.network)
        between.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        between.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        XCTAssertEqual(between.networkStart, .node(a))
        XCTAssertEqual(between.networkEnd, .node(b))
        XCTAssertEqual(between.networkPreview?.refusal, .trackOverWater)
        let card = try XCTUnwrap(between.networkHeightCard)
        XCTAssertTrue(card.label.isEmpty, "no +/-")
        XCTAssertTrue(card.note?.hasPrefix("Both ends are on track already") == true)
    }

    /// The screenshot scene: its stretch across the river is refused and
    /// the card offers a bridge and a tunnel.
    func testTheScreenshotSceneShowsBothFixes() throws {
        let session = GameSession(world: ScreenshotScene.trackHeight.make(in: .traditionalChinese))
        ScreenshotScene.trackHeight.prepare(session)
        XCTAssertEqual(session.networkPreview?.refusal, .trackOverWater)
        let card = try XCTUnwrap(session.networkHeightCard)
        XCTAssertEqual(card.label, "End on the ground")
        XCTAssertEqual(card.fixes.map(\.kind), [.bridge, .tunnel])
        XCTAssertNil(card.note, "the fixes say what they do")
    }
}
