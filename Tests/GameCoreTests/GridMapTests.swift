import GameCore
import XCTest

final class GridMapTests: XCTestCase {
    func testMapHasRequestedSizeAndStartsEmpty() throws {
        let map = try GridMap(width: 20, height: 12)

        XCTAssertEqual(map.width, 20)
        XCTAssertEqual(map.height, 12)
        XCTAssertEqual(map.tiles.count, 240)
        XCTAssertTrue(map.tiles.allSatisfy { $0.type == .empty })
    }

    func testTileAtValidPositionReportsPositionAndType() throws {
        let map = try GridMap(width: 5, height: 3)
        let corner = GridPosition(x: 4, y: 2)

        XCTAssertEqual(map.tile(at: corner), MapTile(position: corner, type: .empty))
        XCTAssertTrue(map.contains(corner))
    }

    func testOutOfBoundsPositionsHaveNoTile() throws {
        let map = try GridMap(width: 5, height: 3)
        let outside = [
            GridPosition(x: -1, y: 0),
            GridPosition(x: 0, y: -1),
            GridPosition(x: 5, y: 0),
            GridPosition(x: 0, y: 3),
        ]

        for position in outside {
            XCTAssertFalse(map.contains(position), "\(position)")
            XCTAssertNil(map.tile(at: position), "\(position)")
        }
    }

    func testInvalidSizesAreRejected() {
        let tooLarge = GridMap.maximumSideLength + 1
        for (width, height) in [(0, 10), (10, 0), (-3, 5), (tooLarge, 1)] {
            XCTAssertThrowsGameError(
                try GridMap(width: width, height: height),
                .invalidMapSize(width: width, height: height)
            )
        }
    }

    func testTilesAreInRowMajorOrder() throws {
        let map = try GridMap(width: 3, height: 2)

        XCTAssertEqual(map.tiles.map(\.position), [
            GridPosition(x: 0, y: 0), GridPosition(x: 1, y: 0), GridPosition(x: 2, y: 0),
            GridPosition(x: 0, y: 1), GridPosition(x: 1, y: 1), GridPosition(x: 2, y: 1),
        ])
    }
}
