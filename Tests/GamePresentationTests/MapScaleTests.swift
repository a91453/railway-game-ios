import GameCore
import GamePresentation
import XCTest

final class MapScaleTests: XCTestCase {
    func testFittingSizeIsLimitedByTheTighterAxis() {
        XCTAssertEqual(MapScale.fittingSize(width: 320, height: 1_000, columns: 32, rows: 24), 10)
        XCTAssertEqual(MapScale.fittingSize(width: 1_000, height: 240, columns: 32, rows: 24), 10)
    }

    func testPhoneSizedViewportsScrollAtATappableSize() {
        // A 32 × 24 map in a portrait phone's map area.
        let fitting = MapScale.fittingSize(width: 402, height: 420, columns: 32, rows: 24)

        XCTAssertEqual(MapScale.automaticSize(fitting: fitting), MapScale.compactSize)
        XCTAssertEqual(MapScale.minimumSize(fitting: fitting), fitting, "zooming out can show the whole map")
    }

    func testTabletSizedViewportsShowTheWholeMap() {
        let fitting = MapScale.fittingSize(width: 834, height: 700, columns: 32, rows: 24)

        XCTAssertEqual(fitting, 26.0625)
        XCTAssertEqual(MapScale.automaticSize(fitting: fitting), fitting)
        XCTAssertEqual(MapScale.minimumSize(fitting: fitting), fitting, "never smaller than the whole map")
    }

    func testAutomaticSizeNeverExceedsTheLargestSize() {
        XCTAssertEqual(MapScale.automaticSize(fitting: 500), MapScale.largestSize)
    }

    func testZoomStaysWithinRange() {
        let fitting = 12.5

        // Stage E1: a step doubles or halves the size, as the references'
        // zoom buttons go one zoom level.
        XCTAssertEqual(MapScale.zoomFactor, 2)
        XCTAssertEqual(MapScale.zoomedIn(from: 16, fitting: fitting), 32)
        XCTAssertEqual(MapScale.zoomedIn(from: 40, fitting: fitting), MapScale.largestSize)
        XCTAssertEqual(MapScale.zoomedOut(from: 32, fitting: fitting), 16)
        XCTAssertEqual(MapScale.zoomedOut(from: 16, fitting: fitting), fitting)
        XCTAssertEqual(MapScale.clamped(1, fitting: fitting), fitting)
    }

    /// Small tiles draw an overview; the compact phone size and larger draw
    /// everything.
    func testSmallTilesDrawAnOverview() {
        XCTAssertEqual(MapScale.detail(forTileSize: 8), .overview)
        XCTAssertEqual(MapScale.detail(forTileSize: 19.9), .overview)
        XCTAssertEqual(MapScale.detail(forTileSize: 20), .full)
        XCTAssertEqual(MapScale.detail(forTileSize: MapScale.compactSize), .full)
        XCTAssertEqual(MapScale.detail(forTileSize: MapScale.largestSize), .full)
    }

    func testOffscreenSegmentsAreNotEvenProjected() {
        let projection = RecordingProjection()
        let runs = MapScale.visiblePolylines(
            [WorldCoordinate(x: 200, y: 200), WorldCoordinate(x: 300, y: 250)],
            projection: projection, margin: 0
        )
        XCTAssertTrue(runs.isEmpty)
        XCTAssertTrue(projection.calls.isEmpty)
    }

    func testAnEdgeCrossingTheViewIsKeptWithBothEndsOutside() {
        let projection = RecordingProjection()
        let runs = MapScale.visiblePolylines(
            [WorldCoordinate(x: -50, y: 50), WorldCoordinate(x: 150, y: 50)],
            projection: projection, margin: 0
        )
        XCTAssertEqual(runs, [[ScreenPoint(x: 200, y: 50), ScreenPoint(x: 200, y: -150)]])
        XCTAssertEqual(projection.calls.count, 2)
    }

