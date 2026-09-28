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

        XCTAssertEqual(MapScale.zoomedIn(from: 32, fitting: fitting), 40)
        XCTAssertEqual(MapScale.zoomedIn(from: 60, fitting: fitting), MapScale.largestSize)
        XCTAssertEqual(MapScale.zoomedOut(from: 32, fitting: fitting), 24)
        XCTAssertEqual(MapScale.zoomedOut(from: 16, fitting: fitting), fitting)
        XCTAssertEqual(MapScale.clamped(1, fitting: fitting), fitting)
    }

    func testPointsMapToColumnsAlongXAndRowsAlongY() {
        XCTAssertEqual(MapScale.position(atX: 0, y: 0, tileSize: 30), GridPosition(x: 0, y: 0))
        XCTAssertEqual(MapScale.position(atX: 29.9, y: 30, tileSize: 30), GridPosition(x: 0, y: 1))
        XCTAssertEqual(MapScale.position(atX: 95, y: 5, tileSize: 30), GridPosition(x: 3, y: 0))
        XCTAssertEqual(MapScale.position(atX: 5, y: 95, tileSize: 30), GridPosition(x: 0, y: 3))
    }

    func testPointsLeftOfOrAboveTheMapAreOutside() {
        XCTAssertEqual(MapScale.position(atX: -0.5, y: -0.5, tileSize: 30), GridPosition(x: -1, y: -1))
    }
}
