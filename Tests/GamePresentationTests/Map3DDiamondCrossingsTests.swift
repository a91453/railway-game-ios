import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 888 (GRADE-CROSSING-LOOK): a diamond crossing in the 3D map,
/// laid as the old version's diamond pieces lay it: each rail stops short
/// of the rail it crosses on the diamond's side, eight wing rails beside
/// the rails at the corners, and no mast standing on the other track.
final class Map3DDiamondCrossingsTests: XCTestCase {
    private typealias Builder = Map3DScene.Builder

    /// A north–south line through the middle of a 512 × 256 m world,
    /// crossed at its middle (x 256, y 128 m) by a track drawn from
    /// `from` to `to` (world units) with the network tool (decision 887).
    @MainActor
    private func crossed(from: PlanPoint, to: PlanPoint) throws -> GameWorld {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let north = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 2_048))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 14_336))
        try world.buildTrackEdge(from: north, to: south)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: from, reach: 128)
        session.tapNetwork(at: to, reach: 128)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return session.world
    }

    private func builder(_ world: GameWorld) -> Builder {
        Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
    }

    /// The node in the scene: 256 m east, 128 m south of the origin.
    private let node = Map3DPoint(256, Map3DScene.railLift, 128)

    @MainActor
    func testADiamondIsFoundWithTheAngleItIsLaidAt() throws {
        let square = try crossed(from: PlanPoint(x: 8_192, y: 8_192), to: PlanPoint(x: 24_576, y: 8_192))
        var b = builder(square)
        _ = b.addTrack(square.railwaySnapshot())
        XCTAssertEqual(b.diamonds.count, 1)
        let diamond = try XCTUnwrap(b.diamonds.first)
        XCTAssertEqual(diamond.sine, 1, accuracy: 0.001)
        XCTAssertEqual((diamond.point - node).length, 0, accuracy: 0.01)

        let skew = try crossed(from: PlanPoint(x: 12_288, y: 4_096), to: PlanPoint(x: 20_480, y: 12_288))
        let found = Map3DDiamondCrossings.find(skew.railwaySnapshot()) { b.point($0) + Builder.lifted }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(try XCTUnwrap(found.first).sine, Float(0.5).squareRoot(), accuracy: 0.001, "45°")

        // A plain line has none: two ends at each node.
        var plain = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try plain.buildTrackNode(at: WorldCoordinate(x: 4_096, y: 8_192))
        let c = try plain.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let d = try plain.buildTrackNode(at: WorldCoordinate(x: 28_672, y: 8_192))
        try plain.buildTrackEdge(from: a, to: c)
        try plain.buildTrackEdge(from: c, to: d)
        XCTAssertTrue(Map3DDiamondCrossings.find(plain.railwaySnapshot()) { b.point($0) }.isEmpty)
    }

    /// At 90°, each rail of the four tracks running into the node stops
    /// a flangeway short of the other track's rail, and runs on from that
    /// rail's near face: rails 1.207 m apart at Taiwan's gauge, so 0.4835
    /// to 0.5335 m from the node, at the node's end of the line only.
    @MainActor
    func testEachRailStopsAFlangewayShortOfTheRailItCrosses() throws {
        let world = try crossed(from: PlanPoint(x: 8_192, y: 8_192), to: PlanPoint(x: 24_576, y: 8_192))
        var b = builder(world)
        _ = b.addTrack(world.railwaySnapshot())
        let offset = (b.look.gauge + Builder.railWidth) / 2
        let lines = b.trackLines.map(\.points).filter { line in
            [line[0], line[line.count - 1]].contains { Map3DPoint($0.x - node.x, 0, $0.z - node.z).length < 0.05 }
        }
        XCTAssertEqual(lines.count, 4)
        for line in lines {
            let length = zip(line, line.dropFirst()).reduce(Float(0)) { $0 + Map3DPoint($1.1.x - $1.0.x, 0, $1.1.z - $1.0.z).length }
            let startsAtNode = Map3DPoint(line[0].x - node.x, 0, line[0].z - node.z).length < 0.05
            for side: Float in [-1, 1] {
                let gaps = b.diamondGaps(line, offset: side * offset)
                XCTAssertEqual(gaps.count, 1)
                let gap = try XCTUnwrap(gaps.first)
                let near = startsAtNode ? gap.lowerBound : length - gap.upperBound
                let far = startsAtNode ? gap.upperBound : length - gap.lowerBound
                XCTAssertEqual(near, offset - Builder.railWidth / 2 - Map3DDiamondCrossings.flangeway, accuracy: 0.001)
                XCTAssertEqual(far, offset - Builder.railWidth / 2, accuracy: 0.001)
                let pieces = Map3DDiamondCrossings.cut(line, without: gaps)
                XCTAssertEqual(pieces.count, 2, "the rail inside the diamond, and on from the corner")
            }
        }
        // Away from a diamond, nothing is cut.
        XCTAssertTrue(b.diamondGaps([Map3DPoint(0, 0, 0), Map3DPoint(40, 0, 0)], offset: offset).isEmpty)
    }

    /// Eight wing rails, at any angle: each beside one track's rail on its
    /// gauge side, a rail and a flangeway from it, starting on the other
    /// track's rail and running out of the diamond, longer as the angle
    /// flattens.
    @MainActor
    func testEightWingRailsBesideTheRailsAtTheCorners() throws {
        let gauge: Float = 1.067
        let offset = (gauge + Builder.railWidth) / 2
        for degrees: Float in [90, 67.5, 45, 15] {
            let angle = degrees * .pi / 180
            let diamond = Map3DDiamondCrossing(point: Map3DPoint(0, 0, 0), world: WorldCoordinate(x: 0, y: 0), first: Map3DPoint(1, 0, 0),
                                               second: Map3DPoint(cos(angle), 0, sin(angle)))
            let wings = Map3DDiamondCrossings.wings(of: diamond, gauge: gauge)
            XCTAssertEqual(wings.count, 8)
            for wing in wings {
                let way = try XCTUnwrap((wing[1] - wing[0]).normalized)
                XCTAssertEqual((wing[1] - wing[0]).length, Map3DDiamondCrossings.wingLength / sin(angle), accuracy: 0.001)
                // Along one of the tracks, and out of the diamond.
                let track = abs(way.dot(diamond.first)) > 0.999 ? diamond.first : diamond.second
                XCTAssertEqual(abs(way.dot(track)), 1, accuracy: 0.001, "\(degrees)°")
                let other = track == diamond.first ? diamond.second : diamond.first
                let normal = Map3DPoint(-track.z, 0, track.x), otherNormal = Map3DPoint(-other.z, 0, other.x)
                // Inside the gauge, a rail and a flangeway from its rail.
                XCTAssertEqual(abs(wing[0].dot(normal)), offset - Builder.railWidth - Map3DDiamondCrossings.flangeway, accuracy: 0.001)
                // From the other track's rail line, outwards.
                XCTAssertEqual(abs(wing[0].dot(otherNormal)), offset, accuracy: 0.001)
                XCTAssertGreaterThan(abs(wing[1].dot(otherNormal)), offset)
            }
        }
    }

    /// No mast of the overhead line stands on the other track at a
    /// diamond, square or as flat as 1 in 4: each is 2 m or more from both
    /// tracks' middles.
    @MainActor
    func testNoMastStandsOnTheOtherTrack() throws {
        let draws = [(PlanPoint(x: 8_192, y: 8_192), PlanPoint(x: 24_576, y: 8_192)),
                     (PlanPoint(x: 16_384 - 1_600, y: 2_048), PlanPoint(x: 16_384 + 1_600, y: 14_336))]
        for (from, to) in draws {
            let world = try crossed(from: from, to: to)
            var b = builder(world)
            _ = b.addTrack(world.railwaySnapshot())
            b.addOverheadLine()
            let diamond = try XCTUnwrap(b.diamonds.first)
            let tops = b.closeMeshes.values.flatMap(\.vertices)
                .filter { $0.color == Map3DPalette.mastSteel && abs($0.y - (Map3DScene.railLift + Builder.mastTop)) < 0.01 }
                .map { Map3DPoint($0.x - node.x, 0, $0.z - node.z) }
            XCTAssertFalse(tops.isEmpty)
            for top in tops {
                for way in [diamond.first, diamond.second] {
                    let across = abs(top.x * way.z - top.z * way.x)
                    XCTAssertGreaterThanOrEqual(across, Builder.mastClearOfTrack - 0.3, "\(top) on the track along \(way)")
                }
            }
        }
    }

    /// The preview's meshes (`tools/diamond-crossing/preview.py`): the
    /// scene round the node of a crossing at 90°, at 45° and at 1 in 4
    /// (about 14.5°, the flattest decision 887 lays), its base and close
    /// detail (the overhead line) within 30 m of the node.
    @MainActor
    func testWriteThePreviewsMeshes() throws {
        guard let out = ProcessInfo.processInfo.environment["DIAMOND_PREVIEW"] else {
            throw XCTSkip("DIAMOND_PREVIEW=<file.json> writes the preview's meshes")
        }
        var scenes: [[String: Any]] = []
        let draws: [(String, PlanPoint, PlanPoint)] = [
            ("90", PlanPoint(x: 8_192, y: 8_192), PlanPoint(x: 24_576, y: 8_192)),
            ("45", PlanPoint(x: 12_288, y: 4_096), PlanPoint(x: 20_480, y: 12_288)),
            ("15", PlanPoint(x: 16_384 - 1_600, y: 2_048), PlanPoint(x: 16_384 + 1_600, y: 14_336)),
        ]
        for (name, from, to) in draws {
            let world = try crossed(from: from, to: to)
            let scene = Map3DScene(world: world)
            let centre = scene.point(WorldCoordinate(x: 16_384, y: 8_192, z: 0))
            var positions: [Float] = [], colours: [Int] = [], lit: [Bool] = [], indices: [Int] = []
            for chunk in scene.chunks {
                for (mesh, count) in [(chunk.mesh, chunk.baseIndexCount), (chunk.close, chunk.close.indices.count)] {
                    var kept: [Int: Int] = [:]
                    for triangle in stride(from: 0, to: count, by: 3) {
                        let corners = (0..<3).map { Int(mesh.indices[triangle + $0]) }
                        guard corners.allSatisfy({ abs(mesh.vertices[$0].x - centre.x) < 30 && abs(mesh.vertices[$0].z - centre.z) < 30 })
                        else { continue }
                        for corner in corners {
                            if kept[corner] == nil {
                                let vertex = mesh.vertices[corner]
                                kept[corner] = lit.count
                                positions += [vertex.x - centre.x, vertex.y, vertex.z - centre.z]
                                colours.append(Int(vertex.color & 0xFF_FFFF))
                                lit.append(vertex.glows)
                            }
                            indices.append(kept[corner]!)
                        }
                    }
                }
            }
            var rails: Float = 0
            for vertex in scene.chunks.flatMap(\.mesh.vertices) where vertex.color == Map3DPalette.railTop {
                if abs(vertex.x - centre.x) < 3, abs(vertex.z - centre.z) < 3 { rails = max(rails, vertex.y) }
            }
            scenes.append(["name": name, "rails": rails, "positions": positions, "colours": colours, "lit": lit, "indices": indices])
        }
        try JSONSerialization.data(withJSONObject: scenes).write(to: URL(fileURLWithPath: out))
    }
}
