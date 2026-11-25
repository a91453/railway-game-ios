import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 984: the 3D map lays each edge's rails at the edge's own gauge
/// (decision 970), a real line's at the real line's, and only track of
/// the gauge nothing sets at the map's (decision 799).
final class Map3DTrackGaugeDrawnTests: XCTestCase {
    private typealias Builder = Map3DScene.Builder

    private func builder(_ world: GameWorld) -> Builder {
        Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
    }

    /// The distances from the centre line `z` (scene metres) to the inner
    /// faces of the rails drawn within 2 m of it, nearest first, one side.
    private func innerFaces(of builder: inout Builder, along z: Float) -> [Float] {
        let mesh = builder.chunks().reduce(into: Map3DMesh()) { $0.append($1.mesh) }
        let tops = mesh.vertices.filter { $0.color == Map3DPalette.railTop }.map { $0.z - z }.filter { $0 > 0 && $0 < 2 }
        // Each rail's top has an inner and an outer edge; the inner ones.
        let edges = Set(tops.map { ($0 * 1_000).rounded() / 1_000 }).sorted()
        return stride(from: 0, to: edges.count, by: 2).map { edges[$0] }
    }

    func testWhatEachGaugeIsDrawnAt() {
        let taiwan = Map3DTrackGauge.cape, finland = Map3DTrackGauge.finnish
        XCTAssertEqual(Map3DTrackGauge.drawn(.cape, map: taiwan), [1.067])
        XCTAssertEqual(Map3DTrackGauge.drawn(.standard, map: taiwan), [1.435])
        XCTAssertEqual(Map3DTrackGauge.drawn(.shinkansen, map: taiwan), [1.435])
        XCTAssertEqual(Map3DTrackGauge.drawn(.forest, map: taiwan), [0.762])
        XCTAssertEqual(Map3DTrackGauge.drawn(.broad, map: taiwan), [1.524])
        // Decision 799: track of no gauge of its own at the map's.
        XCTAssertEqual(Map3DTrackGauge.drawn(.default, map: finland), [1.524])
        XCTAssertEqual(Map3DTrackGauge.drawn(.standard, map: finland), [1.435])
        // An old save's three-rail track: both, widest first.
        XCTAssertEqual(Map3DTrackGauge.drawn(TrackGauge(rails: [.cape, .standard], loading: .shinkansen), map: taiwan), [1.435, 1.067])
    }

    /// The systems the real lines' tracks are laid by
    /// (``RealRailwayOperations/siteSystems``), each at its real gauge.
    func testARealLinesTrackIsAtItsRealGauge() {
        let map = Map3DTrackGauge.cape
        for system in ["tra_sched", "tra"] { XCTAssertEqual(Map3DTrackGauge.drawn(realLine: system, map: map), [1.067], system) }
        for system in ["thsr_sched", "mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt", "hkmtr"] {
            XCTAssertEqual(Map3DTrackGauge.drawn(realLine: system, map: map), [1.435], system)
        }
        XCTAssertEqual(Map3DTrackGauge.drawn(realLine: "afr_sched", map: map), [0.762])
        XCTAssertEqual(Map3DTrackGauge.drawn(realLine: "vr", map: Map3DTrackGauge.finnish), [1.524])
        XCTAssertEqual(Map3DTrackGauge.drawn(realLine: "fksubway:N", map: map), [1.435])
        // Every system that runs real trains is known.
        for system in RealRailwayOperations.siteSystems.values { XCTAssertNotNil(TrackGauge.ofRealLine(system), system) }
        // One the game does not know: the map's, as before.
        XCTAssertEqual(Map3DTrackGauge.drawn(realLine: "elsewhere", map: Map3DTrackGauge.finnish), [1.524])
    }

