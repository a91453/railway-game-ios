import GameCore
@testable import GamePresentation
import XCTest

/// Decision 394: the cab view deep in a tunnel leaves out what is on the
/// ground, and draws it all again before an opening can be seen.
final class Map3DUndergroundTests: XCTestCase {
    /// A flat world: surface track from x = 32 m to the portal at 192 m,
    /// then a tunnel falling 4 m to x = 480 m and on, level, to 960 m,
    /// where it ends underground. A train's front at `at` (by default
    /// 320 m into the level tunnel, 608 m from the portal), running east.
    private func tunnelWorld(at: TrainPosition = .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 20_480))
        throws -> (scene: Map3DScene, head: Map3DTrains.Head) {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 16_384))
        let down = try world.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 16_384, z: -256))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 16_384, z: -256))
        try world.buildTrackEdge(from: a, to: portal)
        try world.buildTrackEdge(from: portal, to: down, structure: .tunnel)
        try world.buildTrackEdge(from: down, to: end, structure: .tunnel)
        let train = try world.purchaseTrain(named: "Mole").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: at)
        let scene = Map3DScene(world: world)
        let frame = Map3DTrains.frame(TrainMotion(world: world, time: 0), progress: 1, heights: Map3DTrains.Heights(world: world), in: scene,
                                      models: nil, eye: nil)
        return (scene, try XCTUnwrap(frame.heads.first { $0.train == train }))
    }

    /// The cab camera at `head`, as the Metal view moves it.
    private func cab(_ head: Map3DTrains.Head) -> Map3DCamera {
        Map3DFollow(train: head.train, view: .cab).camera(following: head, from: Map3DCamera(viewport: (390, 844)), elapsed: 0, turnsAtOnce: true)
    }

    private func answer(_ view: Map3DFollow.View?, _ head: Map3DTrains.Head, scene: Map3DScene, flying: Bool = false,
                        from start: Map3DUnderground = Map3DUnderground()) -> Bool {
        var underground = start
        let camera = view == .cab ? cab(head) : Map3DFollow(train: head.train, view: view ?? .back)
            .camera(following: head, from: Map3DCamera(viewport: (390, 844)), elapsed: 0, turnsAtOnce: true)
        underground.update(view: view, head: head, flying: flying, camera: camera, openings: scene.trackCover.openings)
        return underground.isUnderground
    }

    /// The tunnel opens once, at its portal; its end underground is no
    /// opening.
    func testTheTunnelOpensAtItsPortal() throws {
        let (scene, _) = try tunnelWorld()
        let openings = scene.trackCover.openings
        XCTAssertEqual(openings.count, 1)
        let portal = scene.point(worldX: 12_288, worldY: 16_384, height: 0)
        XCTAssertEqual(try XCTUnwrap(openings.first).x, portal.x, accuracy: 0.5)
    }

    /// Deep in the bore, the portal 608 m behind: only what is under the
    /// ground is drawn.
    func testDeepInTheBoreOnlyTheUndergroundIsDrawn() throws {
        let (scene, head) = try tunnelWorld()
        XCTAssertTrue(head.inTunnel)
        XCTAssertGreaterThan(head.forward.x, 0.9, "running east, away from the portal")
        XCTAssertTrue(answer(.cab, head, scene: scene))
    }

    /// Facing the portal down the straight bore, 608 m off: it is seen, so
    /// everything is drawn.
    func testAnOpeningInViewDrawsEverything() throws {
        let (scene, east) = try tunnelWorld()
        let west = Map3DTrains.Head(train: east.train, point: east.point, forward: east.forward * -1, nose: east.nose, ground: east.ground,
                                    inTunnel: east.inTunnel)
        XCTAssertFalse(answer(.cab, west, scene: scene))
        XCTAssertFalse(answer(.cab, west, scene: scene, from: underground(at: 1_000)), "already underground, it comes back")
    }

    /// 100 m into the tunnel, running away from the portal: near enough
    /// to it that everything is drawn.
    func testNearAnOpeningEverythingIsDrawn() throws {
        // On the falling edge, 100 m past the portal.
        let (scene, head) = try tunnelWorld(at: .onEdge(TrackTraversal(edge: .edge(2), direction: .forward), offset: 6_400))
        XCTAssertTrue(head.inTunnel)
        XCTAssertFalse(answer(.cab, head, scene: scene))
    }

    /// From behind or above, or flying into the cab, the camera is over
    /// the ground: everything is drawn.
    func testOtherViewsDrawEverything() throws {
        let (scene, head) = try tunnelWorld()
        XCTAssertFalse(answer(.back, head, scene: scene))
        XCTAssertFalse(answer(.aboveBack, head, scene: scene))
        XCTAssertFalse(answer(nil, head, scene: scene))
        XCTAssertFalse(answer(.cab, head, scene: scene, flying: true))
        XCTAssertFalse(answer(.back, head, scene: scene, from: underground(at: 1_000)), "out of the cab, at once")
    }

    /// On the surface the cab draws everything.
    func testOnTheSurfaceTheCabDrawsEverything() throws {
        let (scene, head) = try tunnelWorld(at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 6_400))
        XCTAssertFalse(head.inTunnel)
        XCTAssertFalse(answer(.cab, head, scene: scene))
    }

    // MARK: The edge

    /// A head in a tunnel at the scene's origin running east, and an
    /// opening `behind` metres behind its eye.
    private func behind(_ metres: Float) -> (head: Map3DTrains.Head, camera: Map3DCamera, openings: [Map3DPoint]) {
        let head = Map3DTrains.Head(train: TrainID(rawValue: 1), point: Map3DPoint(0, 0, 0), forward: Map3DPoint(1, 0, 0),
                                    nose: Map3DPoint(0, -10, 0), ground: 0, inTunnel: true)
        let camera = cab(head)
        return (head, camera, [camera.eye - Map3DPoint(metres, 0, 0)])
    }

    private func underground(at metres: Float) -> Map3DUnderground {
        var underground = Map3DUnderground()
        let (head, camera, openings) = behind(metres)
        underground.update(view: .cab, head: head, flying: false, camera: camera, openings: openings)
        return underground
    }

    /// Between ``Map3DUnderground/near`` and its margin, the answer stays
    /// what it was: frame after frame across the edge, it changes once.
    func testTheEdgeDoesNotFlicker() {
        let near = Map3DUnderground.near, far = near * Map3DUnderground.hideMargin
        XCTAssertTrue(underground(at: far + 10).isUnderground, "well away")
        XCTAssertFalse(underground(at: far - 10).isUnderground, "not yet well away")
        // Running away from the opening, then back toward it, a metre a
        // frame, swaying ±5 m.
        var underground = Map3DUnderground()
        var changes = 0, last = false
        let ways = Array(stride(from: near - 50, through: far + 50, by: 1)) + Array(stride(from: far + 50, through: near - 50, by: -1))
        for (index, metres) in ways.enumerated() {
            let (head, camera, openings) = behind(metres + (index % 2 == 0 ? 5 : -5))
            underground.update(view: .cab, head: head, flying: false, camera: camera, openings: openings)
            if underground.isUnderground != last { changes += 1 }
            last = underground.isUnderground
            if metres < near - 5 { XCTAssertFalse(underground.isUnderground, "at \(metres) m everything is drawn") }
        }
        XCTAssertEqual(changes, 2, "under once going away, back once coming in")
    }
}
