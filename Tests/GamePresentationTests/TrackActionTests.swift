import GameCore
import GamePresentation
import XCTest

final class TrackActionTests: XCTestCase {
    private static let tile = GridPosition(x: 3, y: 2)

    func testBuildingTrackGoesThroughGameCoreAndChargesItsCost() async throws {
        let world = try makeWorld(balance: 10_000)
        var expected = world
        try expected.buildTrack(at: Self.tile, connections: [.south, .east])
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildTrack)
            session.selectTrackPiece(.curve)

            session.applyTool()

            XCTAssertEqual(session.world, expected, "the session applies exactly the GameCore command")
            XCTAssertEqual(session.world.economy.balance, 9_900)
            XCTAssertEqual(session.selectedTile?.type, .track(connections: [.south, .east]))
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built curve track at (3, 2)."))
        }
    }

    func testBuildingOnAnOccupiedTileReportsTheErrorAndChangesNothing() async throws {
        var world = try makeWorld()
        try world.buildTrack(at: Self.tile, connections: [.north, .south])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildTrack)

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .failure, text: GameError.tileOccupied(Self.tile).playerMessage)
            )
        }
    }

    func testBuildingWithoutEnoughCashReportsTheErrorAndChangesNothing() async throws {
        let world = try makeWorld(balance: 99)
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildTrack)

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertEqual(session.message?.text, "Not enough cash: this costs 100 and you have 99.")
        }
    }

    func testBuildingAnEmptyPieceIsRejectedByGameCore() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildTrack)
            session.toggleTrackDirection(.east)
            session.toggleTrackDirection(.west)

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .failure, text: GameError.invalidTrackConnections.playerMessage)
            )
        }
    }

    func testRemovingTrackEmptiesTheTileWithoutARefund() async throws {
        var world = try makeWorld(balance: 10_000)
        try world.buildTrack(at: Self.tile, connections: [.east, .west])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.removeTrack)

            session.applyTool()

            XCTAssertEqual(session.selectedTile?.type, .empty)
            XCTAssertEqual(session.world.economy.balance, 9_900, "removal is free and not refunded")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Removed track at (3, 2)."))
        }
    }

    func testRemovingWhereThereIsNoTrackChangesNothing() async throws {
        var world = try makeWorld()
        let stationTile = GridPosition(x: 0, y: 0)
        try world.buildStation(named: "Central", at: stationTile)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.removeTrack)

            for position in [Self.tile, stationTile] {
                session.select(position)
                session.applyTool()

                XCTAssertEqual(session.world, world)
                XCTAssertEqual(
                    session.message,
                    StatusMessage(kind: .failure, text: GameError.noTrackToRemove(position).playerMessage)
                )
            }
        }
    }

    func testActionsNeedASelectionAndDoNothingInSelectMode() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.buildTrack)
            session.applyTool()
            XCTAssertEqual(session.world, world, "no tile selected")
            XCTAssertNil(session.message)

            session.select(Self.tile)
            session.selectTool(.select)
            session.applyTool()
            XCTAssertEqual(session.world, world, "select mode only inspects")
            XCTAssertNil(session.message)
        }
    }

    func testSelectingAnotherTileOrToolClearsTheMessage() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.removeTrack)
            session.select(Self.tile)

            session.applyTool()
            XCTAssertNotNil(session.message)
            session.select(Self.tile)
            XCTAssertNotNil(session.message, "re-selecting the same tile keeps the message")
            session.select(GridPosition(x: 0, y: 0))
            XCTAssertNil(session.message)

            session.applyTool()
            session.selectTool(.buildTrack)
            XCTAssertNil(session.message)

            session.applyTool()
            session.dismissMessage()
            XCTAssertNil(session.message)
        }
    }
}
