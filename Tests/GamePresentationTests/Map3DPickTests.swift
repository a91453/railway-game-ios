@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 517 續: a tap on the 3D map turned into a ray, walked to the
/// ground, and a track node near the finger taken first.
final class Map3DPickTests: XCTestCase {
    private static let flat: Map3DPick.Ground = { _, _ in 0 }

    /// Cameras from the far, flat view to the closest, most tilted one,
    /// turned every way, a follow view's set tilt among them.
    private func cameras() -> [Map3DCamera] {
        var cameras: [Map3DCamera] = []
        for distance: Float in [60, 120, 200, 450, 1_200, 12_000] {
            for heading: Float in [0, 0.7, 2.4, -1.9] {
                cameras.append(Map3DCamera(target: Map3DPoint(130, 0, -250), distance: distance, heading: heading, viewport: (844, 390)))
            }
        }
        var follow = Map3DCamera(target: Map3DPoint(-40, 0, 75), distance: 300, heading: 1, viewport: (390, 844))
        follow.pitch = 1.1
        cameras.append(follow)
        return cameras
    }

    func testTheMiddleOfTheViewLandsOnWhatTheCameraLooksAt() throws {
        for camera in cameras() {
            let hit = try XCTUnwrap(Map3DPick.ground(along: camera.ray(throughX: camera.viewport.width / 2, y: camera.viewport.height / 2),
                                                     ground: Self.flat, within: camera.depthRange.far))
            XCTAssertEqual(hit.x, camera.target.x, accuracy: 0.01 * camera.distance / 100, "\(camera)")
            XCTAssertEqual(hit.z, camera.target.z, accuracy: 0.01 * camera.distance / 100, "\(camera)")
        }
    }

    func testThePointHitIsDrawnUnderTheFinger() throws {
        // On a hillside, so the walk and its halving are what find it.
        let hill: Map3DPick.Ground = { x, z in 2 + 0.03 * x - 0.02 * z }
        for camera in cameras() {
            let (width, height) = camera.viewport
            for (sx, sy) in [(0.1, 0.9), (0.5, 0.2), (0.85, 0.6), (0.02, 0.02), (0.98, 0.5)] as [(Float, Float)] {
                let x = sx * width, y = sy * height
                guard let hit = Map3DPick.ground(along: camera.ray(throughX: x, y: y), ground: hill, within: camera.depthRange.far) else {
                    XCTFail("no ground at (\(x), \(y)) from \(camera)")
                    continue
                }
                XCTAssertEqual(hit.y, hill(hit.x, hit.z), accuracy: 0.05, "on the ground")
                let back = try XCTUnwrap(camera.screenPoint(of: hit))
                XCTAssertEqual(back.x, x, accuracy: 0.05, "\(camera)")
                XCTAssertEqual(back.y, y, accuracy: 0.05, "\(camera)")
            }
        }
    }

    func testAHillInFrontHidesTheGroundBehindIt() throws {
        // A ridge 80 m high, 20 m wide, across the view 100 m in front of
        // the target: a ray through the target's ground point first meets
        // the ridge.
        let camera = Map3DCamera(target: Map3DPoint(0, 0, 0), distance: 150, heading: 0, viewport: (844, 390))
        let ridge: Map3DPick.Ground = { _, z in abs(z - 60) < 10 ? 80 : 0 }
        let middle = camera.ray(throughX: 422, y: 195)
        let hit = try XCTUnwrap(Map3DPick.ground(along: middle, ground: ridge, within: camera.depthRange.far))
        XCTAssertEqual(hit.y, 80, accuracy: 0.01, "on the ridge’s top")
        XCTAssertGreaterThan(hit.z, 55)
        // Nothing hides the ground beside the ridge's top.
        XCTAssertEqual(try XCTUnwrap(Map3DPick.ground(along: middle, ground: Self.flat, within: camera.depthRange.far)).y, 0, accuracy: 0.01)
    }

