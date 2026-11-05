import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585 續 (FERRYPIER): the author could not put a pier anywhere on
/// Cijin ("整個旗津都沒辦法按"). Measured on the real map of Kaohsiung
/// harbour: the game's water (``WaterGrid``, 64 m cells) and the water the
/// map draws (the base map's, `taiwan.pmtiles`) agree but for a sliver one
/// cell wide along the shore, so the harbour and its channels are water
/// (not cause 2); but the land a pier can stand on is that one cell along
/// it, and a finger on the drawn shore lands on it about two times in
/// three (cause 1). A tap now finds the nearest such cell within
/// ``RealFerry/snapCells``, as the real ferries' piers do.
@MainActor
final class FerryPierSnapTests: XCTestCase {
    nonisolated private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// A new game round Cijin, with Taiwan's real water.
    private func kaohsiung() throws -> (world: GameWorld, frame: RealWorldFrame) {
        let grid = try WaterGrid(data: Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.59, longitudeDegrees: 120.29))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        var world = GameWorld.newGame(anchor: anchor, water: grid.cells(frame: frame, bounds: GameWorld.newGameBounds))
        world.setEconomyMode(.management)
        return (world, frame)
    }

    private func cell(_ latitude: Double, _ longitude: Double, _ frame: RealWorldFrame) -> CellPosition {
        let (x, y) = frame.worldPosition(latitude: latitude, longitude: longitude)
        return CellPosition(containing: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())))
    }

    /// The shore the map marks is exactly the cells a pier can stand on.
    func testTheMarkedShoreIsEveryPierCell() throws {
        var small = try makeWorld(width: 20 * Land.cellLength, height: 12 * Land.cellLength)
        try small.setWater([CellPosition(row: 0, column: 0), CellPosition(row: 5, column: 4), CellPosition(row: 5, column: 5),
                            CellPosition(row: 6, column: 5), CellPosition(row: 11, column: 19), CellPosition(row: 3, column: 10)])
        for world in [small, try kaohsiung().world] {
            var marked: Set<CellPosition> = []
            for run in world.pierShore() {
                for column in run.columns { XCTAssertTrue(marked.insert(CellPosition(row: run.row, column: column)).inserted, "once") }
            }
            var expected: Set<CellPosition> = []
            for row in 0..<Land.rows(in: world.bounds) {
                for column in 0..<Land.columns(in: world.bounds) where world.isPierCell(row: row, column: column) {
                    expected.insert(CellPosition(row: row, column: column))
                }
            }
            XCTAssertEqual(marked, expected)
            let runs = world.pierShore()
            XCTAssertEqual(runs, runs.sorted { ($0.row, $0.columns.lowerBound) < ($1.row, $1.columns.lowerBound) }, "by row and then column")
        }
    }

    /// The water the map draws round Kaohsiung harbour, by 8 m square: the
    /// base map's water areas (each filled by itself, so the tiles' seams
    /// and the areas' overlaps do not cancel), from cell `first` to `last`.
    private struct DrawnWater {
        static let step = 8.0
        let first: CellPosition
        let columns: Int, rows: Int
        var wet: [[Bool]]

        init(world: GameWorld, frame: RealWorldFrame, first: CellPosition, last: CellPosition) throws {
            let tiles = try BaseMapTiles(data: Data(
                contentsOf: FerryPierSnapTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped
            ))
            let length = Double(Land.cellLength)
            let region = WorldRegion(minX: Double(first.column) * length, minY: Double(first.row) * length,
                                     maxX: Double(last.column + 1) * length, maxY: Double(last.row + 1) * length)
            let base = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: 0, originY: 0)
            let metres = length / Double(WorldCoordinate.unitsPerMetre), step = Self.step
            self.first = first
            columns = Int(Double(last.column - first.column + 1) * metres / step)
            rows = Int(Double(last.row - first.row + 1) * metres / step)
            wet = Array(repeating: Array(repeating: false, count: columns), count: rows)
            let x0 = Double(first.column) * metres, z0 = Double(first.row) * metres
            for area in base.areas where area.cover == .water {
                let points = area.rings.flatMap { $0 }
                guard let top = points.map(\.z).min(), let bottom = points.map(\.z).max() else { continue }
                let j0 = max(0, Int(((top - z0) / step).rounded(.down))), j1 = min(rows - 1, Int(((bottom - z0) / step).rounded(.up)))
                guard j0 <= j1 else { continue }
                for j in j0...j1 {
                    let z = z0 + (Double(j) + 0.5) * step
                    var crossings: [Double] = []
                    for ring in area.rings where ring.count > 2 {
                        for k in ring.indices {
                            let a = ring[k], b = ring[(k + 1) % ring.count]
                            if (a.z <= z) != (b.z <= z) { crossings.append(a.x + (z - a.z) / (b.z - a.z) * (b.x - a.x)) }
                        }
                    }
                    crossings.sort()
                    for k in stride(from: 0, to: crossings.count - 1, by: 2) {
                        let low = max(0, Int(((crossings[k] - x0) / step - 0.5).rounded(.up)))
                        let high = min(columns - 1, Int(((crossings[k + 1] - x0) / step - 0.5).rounded(.down)))
                        if low <= high { for i in low...high { wet[j][i] = true } }
                    }
                }
            }
        }

        /// The cell the square at `i`, `j` lies in.
        func cell(_ i: Int, _ j: Int) -> CellPosition {
            let per = Double(Land.cellLength) / Double(WorldCoordinate.unitsPerMetre) / Self.step
            return CellPosition(row: first.row + Int(Double(j) / per), column: first.column + Int(Double(i) / per))
        }

        /// The squares a finger on the drawn shore lands on: drawn land
        /// within 24 m of drawn water.
        var shoreTaps: [(i: Int, j: Int)] {
            var taps: [(Int, Int)] = []
            for j in 3..<(rows - 3) {
                for i in 3..<(columns - 3) where !wet[j][i] {
                    if (-3...3).contains(where: { dj in (-3...3).contains { di in wet[j + dj][i + di] } }) { taps.append((i, j)) }
                }
            }
            return taps
        }
    }

    /// Cause 2 is small: of the 16,000-odd cells from Gushan to Hongmaogang,
    /// fewer than 2 % are water in the game and land on the map or the
    /// other way, each a cell along the shore. Cause 1 is the author's: a
    /// finger on the drawn shore of Cijin, Gushan or Hongmaogang lands on a
    /// cell a pier can stand on less than three times in four, but within
    /// ``RealFerry/snapCells`` of one 99 % of the time.
    func testTheShoreIsOneCellThinButTheWaterIsTheMapsOwn() throws {
        let (world, frame) = try kaohsiung()
        let first = cell(22.630, 120.255, frame), last = cell(22.540, 120.320, frame)
        let drawn = try DrawnWater(world: world, frame: frame, first: first, last: last)
        let per = Int(Double(Land.cellLength) / Double(WorldCoordinate.unitsPerMetre) / DrawnWater.step)
        var cells = 0, disagree = 0
        for row in first.row...last.row {
            for column in first.column...last.column {
                var wet = 0
                for jj in 0..<per {
                    for ii in 0..<per {
                        let j = (row - first.row) * per + jj, i = (column - first.column) * per + ii
                        if j < drawn.rows, i < drawn.columns, drawn.wet[j][i] { wet += 1 }
                    }
                }
                cells += 1
                if world.terrain.isWater(row: row, column: column) != (wet * 2 > per * per) { disagree += 1 }
            }
        }
        print("FERRYPIER cells \(cells), game water and drawn water disagree on \(disagree)")
        XCTAssertLessThan(Double(disagree), 0.02 * Double(cells))

        let places: [(name: String, latitude: Double, longitude: Double)] = [
            ("Cijin", 22.600, 120.275), ("Gushan", 22.620, 120.268), ("Hongmaogang", 22.552, 120.305)
        ]
        let taps = drawn.shoreTaps
        for place in places {
            let centre = cell(place.latitude, place.longitude, frame)
            let near = taps.map { drawn.cell($0.i, $0.j) }.filter { abs($0.row - centre.row) <= 8 && abs($0.column - centre.column) <= 8 }
            let onPier = near.filter { world.isPierCell(row: $0.row, column: $0.column) }.count
            let onWater = near.filter { world.terrain.isWater(row: $0.row, column: $0.column) }.count
            let snapped = near.filter { world.nearestPierCell(to: $0, within: RealFerry.snapCells) != nil }.count
            print("FERRYPIER \(place.name): \(near.count) taps on the drawn shore, \(onPier) on a pier cell, \(onWater) on the game's water, \(snapped) within \(RealFerry.snapCells) cells of one")
            XCTAssertGreaterThan(near.count, 100, place.name)
            XCTAssertLessThan(Double(onPier), 0.75 * Double(near.count), place.name)
            XCTAssertGreaterThanOrEqual(Double(snapped), 0.99 * Double(near.count), place.name)
        }
    }

    /// On the real map, a tap on Cijin's drawn shore that misses the one
    /// cell puts a pier on the nearest; one in the middle of the city says
    /// where the shore is.
    func testATapOnCijinsShorePutsAPier() throws {
        let (world, frame) = try kaohsiung()
        let first = cell(22.610, 120.265, frame), last = cell(22.590, 120.285, frame)
        let drawn = try DrawnWater(world: world, frame: frame, first: first, last: last)
        let miss = try XCTUnwrap(drawn.shoreTaps.map { drawn.cell($0.i, $0.j) }.first {
            !world.terrain.isWater(row: $0.row, column: $0.column) && !world.isPierCell(row: $0.row, column: $0.column)
        }, "a tap on the drawn shore that is not a pier cell: what the author met")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        XCTAssertFalse(try XCTUnwrap(session.ferryMapOverlay).shore.isEmpty, "the mode marks the shore")
        session.tapBusTool(at: miss.middle, reach: 0)
        let pier = try XCTUnwrap(session.ferryDraft.first)
        XCTAssertTrue(world.isPierCell(row: pier.row, column: pier.column))
        XCTAssertLessThanOrEqual(max(abs(pier.row - miss.row), abs(pier.column - miss.column)), RealFerry.snapCells)

        // A cell of the city east of the harbour with no shore near it.
        let east = cell(22.615, 120.320, frame)
        let inland = try XCTUnwrap((0..<40).lazy.map { CellPosition(row: east.row, column: east.column + $0) }.first {
            world.nearestPierCell(to: $0, within: RealFerry.snapCells) == nil
        })
        session.tapBusTool(at: inland.middle, reach: 0)
        XCTAssertEqual(session.ferryDraft, [pier])
        XCTAssertEqual(session.message?.kind, .failure)
        let text = try XCTUnwrap(session.message?.text)
        XCTAssertTrue(text.hasPrefix("碼頭要蓋在岸邊，就是淡藍色的格子：") || text.hasPrefix("這附近沒有岸邊"), text)
        print("FERRYPIER inland tap: \(text)")
    }
}
