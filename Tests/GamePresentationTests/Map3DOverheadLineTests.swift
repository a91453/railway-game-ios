import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 326: the overhead line over the track.
final class Map3DOverheadLineTests: XCTestCase {
    private typealias Builder = Map3DScene.Builder

    /// A builder with `tracks` (their z) straight along x from −200 to
    /// 200 m, and `platforms` (their offset to the right, +z, of the
    /// track at z 0, 3.2 m wide).
    private func builder(tracks: [Float] = [0], kind: TrackSectionKind = .surface, platforms: [Float] = []) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: GameWorld.newGame())
        builder.trackLines = tracks.map { (line($0), kind) }
        builder.laidPlatforms = platforms.map {
            Builder.LaidPlatform(station: StationID(rawValue: 1), line: line(0), offset: $0, width: 3.2, structure: .surface)
        }
        return builder
    }

    private func line(_ z: Float) -> [Map3DPoint] {
        stride(from: Float(-200), through: 200, by: 16).map { Map3DPoint($0, Map3DScene.railLift, z) }
    }

    /// Where each mast stands: the middle of its top, ``Builder/mastTop``
    /// above the rails.
    private func mastTops(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DPoint] {
        let tops = meshes.values.flatMap(\.vertices)
            .filter { $0.color == Map3DPalette.mastSteel && abs($0.y - (Map3DScene.railLift + Builder.mastTop)) < 0.01 }
        var groups: [[Map3DPoint]] = []
        for top in tops.map({ Map3DPoint($0.x, $0.y, $0.z) }) {
            if let index = groups.firstIndex(where: { ($0[0] - top).length < 0.5 }) { groups[index].append(top) } else { groups.append([top]) }
        }
        return groups.map { group in group.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(group.count)) }.sorted { $0.x < $1.x }
    }

    private func wires(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        meshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.overheadWire }
    }

    func testMastsStandBesideOneTrackAtMostFortyMetresApartCloseUpOnly() {
        var b = builder()
        b.addOverheadLine()
        let masts = mastTops(b.closeMeshes)
        XCTAssertEqual(masts.count, 11, "400 m: a mast every 40 m, one at each end")
        for (a, c) in zip(masts, masts.dropFirst()) { XCTAssertLessThanOrEqual(c.x - a.x, 40.01) }
        XCTAssertTrue(masts.allSatisfy { abs(abs($0.z) - Builder.mastOffset) < 0.01 }, "beside the track, all on one side")
        XCTAssertEqual(Set(masts.map { $0.z > 0 }).count, 1)
        // The wires over the track: the contact wire zigzagging, the
        // messenger above it.
        let wire = wires(b.closeMeshes)
        XCTAssertFalse(wire.isEmpty)
        XCTAssertTrue(wire.allSatisfy { abs($0.z) < Builder.wireStagger + 0.1 })
        XCTAssertEqual(wire.map(\.y).max() ?? 0, Map3DScene.railLift + Builder.messengerHeight + Builder.wireThickness / 2, accuracy: 0.05)
        // Close up only: nothing in the full or the simplified city.
        for meshes in [b.meshes, b.nearMeshes, b.farMeshes] { XCTAssertTrue(mastTops(meshes).isEmpty && wires(meshes).isEmpty) }
    }

    /// No mast in the street at a level crossing: the 40 m spacing put
    /// one at x 0, where a street crosses the track, and its traffic drove
    /// through it. The wire spans over the street to the masts either side.
    func testNoMastStandsInTheStreetAtALevelCrossing() {
        var b = builder()
        let crossing = Map3DLevelCrossing(point: Map3DPoint(0, Map3DScene.railLift, 0), along: Map3DPoint(0, 0, 1), kind: .secondary)
        b.crossings = [crossing]
        b.addOverheadLine()
        let masts = mastTops(b.closeMeshes)
        XCTAssertFalse(masts.isEmpty)
        XCTAssertTrue(masts.allSatisfy { abs($0.x) > crossing.halfWidth + 0.5 }, "\(masts.map(\.x))")
        XCTAssertTrue(wires(b.closeMeshes).contains { abs($0.x) < 1 }, "the wire still hangs over the street")
    }

    func testALongLinesWiresStayInTheChunksTheyHangOver() {
        // 3 km of track: each chunk holds only the spans over it, so its
        // box is not seen, nor drawn close up, from all along the line.
        var b = builder()
        b.trackLines = [(stride(from: Float(-1_500), through: 1_500, by: 16).map { Map3DPoint($0, Map3DScene.railLift, 0) }, .surface)]
        b.addOverheadLine()
        XCTAssertGreaterThan(b.closeMeshes.count, 4)
        for mesh in b.closeMeshes.values {
            let xs = mesh.vertices.map(\.x)
            XCTAssertLessThanOrEqual((xs.max() ?? 0) - (xs.min() ?? 0), Map3DScene.chunkSize + Builder.mastSpacing)
        }
    }

    func testOnACurveTheMastsStandCloserSoTheWireStaysOverTheTrack() throws {
        // A curve of 300 m radius, a quarter of a circle.
        let arc = stride(from: Float(0), through: .pi / 2, by: 0.02).map { Map3DPoint(300 * cosf($0), 0, 300 * sinf($0)) }
        let path = try XCTUnwrap(Map3DStreetLife.Path(arc))
        let supports = Builder.wireSupports(path)
        for (a, c) in zip(supports, supports.dropFirst()) {
            XCTAssertLessThan(c - a, 34, "closer than on the straight")
            let from = path.at(a).point, to = path.at(c).point
            let across = try XCTUnwrap((to - from).normalized).cross(.up)
            for distance in stride(from: a, through: c, by: 1) {
                XCTAssertLessThanOrEqual(abs((path.at(distance).point - from).dot(across)), Builder.wireStray + 0.05)
            }
        }
        let straight = try XCTUnwrap(Map3DStreetLife.Path(line(0)))
        XCTAssertEqual(Builder.wireSupports(straight), stride(from: Float(0), through: 400, by: 40).map { $0 })
    }

    func testBesideOtherTrackTheMastsStandOutsideAndBetweenTwoNone() {
        var two = builder(tracks: [0, 4.5])
        two.addOverheadLine()
        let pairs = mastTops(two.closeMeshes)
        XCTAssertEqual(Set(pairs.map { ($0.z * 100).rounded() / 100 }), [-Builder.mastOffset, 4.5 + Builder.mastOffset])
        var three = builder(tracks: [-4.5, 0, 4.5])
        three.addOverheadLine()
        let outside = mastTops(three.closeMeshes)
        XCTAssertFalse(outside.isEmpty)
        XCTAssertTrue(outside.allSatisfy { abs($0.z) > 6 }, "the middle track hangs its wires from its neighbours'")
        XCTAssertTrue(wires(three.closeMeshes).contains { abs($0.z) < 0.5 }, "it still has its wires")
    }

    func testAMastStandsClearOfAPlatformOrOnItsMiddleWhenItMust() {
        var clear = builder(platforms: [3.2])
        clear.addOverheadLine()
        XCTAssertTrue(mastTops(clear.closeMeshes).allSatisfy { $0.z < 0 }, "on the side with no platform")
        // Another track on that side: on the platform's middle, standing
        // on it.
        var boxed = builder(tracks: [0, -4.5], platforms: [3.2])
        boxed.addOverheadLine()
        let onPlatform = mastTops(boxed.closeMeshes).filter { $0.z > 0 }
        XCTAssertFalse(onPlatform.isEmpty)
        XCTAssertTrue(onPlatform.allSatisfy { abs($0.z - 3.2) < 0.01 })
        // The footings' tops (their sides are shaded), a quarter of a metre
        // above the platform.
        let footings = boxed.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.concrete && $0.z > 2 }
        XCTAssertFalse(footings.isEmpty)
        XCTAssertTrue(footings.allSatisfy { abs($0.y - (Map3DScene.railLift + Builder.platformHeight + 0.25)) < 0.01 })
    }

    func testNoOverheadLineInATunnelNorWhereTheGroundCoversTheTrack() {
        var b = builder(kind: .tunnel)
        b.addOverheadLine()
        XCTAssertTrue(mastTops(b.closeMeshes).isEmpty && wires(b.closeMeshes).isEmpty)
        var buried = builder()
        buried.trackLines = [(line(0).map { $0 - Map3DPoint(0, 6, 0) }, .surface)]
        buried.addOverheadLine()
        XCTAssertTrue(wires(buried.closeMeshes).isEmpty)
        XCTAssertFalse(buried.closeMeshes.values.contains { $0.vertices.contains { $0.color == Map3DPalette.mastSteel } })
    }

    func testNoOverheadLineAlongARealLineRunWithoutOne() {
        var diesel = builder()
        diesel.realLines = [(line(1), false)]
        diesel.addOverheadLine()
        XCTAssertTrue(mastTops(diesel.closeMeshes).isEmpty && wires(diesel.closeMeshes).isEmpty)
        // A wired line nearer than the diesel one wins; a real line 100 m
        // off says nothing of this track.
        var wired = builder()
        wired.realLines = [(line(1), true), (line(8), false)]
        wired.addOverheadLine()
        XCTAssertEqual(mastTops(wired.closeMeshes).count, 11)
        var away = builder()
        away.realLines = [(line(100), false)]
        away.addOverheadLine()
        XCTAssertEqual(mastTops(away.closeMeshes).count, 11)
    }

    func testTheRealLinesWithoutAnOverheadLine() throws {
        func file(_ name: String) throws -> Data {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        let railways = try RealRailways(lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"))
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        let everywhere = 1e13
        var b = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -everywhere, minY: -everywhere, maxX: everywhere, maxY: everywhere),
                        world: GameWorld.newGame())
        b.addRealLines(railways, frame: frame)
        /// Whether the real line nearest `name`'s station runs under wires.
        func wired(_ name: String, _ system: String = "tra_sched") throws -> Bool {
            let station = try XCTUnwrap(railways.stations(named: name, near: nil).first { $0.system.id == system }, name)
            let at = frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)
            let p = b.point(x: at.x, y: at.y, height: 0)
            var nearest: (distance: Float, wired: Bool) = (.infinity, true)
            for line in b.realLines {
                for point in line.points where (point - p).length < nearest.distance { nearest = ((point - p).length, line.wired) }
            }
            return nearest.wired
        }
        for name in ["瑞芳", "猴硐", "豐原", "苗栗", "六家", "北新竹"] { XCTAssertTrue(try wired(name), name) }
        // The diesel branches (the Neiwan Line past Zhuzhong), the forest
        // railway, a metro.
        for name in ["十分", "菁桐", "海科館", "集集", "車埕", "竹東", "內灣"] { XCTAssertFalse(try wired(name), name) }
        XCTAssertFalse(try wired("奮起湖", "afr_sched"))
        XCTAssertFalse(try wired("市政府", "mrt"))
    }
}
