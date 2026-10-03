import GameCore
import GamePresentation
import XCTest

/// The map's camera (set ahead of Stage E1): world points to the screen and
/// back, the region in view, and zooming and panning within the zoom range
/// and the map's edges. With the map's corner in the view's corner it draws
/// exactly what ``MapScale`` drew. Stage E1: it opens in the middle of the
/// map or on what is built, and the zoom buttons double or halve the size.
final class MapCameraTests: XCTestCase {
    /// 32 × 24 tiles: 32768 × 24576 world units.
    private let map = try! GridMap(width: 32, height: 24)
    /// A portrait phone's map area: the map is wider and taller than it.
    private let phone = ScreenSize(width: 402, height: 420)
    /// An iPad's map area: the whole map fits.
    private let tablet = ScreenSize(width: 834, height: 700)

    private func assertEqual(_ point: ScreenPoint, _ expected: (x: Double, y: Double), accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, expected.x, accuracy: accuracy, "x", file: file, line: line)
        XCTAssertEqual(point.y, expected.y, accuracy: accuracy, "y", file: file, line: line)
    }

    // MARK: - The scrolling map's steps

    /// On a phone the map opens at ``MapScale/compactSize`` in its middle.
    /// With the map's north-west corner in the view's corner, everything is
    /// drawn and tapped where ``MapScale`` put it.
    func testAPhoneStartsAtTheCompactSizeInTheMiddle() {
        let opening = PlanCamera(map: map, viewport: phone)
        XCTAssertEqual(opening.tileSize, MapScale.compactSize)
        XCTAssertEqual(opening.centerX, 16_384)
        XCTAssertEqual(opening.centerY, 12_288)

        let camera = opening.panned(byX: 1e7, y: 1e7)
        XCTAssertEqual(camera.pointsPerUnit, 32.0 / 1_024)
        assertEqual(camera.screenPoint(of: WorldCoordinate(x: 0, y: 0)), (0, 0))
        for point in [WorldCoordinate(x: 2_048, y: 2_048), WorldCoordinate(x: 6_144, y: 1_000, z: 640), WorldCoordinate(x: 31_000, y: 24_000)] {
            assertEqual(camera.screenPoint(of: point), MapScale.center(of: point, tileSize: camera.tileSize))
        }
        for (x, y) in [(0.0, 0.0), (100.4, 37.6), (401.0, 419.0)] {
            XCTAssertEqual(camera.planPoint(at: ScreenPoint(x: x, y: y)), MapScale.worldPoint(atX: x, y: y, tileSize: camera.tileSize))
        }
        XCTAssertEqual(camera.worldDistance(NetworkBuilding.touchRadius), MapScale.worldDistance(NetworkBuilding.touchRadius, tileSize: camera.tileSize))
        XCTAssertEqual(camera.detail, .full)
        XCTAssertEqual(camera.visibleRegion, WorldRegion(minX: 0, minY: 0, maxX: 402 * 32, maxY: 420 * 32))
    }

    /// On a tablet the whole map fits, centred along the side with room to
    /// spare, as the scrolling map centred a map smaller than the view.
    func testATabletShowsTheWholeMapCentred() {
        let camera = PlanCamera(map: map, viewport: tablet)

        // 834 / 32 = 26.0625 across, 700 / 24 = 29.17 down: the width fits.
        XCTAssertEqual(camera.tileSize, 26.0625)
        XCTAssertEqual(camera.centerX, 16_384)
        XCTAssertEqual(camera.centerY, 12_288)
        assertEqual(camera.screenPoint(of: WorldCoordinate(x: 0, y: 0)), (0, (700 - 24 * 26.0625) / 2))
        assertEqual(camera.screenPoint(of: WorldCoordinate(x: 32_768, y: 24_576)), (834, (700 + 24 * 26.0625) / 2))
        XCTAssertFalse(camera.canZoomOut, "already the whole map")
        XCTAssertTrue(camera.canZoomIn)
    }

    /// The buttons multiply or divide by ``MapScale/zoomFactor`` within
    /// the zoom range, about the middle of the view.
    func testTheZoomButtonsStepAboutTheMiddle() {
        let camera = PlanCamera(map: map, viewport: phone).centered(on: WorldCoordinate(x: 16_384, y: 12_288))
        let middle = ScreenPoint(x: 201, y: 210)

        let closer = camera.zoomedIn()
        XCTAssertEqual(closer.tileSize, 64)
        XCTAssertEqual(closer.worldPosition(at: middle).x, 16_384, accuracy: 1e-9)
        XCTAssertEqual(closer.worldPosition(at: middle).y, 12_288, accuracy: 1e-9)
        XCTAssertEqual(closer.zoomedOut().tileSize, 32)

        var farthest = camera
        while farthest.canZoomOut {
            farthest = farthest.zoomedOut()
        }
        let fitting = MapScale.fittingSize(width: phone.width, height: phone.height, columns: 32, rows: 24)
        XCTAssertEqual(farthest.tileSize, MapScale.minimumSize(fitting: fitting))
        XCTAssertEqual(farthest.zoomedOut(), farthest)

        var nearest = camera
        while nearest.canZoomIn {
            nearest = nearest.zoomedIn()
        }
        XCTAssertEqual(nearest.tileSize, MapScale.largestSize)
        XCTAssertEqual(nearest.zoomedIn(), nearest)
    }

    /// A pinch keeps the world point under the fingers where it is, and
    /// stops at the ends of the zoom range.
    func testAPinchKeepsThePointUnderTheFingers() {
        let camera = PlanCamera(map: map, viewport: phone).centered(on: WorldCoordinate(x: 16_384, y: 12_288))
        let fingers = ScreenPoint(x: 120, y: 300)
        let under = camera.worldPosition(at: fingers)

        let pinched = camera.zoomed(by: 1.5, around: fingers)
        XCTAssertEqual(pinched.tileSize, 48)
        assertEqual(pinched.screenPoint(worldX: under.x, worldY: under.y), (120, 300), accuracy: 1e-6)

        XCTAssertEqual(camera.zoomed(by: 100, around: fingers).tileSize, MapScale.largestSize)
        XCTAssertEqual(camera.zoomed(by: 0.001, around: fingers).tileSize, camera.zoomed(by: 0.002, around: fingers).tileSize, "the smallest size")
        XCTAssertEqual(camera.zoomed(by: 0, around: fingers), camera)
        XCTAssertEqual(camera.zoomed(by: .nan, around: fingers), camera)
    }

    /// A drag moves the map with the finger and stops at the map's edges.
    func testADragMovesTheMapWithTheFingerUpToItsEdges() {
        let camera = PlanCamera(map: map, viewport: phone).centered(on: WorldCoordinate(x: 16_384, y: 12_288))
        let finger = ScreenPoint(x: 200, y: 200)
        let under = camera.worldPosition(at: finger)

        let dragged = camera.panned(byX: -64, y: 32)
        assertEqual(dragged.screenPoint(worldX: under.x, worldY: under.y), (136, 232))

        let farNorthWest = camera.panned(byX: 100_000, y: 100_000)
        assertEqual(farNorthWest.screenPoint(of: WorldCoordinate(x: 0, y: 0)), (0, 0))
        let farSouthEast = camera.panned(byX: -100_000, y: -100_000)
        assertEqual(farSouthEast.screenPoint(of: WorldCoordinate(x: 32_768, y: 24_576)), (402, 420))
        XCTAssertEqual(camera.panned(byX: .infinity, y: 0), camera)

        let whole = PlanCamera(map: map, viewport: tablet)
        XCTAssertEqual(whole.panned(byX: 50, y: 50), whole, "a map that fits stays centred")
    }

    /// What is in view, for drawing only that: the inverse of the view's
    /// corners.
    /// The screen never sends a point that is not a number, but turning one
    /// into world units must not trap; infinities stop at the world's limit.
    func testPointsThatAreNotNumbersDoNotTrap() {
        let camera = PlanCamera(map: map, viewport: phone)
        let point = camera.planPoint(at: ScreenPoint(x: .nan, y: .nan))
        XCTAssertEqual(point, PlanPoint(x: 0, y: 0))
        XCTAssertEqual(camera.worldDistance(.nan), 0)
        let far = camera.planPoint(at: ScreenPoint(x: .infinity, y: -.infinity))
        XCTAssertEqual(far, PlanPoint(x: WorldCoordinate.limit, y: -WorldCoordinate.limit))
    }

    func testTheVisibleRegionIsWhatTheViewShows() {
        let camera = PlanCamera(map: map, viewport: phone).centered(on: WorldCoordinate(x: 16_384, y: 12_288)).zoomedIn()
        let region = camera.visibleRegion
        let topLeft = camera.worldPosition(at: ScreenPoint(x: 0, y: 0))
        let bottomRight = camera.worldPosition(at: ScreenPoint(x: 402, y: 420))
        XCTAssertEqual(region.minX, topLeft.x, accuracy: 1e-9)
        XCTAssertEqual(region.minY, topLeft.y, accuracy: 1e-9)
        XCTAssertEqual(region.maxX, bottomRight.x, accuracy: 1e-9)
        XCTAssertEqual(region.maxY, bottomRight.y, accuracy: 1e-9)

        XCTAssertTrue(region.contains(WorldCoordinate(x: 16_384, y: 12_288)))
        XCTAssertFalse(region.contains(WorldCoordinate(x: 0, y: 0)))
        let edge = WorldRegion(enclosing: [WorldCoordinate(x: 0, y: 12_000), WorldCoordinate(x: 5_000, y: 12_500, z: 300)])
        XCTAssertEqual(edge, WorldRegion(minX: 0, minY: 12_000, maxX: 5_000, maxY: 12_500))
        XCTAssertFalse(region.intersects(edge!))
        XCTAssertTrue(region.expanded(by: 20_000).intersects(edge!))
        XCTAssertNil(WorldRegion(enclosing: [WorldCoordinate]()))
    }

    /// A new view size keeps the middle and the zoom where the new range and
    /// the edges allow; a view of no size still has a positive scale.
    func testResizingKeepsTheMiddleAndZoom() {
        let camera = PlanCamera(map: map, viewport: phone).centered(on: WorldCoordinate(x: 10_000, y: 9_000))
        let landscape = camera.resized(to: ScreenSize(width: 420, height: 402))
        XCTAssertEqual(landscape.tileSize, camera.tileSize)
        XCTAssertEqual(landscape.centerX, 10_000)
        XCTAssertEqual(landscape.centerY, 9_000)

        // 2000 / 32 = 62.5: zooming out stops where the whole map fits.
        let wide = camera.resized(to: ScreenSize(width: 2_000, height: 2_000))
        XCTAssertEqual(wide.tileSize, 62.5)
        XCTAssertEqual(wide.centerX, 16_384, "the whole map, centred")
        XCTAssertEqual(wide.centerY, 12_288)

        let empty = PlanCamera(map: map, viewport: ScreenSize(width: 0, height: 0))
        XCTAssertGreaterThan(empty.pointsPerUnit, 0)
        XCTAssertEqual(empty.viewport, ScreenSize(width: 1, height: 1))
        XCTAssertGreaterThan(empty.zoomedOut().zoomedOut().zoomedOut().zoomedOut().pointsPerUnit, 0)
    }

    /// Stage E1: a camera opens on `showing`, what is built: centred on it,
    /// zoomed out until it fits with ``PlanCamera/focusPadding`` points to
    /// spare, but never closer than it would open without it, and kept on
    /// the map.
    func testACameraOpensOnWhatIsBuilt() throws {
        let large = try GridMap(width: 1_024, height: 1_024)
        // A network 28 × 20 tiles in the middle of a 16 km map.
        let demo = WorldRegion(minX: 498 * 1_024, minY: 502 * 1_024, maxX: 526 * 1_024, maxY: 522 * 1_024)
        let camera = PlanCamera(map: large, viewport: phone, showing: demo)
        XCTAssertEqual(camera.centerX, 512 * 1_024)
        XCTAssertEqual(camera.centerY, 512 * 1_024)
        // (402 - 60) / 28 = 12.2 across, (420 - 60) / 20 = 18 down.
        XCTAssertEqual(camera.tileSize, 342.0 / 28, accuracy: 1e-9)
        let corner = camera.screenPoint(worldX: demo.minX, worldY: demo.minY)
        XCTAssertEqual(corner.x, 30, accuracy: 1e-9)
        XCTAssertGreaterThan(corner.y, 30)
        XCTAssertEqual(camera.detail, .overview)

        // One station: the size it opens at without one, centred on it.
        let station = WorldRegion(enclosing: [WorldCoordinate(x: 300_000, y: 200_000)])!
        let single = PlanCamera(map: large, viewport: phone, showing: station)
        XCTAssertEqual(single.tileSize, MapScale.compactSize)
        XCTAssertEqual(single.centerX, 300_000)
        XCTAssertEqual(single.centerY, 200_000)
        XCTAssertEqual(PlanCamera(map: large, viewport: phone).centerX, 512 * 1_024, "nothing built: the middle")

        // At the map's corner the view stops at its edges.
        let cornerStation = WorldRegion(enclosing: [WorldCoordinate(x: 0, y: 0)])!
        assertEqual(PlanCamera(map: large, viewport: phone, showing: cornerStation).screenPoint(of: WorldCoordinate(x: 0, y: 0)), (0, 0))
        // More than the whole map stops at the whole map.
        let everything = WorldRegion(minX: -1e9, minY: -1e9, maxX: 1e9, maxY: 1e9)
        XCTAssertFalse(PlanCamera(map: large, viewport: phone, showing: everything).canZoomOut)
    }

    /// What a game has built: its track nodes, the points along its edges,
    /// its stations, and an old save's grid track; nothing for a new game.
    func testTheBuiltRegionHoldsTheNetworkAndTheStations() throws {
        XCTAssertNil(WorldRegion.built(in: .newGame()))
        // The demo's ring, 20 tiles round Central (tile 512, 512): its nodes
        // are on the diagonals, 14 tiles out each way, but its arcs reach 20.
        let demo = try XCTUnwrap(WorldRegion.built(in: DemoWorld.make(in: .english)))
        XCTAssertEqual(demo, WorldRegion(minX: 492 * 1_024, minY: 492 * 1_024, maxX: 532 * 1_024, maxY: 532 * 1_024))

        var world = try makeWorld(width: 16, height: 8, balance: 1_000_000)
        try world.buildTrack(at: GridPosition(x: 3, y: 2), connections: [.east, .west])
        try world.buildStation(named: "Far", at: PlanPoint(x: 10_240, y: 6_144))
        XCTAssertEqual(WorldRegion.built(in: world), WorldRegion(minX: 3_584, minY: 2_560, maxX: 10_240, maxY: 6_144))
    }

    /// The level of detail follows the zoom, as ``MapScale`` decides it.
    func testTheDetailFollowsTheZoom() {
        let camera = PlanCamera(map: try! GridMap(width: 1_024, height: 1_024), viewport: phone)
        var farther = camera
        while farther.canZoomOut {
            farther = farther.zoomedOut()
        }
        XCTAssertLessThan(farther.tileSize, 1, "a 16 km map fits a phone")
        XCTAssertEqual(farther.detail, .overview)
        XCTAssertEqual(camera.detail, .full)
    }
}
