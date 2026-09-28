import GameCore
import GamePresentation
import XCTest

final class ConstructionToolTests: XCTestCase {
    func testSessionStartsInSelectModeWithAStraightPiece() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            XCTAssertEqual(session.tool, .select)
            XCTAssertEqual(session.trackConnections, [.east, .west])
        }
    }

    func testSwitchingToolsDoesNotChangeTheWorld() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(GridPosition(x: 1, y: 1))

            for tool in ConstructionTool.allCases {
                session.selectTool(tool)
                XCTAssertEqual(session.tool, tool)
            }

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.selection, GridPosition(x: 1, y: 1), "switching tools keeps the selection")
        }
    }

    func testEditingTheTrackPieceDoesNotChangeTheWorld() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            session.selectTool(.buildTrack)
            session.selectTrackPiece(.fourWay)
            session.rotateTrackPiece()
            session.toggleTrackDirection(.north)

            XCTAssertEqual(session.world, world)
        }
    }

    func testTogglingDirectionsBuildsTheMatchingConnections() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            session.toggleTrackDirection(.east)
            session.toggleTrackDirection(.west)
            XCTAssertEqual(session.trackConnections, [], "toggling both ends of the straight clears it")

            session.toggleTrackDirection(.north)
            session.toggleTrackDirection(.east)
            XCTAssertEqual(session.trackConnections, [.north, .east])
            XCTAssertEqual(session.trackConnections.rawValue, 0b0011)

            session.toggleTrackDirection(.north)
            XCTAssertEqual(session.trackConnections, .east)
        }
    }

    func testPiecesAndRotation() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)

            session.selectTrackPiece(.curve)
            XCTAssertEqual(session.trackConnections, [.south, .east])
            session.rotateTrackPiece()
            XCTAssertEqual(session.trackConnections, [.south, .west])
            session.rotateTrackPiece()
            XCTAssertEqual(session.trackConnections, [.west, .north])

            session.selectTrackPiece(.straight)
            session.rotateTrackPiece()
            XCTAssertEqual(session.trackConnections, [.north, .south])
        }
    }

    func testPieceShapesMatchTheirNames() {
        XCTAssertEqual(TrackPiece.straight.connections.shapeName, "Straight")
        XCTAssertEqual(TrackPiece.curve.connections.shapeName, "Curve")
        XCTAssertEqual(TrackPiece.junction.connections.shapeName, "T-junction")
        XCTAssertEqual(TrackPiece.fourWay.connections.shapeName, "Four-way")
    }

    func testRotatingFourTimesReturnsTheSamePiece() {
        for piece in TrackPiece.allCases {
            var connections = piece.connections
            for _ in 0..<4 { connections = connections.rotatedClockwise }
            XCTAssertEqual(connections, piece.connections)
        }
        XCTAssertEqual(TrackConnections().rotatedClockwise, [])
        XCTAssertEqual(TrackConnections.north.rotatedClockwise, .east)
        XCTAssertEqual(TrackConnections.west.rotatedClockwise, .north)
    }
}
