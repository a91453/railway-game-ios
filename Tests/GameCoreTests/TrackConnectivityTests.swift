import Foundation
import GameCore
import XCTest

/// Track connectivity is derived from the map: two orthogonally adjacent
/// track tiles are joined when each has an exit toward the other.
///
/// Neighbouring positions are written out rather than computed, so a wrong
/// step or `opposite` in GameCore cannot make these expectations wrong too.
final class TrackConnectivityTests: XCTestCase {
    private let center = GridPosition(x: 5, y: 5)
    private let north = GridPosition(x: 5, y: 4)
    private let east = GridPosition(x: 6, y: 5)
    private let south = GridPosition(x: 5, y: 6)
    private let west = GridPosition(x: 4, y: 5)
    private let allExits: TrackConnections = [.north, .east, .south, .west]

    /// Builds one-exit pieces around ``center`` that each point back at it.
    private func buildMatchingNeighbors(in world: inout GameWorld) throws {
        try world.buildTrack(at: north, connections: .south)
        try world.buildTrack(at: east, connections: .west)
        try world.buildTrack(at: south, connections: .north)
        try world.buildTrack(at: west, connections: .east)
    }

    func testOppositeDirections() {
        XCTAssertEqual(TrackDirection.north.opposite, .south)
        XCTAssertEqual(TrackDirection.east.opposite, .west)
        XCTAssertEqual(TrackDirection.south.opposite, .north)
        XCTAssertEqual(TrackDirection.west.opposite, .east)
    }

    // MARK: - The link rule

    func testFacingExitsJoinInEveryDirection() throws {
        let cases: [(exit: TrackConnections, neighbor: GridPosition, exitBack: TrackConnections)] = [
            (.north, north, .south),
            (.east, east, .west),
            (.south, south, .north),
            (.west, west, .east),
        ]
        for (exit, neighbor, exitBack) in cases {
            var world = try makeWorld()
            try world.buildTrack(at: center, connections: exit)
            try world.buildTrack(at: neighbor, connections: exitBack)

            XCTAssertTrue(world.isConnected(center, to: neighbor), "\(neighbor)")
            XCTAssertTrue(world.isConnected(neighbor, to: center), "\(neighbor)")
            XCTAssertEqual(world.connectedNeighbors(of: center), [neighbor])
            XCTAssertEqual(world.connectedNeighbors(of: neighbor), [center])
        }
    }

    func testAnExitOnOnlyOneSideIsNotALink() throws {
        // The center points east, but its east neighbour has no west exit.
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: [.east, .west])
        try world.buildTrack(at: east, connections: [.north, .south])

        XCTAssertFalse(world.isConnected(center, to: east))
        XCTAssertFalse(world.isConnected(east, to: center))
        XCTAssertEqual(world.connectedNeighbors(of: center), [])
        XCTAssertEqual(world.connectedNeighbors(of: east), [])

        // The east neighbour points west, but the center has no east exit.
        world = try makeWorld()
        try world.buildTrack(at: center, connections: [.north, .south])
        try world.buildTrack(at: east, connections: [.east, .west])

