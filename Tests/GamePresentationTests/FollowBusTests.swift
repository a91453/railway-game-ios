import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400 (FOLLOWBUS): the camera following a bus: the bus's ID, the
/// next run when one ends, the follow bar's text, the session's follow and
/// the camera that reads a bus as a ``Map3DFollow/Pose``.
@MainActor
final class FollowBusTests: XCTestCase {
    private func route(_ service: BusService = .every(minutes: 10), buses: Int = 3) -> BusRoute {
        BusRoute(id: BusRouteID(rawValue: 1), station: StationID(rawValue: 1),
                 stops: [CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 14)], legMetres: [900, 900], service: service,
                 buses: buses)
    }

    /// The new game's line, a road along the first station's row and a
    /// route of two stops on it.
    private func world(buses: Int = 2) throws -> (GameWorld, BusRoute) {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(world.stations.first)
        let home = CellPosition(containing: station.location)
        let cells = (0...24).map { CellPosition(row: home.row, column: home.column + $0) }
        try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
        let route = try world.createBusRoute(to: station.id, stops: [cells[24], cells[14]], service: .every(minutes: 10), buses: buses)
        return (world, route)
    }

    // MARK: - Which bus

    func testABusKeepsItsRunWhileItDrives() throws {
        let motion = try XCTUnwrap(BusMotion(route()))
        let early = try XCTUnwrap(motion.buses(at: 8 * 3_600 + 60).first)
        let later = try XCTUnwrap(motion.bus(run: early.run, at: 8 * 3_600 + 200))
        XCTAssertEqual(early.run, later.run)
        XCTAssertGreaterThan(later.elapsed, early.elapsed)
        XCTAssertNil(motion.bus(run: early.run, at: 8 * 3_600 + motion.cycle + 3_600), "an hour after its trip it is not out")
    }

    func testTheNextRunTakesOverWhenATripEnds() throws {
        let motion = try XCTUnwrap(BusMotion(route(.every(minutes: 5), buses: 4)))
        // Just as the bus at run 20 shrinks into its first stop.
        let end = Double(motion.departures[20]) - BusMotion.layover + motion.cycle - 2
        let old = try XCTUnwrap(motion.bus(run: 20, at: end))
        XCTAssertLessThan(old.scale, 1)
        let next = try XCTUnwrap(motion.successor(of: 20, at: end))
        XCTAssertNotEqual(next.run, 20)
        XCTAssertGreaterThanOrEqual(next.scale, 1)
        // The one that left its first stop last, not the one about to end.
        XCTAssertTrue(motion.buses(at: end).filter { $0.run != 20 && $0.scale >= 1 }.allSatisfy { $0.elapsed >= next.elapsed })
    }

    func testNoNextRunWhenNoneIsOut() throws {
        let motion = try XCTUnwrap(BusMotion(route(.runs([480]), buses: 1)))
        let end = 480.0 * 60 - BusMotion.layover + motion.cycle - 2
        XCTAssertNil(motion.successor(of: 0, at: end))
        XCTAssertNil(motion.successor(of: -1, at: 3 * 3_600))
    }

    // MARK: - The bar

    func testTheBarSaysWhereTheBusIsAndWhatComesNext() throws {
        // Two legs: stops 0, 1 and the station 2.
        func text(_ bus: BusMotion.Bus) -> (at: Int?, next: Int?) { GameWorld.busStops(of: bus, legs: 2) }
        func bus(leg: Int, share: Double, outbound: Bool, stopped: Bool) -> BusMotion.Bus {
            BusMotion.Bus(run: 0, elapsed: 0, leg: leg, share: share, outbound: outbound, stopped: stopped, scale: 1)
        }
        XCTAssertEqual(text(bus(leg: 0, share: 0, outbound: true, stopped: true)).at, 0, "waiting at the first stop")
        XCTAssertEqual(text(bus(leg: 0, share: 0, outbound: true, stopped: true)).next, 1)
        XCTAssertEqual(text(bus(leg: 0, share: 0.5, outbound: true, stopped: false)).next, 1, "on the first leg, coming to stop 1")
        XCTAssertNil(text(bus(leg: 0, share: 0.5, outbound: true, stopped: false)).at)
        XCTAssertEqual(text(bus(leg: 0, share: 1, outbound: true, stopped: true)).at, 1, "standing at the middle stop")
        XCTAssertEqual(text(bus(leg: 1, share: 0.5, outbound: true, stopped: false)).next, 2, "to the station")
        XCTAssertEqual(text(bus(leg: 1, share: 1, outbound: true, stopped: true)).next, nil, "at the station, the end of the way out")
        XCTAssertEqual(text(bus(leg: 1, share: 0.5, outbound: false, stopped: false)).next, 1, "back, leg 1 from its far end")
        XCTAssertEqual(text(bus(leg: 0, share: 0.5, outbound: false, stopped: false)).next, 0, "back to the first stop")
        XCTAssertEqual(text(bus(leg: 1, share: 0, outbound: false, stopped: true)).at, 1)
        XCTAssertEqual(text(bus(leg: 1, share: 0, outbound: false, stopped: true)).next, 0)
    }

    // MARK: - The session

    func testFollowingABusAndATrainNeverAtOnce() throws {
        let (world, route) = try world()
        let session = GameSession(world: world, language: .english)
        XCTAssertTrue(session.hasBusToFollow(onRoute: route.id), "an every-ten-minutes route has a bus out at any time")
        session.followBus(onRoute: route.id)
        let id = try XCTUnwrap(session.followedBusID)
        XCTAssertEqual(id.route, route.id)
        XCTAssertNotNil(session.followedBus)
        XCTAssertTrue(session.isFollowingBus)
        XCTAssertTrue(session.isFollowingVehicle)
        XCTAssertTrue(session.isFollowing(id))
        let facts = try XCTUnwrap(session.busFollowBar)
        XCTAssertEqual(facts.routeName, "Feeder bus \(route.id.rawValue)")
        XCTAssertFalse(facts.stopText.isEmpty)
        XCTAssertNil(session.followedTrain)
        session.stopFollowingBus()
        XCTAssertNil(session.followedBusID)
        XCTAssertNil(session.busFollowBar)
        XCTAssertFalse(session.isFollowingVehicle)
    }

    func testFollowingAnUnknownBusDoesNothing() throws {
        let (world, route) = try world()
        let session = GameSession(world: world, language: .english)
        session.followBus(BusID(route: route.id, run: 9_999))
        session.followBus(BusID(route: BusRouteID(rawValue: 77), run: 0))
        XCTAssertNil(session.followedBusID)
    }

    func testLeaving3DLetsGoOfABus() throws {
        let (world, route) = try world()
        let session = GameSession(world: world, language: .english)
        session.setMap3DOpen(true)
        session.followBus(onRoute: route.id)
        XCTAssertTrue(session.isFollowingBus)
        session.setMap3DOpen(false)
        XCTAssertFalse(session.isFollowingBus, "the flat map draws no buses")
    }

    func testTheBarSpeaksChinese() throws {
        let (world, route) = try world()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.followBus(onRoute: route.id)
        let facts = try XCTUnwrap(session.busFollowBar)
        XCTAssertEqual(facts.routeName, "接駁公車 \(route.id.rawValue) 號")
        XCTAssertTrue(facts.stopText.contains("站"), facts.stopText)
    }

    // MARK: - The camera

    private func pose() -> Map3DFollow.Pose {
        Map3DFollow.Pose(forward: Map3DPoint(1, 0, 0), nose: Map3DPoint(106, 5, 100), rail: Map3DPoint(100, 5, 100), middle: Map3DPoint(100, 5, 100),
                         length: 12, eyeHeight: 2, bodyHeight: 3.4)
    }

    func testABusIsFollowedFromEveryViewButTheStation() {
        let start = Map3DCamera(viewport: (390, 844))
        for view in Map3DFollow.View.allCases {
            let camera = Map3DFollow(bus: BusID(route: BusRouteID(rawValue: 1), run: 3), view: view)
                .camera(following: pose(), from: start, elapsed: 0, turnsAtOnce: true)
            XCTAssertTrue(camera.target.x.isFinite && camera.target.y.isFinite && camera.target.z.isFinite, "\(view)")
            XCTAssertTrue(camera.distance.isFinite, "\(view)")
        }
        let follow = Map3DFollow(bus: BusID(route: BusRouteID(rawValue: 1), run: 3))
        XCTAssertNil(follow.train)
        XCTAssertEqual(follow.bus, BusID(route: BusRouteID(rawValue: 1), run: 3))
    }

    func testTheCabEyeIsADriversNotATrains() {
        let start = Map3DCamera(viewport: (390, 844))
        let bus = Map3DFollow(bus: BusID(route: BusRouteID(rawValue: 1), run: 0), view: .cab)
            .camera(following: pose(), from: start, elapsed: 0, turnsAtOnce: true)
        var train = pose()
        train.eyeHeight = nil
        let other = Map3DFollow(bus: BusID(route: BusRouteID(rawValue: 1), run: 0), view: .cab)
            .camera(following: train, from: start, elapsed: 0, turnsAtOnce: true)
        XCTAssertEqual(bus.heading, other.heading)
        XCTAssertNotEqual(bus.eye.y, other.eye.y, "the bus's 2 m eye is not the train's")
        XCTAssertEqual(bus.eye.y, 5 + 2 + 0, accuracy: 0.3)
    }

    func testATrainsHeadReadsTheSameThroughAPose() {
        let head = Map3DTrains.Head(train: TrainID(rawValue: 1), point: Map3DPoint(0, 6, 0), forward: Map3DPoint(0, 0, -1))
        let start = Map3DCamera(viewport: (390, 844))
        for view in Map3DFollow.View.allCases where view != .station {
            let follow = Map3DFollow(train: head.train, view: view)
            XCTAssertEqual(follow.camera(following: head, from: start, elapsed: 0, turnsAtOnce: true),
                           follow.camera(following: head.pose, from: start, elapsed: 0, turnsAtOnce: true))
        }
    }

    // MARK: - On the map

    func testTheFollowedBusIsDrawnWhateverTheBudgetKeepsAndItsPoseIsLaid() throws {
        let (world, route) = try world(buses: 3)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let second = 8 * 3_600 + 180
        let motion = try XCTUnwrap(BusMotion(route))
        let out = motion.buses(at: Double(second))
        let chosen = try XCTUnwrap(out.last)
        let id = BusID(route: route.id, run: chosen.run)
        let pose = try XCTUnwrap(buses.pose(of: id, second: Double(second)))
        XCTAssertEqual(pose.length, Map3DLowFloorBus.length)
        XCTAssertEqual(pose.forward.length, 1, accuracy: 0.001)
        // Far from the camera, and with room for none, it is still drawn.
        let far = Map3DPoint(pose.rail.x + 5_000, 0, pose.rail.z)
        XCTAssertTrue(buses.frame(second: Double(second), target: far, distance: 300, detail: .full, most: 0).instances.isEmpty)
        let drawn = buses.frame(second: Double(second), target: far, distance: 300, detail: .full, most: 0, followed: id)
        XCTAssertEqual(drawn.instances.count, 1)
        XCTAssertNil(buses.pose(of: BusID(route: route.id, run: 9_999), second: Double(second)))
    }

    func testATapTakesTheBusUnderTheFinger() throws {
        let (world, route) = try world(buses: 3)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let second = 8.0 * 3_600 + 180
        let motion = try XCTUnwrap(BusMotion(route))
        let bus = try XCTUnwrap(motion.buses(at: second).first { $0.scale >= 1 })
        let id = BusID(route: route.id, run: bus.run)
        let pose = try XCTUnwrap(buses.pose(of: id, second: second))
        var camera = Map3DCamera(target: pose.rail, distance: 120, viewport: (390, 844))
        camera.heading = 0.3
        let screen = try XCTUnwrap(camera.screenPoint(of: pose.rail + Map3DPoint(0, Map3DLowFloorBus.height / 2, 0)))
        XCTAssertEqual(buses.bus(atX: screen.x + 4, y: screen.y - 3, camera: camera, second: second, within: Map3DBuses.tapReach), id)
        XCTAssertNil(buses.bus(atX: screen.x + 300, y: screen.y, camera: camera, second: second, within: Map3DBuses.tapReach))
        camera.distance = Map3DStreetLife.vehiclesFrom + 100
        XCTAssertNil(buses.bus(atX: screen.x, y: screen.y, camera: camera, second: second, within: Map3DBuses.tapReach), "too far to be drawn")
    }

    // MARK: - Streaming

    /// Decision 358 with a bus: the camera follows the bus, so the target
    /// is the bus and its motion (smoothed frame by frame, ``Map3DStreaming/Motion``)
    /// is the bus's own, as a train's. Driving east along the road at 1×
    /// (5 m/s, over ``Map3DStreaming/still``), the chunks 4 km ahead are
    /// wanted, before they are in view; 4 km behind, they are not.
    func testFollowingARunningBusBuildsTheChunksAheadOfIt() throws {
        let (world, route) = try world(buses: 3)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let motion = try XCTUnwrap(BusMotion(route))
        // A bus on the move at 09:00 (not standing at a stop).
        var second = 9.0 * 3_600 + 120
        let bus = try XCTUnwrap(motion.buses(at: second).first { !$0.stopped && $0.scale >= 1 })
        let id = BusID(route: route.id, run: bus.run)
        var streaming = Map3DStreaming.Motion()
        var pose: Map3DFollow.Pose?
        for frame in 0..<180 {
            pose = try XCTUnwrap(buses.pose(of: id, second: second))
            streaming.update(target: try XCTUnwrap(pose).rail, at: Double(frame) / 60)
            second += 1.0 / 60
        }
        let at = try XCTUnwrap(pose)
        let velocity = streaming.velocity
        XCTAssertGreaterThan((velocity.x * velocity.x + velocity.y * velocity.y).squareRoot(), Map3DStreaming.still,
                             "the bus's own motion is over the line that counts as still")
        let half = 50_000 * Double(WorldCoordinate.unitsPerMetre)
        let grid = Map3DStreaming(originX: scene.originX, originY: scene.originY,
                                  map: WorldRegion(minX: scene.originX - half, minY: scene.originY - half,
                                                   maxX: scene.originX + half, maxY: scene.originY + half))
        let forward = SIMD2<Float>(velocity.x, velocity.y) / (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        func key(_ metres: Float) -> Map3DStreaming.Key {
            grid.key(of: Map3DPoint(at.rail.x + forward.x * metres, 0, at.rail.z + forward.y * metres))
        }
        let wanted = grid.wanted(target: at.rail, velocity: velocity)
        XCTAssertTrue(wanted.contains(key(4_000)), "4 km ahead of the bus")
        XCTAssertFalse(wanted.contains(key(-4_000)), "and not 4 km behind it")
        // The strip ahead is what a standing bus (a stop, a traffic light) does not build.
        let standing = grid.wanted(target: at.rail, velocity: .zero)
        XCTAssertFalse(standing.contains(key(4_000)))
        XCTAssertTrue(Set(standing).isSubset(of: Set(wanted)))
    }
}