    func testARayAboveTheHorizonLandsNowhere() {
        var camera = Map3DCamera(target: .zero, distance: 200, heading: 0, viewport: (844, 390))
        camera.pitch = 85 * .pi / 180
        XCTAssertNil(Map3DPick.ground(along: camera.ray(throughX: 422, y: 2), ground: Self.flat, within: camera.depthRange.far))
        // Below the horizon it still lands, on the sea past the ground's end.
        XCTAssertNotNil(Map3DPick.ground(along: camera.ray(throughX: 422, y: 388), ground: Self.flat, within: camera.depthRange.far))
    }

    // MARK: - Nodes and cells

    private static let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
    private static let world = try! newGameLine(through: [towns[0], towns[1]])

    /// A camera 200 m from `node`'s rails, and the space with the scene's
    /// origin away from the world's.
    private func view(of node: TrackNode) -> (camera: Map3DCamera, space: Map3DPick.Space) {
        let space = Map3DPick.Space(originX: Double(node.position.x) - 3_000, originY: Double(node.position.y) + 1_700)
        let at = space.point(node.position) + Map3DPoint(0, Map3DScene.railLift, 0)
        return (Map3DCamera(target: at, distance: 200, heading: 0.4, viewport: (844, 390)), space)
    }

    func testATapNearANodePicksIt() throws {
        let world = Self.world
        let node = try XCTUnwrap(world.network.nodes.first)
        let (camera, space) = view(of: node)
        let ground = Map3DPick.ground(of: world, in: space)
        let seen = try XCTUnwrap(camera.screenPoint(of: space.point(node.position) + Map3DPoint(0, Map3DScene.railLift, 0)))
        XCTAssertEqual(seen.x, 422, accuracy: 0.01)
        let near = try XCTUnwrap(Map3DPick.pick(atX: seen.x + 15, y: seen.y - 12, camera: camera, space: space, bounds: world.bounds,
                                                nodes: world.network.nodes, ground: ground))
        XCTAssertEqual(near.target, .node(node.id), "19 points away is within reach")
        XCTAssertEqual(near.plan, node.position.plan)
        let off = try XCTUnwrap(Map3DPick.pick(atX: seen.x + 30, y: seen.y, camera: camera, space: space, bounds: world.bounds,
                                               nodes: world.network.nodes, ground: ground))
        XCTAssertEqual(off.target, .ground, "30 points away is not")
        XCTAssertEqual(off.point.y, ground(off.point.x, off.point.z), accuracy: 0.05)
    }

    func testANodeIsFoundWhereItsRailsAreDrawnNotTheGroundUnderIt() throws {
        // A node 30 m up (a viaduct's): where it is seen, not where the
        // ground under it is.
        let id = TrackNodeID.node(7)
        let raised = TrackNode(id: id, position: WorldCoordinate(x: 600_000, y: 400_000, z: 30 * WorldCoordinate.unitsPerMetre))
        let space = Map3DPick.Space(originX: 590_000, originY: 395_000)
        let camera = Map3DCamera(target: Map3DPoint(150, 0, 80), distance: 200, heading: 0, viewport: (844, 390))
        let bounds = try WorldBounds(width: 1_000_000, height: 1_000_000)
        let drawn = try XCTUnwrap(camera.screenPoint(of: space.point(raised.position) + Map3DPoint(0, Map3DScene.railLift, 0)))
        let foot = try XCTUnwrap(camera.screenPoint(of: Map3DPoint(space.point(raised.position).x, 0, space.point(raised.position).z)))
        XCTAssertGreaterThan(abs(drawn.y - foot.y), 2 * Float(NetworkBuilding.touchRadius), "30 m up is well apart on the screen")
        let atRails = Map3DPick.pick(atX: drawn.x, y: drawn.y, camera: camera, space: space, bounds: bounds, nodes: [raised], ground: Self.flat)
        XCTAssertEqual(atRails?.target, .node(id))
        let atFoot = Map3DPick.pick(atX: foot.x, y: foot.y, camera: camera, space: space, bounds: bounds, nodes: [raised], ground: Self.flat)
        XCTAssertEqual(atFoot?.target, .ground)
    }

