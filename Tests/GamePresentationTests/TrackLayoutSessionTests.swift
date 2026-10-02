import GameCore
import GamePresentation
import XCTest

/// Stage C2: the track tool lays Phase 4.5 Stage S1's turnouts and level
/// crossings on the grid through `buildTurnout` and `buildCrossing`.
@MainActor
final class TrackLayoutSessionTests: XCTestCase {
    func testATurnoutStartsAsAJunctionWithAThroughStem() throws {
        let session = GameSession(world: try makeWorld())
        session.selectTool(.buildTrack)
        XCTAssertEqual(session.trackPieceKind, .plain)
        session.setTrackPieceKind(.turnout)
        XCTAssertEqual(session.trackConnections, [.east, .south, .west], "a straight cannot be a turnout")
        XCTAssertEqual(session.turnoutStem, .west, "the first exit a straight track runs through")
        session.setTurnoutStem(.north)
        XCTAssertEqual(session.turnoutStem, .west, "not an exit")
        session.setTurnoutStem(.east)
        XCTAssertEqual(session.turnoutStem, .east)
        XCTAssertEqual(session.trackPieceKindText, "Turnout · stem E")
        XCTAssertEqual(session.trackPieceLayout, .turnout(stem: .east))

        session.select(GridPosition(x: 3, y: 1))
        session.applyTool()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built a turnout at (3, 1): E–S–W, stem E."))
        XCTAssertEqual(session.world.track(at: GridPosition(x: 3, y: 1))?.layout, .turnout(stem: .east))
        XCTAssertEqual(session.world.tileSummary(at: GridPosition(x: 3, y: 1), in: .english), "Turnout · E–S–W, stem E")
        XCTAssertEqual(session.world.economy.balance, Money(10_000 - testCosts.track.amount))

        var direct = try makeWorld()
        try direct.buildTurnout(at: GridPosition(x: 3, y: 1), connections: [.east, .south, .west], stem: .east)
        XCTAssertEqual(session.world, direct, "the same command applied to GameCore directly")
    }

    func testTheStemTurnsWithThePieceAndStaysAnExit() throws {
        let session = GameSession(world: try makeWorld())
        session.selectTool(.buildTrack)
        session.setTrackPieceKind(.turnout)
        session.rotateTrackPiece()
        XCTAssertEqual(session.trackConnections, [.north, .south, .west])
        XCTAssertEqual(session.turnoutStem, .north)
        session.toggleTrackDirection(.north)
        XCTAssertEqual(session.trackConnections, [.south, .west])
        XCTAssertEqual(session.turnoutStem, .west, "the stem stays an exit")
        XCTAssertEqual(session.trackPieceKind, .turnout)
        session.select(GridPosition(x: 2, y: 2))
        session.applyTool()
        XCTAssertEqual(session.message?.text, GameError.invalidTrackConnections.playerMessage(in: .english), "GameCore needs three exits")
        XCTAssertNil(session.world.track(at: GridPosition(x: 2, y: 2)))

        session.selectTrackPiece(.fourWay)
        XCTAssertEqual(session.trackPieceKind, .turnout)
        XCTAssertEqual(session.turnoutStem, .west)
        session.selectTrackPiece(.curve)
        XCTAssertEqual(session.trackPieceKind, .plain, "a curve cannot be a turnout")
    }

    func testACrossingHasAllFourExitsAndChangingOneMakesItPlain() throws {
        let session = GameSession(world: try makeWorld(), language: .traditionalChinese)
        session.selectTool(.buildTrack)
        session.setTrackPieceKind(.crossing)
        XCTAssertEqual(session.trackConnections, [.north, .east, .south, .west])
        session.select(GridPosition(x: 2, y: 1))
        session.applyTool()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已在 (2, 1) 鋪設平面交叉。"))
        XCTAssertEqual(session.world.track(at: GridPosition(x: 2, y: 1))?.layout, .crossing)

        XCTAssertEqual(session.trackPieceKindText, "平面交叉")
        XCTAssertEqual(session.trackPieceLayout, .crossing)
        session.toggleTrackDirection(.north)
        XCTAssertEqual(session.trackPieceKind, .plain)
        XCTAssertEqual(session.trackPieceLayout, .open)
        session.setTrackPieceKind(.crossing)
        session.selectTrackPiece(.straight)
        XCTAssertEqual(session.trackPieceKind, .plain)
        XCTAssertEqual(TrackPieceKind.allCases.map { $0.title(in: .traditionalChinese) }, ["一般", "道岔", "平面交叉"])
        XCTAssertEqual(TrackPieceKind.allCases.map { $0.title(in: .english) }, ["Plain", "Turnout", "Crossing"])

        session.setTrackPieceKind(.turnout)
        session.select(GridPosition(x: 4, y: 1))
        session.applyTool()
        XCTAssertEqual(session.message?.text, "已在 (4, 1) 鋪設道岔：東–南–西，共用端 西。")
    }
}