        XCTAssertFalse(world.isConnected(center, to: east))
        XCTAssertFalse(world.isConnected(east, to: center))
        XCTAssertEqual(world.connectedNeighbors(of: center), [])
        XCTAssertEqual(world.connectedNeighbors(of: east), [])
    }

    func testEmptyTilesAndStationsAreNotTrack() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: allExits)
        try world.buildStation(named: "North", at: north)
        // east stays empty
        try world.buildTrack(at: south, connections: .north)
        try world.buildTrack(at: west, connections: [.east, .west])

        XCTAssertEqual(world.connectedNeighbors(of: center), [south, west])
        XCTAssertFalse(world.isConnected(center, to: north))
        XCTAssertFalse(world.isConnected(north, to: center))
        XCTAssertFalse(world.isConnected(center, to: east))
        XCTAssertFalse(world.isConnected(east, to: center))
        XCTAssertEqual(world.connectedNeighbors(of: north), [])
        XCTAssertEqual(world.connectedNeighbors(of: east), [])
    }

    func testOnlyOrthogonalNeighboursCanBeConnected() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: allExits)
        try buildMatchingNeighbors(in: &world)
        let diagonal = GridPosition(x: 6, y: 4)
        try world.buildTrack(at: diagonal, connections: allExits)
        let twoEast = GridPosition(x: 7, y: 5)
        try world.buildTrack(at: twoEast, connections: allExits)

        XCTAssertFalse(world.isConnected(center, to: center))
        XCTAssertFalse(world.isConnected(center, to: diagonal))
        XCTAssertFalse(world.isConnected(diagonal, to: center))
        XCTAssertFalse(world.isConnected(center, to: twoEast))
        XCTAssertFalse(world.isConnected(twoEast, to: center))
        XCTAssertEqual(world.connectedNeighbors(of: center), [north, east, south, west])
    }

    func testExitsOverTheMapEdgeDoNotWrapAround() throws {
        var world = try makeWorld(width: 4, height: 3)
        let northWest = GridPosition(x: 0, y: 0)
        let northEast = GridPosition(x: 3, y: 0)
        let westOfSecondRow = GridPosition(x: 0, y: 1)
        let southWest = GridPosition(x: 0, y: 2)
        // In row-major storage (3, 0) and (0, 1) are next to each other, and
        // north of row 0 would wrap to the last row.
        try world.buildTrack(at: northEast, connections: allExits)
        try world.buildTrack(at: westOfSecondRow, connections: allExits)
        try world.buildTrack(at: northWest, connections: [.north, .west])
        try world.buildTrack(at: southWest, connections: [.south, .west])

        XCTAssertFalse(world.isConnected(northEast, to: westOfSecondRow))
        XCTAssertFalse(world.isConnected(westOfSecondRow, to: northEast))
        XCTAssertEqual(world.connectedNeighbors(of: northEast), [])
        XCTAssertEqual(world.connectedNeighbors(of: northWest), [])
        XCTAssertEqual(world.connectedNeighbors(of: southWest), [])
        XCTAssertFalse(world.isConnected(northWest, to: GridPosition(x: -1, y: 0)))
        XCTAssertFalse(world.isConnected(northWest, to: GridPosition(x: 0, y: -1)))
        XCTAssertFalse(world.isConnected(northWest, to: southWest))
        XCTAssertFalse(world.isConnected(northEast, to: GridPosition(x: 4, y: 0)))
    }

    func testExtremeCoordinatesAreAnsweredWithoutTrapping() throws {
        var world = try makeWorld(width: 4, height: 4)
        let corner = GridPosition(x: 0, y: 0)
        let farCorner = GridPosition(x: 3, y: 3)
        try world.buildTrack(at: corner, connections: allExits)
        try world.buildTrack(at: farCorner, connections: allExits)
        let coordinates = [Int.min, Int.min + 1, -1, 0, 3, 4, Int.max - 1, Int.max]
        let positions = coordinates.flatMap { x in coordinates.map { y in GridPosition(x: x, y: y) } }

        for position in positions where !world.map.contains(position) {
            XCTAssertEqual(world.connectedNeighbors(of: position), [], "\(position)")
            for other in positions {
                XCTAssertFalse(world.isConnected(position, to: other), "\(position) \(other)")
                XCTAssertFalse(world.isConnected(other, to: position), "\(other) \(position)")
            }
        }
    }

    // MARK: - Construction does not require a link

    func testDanglingTrackIsBuiltAndJoinsOnceAMatchingNeighbourIsBuilt() throws {
        var world = try makeWorld(balance: 1_000)
        try world.buildTrack(at: center, connections: [.east, .west])
        XCTAssertEqual(world.connectedNeighbors(of: center), [])

        // A neighbour that does not face back is also allowed, and changes
        // neither piece.
        try world.buildTrack(at: east, connections: [.north, .south])
        XCTAssertEqual(world.connectedNeighbors(of: center), [])

        try world.buildTrack(at: west, connections: .east)
        XCTAssertEqual(world.connectedNeighbors(of: center), [west])
        XCTAssertTrue(world.isConnected(west, to: center))

        XCTAssertEqual(world.track(at: center)?.connections, [.east, .west])
        XCTAssertEqual(world.track(at: east)?.connections, [.north, .south])
        XCTAssertEqual(world.track(at: west)?.connections, .east)
        XCTAssertEqual(world.economy.balance, 700)
    }

    // MARK: - Piece shapes

    func testEachTrackTileIsOneNodeJoiningAllItsExits() throws {
        let shapes: [(connections: TrackConnections, joined: [GridPosition])] = [
            ([.north, .south], [north, south]),
            ([.east, .west], [east, west]),
            ([.north, .east], [north, east]),
            ([.south, .west], [south, west]),
            ([.east, .south, .west], [east, south, west]),
            ([.north, .east, .west], [north, east, west]),
            (allExits, [north, east, south, west]),
        ]
        for (connections, joined) in shapes {
            var world = try makeWorld()
            try buildMatchingNeighbors(in: &world)
            try world.buildTrack(at: center, connections: connections)

            XCTAssertEqual(world.connectedNeighbors(of: center), joined, "\(connections)")
            for neighbor in [north, east, south, west] {
                let isJoined = joined.contains(neighbor)
                XCTAssertEqual(world.isConnected(neighbor, to: center), isJoined, "\(connections) \(neighbor)")
                XCTAssertEqual(world.connectedNeighbors(of: neighbor), isJoined ? [center] : [], "\(connections) \(neighbor)")
            }
        }
    }

    func testNeighboursAreListedNorthEastSouthWestWhateverTheBuildOrder() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: allExits)

        try world.buildTrack(at: west, connections: .east)
        XCTAssertEqual(world.connectedNeighbors(of: center), [west])
        try world.buildTrack(at: south, connections: .north)
        XCTAssertEqual(world.connectedNeighbors(of: center), [south, west])
        try world.buildTrack(at: east, connections: .west)
        XCTAssertEqual(world.connectedNeighbors(of: center), [east, south, west])
        try world.buildTrack(at: north, connections: .south)
        XCTAssertEqual(world.connectedNeighbors(of: center), [north, east, south, west])
    }

    // MARK: - Every pair of adjacent tiles

    private enum TileContent: CustomStringConvertible {
        case empty
        case station
        case track(TrackConnections)

        /// Empty, station, and every valid track piece.
        static let all: [TileContent] = [.empty, .station] + (1...15).map { .track(TrackConnections(rawValue: $0)) }

        func has(_ exit: TrackConnections) -> Bool {
            if case .track(let connections) = self { return connections.contains(exit) }
            return false
        }

        func build(at position: GridPosition, in world: inout GameWorld) throws {
            switch self {
            case .empty: break
            case .station: try world.buildStation(named: "Stop \(position.x)-\(position.y)", at: position)
            case .track(let connections): try world.buildTrack(at: position, connections: connections)
            }
        }

        var description: String {
            switch self {
            case .empty: "empty"
            case .station: "station"
            case .track(let connections): "track \(connections.rawValue)"
            }
        }
    }

    /// The rule, stated per axis for every combination of contents: a pair is
    /// joined exactly when both are track and each has the exit facing the
    /// other. Every other exit points off the map, which is also allowed.
    func testEveryAdjacentPairFollowsTheLinkRuleSymmetrically() throws {
        let axes: [(width: Int, height: Int, first: GridPosition, second: GridPosition, firstExit: TrackConnections, secondExit: TrackConnections)] = [
            (2, 1, GridPosition(x: 0, y: 0), GridPosition(x: 1, y: 0), .east, .west),
            (1, 2, GridPosition(x: 0, y: 0), GridPosition(x: 0, y: 1), .south, .north),
        ]
        for axis in axes {
            for firstContent in TileContent.all {
                for secondContent in TileContent.all {
                    var world = try makeWorld(width: axis.width, height: axis.height)
                    try firstContent.build(at: axis.first, in: &world)
                    try secondContent.build(at: axis.second, in: &world)
                    let joined = firstContent.has(axis.firstExit) && secondContent.has(axis.secondExit)
                    let label = "\(firstContent) at \(axis.first), \(secondContent) at \(axis.second)"

                    XCTAssertEqual(world.isConnected(axis.first, to: axis.second), joined, label)
                    XCTAssertEqual(world.isConnected(axis.second, to: axis.first), joined, label)
                    XCTAssertEqual(world.connectedNeighbors(of: axis.first), joined ? [axis.second] : [], label)
                    XCTAssertEqual(world.connectedNeighbors(of: axis.second), joined ? [axis.first] : [], label)
                }
            }
        }
    }

    // MARK: - Changes to the map

    func testRemovingTrackDisconnectsAtOnceAndLeavesNeighboursAsBuilt() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: allExits)
        try buildMatchingNeighbors(in: &world)
        let neighborTiles = [north, east, south, west].map { world.map.tile(at: $0) }

        try world.removeTrack(at: center)

        XCTAssertEqual(world.connectedNeighbors(of: center), [])
        for neighbor in [north, east, south, west] {
            XCTAssertFalse(world.isConnected(neighbor, to: center), "\(neighbor)")
            XCTAssertEqual(world.connectedNeighbors(of: neighbor), [], "\(neighbor)")
        }
        // The exits that pointed at the removed piece are now dangling.
        XCTAssertEqual([north, east, south, west].map { world.map.tile(at: $0) }, neighborTiles)
    }

    func testRebuildingJoinsExactlyTheMatchingExits() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: allExits)
        try buildMatchingNeighbors(in: &world)
        try world.removeTrack(at: center)

        try world.buildTrack(at: center, connections: [.north, .south])
        XCTAssertEqual(world.connectedNeighbors(of: center), [north, south])
        XCTAssertFalse(world.isConnected(east, to: center))
        XCTAssertFalse(world.isConnected(west, to: center))

        try world.removeTrack(at: center)
        try world.buildTrack(at: center, connections: allExits)
        XCTAssertEqual(world.connectedNeighbors(of: center), [north, east, south, west])
    }

    func testQueriesDoNotChangeTheWorld() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: allExits)
        try buildMatchingNeighbors(in: &world)
        try world.buildStation(named: "Central", at: GridPosition(x: 7, y: 5))
        let before = world

        for x in -1...20 {
            for y in -1...20 {
                let position = GridPosition(x: x, y: y)
                _ = world.connectedNeighbors(of: position)
                _ = world.isConnected(position, to: center)
                _ = world.isConnected(center, to: position)
            }
        }

        XCTAssertEqual(world, before)
    }

    func testSnapshotsKeepTheConnectivityOfTheirOwnMap() throws {
        var world = try makeWorld()
        try world.buildTrack(at: center, connections: .east)
        try world.buildTrack(at: east, connections: .west)
        let joinedSnapshot = world

        try world.removeTrack(at: east)
        let removedSnapshot = world
        try world.buildTrack(at: east, connections: .west)

        XCTAssertTrue(joinedSnapshot.isConnected(center, to: east))
        XCTAssertEqual(joinedSnapshot.connectedNeighbors(of: center), [east])
        XCTAssertFalse(removedSnapshot.isConnected(center, to: east))
        XCTAssertEqual(removedSnapshot.connectedNeighbors(of: center), [])
        XCTAssertTrue(world.isConnected(center, to: east))
    }

    // MARK: - Largest map

    func testCornersOfTheLargestMap() throws {
        let side = GridMap.maximumSideLength
        let last = side - 1
        var world = try GameWorld(
            width: side,
            height: side,
            economy: GameEconomy(balance: 10_000, costs: testCosts)
        )
        let corners = [
            GridPosition(x: 0, y: 0),
            GridPosition(x: last, y: 0),
            GridPosition(x: 0, y: last),
            GridPosition(x: last, y: last),
        ]
        for corner in corners {
            try world.buildTrack(at: corner, connections: allExits)
        }
        // Every corner's two outward exits point off the map.
        for corner in corners {
            XCTAssertEqual(world.connectedNeighbors(of: corner), [], "\(corner)")
        }
        XCTAssertFalse(world.isConnected(GridPosition(x: last, y: 0), to: GridPosition(x: side, y: 0)))
        XCTAssertFalse(world.isConnected(GridPosition(x: last, y: 0), to: GridPosition(x: 0, y: 1)))
        XCTAssertFalse(world.isConnected(GridPosition(x: 0, y: last), to: GridPosition(x: 0, y: side)))
        XCTAssertFalse(world.isConnected(GridPosition(x: last, y: last), to: GridPosition(x: last, y: side)))

        try world.buildTrack(at: GridPosition(x: last, y: last - 1), connections: .south)
        try world.buildTrack(at: GridPosition(x: last - 1, y: last), connections: .east)
        try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: .west)

        XCTAssertEqual(
            world.connectedNeighbors(of: GridPosition(x: last, y: last)),
            [GridPosition(x: last, y: last - 1), GridPosition(x: last - 1, y: last)]
        )
        XCTAssertEqual(world.connectedNeighbors(of: GridPosition(x: 0, y: 0)), [GridPosition(x: 1, y: 0)])
        XCTAssertEqual(world.connectedNeighbors(of: GridPosition(x: last, y: 0)), [])
    }

    // MARK: - Connection masks

    func testOnlyTheFourDirectionBitsCanBeBuilt() throws {
        let position = GridPosition(x: 2, y: 2)
        for raw in UInt8.min...UInt8.max {
            var world = try makeWorld()
            let before = world
            let isValidPiece = (1...15).contains(raw)

            do throws(GameError) {
                let track = try world.buildTrack(at: position, connections: TrackConnections(rawValue: raw))
                XCTAssertTrue(isValidPiece, "\(raw) was accepted")
                XCTAssertEqual(track.connections.rawValue, raw)
                XCTAssertEqual(world.track(at: position), Track(position: position, connections: TrackConnections(rawValue: raw)))
                XCTAssertEqual(world.map.tile(at: position)?.type, .empty, "the land holds no track")
                XCTAssertEqual(world.economy.balance, 9_900)
            } catch {
                XCTAssertFalse(isValidPiece, "\(raw) was rejected")
                XCTAssertEqual(error, .invalidTrackConnections, "\(raw)")
                XCTAssertEqual(world, before, "\(raw)")
            }
        }
    }

    func testCommandsAndSavesAcceptTheSameConnectionMasks() throws {
        // Stage S3A: a saved map tile may still hold grid track; the world
        // decoder moves it into the railway network.
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try makeWorld(width: 1, height: 1))) as? [String: Any])
        for raw in UInt8.min...UInt8.max {
            var object = empty
            object["map"] = ["width": 1, "height": 1, "tiles": [["track": ["connections": Int(raw)]]]]
            let save = try JSONSerialization.data(withJSONObject: object)
            let decodes = (try? JSONDecoder().decode(GameWorld.self, from: save)) != nil
            var world = try makeWorld(width: 1, height: 1)
            let builds = (try? world.buildTrack(at: GridPosition(x: 0, y: 0), connections: TrackConnections(rawValue: raw))) != nil

            XCTAssertEqual(builds, (1...15).contains(raw), "\(raw)")
            XCTAssertEqual(decodes, builds, "\(raw)")
        }
    }

    func testUnknownBitsStayAPlainOptionSetValue() {
        let connections = TrackConnections(rawValue: 0b1_0001)

        XCTAssertEqual(connections.rawValue, 17)
        XCTAssertTrue(connections.contains(.north))
        XCTAssertEqual(connections.directions, [.north])
        XCTAssertEqual(connections.subtracting(.north).rawValue, 16)
    }

    func testInvalidConnectionsAreRejectedBeforeOtherRulesAndChangeNothing() throws {
        var world = try makeWorld(width: 4, height: 4, balance: 1_100)
        let stationTile = GridPosition(x: 1, y: 1)
        let trackTile = GridPosition(x: 2, y: 2)
        let emptyTile = GridPosition(x: 3, y: 3)
        let outside = GridPosition(x: 9, y: 9)
        let extreme = GridPosition(x: .min, y: .max)
        try world.buildStation(named: "Central", at: stationTile)
        try world.buildTrack(at: trackTile, connections: .north)
        XCTAssertEqual(world.economy.balance, .zero)
        let before = world

        for raw: UInt8 in [0, 16, 0b1_0001, 0xF0, 0xFF] {
            let connections = TrackConnections(rawValue: raw)
            for position in [stationTile, trackTile, emptyTile, outside, extreme] {
                XCTAssertThrowsGameError(
                    try world.buildTrack(at: position, connections: connections),
                    .invalidTrackConnections
                )
            }
        }
        XCTAssertEqual(world, before)

        // With a valid piece, the remaining rules apply in their usual order.
        XCTAssertThrowsGameError(try world.buildTrack(at: outside, connections: .east), .outOfBounds(outside))
        XCTAssertThrowsGameError(try world.buildTrack(at: extreme, connections: .east), .outOfBounds(extreme))
        XCTAssertThrowsGameError(try world.buildTrack(at: stationTile, connections: .east), .tileOccupied(stationTile))
        XCTAssertThrowsGameError(
            try world.buildTrack(at: emptyTile, connections: .east),
            .insufficientFunds(required: 100, available: .zero)
        )
        XCTAssertEqual(world, before)
    }
}
