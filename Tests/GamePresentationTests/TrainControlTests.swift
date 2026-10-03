import GameCore
import GamePresentation
import XCTest

/// The train tool: every change goes through one `GameWorld` command, the
/// path comes from `GameWorld.path(from:toStation:length:)` and is
/// committed unchanged with `setTrainContinuation(_:along:stoppingAt:)`,
/// only the game loop moves trains, and what is shown is read from the
/// world. On the track network since Stage F3c.
///
/// Each test compares the session's world with the same commands applied to
/// GameCore directly, so the session can neither add, drop nor alter one.
final class TrainControlTests: XCTestCase {
    // A dead-end line of the track network on row 2 (nodes at columns 0–5,
    // edges 1–5 eastward, see `TestLine`), three stations beside it on
    // row 1 with platforms either side of a node, one away from it, and an
    // empty tile:
    //
    //   row 1:        W       M       E        T (row 4), empty (3, 4)
    //   row 2:   o - o - o - o - o - o
    private static let line = TestLine(tiles: 6, row: 2)
    private static let west = StationID(rawValue: 1)
    private static let mid = StationID(rawValue: 2)
    private static let east = StationID(rawValue: 3)
    private static let terminus = StationID(rawValue: 4)
    private static let emptyTile = GridPosition(x: 3, y: 4)
    private static let first = TrainID(rawValue: 1)
    private static let second = TrainID(rawValue: 2)

    private func makeLineWorld(balance: Money = 100_000, speed: GameSpeed = .normal) throws -> GameWorld {
        var world = try makeWorld(balance: balance, speed: speed)
        try Self.line.build(in: &world)
        try Self.line.buildStation(named: "West", beside: 1, at: 1, in: &world)
        try Self.line.buildStation(named: "Mid", beside: 3, at: 1, in: &world)
        try Self.line.buildStation(named: "East", beside: 5, at: 1, in: &world)
        try world.buildStation(named: "Terminus", at: TestLine.centre(7, 4))
        return world
    }

    /// A line world with Train 1 bought and standing at the node at
    /// `column`, facing east or west.
    private func makePlacedWorld(at column: Int = 1, facingEast: Bool = true) throws -> GameWorld {
        var world = try makeLineWorld()
        try world.purchaseTrain(named: "Train 1")
        try world.placeTrain(Self.first, at: Self.line.at(column, facingEast: facingEast))
        return world
    }

