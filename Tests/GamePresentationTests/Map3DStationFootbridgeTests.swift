@testable import GamePresentation
import GameCore
import XCTest

/// Decision 936: the footbridges and underpass stairs between a station's
/// platforms, and an island's transfer signs, are the studio's models.
final class Map3DStationFootbridgeTests: XCTestCase {
    private typealias Bridge = Map3DStationFootbridge
    private typealias Sign = Map3DPlatformTransferSign
    private typealias Builder = Map3DScene.Builder

    // MARK: The models

    /// Every part of every style decodes, near and far, at the studio's
    /// sizes and in colours the game already has.
    func testThePartsDecodeAtTheStudiosSizes() throws {
        XCTAssertEqual(Bridge.models.count, Bridge.encoded.count)
        XCTAssertEqual(Bridge.models.count, 3 * 4 * 2 + 2)
        for style in Bridge.Style.allCases {
            for far in [false, true] {
                let stair = try XCTUnwrap(Bridge.model(style, .stair, far: far)), span = try XCTUnwrap(Bridge.model(style, .span, far: far))
                let pier = try XCTUnwrap(Bridge.model(style, .pier, far: far)), end = try XCTUnwrap(Bridge.model(style, .end, far: far))
                XCTAssertEqual(stair.minimum.x, 0, accuracy: 0.35, "its first step at its origin")
                XCTAssertEqual(stair.maximum.x, Bridge.towerLength, accuracy: 0.35)
                XCTAssertEqual(stair.minimum.z, 0, accuracy: 0.02, "it stands on the platform")
                XCTAssertLessThanOrEqual(stair.maximum.y, Bridge.towerHalfWidth + 0.35)
                XCTAssertGreaterThanOrEqual(stair.minimum.y, -Bridge.towerHalfWidth - 0.35)
                XCTAssertEqual(span.maximum.y - span.minimum.y, Bridge.spanLength, accuracy: 0.05)
                // A span's and an end wall's origin is its underside;
                // with the tower's top they make one roof line.
                XCTAssertEqual(span.minimum.z, 0, accuracy: 0.02)
                XCTAssertEqual(end.minimum.z, 0, accuracy: 0.02)
                XCTAssertEqual(span.maximum.z + Bridge.deck, stair.maximum.z, accuracy: 0.02)
                XCTAssertEqual(end.maximum.y - end.minimum.y, 2 * Bridge.endHalf, accuracy: 0.02)
                XCTAssertEqual(pier.minimum.z, 0, accuracy: 0.02)
                XCTAssertEqual(pier.maximum.z, Bridge.deck + Builder.platformHeight, accuracy: 0.05, "up to the corridor's underside")
                for model in [stair, span, pier, end] {
                    XCTAssertTrue(model.vertices.allSatisfy { Bridge.meshPalette.contains($0.color) })
                }
            }
            // The far version is the lighter.
            let near = try XCTUnwrap(Bridge.model(style, .stair)), far = try XCTUnwrap(Bridge.model(style, .stair, far: true))
            XCTAssertLessThan(far.triangleCount, near.triangleCount)
        }
        let stairs = try XCTUnwrap(Bridge.underpass()), farStairs = try XCTUnwrap(Bridge.underpass(far: true))
        XCTAssertEqual(stairs.minimum.x, Bridge.Kind.underpass.reach.lowerBound, accuracy: 0.05)
        XCTAssertEqual(stairs.maximum.x, Bridge.Kind.underpass.reach.upperBound, accuracy: 0.05)
        XCTAssertEqual(stairs.minimum.z, -1.95, accuracy: 0.05, "its steps go down under the platform")
        XCTAssertLessThan(farStairs.triangleCount, stairs.triangleCount)
        XCTAssertNil(Bridge.Style(.nordic))
    }

