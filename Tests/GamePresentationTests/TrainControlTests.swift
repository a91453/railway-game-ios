import GameCore
import GamePresentation
import XCTest

/// The train tool: every change goes through one `GameWorld` command, the
/// route comes from `GameWorld.route(from:to:)` and is committed unchanged
/// with `setTrainContinuation`, only the game loop moves trains, and what is
/// shown is read from the world.
///
/// Each test compares the session's world with the same commands applied to
/// GameCore directly, so the session can neither add, drop nor alter one.
final class TrainControlTests: XCTestCase {
    // A dead-end line on row 2, a station and an empty tile:
    //
    //   a - b - c - d - e      S (station)
    private static let a = GridPosition(x: 1, y: 2)
    private static let b = GridPosition(x: 2, y: 2)
    private static let c = GridPosition(x: 3, y: 2)
    private static let d = GridPosition(x: 4, y: 2)
    private static let e = GridPosition(x: 5, y: 2)
    private static let station = GridPosition(x: 7, y: 2)
    private static let emptyTile = GridPosition(x: 3, y: 4)
    private static let first = TrainID(rawValue: 1)
    private static let second = TrainID(rawValue: 2)

    private func makeLineWorld(balance: Money = 100_000, speed: GameSpeed = .normal) throws -> GameWorld {
        var world = try makeWorld(balance: balance, speed: speed)
        try world.buildTrack(at: Self.a, connections: .east)
        for tile in [Self.b, Self.c, Self.d] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: Self.e, connections: .west)
        try world.buildStation(named: "Terminus", at: Self.station)
        return world
    }

    /// A line world with Train 1 bought and placed at `tile`.
    private func makePlacedWorld(at tile: GridPosition = a, heading: TrackDirection = .east) throws -> GameWorld {
        var world = try makeLineWorld()
        try world.purchaseTrain(named: "Train 1")
        try world.placeTrain(Self.first, at: .atNode(tile, heading: heading))
        return world
    }

    // MARK: - Selecting and buying

    func testTheFirstTrainIsSelectedWhenThereIsOne() async throws {
        let empty = try makeLineWorld()
        var withTrains = empty
        try withTrains.purchaseTrain(named: "Blue")
        try withTrains.purchaseTrain(named: "Red")
        await MainActor.run { [withTrains] in
            XCTAssertNil(GameSession(world: empty).selectedTrainID)
            XCTAssertNil(GameSession(world: empty).selectedTrain)

            let session = GameSession(world: withTrains)
            XCTAssertEqual(session.selectedTrainID, Self.first)
            XCTAssertEqual(session.selectedTrain, withTrains.train(id: Self.first))
        }
    }

    func testBuyingATrainGoesThroughGameCoreAndSelectsIt() async throws {
        let world = try makeLineWorld(balance: 100_000)
        var expected = world
        try expected.purchaseTrain(named: "Train 1")
        try expected.purchaseTrain(named: "Train 2")
        await MainActor.run { [expected] in
            let session = GameSession(world: world)

            session.purchaseTrain()
            XCTAssertEqual(session.selectedTrainID, Self.first)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Bought Train 1. Select a track tile to place it."))
            XCTAssertNil(session.selectedTrain?.position, "a new train is not on the track")

            session.purchaseTrain()
            XCTAssertEqual(session.selectedTrainID, Self.second, "the newest train is selected")
            XCTAssertEqual(session.world, expected, "the world charged and numbered both trains")
            XCTAssertEqual(session.world.economy.balance, world.economy.balance - testCosts.train - testCosts.train)
        }
    }

    func testBuyingWithoutEnoughCashChangesNothing() async throws {
        // The line costs 1,500, leaving 4,999: one short of a train.
        let world = try makeLineWorld(balance: 6_499)
        XCTAssertEqual(world.economy.balance, testCosts.train - Money(1))
        await MainActor.run {
            let session = GameSession(world: world)

            session.purchaseTrain()

            XCTAssertEqual(session.world, world)
            XCTAssertNil(session.selectedTrainID)
            XCTAssertEqual(
                session.message,
                StatusMessage(
                    kind: .failure,
                    text: GameError.insufficientFunds(required: testCosts.train, available: Money(4_999)).playerMessage
                )
            )
        }
    }

    func testSelectingATrainNeverChangesTheWorld() async throws {
        var world = try makePlacedWorld()
        try world.purchaseTrain(named: "Train 2")
        await MainActor.run { [world] in
            let session = GameSession(world: world)

            session.selectTrain(Self.second)
            XCTAssertEqual(session.selectedTrainID, Self.second)
            session.selectTrain(TrainID(rawValue: 99))
            XCTAssertEqual(session.selectedTrainID, Self.second, "a train the world does not have is ignored")
            session.selectTrain(Self.first)
            XCTAssertEqual(session.selectedTrainID, Self.first)

            XCTAssertEqual(session.world, world)
        }
    }

    // MARK: - Placing

    func testPlacingUsesTheSelectedTileAndHeading() async throws {
        let world = try makeLineWorld()
        var expected = world
        try expected.purchaseTrain(named: "Train 1")
        try expected.placeTrain(Self.first, at: .atNode(Self.c, heading: .west))
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.purchaseTrain()
            session.setPlacementHeading(.west)
            session.select(Self.c)

            session.placeSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.selectedTrain?.position, .atNode(Self.c, heading: .west))
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Placed Train 1 at (3, 2), facing west."))
        }
    }

    func testPlacingWhereGameCoreRefusesChangesNothing() async throws {
        var world = try makeLineWorld()
        try world.purchaseTrain(named: "Train 1")
        let placed = try makePlacedWorld(at: Self.b)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            for tile in [Self.station, Self.emptyTile] {
                session.select(tile)
                session.placeSelectedTrain()
                XCTAssertEqual(session.world, world)
                XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidTrainPosition.playerMessage))
            }

            let other = GameSession(world: placed)
            other.select(Self.d)
            other.placeSelectedTrain()
            XCTAssertEqual(other.world, placed, "placing never moves a train that is already on the track")
            XCTAssertEqual(other.message, StatusMessage(kind: .failure, text: GameError.trainAlreadyPlaced(Self.first).playerMessage))
        }
    }

    func testChoosingAHeadingOrTilesNeverMovesAPlacedTrain() async throws {
        let world = try makePlacedWorld(at: Self.b, heading: .east)
        await MainActor.run {
            let session = GameSession(world: world)

            for heading in TrackDirection.allCases {
                session.setPlacementHeading(heading)
            }
            for tile in [Self.a, Self.e, Self.station, Self.emptyTile] {
                session.select(tile)
            }
            for tool in ConstructionTool.allCases {
                session.selectTool(tool)
            }
            session.clearSelection()

            XCTAssertEqual(session.world, world)
        }
    }

    // MARK: - Rate

    func testTheRateIsGameCoresRate() async throws {
        let world = try makePlacedWorld()
        var expected = world
        try expected.setTrainMovementRate(Self.first, to: 256)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            XCTAssertEqual(session.selectedTrainRate, 0)

            session.setSelectedTrainRate(256)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.selectedTrainRate, 256)
            XCTAssertNil(session.message, "a new rate is shown by the control, not announced")

            // A control bound to the property sets GameCore's rate, and reads it back.
            session.selectedTrainRate = 96
            XCTAssertEqual(session.world.train(id: Self.first)?.movement.rate, 96)
            XCTAssertEqual(session.selectedTrainRate, 96)
        }
    }

    func testARateGameCoreRefusesChangesNothing() async throws {
        let placed = try makePlacedWorld()
        let noTrain = try makeLineWorld()
        var unplaced = noTrain
        try unplaced.purchaseTrain(named: "Train 1")
        await MainActor.run { [unplaced] in
            let session = GameSession(world: placed)
            session.selectedTrainRate = -1
            XCTAssertEqual(session.world, placed)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidMovementRate.playerMessage))

            let offTrack = GameSession(world: unplaced)
            offTrack.setSelectedTrainRate(128)
            XCTAssertEqual(offTrack.world, unplaced)
            XCTAssertEqual(offTrack.message, StatusMessage(kind: .failure, text: GameError.trainNotPlaced(Self.first).playerMessage))

            let none = GameSession(world: noTrain)
            none.setSelectedTrainRate(128)
            XCTAssertEqual(none.world, noTrain)
            XCTAssertEqual(none.message, StatusMessage(kind: .failure, text: "Buy a train first."))
        }
    }

    // MARK: - Sending

    func testSendingCommitsGameCoresRouteUnchanged() async throws {
        let world = try makePlacedWorld(at: Self.a, heading: .east)
        let route = try XCTUnwrap(world.route(from: .atNode(Self.a, heading: .east), to: Self.e))
        XCTAssertEqual(route, [Self.b, Self.c, Self.d, Self.e])
        var expected = world
        try expected.setTrainContinuation(Self.first, to: route)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.select(Self.e)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(Array(session.selectedTrain?.movement.remainingContinuation ?? []), route)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to (5, 2), 4 links from (1, 2). Set a rate to start.")
            )
        }
    }

    func testSendingToTheNextNodeCommitsTheEmptyRoute() async throws {
        var world = try makePlacedWorld(at: Self.a, heading: .east)
        try world.setTrainMovementRate(Self.first, to: 512)
        try world.setTrainContinuation(Self.first, to: [Self.b, Self.c])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: Self.first)?.position, .onLink(from: Self.a, to: Self.b, offset: 512))
        var expected = world
        try expected.setTrainContinuation(Self.first, to: [])
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.select(Self.b)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected, "the train runs to the end of its link and stops there")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Train 1 stops at (2, 2)."))
        }
    }

    func testAMovedTrainIsRoutedFromWhereItIsNow() async throws {
        let world = try makePlacedWorld(at: Self.a, heading: .east)
        try await MainActor.run {
            let session = GameSession(world: world)
            session.setSelectedTrainRate(512)
            session.select(Self.e)
            session.sendSelectedTrain()
            // Three ticks at 1×: 1536 units, half way from b to c.
            session.advance(realElapsed: .milliseconds(300))
            let moved = session.world
            XCTAssertEqual(moved.train(id: Self.first)?.position, .onLink(from: Self.b, to: Self.c, offset: 512))

            session.select(Self.d)
            session.sendSelectedTrain()

            var expected = moved
            let route = moved.route(from: .onLink(from: Self.b, to: Self.c, offset: 512), to: Self.d)
            XCTAssertEqual(route, [Self.d], "from the node ahead of the train, not from where it started")
            try expected.setTrainContinuation(Self.first, to: [Self.d])
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Sent Train 1 to (4, 2), 1 link from (3, 2)."))
        }
    }

    func testSendingTwiceWithoutTimePassingCommitsTheSameRoute() async throws {
        let world = try makePlacedWorld(at: Self.a, heading: .east)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.select(Self.d)
            session.sendSelectedTrain()
            let once = session.world

            session.sendSelectedTrain()
            session.applyTool()

            XCTAssertEqual(session.world, once, "a repeated press recomputes the same route from the same place")
        }
    }

    func testNoRouteChangesNothingAndKeepsTheCurrentPath() async throws {
        var world = try makePlacedWorld(at: Self.b, heading: .east)
        try world.setTrainContinuation(Self.first, to: [Self.c, Self.d, Self.e])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            // Behind the train with no loop to turn round, and an empty tile.
            for tile in [Self.a, Self.emptyTile] {
                session.select(tile)
                session.sendSelectedTrain()
                XCTAssertEqual(session.world, world)
                XCTAssertEqual(
                    session.message,
                    StatusMessage(
                        kind: .failure,
                        text: "No route for Train 1 to \(tile): it must be track the train can reach without turning back. Its path is unchanged."
                    )
                )
            }
            // A station with no track beside it (Stage N): no platform.
            XCTAssertEqual(session.world.platforms(of: StationID(rawValue: 1)), [])
            session.select(Self.station)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(
                session.message,
                StatusMessage(
                    kind: .failure,
                    text: "No route for Train 1 to Terminus: it needs track beside the station that the train can reach without turning back. Its path is unchanged."
                )
            )
            XCTAssertEqual(Array(session.selectedTrain?.movement.remainingContinuation ?? []), [Self.c, Self.d, Self.e])

            // A failed request does not get in the way of the next one.
            session.select(Self.d)
            session.sendSelectedTrain()
            XCTAssertEqual(session.message?.kind, .success)
            XCTAssertEqual(Array(session.selectedTrain?.movement.remainingContinuation ?? []), [Self.c, Self.d])
        }
    }

    func testSendingWithoutATrainPlacementOrDestinationChangesNothing() async throws {
        let noTrain = try makeLineWorld()
        var unplaced = noTrain
        try unplaced.purchaseTrain(named: "Train 1")
        let placed = try makePlacedWorld()
        await MainActor.run { [unplaced] in
            let first = GameSession(world: noTrain)
            first.select(Self.e)
            first.sendSelectedTrain()
            XCTAssertEqual(first.world, noTrain)
            XCTAssertEqual(first.message, StatusMessage(kind: .failure, text: "Buy a train first."))

            let second = GameSession(world: unplaced)
            second.select(Self.e)
            second.sendSelectedTrain()
            XCTAssertEqual(second.world, unplaced)
            XCTAssertEqual(second.message, StatusMessage(kind: .failure, text: GameError.trainNotPlaced(Self.first).playerMessage))

            let third = GameSession(world: placed)
            third.sendSelectedTrain()
            XCTAssertEqual(third.world, placed)
            XCTAssertEqual(third.message, StatusMessage(kind: .failure, text: "Select the track tile to send Train 1 to."))
        }
    }

    func testOnlyTheSelectedTrainIsSent() async throws {
        var world = try makePlacedWorld(at: Self.a, heading: .east)
        try world.purchaseTrain(named: "Train 2")
        try world.placeTrain(Self.second, at: .atNode(Self.e, heading: .west))
        var expected = world
        try expected.setTrainContinuation(Self.second, to: [Self.d, Self.c, Self.b])
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.selectTrain(Self.second)
            session.select(Self.b)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected, "the route is Train 2's, from Train 2's position")
            XCTAssertEqual(session.world.train(id: Self.first), world.train(id: Self.first))
        }
    }

    // MARK: - Reversing and taking off

    func testReversingAndTakingOffGoThroughGameCore() async throws {
        var world = try makePlacedWorld(at: Self.b, heading: .east)
        try world.setTrainMovementRate(Self.first, to: 64)
        try world.setTrainContinuation(Self.first, to: [Self.c, Self.d])
        var reversed = world
        try reversed.reverseTrain(Self.first)
        var unplaced = reversed
        try unplaced.unplaceTrain(Self.first)
        await MainActor.run { [world, reversed, unplaced] in
            let session = GameSession(world: world)

            session.reverseSelectedTrain()
            XCTAssertEqual(session.world, reversed)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Reversed Train 1; its path was cleared."))

            session.unplaceSelectedTrain()
            XCTAssertEqual(session.world, unplaced)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Took Train 1 off the track."))

            session.unplaceSelectedTrain()
            XCTAssertEqual(session.world, unplaced)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.trainNotPlaced(Self.first).playerMessage))
            session.reverseSelectedTrain()
            XCTAssertEqual(session.world, unplaced)
        }
    }

    // MARK: - The tool and the whole flow

    func testTheTrainToolPlacesAnUnplacedTrainAndSendsAPlacedOne() async throws {
        let world = try makeLineWorld()
        var expected = world
        try expected.purchaseTrain(named: "Train 1")
        try expected.placeTrain(Self.first, at: .atNode(Self.b, heading: .east))
        try expected.setTrainContinuation(Self.first, to: [Self.c, Self.d, Self.e])
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.select(Self.b)
            session.applyTool()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Buy a train first."))

            session.purchaseTrain()
            session.applyTool()
            XCTAssertEqual(session.selectedTrain?.position, .atNode(Self.b, heading: .east))

            session.select(Self.e)
            session.applyTool()
            XCTAssertEqual(session.world, expected)
        }
    }

    /// Place, choose a destination, set a rate, route, commit, advance, read:
    /// the whole Stage M flow, checked against GameCore run directly.
    func testTheGameLoopMovesASentTrainExactlyAsGameCoreDoes() async throws {
        let world = try makeLineWorld(speed: .normal)
        var expected = world
        try expected.purchaseTrain(named: "Train 1")
        try expected.placeTrain(Self.first, at: .atNode(Self.a, heading: .east))
        try expected.setTrainMovementRate(Self.first, to: 384)
        let route = try XCTUnwrap(expected.route(from: .atNode(Self.a, heading: .east), to: Self.e))
        try expected.setTrainContinuation(Self.first, to: route)
        let committed = expected
        try expected.advance(ticks: 7)
        await MainActor.run { [committed, expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.purchaseTrain()
            session.select(Self.a)
            session.applyTool()
            session.selectedTrainRate = 384
            session.select(Self.e)
            session.applyTool()
            XCTAssertEqual(session.world, committed)

            // Nothing moves until the game loop advances the world.
            XCTAssertEqual(session.selectedTrain?.position, .atNode(Self.a, heading: .east))

            for _ in 0..<7 {
                session.advance(realElapsed: .milliseconds(100))
            }
            XCTAssertEqual(session.world, expected)
            // 7 × 384 = 2688 units: two links and 640 into the third.
            XCTAssertEqual(session.selectedTrain?.position, .onLink(from: Self.c, to: Self.d, offset: 640))
            XCTAssertEqual(session.selectedTrain?.positionText, "(3, 2) → (4, 2), 640 / 1024")
            XCTAssertEqual(session.selectedTrain?.movement.pathText, "Path: 1 more node, (5, 2)")

            // The rest of the way: 4 × 1024 − 2688 = 1408 more units.
            for _ in 0..<4 {
                session.advance(realElapsed: .milliseconds(100))
            }
            XCTAssertEqual(session.selectedTrain?.position, .atNode(Self.e, heading: .east))
            XCTAssertEqual(session.selectedTrain?.movement.pathText, "No path ahead")
            XCTAssertEqual(session.selectedTrain?.positionText, "At (5, 2), facing East")
        }
    }

    func testPausedTimeNeverMovesATrain() async throws {
        var world = try makePlacedWorld(at: Self.a, heading: .east)
        try world.setTrainMovementRate(Self.first, to: 1_024)
        try world.setTrainContinuation(Self.first, to: [Self.b, Self.c])
        world.setSpeed(.paused)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.advance(realElapsed: .seconds(3))
            XCTAssertEqual(session.world, world)
        }
    }

    func testReadingWhatIsShownNeverChangesTheWorld() async throws {
        var world = try makePlacedWorld(at: Self.a, heading: .east)
        try world.setTrainMovementRate(Self.first, to: 300)
        try world.setTrainContinuation(Self.first, to: [Self.b, Self.c, Self.d])
        try world.advance(ticks: 2)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            for _ in 0..<3 {
                let train = session.selectedTrain
                _ = train?.positionText
                _ = train?.movement.pathText
                _ = train?.movement.rateText
                _ = session.selectedTrainRate
                if let position = train?.position {
                    _ = MapScale.center(of: position, tileSize: 32)
                    _ = MapScale.facing(of: position)
                }
            }
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.selectedTrain?.positionText, "(1, 2) → (2, 2), 600 / 1024")
            XCTAssertEqual(session.selectedTrain?.movement.pathText, "Path: 2 more nodes, ending at (4, 2)")
            XCTAssertEqual(session.selectedTrain?.movement.rateText, "Rate 300 / min")
        }
    }
}

