import Foundation
import GameCore
import XCTest

/// Stage J on generated networks: every position on the track can be placed,
/// everything else is refused without changing the world, reversing is an
/// exact involution, positions survive saving, and supporting track is
/// protected.
final class TrainPositionPropertyTests: XCTestCase {
    private let id = TrainID(rawValue: 1)

    private func makeWorld(_ c: inout PropertyCase) throws -> GameWorld {
        let shape = c.random.element(of: NetworkShape.allCases)
        let (specs, width, height) = NetworkGenerator.specs(shape, using: &c.random)
        c.note("\(shape) \(width)x\(height), \(specs.count) tiles")
        var world = try NetworkGenerator.build(specs, width: width, height: height)
        try world.purchaseTrain(named: "Probe")
        return world
    }

    /// Every valid position of the world: each track tile facing each way,
    /// and each joined link, both ways, at the boundary offsets.
    private func validPositions(in world: GameWorld) -> [TrainPosition] {
        var positions: [TrainPosition] = []
        for track in world.tracks {
            for heading in TrackDirection.allCases {
                positions.append(.atNode(track.position, heading: heading))
            }
            for neighbor in world.connectedNeighbors(of: track.position) {
                for offset in PositionGenerator.edgeOffsets {
                    positions.append(.onLink(from: track.position, to: neighbor, offset: offset))
                }
            }
        }
        return positions
    }

    func testEveryPositionOnTheTrackCanBePlacedAndReadBack() throws {
        var placed = 0
        try runCampaign("position.valid", cases: 30) { c in
            let world = try makeWorld(&c)
            for position in validPositions(in: world) {
                var copy = world
                do throws(GameError) {
                    try copy.placeTrain(id, at: position)
                } catch {
                    c.fail("\(position) refused: \(error)")
                    continue
                }
                placed += 1
                c.expect(copy.train(id: id)?.position == position, "\(position) read back as \(String(describing: copy.train(id: id)?.position))")
                c.expect(copy.train(id: id)?.movement == .idle, "a placed train is not idle")
                c.expect(copy.map == world.map && copy.economy == world.economy && copy.clock == world.clock, "placing changed more than the train")
            }
        }
        assertVolume(placed > 10_000, "too few positions were placed")
    }

    func testPositionsOffTheTrackAreRefusedWithoutChangingTheWorld() throws {
        try runCampaign("position.invalid", cases: 60) { c in
            let world = try makeWorld(&c)
            var invalid: [TrainPosition] = []
            let tracks = world.tracks.map(\.position)
            // Links at or past their ends, or with an offset far out.
            for tile in tracks {
                for neighbor in world.connectedNeighbors(of: tile) {
                    for offset: Int64 in [0, 1024, -1, 1025, 2048, .min, .max] {
                        invalid.append(.onLink(from: tile, to: neighbor, offset: offset))
                    }
                }
            }
            // Pairs that are not a joined link: one-sided, empty, station,
            // off the map, diagonal, two apart, the same tile.
            for tile in tracks {
                for way in TrackDirection.allCases where !world.isConnected(tile, to: step(tile, way)) {
                    invalid.append(.onLink(from: tile, to: step(tile, way), offset: 512))
                    invalid.append(.onLink(from: step(tile, way), to: tile, offset: 512))
                }
                invalid.append(.onLink(from: tile, to: GridPosition(x: tile.x + 1, y: tile.y + 1), offset: 512))
                invalid.append(.onLink(from: tile, to: GridPosition(x: tile.x + 2, y: tile.y), offset: 512))
                invalid.append(.onLink(from: tile, to: tile, offset: 512))
            }
            // Nodes that are not track tiles.
            for y in -1...world.map.height {
                for x in -1...world.map.width where world.track(at: GridPosition(x: x, y: y)) == nil {
                    invalid.append(.atNode(GridPosition(x: x, y: y), heading: c.random.element(of: TrackDirection.allCases)))
                }
            }
            invalid.append(.atNode(GridPosition(x: .min, y: .max), heading: .north))
            invalid.append(.onLink(from: GridPosition(x: .max, y: 0), to: GridPosition(x: .min, y: 0), offset: 1))
            for position in invalid {
                var copy = world
                do throws(GameError) {
                    try copy.placeTrain(id, at: position)
                    c.fail("\(position) was placed")
                } catch {
                    c.expect(error == .invalidTrainPosition, "\(position) gave \(error)")
                }
                c.expect(copy == world, "refusing \(position) changed the world")
            }
        }
    }

