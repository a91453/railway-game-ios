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

    // MARK: - What the ground hides (PR 3)

    /// A node at (600,000, 400,000) on flat ground, the scene's origin
    /// off it, and a camera 150 m from its rails, looking at it from the
    /// south (+z).
    private static let lone = TrackNode(id: TrackNodeID.node(7), position: WorldCoordinate(x: 600_000, y: 400_000, z: 0))
    private static let loneSpace = Map3DPick.Space(originX: 590_000, originY: 395_000)
    private static let bigBounds = try! WorldBounds(width: 1_000_000, height: 1_000_000)

    private func loneCamera() -> (camera: Map3DCamera, at: Map3DPoint) {
        let at = Self.loneSpace.point(Self.lone.position) + Map3DPoint(0, Map3DScene.railLift, 0)
        return (Map3DCamera(target: at, distance: 150, heading: 0, viewport: (844, 390)), at)
    }

    func testANodeBehindAHillIsNotPicked() throws {
        let (camera, at) = loneCamera()
        // An 80 m ridge across the view, 60 m in front of the node.
        let ridge: Map3DPick.Ground = { _, z in abs(z - (at.z + 60)) < 10 ? 80 : 0 }
        XCTAssertFalse(Map3DPick.isSeen(at, from: camera.eye, ground: ridge))
        XCTAssertTrue(Map3DPick.isSeen(at, from: camera.eye, ground: Self.flat))
        let seen = try XCTUnwrap(camera.screenPoint(of: at))
        let open = Map3DPick.pick(atX: seen.x, y: seen.y, camera: camera, space: Self.loneSpace, bounds: Self.bigBounds,
                                  nodes: [Self.lone], ground: Self.flat)
        XCTAssertEqual(open?.target, .node(Self.lone.id))
        let hidden = try XCTUnwrap(Map3DPick.pick(atX: seen.x, y: seen.y, camera: camera, space: Self.loneSpace, bounds: Self.bigBounds,
                                                  nodes: [Self.lone], ground: ridge))
        XCTAssertEqual(hidden.target, .ground, "the ridge is what the finger is on")
        XCTAssertEqual(hidden.point.y, 80, accuracy: 0.05)
    }

    func testOfTwoNodesTheSeenOneWinsThoughFartherOnTheScreen() throws {
        let (camera, at) = loneCamera()
        let metre = WorldCoordinate.unitsPerMetre
        // A second node 6 m east, behind an 80 m wall 60 m in front of it
        // that stops half a metre east of the first; the hidden one has
        // the lower number and is nearer the finger.
        let hiddenNode = TrackNode(id: TrackNodeID.node(1), position: WorldCoordinate(x: 600_000 + 6 * metre, y: 400_000, z: 0))
        let ground: Map3DPick.Ground = { x, z in x > at.x + 0.5 && abs(z - (at.z + 60)) < 10 ? 80 : 0 }
        let drawn = try XCTUnwrap(camera.screenPoint(of: Self.loneSpace.point(hiddenNode.position) + Map3DPoint(0, Map3DScene.railLift, 0)))
        XCTAssertFalse(Map3DPick.isSeen(Self.loneSpace.point(hiddenNode.position) + Map3DPoint(0, Map3DScene.railLift, 0), from: camera.eye,
                                        ground: ground))
        // A finger a little nearer the hidden one, both within reach.
        let first = try XCTUnwrap(camera.screenPoint(of: at))
        let x = first.x + (drawn.x - first.x) * 0.6, y = first.y + (drawn.y - first.y) * 0.6
        XCTAssertLessThan(((x - first.x) * (x - first.x) + (y - first.y) * (y - first.y)).squareRoot(), Float(NetworkBuilding.touchRadius))
        XCTAssertEqual(Map3DPick.pick(atX: x, y: y, camera: camera, space: Self.loneSpace, bounds: Self.bigBounds,
                                      nodes: [hiddenNode, Self.lone], ground: Self.flat)?.target, .node(hiddenNode.id), "unhidden, the nearer")
        let hit = Map3DPick.pick(atX: x, y: y, camera: camera, space: Self.loneSpace, bounds: Self.bigBounds,
                                 nodes: [hiddenNode, Self.lone], ground: ground)
        XCTAssertEqual(hit?.target, .node(Self.lone.id))
    }

    func testANodeDeepInATunnelIsNotSeenButOneAtItsMouthIs() {
        let (camera, at) = loneCamera()
        XCTAssertFalse(Map3DPick.isSeen(at - Map3DPoint(0, 30, 0), from: camera.eye, ground: Self.flat), "30 m under the ground")
        // A cutting's track some metres under the ground's grid, on the
        // way down to a tunnel's mouth, is still seen.
        XCTAssertTrue(Map3DPick.isSeen(at - Map3DPoint(0, 3, 0), from: camera.eye, ground: Self.flat))
    }

    // MARK: - Edges (PR 3)

    private func edgeView() throws -> (camera: Map3DCamera, space: Map3DPick.Space, edge: TrackEdgeID, along: Int64, at: Map3DPoint,
                                       edges: [(id: TrackEdgeID, geometry: TrackGeometry)], ahead: Map3DPoint) {
        let world = Self.world
        let edges = world.network.edges.compactMap { edge in world.trackGeometry(of: edge.id).map { (id: edge.id, geometry: $0) } }
        let longest = try XCTUnwrap(edges.max { $0.geometry.length < $1.geometry.length })
        XCTAssertGreaterThan(longest.geometry.length, 400 * WorldCoordinate.unitsPerMetre)
        // Its middle, between two of its samples.
        let geometry = longest.geometry
        let along = geometry.length / 2
        let index = try XCTUnwrap(geometry.distances.lastIndex { $0 <= along })
        let next = min(index + 1, geometry.points.count - 1)
        let share = next == index ? 0 : Double(along - geometry.distances[index]) / Double(geometry.distances[next] - geometry.distances[index])
        let a = geometry.points[index], b = geometry.points[next]
        let middle = WorldCoordinate(x: a.x + Int64((Double(b.x - a.x) * share).rounded()), y: a.y + Int64((Double(b.y - a.y) * share).rounded()),
                                     z: a.z + Int64((Double(b.z - a.z) * share).rounded()))
        let space = Map3DPick.Space(originX: Double(middle.x) - 2_500, originY: Double(middle.y) + 1_100)
        let at = space.point(middle) + Map3DPoint(0, Map3DScene.railLift, 0)
        let way = try XCTUnwrap((space.point(geometry.points[max(index, 1)]) - space.point(geometry.points[max(index, 1) - 1])).normalized)
        return (Map3DCamera(target: at, distance: 200, heading: 0.4, viewport: (844, 390)), space, longest.id, along, at, edges, at + way * 10)
    }

    func testATapNearTrackBetweenNodesPicksThePlaceOnTheEdge() throws {
        let world = Self.world
        let (camera, space, edge, along, at, edges, ahead) = try edgeView()
        let seen = try XCTUnwrap(camera.screenPoint(of: at))
        // Square to the track on the screen.
        let next = try XCTUnwrap(camera.screenPoint(of: ahead))
        let run = ((next.x - seen.x) * (next.x - seen.x) + (next.y - seen.y) * (next.y - seen.y)).squareRoot()
        let square = (x: -(next.y - seen.y) / run, y: (next.x - seen.x) / run)
        let ground: Map3DPick.Ground = { _, _ in at.y - Map3DScene.railLift }
        let hit = try XCTUnwrap(Map3DPick.pick(atX: seen.x + 6, y: seen.y - 8, camera: camera, space: space, bounds: world.bounds,
                                               nodes: world.network.nodes, edges: edges, ground: ground))
        guard case .edge(let point) = hit.target else { return XCTFail("\(hit.target)") }
        XCTAssertEqual(point.edge, edge)
        // 10 points from the middle, 200 m off: a few metres along.
        XCTAssertEqual(Double(point.distance), Double(along), accuracy: 12 * Double(WorldCoordinate.unitsPerMetre))
        // The point is on the track, where its rails are drawn.
        XCTAssertEqual(hit.point.y, at.y, accuracy: 1)
        // 30 points off it, the ground.
        let off = Map3DPick.pick(atX: seen.x + 30 * square.x, y: seen.y + 30 * square.y, camera: camera, space: space, bounds: world.bounds,
                                 nodes: world.network.nodes, edges: edges, ground: ground)
        XCTAssertEqual(off?.target, .ground)
        // Without the edges given, the ground too: nodes alone, as before.
        XCTAssertEqual(Map3DPick.pick(atX: seen.x + 6, y: seen.y - 8, camera: camera, space: space, bounds: world.bounds,
                                      nodes: world.network.nodes, ground: ground)?.target, .ground)
    }

    func testANodeWithinReachWinsOverTheTrack() throws {
        let world = Self.world
        let node = try XCTUnwrap(world.network.nodes.first)
        let (camera, space) = view(of: node)
        let edges = world.network.edges.compactMap { edge in world.trackGeometry(of: edge.id).map { (id: edge.id, geometry: $0) } }
        let seen = try XCTUnwrap(camera.screenPoint(of: space.point(node.position) + Map3DPoint(0, Map3DScene.railLift, 0)))
        // 15 points off the node: its own edge leaves it, nearer still.
        let hit = Map3DPick.pick(atX: seen.x + 15, y: seen.y - 12, camera: camera, space: space, bounds: world.bounds,
                                 nodes: world.network.nodes, edges: edges, ground: Map3DPick.ground(of: world, in: space))
        XCTAssertEqual(hit?.target, .node(node.id))
    }

    func testTrackBehindAHillIsNotPicked() throws {
        let world = Self.world
        let (camera, space, _, _, at, edges, _) = try edgeView()
        let seen = try XCTUnwrap(camera.screenPoint(of: at))
        let base = at.y - Map3DScene.railLift
        // A ridge between the eye and the track's middle, square to the
        // way the camera looks.
        let look = (camera.target - camera.eye).normalized!
        let ridge: Map3DPick.Ground = { x, z in
            let along = (Map3DPoint(x, at.y, z) - at).dot(Map3DPoint(look.x, 0, look.z).normalized!)
            return abs(along + 70) < 12 ? base + 120 : base
        }
        let hit = try XCTUnwrap(Map3DPick.pick(atX: seen.x, y: seen.y, camera: camera, space: space, bounds: world.bounds,
                                               nodes: world.network.nodes, edges: edges, ground: ridge))
        XCTAssertEqual(hit.target, .ground)
        XCTAssertGreaterThan(hit.point.y, base + 100, "on the ridge")
    }

    // MARK: - The scene's own ground (PR 3)

    func testTheGridIsTheDrawnSquaresSplitAsTheScenesQuads() throws {
        let world = Self.world
        let cell = Double(Land.cellLength), metre = Double(WorldCoordinate.unitsPerMetre)
        // Corners 0, 10 / 20, 30 m round the square of row 10, column 20.
        let grid = Map3DGroundGrid(originX: 0, originY: 0, firstRow: 10, firstColumn: 20, rows: 2, columns: 2, heights: [0, 30, 10, 20], file: nil)
        func scene(_ column: Double, _ row: Double) -> (Float, Float) { (Float(column * cell / metre), Float(row * cell / metre)) }
        let (x0, z0) = scene(20, 10)
        XCTAssertEqual(grid.height(x: x0, z: z0, world: world), 0, accuracy: 0.001)
        let (x1, z1) = scene(20.999, 10.999)
        XCTAssertEqual(grid.height(x: x1, z: z1, world: world), 20, accuracy: 0.05)
        // The middle is on the north-west to south-east diagonal: half of
        // a (0) and c (20), not of b (10) and d (30).
        let (xm, zm) = scene(20.5, 10.5)
        XCTAssertEqual(grid.height(x: xm, z: zm, world: world), 10, accuracy: 0.001)
        // Below the diagonal (fx > fy) the triangle a c d.
        let (xd, zd) = scene(20.75, 10.25)
        XCTAssertEqual(grid.height(x: xd, z: zd, world: world), 0 + 0.75 * 30 + 0.25 * (20 - 30), accuracy: 0.001)
        XCTAssertEqual(grid.corner(row: 11, column: 21), 20)
        XCTAssertNil(grid.corner(row: 12, column: 21))
    }

    func testTheScenesGroundIsTheGroundItLaysAndTheWorldsPastIt() throws {
        let world = Self.world
        let node = try XCTUnwrap(world.network.nodes.first)
        let cell = Double(Land.cellLength)
        let x = (Double(node.position.x) / cell).rounded(.down) * cell, y = (Double(node.position.y) / cell).rounded(.down) * cell
        let region = WorldRegion(minX: x - 4 * cell, minY: y - 4 * cell, maxX: x + 4 * cell, maxY: y + 4 * cell)
        let scene = Map3DScene(world: world, snapshot: nil, skyline: nil, frame: (region, x, y), baseMap: nil, cityTiles: [], heights: nil,
                               lineBands: nil, railways: nil, temples: nil)
        let grid = scene.drawnGround
        XCTAssertEqual(grid.rows, 9)
        XCTAssertEqual(grid.columns, 9)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let ground = Map3DPick.ground(of: scene, world: world)
        let worldGround = Map3DPick.ground(of: world, in: Map3DPick.Space(scene: scene))
        let column = Int(x / cell), row = Int(y / cell)
        for (r, c) in [(row, column), (row - 4, column - 4), (row + 4, column + 4), (row + 2, column - 3)] {
            let plan = PlanPoint(x: Int64(Double(c) * cell), y: Int64(Double(r) * cell))
            let expected = Float(Double(world.groundHeight(at: plan) ?? 0) / metre)
            XCTAssertEqual(grid.corner(row: r, column: c), expected, "corner (\(r), \(c))")
            let at = Map3DPick.Space(scene: scene).point(WorldCoordinate(x: plan.x, y: plan.y))
            XCTAssertEqual(ground(at.x, at.z), expected, accuracy: 0.001)
        }
        // Past the scene, the world's own corners.
        let far = Map3DPick.Space(scene: scene).point(WorldCoordinate(x: Int64(x + 20 * cell), y: Int64(y - 15 * cell)))
        XCTAssertEqual(ground(far.x, far.z), worldGround(far.x, far.z), accuracy: 0.001)
    }
}