    /// `world` with train `id` sent to `station` along GameCore's path.
    private static func sent(_ world: GameWorld, _ id: TrainID, to station: StationID) throws -> GameWorld {
        var world = world
        let train = try XCTUnwrap(world.train(id: id))
        let path = try XCTUnwrap(world.path(from: try XCTUnwrap(train.position), toStation: station, length: train.length))
        try world.setTrainContinuation(id, along: path.traversals, stoppingAt: path.end)
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
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Bought Train 1. Select a station to place it."))
            XCTAssertNil(session.selectedTrain?.position, "a new train is not on the track")

            session.purchaseTrain()
            XCTAssertEqual(session.selectedTrainID, Self.second, "the newest train is selected")
            XCTAssertEqual(session.world, expected, "the world charged and numbered both trains")
            XCTAssertEqual(session.world.economy.balance, world.economy.balance - testCosts.train - testCosts.train)
        }
    }

    func testBuyingWithoutEnoughCashChangesNothing() async throws {
        // What the line costs, and 4,999 left: one short of a train.
        let cost = Money(1_000_000) - (try makeLineWorld(balance: 1_000_000)).economy.balance
        let world = try makeLineWorld(balance: cost + testCosts.train - Money(1))
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
                    text: GameError.insufficientFunds(required: testCosts.train, available: Money(4_999)).playerMessage(in: .english)
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

    /// Mid's first platform is the last half of edge 3: facing west, the
    /// train stands with its head at the platform's west end, 512 along
    /// the edge the way it faces.
    func testPlacingUsesTheSelectedStationAndHeading() async throws {
        let world = try makeLineWorld()
        var expected = world
        try expected.purchaseTrain(named: "Train 1")
        let position = TrainPosition.onEdge(TrackTraversal(edge: .edge(3), direction: .backward), offset: 512)
        try expected.placeTrain(Self.first, at: position)
        try expected.setTrainContinuation(Self.first, along: [], stoppingAt: 512)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.purchaseTrain()
            session.setPlacementHeading(.west)
            session.selectStation(Self.mid)

            session.placeSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.selectedTrain?.position, position)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Placed Train 1 at Mid, on edge #3 going backward."))
        }
    }

    func testPlacingWhereGameCoreRefusesChangesNothing() async throws {
        var world = try makeLineWorld()
        try world.purchaseTrain(named: "Train 1")
        let placed = try makePlacedWorld(at: 2)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectStation(Self.terminus)
            session.placeSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Terminus has no platform yet. Add one with the network tool."))

            session.select(Self.emptyTile)
            session.placeSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select a station to place Train 1 at."))

            let other = GameSession(world: placed)
            other.selectStation(Self.mid)
            other.placeSelectedTrain()
            XCTAssertEqual(other.world, placed, "placing never moves a train that is already on the track")
            XCTAssertEqual(other.message, StatusMessage(kind: .failure, text: GameError.trainAlreadyPlaced(Self.first).playerMessage(in: .english)))
        }
    }

    func testChoosingAHeadingStationsOrTilesNeverMovesAPlacedTrain() async throws {
        let world = try makePlacedWorld(at: 2)
        await MainActor.run {
            let session = GameSession(world: world)

            for heading in CompassHeading.allCases {
                session.setPlacementHeading(heading)
            }
            for station in [Self.west, Self.east, Self.terminus] {
                session.selectStation(station)
            }
            session.select(Self.emptyTile)
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
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidMovementRate.playerMessage(in: .english)))

            let offTrack = GameSession(world: unplaced)
            offTrack.setSelectedTrainRate(128)
            XCTAssertEqual(offTrack.world, unplaced)
            XCTAssertEqual(offTrack.message, StatusMessage(kind: .failure, text: GameError.trainNotPlaced(Self.first).playerMessage(in: .english)))

            let none = GameSession(world: noTrain)
            none.setSelectedTrainRate(128)
            XCTAssertEqual(none.world, noTrain)
            XCTAssertEqual(none.message, StatusMessage(kind: .failure, text: "Buy a train first."))
        }
    }

    // MARK: - Sending

    /// From West, facing east, to East's platform on the last half of edge
    /// 5: edges 2 to 5, stopping at the end of edge 5.
    func testSendingCommitsGameCoresPathUnchanged() async throws {
        let world = try makePlacedWorld(at: 1, facingEast: true)
        let path = try XCTUnwrap(world.path(from: Self.line.at(1, facingEast: true), toStation: Self.east, length: 0))
        XCTAssertEqual(path.traversals, Self.line.path(from: 1, through: [2, 3, 4, 5]))
        XCTAssertEqual(path.distance, 4_096)
        let expected = try Self.sent(world, Self.first, to: Self.east)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectStation(Self.east)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.selectedTrain?.movement.remainingEdges, [.edge(2), .edge(3), .edge(4), .edge(5)])
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to East, 4096 units along the track. Set a rate to start.")
            )
        }
    }

    func testSendingToTheStationItStandsAtStopsItThere() async throws {
        let world = try makePlacedWorld(at: 1, facingEast: true)
        let expected = try Self.sent(world, Self.first, to: Self.west)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectStation(Self.west)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Train 1 stops at West. Set a rate to start."))
        }
    }

    func testAMovedTrainIsSentFromWhereItIsNow() async throws {
        let world = try makePlacedWorld(at: 1, facingEast: true)
        try await MainActor.run {
            let session = GameSession(world: world)
            session.setSelectedTrainRate(512)
            session.selectStation(Self.east)
            session.sendSelectedTrain()
            // Three ticks at 1×: 1536 units, half way along edge 3.
            session.advance(realElapsed: .milliseconds(300))
            let moved = session.world
            XCTAssertEqual(moved.train(id: Self.first)?.position, Self.line.between(2, 3, offset: 512))

            session.selectStation(Self.mid)
            session.sendSelectedTrain()

            // To the end of Mid's platform on edge 3, the end of the edge
            // (no stop part of the way), from where the train is, not from
            // where it started.
            let expected = try Self.sent(moved, Self.first, to: Self.mid)
            XCTAssertEqual(expected.train(id: Self.first)?.movement.remainingEdges, [])
            XCTAssertNil(expected.train(id: Self.first)?.movement.end)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Sent Train 1 to Mid, 512 units along the track."))
        }
    }

    func testSendingTwiceWithoutTimePassingCommitsTheSamePath() async throws {
        let world = try makePlacedWorld(at: 1, facingEast: true)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.selectStation(Self.mid)
            session.sendSelectedTrain()
            let once = session.world

            session.sendSelectedTrain()
            session.applyTool()

            XCTAssertEqual(session.world, once, "a repeated press asks for the same path from the same place")
        }
    }

    func testNoPathChangesNothingAndKeepsTheCurrentPath() async throws {
        let world = try Self.sent(try makePlacedWorld(at: 3, facingEast: true), Self.first, to: Self.east)
        let remaining = try XCTUnwrap(world.train(id: Self.first)).movement.remainingEdges
        XCTAssertEqual(remaining, [.edge(4), .edge(5)])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            // Behind the train with no loop to turn round, and a station
            // with no platform.
            for (station, name) in [(Self.west, "West"), (Self.terminus, "Terminus")] {
                session.selectStation(station)
                session.sendSelectedTrain()
                XCTAssertEqual(session.world, world)
                XCTAssertEqual(
                    session.message,
                    StatusMessage(
                        kind: .failure,
                        text: "No route for Train 1 to \(name): it needs a platform on the track network as long as the train, that it can reach without turning back. Its path is unchanged."
                    )
                )
            }
            session.select(Self.emptyTile)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select the station to send Train 1 to."))
            XCTAssertEqual(session.selectedTrain?.movement.remainingEdges, remaining)

            // A failed request does not get in the way of the next one.
            session.selectStation(Self.east)
            session.sendSelectedTrain()
            XCTAssertEqual(session.message?.kind, .success)
            XCTAssertEqual(session.selectedTrain?.movement.remainingEdges, remaining)
        }
    }

    func testSendingWithoutATrainPlacementOrDestinationChangesNothing() async throws {
        let noTrain = try makeLineWorld()
        var unplaced = noTrain
        try unplaced.purchaseTrain(named: "Train 1")
        let placed = try makePlacedWorld()
        await MainActor.run { [unplaced] in
            let first = GameSession(world: noTrain)
            first.selectStation(Self.east)
            first.sendSelectedTrain()
            XCTAssertEqual(first.world, noTrain)
            XCTAssertEqual(first.message, StatusMessage(kind: .failure, text: "Buy a train first."))

            let second = GameSession(world: unplaced)
            second.selectStation(Self.east)
            second.sendSelectedTrain()
            XCTAssertEqual(second.world, unplaced)
            XCTAssertEqual(second.message, StatusMessage(kind: .failure, text: GameError.trainNotPlaced(Self.first).playerMessage(in: .english)))

            let third = GameSession(world: placed)
            third.sendSelectedTrain()
            XCTAssertEqual(third.world, placed)
            XCTAssertEqual(third.message, StatusMessage(kind: .failure, text: "Select the station to send Train 1 to."))
        }
    }

    func testOnlyTheSelectedTrainIsSent() async throws {
        var world = try makePlacedWorld(at: 1, facingEast: true)
        try world.purchaseTrain(named: "Train 2")
        try world.placeTrain(Self.second, at: Self.line.at(5, facingEast: false))
        let expected = try Self.sent(world, Self.second, to: Self.west)
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.selectTrain(Self.second)
            session.selectStation(Self.west)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected, "the path is Train 2's, from Train 2's position")
            XCTAssertEqual(session.world.train(id: Self.first), world.train(id: Self.first))
        }
    }

    // MARK: - Reversing and taking off

    func testReversingAndTakingOffGoThroughGameCore() async throws {
        var world = try Self.sent(try makePlacedWorld(at: 2, facingEast: true), Self.first, to: Self.east)
        try world.setTrainMovementRate(Self.first, to: 64)
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
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.trainNotPlaced(Self.first).playerMessage(in: .english)))
            session.reverseSelectedTrain()
            XCTAssertEqual(session.world, unplaced)
        }
    }

    // MARK: - The tool and the whole flow

    func testTheTrainToolPlacesAnUnplacedTrainAndSendsAPlacedOne() async throws {
        let world = try makeLineWorld()
        var placed = world
        try placed.purchaseTrain(named: "Train 1")
        // West's first platform is the last half of edge 1: facing east,
        // the head at its end, the end of the edge.
        try placed.placeTrain(Self.first, at: Self.line.at(1, facingEast: true))
        let expected = try Self.sent(placed, Self.first, to: Self.east)
        await MainActor.run { [placed, expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.selectStation(Self.west)
            session.applyTool()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Buy a train first."))

            session.purchaseTrain()
            session.applyTool()
            XCTAssertEqual(session.world, placed)

            session.selectStation(Self.east)
            session.applyTool()
            XCTAssertEqual(session.world, expected)
        }
    }

    /// Place, choose a destination, set a rate, find the path, commit,
    /// advance, read: the whole Stage M flow, checked against GameCore run
    /// directly.
    func testTheGameLoopMovesASentTrainExactlyAsGameCoreDoes() async throws {
        let world = try makeLineWorld(speed: .normal)
        var expected = world
        try expected.purchaseTrain(named: "Train 1")
        try expected.placeTrain(Self.first, at: Self.line.at(1, facingEast: true))
        try expected.setTrainMovementRate(Self.first, to: 384)
        expected = try Self.sent(expected, Self.first, to: Self.east)
        let committed = expected
        try expected.advance(ticks: 7)
        await MainActor.run { [committed, expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.purchaseTrain()
            session.selectStation(Self.west)
            session.applyTool()
            session.selectedTrainRate = 384
            session.selectStation(Self.east)
            session.applyTool()
            XCTAssertEqual(session.world, committed)

            // Nothing moves until the game loop advances the world.
            XCTAssertEqual(session.selectedTrain?.position, Self.line.at(1, facingEast: true))

            for _ in 0..<7 {
                session.advance(realElapsed: .milliseconds(100))
            }
            XCTAssertEqual(session.world, expected)
            // 7 × 384 = 2688 units: edges 2 and 3, and 640 along edge 4.
            XCTAssertEqual(session.selectedTrain?.position, Self.line.between(3, 4, offset: 640))
            XCTAssertEqual(session.selectedTrain?.positionText(in: .english), "Edge #4 forward, 640 units along")
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "Path: 1 more edge, Edge #5")

            // The rest of the way: 4096 − 2688 = 1408 more units.
            for _ in 0..<4 {
                session.advance(realElapsed: .milliseconds(100))
            }
            XCTAssertEqual(session.selectedTrain?.position, Self.line.at(5, facingEast: true))
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "No path ahead")
            XCTAssertEqual(session.selectedTrain?.positionText(in: .english), "Edge #5 forward, 1024 units along")
        }
    }

    func testPausedTimeNeverMovesATrain() async throws {
        var world = try Self.sent(try makePlacedWorld(at: 1, facingEast: true), Self.first, to: Self.east)
        try world.setTrainMovementRate(Self.first, to: 1_024)
        world.setSpeed(.paused)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.advance(realElapsed: .seconds(3))
            XCTAssertEqual(session.world, world)
        }
    }

    func testReadingWhatIsShownNeverChangesTheWorld() async throws {
        var world = try Self.sent(try makePlacedWorld(at: 1, facingEast: true), Self.first, to: Self.east)
        try world.setTrainMovementRate(Self.first, to: 300)
        try world.advance(ticks: 2)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            for _ in 0..<3 {
                let train = session.selectedTrain
                _ = train?.positionText
                _ = train?.pathText
                _ = train?.movement.rateText
                _ = session.selectedTrainRate
                if let position = train?.position {
                    _ = MapScale.center(of: position, in: session.world, tileSize: 32)
                    _ = MapScale.facing(of: position, in: session.world)
                }
            }
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.selectedTrain?.positionText(in: .english), "Edge #2 forward, 600 units along")
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "Path: 3 more edges, ending on Edge #5")
            XCTAssertEqual(session.selectedTrain?.movement.rateText(in: .english), "Rate 300 / min")
        }
    }
}

