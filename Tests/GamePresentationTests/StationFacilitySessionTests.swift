import GameCore
import GamePresentation
import XCTest

/// Growing stations and trains of several cars through the session (Stage
/// S2): each action is one `GameWorld` command, and the texts are derived
/// from the world.
final class StationFacilitySessionTests: XCTestCase {
    //   row 0:  .  .  .  A  .  .  .      A = Central (3,0)
    //   row 1:  o - o - o - o - o - o - o
    private static func p(_ x: Int, _ y: Int) -> GridPosition {
        GridPosition(x: x, y: y)
    }

    private static func makeLine() throws -> GameWorld {
        var world = try GameWorld(width: 7, height: 3, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildTrack(at: p(0, 1), connections: .east)
        for x in 1...5 {
            try world.buildTrack(at: p(x, 1), connections: [.east, .west])
        }
        try world.buildTrack(at: p(6, 1), connections: .west)
        try world.buildStation(named: "Central", at: p(3, 0))
        return world
    }

    func testTheStationToolGrowsTheStationBesideTheTile() async throws {
        let world = try Self.makeLine()
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.buildStation)
            session.growsStation = true

            session.select(Self.p(5, 0))
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "There is no station beside (5, 0) to grow."))

            session.select(Self.p(4, 0))
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "“Central” now covers 2 tiles."))
            XCTAssertEqual(session.world.stations.first?.annexes, [Self.p(4, 0)])
            XCTAssertEqual(session.world.economy.balance, Money(997_300))
            XCTAssertEqual(session.world.tileSummary(at: Self.p(4, 0)), "Station · Central · 2 tiles")
            XCTAssertEqual(session.world.platforms(of: StationID(rawValue: 1)), [Self.p(3, 1), Self.p(4, 1)])

            // Growing onto track is GameCore's refusal.
            session.select(Self.p(4, 1))
            session.applyTool()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tile (4, 1) is already occupied."))
        }
    }

    func testCarsAreSetOffTheTrackAndALongTrainIsSentAlongThePlatforms() async throws {
        var world = try Self.makeLine()
        try world.extendStation(StationID(rawValue: 1), to: Self.p(4, 0))
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.purchaseTrain()
            XCTAssertEqual(session.selectedTrain?.carsText, "1 car")

            session.setSelectedTrainCars(2)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Train 1 now has 2 cars."))
            XCTAssertEqual(session.selectedTrain?.carsText, "2 cars")
            session.setSelectedTrainCars(17)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "A train has 1 to 16 cars."))

            // Facing east at (1,1), its second car at (0,1).
            session.setPlacementHeading(.east)
            session.select(Self.p(1, 1))
            session.applyTool()
            XCTAssertEqual(session.selectedTrain?.trail, [Self.p(0, 1)])
            session.setSelectedTrainCars(3)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Train #1 is already on the track."))

            // To Central: (2,1), the first platform (3,1), and one more for
            // the second car.
            session.select(Self.p(3, 0))
            session.applyTool()
            XCTAssertEqual(session.selectedTrain?.movement.continuation, [Self.p(2, 1), Self.p(3, 1), Self.p(4, 1)])
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Sent Train 1 to Central, platform (4, 1), 3 links from (1, 1). Set a rate to start."))
        }
    }

    func testAStopTellsWhenThePlatformIsTooShort() throws {
        var world = try Self.makeLine()
        let id = try world.purchaseTrain(named: "Long").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .atNode(Self.p(3, 1), heading: .east))
        XCTAssertEqual(world.stationStopText(of: id), "Stopped at Central · the platform is too short for all its cars")

        try world.extendStation(StationID(rawValue: 1), to: Self.p(2, 0))
        XCTAssertEqual(world.stationStopText(of: id), "Stopped at Central")
    }

    /// The body is drawn from the head through the trail's centres to the
    /// tail: at a node, whole links; on a link, the tail part way.
    func testTheBodyIsDrawnBackToTheTail() throws {
        var world = try Self.makeLine()
        let id = try world.purchaseTrain(named: "Long").id
        XCTAssertTrue(MapScale.bodyPoints(of: try XCTUnwrap(world.train(id: id)), tileSize: 10).isEmpty)
        try world.setTrainCars(id, to: 3)
        try world.placeTrain(id, at: .atNode(Self.p(3, 1), heading: .east))
        var points = MapScale.bodyPoints(of: try XCTUnwrap(world.train(id: id)), tileSize: 10)
        XCTAssertEqual(points.map(\.x), [35, 25, 15])
        XCTAssertEqual(points.map(\.y), [15, 15, 15])

        // 256 along (3,1) → (4,1): (3,1) at 256, (2,1) at 1280, (1,1) at
        // 2304, the tail 2048 back, three quarters of the way to (1,1).
        try world.unplaceTrain(id)
        try world.placeTrain(id, at: .onLink(from: Self.p(3, 1), to: Self.p(4, 1), offset: 256))
        points = MapScale.bodyPoints(of: try XCTUnwrap(world.train(id: id)), tileSize: 10)
        XCTAssertEqual(points.map(\.x), [37.5, 35, 25, 17.5])
    }
}
