@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 313, later (2026-10-21, the owner's iPhone 17 Pro): the 3D map
/// opens where the 2D map looks, not over the middle of what is built (the
/// high-speed demo's Taipei–Zuoying line put it over Sun Moon Lake) or of
/// the whole map (a new real-world game's, the mountains).
final class Map3DOpenHereTests: XCTestCase {
    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The world point of a place on a whole-Taiwan map, near enough for
    /// a scene 12 km across.
    static func point(_ latitude: Double, _ longitude: Double, in world: GameWorld) throws -> (x: Double, y: Double) {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let anchor = frame.anchor
        let east = (longitude - anchor.longitudeDegrees) * 111_320 * cos(anchor.latitudeDegrees * .pi / 180)
        let south = (anchor.latitudeDegrees - latitude) * 110_540
        return frame.worldPosition(east: east, south: south)
    }

    /// A short line round `centre`, `metres` long, east to west.
    static func line(round centre: (x: Double, y: Double), metres: Double, in world: GameWorld) throws -> GameWorld {
        let half = Int64(metres / 2 * metre)
        let x = Int64(centre.x), y = Int64(centre.y)
        return try LineBuilder.line(through: [PlanPoint(x: x - half, y: y), PlanPoint(x: x, y: y), PlanPoint(x: x + half, y: y)], in: world)
    }

    func testTheHighSpeedDemoOpensAtTaipeiNotOverTheMiddleOfTheIsland() throws {
        // Lines at Taipei and Zuoying, as the demo's ends: what is built
        // spans the island.
        var world = HighSpeedDemo.newWorld(paying: GameWorld.startingBalance, eventSeed: 1)
        let taipei = try Self.point(25.0478, 121.5170, in: world), zuoying = try Self.point(22.6873, 120.3076, in: world)
        world = try Self.line(round: taipei, metres: 2_000, in: world)
        world = try Self.line(round: zuoying, metres: 2_000, in: world)

        // As it was: the middle of the two, some 130 km from either.
        let middle = Map3DScene.frame(world: world, focus: nil)
        let off = hypot(middle.originX - taipei.x, middle.originY - taipei.y) / Self.metre
        XCTAssertGreaterThan(off, 100_000)

        // Opened from the 2D map looking at Taipei: the scene round Taipei.
        let here = Map3DScene.frame(world: world, focus: taipei)
        XCTAssertEqual(here.originX, taipei.x.rounded())
        XCTAssertEqual(here.originY, taipei.y.rounded())
        XCTAssertLessThanOrEqual(here.region.minX, taipei.x)
        XCTAssertGreaterThanOrEqual(here.region.maxX, taipei.x)
        XCTAssertLessThanOrEqual(here.region.minY, taipei.y)
        XCTAssertGreaterThanOrEqual(here.region.maxY, taipei.y)
        let reach = Map3DScene.reach * Self.metre
        XCTAssertLessThanOrEqual(here.region.maxX - here.region.minX, 2 * reach + 1)
        XCTAssertLessThanOrEqual(here.region.maxY - here.region.minY, 2 * reach + 1)
    }

    func testANewRealWorldGameOpensWhereTheMapLooks() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        XCTAssertNil(WorldRegion.built(in: world), "nothing built yet")
        let map = WorldRegion(bounds: world.bounds)
        let looking = (x: map.minX + (map.maxX - map.minX) * 0.3, y: map.minY + (map.maxY - map.minY) * 0.7)
        let frame = Map3DScene.frame(world: world, focus: looking)
        XCTAssertEqual(frame.originX, looking.x.rounded())
        XCTAssertEqual(frame.originY, looking.y.rounded())
        // The ground round it, as far as the margin.
        let margin = Map3DScene.margin * Self.metre
        XCTAssertEqual(frame.region.maxX - frame.region.minX, 2 * margin, accuracy: 1)
    }

    func testAFocusOffTheMapIsKeptWithinIt() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let map = WorldRegion(bounds: world.bounds)
        let frame = Map3DScene.frame(world: world, focus: (x: map.maxX + 50_000 * Self.metre, y: map.minY - 50_000 * Self.metre))
        XCTAssertEqual(frame.originX, map.maxX.rounded())
        XCTAssertEqual(frame.originY, map.minY.rounded())
        XCTAssertGreaterThanOrEqual(frame.region.minX, map.minX)
        XCTAssertLessThanOrEqual(frame.region.maxX, map.maxX)
        XCTAssertGreaterThanOrEqual(frame.region.minY, map.minY)
        XCTAssertLessThanOrEqual(frame.region.maxY, map.maxY)
        XCTAssertLessThan(frame.region.minX, frame.region.maxX)
    }

    func testWhatIsBuiltNearTheFocusStaysInTheScene() throws {
        // A line 4 km long, the 2D map looking at its east end: the whole
        // line, and the margin round it, still in the scene.
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let map = WorldRegion(bounds: world.bounds)
        let centre = (x: (map.minX + map.maxX) / 2, y: (map.minY + map.maxY) / 2)
        world = try Self.line(round: centre, metres: 4_000, in: world)
        let built = try XCTUnwrap(WorldRegion.built(in: world))
        let frame = Map3DScene.frame(world: world, focus: (x: built.maxX, y: centre.y))
        XCTAssertLessThanOrEqual(frame.region.minX, built.minX)
        XCTAssertGreaterThanOrEqual(frame.region.maxX, built.maxX)
    }

    /// Nothing built near: a scene round one focus covers only the margin
    /// round it, so a focus in the same square kilometres off is not in
    /// it, and the cache builds anew; the same focus, or one near it, is.
    func testASceneRoundAnotherFocusInTheSameSquareHoldsItOnlyWhenItCoversIt() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let map = WorldRegion(bounds: world.bounds)
        let side = Map3DScene.reach / 2 * Self.metre
        let corner = (x: ((map.minX + map.maxX) / 2 / side).rounded(.down) * side, y: ((map.minY + map.maxY) / 2 / side).rounded(.down) * side)
        let first = (x: corner.x + 100 * Self.metre, y: corner.y + 100 * Self.metre)
        let far = (x: corner.x + 2_900 * Self.metre, y: corner.y + 2_900 * Self.metre)
        XCTAssertEqual(Map3DScene.FocusArea(x: first.x, y: first.y), Map3DScene.FocusArea(x: far.x, y: far.y), "the same square")
        let region = Map3DScene.region(world: world, focus: first)
        XCTAssertFalse(region.minX <= far.x && far.x <= region.maxX, "off the scene")
        XCTAssertFalse(Map3DScene.holds(far, in: region, world: world))
        XCTAssertTrue(Map3DScene.holds(first, in: region, world: world))
        XCTAssertTrue(Map3DScene.holds((x: first.x + 500 * Self.metre, y: first.y), in: region, world: world))
        XCTAssertTrue(Map3DScene.holds(nil, in: region, world: world))
        // Its own region holds the far focus.
        XCTAssertTrue(Map3DScene.holds(far, in: Map3DScene.region(world: world, focus: far), world: world))
    }

    /// At the map's edge the scene stops where the map does, and still
    /// holds its focus.
    func testASceneAtTheMapsEdgeHoldsItsFocus() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let map = WorldRegion(bounds: world.bounds)
        let focus = (x: map.maxX, y: map.minY)
        XCTAssertTrue(Map3DScene.holds(focus, in: Map3DScene.region(world: world, focus: focus), world: world))
        XCTAssertTrue(Map3DScene.holds((x: map.maxX + 1_000 * Self.metre, y: map.minY), in: Map3DScene.region(world: world, focus: focus), world: world))
    }

    func testAFocusAFewKilometresOffBuildsAnew() {
        let metre = Self.metre
        let a = Map3DScene.FocusArea(x: 1_000 * metre, y: 1_000 * metre)
        XCTAssertEqual(a, Map3DScene.FocusArea(x: 2_000 * metre, y: 2_500 * metre))
        XCTAssertNotEqual(a, Map3DScene.FocusArea(x: 4_000 * metre, y: 1_000 * metre))
        XCTAssertNotEqual(a, Map3DScene.FocusArea(x: 1_000 * metre, y: -1_000 * metre))
    }
}
