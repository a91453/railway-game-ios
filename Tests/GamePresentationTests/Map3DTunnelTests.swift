import GameCore
@testable import GamePresentation
import XCTest

/// Decision 359: the 3D map in and round a tunnel, worked out without a
/// GPU: what shows over the ground where the track goes under it.
final class Map3DTunnelTests: XCTestCase {
    /// A flat world (the ground at 0 m) 1,280 m by 512 m: surface track
    /// from x = 32 m to the portal at 192 m, then a tunnel falling 4 m to
    /// x = 480 m (1.4 %) and on, level, to 960 m. A train of `cars` cars
    /// has its front at `at` (by default 320 m into the level tunnel).
    /// `deep`: falling 20 m instead, to x = 960 m (2.6 %), and on to
    /// 1,248 m.
    private func tunnelWorld(cars: Int = 4, at: TrainPosition = .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 20_480),
                             deep: Bool = false) throws -> (world: GameWorld, train: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 16_384))
        let down = try world.buildTrackNode(at: deep ? WorldCoordinate(x: 61_440, y: 16_384, z: -1_280) : WorldCoordinate(x: 30_720, y: 16_384, z: -256))
        let end = try world.buildTrackNode(at: deep ? WorldCoordinate(x: 79_872, y: 16_384, z: -1_280) : WorldCoordinate(x: 61_440, y: 16_384, z: -256))
        try world.buildTrackEdge(from: a, to: portal)
        try world.buildTrackEdge(from: portal, to: down, structure: .tunnel)
        try world.buildTrackEdge(from: down, to: end, structure: .tunnel)
        let train = try world.purchaseTrain(named: "Mole").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: at)
        return (world, train)
    }

    private func frame(_ world: GameWorld, scene: Map3DScene) -> Map3DTrains.Frame {
        Map3DTrains.frame(TrainMotion(world: world, time: 0), progress: 1, heights: Map3DTrains.Heights(world: world), in: scene,
                          models: nil, eye: nil)
    }

    /// The owner's report (2026-10-22): a train in a tunnel was drawn at
    /// the track's height over track not drawn. Decision 359 (續): the
    /// tunnel is drawn now, so its cars are, in it; they are no car of
    /// decision 342's, as nothing on the ground stands between them and
    /// an eye over it.
    func testACarInATunnelIsDrawnInItsBore() throws {
        let (world, _) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let frame = frame(world, scene: scene)
        XCTAssertFalse(frame.boxes.isEmpty, "the cars are drawn")
        XCTAssertFalse(frame.shadows.isEmpty)
        XCTAssertTrue(frame.cars.isEmpty, "cars in the tunnel see through buildings at \(frame.cars)")
    }

    /// Half out of the portal: every car shows; only those out of it see
    /// through buildings.
    func testEveryCarShowsHalfOutOfTheTunnel() throws {
        // Running out: its front 60 m past the portal, its back in the
        // tunnel.
        let (world, _) = try tunnelWorld(cars: 6, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .backward), offset: 3_840))
        let scene = Map3DScene(world: world)
        let frame = frame(world, scene: scene)
        let portalX = scene.point(worldX: 12_288, worldY: 16_384, height: 0).x
        XCTAssertGreaterThanOrEqual(frame.boxes.vertices.filter { $0.x > portalX + 5 }.count, 1, "the cars in the tunnel show")
        XCTAssertFalse(frame.cars.isEmpty)
        XCTAssertLessThan(frame.cars.count, 6)
        for car in frame.cars { XCTAssertLessThanOrEqual(car.x, portalX, "a car in the tunnel sees through") }
    }

    /// The camera following a train into a tunnel: from behind and above,
    /// over the ground; from the cab, in the tunnel, at the cab's eye.
    func testTheFollowCameraInATunnel() throws {
        let (world, train) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let head = try XCTUnwrap(frame(world, scene: scene).heads.first { $0.train == train }, "the head is kept for the camera")
        let ground = try XCTUnwrap(head.ground)
        XCTAssertEqual(ground, 0, accuracy: 0.01, "the flat ground over the tunnel")
        XCTAssertTrue(head.inTunnel)
        XCTAssertLessThan(head.rail.y, ground)
        let start = Map3DCamera(target: head.rail, distance: 300, viewport: (390, 844))
        for view in Map3DFollow.View.allCases {
            for scale in [Map3DFollow.scales.lowerBound, 1, Map3DFollow.scales.upperBound] {
                var follow = Map3DFollow(train: train, view: view)
                follow.scale = scale
                let camera = follow.camera(following: head, from: start, elapsed: 0, turnsAtOnce: true)
                if view == .cab {
                    XCTAssertEqual(camera.eye.y, head.nose.y + Map3DFollow.cabEyeHeight, accuracy: 0.05, "at \(scale): the cab's eye in the tunnel")
                } else {
                    XCTAssertGreaterThan(camera.eye.y, ground + 0.5, "\(view) at \(scale): the eye in the ground")
                    XCTAssertEqual(camera.target.y, ground, accuracy: 0.01, "\(view) looks at the ground over the train")
                }
            }
        }
    }

    /// Out of the tunnel the camera follows as before: at the rails.
    func testOnTheSurfaceTheCameraLooksAtTheRails() throws {
        let (world, train) = try tunnelWorld(cars: 2, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .backward), offset: 6_400))
        let scene = Map3DScene(world: world)
        let head = try XCTUnwrap(frame(world, scene: scene).heads.first { $0.train == train })
        XCTAssertEqual(try XCTUnwrap(head.ground), 0, accuracy: 0.01)
        XCTAssertFalse(scene.trackCover.isInTunnel(head.nose))
        XCTAssertFalse(head.inTunnel)
        let camera = Map3DFollow(train: train).camera(following: head, from: Map3DCamera(viewport: (390, 844)), elapsed: 0, turnsAtOnce: true)
        XCTAssertEqual(camera.target, head.rail)
    }

    /// Only the tunnel's track is in it: not the surface track past the
    /// portal, nor a surface track beside the tunnel 4 m away, nor one
    /// crossing 8 m over it; the outside of a bend in the tunnel is.
    func testWhatIsInTheTunnel() throws {
        var (world, _) = try tunnelWorld()
        let over1 = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 8_192, z: 256))
        let over2 = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 24_576, z: 256))
        try world.buildTrackEdge(from: over1, to: over2, structure: .elevated)
        let scene = Map3DScene(world: world)
        let cover = scene.trackCover
        func rail(_ x: Double, y: Double = 16_384, z: Double) -> Map3DPoint {
            scene.point(worldX: x, worldY: y, height: z) + Map3DPoint(0, Map3DScene.railLift, 0)
        }
        XCTAssertTrue(cover.isInTunnel(rail(12_352, z: -1)), "1 m into the portal")
        XCTAssertFalse(cover.isInTunnel(rail(12_224, z: 0)), "1 m out of it")
        XCTAssertFalse(cover.isInTunnel(rail(40_960, y: 16_384 + 256, z: -256)), "4 m beside the tunnel")
        XCTAssertTrue(cover.isInTunnel(rail(40_960, y: 16_384 + 64, z: -256)), "1 m off its middle")
        XCTAssertFalse(cover.isInTunnel(rail(40_960, z: 256)), "on the viaduct over it")
        XCTAssertNotNil(cover.ground(at: rail(40_960, z: 256)), "the viaduct is track too")
        XCTAssertNil(cover.ground(at: rail(40_960, y: 4_096, z: 0)), "off the track")
    }

    // MARK: The tunnel drawn (decision 359 續)

    /// Every vertex of the scene's chunks, near and far detail alike.
    private func vertices(_ scene: Map3DScene) -> [Map3DVertex] {
        scene.chunks.flatMap { $0.mesh.vertices }
    }

    /// Where the tunnel's rails run in the scene: along x at this z.
    private func line(_ scene: Map3DScene, y: Double = 16_384) -> Float {
        scene.point(worldX: 0, worldY: y, height: 0).z
    }

    /// The bore round the level tunnel: walls 3.2 m either side of the
    /// track (the reference's `PORTAL_HALF_CLEAR`), a roof 6 m over the
    /// rails, and lamps on its walls that glow at night.
    func testTheTunnelHasABoreWithLamps() throws {
        let (world, _) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let z = line(scene)
        let rail = Float(-4) + Map3DScene.railLift
        let from = scene.point(worldX: 32_000, worldY: 16_384, height: 0).x, to = scene.point(worldX: 60_000, worldY: 16_384, height: 0).x
        let bore = vertices(scene).filter { $0.x > from && $0.x < to && abs($0.z - z) < 4 && $0.y < rail + 6.5 && $0.y > rail - 1.5 }
        XCTAssertTrue(bore.contains { abs(abs($0.z - z) - Map3DScene.Builder.boreHalfWidth) < 0.01 && $0.y > rail + 1 }, "its walls")
        XCTAssertTrue(bore.contains { abs($0.z - z) < 0.5 && abs($0.y - (rail + Map3DScene.Builder.boreCrown)) < 0.01 }, "its roof")
        XCTAssertTrue(bore.contains { abs($0.z - z) < 1 && $0.y < rail && $0.y > rail - 0.5 }, "its bed")
        let lamps = bore.filter(\.glows)
        XCTAssertFalse(lamps.isEmpty, "its lamps")
        let along = Set(lamps.map { Int(($0.x / Map3DScene.Builder.lampSpacing).rounded(.down)) })
        XCTAssertGreaterThan(along.count, 10, "a lamp every \(Map3DScene.Builder.lampSpacing) m")
    }

    /// Only 4 m down, the bore's roof would stand out of the ground: a
    /// bank of earth covers it there (a cut-and-cover tunnel's), so the
    /// train in it never shows over the ground. 20 m down it is all
    /// under the ground and nothing of it shows.
    func testAShallowTunnelIsCoveredAndADeepOneHidden() throws {
        let (shallow, _) = try tunnelWorld()
        let scene = Map3DScene(world: shallow)
        let z = line(scene)
        let x = scene.point(worldX: 40_960, worldY: 16_384, height: 0).x
        let over = vertices(scene).filter { abs($0.x - x) < 16 && abs($0.z - z) < 4.5 && $0.y > 0.1 }
        XCTAssertTrue(over.contains { $0.ny > 0.9 && $0.y >= -4 + Map3DScene.railLift + Map3DScene.Builder.boreCrown }, "its bank's top")

        let (deep, _) = try tunnelWorld(at: .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 8_192), deep: true)
        let deepScene = Map3DScene(world: deep)
        let deepX = deepScene.point(worldX: 70_000, worldY: 16_384, height: 0).x
        let showing = vertices(deepScene).filter { abs($0.x - deepX) < 64 && abs($0.z - line(deepScene)) < 8 && $0.y > -1 }
        XCTAssertTrue(showing.allSatisfy { $0.y < 0.5 }, "nothing of a deep tunnel over the ground: \(showing.filter { $0.y >= 0.5 }.prefix(3))")
        XCTAssertTrue(vertices(deepScene).contains { abs($0.x - deepX) < 16 && $0.y < -10 }, "its bore is drawn")
    }

    /// Two tunnels 4 m apart share one bore: no wall between them where
    /// a train runs.
    func testTwoTracksShareABore() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        for y: Int64 in [16_384, 16_640] {
            let a = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: y, z: -1_280))
            let b = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: y, z: -1_280))
            try world.buildTrackEdge(from: a, to: b, structure: .tunnel)
        }
        let scene = Map3DScene(world: world)
        let first = line(scene), second = line(scene, y: 16_640)
        let rail = Float(-20) + Map3DScene.railLift
        let x = scene.point(worldX: 40_960, worldY: 16_384, height: 0).x
        let between = vertices(scene).filter {
            abs($0.x - x) < 64 && $0.z > first + 0.8 && $0.z < second - 0.8 && $0.y > rail + 0.5 && $0.y < rail + Map3DTrains.carHeight + 0.5
        }
        XCTAssertTrue(between.isEmpty, "a wall between the tracks at \(between.prefix(3).map { ($0.x, $0.y, $0.z) })")
        let all = vertices(scene).filter { abs($0.x - x) < 64 }
        XCTAssertTrue(all.contains { abs($0.z - (first - Map3DScene.Builder.boreHalfWidth)) < 0.01 }, "the outer wall on one side")
        XCTAssertTrue(all.contains { abs($0.z - (second + Map3DScene.Builder.boreHalfWidth)) < 0.01 }, "and on the other")
    }

    /// The portal: a head wall up to 7.3 m over the rails across the
    /// opening and 2 m past it, and wing walls splaying 8 m out of it
    /// (the reference's `tunnel-portals.js`), on the drawn ground.
    func testThePortalHasAHeadWallAndWings() throws {
        let (world, _) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let portal = scene.point(worldX: 12_288, worldY: 16_384, height: 0)
        let rail = Map3DScene.railLift
        let near = vertices(scene).filter { abs($0.x - portal.x) < 12 && abs($0.z - portal.z) < 12 }
        XCTAssertTrue(near.contains { $0.y > rail + 7.2 && abs($0.z - portal.z) > 5 }, "the head wall's shoulders")
        XCTAssertTrue(near.contains { $0.x < portal.x - 7.9 && abs($0.z - portal.z) > 7 }, "the wings 8 m out of it")
        XCTAssertFalse(near.contains { $0.y > rail + 0.5 && $0.y < rail + 5.5 && abs($0.z - portal.z) < 3 && abs($0.x - portal.x) < 1.5 && $0.nx.magnitude > 0.9 },
                       "the opening is open")
        XCTAssertTrue(near.contains { $0.y < 0.01 && abs($0.z - portal.z) > 5 }, "down to the ground")
    }

    /// Decision 358: chunks built apart are the whole scene's, tunnel and
    /// portals too.
    func testTunnelChunksBuiltApartAreTheWholeScenes() throws {
        let (world, _) = try tunnelWorld()
        let origin = (x: 40_960.0, y: 16_384.0)
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        // The whole map, 1,280 m by 512 m: chunks −2…1 by −1…0.
        let whole = WorldRegion(bounds: world.bounds)
        let snapshot = world.railwaySnapshot()
        let scene = Map3DScene(world: world, snapshot: snapshot, skyline: nil, frame: (whole, origin.x, origin.y), baseMap: nil, cityTiles: [],
                               heights: nil, lineBands: nil, railways: nil, temples: nil)
        var apart: [Map3DScene.Chunk] = []
        for column in -2...1 {
            apart += Map3DScene.chunks([Map3DStreaming.Key(column: column, row: -1), Map3DStreaming.Key(column: column, row: 0)], of: grid,
                                       world: world, snapshot: snapshot)
        }
        let wholeChunks = Dictionary(uniqueKeysWithValues: scene.chunks.map { (Map3DStreaming.Key(column: $0.column, row: $0.row), $0) })
        XCTAssertEqual(apart.count, scene.chunks.count)
        var glowing = 0
        for chunk in apart {
            let same = try XCTUnwrap(wholeChunks[Map3DStreaming.Key(column: chunk.column, row: chunk.row)])
            XCTAssertEqual(chunk.mesh.vertices, same.mesh.vertices, "\(chunk.column), \(chunk.row)")
            XCTAssertEqual(chunk.mesh.indices, same.mesh.indices)
            glowing += chunk.mesh.vertices.filter(\.glows).count
        }
        XCTAssertGreaterThan(glowing, 0, "the tunnel is in them")
    }
}