final class TrainDisplayTests: XCTestCase {
    func testPositionsReadAsGameCoreStoresThem() {
        XCTAssertEqual(
            TrainPosition.onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 256).displayText(in: .english),
            "Edge #3 forward, 256 units along"
        )
        XCTAssertEqual(
            TrainPosition.onEdge(TrackTraversal(edge: .edge(3), direction: .backward), offset: 0).displayText(in: .english),
            "Edge #3 backward, 0 units along"
        )
        XCTAssertEqual(Train(id: TrainID(rawValue: 1), name: "Train 1").positionText(in: .english), "Not on the track")
        XCTAssertEqual(Train(id: TrainID(rawValue: 1), name: "Train 1").pathText(in: .english), "No path ahead")
    }

    func testPathAndRateText() throws {
        var world = try makeWorld(balance: 100_000, speed: .normal)
        let line = TestLine(tiles: 5, row: 0)
        try line.build(in: &world)
        try world.purchaseTrain(named: "Train 1")
        let id = TrainID(rawValue: 1)
        try world.placeTrain(id, at: line.at(1, facingEast: true))
        XCTAssertEqual(world.train(id: id)?.pathText(in: .english), "No path ahead")
        XCTAssertEqual(world.train(id: id)?.movement.rateText(in: .english), "Rate 0 / min")

        try world.setTrainContinuation(id, along: line.path(from: 1, through: [2]), stoppingAt: nil)
        XCTAssertEqual(world.train(id: id)?.pathText(in: .english), "Path: 1 more edge, Edge #2")

        try world.setTrainContinuation(id, along: line.path(from: 1, through: [2, 3, 4]), stoppingAt: 512)
        try world.setTrainMovementRate(id, to: 1_536)
        try world.advance(ticks: 1)
        // Edge 2 and half of edge 3 behind it: edge 4 left, stopping half
        // way along it.
        XCTAssertEqual(world.train(id: id)?.pathText(in: .english), "Path: 1 more edge, Edge #4, stopping 512 units along it")
        XCTAssertEqual(world.train(id: id)?.movement.rateText(in: .english), "Rate 1536 / min")
    }
}
