import GameCore
@testable import GamePresentation
import XCTest

/// Decision 672: seeing underground in the 3D map, the headlamps' light in
/// a tunnel, and the ground round a shallow bore at its portal, worked out
/// without a GPU.
final class Map3DXRayTests: XCTestCase {
    /// Decision 359's tunnel world: flat ground at 0 m, surface track from
    /// x = 32 m to the portal at 192 m, then a tunnel falling 4 m to
    /// 480 m and on, level, to 960 m. A train of four cars has its front
    /// 320 m into the level tunnel. `platform`: a station's platform in
    /// the level tunnel, from 520 m to 740 m.
    private func tunnelWorld(platform: Bool = false) throws -> (world: GameWorld, train: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 16_384))
        let down = try world.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 16_384, z: -256))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 16_384, z: -256))
        try world.buildTrackEdge(from: a, to: portal)
        try world.buildTrackEdge(from: portal, to: down, structure: .tunnel)
        try world.buildTrackEdge(from: down, to: end, structure: .tunnel)
        if platform {
            let station = try world.buildStation(named: "Deep", at: PlanPoint(x: 40_000, y: 16_640))
            try world.addTrackPlatform(station.id, on: .edge(3), from: 40 * 64, to: 260 * 64)
        }
        let train = try world.purchaseTrain(named: "Mole").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 20_480))
        return (world, train)
    }

    private func frame(_ world: GameWorld, scene: Map3DScene, buried: Bool = false, headlamp: TrainID? = nil) -> Map3DTrains.Frame {
        Map3DTrains.frame(TrainMotion(world: world, time: 0), progress: 1, heights: Map3DTrains.Heights(world: world), in: scene,
                          models: nil, eye: nil, buried: buried, headlamp: headlamp)
    }

    // MARK: Seeing underground

    /// Off (the default), nothing is built or drawn: the empty x-ray, and
    /// no buried cars in a frame not asked for them. On, only over the
    /// map, not while following.
    func testOffCostsNothing() throws {
        XCTAssertTrue(Map3DXRay().mesh.isEmpty)
        XCTAssertFalse(Map3DXRay.draws(switchOn: false, following: false))
        XCTAssertFalse(Map3DXRay.draws(switchOn: true, following: true))
        XCTAssertTrue(Map3DXRay.draws(switchOn: true, following: false))
        let (world, _) = try tunnelWorld()
        let frame = frame(world, scene: Map3DScene(world: world))
        XCTAssertTrue(frame.buried.isEmpty, "the cars in the tunnel are kept only when asked")
    }

    /// On, the tunnel's track shows through the ground, see-through, over
    /// the tunnel only; the cars in it are kept for it.
    func testTheTunnelAndItsTrainShowThroughTheGround() throws {
        let (world, _) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let xray = Map3DXRay(scene: scene, snapshot: world.railwaySnapshot())
        XCTAssertFalse(xray.mesh.isEmpty)
        let portalX = scene.point(worldX: 12_288, worldY: 16_384, height: 0).x
        let endX = scene.point(worldX: 61_440, worldY: 16_384, height: 0).x
        for vertex in xray.mesh.vertices {
            XCTAssertGreaterThan(vertex.x, portalX - 5, "only the tunnel shows")
            XCTAssertLessThan(vertex.x, endX + 5)
            let alpha = vertex.color >> 24
            XCTAssertGreaterThan(alpha, 0)
            XCTAssertLessThan(alpha, 255, "see-through")
        }
        let frame = frame(world, scene: scene, buried: true)
        XCTAssertEqual(frame.buried.count, 4, "every car is in the tunnel")
        var cars = Map3DMesh()
        Map3DXRay.addCars(frame.buried, to: &cars)
        XCTAssertFalse(cars.isEmpty)
        XCTAssertTrue(cars.vertices.allSatisfy { $0.color >> 24 == Map3DXRay.carOpacity })
    }

    /// A tunnel deeper than ``Map3DXRay/deepest`` (a mountain's) does not
    /// show; one under 30 m of a city does.
    func testOnlyShallowTunnelsShow() {
        func piece(cover: Float, tunnel: Bool = true) -> Map3DTrackCover.Piece {
            Map3DTrackCover.Piece(a: Map3DPoint(0, -cover, 0), b: Map3DPoint(16, -cover, 0), groundA: 0, groundB: 0,
                                  opensBefore: false, opensAfter: false, isTunnel: tunnel)
        }
        XCTAssertTrue(Map3DXRay.shows(piece(cover: 4)))
        XCTAssertTrue(Map3DXRay.shows(piece(cover: 30)))
        XCTAssertFalse(Map3DXRay.shows(piece(cover: 31)))
        XCTAssertFalse(Map3DXRay.shows(piece(cover: 4, tunnel: false)), "track in the open is drawn as it is")
    }

    /// An underground platform: a slab beside its track in the tunnel,
    /// along the platform's length (the place decision 670's parts go).
    func testAnUndergroundPlatformIsLaidBesideItsTrack() throws {
        let (world, _) = try tunnelWorld(platform: true)
        let scene = Map3DScene(world: world)
        let platforms = Map3DXRay.platforms(world.railwaySnapshot(), in: scene)
        let platform = try XCTUnwrap(platforms.first)
        XCTAssertEqual(platforms.count, 1)
        XCTAssertEqual(platform.width, Map3DScene.Builder.platformWidth)
        let startX = scene.point(worldX: 30_720 + 40 * 64, worldY: 16_384, height: 0).x
        let endX = scene.point(worldX: 30_720 + 260 * 64, worldY: 16_384, height: 0).x
        XCTAssertEqual(platform.line.map(\.x).min() ?? 0, startX, accuracy: 1)
        XCTAssertEqual(platform.line.map(\.x).max() ?? 0, endX, accuracy: 1)
        var mesh = Map3DMesh()
        Map3DXRay.addPlatform(platform, to: &mesh)
        let rails = platform.line[0].y
        XCTAssertTrue(mesh.vertices.allSatisfy { $0.y <= rails + Map3DScene.Builder.platformHeight + 0.05 })
        let without = Map3DXRay(scene: Map3DScene(world: try tunnelWorld().world), snapshot: try tunnelWorld().world.railwaySnapshot())
        let with = Map3DXRay(scene: scene, snapshot: world.railwaySnapshot())
        XCTAssertGreaterThan(with.mesh.vertices.count, without.mesh.vertices.count)
    }

    // MARK: Headlamps

    /// Following a train in a tunnel, its lamps light the track ahead: a
    /// glowing band ahead of its nose; no other train's, and none in the
    /// open.
    func testTheFollowedTrainsLampsLightTheTrackAhead() throws {
        let (world, train) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let plain = frame(world, scene: scene)
        let lit = frame(world, scene: scene, headlamp: train)
        let added = Array(lit.boxes.vertices.dropFirst(plain.boxes.vertices.count))
        XCTAssertFalse(added.isEmpty, "the light is drawn")
        XCTAssertTrue(added.allSatisfy { $0.layer == Map3DVertex.glowing })
        let head = try XCTUnwrap(lit.heads.first { $0.train == train })
        let ahead = added.map { ($0.position - head.nose).dot(head.forward) }
        XCTAssertGreaterThan(ahead.max() ?? 0, Map3DHeadlamp.reach - 2)
        XCTAssertGreaterThan(ahead.min() ?? -1, -0.5, "ahead of the nose")
        for vertex in added { XCTAssertLessThan(vertex.y, head.rail.y, "on the bed, under the rails") }
        XCTAssertEqual(frame(world, scene: scene, headlamp: TrainID(rawValue: 99)).boxes.vertices.count, plain.boxes.vertices.count)
    }

    /// The path runs on along the track and then straight on, every 4 m.
    func testTheLampsPathGoesStraightOnPastTheTrack() {
        let path = Map3DHeadlamp.path(nose: Map3DPoint(0, 0, 0), forward: Map3DPoint(1, 0, 0), ahead: [Map3DPoint(10, 0, 0)],
                                      cover: Map3DTrackCover())
        XCTAssertEqual(path.count, Int(Map3DHeadlamp.reach / Map3DHeadlamp.step) + 1)
        XCTAssertEqual(path.last?.x ?? 0, Map3DHeadlamp.reach, accuracy: 0.01)
        XCTAssertTrue(path.allSatisfy { abs($0.z) < 0.01 && $0.y == 0 })
    }

    // MARK: Portals

    /// The owner's report: the ground ran through a shallow bore by its
    /// portal, a plane across the tunnel from the cab. Now no ground lies
    /// in the bore anywhere along it.
    func testNoGroundLiesInAShallowBore() throws {
        let (world, _) = try tunnelWorld()
        let scene = Map3DScene(world: world)
        let meshes = scene.chunks.map(\.mesh)
        let lineZ = scene.point(worldX: 0, worldY: 16_384, height: 0).z
        let portalX = scene.point(worldX: 12_288, worldY: 16_384, height: 0).x
        var inside: [(Float, Float)] = []
        for metre in stride(from: Float(2), through: 280, by: 6) {
            let x = portalX + metre
            let rail = try XCTUnwrap(scene.trackCover.railHeight(near: Map3DPoint(x, 0, lineZ), rise: 6))
            let floor = rail - Map3DScene.Builder.bedDrop, crown = rail + Map3DScene.Builder.boreCrown
            for across: Float in [-1.5, 0, 1.5] {
                for height in Map3DTrenchTests.heights(over: x, lineZ + across, in: meshes, colours: Map3DTrenchTests.groundColours)
                where height > floor + 0.05 && height < crown - 0.05 {
                    inside.append((metre, height))
                }
            }
        }
        XCTAssertTrue(inside.isEmpty, "ground in the bore at (metres in, height) \(inside.prefix(6))")
    }

    /// Decision 672, review L13-7: the same portal ends make the same
    /// portals whatever order they come in.
    func testThePortalsAreTheSameWhateverTheEndsOrder() {
        typealias Builder = Map3DScene.Builder
        let ends = [
            Builder.PortalEnd(point: Map3DPoint(0, 0, 0), into: Map3DPoint(1, 0, 0)),
            Builder.PortalEnd(point: Map3DPoint(1, 0, 4.5), into: Map3DPoint(1, 0, 0)),
            Builder.PortalEnd(point: Map3DPoint(2, 0, 9), into: Map3DPoint(1, 0, 0)),
            Builder.PortalEnd(point: Map3DPoint(0, 0, 14), into: Map3DPoint(1, 0, 0)),
            Builder.PortalEnd(point: Map3DPoint(300, 0, 0), into: Map3DPoint(-1, 0, 0)),
        ]
        func described(_ portals: [Builder.Portal]) -> [String] {
            portals.map { "\($0.point.x),\($0.point.y),\($0.point.z),\($0.into.x),\($0.into.z),\($0.halfWidth)" }.sorted()
        }
        let expected = described(Builder.portals(ends))
        XCTAssertEqual(expected.count, 3, "the ends side by side share portals, as far as each fits all its members")
        for order in [[4, 3, 2, 1, 0], [2, 0, 4, 3, 1], [3, 1, 0, 2, 4], [1, 3, 4, 0, 2]] {
            XCTAssertEqual(described(Builder.portals(order.map { ends[$0] })), expected, "order \(order)")
        }
    }
}