    func testOfTwoNodesTheNearerOnTheScreenWins() throws {
        let space = Map3DPick.Space(originX: 0, originY: 0)
        let camera = Map3DCamera(target: Map3DPoint(1_000, 0, 1_000), distance: 200, heading: 0, viewport: (844, 390))
        let bounds = try WorldBounds(width: 1_000_000, height: 1_000_000)
        let metre = WorldCoordinate.unitsPerMetre
        let a = TrackNode(id: TrackNodeID.node(2), position: WorldCoordinate(x: 1_000 * metre, y: 1_000 * metre, z: 0))
        let b = TrackNode(id: TrackNodeID.node(1), position: WorldCoordinate(x: 1_003 * metre, y: 1_000 * metre, z: 0))
        let pa = try XCTUnwrap(camera.screenPoint(of: space.point(a.position) + Map3DPoint(0, Map3DScene.railLift, 0)))
        let pb = try XCTUnwrap(camera.screenPoint(of: space.point(b.position) + Map3DPoint(0, Map3DScene.railLift, 0)))
        XCTAssertEqual(Map3DPick.pick(atX: pa.x - 1, y: pa.y, camera: camera, space: space, bounds: bounds, nodes: [a, b], ground: Self.flat)?.target,
                       .node(a.id))
        XCTAssertEqual(Map3DPick.pick(atX: pb.x + 1, y: pb.y, camera: camera, space: space, bounds: bounds, nodes: [a, b], ground: Self.flat)?.target,
                       .node(b.id))
        // Halfway, as near to both: the lower number.
        XCTAssertEqual(Map3DPick.pick(atX: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2, camera: camera, space: space, bounds: bounds,
                                      nodes: [a, b], ground: Self.flat)?.target, .node(b.id))
    }

    func testTheGroundHitHasItsCellAndNothingOutsideTheMapIsHit() throws {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let space = Map3DPick.Space(originX: 0, originY: 0)
        let bounds = try WorldBounds(width: 64 * 4_096, height: 64 * 4_096)
        // Looking at the middle of cell row 3, column 5.
        let target = Map3DPoint(Float((5.5 * 4_096) / metre), 0, Float((3.5 * 4_096) / metre))
        let camera = Map3DCamera(target: target, distance: 150, heading: 1.2, viewport: (844, 390))
        let hit = try XCTUnwrap(Map3DPick.pick(atX: 422, y: 195, camera: camera, space: space, bounds: bounds, nodes: [], ground: Self.flat))
        XCTAssertEqual(hit.target, .ground)
        XCTAssertEqual(hit.row, 3)
        XCTAssertEqual(hit.column, 5)
        XCTAssertEqual(hit.plan, LandCell(row: 3, column: 5, use: .park, residents: 0, jobs: 0).middle)
        // The map's north-west corner seen from inside: past it is off the map.
        let corner = Map3DCamera(target: Map3DPoint(0, 0, 0), distance: 150, heading: 0, viewport: (844, 390))
        XCTAssertNil(Map3DPick.pick(atX: 422, y: 100, camera: corner, space: space, bounds: bounds, nodes: [], ground: Self.flat), "north of the map")
        XCTAssertNotNil(Map3DPick.pick(atX: 600, y: 300, camera: corner, space: space, bounds: bounds, nodes: [], ground: Self.flat), "inside")
    }

    func testTheWorldsOwnGroundIsWhereTheWorldSaysAndSeaOutside() throws {
        let world = Self.world
        let node = try XCTUnwrap(world.network.nodes.first)
        let space = Map3DPick.Space(originX: 0, originY: 0)
        let ground = Map3DPick.ground(of: world, in: space)
        let at = space.point(node.position)
        let expected = Float(Double(try XCTUnwrap(world.groundHeight(at: node.position.plan))) / Double(WorldCoordinate.unitsPerMetre))
        XCTAssertEqual(ground(at.x, at.z), expected, accuracy: 0.02)
        XCTAssertEqual(ground(-500, -500), 0, "off the map is the sea")
    }
}
