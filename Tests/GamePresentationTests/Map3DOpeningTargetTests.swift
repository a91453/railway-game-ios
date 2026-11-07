@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 635 (D5, the Mac playtest of 2026-11-08): the high-speed demo
/// with the 2D map pulled out to the whole island, the 3D button opened
/// over the Central Mountain Range, no track in sight and no way to pull
/// the 3D map out to find it; with Taichung selected, the same; pulled
/// close on the 2D map, the 3D map still opened far out.
final class Map3DOpeningTargetTests: XCTestCase {
    static let metre = Double(WorldCoordinate.unitsPerMetre)
    static let phone = ScreenSize(width: 852, height: 393)

    /// The demo with short lines at Taipei and Zuoying, its two ends.
    func demo() throws -> (world: GameWorld, taipei: (x: Double, y: Double), zuoying: (x: Double, y: Double)) {
        var world = HighSpeedDemo.newWorld(paying: GameWorld.startingBalance, eventSeed: 1)
        let taipei = try Map3DOpenHereTests.point(25.0478, 121.5170, in: world)
        let zuoying = try Map3DOpenHereTests.point(22.6873, 120.3076, in: world)
        world = try Map3DOpenHereTests.line(round: taipei, metres: 2_000, in: world)
        world = try Map3DOpenHereTests.line(round: zuoying, metres: 2_000, in: world)
        return (world, taipei, zuoying)
    }

    func distance(_ plan: Map3DHandoff.Plan, _ point: (x: Double, y: Double)) -> Double {
        hypot(plan.x - point.x, plan.y - point.y) / Self.metre
    }

    func testTheWholeIslandOpensOnTheNearestTrackNotTheMountains() throws {
        let (world, taipei, zuoying) = try demo()
        let island = PlanCamera(bounds: world.bounds, viewport: Self.phone, showing: WorldRegion(bounds: world.bounds))
        XCTAssertGreaterThan(island.visibleRegion.height / Self.metre, Map3DHandoff.opensOverTheMiddleUpTo)
        let middle = (x: island.centerX, y: island.centerY)
        let plan = Map3DHandoff.opening(from: island, in: world)
        // Not the middle, which is tens of kilometres from either line.
        XCTAssertGreaterThan(min(distance(Map3DHandoff.Plan(x: middle.x, y: middle.y, referenceSize: 0), taipei),
                                 distance(Map3DHandoff.Plan(x: middle.x, y: middle.y, referenceSize: 0), zuoying)), 20_000)
        // On the track nearer the middle (its 2 km and its stations beside it).
        let nearer = distance(plan, taipei) < distance(plan, zuoying) ? taipei : zuoying
        XCTAssertLessThanOrEqual(distance(plan, nearer), 1_500)
        // Shown about 3 km tall, as a town.
        let shown = 2 * Double(Map3DHandoff.distance(referenceSize: plan.referenceSize, viewportHeight: Self.phone.height))
            * tan(Double(Map3DCamera.fieldOfView) / 2)
        XCTAssertEqual(shown, Map3DHandoff.groundShownOverTarget, accuracy: 1)
    }

    func testASelectedStationWinsOverTheNearestTrack() throws {
        var (world, taipei, zuoying) = try demo()
        world = try Map3DOpenHereTests.line(round: (x: zuoying.x, y: zuoying.y + 5_000 * Self.metre), metres: 1_000, in: world)
        let island = PlanCamera(bounds: world.bounds, viewport: Self.phone, showing: WorldRegion(bounds: world.bounds))
        let far = try XCTUnwrap(world.stations.max { a, b in
            hypot(Double(a.location.x) - taipei.x, Double(a.location.y) - taipei.y)
                < hypot(Double(b.location.x) - taipei.x, Double(b.location.y) - taipei.y)
        })
        let plan = Map3DHandoff.opening(from: island, in: world, station: far.id)
        XCTAssertEqual(plan.x, Double(far.location.x))
        XCTAssertEqual(plan.y, Double(far.location.y))
    }

    func testAClose2DMapOpensWhereItLooksAsCloseAsItWas() throws {
        let (world, taipei, _) = try demo()
        let half = 600 * Self.metre
        let close = PlanCamera(bounds: world.bounds, viewport: Self.phone,
                               showing: WorldRegion(minX: taipei.x - half, minY: taipei.y - half, maxX: taipei.x + half, maxY: taipei.y + half))
        let station = try XCTUnwrap(world.stations.first)
        let plan = Map3DHandoff.opening(from: close, in: world, station: station.id)
        XCTAssertEqual(plan, Map3DHandoff.Plan(x: close.centerX, y: close.centerY, referenceSize: close.referenceSize),
                       "near enough, the middle and zoom as they were, selection or not")
        // And the 3D camera as close as that, not the whole scene.
        let opened = Map3DHandoff.openingDistance(of: plan, sceneSpan: 12_000, viewportHeight: Self.phone.height)
        XCTAssertEqual(opened, Map3DHandoff.distance(referenceSize: plan.referenceSize, viewportHeight: Self.phone.height))
        XCTAssertLessThan(opened, 3_000)
        XCTAssertEqual(Map3DHandoff.openingDistance(of: nil, sceneSpan: 12_000, viewportHeight: Self.phone.height), 10_800,
                       "from the settings, the whole scene as before")
    }

    func testNothingBuiltKeepsTheMiddle() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 23.7, longitudeDegrees: 121.0)))
        XCTAssertNil(WorldRegion.built(in: world))
        let island = PlanCamera(bounds: world.bounds, viewport: Self.phone, showing: WorldRegion(bounds: world.bounds))
        let plan = Map3DHandoff.opening(from: island, in: world)
        XCTAssertEqual(plan, Map3DHandoff.Plan(x: island.centerX, y: island.centerY, referenceSize: island.referenceSize))
    }
}