    /// Five parallel edges, one of each gauge the track tool offers, each
    /// with its two rails its own gauge apart.
    func testEachEdgesRailsAreItsOwnGaugeApart() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 100_000_000, speed: .paused)
        let gauges: [(TrackGauge, Float)] = [(.cape, 1.067), (.standard, 1.435), (.shinkansen, 1.435), (.forest, 0.762), (.broad, 1.524)]
        for (row, gauge) in gauges.enumerated() {
            let y = Int64(2_048 + row * 2_560)
            let west = try world.buildTrackNode(at: WorldCoordinate(x: 4_096, y: y))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: 28_672, y: y))
            let edge = try world.buildTrackEdge(from: west, to: east, gauge: gauge.0)
            XCTAssertEqual(world.network.edge(edge)?.gauge, gauge.0)
        }
        var b = builder(world)
        _ = b.addTrack(world.railwaySnapshot())
        for (row, gauge) in gauges.enumerated() {
            let z = Float(2_048 + row * 2_560) / Float(WorldCoordinate.unitsPerMetre)
            let faces = innerFaces(of: &b, along: z)
            XCTAssertEqual(faces.count, 1, "\(gauge.0.code)")
            XCTAssertEqual(try XCTUnwrap(faces.first) * 2, gauge.1, accuracy: 0.002, "\(gauge.0.code)")
        }
    }

    /// Track of no gauge of its own on Finland's map is still laid at
    /// Finland's (decision 799), and standard-gauge track there at its own.
    func testFinlandsMapKeepsItsGaugeForTrackOfNone() throws {
        let rovaniemi = GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground())
        XCTAssertEqual(Map3DTrackGauge.drawn(.default, map: Map3DTrackGauge.metres(world: rovaniemi)), [1.524])
        var b = builder(rovaniemi)
        b.addTrackPiece([Map3DPoint(0, 0, 50), Map3DPoint(100, 0, 50)], kind: .surface,
                        gauges: Map3DTrackGauge.drawn(.standard, map: b.look.gauge))
        XCTAssertEqual(try XCTUnwrap(innerFaces(of: &b, along: 50).first) * 2, 1.435, accuracy: 0.002)
    }

    /// Three-rail track: each gauge's two rails about the one centre
    /// line, so a train of either stands on its own.
    func testThreeRailTrackHasEachGaugesRails() throws {
        let world = try makeWorld(width: 32_768, height: 16_384, balance: 1_000_000, speed: .paused)
        var b = builder(world)
        b.addTrackPiece([Map3DPoint(0, 0, 50), Map3DPoint(100, 0, 50)], kind: .surface, gauges: [1.435, 1.067])
        let faces = innerFaces(of: &b, along: 50)
        XCTAssertEqual(faces.count, 2)
        XCTAssertEqual(faces[0] * 2, 1.067, accuracy: 0.002)
        XCTAssertEqual(faces[1] * 2, 1.435, accuracy: 0.002)
    }

    /// A standard-gauge track laid across a 1,067 mm one: each track's
    /// rails stop a flangeway short of the other's rails where the other's
    /// gauge puts them, and the wing rails stand by each track's own.
    @MainActor
    func testADiamondOfTwoGaugesKeepsEachTracksOwn() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let north = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 2_048))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 14_336))
        try world.buildTrackEdge(from: north, to: south)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.chooseNetworkGauge(.standard)
        session.tapNetwork(at: PlanPoint(x: 8_192, y: 8_192), reach: 128)
        session.tapNetwork(at: PlanPoint(x: 24_576, y: 8_192), reach: 128)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        world = session.world

        var b = builder(world)
        _ = b.addTrack(world.railwaySnapshot())
        let diamond = try XCTUnwrap(b.state.track.diamonds.first)
        XCTAssertEqual(b.state.track.diamonds.count, 1)
        // The first track is the one whose edge the node's ends list first;
        // either way one is each gauge.
        XCTAssertEqual([diamond.firstGauge, diamond.secondGauge].sorted(), [1.067, 1.435])

        let node = Map3DPoint(256, Map3DScene.railLift, 128)
        let lines = b.state.track.trackLines.map(\.points).filter { line in
            [line[0], line[line.count - 1]].contains { Map3DPoint($0.x - node.x, 0, $0.z - node.z).length < 0.05 }
        }
        XCTAssertEqual(lines.count, 4)
        for line in lines {
            let startsAtNode = Map3DPoint(line[0].x - node.x, 0, line[0].z - node.z).length < 0.05
            let length = zip(line, line.dropFirst()).reduce(Float(0)) { $0 + Map3DPoint($1.1.x - $1.0.x, 0, $1.1.z - $1.0.z).length }
            // East–west lines are the standard-gauge track's.
            let eastWest = abs(line[line.count - 1].x - line[0].x) > abs(line[line.count - 1].z - line[0].z)
            let own: Float = eastWest ? 1.435 : 1.067, other: Float = eastWest ? 1.067 : 1.435
            let offset = (own + Builder.railWidth) / 2
            for side: Float in [-1, 1] {
                let gap = try XCTUnwrap(b.diamondGaps(line, offset: side * offset).first)
                let far = startsAtNode ? gap.upperBound : length - gap.lowerBound
                // Up to the near face of the other track's rail.
                XCTAssertEqual(far, other / 2, accuracy: 0.001)
                XCTAssertEqual(gap.upperBound - gap.lowerBound, Map3DDiamondCrossings.flangeway, accuracy: 0.001)
            }
        }
        for wing in Map3DDiamondCrossings.wings(of: diamond) {
            let way = try XCTUnwrap((wing[1] - wing[0]).normalized)
            let alongFirst = abs(way.dot(diamond.first)) > 0.999
            let track = alongFirst ? diamond.first : diamond.second, other = alongFirst ? diamond.second : diamond.first
            let own = alongFirst ? diamond.firstGauge : diamond.secondGauge, others = alongFirst ? diamond.secondGauge : diamond.firstGauge
            let normal = Map3DPoint(-track.z, 0, track.x), otherNormal = Map3DPoint(-other.z, 0, other.x)
            let start = wing[0] - diamond.point
            // Inside its own track's gauge, a flangeway from its rail.
            XCTAssertEqual(abs(start.dot(normal)), own / 2 - Builder.railWidth / 2 - Map3DDiamondCrossings.flangeway, accuracy: 0.001)
            // From the other track's rail line, outwards.
            XCTAssertEqual(abs(start.dot(otherNormal)), (others + Builder.railWidth) / 2, accuracy: 0.001)
        }
    }
}
