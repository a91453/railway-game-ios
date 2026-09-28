import Foundation
import GameCore
import XCTest

/// Train movement: each basic step a train travels its rate along the rest
/// of its link and then its explicit continuation, and time can only
/// advance as a whole batch.
///
/// Expected positions are worked out by hand from the rules (1024 units per
/// link) and written out, never taken from a previous run.
final class TrainMovementTests: XCTestCase {
    // A line along y = 5 with a branch south at d:
    //
    //   a - b - c - d - e - f - g
    //               |
    //               s1
    //               |
    //               s2
    private let a = GridPosition(x: 1, y: 5)
    private let b = GridPosition(x: 2, y: 5)
    private let c = GridPosition(x: 3, y: 5)
    private let d = GridPosition(x: 4, y: 5)
    private let e = GridPosition(x: 5, y: 5)
    private let f = GridPosition(x: 6, y: 5)
    private let g = GridPosition(x: 7, y: 5)
    private let s1 = GridPosition(x: 4, y: 6)
    private let s2 = GridPosition(x: 4, y: 7)
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)

    private func makeLineWorld(trainCount: Int = 1, speed: GameSpeed = .normal) throws -> GameWorld {
        var world = try makeWorld(balance: 100_000)
        try world.buildTrack(at: a, connections: .east)
        for tile in [b, c, e, f] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: d, connections: [.east, .south, .west])
        try world.buildTrack(at: g, connections: .west)
        try world.buildTrack(at: s1, connections: [.north, .south])
        try world.buildTrack(at: s2, connections: .north)
        for number in 0..<trainCount {
            try world.purchaseTrain(named: "Local \(number + 1)")
        }
        world.setSpeed(speed)
        return world
    }

    private func train(_ id: TrainID, in world: GameWorld) throws -> Train {
        try XCTUnwrap(world.train(id: id))
    }

    /// Every placed train is at a track node or strictly inside a joined
    /// link: movement never produces offset 0 or 1024.
    private func assertCanonical(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        for train in world.trains {
            switch train.position {
            case nil:
                XCTAssertEqual(train.movement, .idle, file: file, line: line)
            case .atNode(let tile, _)?:
                XCTAssertNotNil(world.track(at: tile), "\(train.id)", file: file, line: line)
            case .onLink(let from, let to, let offset)?:
                XCTAssertTrue((1...1023).contains(offset), "\(train.id) offset \(offset)", file: file, line: line)
                XCTAssertTrue(world.isConnected(from, to: to), "\(train.id)", file: file, line: line)
            }
        }
    }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    private func roundTrip(_ world: GameWorld) throws -> GameWorld {
        try JSONDecoder().decode(GameWorld.self, from: encode(world))
    }

    // MARK: - Defaults

    func testTrainsStartIdleAndIdleTrainsNeverMove() throws {
        var world = try makeLineWorld()
        XCTAssertEqual(try train(first, in: world).movement, .idle)
        XCTAssertEqual(TrainMovement.idle.rate, 0)
        XCTAssertEqual(TrainMovement.idle.continuation, [])
        XCTAssertEqual(TrainMovement.idle.cursor, 0)

        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 100))
        XCTAssertEqual(try train(first, in: world).movement, .idle)
        try world.advance(ticks: 50)

        XCTAssertEqual(try train(first, in: world).position, .onLink(from: a, to: b, offset: 100))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 50))
    }

    // MARK: - The kernel, through basic steps

    /// The worked example: A->B at 256 with continuation [C, D], then 1300,
    /// 124 and 1148 units in three basic steps.
    func testTheWorkedExampleAcrossThreeSteps() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 256))
        try world.setTrainContinuation(first, to: [c, d])

        // 768 to b, then 532 of the remaining 1300 into b->c: entry c entered.
        try world.setTrainMovementRate(first, to: 1300)
        try world.advance(ticks: 1)
        var train = try train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: b, to: c, offset: 532))
        XCTAssertEqual(train.movement.continuation, [c, d])
        XCTAssertEqual(train.movement.cursor, 1)
        XCTAssertEqual(Array(train.movement.remainingContinuation), [d])

        // 124 more on the same link; nothing entered.
        try world.setTrainMovementRate(first, to: 124)
        try world.advance(ticks: 1)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: b, to: c, offset: 656))
        XCTAssertEqual(train.movement.cursor, 1)

        // 368 to c, then 780 into c->d: the last entry is entered, so the
        // continuation is spent and stored as empty.
        try world.setTrainMovementRate(first, to: 1148)
        try world.advance(ticks: 1)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: c, to: d, offset: 780))
        XCTAssertEqual(train.movement.continuation, [])
        XCTAssertEqual(train.movement.cursor, 0)
        XCTAssertEqual(train.movement.rate, 1148)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 3))
    }

    func testZeroDistanceChangesNothing() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 256))
        try world.setTrainContinuation(first, to: [c])
        let before = world

        try world.advance(ticks: 0)
        XCTAssertEqual(world, before)

        try world.advance(ticks: 3)
        var expected = before
        try expected.advance(ticks: 3)
        XCTAssertEqual(world, expected)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: a, to: b, offset: 256), "rate 0")
    }

    func testPartialAndExactArrival() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: b, to: c, offset: 1000))
        try world.setTrainContinuation(first, to: [d])
        try world.setTrainMovementRate(first, to: 23)

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: b, to: c, offset: 1023))

        // Exactly the one unit left: at c, facing east, and d not entered
        // even though b->c->d is open and the rate allows more next step.
        try world.setTrainMovementRate(first, to: 1)
        try world.advance(ticks: 1)
        var train = try train(first, in: world)
        XCTAssertEqual(train.position, .atNode(c, heading: .east))
        XCTAssertEqual(train.movement.cursor, 0)
        XCTAssertEqual(train.movement.continuation, [d])

        // The next unit enters c->d.
        try world.advance(ticks: 1)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: c, to: d, offset: 1))
        XCTAssertEqual(train.movement.continuation, [], "spent")
    }

    func testExactArrivalDoesNotLookAtTheNextLink() throws {
        // The next entry is blocked; arriving exactly is the same either way.
        var open = try makeLineWorld()
        try open.placeTrain(first, at: .onLink(from: b, to: c, offset: 512))
        try open.setTrainContinuation(first, to: [d, e])
        try open.setTrainMovementRate(first, to: 512)
        var blocked = open
        try blocked.removeTrack(at: d)

        try open.advance(ticks: 1)
        try blocked.advance(ticks: 1)

        for world in [open, blocked] {
            let train = try train(first, in: world)
            XCTAssertEqual(train.position, .atNode(c, heading: .east))
            XCTAssertEqual(train.movement.cursor, 0)
            XCTAssertEqual(train.movement.continuation, [d, e])
        }
    }

    func testOneStepCrossesManyLinksAndTurnsExactlyWhereTold() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        // a -> b -> c -> d, then right (south) at the junction to s1, s2.
        try world.setTrainContinuation(first, to: [b, c, d, s1, s2])
        // a->b, b->c, c->d: 3072 units; the last 100 go into d->s1.
        try world.setTrainMovementRate(first, to: 3 * 1024 + 100)

        try world.advance(ticks: 1)

        let train = try train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: d, to: s1, offset: 100))
        XCTAssertEqual(train.movement.continuation, [b, c, d, s1, s2])
        XCTAssertEqual(train.movement.cursor, 4)
        assertCanonical(world)

        // The other exit of the same junction, told explicitly. Four links
        // end exactly at e with the continuation spent; 100 units are unused.
        var straight = try makeLineWorld()
        try straight.placeTrain(first, at: .atNode(a, heading: .east))
        try straight.setTrainContinuation(first, to: [b, c, d, e])
        try straight.setTrainMovementRate(first, to: 4 * 1024 + 100)
        try straight.advance(ticks: 1)
        XCTAssertEqual(try self.train(first, in: straight).position, .atNode(e, heading: .east))
    }

    func testFiniteLoopsAreFollowedAndEnd() throws {
        var world = try makeWorld(balance: 100_000)
        let nw = GridPosition(x: 10, y: 10)
        let ne = GridPosition(x: 11, y: 10)
        let se = GridPosition(x: 11, y: 11)
        let sw = GridPosition(x: 10, y: 11)
        try world.buildTrack(at: nw, connections: [.east, .south])
        try world.buildTrack(at: ne, connections: [.west, .south])
        try world.buildTrack(at: se, connections: [.north, .west])
        try world.buildTrack(at: sw, connections: [.north, .east])
        try world.purchaseTrain(named: "Loop")
        world.setSpeed(.normal)
        try world.placeTrain(first, at: .atNode(nw, heading: .east))
        // Twice round the square, visiting nw again in the middle.
        let lap = [ne, se, sw, nw]
        try world.setTrainContinuation(first, to: lap + lap)
        try world.setTrainMovementRate(first, to: 3 * 1024)

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .atNode(sw, heading: .west))
        XCTAssertEqual(try train(first, in: world).movement.cursor, 3)

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .atNode(se, heading: .south))
        XCTAssertEqual(try train(first, in: world).movement.cursor, 6)

        // Two entries (sw, nw) left; the extra distance is not used.
        try world.advance(ticks: 1)
        let train = try train(first, in: world)
        XCTAssertEqual(train.position, .atNode(nw, heading: .north))
        XCTAssertEqual(train.movement.continuation, [])
    }

    func testAHugeRateEndsWithTheContinuationWithoutOverflow() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 1023))
        try world.setTrainContinuation(first, to: [c, d, e, f, g])
        try world.setTrainMovementRate(first, to: .max)

        try world.advance(ticks: 1)

        let train = try train(first, in: world)
        XCTAssertEqual(train.position, .atNode(g, heading: .east))
        XCTAssertEqual(train.movement.rate, .max)
        XCTAssertEqual(train.movement.continuation, [])
        assertCanonical(world)

        // g is a dead end: more steps change nothing.
        let atEnd = world
        try world.advance(ticks: 1000)
        XCTAssertEqual(world.trains, atEnd.trains)
    }

    func testWithoutAContinuationATrainRunsToTheEndOfItsLinkAndStops() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: c, to: d, offset: 24))
        try world.setTrainMovementRate(first, to: 400)

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: c, to: d, offset: 424))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: c, to: d, offset: 824))
        // 200 to d; the other 200 are unused. d has exits east and south,
        // and neither is taken.
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))
        try world.advance(ticks: 5)
        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))
    }

    func testAtANodeARateAloneNeverChoosesAWay() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(d, heading: .east))
        try world.setTrainMovementRate(first, to: 5000)

        try world.advance(ticks: 10)

        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))
    }

    // MARK: - Commands

    func testMovementCommandsRejectUnknownAndUnplacedTrains() throws {
        var world = try makeLineWorld()
        let before = world

        XCTAssertThrowsGameError(try world.setTrainMovementRate(second, to: 10), .unknownTrain(second))
        XCTAssertThrowsGameError(try world.setTrainMovementRate(second, to: -1), .unknownTrain(second))
        XCTAssertThrowsGameError(try world.setTrainContinuation(second, to: []), .unknownTrain(second))
        XCTAssertThrowsGameError(try world.setTrainMovementRate(first, to: 10), .trainNotPlaced(first))
        XCTAssertThrowsGameError(try world.setTrainMovementRate(first, to: -1), .trainNotPlaced(first))
        XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: [b]), .trainNotPlaced(first))
        XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: []), .trainNotPlaced(first))
        XCTAssertEqual(world, before, "an unplaced train is never put on the track")
    }

    func testRatesMustNotBeNegative() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainMovementRate(first, to: 7)
        let before = world

        for rate: Int64 in [-1, -1024, .min] {
            XCTAssertThrowsGameError(try world.setTrainMovementRate(first, to: rate), .invalidMovementRate)
        }
        XCTAssertEqual(world, before)

        for rate: Int64 in [0, 1, 1024, .max] {
            try world.setTrainMovementRate(first, to: rate)
            XCTAssertEqual(try train(first, in: world).movement.rate, rate)
        }
    }

    func testContinuationsMustBeJoinedPathsWithoutUTurns() throws {
        var world = try makeLineWorld()
        let station = GridPosition(x: 5, y: 6)
        try world.buildStation(named: "Yard", at: station)
        // One-sided: f has no south exit, but the tile south of f points north.
        let belowF = GridPosition(x: 6, y: 6)
        try world.buildTrack(at: belowF, connections: .north)
        try world.placeTrain(first, at: .onLink(from: b, to: c, offset: 10))
        try world.setTrainContinuation(first, to: [d, e])
        let before = world

        let invalid: [[GridPosition]] = [
            [b], // straight back from the end of b->c
            [d, c], // back after one link
            [d, e, d], // back after two
            [c], // the node already ahead is not listed
            [e], // skips d
            [GridPosition(x: 4, y: 4)], // diagonal from c
            [d, GridPosition(x: 5, y: 6)], // diagonal, and a station
            [d, e, station], // a station
            [d, e, f, belowF], // one-sided exit
            [d, s1, s2, GridPosition(x: 4, y: 8)], // empty tile
            [d, e, f, g, GridPosition(x: 8, y: 5)], // g has no east exit
            [d, d], // same tile
            [GridPosition(x: Int.max, y: 5)],
            [GridPosition(x: Int.min, y: Int.min)],
            [d, GridPosition(x: 4, y: -1)],
        ]
        for nodes in invalid {
            XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: nodes), .invalidContinuation)
        }
        XCTAssertEqual(world, before, "the old continuation is kept whole")
    }

    func testAtANodeTheHeadingDecidesWhatIsAUTurn() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(d, heading: .east))

        XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: [c]), .invalidContinuation)
        try world.setTrainContinuation(first, to: [e])
        try world.setTrainContinuation(first, to: [s1, s2])
        XCTAssertEqual(try train(first, in: world).movement.continuation, [s1, s2])

        // Leaving west needs a reverse first.
        try world.reverseTrain(first)
        try world.setTrainContinuation(first, to: [c, b])
        XCTAssertEqual(try train(first, in: world).movement.continuation, [c, b])
    }

    func testReplacingAContinuationStartsItsCursorAgain() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainContinuation(first, to: [b, c, d])
        try world.setTrainMovementRate(first, to: 1024 + 300)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: b, to: c, offset: 300))
        XCTAssertEqual(try train(first, in: world).movement.cursor, 2)

        // From the end of b->c, which is c.
        try world.setTrainContinuation(first, to: [d, s1])

        let train = try train(first, in: world)
        XCTAssertEqual(train.movement.continuation, [d, s1])
        XCTAssertEqual(train.movement.cursor, 0)
        XCTAssertEqual(train.position, .onLink(from: b, to: c, offset: 300), "setting a path never moves the train")
    }

    func testRateZeroHoldsATrainAndKeepsItsContinuation() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 512))
        try world.setTrainContinuation(first, to: [c, d])
        try world.setTrainMovementRate(first, to: 1024)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: b, to: c, offset: 512))

        try world.setTrainMovementRate(first, to: 0)
        try world.advance(ticks: 10)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: b, to: c, offset: 512))
        XCTAssertEqual(try train(first, in: world).movement.cursor, 1)

        try world.setTrainMovementRate(first, to: 1024)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: c, to: d, offset: 512))
    }

    func testClearingAContinuationDoesNotMoveTheTrain() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .onLink(from: b, to: c, offset: 100))
        try world.setTrainContinuation(first, to: [d, e])
        try world.setTrainMovementRate(first, to: 300)

        try world.setTrainContinuation(first, to: [])

        var train = try train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: b, to: c, offset: 100))
        XCTAssertEqual(train.movement.continuation, [])
        XCTAssertEqual(train.movement.cursor, 0)
        XCTAssertEqual(train.movement.rate, 300)
        // It still runs to the end of its link, then stops.
        try world.advance(ticks: 10)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .atNode(c, heading: .east))

        // To stop at once, the rate is set to 0.
        var held = try makeLineWorld()
        try held.placeTrain(first, at: .onLink(from: b, to: c, offset: 100))
        try held.setTrainMovementRate(first, to: 0)
        try held.advance(ticks: 10)
        XCTAssertEqual(try self.train(first, in: held).position, .onLink(from: b, to: c, offset: 100))
    }

    func testReversingClearsTheContinuationAndKeepsTheRate() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainContinuation(first, to: [b, c, d, e])
        try world.setTrainMovementRate(first, to: 1024 + 256)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: b, to: c, offset: 256))

        try world.reverseTrain(first)

        var train = try train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: c, to: b, offset: 768))
        XCTAssertEqual(train.movement.continuation, [])
        XCTAssertEqual(train.movement.cursor, 0)
        XCTAssertEqual(train.movement.rate, 1024 + 256)
        // Runs back to b and stops: the old path is not resumed or extended.
        try world.advance(ticks: 3)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .atNode(b, heading: .west))
    }

    func testUnplacingResetsMovementAndPlacingAgainStartsIdle() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainContinuation(first, to: [b, c])
        try world.setTrainMovementRate(first, to: 100)
        try world.advance(ticks: 1)

        try world.unplaceTrain(first)
        XCTAssertEqual(try train(first, in: world).movement, .idle)

        try world.placeTrain(first, at: .atNode(a, heading: .east))
        XCTAssertEqual(try train(first, in: world).movement, .idle)
        try world.advance(ticks: 20)
        XCTAssertEqual(try train(first, in: world).position, .atNode(a, heading: .east))
    }

    // MARK: - Track removed ahead, and rebuilt

    func testATrainWaitsAtTheLastNodeBeforeRemovedTrackAndResumesWhenRebuilt() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainContinuation(first, to: [b, c, d, e])
        try world.setTrainMovementRate(first, to: 700)
        // d is ahead, not under the train: removal is allowed.
        try world.removeTrack(at: d)

        // Step 1: 700 into a->b. Step 2: 324 to b, 376 into b->c. Step 3: 648
        // to c, where d is missing: the train waits at c and the last 52
        // units are dropped.
        try world.advance(ticks: 3)
        var train = try train(first, in: world)
        XCTAssertEqual(train.position, .atNode(c, heading: .east))
        XCTAssertEqual(train.movement.cursor, 2, "d is not consumed")
        XCTAssertEqual(train.movement.continuation, [b, c, d, e])

        // Waiting saves no distance.
        try world.advance(ticks: 50)
        XCTAssertEqual(try self.train(first, in: world), train)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 53))

        // A rebuild without the west exit is not a link yet.
        try world.buildTrack(at: d, connections: [.east, .south])
        try world.advance(ticks: 2)
        XCTAssertEqual(try self.train(first, in: world), train)
        try world.removeTrack(at: d)

        // The true rebuild: the next step uses only its own 700 units.
        try world.buildTrack(at: d, connections: [.east, .west])
        try world.advance(ticks: 1)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: c, to: d, offset: 700))
        XCTAssertEqual(train.movement.cursor, 3)

        // 324 to d, 376 into d->e: the continuation is spent.
        try world.advance(ticks: 1)
        train = try self.train(first, in: world)
        XCTAssertEqual(train.position, .onLink(from: d, to: e, offset: 376))
        XCTAssertEqual(train.movement.continuation, [])
    }

    func testTheWaitingTrainChecksOnlyItsOwnNextLink() throws {
        // At the junction d the named link south is gone; east is open but
        // is not taken instead.
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(c, heading: .east))
        try world.setTrainContinuation(first, to: [d, s1, s2])
        try world.setTrainMovementRate(first, to: 5000)
        try world.removeTrack(at: s1)

        try world.advance(ticks: 4)

        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))
        XCTAssertEqual(try train(first, in: world).movement.cursor, 1)
    }

    func testOneWaitingTrainDoesNotHoldBackOthersOrTheClock() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(c, heading: .east))
        try world.setTrainContinuation(first, to: [d, s1])
        try world.setTrainMovementRate(first, to: 1024)
        try world.removeTrack(at: s1)
        try world.placeTrain(second, at: .atNode(a, heading: .east))
        try world.setTrainContinuation(second, to: [b])
        try world.setTrainMovementRate(second, to: 256)

        try world.advance(ticks: 3)

        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))
        XCTAssertEqual(try train(second, in: world).position, .onLink(from: a, to: b, offset: 768))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 3))
    }

    func testReversingOrUnplacingAWaitingTrainForgetsItsPath() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(c, heading: .east))
        try world.setTrainContinuation(first, to: [d, e])
        try world.setTrainMovementRate(first, to: 2048)
        try world.removeTrack(at: e)
        try world.advance(ticks: 2)
        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))

        var reversed = world
        try reversed.reverseTrain(first)
        try reversed.buildTrack(at: e, connections: [.east, .west])
        try reversed.advance(ticks: 3)
        XCTAssertEqual(try train(first, in: reversed).position, .atNode(d, heading: .west))
        XCTAssertEqual(try train(first, in: reversed).movement.continuation, [])

        try world.unplaceTrain(first)
        try world.buildTrack(at: e, connections: [.east, .west])
        try world.placeTrain(first, at: .atNode(d, heading: .east))
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(first, in: world).position, .atNode(d, heading: .east))
        XCTAssertEqual(try train(first, in: world).movement, .idle)
    }

    // MARK: - Fixed-step orchestration

    /// Two trains, one of them blocked for a while, advanced as one batch or
    /// one tick at a time.
    private func makeBusyWorld(speed: GameSpeed) throws -> GameWorld {
        var world = try makeLineWorld(trainCount: 2, speed: speed)
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 5))
        try world.setTrainContinuation(first, to: [c, d, s1, s2])
        try world.setTrainMovementRate(first, to: 333)
        try world.placeTrain(second, at: .onLink(from: g, to: f, offset: 1000))
        try world.setTrainContinuation(second, to: [e, d, c])
        try world.setTrainMovementRate(second, to: 97)
        try world.removeTrack(at: s2)
        return world
    }

    func testAdvancingManyTicksIsAdvancingOneTickManyTimes() throws {
        for speed in [GameSpeed.normal, .double] {
            var batch = try makeBusyWorld(speed: speed)
            var single = batch

            try batch.advance(ticks: 57)
            for _ in 0..<57 {
                try single.advance(ticks: 1)
            }

            XCTAssertEqual(batch, single, "\(speed)")
            assertCanonical(batch)
        }
    }

    func testOneTickAtDoubleSpeedIsTwoTicksAtNormalSpeed() throws {
        var double = try makeBusyWorld(speed: .double)
        var normal = try makeBusyWorld(speed: .normal)

        for _ in 0..<20 {
            try double.advance(ticks: 1)
            try normal.advance(ticks: 2)
            XCTAssertEqual(double.trains, normal.trains)
            XCTAssertEqual(double.clock.now, normal.clock.now)
        }
        // Only the speed setting itself differs.
        double.setSpeed(.normal)
        XCTAssertEqual(double, normal)
    }

    func testPausedTicksMoveNothingAndResumingCarriesOn() throws {
        var world = try makeBusyWorld(speed: .normal)
        try world.advance(ticks: 4)
        let beforePause = world

        world.pause()
        try world.advance(ticks: 1000)
        XCTAssertEqual(world.trains, beforePause.trains)
        XCTAssertEqual(world.clock.now, beforePause.clock.now)

        world.resume()
        try world.advance(ticks: 6)
        var uninterrupted = beforePause
        try uninterrupted.advance(ticks: 6)
        XCTAssertEqual(world, uninterrupted)
    }

    func testEachTrainMovesAsIfItWereAlone() throws {
        var together = try makeBusyWorld(speed: .normal)
        var onlyFirst = together
        try onlyFirst.setTrainMovementRate(second, to: 0)
        var onlySecond = together
        try onlySecond.setTrainMovementRate(first, to: 0)

        try together.advance(ticks: 25)
        try onlyFirst.advance(ticks: 25)
        try onlySecond.advance(ticks: 25)

        XCTAssertEqual(together.train(id: first)?.position, onlyFirst.train(id: first)?.position)
        XCTAssertEqual(together.train(id: first)?.movement.cursor, onlyFirst.train(id: first)?.movement.cursor)
        XCTAssertEqual(together.train(id: second)?.position, onlySecond.train(id: second)?.position)
        XCTAssertEqual(together.trains.map(\.id), [first, second], "trains stay in ID order")
    }

    func testSameCommandsGiveTheSameWorldAndSave() throws {
        var firstRun = try makeBusyWorld(speed: .double)
        var secondRun = try makeBusyWorld(speed: .double)

        try firstRun.advance(ticks: 13)
        try secondRun.advance(ticks: 13)

        XCTAssertEqual(firstRun, secondRun)
        XCTAssertEqual(try encode(firstRun), try encode(secondRun))
    }

    func testAHugeBatchEndsQuicklyOnceNothingMoves() throws {
        // A billion minutes at 1x. The train finishes its continuation in a
        // few steps; after that no step can change anything, so the clock
        // moves on without running the rest one by one.
        var world = try makeBusyWorld(speed: .normal)
        try world.advance(ticks: 1_000_000_000)

        XCTAssertEqual(world.clock.now, GameTime(minutes: 1_000_000_000))
        XCTAssertEqual(try train(first, in: world).position, .atNode(s1, heading: .south), "waits for s2")
        XCTAssertEqual(try train(second, in: world).position, .atNode(c, heading: .west))
        var stepwise = try makeBusyWorld(speed: .normal)
        try stepwise.advance(ticks: 200)
        XCTAssertEqual(world.trains, stepwise.trains)
    }

    // MARK: - Clock capacity

    private func worldNearTheEndOfTime(minutesLeft: Int64, speed: GameSpeed) throws -> GameWorld {
        var world = try GameWorld(
            width: 20, height: 20,
            economy: GameEconomy(balance: 100_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: .max - minutesLeft), speed: speed)
        )
        try world.buildTrack(at: a, connections: .east)
        try world.buildTrack(at: b, connections: [.east, .west])
        try world.purchaseTrain(named: "Late")
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 1))
        try world.setTrainMovementRate(first, to: 1)
        return world
    }

    func testTheLastMinutesCanBeReachedExactly() throws {
        var world = try worldNearTheEndOfTime(minutesLeft: 3, speed: .normal)
        try world.advance(ticks: 0)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(minutes: .max))
        XCTAssertEqual(try train(first, in: world).position, .onLink(from: a, to: b, offset: 4))

        var double = try worldNearTheEndOfTime(minutesLeft: 4, speed: .double)
        try double.advance(ticks: 2)
        XCTAssertEqual(double.clock.now, GameTime(minutes: .max))
    }

    func testABatchPastTheEndOfTimeIsRejectedWhole() throws {
        let cases: [(minutesLeft: Int64, speed: GameSpeed, ticks: Int)] = [
            (3, .normal, 4), // one step too many
            (4, .double, 3), // six steps, four left
            (5, .double, 3), // six steps, five left
            (.max, .double, .max), // ticks x 2 overflows
            (.max - 1, .normal, .max), // now + steps overflows
        ]
        for (minutesLeft, speed, ticks) in cases {
            var world = try worldNearTheEndOfTime(minutesLeft: minutesLeft, speed: speed)
            let before = world

            XCTAssertThrowsGameError(try world.advance(ticks: ticks), .clockOverflow)

            XCTAssertEqual(world, before, "\(minutesLeft) \(speed) \(ticks): no train or minute moved")
        }
    }

    func testPausedBatchesNeverOverflow() throws {
        var world = try worldNearTheEndOfTime(minutesLeft: 0, speed: .paused)
        let before = world

        try world.advance(ticks: .max)

        XCTAssertEqual(world, before)
    }

    func testTheClockAloneChecksCapacityTheSameWay() throws {
        var clock = GameClock(now: GameTime(minutes: .max - 2), speed: .double)
        XCTAssertThrowsGameError(try clock.advance(ticks: 2), .clockOverflow)
        XCTAssertEqual(clock.now, GameTime(minutes: .max - 2))
        try clock.advance(ticks: 1)
        XCTAssertEqual(clock.now, GameTime(minutes: .max))

        var fresh = GameClock(speed: .double)
        XCTAssertThrowsGameError(try fresh.advance(ticks: .max), .clockOverflow)
        XCTAssertEqual(fresh.now, .zero)
        fresh.pause()
        try fresh.advance(ticks: .max)
        XCTAssertEqual(fresh.now, .zero)
    }

    // MARK: - Saving

    func testSavingMidJourneyAndContinuingMatchesNotSaving() throws {
        var world = try makeBusyWorld(speed: .normal)
        try world.advance(ticks: 5)
        XCTAssertGreaterThan(try train(first, in: world).movement.cursor, 0)

        var loaded = try roundTrip(world)
        XCTAssertEqual(loaded, world)

        try world.advance(ticks: 30)
        try loaded.advance(ticks: 30)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try loaded.purchaseTrain(named: "Next").id, TrainID(rawValue: 3))
    }

    func testAWorldWaitingForTrackSavesAndResumesAfterTheRebuild() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.setTrainContinuation(first, to: [b, c, d, s1, s2])
        try world.setTrainMovementRate(first, to: 1500)
        try world.removeTrack(at: d)
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(first, in: world).position, .atNode(c, heading: .east))

        // d, s1 and s2 of the continuation are not all joined any more, and
        // the save is still valid.
        var loaded = try roundTrip(world)
        XCTAssertEqual(loaded, world)

        try world.buildTrack(at: d, connections: [.east, .south, .west])
        try loaded.buildTrack(at: d, connections: [.east, .south, .west])
        // c->d, then 476 into d->s1; 548 to s1, 952 into s1->s2; 72 to s2.
        try world.advance(ticks: 3)
        try loaded.advance(ticks: 3)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try train(first, in: world).position, .atNode(s2, heading: .south))
    }

    func testIdleTrainsAreSavedWithoutAMovementAndOldSavesReadAsIdle() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(a, heading: .east))
        try world.placeTrain(second, at: .atNode(c, heading: .east))
        try world.setTrainMovementRate(second, to: 10)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]])

        XCTAssertNil(trains[0]["movement"])
        XCTAssertNotNil(trains[1]["movement"])

        // A save from before movement existed: trains without "movement".
        let old = try JSONDecoder().decode(Train.self, from: Data(#"{"id": 1, "name": "A", "position": {"atNode": {"tile": {"x": 1, "y": 5}, "heading": {"east": {}}}}}"#.utf8))
        XCTAssertEqual(old.movement, .idle)
    }

    private func savedTrain(position: String?, movement: String) -> Data {
        let position = position.map { #", "position": \#($0)"# } ?? ""
        return Data(#"{"id": 1, "name": "A"\#(position), "movement": \#(movement)}"#.utf8)
    }

    func testMalformedMovementIsRejectedNotReadAsIdle() {
        // Positions on the line: c = (3, 5), d = (4, 5), e = (5, 5).
        let atC = #"{"atNode": {"tile": {"x": 3, "y": 5}, "heading": {"east": {}}}}"#
        let bToC = #"{"onLink": {"from": {"x": 2, "y": 5}, "to": {"x": 3, "y": 5}, "offset": 300}}"#
        func movement(rate: String = "10", nodes: String = #"[{"x": 4, "y": 5}, {"x": 5, "y": 5}]"#, cursor: String = "0") -> String {
            #"{"rate": \#(rate), "continuation": \#(nodes), "cursor": \#(cursor)}"#
        }
        let malformed: [(position: String?, movement: String)] = [
            (atC, "null"),
            (atC, "{}"),
            (atC, movement(rate: "-1")),
            (atC, movement(rate: "1.5")),
            (atC, movement(rate: #""fast""#)),
            (atC, movement(cursor: "-1")),
            (atC, movement(cursor: "2")), // spent but not emptied
            (atC, movement(cursor: "3")),
            (atC, movement(nodes: "[]", cursor: "1")),
            (atC, movement(nodes: #"[{"x": 4, "y": 5}, {"x": 6, "y": 5}]"#)), // gap
            (atC, movement(nodes: #"[{"x": 4, "y": 5}, {"x": 3, "y": 5}]"#)), // U-turn inside
            (atC, movement(nodes: #"[{"x": 4, "y": 5}, {"x": 4, "y": 5}]"#)), // same tile
            (atC, movement(nodes: #"[{"x": 2, "y": 5}]"#)), // U-turn from the heading
            (atC, movement(nodes: #"[{"x": 5, "y": 5}]"#)), // not next to c
            (atC, movement(nodes: #"[{"x": 9223372036854775807, "y": 5}]"#)),
            (bToC, movement(nodes: #"[{"x": 2, "y": 5}]"#)), // back along the link
            (bToC, movement(nodes: #"[{"x": 3, "y": 5}, {"x": 4, "y": 5}]"#)), // lists c, the node ahead
            // Entered entries must lead to where the train is.
            (bToC, movement(nodes: #"[{"x": 4, "y": 5}, {"x": 5, "y": 5}]"#, cursor: "1")),
            (atC, movement(nodes: #"[{"x": 3, "y": 4}, {"x": 3, "y": 5}, {"x": 4, "y": 5}]"#, cursor: "2")), // arrived heading south, not east
            (nil, movement()), // an unplaced train is idle
            (nil, movement(nodes: "[]")),
        ]
        for (position, movement) in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(Train.self, from: savedTrain(position: position, movement: movement)), movement)
        }

        // The same shapes, consistent: accepted.
        let valid: [(position: String?, movement: String)] = [
            (atC, movement()),
            (atC, movement(nodes: "[]")),
            (bToC, movement(nodes: #"[{"x": 4, "y": 5}]"#)),
            (bToC, movement(nodes: #"[{"x": 2, "y": 5}, {"x": 3, "y": 5}, {"x": 4, "y": 5}]"#, cursor: "2")),
            (atC, movement(nodes: #"[{"x": 2, "y": 5}, {"x": 3, "y": 5}, {"x": 4, "y": 5}]"#, cursor: "2")),
            (atC, movement(nodes: #"[{"x": 3, "y": 5}, {"x": 4, "y": 5}]"#, cursor: "1")),
        ]
        for (position, movement) in valid {
            XCTAssertNoThrow(try JSONDecoder().decode(Train.self, from: savedTrain(position: position, movement: movement)), movement)
        }
    }

    func testWorldDecodingKeepsTheCurrentPositionRuleAndTheMapBounds() throws {
        var world = try makeLineWorld()
        try world.buildTrack(at: GridPosition(x: 19, y: 5), connections: [.east, .west])
        try world.placeTrain(first, at: .atNode(c, heading: .east))
        try world.setTrainContinuation(first, to: [d, e])
        try world.setTrainMovementRate(first, to: 5)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])

        func decode(_ change: (inout [String: Any]) -> Void) throws -> GameWorld {
            var object = saved
            var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
            change(&trains[0])
            object["trains"] = trains
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }

        XCTAssertEqual(try decode { _ in }, world)
        // A continuation that leaves the map (20 x 20) from track at its edge.
        XCTAssertThrowsError(try decode { train in
            train["position"] = ["atNode": ["tile": ["x": 19, "y": 5], "heading": ["east": [String: Any]()]]]
            train["movement"] = ["rate": 5, "continuation": [["x": 20, "y": 5]], "cursor": 0]
        })
        // The current position must still be on track.
        XCTAssertThrowsError(try decode { train in
            train["position"] = ["atNode": ["tile": ["x": 3, "y": 4], "heading": ["east": [String: Any]()]]]
            train["movement"] = ["rate": 5, "continuation": [["x": 4, "y": 4]], "cursor": 0]
        })
    }
}
