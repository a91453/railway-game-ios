import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ROAD-FORK-CELL (decision 821's next step): a road dragged off a road
/// already there at a slant, or onto one, forks as a plain T, without a
/// block of 2 × 2 cells (drawn as a small triangle and paid for a cell too
/// many). A cell is 4,096 units (64 m).
///
/// A world of 64 × 16 cells with the city's road along row 8 from column 5
/// to 40.
@MainActor
final class RoadForkCellTests: XCTestCase {
    private let side = Double(Land.cellLength)

    private func session() throws -> GameSession {
        let cell = Land.cellLength
        var world = GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        world.enableRoads()
        try world.setRoads((5...40).map { CellPosition(row: 8, column: $0) },
                           in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1), LandBlock(row: 0, column: 2), LandBlock(row: 0, column: 3)])
        let session = GameSession(world: world)
        session.selectTool(.bus)
        session.setBusMode(.roads)
        return session
    }

    private func cell(_ row: Int, _ column: Int) -> CellPosition { CellPosition(row: row, column: column) }

    /// A finger from `from` going `dx`, `dy` cells, a move every `step`
    /// units, lifted at the end.
    private func drag(_ session: GameSession, from: PlanPoint, dx: Double, dy: Double, step: Double = 1_200) {
        let length = (dx * dx + dy * dy).squareRoot() * side
        let moves = max(1, Int((length / step).rounded(.up)))
        for move in 1...moves {
            let t = Double(move) / Double(moves)
            let to = PlanPoint(x: from.x + Int64((dx * side * t).rounded()), y: from.y + Int64((dy * side * t).rounded()))
            if move == moves { session.endRoadDrag(from: from, to: to) } else { session.dragRoad(from: from, to: to) }
        }
    }

    /// The blocks of 2 × 2 cells, all with a road or drawn, with a cell
    /// drawn that has no road yet.
    private func blocks(_ session: GameSession) -> [CellPosition] {
        guard let roads = session.world.roads else { return [] }
        let drawn = Set(session.roadDraft.cells), new = drawn.filter { !roads.contains($0) }
        let all = drawn.union(roads.allCells)
        var found = Set<CellPosition>()
        for at in new {
            for dr in -1...0 {
                for dc in -1...0 {
                    let corner = cell(at.row + dr, at.column + dc)
                    let four = [corner, cell(corner.row + 1, corner.column), cell(corner.row, corner.column + 1), cell(corner.row + 1, corner.column + 1)]
                    if four.allSatisfy(all.contains) { found.insert(corner) }
                }
            }
        }
        return found.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    func testASteepForkOffTheRoadIsAPlainT() throws {
        let session = try session()
        // From the road at (8, 10), 60° south-east: the first step is
        // south, off the road, with the road's next cell beside it.
        drag(session, from: cell(8, 10).middle, dx: 1.7, dy: 3)
        let cells = session.roadDraft.cells
        XCTAssertEqual(Array(cells.prefix(3)), [cell(8, 10), cell(8, 11), cell(9, 11)], "along the road one cell, then off it")
        XCTAssertFalse(cells.contains(cell(9, 10)), "the cell of the 2 × 2 block is not drawn")
        XCTAssertEqual(blocks(session), [])
        let preview = try XCTUnwrap(session.roadPreview)
        XCTAssertFalse(preview.laid.contains(cell(9, 10)))
        XCTAssertTrue(preview.canBuild)
        XCTAssertTrue(session.confirmRoad())
        XCTAssertFalse(try XCTUnwrap(session.world.roads).built.contains(cell(9, 10)), "not laid or paid for")
    }

    func testASlantRoadOntoTheRoadEndsInAPlainT() throws {
        let session = try session()
        // From (12, 20) up to the road at 60°, north-east.
        drag(session, from: cell(12, 20).middle, dx: 2.3, dy: -4)
        XCTAssertEqual(session.roadDraft.cells.last.map { $0.row }, 8, "ends on the road")
        XCTAssertEqual(blocks(session), [])
    }

    func testAForkAtAnySlantInEitherDirectionLeavesNoBlock() throws {
        // Off the road both ways, north and south, at 20° to 80°, from the
        // cell's middle and off it; and the same roads drawn back onto it.
        for angle in stride(from: 20.0, through: 80.0, by: 5.0) {
            for (east, south) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
                for nudge in [0.0, 0.3, -0.3] {
                    let radians = angle * .pi / 180, reach = 6.0
                    let dx = east * cos(radians) * reach, dy = south * sin(radians) * reach
                    let from = PlanPoint(x: cell(8, 22).middle.x + Int64(nudge * side / 2), y: cell(8, 22).middle.y)
                    let off = try session()
                    drag(off, from: from, dx: dx, dy: dy)
                    XCTAssertEqual(blocks(off), [], "off the road at \(angle)°, \(east), \(south), \(nudge)")
                    let to = PlanPoint(x: from.x + Int64(dx * side), y: from.y + Int64(dy * side))
                    let onto = try session()
                    drag(onto, from: to, dx: -dx, dy: -dy)
                    XCTAssertEqual(blocks(onto), [], "onto the road at \(angle)°, \(east), \(south), \(nudge)")
                    for draft in [off.roadDraft.cells, onto.roadDraft.cells] {
                        for (a, b) in zip(draft, draft.dropFirst()) {
                            XCTAssertTrue(a != b && abs(a.row - b.row) <= 1 && abs(a.column - b.column) <= 1, "each beside the last")
                        }
                    }
                }
            }
        }
    }

    func testARoadAwayFromAnyRoadIsDrawnAsBefore() throws {
        let session = try session()
        let from = cell(13, 10).middle
        drag(session, from: from, dx: 7, dy: -2.5)
        // The same moves on a draft that knows no road.
        var draft = RoadDraft()
        draft.extend(to: cell(13, 10))
        var finger = from
        let moves = max(1, Int(((49.0 + 6.25).squareRoot() * side / 1_200).rounded(.up)))
        for move in 1...moves {
            let t = Double(move) / Double(moves)
            let to = PlanPoint(x: from.x + Int64((7 * side * t).rounded()), y: from.y + Int64((-2.5 * side * t).rounded()))
            draft.extend(from: finger, to: to)
            finger = to
        }
        XCTAssertEqual(session.roadDraft.cells, draft.cells)
    }
}