    /// The underpass's steps are drawn on the platform's top, in the
    /// order they go down; what stands over the platform is as made.
    func testTheUnderpassStepsArePressedOntoThePlatform() throws {
        XCTAssertEqual(Bridge.pressedHeight(0), 0.1, accuracy: 0.001)
        XCTAssertEqual(Bridge.pressedHeight(-1.95), 0.022, accuracy: 0.001)
        XCTAssertGreaterThan(Bridge.pressedHeight(-0.5), Bridge.pressedHeight(-1))
        var mesh = Map3DMesh()
        let stairs = try XCTUnwrap(Bridge.underpass())
        Bridge.add(stairs, to: &mesh, at: Map3DPoint(0, 2, 0), forward: Map3DPoint(1, 0, 0), pressed: true)
        XCTAssertEqual(mesh.triangleCount, stairs.triangleCount)
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertGreaterThanOrEqual(bounds.min.y, 2)
        XCTAssertEqual(bounds.max.y, 2 + stairs.maximum.z, accuracy: 0.01)
    }

    // MARK: The plan

    func testATowerStandsOnEachPlatformWideEnoughWithRoom() {
        // Two side platforms either side of two tracks.
        let sides = [Bridge.Body(low: -7, high: -3.8, fits: true), Bridge.Body(low: 3.8, high: 7, fits: true)]
        XCTAssertEqual(Bridge.crossing(bodies: sides, tracks: [-2.2, 2.2]), Bridge.Crossing(towers: [-5.4, 5.4], piers: [0]))
        // Tracks too near each other for a pier between them.
        XCTAssertEqual(Bridge.crossing(bodies: sides, tracks: [-2, 2])?.piers, [])
        // An island's halves are one platform; no pier where it stands.
        let island = [Bridge.Body(low: -1.6, high: 0, fits: true), Bridge.Body(low: 0, high: 1.6, fits: true)]
        XCTAssertEqual(Bridge.merged(island), [Bridge.Body(low: -1.6, high: 1.6, fits: true)])
        let three = Bridge.crossing(bodies: sides + island, tracks: [-2.7, 2.7])
        XCTAssertEqual(three?.towers, [-5.4, 0, 5.4])
        XCTAssertEqual(three?.piers, [])
        // One half with no room: no tower on the island.
        let half = [Bridge.Body(low: -1.6, high: 0, fits: true), Bridge.Body(low: 0, high: 1.6, fits: false)]
        XCTAssertEqual(Bridge.crossing(bodies: sides + half, tracks: [-2.7, 2.7])?.towers, [-5.4, 5.4])
        // One platform, a platform too narrow, or no track between: none.
        XCTAssertNil(Bridge.crossing(bodies: [sides[0]], tracks: [0]))
        XCTAssertNil(Bridge.crossing(bodies: [sides[0], Bridge.Body(low: 3.8, high: 6, fits: true)], tracks: [0]))
        XCTAssertNil(Bridge.crossing(bodies: sides, tracks: [9]))
    }

    func testTheSpansFillTheWayBetweenTheTowers() {
        for gap: Float in [3.2, 6, 10.8, 14, 23.7] {
            let spans = Bridge.spans(from: 0, to: gap)
            XCTAssertEqual(Float(spans.count) * spans.length, max(gap - 2 * Bridge.towerHalfWidth, 0.5), accuracy: 0.001)
            if gap >= 6 {
                XCTAssertGreaterThanOrEqual(spans.length / Bridge.spanLength, 0.66)
                XCTAssertLessThanOrEqual(spans.length / Bridge.spanLength, 1.5)
            }
        }
    }

    func testItStandsPastTheCanopysEndOrNowhere() throws {
        let room = Bridge.towerLength
        let start = try XCTUnwrap(Bridge.place(length: 200, share: 0.6, room: room, atStart: true))
        XCTAssertEqual(start.upperBound, 40 - Bridge.canopyGap, accuracy: 0.001)
        XCTAssertEqual(start.upperBound - start.lowerBound, room, accuracy: 0.001)
        let end = try XCTUnwrap(Bridge.place(length: 200, share: 0.6, room: room, atStart: false))
        XCTAssertEqual(end.lowerBound, 160 + Bridge.canopyGap, accuracy: 0.001)
        // A short platform has room for the underpass's stairs only; a
        // hall's roof (95 %) leaves room for neither.
        XCTAssertNil(Bridge.place(length: 80, share: 0.6, room: room, atStart: true))
        XCTAssertNotNil(Bridge.place(length: 80, share: 0.6, room: 8.5, atStart: true))
        XCTAssertNil(Bridge.place(length: 200, share: 0.95, room: 8.5, atStart: true))
    }