    func testLeavingAndReenteringTheViewDoesNotDrawAFalseConnectingLine() {
        let projection = RecordingProjection()
        let runs = MapScale.visiblePolylines([
            WorldCoordinate(x: 50, y: 50), WorldCoordinate(x: 120, y: 50),
            WorldCoordinate(x: 120, y: 150), WorldCoordinate(x: 50, y: 150),
            WorldCoordinate(x: 50, y: 50)
        ], projection: projection, margin: 0)
        XCTAssertEqual(runs, [
            [ScreenPoint(x: 200, y: -50), ScreenPoint(x: 200, y: -120)],
            [ScreenPoint(x: 400, y: -50), ScreenPoint(x: 200, y: -50)]
        ])
        XCTAssertEqual(projection.calls.count, 4)
    }

    func testStrokeMarginUsesScreenPointsAtTheCurrentZoom() {
        let projection = RecordingProjection() // two screen points per world unit
        let points = [WorldCoordinate(x: 20, y: -5), WorldCoordinate(x: 80, y: -5)]
        XCTAssertTrue(MapScale.visiblePolylines(points, projection: projection, margin: 8).isEmpty)
        XCTAssertEqual(MapScale.visiblePolylines(points, projection: projection, margin: 12).count, 1)
    }

    func testOverviewReducesCloseVerticesButKeepsBothEnds() {
        let projection = RecordingProjection()
        let points = (0...5).map { WorldCoordinate(x: Int64($0), y: 50) }
        let full = MapScale.visiblePolylines(points, projection: projection, margin: 0)
        let overview = MapScale.visiblePolylines(points, projection: projection, margin: 0, minimumSpacing: 3)
        XCTAssertEqual(full[0].count, 6)
        XCTAssertEqual(overview, [[ScreenPoint(x: 200, y: 0), ScreenPoint(x: 200, y: -3), ScreenPoint(x: 200, y: -5)]])
    }

    func testEachVertexUsesTheProjectionIncludingNonuniformScale() {
        let projection = RecordingProjection()
        let runs = MapScale.visiblePolylines([
            WorldCoordinate(x: 10, y: 10), WorldCoordinate(x: 30, y: 20),
            WorldCoordinate(x: 40, y: 40)
        ], projection: projection, margin: 0)
        XCTAssertEqual(runs, [[ScreenPoint(x: 120, y: -10), ScreenPoint(x: 140, y: -30), ScreenPoint(x: 180, y: -40)]])
        XCTAssertEqual(projection.calls, [ScreenPoint(x: 10, y: 10), ScreenPoint(x: 30, y: 20), ScreenPoint(x: 40, y: 40)])
    }

    func testMaximumSizeMapCullsDistantTrackAndRetainsACrossing() throws {
        let map = try GridMap(width: 1024, height: 1024)
        // The map's north-west corner in the view's (a new camera opens in
        // the middle of the map).
        let camera = PlanCamera(map: map, viewport: ScreenSize(width: 402, height: 420)).panned(byX: 1e7, y: 1e7)
        let distant = [WorldCoordinate(x: 600_000, y: 600_000), WorldCoordinate(x: 700_000, y: 700_000)]
        XCTAssertTrue(MapScale.visiblePolylines(distant, projection: camera, margin: 32).isEmpty)
        let crossing = [WorldCoordinate(x: -1_024, y: 4_096), WorldCoordinate(x: 1_048_576, y: 4_096)]
        let runs = MapScale.visiblePolylines(crossing, projection: camera, margin: 32)
        XCTAssertEqual(runs, [[ScreenPoint(x: -32, y: 128), ScreenPoint(x: 32_768, y: 128)]])
    }
}

/// Turns the map and uses different scales on the two axes. A renderer
/// must call this for every point instead of using pointsPerUnit to draw.
private final class RecordingProjection: MapProjection {
    let visibleRegion = WorldRegion(minX: 0, minY: 0, maxX: 100, maxY: 100)
    let pointsPerUnit = 2.0
    var calls: [ScreenPoint] = []

    func screenPoint(worldX x: Double, worldY y: Double) -> ScreenPoint {
        calls.append(ScreenPoint(x: x, y: y))
        return ScreenPoint(x: 100 + y * 2, y: -x)
    }

    func worldPosition(at point: ScreenPoint) -> (x: Double, y: Double) {
        (-point.y, (point.x - 100) / 2)
    }
}
