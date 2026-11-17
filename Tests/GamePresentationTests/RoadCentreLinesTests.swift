import GameCore
@testable import GamePresentation
import XCTest

/// Decision 476: the player's roads as one line through their cells.
final class RoadCentreLinesTests: XCTestCase {
    private func cells(_ list: [(Int, Int)]) -> Set<CellPosition> {
        Set(list.map { CellPosition(row: $0.0, column: $0.1) })
    }

    func testAStraightRoadIsOneLineThroughItsMiddles() {
        let road = (3...6).map { CellPosition(row: 2, column: $0) }
        XCTAssertEqual(RoadCentreLines.lines(of: Set(road)), [road.map(\.middle)])
    }

    func testAShortCornerIsCutAcrossInsideItsCells() throws {
        // Decision 821: one cell each side of a turn is a step, drawn as a
        // bend inside the cells (a long corner stays a street corner,
        // RoadSmoothTests).
        let lines = RoadCentreLines.lines(of: cells([(0, 0), (0, 1), (1, 1)]))
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(lines.count, 1)
        XCTAssertFalse(line.contains(CellPosition(row: 0, column: 1).middle), "the corner is cut")
        XCTAssertEqual(line.first, CellPosition(row: 0, column: 0).middle)
        XCTAssertEqual(line.last, CellPosition(row: 1, column: 1).middle)
        let room = RoadCentreLines.Corridor([CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 1), CellPosition(row: 1, column: 1)])
        XCTAssertTrue(line.allSatisfy { room.outside(RoadCentreLines.Point($0)) == 0 }, "inside its cells")
    }

    func testAStaircaseTurnsThroughItsCellsWithNoTriangle() {
        // Corner to corner alone is joined straight; with the cell beside
        // both, the road turns through it instead.
        XCTAssertEqual(RoadCentreLines.lines(of: cells([(0, 0), (1, 1)])).count, 1)
        let lines = RoadCentreLines.lines(of: cells([(0, 0), (0, 1), (1, 1)]))
        XCTAssertEqual(lines.count, 1, "no third side from (0,0) to (1,1)")
    }

    func testAForkIsThreeLinesAndALoneCellADot() {
        let fork = RoadCentreLines.lines(of: cells([(1, 0), (1, 1), (1, 2), (0, 1), (2, 1)]))
        XCTAssertEqual(fork.count, 4, "four arms from the middle cell")
        XCTAssertEqual(RoadCentreLines.lines(of: cells([(5, 5)])), [[CellPosition(row: 5, column: 5).middle]])
    }

    func testTouchingKeepsOnlyTheLinesThroughTheCellsDrawn() {
        // Decision 821: whole, as they will be drawn once laid.
        let city = cells([(0, 0), (0, 1), (0, 2)]), drawn = cells([(1, 2), (2, 2)]), apart = cells([(6, 6), (6, 7)])
        let all = city.union(drawn).union(apart)
        let lines = RoadCentreLines.lines(of: all, touching: drawn)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(RoadCentreLines.lines(of: all).contains(lines[0]))
        XCTAssertEqual(lines[0].first, CellPosition(row: 0, column: 0).middle)
        XCTAssertEqual(lines[0].last, CellPosition(row: 2, column: 2).middle)
    }

    func testTheWidthIsTheBaseMapsLane() {
        XCTAssertEqual(RoadCentreLines.width(zoom: 14), 1.5)
        XCTAssertEqual(RoadCentreLines.width(zoom: 18), 8)
        XCTAssertEqual(RoadCentreLines.width(zoom: 20), 8)
        XCTAssertEqual(RoadCentreLines.width(zoom: 9), 1, "never under a point")
        XCTAssertEqual(RoadCentreLines.width(zoom: 16, casing: true), RoadCentreLines.width(zoom: 16) + 1.5)
        XCTAssertGreaterThan(RoadCentreLines.width(zoom: 16), 1.5)
        XCTAssertLessThan(RoadCentreLines.width(zoom: 16), 8)
    }
}