    func testReversingIsAnExactInvolutionAtTheSamePoint() throws {
        try runCampaign("position.reverse", cases: 40) { c in
            let world = try makeWorld(&c)
            for position in validPositions(in: world) where c.random.chance(1, in: 3) {
                var copy = world
                try copy.placeTrain(id, at: position)
                try copy.reverseTrain(id)
                guard let reversed = copy.train(id: id)?.position else { return c.fail("reversing unplaced \(position)") }
                switch (position, reversed) {
                case (.atNode(let tile, let heading), .atNode(let tile2, let heading2)):
                    c.expect(tile == tile2 && heading2 == heading.opposite, "\(position) reversed to \(reversed)")
                case (.onLink(let from, let to, let offset), .onLink(let from2, let to2, let offset2)):
                    // The same point, measured from the other end.
                    c.expect(from2 == to && to2 == from && offset2 == TrainPosition.linkLength - offset, "\(position) reversed to \(reversed)")
                default:
                    c.fail("\(position) reversed to \(reversed)")
                }
                // The reversed position is itself a valid placement.
                var fresh = world
                c.expect((try? fresh.placeTrain(id, at: reversed)) != nil, "reversed \(reversed) cannot be placed")
                try copy.reverseTrain(id)
                c.expect(copy.train(id: id)?.position == position, "reversing twice did not restore \(position)")
            }
        }
    }

    func testPositionsSurviveSavingAndMalformedOffsetsAreRefused() throws {
        try runCampaign("position.codable", cases: 30) { c in
            let world = try makeWorld(&c)
            let encoder = JSONEncoder()
            var worldsSaved = 0
            for position in validPositions(in: world) where c.random.chance(1, in: 4) {
                let data = try encoder.encode(position)
                c.expect((try? JSONDecoder().decode(TrainPosition.self, from: data)) == position, "\(position) did not round-trip")
                // Whole worlds are slower to save: a few per case.
                guard worldsSaved < 3 else { continue }
                worldsSaved += 1
                var placed = world
                try placed.placeTrain(id, at: position)
                c.expect(WorldInvariants.roundTripProblem(of: placed) == nil, "a world with \(position) did not round-trip")
            }
            // The two ends of a link are never a link position.
            if let tile = world.tracks.first?.position, let neighbor = world.connectedNeighbors(of: tile).first {
                for offset in [0, 1024, -5, 5000] {
                    let json = #"{"onLink": {"from": {"x": \#(tile.x), "y": \#(tile.y)}, "to": {"x": \#(neighbor.x), "y": \#(neighbor.y)}, "offset": \#(offset)}}"#
                    c.expect((try? JSONDecoder().decode(TrainPosition.self, from: Data(json.utf8))) == nil, "offset \(offset) decoded")
                }
            }
        }
    }

    func testTrackUnderATrainCannotBeRemovedAndOtherTrackCan() throws {
        try runCampaign("position.trackInUse", cases: 40) { c in
            let world = try makeWorld(&c)
            guard let position = PositionGenerator.validPosition(in: world, using: &c.random) else { return }
            c.note("train at \(position)")
            var placed = world
            try placed.placeTrain(id, at: position)
            let supporting: Set<GridPosition> = {
                switch position {
                case .atNode(let tile, _): [tile]
                case .onLink(let from, let to, _): [from, to]
                }
            }()
            for track in placed.tracks {
                var copy = placed
                do throws(GameError) {
                    try copy.removeTrack(at: track.position)
                    c.expect(!supporting.contains(track.position), "removed \(track.position) under the train")
                    c.expect(WorldInvariants.violations(in: copy).isEmpty, "removing \(track.position) broke \(WorldInvariants.violations(in: copy))")
                } catch {
                    c.expect(supporting.contains(track.position) && error == .trackInUse(track.position), "removing \(track.position) gave \(error)")
                    c.expect(copy == placed, "a refused removal changed the world")
                }
            }
        }
    }
}
