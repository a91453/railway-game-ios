import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Taiwan's ground height (ARCHITECTURE decision 124): the app's heights
/// file, read a row at a time, the corners it gives GameCore's blocks, and
/// the height the network tool shows at the ends it picked.
@MainActor
final class HeightGridTests: XCTestCase {
    private static let grid: HeightGrid = {
        do {
            return try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// A small file written as `build_slope_grid.py` writes one: each row's
    /// heights as varint differences, with runs of zeros.
    private static func file(north: Double = 1, west: Double = 0, cellDegrees: Double = 0.5, rows heights: [[Int]]) -> Data {
        var bytes = Array("TWHG".utf8)
        func little(_ value: UInt64, _ size: Int) {
            bytes += (0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
        }
        func varint(_ value: Int, into out: inout [UInt8]) {
            var value = value
            while value >= 0x80 {
                out.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            out.append(UInt8(value))
        }
        var body: [UInt8] = [], offsets = [0]
        for row in heights {
            var previous = 0, index = 0
            while index < row.count {
                let difference = row[index] - previous
                if difference == 0 {
                    var end = index
                    while end < row.count, row[end] == previous { end += 1 }
                    body.append(0)
                    varint(end - index, into: &body)
                    index = end
                } else {
                    varint((difference << 1) ^ (difference >> 63), into: &body)
                    previous = row[index]
                    index += 1
                }
            }
            offsets.append(body.count)
        }
        little(1, 2)
        little(0, 2)
        little(north.bitPattern, 8)
        little(west.bitPattern, 8)
        little(cellDegrees.bitPattern, 8)
        little(UInt64(heights.count), 4)
        little(UInt64(heights.first?.count ?? 0), 4)
        for offset in offsets { little(UInt64(offset), 4) }
        return Data(bytes + body)
    }

    // MARK: - The file

    func testASmallFileReadsItsRowsAndBlendsBetweenTheirMiddles() throws {
        let grid = try HeightGrid(data: Self.file(rows: [[0, 0, 300, -7], [5, 5, 5, 200]]))
        XCTAssertEqual(grid.row(0), [0, 0, 300, -7])
        XCTAssertEqual(grid.row(1), [5, 5, 5, 200])
        // Cell (0, 2)'s middle lies at 0.75° N, 1.25° E.
        XCTAssertEqual(grid.height(latitude: 0.75, longitude: 1.25), 300)
        // Halfway between (0, 2) and (0, 3): 146.5; and halfway down to row 1
        // too: (300 − 7 + 5 + 200) / 4.
        XCTAssertEqual(grid.height(latitude: 0.75, longitude: 1.5), 146.5)
        XCTAssertEqual(grid.height(latitude: 0.5, longitude: 1.5), 124.5)
        // Outside the grid is the sea.
        XCTAssertEqual(grid.height(latitude: 5, longitude: 5), 0)
        XCTAssertEqual(grid.height(latitude: 1.25, longitude: 1.25), 0, "a cell north of the grid, above the 300 m one, is the sea")
    }

    func testAFileOutOfShapeIsRefused() throws {
        var good = [UInt8](Self.file(rows: [[1, 2]]))
        XCTAssertNoThrow(try HeightGrid(data: Data(good)))
        var magic = good
        magic[0] = UInt8(ascii: "X")
        XCTAssertThrowsError(try HeightGrid(data: Data(magic)))
        var version = good
        version[4] = 2
        XCTAssertThrowsError(try HeightGrid(data: Data(version)))
        XCTAssertThrowsError(try HeightGrid(data: Data(good.dropLast())), "the offsets say a byte more")
        XCTAssertThrowsError(try HeightGrid(data: Data(good.prefix(20))))
        // A row whose bytes do not make its columns reads as nothing, and
        // as the sea.
        good.removeLast()
        good.append(0x80)
        let broken = try HeightGrid(data: Data(good))
        XCTAssertNil(broken.row(0))
        XCTAssertEqual(broken.height(latitude: 0.75, longitude: 0.25), 0)
    }

    /// The app's file, against the heights the Ministry of the Interior and
    /// the mountains' own signs give.
    func testTheBundledFileHasTaiwansMountains() {
        let grid = Self.grid
        XCTAssertEqual(grid.rows, 9_296)
        XCTAssertEqual(grid.columns, 8_064)
        XCTAssertEqual(grid.height(latitude: 23.5103, longitude: 120.8050), 2_216, accuracy: 30, "Alishan station, 2,216 m")
        XCTAssertEqual(grid.height(latitude: 24.1376, longitude: 121.2756), 3_275, accuracy: 30, "Wuling on Hehuanshan, 3,275 m")
        XCTAssertGreaterThan(grid.height(latitude: 23.4700, longitude: 120.9573), 3_800, "Yushan, 3,952 m, its top shaved by the median")
        XCTAssertEqual(grid.height(latitude: 25.0478, longitude: 121.5170), 15, accuracy: 15, "Taipei Main Station, some 7 m, a city of a surface model")
        XCTAssertEqual(grid.height(latitude: 24.0, longitude: 119.9), 0, "the strait")
    }

    // MARK: - Blocks for GameCore

    /// The corners of a new game round Alishan: two blocks side by side
    /// give their shared edge the same heights, and GameCore reads them.
    func testBlocksShareTheirEdgesAndGameCoreReadsThem() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 23.5103, longitudeDegrees: 120.8050))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let middle = LandBlock(row: 8, column: 8)
        let blocks = Self.grid.ground(of: [LandBlock(row: 8, column: 9), middle], frame: frame)
        XCTAssertEqual(blocks.map(\.block), [middle, LandBlock(row: 8, column: 9)], "by row and then column")
        let side = GroundBlock.side
        for i in 0..<side {
            XCTAssertEqual(blocks[0].heights[i * side + side - 1], blocks[1].heights[i * side], "corner row \(i) of the shared edge")
        }
        // The map's middle is the anchor, the station: its corner (0, 0) of
        // block (8, 8).
        XCTAssertEqual(Double(blocks[0].heights[0]), 2_216, accuracy: 30)

        var world = GameWorld.newGame(anchor: anchor)
        try world.setGround(blocks)
        let point = PlanPoint(x: 8 * Land.blockLength, y: 8 * Land.blockLength)
        XCTAssertEqual(world.groundHeight(at: point), Int64(blocks[0].heights[0]) * WorldCoordinate.unitsPerMetre)
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 0, y: 0)), "a block not read")
    }

    // MARK: - The network tool

    func testTheNetworkToolShowsTheGroundAtItsEnds() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 23.5103, longitudeDegrees: 120.8050))
        let session = GameSession(world: GameWorld.newGame(anchor: anchor), language: .traditionalChinese)
        session.heights = Self.grid
        session.selectTool(.network)
        let middle = GameWorld.newGameBounds.width / 2
        session.tapNetwork(at: PlanPoint(x: middle, y: middle), reach: 512)
        let start = Int(Self.grid.height(at: PlanPoint(x: middle, y: middle), frame: RealWorldFrame(world: session.world)!).rounded())
        XCTAssertEqual(session.networkDraftText(), "從新節點（地面海拔 \(start) 公尺）開始。請點終點，或從起點拖曳過去。")
        session.tapNetwork(at: PlanPoint(x: middle + 8_192, y: middle), reach: 512)
        let end = Int(Self.grid.height(at: PlanPoint(x: middle + 8_192, y: middle), frame: RealWorldFrame(world: session.world)!).rounded())
        XCTAssertNotEqual(start, end, "128 m along a mountainside")
        XCTAssertEqual(session.networkDraftText(), "一段新的軌道 · 地面海拔 \(start) → \(end) 公尺")

        // A blank map has no ground to show.
        let blank = GameSession(world: GameWorld.newGame(), language: .traditionalChinese)
        blank.heights = Self.grid
        blank.selectTool(.network)
        blank.tapNetwork(at: PlanPoint(x: middle, y: middle), reach: 512)
        XCTAssertEqual(blank.networkDraftText(), "從新節點開始。請點終點，或從起點拖曳過去。")
    }
}
