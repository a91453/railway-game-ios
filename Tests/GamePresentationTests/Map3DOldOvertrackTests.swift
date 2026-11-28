@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1043: a ground station in Japan whose building stands over
/// its tracks, from the earlier version's 橋上駅舎, restyled as the game's.
final class Map3DOldOvertrackTests: XCTestCase {
    private typealias Old = Map3DOldOvertrack
    private typealias Body = Map3DStationFootbridge.Body
    private typealias Builder = Map3DScene.Builder

    /// The old red roofs' colour (decision 1042's palette slot).
    private let red = Map3DOldGroundStation.meshPalette[8]

    // MARK: The models

    /// Every model decodes in the ground stations' palette with no old
    /// red left, its roof green; each hall's underside at the footbridge
    /// deck over the platforms (nothing between the platforms' height and
    /// it over its tracks), a blue name board on each street front, and
    /// its far version lighter.
    func testTheModelsDecodeRestyled() throws {
        let face = Old.platformFace + Old.deck
        for (hall, tracks, fronts) in [(Old.Hall.side, [-Old.sideTracks, Old.sideTracks], [Float(-1)]),
                                       (.island, [-Old.islandTracks, Old.islandTracks], [-1, 1])] {
            let near = try XCTUnwrap(Old.model(hall.rawValue)), far = try XCTUnwrap(Old.model(hall.rawValue, far: true))
            XCTAssertLessThan(far.triangleCount, near.triangleCount, hall.rawValue)
            for model in [near, far] {
                XCTAssertTrue(model.vertices.allSatisfy { Map3DOldGroundStation.meshPalette.contains($0.color) && $0.color != red }, hall.rawValue)
                XCTAssertEqual(model.minimum.x, Old.hallReach.lowerBound, accuracy: 0.15, hall.rawValue)
                XCTAssertEqual(model.maximum.x, Old.hallReach.upperBound, accuracy: 0.15, hall.rawValue)
                XCTAssertTrue(model.vertices.contains { abs($0.z - face) < 0.01 }, "\(hall) underside")
                // The trains' way under it is clear.
                for track in tracks {
                    XCTAssertFalse(model.vertices.contains { abs($0.y - track) < 1.5 && $0.z > 0.9 && $0.z < face - 0.01 }, "\(hall) over \(track)")
                }
            }
            XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.gymGreen && $0.z > 11.5 }, "\(hall) green roof")
            for front in fronts {
                XCTAssertTrue(near.vertices.contains { $0.color == Map3DPalette.canopy && $0.y * front > 11.3 && $0.z > 11.9 }, "\(hall) board \(front)")
            }
        }
        let stair = try XCTUnwrap(Old.model(Old.stair))
        XCTAssertTrue(stair.vertices.allSatisfy { $0.color != red })
        XCTAssertEqual(stair.minimum.z, Old.platformFace, accuracy: 0.05)
        XCTAssertEqual(stair.maximum.y, Old.stairRoof, accuracy: 0.05)
        // The corridor's metre: its walls and roof between the hall's
        // and the stair's, open at both ends.
        let corridor = try XCTUnwrap(Old.model(Old.corridor))
        XCTAssertEqual(corridor.minimum.y, 0, accuracy: 0.001)
        XCTAssertEqual(corridor.maximum.y, 1, accuracy: 0.001)
        XCTAssertEqual(corridor.minimum.z, face, accuracy: 0.01)
        XCTAssertTrue(corridor.vertices.contains { $0.color == Map3DPalette.gymGreen })
        XCTAssertNil(Old.models[Old.stair + "-far"], "the stair has no far version")
    }

    // MARK: The plan

    private let sides = [Body(low: -7.3, high: -4.1, fits: true), Body(low: 4.1, high: 7.3, fits: true)]

    /// Two side platforms either side of two tracks 5 m apart: the side
    /// hall over their middle, its street side the way with no other track
    /// (the line's left when both are clear), no further stairs.
    func testTwoSidePlatformsTakeTheSideHall() throws {
        let plan = try XCTUnwrap(Old.plan(bodies: sides, tracks: [-2.5, 2.5]))
        XCTAssertEqual(plan, Old.Plan(hall: .side, centre: 0, way: 1))
        // 4 m apart, as the game's double track often is, still fits.
        XCTAssertEqual(Old.plan(bodies: [Body(low: -6.8, high: -3.6, fits: true), Body(low: 3.6, high: 6.8, fits: true)], tracks: [-2, 2])?.hall, .side)
        // Another track on the left: the street side turns right.
        XCTAssertEqual(Old.plan(bodies: sides, tracks: [-10, -2.5, 2.5])?.way, -1)
        // Other track either side: no room for the street's stairs.
        XCTAssertNil(Old.plan(bodies: sides, tracks: [-10, -2.5, 2.5, 10]))
        // A street platform too wide for the wing.
        XCTAssertNil(Old.plan(bodies: [Body(low: -9.3, high: -4.1, fits: true), Body(low: 4.1, high: 9.3, fits: true)], tracks: [-2.5, 2.5]))
        // Tracks too far apart for the hall.
        XCTAssertNil(Old.plan(bodies: [Body(low: -10.3, high: -7.1, fits: true), Body(low: 7.1, high: 10.3, fits: true)], tracks: [-5.5, 5.5]))
    }

    /// An island between its two tracks 11 m apart: the island hall.
    func testAnIslandTakesTheIslandHall() {
        let halves = [Body(low: -3.9, high: 0, fits: true), Body(low: 0, high: 3.9, fits: true)]
        XCTAssertEqual(Old.plan(bodies: halves, tracks: [-5.5, 5.5]), Old.Plan(hall: .island, centre: 0, way: 1))
        // A third track by it: not the earlier version's island.
        XCTAssertNil(Old.plan(bodies: halves, tracks: [-10, -5.5, 5.5]))
        // Two islands (four tracks): neither hall.
        XCTAssertNil(Old.plan(bodies: halves + [Body(low: 18.4, high: 25.6, fits: true)], tracks: [-5.5, 5.5, 16.5, 27.5]))
    }

    /// A further island past the side platforms: its stair, the corridor
    /// from the hall's wall to it, and a pier between two through tracks
    /// it crosses; none on the street side.
    func testAFurtherIslandTakesTheStairAndCorridor() throws {
        let island = Body(low: 22.6, high: 30.4, fits: true)
        let plan = try XCTUnwrap(Old.plan(bodies: sides + [island], tracks: [-2.5, 2.5, 12, 17, 21, 32]))
        XCTAssertEqual(plan.hall, .side)
        XCTAssertEqual(plan.way, 1)
        XCTAssertEqual(plan.stairs, [26.5])
        XCTAssertEqual(plan.corridors.count, 1)
        XCTAssertEqual(plan.corridors[0].lowerBound, Old.hallWall, accuracy: 0.001)
        XCTAssertEqual(plan.corridors[0].upperBound, 26.5 - Old.stairWall, accuracy: 0.001)
        XCTAssertEqual(plan.piers, [14.5])
        XCTAssertEqual(plan.reach.upperBound, 26.5 + Old.stairRoof, accuracy: 0.001)
        // An island too narrow for the stair.
        XCTAssertNil(Old.plan(bodies: sides + [Body(low: 24, high: 28, fits: true)], tracks: [-2.5, 2.5, 21, 32]))
        // Too far.
        XCTAssertNil(Old.plan(bodies: sides + [Body(low: 62.6, high: 70.4, fits: true)], tracks: [-2.5, 2.5, 61, 72]))
    }

    /// An island always (no other way up to it); two side platforms with
    /// the bigger concourse or no room beside them; never a big station.
    func testWhichStationsTakeIt() {
        let side = Old.Plan(hall: .side, centre: 0, way: 1), island = Old.Plan(hall: .island, centre: 0, way: 1)
        XCTAssertTrue(Old.chosen(island, expansion: nil, roomBeside: true))
        XCTAssertFalse(Old.chosen(side, expansion: nil, roomBeside: true))
        XCTAssertTrue(Old.chosen(side, expansion: nil, roomBeside: false))
        XCTAssertTrue(Old.chosen(side, expansion: .concourse, roomBeside: true))
        XCTAssertFalse(Old.chosen(side, expansion: .hall, roomBeside: false))
        XCTAssertFalse(Old.chosen(island, expansion: .hall, roomBeside: false))
    }

    // MARK: In the scene

    private func japan() throws -> GameWorld {
        GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 33.5897, longitudeDegrees: 130.4207)))
    }

    private func line(_ z: Float, y: Float = Map3DScene.railLift) -> [Map3DPoint] {
        stride(from: Float(-100), through: 100, by: 20).map { Map3DPoint($0, y, z) }
    }

    /// Two tracks along x 5 m apart and a side platform outside each, or
    /// an island between two 11 m apart, 200 m long, of one station.
    private func builder(_ world: GameWorld, island: Bool = false) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: world)
        let station = StationID(rawValue: 1)
        // Right of +x is +z: a platform on the -z side has a negative offset.
        let half: Float = island ? 5.5 : 2.5
        builder.state.platforms.laidPlatforms = island
            ? [Builder.LaidPlatform(station: station, line: line(-half), offset: 3.55, width: 3.9, structure: .surface, island: true),
               Builder.LaidPlatform(station: station, line: line(half), offset: -3.55, width: 3.9, structure: .surface, island: true)]
            : [Builder.LaidPlatform(station: station, line: line(-half), offset: -3.2, width: 3.2, structure: .surface),
               Builder.LaidPlatform(station: station, line: line(half), offset: 3.2, width: 3.2, structure: .surface)]
        builder.state.track.trackLines = [(line(-half), .surface), (line(half), .surface)]
        builder.state.stations.stationSystems[station] = "tra_sched"
        return builder
    }

    private func tracks(_ b: Builder) -> [Map3DStreetLife.Path] {
        b.state.track.trackLines.compactMap { Map3DStreetLife.Path($0.points) }
    }

    /// Placed over the platforms' middle, the hall's underside at the
    /// footbridge deck, its street side to the line's left, its platforms
    /// kept clear along its length; in its own colours close up and far
    /// off, its footprint kept.
    func testTheSideHallStandsOverThePlatformsMiddle() throws {
        var b = builder(try japan())
        let placed = try XCTUnwrap(b.planOvertrack(StationID(rawValue: 1), indices: [0, 1], tracks: tracks(b)))
        XCTAssertEqual(placed.plan.hall, .side)
        let length = Old.hallReach.upperBound - Old.hallReach.lowerBound
        for index in [0, 1] {
            let kept = try XCTUnwrap(placed.keepOut[index])
            XCTAssertEqual(kept.lowerBound, 100 - length / 2, accuracy: 0.01)
            XCTAssertEqual(kept.upperBound, 100 + length / 2, accuracy: 0.01)
        }
        XCTAssertEqual(placed.origin.y, 0, accuracy: 0.001, "the ground, 2 m under the platforms")
        _ = b.addOvertrack(placed)
        let near = b.ownColourNear.values.flatMap(\.vertices), far = b.ownColourFar.values.flatMap(\.vertices)
        XCTAssertFalse(near.isEmpty)
        XCTAssertLessThan(far.count, near.count)
        XCTAssertEqual(near.map(\.x).min()!, -length / 2, accuracy: 0.2)
        XCTAssertEqual(near.map(\.x).max()!, length / 2, accuracy: 0.2)
        // Its street side to the left (−z), its wall the other side.
        XCTAssertEqual(near.map(\.z).min()!, -Old.sideStreet, accuracy: 0.05)
        XCTAssertEqual(near.map(\.z).max()!, Old.hallWall + 0.3, accuracy: 0.05)
        let deck = Map3DScene.railLift + Builder.platformHeight + Old.deck
        XCTAssertFalse(near.contains { abs(abs($0.z) - 2.5) < 1.5 && $0.y > 0.9 && $0.y < deck - 0.01 }, "the trains' way clear")
        XCTAssertEqual(b.state.stations.houseFootprints.count, 1)
        XCTAssertEqual(b.state.stations.houseTriangleCount, b.ownColourNear.values.reduce(0) { $0 + $1.triangleCount })
        XCTAssertTrue(b.nearMeshes.isEmpty, "nothing in the chunks' own colours")
    }

    /// The island hall over an island's middle, both its halves kept clear.
    func testTheIslandHallStandsOverTheIsland() throws {
        var b = builder(try japan(), island: true)
        let placed = try XCTUnwrap(b.planOvertrack(StationID(rawValue: 1), indices: [0, 1], tracks: tracks(b)))
        XCTAssertEqual(placed.plan.hall, .island)
        XCTAssertEqual(Set(placed.keepOut.keys), [0, 1])
        _ = b.addOvertrack(placed)
        let near = b.ownColourNear.values.flatMap(\.vertices)
        XCTAssertEqual(near.map(\.z).min()!, -Old.islandStreet, accuracy: 0.05)
        XCTAssertEqual(near.map(\.z).max()!, Old.islandStreet, accuracy: 0.05)
    }

    /// None where a track runs high over the platforms, a platform is cut
    /// short under it, or a platform bends there.
    func testNoneWhereItCannotStand() throws {
        var viaduct = builder(try japan())
        viaduct.state.track.trackLines.append((line(0, y: 9), .surface))
        XCTAssertNil(viaduct.planOvertrack(StationID(rawValue: 1), indices: [0, 1], tracks: tracks(viaduct)))
        var short = builder(try japan())
        short.state.platforms.laidPlatforms[1] = Builder.LaidPlatform(
            station: StationID(rawValue: 1), line: stride(from: Float(10), through: 100, by: 10).map { Map3DPoint($0, Map3DScene.railLift, 2.5) },
            offset: 3.2, width: 3.2, structure: .surface)
        XCTAssertNil(short.planOvertrack(StationID(rawValue: 1), indices: [0, 1], tracks: tracks(short)))
    }

    /// The old canopies leave the hall's length: the units it stands over
    /// are left out, the run before it closed with its post; the lamps
    /// under them go with them.
    func testTheCanopyLeavesRoomForTheHall() throws {
        var b = builder(try japan())
        let placed = try XCTUnwrap(b.planOvertrack(StationID(rawValue: 1), indices: [0, 1], tracks: tracks(b)))
        b.state.stations.overtracks[StationID(rawValue: 1)] = placed
        for (index, range) in placed.keepOut { b.state.stationCrossings.crossingKeepOut[index] = range }
        b.addOldCanopy(on: 1, of: b.state.platforms.laidPlatforms)
        let top = Map3DScene.railLift + Builder.platformHeight
        let near = b.nearMeshes.values.flatMap(\.vertices)
        let roof = near.filter { $0.color == Map3DPalette.canopy }
        XCTAssertFalse(roof.isEmpty)
        // 120 m roofed in six 20 m units; the two the hall's 31 m cross go.
        XCTAssertFalse(roof.contains { abs($0.x) < 19.5 })
        XCTAssertTrue(roof.contains { $0.x < -19.5 } && roof.contains { $0.x > 19.5 })
        let feet = near.filter { $0.color == Map3DPalette.roofSlate && $0.y < top + 0.01 }.map(\.x).sorted()
        XCTAssertEqual(zip(feet, feet.dropFirst()).filter { $1 - $0 > 1 }.count + 1, 6, "four posts and two closing ones")
        b.addPlatformProps()
        let lamps = b.closeMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.tunnelLamp }
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertFalse(lamps.contains { abs($0.x) < Old.hallReach.upperBound - Old.hallMiddle - 1 })
    }

    /// A station with one draws no footbridge of decision 936.
    func testItStandsForTheFootbridge() throws {
        var plain = builder(.newGame())
        plain.addStationCrossings(plain.world.railwaySnapshot())
        XCTAssertFalse(plain.nearMeshes.isEmpty, "the footbridge without it")
        var b = builder(.newGame())
        let placed = try XCTUnwrap(b.planOvertrack(StationID(rawValue: 1), indices: [0, 1], tracks: tracks(b)))
        b.state.stations.overtracks[StationID(rawValue: 1)] = placed
        b.addStationCrossings(b.world.railwaySnapshot())
        XCTAssertTrue(b.nearMeshes.isEmpty)
    }
}
