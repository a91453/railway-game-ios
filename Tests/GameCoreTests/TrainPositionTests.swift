import Foundation
import GameCore
import XCTest

/// Train positions: unplaced, at a node, or strictly inside a link between
/// two joined track tiles, with 1024 units per link.
///
/// Positions and neighbouring tiles are written out rather than computed, so
/// a wrong step, `opposite` or offset rule in GameCore cannot make these
/// expectations wrong too.
final class TrainPositionTests: XCTestCase {
    private let center = GridPosition(x: 5, y: 5)
    private let north = GridPosition(x: 5, y: 4)
    private let east = GridPosition(x: 6, y: 5)
    private let south = GridPosition(x: 5, y: 6)
    private let west = GridPosition(x: 4, y: 5)
    private let allExits: TrackConnections = [.north, .east, .south, .west]
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)

    /// A four-way junction at ``center`` joined to a one-exit piece on every
    /// side, a station at (8, 8), and `trainCount` unplaced trains.
    private func makeJunctionWorld(trainCount: Int = 1) throws -> GameWorld {
        var world = try makeWorld(balance: 100_000)
        try world.buildTrack(at: center, connections: allExits)
        try world.buildTrack(at: north, connections: .south)
        try world.buildTrack(at: east, connections: .west)
        try world.buildTrack(at: south, connections: .north)
        try world.buildTrack(at: west, connections: .east)
        try world.buildStation(named: "Depot", at: GridPosition(x: 8, y: 8))
        for number in 0..<trainCount {
            try world.purchaseTrain(named: "Local \(number + 1)")
        }
        return world
    }

    private func position(of id: TrainID, in world: GameWorld) -> TrainPosition? {
        world.train(id: id)?.position
    }

    /// Where a position is, in units from the map's origin tile centre:
    /// tile centres are 1024 units apart. Only for small coordinates.
    private func point(of position: TrainPosition) -> (x: Int64, y: Int64) {
        switch position {
        case .atNode(let tile, _):
            return (Int64(tile.x) * 1024, Int64(tile.y) * 1024)
        case .onLink(let from, let to, let offset):
            return (
                Int64(from.x) * 1024 + Int64(to.x - from.x) * offset,
                Int64(from.y) * 1024 + Int64(to.y - from.y) * offset
            )
        case .onEdge:
            preconditionFailure("point(of:) is for positions on the grid")
        }
    }

    // MARK: - Purchase

    func testTheLinkLengthIs1024Units() {
        XCTAssertEqual(TrainPosition.linkLength, 1024)
    }

    func testPurchasedTrainsAreUnplacedWithTheirIDNameAndCost() throws {
        var world = try makeJunctionWorld(trainCount: 0)
        let balance = world.economy.balance

        let train = try world.purchaseTrain(named: "Local 1")

        XCTAssertEqual(train.id, first)
        XCTAssertEqual(train.name, "Local 1")
        XCTAssertNil(train.position)
        XCTAssertEqual(world.train(id: first), train)
        XCTAssertNil(world.train(id: second))
        XCTAssertEqual(world.economy.balance, balance - testCosts.train)
        // Track is available, but a new train is never put on it.
        XCTAssertEqual(world.trains.map(\.position), [nil])
    }

    // MARK: - Placement

    func testTrainsCanBePlacedOnLinksInEveryDirection() throws {
        let world = try makeJunctionWorld()
        for neighbor in [north, east, south, west] {
            for position in [
                TrainPosition.onLink(from: center, to: neighbor, offset: 1),
                .onLink(from: neighbor, to: center, offset: 1023),
                .onLink(from: center, to: neighbor, offset: 512),
            ] {
                var placed = world

                try placed.placeTrain(first, at: position)

                XCTAssertEqual(self.position(of: first, in: placed), position)
                XCTAssertEqual(placed.economy.balance, world.economy.balance, "Placement is free")
                XCTAssertEqual(placed.map, world.map)
                XCTAssertEqual(placed.clock, world.clock)
            }
        }
    }

    func testTrainsCanBePlacedAtANodeFacingAnyDirection() throws {
        let world = try makeJunctionWorld()
        for tile in [center, north, east] {
            for heading in TrackDirection.allCases {
                var placed = world

                try placed.placeTrain(first, at: .atNode(tile, heading: heading))

                XCTAssertEqual(position(of: first, in: placed), .atNode(tile, heading: heading))
                XCTAssertEqual(placed.economy.balance, world.economy.balance)
            }
        }
    }

    func testIsolatedAndDeadEndTilesAreValidNodesForEveryHeading() throws {
        var world = try makeWorld(width: 6, height: 6, balance: 100_000)
        let isolated = GridPosition(x: 3, y: 3)
        let corner = GridPosition(x: 0, y: 0)
        try world.buildTrack(at: isolated, connections: .north)
        // Both exits lead over the map edge.
        try world.buildTrack(at: corner, connections: [.north, .west])
        try world.purchaseTrain(named: "Local 1")
        XCTAssertEqual(world.connectedNeighbors(of: isolated), [])
        XCTAssertEqual(world.connectedNeighbors(of: corner), [])

        for tile in [isolated, corner] {
            for heading in TrackDirection.allCases {
                var placed = world
                try placed.placeTrain(first, at: .atNode(tile, heading: heading))
                XCTAssertEqual(position(of: first, in: placed), .atNode(tile, heading: heading))
            }
        }
    }

    func testPlacingAnUnknownTrainIsRejectedFirst() throws {
        var world = try makeJunctionWorld()
        let before = world
        let unknown = TrainID(rawValue: 2)

        XCTAssertThrowsGameError(try world.placeTrain(unknown, at: .atNode(center, heading: .east)), .unknownTrain(unknown))
        XCTAssertThrowsGameError(
            try world.placeTrain(unknown, at: .onLink(from: center, to: east, offset: 0)),
            .unknownTrain(unknown)
        )
        XCTAssertThrowsGameError(
            try world.placeTrain(TrainID(rawValue: .min), at: .atNode(center, heading: .east)),
            .unknownTrain(TrainID(rawValue: .min))
        )
        XCTAssertEqual(world, before)
    }

    func testNodesMustBeTrackTilesInsideTheMap() throws {
        var world = try makeJunctionWorld()
        let before = world
        let tiles = [
            GridPosition(x: 0, y: 0), // empty
            GridPosition(x: 8, y: 8), // station
            GridPosition(x: -1, y: 5),
            GridPosition(x: 20, y: 5),
            GridPosition(x: 5, y: 20),
        ]
        for tile in tiles {
            XCTAssertThrowsGameError(try world.placeTrain(first, at: .atNode(tile, heading: .north)), .invalidTrainPosition)
        }
        XCTAssertEqual(world, before)
    }

    func testLinksMustJoinTwoAdjacentTracksWithFacingExits() throws {
        var world = try makeJunctionWorld()
        // East of `east`: a piece whose west exit faces a piece without an
        // east exit. North of `east`: a piece facing an exit-less side.
        let twoEast = GridPosition(x: 7, y: 5)
        try world.buildTrack(at: twoEast, connections: [.east, .west])
        let northEast = GridPosition(x: 6, y: 4)
        try world.buildTrack(at: northEast, connections: .west)
        let before = world

        let links: [(from: GridPosition, to: GridPosition)] = [
            (center, center), // same tile
            (center, northEast), // diagonal
            (center, twoEast), // a tile skipped
            (east, twoEast), // twoEast has a west exit, east has no east exit
            (twoEast, east),
            (north, northEast), // northEast points west at north, which has no east exit
            (center, GridPosition(x: 5, y: 3)), // skips north
            (south, GridPosition(x: 5, y: 7)), // empty end
            (GridPosition(x: 8, y: 7), GridPosition(x: 8, y: 8)), // empty to station
            (GridPosition(x: 0, y: 0), GridPosition(x: -1, y: 0)), // outside the map
        ]
        for (from, to) in links {
            XCTAssertThrowsGameError(
                try world.placeTrain(first, at: .onLink(from: from, to: to, offset: 512)),
                .invalidTrainPosition
            )
        }
        XCTAssertEqual(world, before)
    }

    func testLinksNextToAStationAreNotTrack() throws {
        var world = try makeWorld(balance: 100_000)
        let track = GridPosition(x: 2, y: 2)
        let station = GridPosition(x: 3, y: 2)
        try world.buildTrack(at: track, connections: [.east, .west])
        try world.buildStation(named: "Depot", at: station)
        try world.purchaseTrain(named: "Local 1")
        let before = world

        XCTAssertThrowsGameError(try world.placeTrain(first, at: .onLink(from: track, to: station, offset: 512)), .invalidTrainPosition)
        XCTAssertThrowsGameError(try world.placeTrain(first, at: .onLink(from: station, to: track, offset: 512)), .invalidTrainPosition)
        XCTAssertEqual(world, before)
    }

    func testLinkOffsetsMustLieStrictlyInsideTheLink() throws {
        let world = try makeJunctionWorld()

        for offset: Int64 in [.min, -1024, -1, 0, 1024, 1025, 2048, .max] {
            var rejected = world
            XCTAssertThrowsGameError(
                try rejected.placeTrain(first, at: .onLink(from: center, to: east, offset: offset)),
                .invalidTrainPosition
            )
            XCTAssertEqual(rejected, world, "\(offset)")
        }
        for offset: Int64 in [1, 2, 512, 1022, 1023] {
            var placed = world
            try placed.placeTrain(first, at: .onLink(from: center, to: east, offset: offset))
            XCTAssertEqual(position(of: first, in: placed), .onLink(from: center, to: east, offset: offset))
        }
    }

    func testExtremeCoordinatesAreRejectedWithoutTrapping() throws {
        var world = try makeJunctionWorld()
        let before = world
        let coordinates = [Int.min, Int.min + 1, -1, 0, 5, Int.max - 1, Int.max]

        for x in coordinates {
            for y in coordinates {
                let tile = GridPosition(x: x, y: y)
                if tile == GridPosition(x: 5, y: 5) { continue }
                XCTAssertThrowsGameError(try world.placeTrain(first, at: .atNode(tile, heading: .west)), .invalidTrainPosition)
                for other in [center, GridPosition(x: Int.min, y: Int.max), GridPosition(x: Int.max, y: Int.min)] {
                    XCTAssertThrowsGameError(
                        try world.placeTrain(first, at: .onLink(from: tile, to: other, offset: 512)),
                        .invalidTrainPosition
                    )
                    XCTAssertThrowsGameError(
                        try world.placeTrain(first, at: .onLink(from: other, to: tile, offset: 512)),
                        .invalidTrainPosition
                    )
                }
            }
        }
        // Neighbours at the edge of Int: adjacent in shape, but not on the map.
        let edgePairs: [(GridPosition, GridPosition)] = [
            (GridPosition(x: .max - 1, y: 0), GridPosition(x: .max, y: 0)),
            (GridPosition(x: .min, y: 0), GridPosition(x: .min + 1, y: 0)),
            (GridPosition(x: 0, y: .max), GridPosition(x: 0, y: .max - 1)),
            (GridPosition(x: .max, y: 0), GridPosition(x: .min, y: 0)),
        ]
        for (from, to) in edgePairs {
            XCTAssertThrowsGameError(try world.placeTrain(first, at: .onLink(from: from, to: to, offset: 512)), .invalidTrainPosition)
        }
        XCTAssertEqual(world, before)
    }

    func testPlacingAPlacedTrainIsRejectedBeforeCheckingThePosition() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 300))
        let before = world

        XCTAssertThrowsGameError(try world.placeTrain(first, at: .atNode(north, heading: .north)), .trainAlreadyPlaced(first))
        XCTAssertThrowsGameError(try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 300)), .trainAlreadyPlaced(first))
        XCTAssertThrowsGameError(try world.placeTrain(first, at: .atNode(GridPosition(x: 0, y: 0), heading: .north)), .trainAlreadyPlaced(first))
        XCTAssertEqual(world, before)
    }

    func testTrainsMayShareANodeOrALink() throws {
        var world = try makeJunctionWorld(trainCount: 3)
        let third = TrainID(rawValue: 3)

        try world.placeTrain(first, at: .atNode(center, heading: .east))
        try world.placeTrain(second, at: .atNode(center, heading: .east))
        try world.placeTrain(third, at: .onLink(from: east, to: center, offset: 1))

        XCTAssertEqual(world.trains.map(\.position), [
            .atNode(center, heading: .east),
            .atNode(center, heading: .east),
            .onLink(from: east, to: center, offset: 1),
        ])
    }

    // MARK: - Unplacing

    func testUnplacingKeepsTheTrainAndItsID() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: center, to: south, offset: 700))
        let balance = world.economy.balance

        try world.unplaceTrain(first)

        XCTAssertEqual(world.train(id: first), Train(id: first, name: "Local 1"))
        XCTAssertNil(position(of: first, in: world))
        XCTAssertEqual(world.economy.balance, balance, "Unplacing is free and refunds nothing")
        XCTAssertEqual(try world.purchaseTrain(named: "Local 2").id, second)

        try world.placeTrain(first, at: .atNode(west, heading: .west))
        XCTAssertEqual(position(of: first, in: world), .atNode(west, heading: .west))
    }

    func testUnplacingAnUnplacedOrUnknownTrainIsRejected() throws {
        var world = try makeJunctionWorld()
        let before = world

        XCTAssertThrowsGameError(try world.unplaceTrain(first), .trainNotPlaced(first))
        XCTAssertThrowsGameError(try world.unplaceTrain(second), .unknownTrain(second))
        XCTAssertEqual(world, before)

        try world.placeTrain(first, at: .atNode(center, heading: .north))
        try world.unplaceTrain(first)
        let unplaced = world
        XCTAssertThrowsGameError(try world.unplaceTrain(first), .trainNotPlaced(first))
        XCTAssertEqual(world, unplaced)
    }

    // MARK: - Reversing

    func testReversingAtANodeFlipsOnlyTheHeading() throws {
        let expected: [(TrackDirection, TrackDirection)] = [(.north, .south), (.east, .west), (.south, .north), (.west, .east)]
        for (heading, reversed) in expected {
            var world = try makeJunctionWorld()
            try world.placeTrain(first, at: .atNode(north, heading: heading))

            try world.reverseTrain(first)

            XCTAssertEqual(position(of: first, in: world), .atNode(north, heading: reversed))
        }
    }

    func testReversingOnALinkSwapsTheEndsAndMeasuresFromTheOtherEnd() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: west, to: center, offset: 256))

        try world.reverseTrain(first)

        XCTAssertEqual(position(of: first, in: world), .onLink(from: center, to: west, offset: 768))

        try world.reverseTrain(first)

        XCTAssertEqual(position(of: first, in: world), .onLink(from: west, to: center, offset: 256))
    }

    func testReversingNeverMovesTheTrainAndTwiceRestoresIt() throws {
        let world = try makeJunctionWorld()
        var positions = TrackDirection.allCases.map { TrainPosition.atNode(center, heading: $0) }
        for neighbor in [north, east, south, west] {
            for offset: Int64 in [1, 256, 512, 1023] {
                positions.append(.onLink(from: center, to: neighbor, offset: offset))
                positions.append(.onLink(from: neighbor, to: center, offset: offset))
            }
        }
        for original in positions {
            var reversed = world
            try reversed.placeTrain(first, at: original)

            try reversed.reverseTrain(first)
            let once = try XCTUnwrap(position(of: first, in: reversed))
            try reversed.reverseTrain(first)

            XCTAssertNotEqual(once, original, "\(original)")
            XCTAssertTrue(point(of: once) == point(of: original), "\(original) moved to \(once)")
            XCTAssertEqual(position(of: first, in: reversed), original)
            var placed = world
            try placed.placeTrain(first, at: original)
            XCTAssertEqual(reversed, placed, "Reversing twice changes nothing else")
        }
    }

    func testReversingAnUnplacedOrUnknownTrainIsRejected() throws {
        var world = try makeJunctionWorld()
        let before = world

        XCTAssertThrowsGameError(try world.reverseTrain(first), .trainNotPlaced(first))
        XCTAssertThrowsGameError(try world.reverseTrain(second), .unknownTrain(second))
        XCTAssertEqual(world, before, "Reversing never places a train")
    }

    // MARK: - Track that carries a train

    func testTheTileUnderATrainAtANodeCannotBeRemoved() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .atNode(north, heading: .north))
        let before = world

        XCTAssertThrowsGameError(try world.removeTrack(at: north), .trackInUse(north))
        XCTAssertEqual(world, before)
    }

    func testNeitherEndOfATrainsLinkCanBeRemoved() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 1))
        let before = world

        XCTAssertThrowsGameError(try world.removeTrack(at: center), .trackInUse(center))
        XCTAssertThrowsGameError(try world.removeTrack(at: east), .trackInUse(east))
        XCTAssertEqual(world, before)
    }

    func testTrackThatCarriesNoTrainCanStillBeRemoved() throws {
        var world = try makeJunctionWorld()
        let remote = GridPosition(x: 15, y: 15)
        try world.buildTrack(at: remote, connections: [.east, .west])
        try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 512))
        let balance = world.economy.balance

        try world.removeTrack(at: remote)
        // Joined to the train's link end, but not part of the link.
        try world.removeTrack(at: north)

        XCTAssertNil(world.track(at: remote))
        XCTAssertNil(world.track(at: north))
        XCTAssertEqual(world.economy.balance, balance, "Removal is still not refunded")
        XCTAssertEqual(position(of: first, in: world), .onLink(from: center, to: east, offset: 512))
    }

    func testTrackCanBeRemovedOnceTheTrainIsUnplaced() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: south, to: center, offset: 900))
        try world.unplaceTrain(first)
        let balance = world.economy.balance

        try world.removeTrack(at: south)
        try world.removeTrack(at: center)

        XCTAssertNil(world.track(at: south))
        XCTAssertNil(world.track(at: center))
        XCTAssertEqual(world.economy.balance, balance)
    }

    func testSharedTrackStaysProtectedUntilNoTrainIsOnIt() throws {
        var world = try makeJunctionWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(center, heading: .south))
        try world.placeTrain(second, at: .onLink(from: west, to: center, offset: 100))

        try world.unplaceTrain(first)
        let before = world
        XCTAssertThrowsGameError(try world.removeTrack(at: center), .trackInUse(center))
        XCTAssertEqual(world, before)

        try world.reverseTrain(second)
        XCTAssertThrowsGameError(try world.removeTrack(at: center), .trackInUse(center))
        XCTAssertThrowsGameError(try world.removeTrack(at: west), .trackInUse(west))

        try world.unplaceTrain(second)
        try world.removeTrack(at: center)
        try world.removeTrack(at: west)
        XCTAssertNil(world.track(at: center))
        XCTAssertNil(world.track(at: west))
    }

    func testRemovalChecksBoundsAndTrackBeforeTrains() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .atNode(center, heading: .north))
        let before = world
        let station = GridPosition(x: 8, y: 8)

        XCTAssertThrowsGameError(try world.removeTrack(at: GridPosition(x: -1, y: 5)), .outOfBounds(GridPosition(x: -1, y: 5)))
        XCTAssertThrowsGameError(try world.removeTrack(at: station), .noTrackToRemove(station))
        XCTAssertThrowsGameError(try world.removeTrack(at: GridPosition(x: 0, y: 0)), .noTrackToRemove(GridPosition(x: 0, y: 0)))
        XCTAssertEqual(world, before)
    }

    // MARK: - Time

    func testTimePassesAsBeforeWithoutMovingTrains() throws {
        var world = try makeJunctionWorld(trainCount: 2)
        try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 256))
        try world.placeTrain(second, at: .atNode(north, heading: .north))
        let positions = world.trains.map(\.position)

        world.setSpeed(.normal)
        try world.advance(ticks: 30)
        world.setSpeed(.double)
        try world.advance(ticks: 10)
        world.pause()
        try world.advance(ticks: 5)
        world.resume()
        try world.advance(ticks: 1)

        XCTAssertEqual(world.clock.now, GameTime(minutes: 52))
        XCTAssertEqual(world.clock.speed, .double)
        XCTAssertEqual(world.trains.map(\.position), positions)
    }

    // MARK: - Snapshots and determinism

    func testOlderSnapshotsKeepTheirOwnTrainPositions() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 256))
        let snapshot = world

        try world.reverseTrain(first)
        let reversed = world
        try world.unplaceTrain(first)

        XCTAssertEqual(position(of: first, in: snapshot), .onLink(from: center, to: east, offset: 256))
        XCTAssertEqual(position(of: first, in: reversed), .onLink(from: east, to: center, offset: 768))
        XCTAssertNil(position(of: first, in: world))
    }

    private func playTrainScript(on world: inout GameWorld) throws {
        try world.placeTrain(first, at: .onLink(from: center, to: east, offset: 256))
        try world.placeTrain(second, at: .atNode(south, heading: .south))
        try world.reverseTrain(first)
        try world.reverseTrain(second)
        try world.unplaceTrain(second)
        try world.placeTrain(second, at: .onLink(from: north, to: center, offset: 1000))
        world.setSpeed(.normal)
        try world.advance(ticks: 7)
    }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    func testSameCommandsGiveTheSamePositionsAndSave() throws {
        var firstRun = try makeJunctionWorld(trainCount: 2)
        var secondRun = try makeJunctionWorld(trainCount: 2)

        try playTrainScript(on: &firstRun)
        try playTrainScript(on: &secondRun)

        XCTAssertEqual(firstRun, secondRun)
        XCTAssertEqual(try encode(firstRun), try encode(secondRun))
        XCTAssertEqual(firstRun.trains.map(\.position), [
            .onLink(from: east, to: center, offset: 768),
            .onLink(from: north, to: center, offset: 1000),
        ])
    }

    // MARK: - Codable

    func testRoundTripKeepsPositionsAndTheNextTrainID() throws {
        var world = try makeJunctionWorld(trainCount: 3)
        try world.placeTrain(first, at: .onLink(from: center, to: west, offset: 256))
        try world.placeTrain(second, at: .atNode(east, heading: .east))

        var decoded = try JSONDecoder().decode(GameWorld.self, from: try encode(world))

        XCTAssertEqual(decoded, world)
        XCTAssertEqual(decoded.trains.map(\.position), [
            .onLink(from: center, to: west, offset: 256),
            .atNode(east, heading: .east),
            nil,
        ])
        XCTAssertEqual(try decoded.purchaseTrain(named: "Local 4").id, TrainID(rawValue: 4))
        try decoded.reverseTrain(first)
        XCTAssertEqual(position(of: first, in: decoded), .onLink(from: west, to: center, offset: 768))
    }

    func testUnplacedTrainsAreSavedWithoutAPosition() throws {
        let train = Train(id: first, name: "Local 1")

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(train)) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["id", "name"])
    }

    func testTrainsSavedBeforePositionsExistedDecodeAsUnplaced() throws {
        let train = try JSONDecoder().decode(Train.self, from: Data(#"{"id": 3, "name": "Local 3"}"#.utf8))
        XCTAssertEqual(train, Train(id: TrainID(rawValue: 3), name: "Local 3"))
        XCTAssertNil(train.position)

        // A whole world in the old format, where trains have only an ID and
        // a name: the placed train's position is left out.
        var world = try makeJunctionWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(center, heading: .east))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]]).map { train in
            var train = train
            train["position"] = nil
            return train
        }
        XCTAssertEqual(trains.map { Set($0.keys) }, [["id", "name"], ["id", "name"]])
        object["trains"] = trains

        var decoded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))

        try world.unplaceTrain(first)
        XCTAssertEqual(decoded, world)
        XCTAssertEqual(try decoded.purchaseTrain(named: "Local 3").id, TrainID(rawValue: 3))
    }

    func testMalformedTrainsAreRejectedNotReadAsUnplaced() {
        let trains = [
            #"{"id": 1, "name": "A", "position": null}"#,
            #"{"id": 1, "name": "A", "position": {}}"#,
            #"{"id": 1, "name": "A", "position": "unplaced"}"#,
            #"{"id": 1, "name": "A", "position": {"moving": {}}}"#,
            #"{"id": 1, "name": "A", "position": {"atNode": {"tile": {"x": 1, "y": 1}}}}"#,
        ]
        for json in trains {
            XCTAssertThrowsError(try JSONDecoder().decode(Train.self, from: Data(json.utf8)), json) { error in
                XCTAssertTrue(error is DecodingError, json)
            }
        }
    }

    func testPositionsDecodeInTheirSavedForm() throws {
        let node = #"{"atNode": {"tile": {"x": 2, "y": 3}, "heading": {"west": {}}}}"#
        let link = #"{"onLink": {"from": {"x": 2, "y": 3}, "to": {"x": 2, "y": 2}, "offset": 1023}}"#

        XCTAssertEqual(try JSONDecoder().decode(TrainPosition.self, from: Data(node.utf8)), .atNode(GridPosition(x: 2, y: 3), heading: .west))
        XCTAssertEqual(
            try JSONDecoder().decode(TrainPosition.self, from: Data(link.utf8)),
            .onLink(from: GridPosition(x: 2, y: 3), to: GridPosition(x: 2, y: 2), offset: 1023)
        )
        for position in [TrainPosition.atNode(GridPosition(x: 0, y: 7), heading: .south), .onLink(from: GridPosition(x: 4, y: 4), to: GridPosition(x: 3, y: 4), offset: 1)] {
            XCTAssertEqual(try JSONDecoder().decode(TrainPosition.self, from: JSONEncoder().encode(position)), position)
        }
    }

    func testMalformedPositionsAreRejected() {
        func link(from: String = #"{"x": 1, "y": 1}"#, to: String = #"{"x": 2, "y": 1}"#, offset: String = "512") -> String {
            #"{"onLink": {"from": \#(from), "to": \#(to), "offset": \#(offset)}}"#
        }
        let node = #"{"tile": {"x": 1, "y": 1}, "heading": {"east": {}}}"#
        let positions = [
            "{}",
            "null",
            "[]",
            #"{"moving": {}}"#,
            #"{"atNode": \#(node), "onLink": {"from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 512}}"#,
            #"{"atNode": {"tile": {"x": 1, "y": 1}}}"#,
            #"{"atNode": {"heading": {"east": {}}}}"#,
            #"{"atNode": {"tile": {"x": 1, "y": 1}, "heading": {"up": {}}}}"#,
            #"{"atNode": {"tile": {"x": 1, "y": 1}, "heading": "east"}}"#,
            #"{"onLink": {"from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}}}"#,
            link(offset: "0"),
            link(offset: "1024"),
            link(offset: "-1"),
            link(offset: "2048"),
            link(offset: "9223372036854775807"),
            link(offset: "-9223372036854775808"),
            link(offset: "9223372036854775808"),
            link(offset: "512.5"),
            link(offset: #""512""#),
            link(to: #"{"x": 1, "y": 1}"#), // same tile
            link(to: #"{"x": 2, "y": 2}"#), // diagonal
            link(to: #"{"x": 3, "y": 1}"#), // a tile skipped
            link(from: #"{"x": -9223372036854775808, "y": 1}"#, to: #"{"x": 9223372036854775807, "y": 1}"#),
            link(from: #"{"x": 9223372036854775807, "y": 1}"#, to: #"{"x": -9223372036854775808, "y": 1}"#),
            link(from: #"{"x": 0, "y": -9223372036854775808}"#, to: #"{"x": 0, "y": 9223372036854775807}"#),
        ]
        for json in positions {
            XCTAssertThrowsError(try JSONDecoder().decode(TrainPosition.self, from: Data(json.utf8)), json)
        }
    }

    /// A save whose train stands on track that is not there, or on a link
    /// that is not joined, is rejected rather than loaded.
    func testWorldDecodingRejectsTrainsOffTheTrack() throws {
        var world = try makeJunctionWorld()
        // One-sided: east of `east` has a west exit, `east` has no east exit.
        try world.buildTrack(at: GridPosition(x: 7, y: 5), connections: [.east, .west])
        try world.placeTrain(first, at: .atNode(center, heading: .north))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])

        func decode(position: Any) throws -> GameWorld {
            var object = saved
            var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
            trains[0]["position"] = position
            object["trains"] = trains
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }
        func node(_ x: Int, _ y: Int) -> Any {
            ["atNode": ["tile": ["x": x, "y": y], "heading": ["north": [String: Any]()]]]
        }
        func link(_ from: (Int, Int), _ to: (Int, Int), offset: Int = 512) -> Any {
            ["onLink": ["from": ["x": from.0, "y": from.1], "to": ["x": to.0, "y": to.1], "offset": offset]]
        }

        XCTAssertEqual(try decode(position: node(5, 5)), world)
        XCTAssertNoThrow(try decode(position: link((5, 5), (6, 5))))
        let offTrack: [Any] = [
            node(0, 0), // empty
            node(8, 8), // station
            node(-1, 5),
            node(20, 5),
            node(Int.min, Int.max),
            link((6, 5), (7, 5)), // one-sided
            link((5, 5), (5, 3)), // not adjacent
            link((8, 7), (8, 8)), // empty to station
            link((19, 0), (20, 0)), // leaves the map
        ]
        for position in offTrack {
            XCTAssertThrowsError(try decode(position: position), "\(position)") { error in
                guard case DecodingError.dataCorrupted = error else {
                    return XCTFail("Expected dataCorrupted, got \(error)")
                }
            }
        }
    }

    func testWorldDecodingRejectsATrainWhoseTrackIsMissingFromTheMap() throws {
        var world = try makeJunctionWorld()
        try world.placeTrain(first, at: .onLink(from: center, to: south, offset: 10))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
        var map = try XCTUnwrap(object["map"] as? [String: Any])
        var tiles = try XCTUnwrap(map["tiles"] as? [Any])
        let width = try XCTUnwrap(map["width"] as? Int)
        tiles[south.y * width + south.x] = ["empty": [String: Any]()]
        map["tiles"] = tiles
        object["map"] = map

        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }
    }
}
