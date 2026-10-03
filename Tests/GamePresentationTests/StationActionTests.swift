import GameCore
import GamePresentation
import XCTest

/// Naming and building stations through the session: since Stage F1 the
/// network tool's platform mode builds a station at the middle of its
/// first platform, named ``GameSession/stationName`` (Stage F3c moved
/// these tests off the grid's station tool).
final class StationActionTests: XCTestCase {
    /// One straight edge along y = 3072, 7168 long (7 tiles of track),
    /// with `left` cash once it is built.
    private func makeLine(left: Money = 100_000) throws -> GameWorld {
        var world = try makeWorld(width: 8, height: 6, balance: left + 700)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 3_072))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 7_680, y: 3_072))
        try world.buildTrackEdge(from: west, to: east)
        XCTAssertEqual(world.economy.balance, left)
        return world
    }

    /// Picks the middle of the edge in platform mode.
    @MainActor
    private static func pickPlatform(in session: GameSession) {
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 3_072), reach: 256)
    }

    func testTheFirstSuggestedNameIsStationOne() async throws {
        let world = try makeWorld()
        await MainActor.run {
            XCTAssertEqual(GameSession(world: world).stationName, "Station 1")
        }
    }

    func testBuildingAStationUsesTheWorldsIDAndChargesItsCost() async throws {
        let world = try makeLine(left: 10_000)
        await MainActor.run {
            let session = GameSession(world: world)
            Self.pickPlatform(in: session)
            session.stationName = "Central"

            session.addNetworkPlatform()

            let station = session.world.stations.first
            XCTAssertEqual(session.world.stations.count, 1)
            XCTAssertEqual(station?.id, StationID(rawValue: 1))
            XCTAssertEqual(station?.name, "Central")
            XCTAssertEqual(session.world.economy.balance, 9_000)
            XCTAssertEqual(session.world.stationSummary(StationID(rawValue: 1), in: .english), "Station · Central · 1 platform, 64 m")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built station “Central” with a 64 m platform on edge #1."))
            XCTAssertEqual(session.stationName, "Station 2", "the next suggestion is ready")
        }
    }

    func testSuggestedNamesSkipNamesAlreadyInUse() async throws {
        var world = try makeLine()
        try world.buildStation(named: "Station 2", at: PlanPoint(x: 512, y: 512))
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            XCTAssertEqual(session.stationName, "Station 3")

            Self.pickPlatform(in: session)
            session.platformStationID = nil
            session.stationName = "Station 3"
            session.addNetworkPlatform()

            XCTAssertEqual(session.stationName, "Station 4")
        }
    }

    func testBlankNamesAreRejectedByGameCore() async throws {
        let world = try makeLine()
        await MainActor.run {
            let session = GameSession(world: world)
            Self.pickPlatform(in: session)
            session.stationName = "   "

            session.addNetworkPlatform()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidName.playerMessage(in: .english)))
            XCTAssertEqual(session.stationName, "   ", "a rejected name is left for the player to fix")
        }
    }

    func testBuildingWithoutEnoughCashChangesNothing() async throws {
        let world = try makeLine(left: 999)
        await MainActor.run {
            let session = GameSession(world: world)
            Self.pickPlatform(in: session)

            session.addNetworkPlatform()

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message?.text, "Not enough cash: this costs $ 10.00 and you have $ 9.99.")
            XCTAssertEqual(session.stationName, "Station 1")
        }
    }
}
