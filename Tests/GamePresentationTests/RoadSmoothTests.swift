import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 821 (ROAD-SMOOTH): the player's roads stay cells, but are drawn
/// as straight lines and smooth bends inside their own cells, with ends and
/// forks at their cells' middles.
final class RoadSmoothTests: XCTestCase {
    private let side = Double(Land.cellLength)

    private func cell(_ row: Int, _ column: Int) -> CellPosition { CellPosition(row: row, column: column) }

    /// The cells a finger drawing from `points[0]` through the rest takes,
    /// a move every `step` of the way.
    private func drag(_ points: [PlanPoint], step: Double = 1_200) -> [CellPosition] {
        var draft = RoadDraft()
        draft.extend(to: CellPosition(containing: points[0]))
        var finger = points[0]
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let moves = max(1, Int(((dx * dx + dy * dy).squareRoot() / step).rounded(.up)))
            for move in 1...moves {
                let t = Double(move) / Double(moves)
                let next = PlanPoint(x: a.x + Int64((dx * t).rounded()), y: a.y + Int64((dy * t).rounded()))
                draft.extend(from: finger, to: next)
                finger = next
            }
        }
        return draft.cells
    }

    /// How far `point` is from the segment `a`–`b`.
    private func distance(_ point: PlanPoint, from a: PlanPoint, to b: PlanPoint) -> Double {
        let px = Double(point.x - a.x), py = Double(point.y - a.y), bx = Double(b.x - a.x), by = Double(b.y - a.y)
        let t = max(0, min(1, (px * bx + py * by) / (bx * bx + by * by)))
        let dx = px - bx * t, dy = py - by * t
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The points every half metre along `line`.
    private func samples(_ line: [PlanPoint]) -> [RoadCentreLines.Point] {
        var out: [RoadCentreLines.Point] = line.prefix(1).map(RoadCentreLines.Point.init)
        for (a, b) in zip(line, line.dropFirst()) {
            let from = RoadCentreLines.Point(a), to = RoadCentreLines.Point(b)
            let pieces = max(1, Int(((to - from).length / 32).rounded(.up)))
            for piece in 1...pieces { out.append(from + (to - from) * (Double(piece) / Double(pieces))) }
        }
        return out
    }

    /// How far the farthest point of `lines` is outside `cells`.
    private func farthestOutside(_ lines: [[PlanPoint]], of cells: Set<CellPosition>) -> Double {
        let room = RoadCentreLines.Corridor(Array(cells))
        return lines.flatMap(samples).map(room.outside).max() ?? 0
    }

    /// The cells beside two cells of `cells` joined corner to corner (the
    /// two that are not road there).
    private func besideCorners(of cells: Set<CellPosition>) -> Set<CellPosition> {
        var beside = Set<CellPosition>()
        for (cell, near) in RoadCentreLines.joins(of: cells) {
            for other in near where other.row != cell.row && other.column != cell.column {
                beside.insert(CellPosition(row: cell.row, column: other.column))
                beside.insert(CellPosition(row: other.row, column: cell.column))
            }
        }
        return beside
    }

    // MARK: - Drawn straight

    func testAThirtyDegreeDragIsDrawnAsOneStraightLine() throws {
        // From one cell's middle to one 7 east and 4 south: 29.7°.
        let from = cell(10, 10).middle, to = cell(14, 17).middle
        let cells = drag([from, to])
        XCTAssertEqual(cells.first, cell(10, 10))
        XCTAssertEqual(cells.last, cell(14, 17))
        let before = RoadCentreLinesBefore.lines(of: Set(cells))
        let lines = RoadCentreLines.lines(of: Set(cells))
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(line.first, from)
        XCTAssertEqual(line.last, to)
        let off = line.map { distance($0, from: from, to: to) }.max() ?? 0
        XCTAssertLessThanOrEqual(off, Double(WorldCoordinate.unitsPerMetre), "within a metre of the finger's line")
        let offBefore = before.flatMap { $0 }.map { distance($0, from: from, to: to) }.max() ?? 0
        XCTAssertGreaterThan(offBefore, 10 * Double(WorldCoordinate.unitsPerMetre), "the cells' middles zigzag")
        XCTAssertLessThanOrEqual(farthestOutside(lines, of: Set(cells)), RoadCentreLines.edge, "inside its own cells, but for a corner's tip")
    }

    func testAStraightDragAtAnyAngleIsAStraightLineInItsCells() {
        // Angles from 3° to 87°, each between two cells' middles.
        for (rows, columns) in [(1, 12), (2, 9), (3, 8), (5, 9), (4, 5), (7, 8), (9, 7), (8, 3), (11, 1)] {
            let from = cell(20, 20).middle, to = cell(20 + rows, 20 + columns).middle
            let cells = drag([from, to], step: 900)
            let lines = RoadCentreLines.lines(of: Set(cells))
            XCTAssertEqual(lines.count, 1, "\(rows)×\(columns)")
            let off = lines.flatMap { $0 }.map { distance($0, from: from, to: to) }.max() ?? .infinity
            XCTAssertLessThanOrEqual(off, Double(WorldCoordinate.unitsPerMetre), "\(rows)×\(columns): straight")
            XCTAssertLessThanOrEqual(farthestOutside(lines, of: Set(cells)), RoadCentreLines.edge + 1, "\(rows)×\(columns)")
        }
    }

    func testFortyFiveDegreesThroughTheCornersStillGoesCornerToCorner() {
        let cells = drag([cell(5, 5).middle, cell(11, 11).middle])
        XCTAssertEqual(cells, (5...11).map { cell($0, $0) }, "corner to corner, as long as before")
        XCTAssertEqual(RoadCentreLines.lines(of: Set(cells)).count, 1)
    }

    func testTheDragStepsThroughEveryCellTheFingerCrossesAndEndsUnderIt() {
        var generator = Generator(seed: 821)
        for _ in 0..<60 {
            var points = [PlanPoint(x: Int64(generator.next(in: 40_000...80_000)), y: Int64(generator.next(in: 40_000...80_000)))]
            for _ in 0..<4 {
                let last = points[points.count - 1]
                points.append(PlanPoint(x: last.x + Int64(generator.next(in: -30_000...30_000)), y: last.y + Int64(generator.next(in: -30_000...30_000))))
            }
            let cells = drag(points, step: Double(generator.next(in: 300...5_000)))
            XCTAssertEqual(cells.last, CellPosition(containing: points[points.count - 1]))
            for (a, b) in zip(cells, cells.dropFirst()) {
                XCTAssertTrue(a != b && abs(a.row - b.row) <= 1 && abs(a.column - b.column) <= 1, "each beside the last")
            }
        }
    }

    // MARK: - Inside its own cells

    func testEveryLineStaysInItsOwnCells() {
        var generator = Generator(seed: 476)
        for round in 0..<80 {
            // Drawn by a finger wandering about, or (as saved before
            // decision 821) a cell at a time corner to corner first.
            var cells: [CellPosition]
            if round % 2 == 0 {
                var points = [PlanPoint(x: 100_000, y: 100_000)]
                for _ in 0..<6 {
                    let last = points[points.count - 1]
                    points.append(PlanPoint(x: last.x + Int64(generator.next(in: -40_000...40_000)), y: last.y + Int64(generator.next(in: -40_000...40_000))))
                }
                cells = drag(points, step: Double(generator.next(in: 400...4_000)))
            } else {
                var draft = RoadDraft()
                var at = cell(30, 30)
                draft.extend(to: at)
                for _ in 0..<8 {
                    at = cell(at.row + generator.next(in: -6...6), at.column + generator.next(in: -6...6))
                    draft.extend(to: at)
                }
                cells = draft.cells
            }
            let set = Set(cells)
            let lines = RoadCentreLines.lines(of: set)
            let room = RoadCentreLines.Corridor(cells), beside = besideCorners(of: set)
            for point in lines.flatMap(samples) {
                let out = room.outside(point)
                guard out > 0 else { continue }
                XCTAssertLessThanOrEqual(out, RoadCentreLines.edge + 1, "round \(round): at most a lane's half past a corner")
                XCTAssertTrue(beside.contains(RoadCentreLines.Corridor.cell(of: point)),
                              "round \(round): only in a cell beside a corner the road goes corner to corner through")
            }
        }
    }

    func testANewRoadNeverLeavesItsCells() {
        // A finger drawing a curve: the cells it crosses hold the road.
        var points: [PlanPoint] = []
        for step in 0...12 {
            let angle = Double(step) / 12 * Double.pi / 2
            points.append(PlanPoint(x: 200_000 + Int64(60_000 * (1 - cos(angle))), y: 200_000 + Int64(60_000 * sin(angle))))
        }
        let cells = drag(points)
        let lines = RoadCentreLines.lines(of: Set(cells))
        XCTAssertEqual(lines.count, 1)
        XCTAssertLessThanOrEqual(farthestOutside(lines, of: Set(cells)), RoadCentreLines.edge + 1)
    }

    // MARK: - Ends and forks

    func testEndsAndForksStayAtTheirCellsMiddles() {
        // A road along row 10 with a slanting branch from its middle cell.
        var cells = Set((0...12).map { cell(10, $0) })
        cells.formUnion(drag([cell(10, 6).middle, cell(17, 8).middle]))
        let lines = RoadCentreLines.lines(of: cells)
        let joined = RoadCentreLines.joins(of: cells)
        let forks = cells.filter { (joined[$0]?.count ?? 0) >= 3 }, ends = cells.filter { (joined[$0]?.count ?? 0) == 1 }
        XCTAssertEqual(forks, [cell(10, 6)])
        for line in lines {
            for tip in [line.first!, line.last!] {
                let at = CellPosition(containing: tip)
                XCTAssertEqual(tip, at.middle, "a line begins and ends at a cell's middle")
                XCTAssertTrue(forks.contains(at) || ends.contains(at), "at an end or a fork")
            }
        }
        let tips = Set(lines.flatMap { [$0.first!, $0.last!] })
        for cell in forks.union(ends) { XCTAssertTrue(tips.contains(cell.middle), "\(cell)") }
        XCTAssertEqual(lines.filter { $0.contains(cell(10, 6).middle) }.count, 3, "three arms meet at the fork's middle")
    }

    func testALongCornerStaysAStreetCorner() throws {
        // Five cells east, then five south: the corner at its cell's middle,
        // rounded a quarter cell each side, the arms through the middles.
        let cells = Set((0...4).map { cell(0, $0) } + (1...4).map { cell($0, 4) })
        let line = try XCTUnwrap(RoadCentreLines.lines(of: cells).first)
        let corner = cell(0, 4).middle, quarter = Land.cellLength / 4
        XCTAssertFalse(line.contains(corner), "the corner is cut")
        XCTAssertTrue(line.contains(PlanPoint(x: corner.x - quarter, y: corner.y)))
        XCTAssertTrue(line.contains(PlanPoint(x: corner.x, y: corner.y + quarter)))
        let middle = cell(0, 0).middle.y, column = cell(0, 4).middle.x
        XCTAssertTrue(line.filter { $0.x <= column - quarter }.allSatisfy { $0.y == middle }, "the arm along the cells' middles")
        XCTAssertTrue(line.filter { $0.y >= cell(0, 4).middle.y + quarter }.allSatisfy { $0.x == column })
    }

    // MARK: - The same line everywhere

    func testTheRoadBeingDrawnIsDrawnAsItWillBeLaid() {
        let built = Set((0...9).map { cell(40, $0) })
        let drawn = Set(drag([cell(40, 9).middle, cell(45, 18).middle]))
        let all = built.union(drawn)
        let whole = RoadCentreLines.lines(of: all)
        let preview = RoadCentreLines.lines(of: all, touching: drawn)
        XCTAssertFalse(preview.isEmpty)
        for line in preview { XCTAssertTrue(whole.contains(line), "the faint line is the laid one") }
        // A branch from the middle of a built road splits it at the fork.
        let branch = Set(drag([cell(40, 4).middle, cell(36, 0).middle])).subtracting(built)
        let forked = built.union(branch)
        let forkedWhole = RoadCentreLines.lines(of: forked)
        for line in RoadCentreLines.lines(of: forked, touching: branch) { XCTAssertTrue(forkedWhole.contains(line)) }
    }

    func testARingIsTheSameLineFromAnyCell() {
        let ring = Set((0...5).map { cell(0, $0) } + (1...5).map { cell($0, 5) } + (0...4).map { cell(5, $0) } + (1...4).map { cell($0, 0) })
        let whole = RoadCentreLines.lines(of: ring)
        XCTAssertEqual(whole.count, 1)
        XCTAssertEqual(RoadCentreLines.lines(of: ring, touching: [cell(3, 5)]), whole)
    }
}

/// Decision 476's lines through the cells' middles, before decision 821,
/// to show what they were.
private enum RoadCentreLinesBefore {
    static func lines(of cells: Set<CellPosition>) -> [[PlanPoint]] {
        [cells.sorted { ($0.column, $0.row) < ($1.column, $1.row) }.map(\.middle)]
    }
}

/// A small seeded generator, so the random roads are the same every run.
private struct Generator {
    var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((state >> 33) % span)
    }
}
