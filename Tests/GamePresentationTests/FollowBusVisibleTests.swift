import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 580 (FOLLOWBUS, 續): the bus followed is in the middle of the
/// picture from above and behind and from beside it, and among what is
/// drawn, in the scene of the website's follow-bus screenshots; and
/// drawn where nothing else moves on the streets (the device has no tier,
/// as the Simulator's GPU, or the camera is too far for vehicles).
@MainActor
final class FollowBusVisibleTests: XCTestCase {
    func testTheFollowedBusIsInViewAndDrawnFromAboveAndBeside() throws {
        let world = ScreenshotScene.followBus.make(in: .english)
        let route = try XCTUnwrap(world.busRoutes.last)
        let motion = try XCTUnwrap(BusMotion(route))
        let second = world.busSecondOfDay
        let bus = try XCTUnwrap(motion.successor(of: -1, at: second))
        let id = BusID(route: route.id, run: bus.run)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let pose = try XCTUnwrap(buses.pose(of: id, second: second))
        for view in [Map3DFollow.View.aboveBack, .side, .back] {
            let camera = Map3DFollow(bus: id, view: view)
                .camera(following: pose, from: Map3DCamera(viewport: (390, 844)), elapsed: 0, turnsAtOnce: true)
            let frame = buses.frame(second: second, target: camera.target, distance: camera.distance, detail: .full, followed: id)
            let drawn = try XCTUnwrap(frame.clear.first, "\(view): the bus is drawn")
            let middle = drawn.point + Map3DPoint(0, Map3DLowFloorBus.height / 2, 0)
            let screen = try XCTUnwrap(camera.screenPoint(of: middle), "\(view): the bus is in front of the camera")
            XCTAssertTrue(screen.x > 0 && screen.x < 390 && screen.y > 0 && screen.y < 844, "\(view): on screen at \(screen)")
        }
    }

    /// The Simulator's GPU has no tier (Apple family 2), so the streets
    /// draw nothing that moves (``Map3DStreetDetail/off``); the bus the
    /// camera follows is drawn all the same, as a followed train is, and
    /// no other.
    func testTheFollowedBusIsDrawnWithNoStreetLife() throws {
        let world = ScreenshotScene.followBus.make(in: .english)
        let route = try XCTUnwrap(world.busRoutes.last)
        let motion = try XCTUnwrap(BusMotion(route))
        let second = world.busSecondOfDay
        let bus = try XCTUnwrap(motion.successor(of: -1, at: second))
        let id = BusID(route: route.id, run: bus.run)
        let scene = Map3DScene(world: world)
        let buses = Map3DBuses(world: world, scene: scene, palette: .standard)
        let pose = try XCTUnwrap(buses.pose(of: id, second: second))
        XCTAssertTrue(buses.frame(second: second, target: pose.rail, distance: 200, detail: .off).instances.isEmpty, "no other bus")
        let off = buses.frame(second: second, target: pose.rail, distance: 200, detail: .off, followed: id)
        XCTAssertEqual(off.instances.count, 1, "the followed bus with the street detail off")
        let far = buses.frame(second: second, target: pose.rail, distance: Map3DStreetLife.vehiclesFrom + 500, detail: .full, followed: id)
        XCTAssertEqual(far.instances.count, 1, "and from farther than vehicles are drawn")
        // Through the street life's frame, with no budget's tier.
        let budget = Map3DMotionBudget(tier: nil, step: .full, trainTriangles: 0)
        let life = scene.streetLife.frame(target: pose.rail, distance: 200, time: 0, detail: budget.tier?.streetDetail ?? .off,
                                          activity: Map3DStreetLife.Activity(world: world), buses: off,
                                          limits: budget.limits(routeBuses: off.instances.count))
        XCTAssertEqual(life.instances.count, 1, "the street life keeps it")
        XCTAssertEqual(life.instances.first?.model, off.instances.first?.model)
    }
}