    // MARK: In the scene

    /// A builder with two tracks along x at z ±`half` and a side
    /// platform outside each, `length` long, of one station.
    private func builder(length: Float = 200, half: Float = 2.5, island: Bool = false) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: .newGame())
        func line(_ z: Float) -> [Map3DPoint] {
            stride(from: -length / 2, through: length / 2, by: length / 10).map { Map3DPoint($0, Map3DScene.railLift, z) }
        }
        let station = StationID(rawValue: 1)
        // Right of +x is +z: a platform on the -z side has a negative offset.
        if island {
            builder.laidPlatforms = [
                Builder.LaidPlatform(station: station, line: line(-half), offset: 3.2, width: 3.2, structure: .surface, island: true),
                Builder.LaidPlatform(station: station, line: line(half + 6.4), offset: -3.2, width: 3.2, structure: .surface, island: true),
                Builder.LaidPlatform(station: station, line: line(-half), offset: -3.2, width: 3.2, structure: .surface),
            ]
            builder.trackLines = [(line(-half), .surface), (line(half + 6.4), .surface)]
        } else {
            builder.laidPlatforms = [
                Builder.LaidPlatform(station: station, line: line(-half), offset: -3.2, width: 3.2, structure: .surface),
                Builder.LaidPlatform(station: station, line: line(half), offset: 3.2, width: 3.2, structure: .surface),
            ]
            builder.trackLines = [(line(-half), .surface), (line(half), .surface)]
        }
        builder.stationSystems[station] = "tra_sched"
        return builder
    }

    private func roofs(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        meshes.values.flatMap(\.vertices).filter { $0.y > Map3DScene.railLift + Builder.platformHeight + Bridge.deck - 0.1 }
    }

    func testAFootbridgeSpansTheTracksPastTheCanopy() throws {
        var b = builder()
        b.addStationCrossings(b.world.railwaySnapshot())
        // A tower on each platform, clear of the canopy (x -60...60) and
        // the platform's ends.
        let near = roofs(b.nearMeshes), far = roofs(b.farMeshes)
        XCTAssertFalse(near.isEmpty)
        XCTAssertFalse(far.isEmpty)
        XCTAssertLessThan(far.count, near.count)
        XCTAssertTrue(roofs(b.meshes).isEmpty && roofs(b.closeMeshes).isEmpty)
        XCTAssertTrue(near.allSatisfy { $0.x < -60 - Bridge.canopyGap + 0.4 && $0.x > -100 })
        // Over both platforms and the tracks between, and no wider.
        XCTAssertEqual(near.map(\.z).min()!, -5.7 - Bridge.towerHalfWidth - 2 * Bridge.endHalf, accuracy: 0.4)
        XCTAssertEqual(near.map(\.z).max()!, 5.7 + Bridge.towerHalfWidth + 2 * Bridge.endHalf, accuracy: 0.4)
        // Nothing of it down in the trains' way between the platforms
        // but the pier in the middle (tracks 5 m apart).
        let low = b.nearMeshes.values.flatMap(\.vertices).filter {
            $0.y < Map3DScene.railLift + 5 && abs($0.z) < 4
        }
        XCTAssertFalse(low.isEmpty)
        XCTAssertTrue(low.allSatisfy { abs($0.z) < 0.7 })
        // Each platform keeps its own things clear of its tower.
        XCTAssertEqual(b.crossingKeepOut.count, 2)
        let kept = try XCTUnwrap(b.crossingKeepOut[0])
        XCTAssertEqual(kept.upperBound - kept.lowerBound, Bridge.towerLength, accuracy: 0.01)
        XCTAssertEqual(kept.upperBound, 40 - Bridge.canopyGap, accuracy: 0.01)
        b.addPlatformProps()
        let props = b.closeMeshes.values.flatMap(\.vertices).filter { $0.y > Map3DScene.railLift + Builder.platformHeight + 0.3 }
        XCTAssertFalse(props.isEmpty)
        XCTAssertTrue(props.allSatisfy { $0.x < -100 + kept.lowerBound - 0.2 || $0.x > -100 + kept.upperBound + 0.2 })
    }

    func testAShortPlatformHasTheUnderpassStairs() {
        var b = builder(length: 80)
        b.addStationCrossings(b.world.railwaySnapshot())
        XCTAssertTrue(roofs(b.nearMeshes).isEmpty, "no footbridge")
        let brick = b.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.redBrick }
        XCTAssertFalse(brick.isEmpty)
        // On the platforms, none of it on the track.
        XCTAssertTrue(brick.allSatisfy { abs($0.z) > 3.7 && abs($0.z) < 7.1 })
        XCTAssertTrue(b.nearMeshes.values.flatMap(\.vertices).allSatisfy { $0.y >= Map3DScene.railLift + Builder.platformHeight })
    }

    func testNoneWhereNothingCrossesOrOnTheNordicMap() {
        // One platform.
        var one = builder()
        one.laidPlatforms.removeLast()
        one.addStationCrossings(one.world.railwaySnapshot())
        XCTAssertTrue(one.nearMeshes.isEmpty && one.crossingKeepOut.isEmpty)
        // Under a shell, or where a real building stands for it.
        var shell = builder()
        shell.shellRoofed = [StationID(rawValue: 1)]
        shell.addStationCrossings(shell.world.railwaySnapshot())
        XCTAssertTrue(shell.nearMeshes.isEmpty)
        var studied = builder()
        studied.studiedStations = [StationID(rawValue: 1)]
        studied.addStationCrossings(studied.world.railwaySnapshot())
        XCTAssertTrue(studied.nearMeshes.isEmpty)
        // A track high over the platforms.
        var viaduct = builder()
        viaduct.trackLines.append((stride(from: Float(-100), through: 100, by: 20).map { Map3DPoint($0, 9, 0) }, .surface))
        viaduct.addStationCrossings(viaduct.world.railwaySnapshot())
        XCTAssertTrue(roofs(viaduct.nearMeshes).isEmpty)
    }

    // MARK: The transfer signs

    func testTheSignsDecodeAndCarryOnlyColourBlocks() throws {
        let hung = try XCTUnwrap(Sign.hung), post = try XCTUnwrap(Sign.post)
        XCTAssertEqual(hung.triangleCount, 296)
        XCTAssertEqual(post.triangleCount, 272)
        XCTAssertEqual(hung.maximum.z, 3.15, accuracy: 0.02, "its rods reach the canopy")
        XCTAssertEqual(hung.maximum.x, 1.2, accuracy: 0.02)
        XCTAssertEqual(post.minimum.z, 0, accuracy: 0.02)
        XCTAssertEqual(post.maximum.z, 2.35, accuracy: 0.02)
        for model in [hung, post] {
            XCTAssertTrue(model.vertices.allSatisfy { Sign.meshPalette.contains($0.color) })
            // A block each side of its middle, none across it.
            let blocks = model.vertices.filter { $0.color == Sign.placeholder }
            XCTAssertTrue(blocks.contains { $0.x < -0.2 } && blocks.contains { $0.x > 0.2 })
            XCTAssertTrue(blocks.allSatisfy { abs($0.x) > 0.2 })
        }
    }

    func testEachSidesBlockTakesItsLinesColour() throws {
        let red: UInt32 = Map3DColor.rgb(0xD0_30_30), blue: UInt32 = Map3DColor.rgb(0x20_50_C0), green: UInt32 = Map3DColor.rgb(0x20_A0_50)
        var mesh = Map3DMesh()
        // Its +x (towards the far track) along world +z.
        XCTAssertTrue(Sign.add(to: &mesh, at: Map3DPoint(0, 1, 0), across: Map3DPoint(0, 0, 1), hung: true, near: [red], far: [blue]))
        XCTAssertEqual(mesh.triangleCount, 296)
        XCTAssertFalse(mesh.vertices.contains { $0.color == Sign.placeholder })
        let reds = mesh.vertices.filter { $0.color == red }, blues = mesh.vertices.filter { $0.color == blue }
        XCTAssertFalse(reds.isEmpty)
        XCTAssertEqual(reds.count, blues.count)
        XCTAssertTrue(reds.allSatisfy { $0.z < 0 } && blues.allSatisfy { $0.z > 0 })
        XCTAssertEqual(try XCTUnwrap(mesh.bounds).max.y, 1 + 3.15, accuracy: 0.02)
        // A second line: a second block beside the first, still on its side.
        var two = Map3DMesh()
        XCTAssertTrue(Sign.add(to: &two, at: Map3DPoint(0, 1, 0), across: Map3DPoint(0, 0, 1), hung: false, near: [red, green], far: [blue]))
        let greens = two.vertices.filter { $0.color == green }
        XCTAssertEqual(greens.count, two.vertices.filter { $0.color == red }.count)
        XCTAssertTrue(greens.allSatisfy { $0.z < 0 })
        XCTAssertEqual(greens.map(\.z).reduce(0, +) / Float(greens.count),
                       two.vertices.filter { $0.color == red }.map(\.z).reduce(0, +) / Float(greens.count) + Sign.secondBlockPost, accuracy: 0.01)
        XCTAssertFalse(Sign.add(to: &two, at: .init(0, 0, 0), across: Map3DPoint(0, 0, 1), hung: true, near: [], far: [blue]))
    }

    func testASignHangsInsideEachEndOfTheCanopyOrStandsPastIt() {
        let roof: ClosedRange<Float> = 40...160
        XCTAssertEqual(Sign.places(length: 200, width: 6.4, roof: roof, taken: []),
                       [Sign.Place(along: 40.2, hung: true), Sign.Place(along: 159.8, hung: true)])
        // Too narrow to hang one: on a post past the canopy.
        XCTAssertEqual(Sign.places(length: 200, width: 2.6, roof: roof, taken: []),
                       [Sign.Place(along: 38.8, hung: false), Sign.Place(along: 161.2, hung: false)])
        XCTAssertEqual(Sign.places(length: 200, width: 2, roof: roof, taken: []), [])
        // No canopy of its own: posts a fifth in from each end.
        XCTAssertEqual(Sign.places(length: 100, width: 6.4, roof: nil, taken: []),
                       [Sign.Place(along: 20, hung: false), Sign.Place(along: 80, hung: false)])
        // Clear of a footbridge's tower.
        XCTAssertEqual(Sign.places(length: 200, width: 2.6, roof: roof, taken: [21...37, 150...162]), [Sign.Place(along: 38.8, hung: false)])
    }

    /// An island whose two tracks no line serves has no sign.
    func testAnIslandWithNoLinesHasNoSign() throws {
        var b = builder(island: true)
        var transfers: [StationID: StationTransfers] = [:]
        for index in b.laidPlatforms.indices {
            let path = try XCTUnwrap(Map3DStreetLife.Path(b.laidPlatforms[index].line))
            XCTAssertTrue(b.transferSigns(on: index, of: b.laidPlatforms, path: path, crossing: nil, transfers: &transfers).isEmpty)
        }
        let before = b.closeMeshes.values.reduce(0) { $0 + $1.triangleCount }
        XCTAssertEqual(before, 0)
        b.addPlatformProps()
        XCTAssertFalse(b.closeMeshes.isEmpty)
    }
}
