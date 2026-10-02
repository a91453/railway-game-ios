import GameCore
import GamePresentation
import XCTest

final class StationActionTests: XCTestCase {
    private static let tile = GridPosition(x: 5, y: 1)

    func testTheFirstSuggestedNameIsStationOne() async throws {
        let world = try makeWorld()
        await MainActor.run {
            XCTAssertEqual(GameSession(world: world).stationName, "Station 1")
        }
    }

    func testBuildingAStationUsesTheWorldsIDAndChargesItsCost() async throws {
        let world = try makeWorld(balance: 10_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildStation)
            session.stationName = "Central"

            session.applyTool()

            let station = session.world.stations.first
            XCTAssertEqual(session.world.stations.count, 1)
            XCTAssertEqual(station?.id, StationID(rawValue: 1))
            XCTAssertEqual(station?.name, "Central")
            XCTAssertEqual(station?.position, Self.tile)
            XCTAssertEqual(session.selectedTile?.type, .station(id: StationID(rawValue: 1)))
            XCTAssertEqual(session.world.economy.balance, 9_000)
            XCTAssertEqual(session.world.tileSummary(at: Self.tile, in: .english), "Station · Central")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built station “Central” at (5, 1)."))
            XCTAssertEqual(session.stationName, "Station 2", "the next suggestion is ready")
        }
    }

    func testSuggestedNamesSkipNamesAlreadyInUse() async throws {
        var world = try makeWorld()
        try world.buildStation(named: "Station 2", at: GridPosition(x: 0, y: 0))
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            XCTAssertEqual(session.stationName, "Station 3")

            session.select(Self.tile)
            session.selectTool(.buildStation)
            session.stationName = "Station 3"
            session.applyTool()

            XCTAssertEqual(session.stationName, "Station 4")
        }
    }

    func testBlankNamesAreRejectedByGameCore() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildStation)
            session.stationName = "   "

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidName.playerMessage(in: .english)))
            XCTAssertEqual(session.stationName, "   ", "a rejected name is left for the player to fix")
        }
    }

    func testBuildingOnAnOccupiedTileChangesNothing() async throws {
        var world = try makeWorld()
        try world.buildTrack(at: Self.tile, connections: [.east, .west])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildStation)

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .failure, text: GameError.tileOccupied(Self.tile).playerMessage(in: .english))
            )
            XCTAssertEqual(session.stationName, "Station 1")
        }
    }

    func testBuildingWithoutEnoughCashChangesNothing() async throws {
        let world = try makeWorld(balance: 999)
        await MainActor.run {
            let session = GameSession(world: world)
            session.select(Self.tile)
            session.selectTool(.buildStation)

            session.applyTool()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message?.text, "Not enough cash: this costs $ 10.00 and you have $ 9.99.")
        }
    }
}