final class TrainDisplayTests: XCTestCase {
    func testPositionsReadAsGameCoreStoresThem() {
        XCTAssertEqual(TrainPosition.atNode(GridPosition(x: 3, y: 2), heading: .north).displayText, "At (3, 2), facing North")
        XCTAssertEqual(
            TrainPosition.onLink(from: GridPosition(x: 4, y: 2), to: GridPosition(x: 3, y: 2), offset: 1).displayText,
            "(4, 2) → (3, 2), 1 / 1024"
        )
        XCTAssertEqual(Train(id: TrainID(rawValue: 1), name: "Train 1").positionText, "Not on the track")
    }

    func testPathAndRateText() throws {
        var world = try makeWorld(balance: 100_000, speed: .normal)
        for x in 0...3 {
            try world.buildTrack(at: GridPosition(x: x, y: 0), connections: [.east, .west])
        }
        try world.purchaseTrain(named: "Train 1")
        let id = TrainID(rawValue: 1)
        try world.placeTrain(id, at: .atNode(GridPosition(x: 0, y: 0), heading: .east))
        XCTAssertEqual(world.train(id: id)?.movement.pathText, "No path ahead")
        XCTAssertEqual(world.train(id: id)?.movement.rateText, "Rate 0 / min")

        try world.setTrainContinuation(id, to: [GridPosition(x: 1, y: 0)])
        XCTAssertEqual(world.train(id: id)?.movement.pathText, "Path: 1 more node, (1, 0)")

        try world.setTrainContinuation(id, to: [GridPosition(x: 1, y: 0), GridPosition(x: 2, y: 0), GridPosition(x: 3, y: 0)])
        try world.setTrainMovementRate(id, to: 1_536)
        try world.advance(ticks: 1)
        // One link entered and half of the next: two entries entered, one left.
        XCTAssertEqual(world.train(id: id)?.movement.pathText, "Path: 1 more node, (3, 0)")
        XCTAssertEqual(world.train(id: id)?.movement.rateText, "Rate 1536 / min")
    }

    func testTrainsAreDrawnWhereGameCoreHasThem() {
        let node = TrainPosition.atNode(GridPosition(x: 3, y: 2), heading: .south)
        XCTAssertTrue(MapScale.center(of: node, tileSize: 32) == (112, 80))
        XCTAssertTrue(MapScale.center(of: GridPosition(x: 0, y: 0), tileSize: 10) == (5, 5))

        let east = TrainPosition.onLink(from: GridPosition(x: 3, y: 2), to: GridPosition(x: 4, y: 2), offset: 256)
        XCTAssertTrue(MapScale.center(of: east, tileSize: 32) == (120, 80), "a quarter of the way to the east tile")
        let north = TrainPosition.onLink(from: GridPosition(x: 3, y: 2), to: GridPosition(x: 3, y: 1), offset: 768)
        XCTAssertTrue(MapScale.center(of: north, tileSize: 32) == (112, 56), "three quarters of the way north")
        let almost = TrainPosition.onLink(from: GridPosition(x: 0, y: 0), to: GridPosition(x: 1, y: 0), offset: 1_023)
        XCTAssertLessThan(MapScale.center(of: almost, tileSize: 1_024).x, 1_536, "never drawn at or past the next node")
    }

    func testTrainsFaceTheirHeadingOrTheFarEndOfTheirLink() {
        let tile = GridPosition(x: 5, y: 5)
        XCTAssertTrue(MapScale.facing(of: .atNode(tile, heading: .north)) == (0, -1))
        XCTAssertTrue(MapScale.facing(of: .atNode(tile, heading: .east)) == (1, 0))
        XCTAssertTrue(MapScale.facing(of: .atNode(tile, heading: .south)) == (0, 1))
        XCTAssertTrue(MapScale.facing(of: .atNode(tile, heading: .west)) == (-1, 0))
        XCTAssertTrue(MapScale.facing(of: .onLink(from: tile, to: GridPosition(x: 4, y: 5), offset: 9)) == (-1, 0))
        XCTAssertTrue(MapScale.facing(of: .onLink(from: tile, to: GridPosition(x: 5, y: 6), offset: 9)) == (0, 1))
        // Values GameCore would never place do not trap.
        let extreme = TrainPosition.onLink(from: GridPosition(x: .min, y: .max), to: GridPosition(x: .max, y: .min), offset: 1)
        XCTAssertTrue(MapScale.facing(of: extreme) == (1, -1))
    }
}
