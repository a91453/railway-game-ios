import Foundation
@testable import GameCore
import XCTest

/// The ground's height (ARCHITECTURE decision 124): the corners of each
/// block's 64 m cells, in whole metres, read a block at a time, and the
/// bilinear height between them in world units. Every number below is
/// worked out by hand.
final class GroundTests: XCTestCase {
    /// 64 × 64 cells, 4 × 4 blocks of land.
    private static let bounds = try! WorldBounds(width: 262_144, height: 262_144)
    private static let side = GroundBlock.side

    private func world() -> GameWorld {
        GameWorld(bounds: Self.bounds, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
    }

    /// A block whose corner `row`, `column` stands `height(row, column)`
    /// metres high.
    private func block(_ row: Int, _ column: Int, _ height: (Int, Int) -> Int) -> GroundBlock {
        let heights = (0..<Self.side).flatMap { r in (0..<Self.side).map { c in Int16(height(r, c)) } }
        return GroundBlock(block: LandBlock(row: row, column: column), heights: heights)!
    }

    // MARK: - Heights

    func testAWorldWithoutGroundIsFlat() {
        let world = world()
        XCTAssertTrue(world.ground.isEmpty)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 0, y: 0)), 0)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 200_000, y: 100_000)), 0)
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 262_144, y: 0)), "outside the world")
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: -1, y: 0)))
    }

    /// Corner (r, c) of block (0, 0) is 10 r + c metres: a plane, which the
    /// blend gives exactly, (10 y + x) / 64 world units.
    func testTheHeightBlendsTheCellsFourCorners() throws {
        var world = world()
        try world.setGround([block(0, 0) { 10 * $0 + $1 }])
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 0, y: 0)), 0)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 4_096, y: 0)), 64, "a corner of 1 m")
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 0, y: 4_096)), 640)
        // (10 · 1,024 + 2,048) / 64 = 192: a quarter of the way to 10 m and
        // half of the way to 1 m, 3 m.
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 2_048, y: 1_024)), 192)
        // The block's far corner, 16 m east and 160 m north… of its last
        // cell: (10 · 61,440 + 65,535) / 64 = 10,623.98…, 10,624.
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 65_535, y: 61_440)), 10_624)
        // Rounded half up: 31 / 64 is 0, 32 / 64 is 1.
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 31, y: 0)), 0)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 32, y: 0)), 1)
        // The next block has not been read.
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 65_536, y: 0)))
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 0, y: 65_536)))
    }

    /// One corner high in a flat cell: the blend is not a plane, and the
    /// middle of the cell has a quarter of it.
    func testACellIsBilinearNotFlat() throws {
        var world = world()
        try world.setGround([block(1, 2) { $0 == 1 && $1 == 1 ? 64 : 0 }])
        let x0: Int64 = 2 * 65_536, y0: Int64 = 65_536
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: x0 + 2_048, y: y0 + 2_048)), 1_024, "16 m, a quarter of 64 m")
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: x0 + 4_096, y: y0 + 4_096)), 4_096)
        // Three quarters of the way both ways: 64 m · 9 / 16 = 36 m.
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: x0 + 3_072, y: y0 + 3_072)), 2_304)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: x0 + 8_192, y: y0 + 8_192)), 0, "the next cell is flat")
    }

    /// Below the sea a tie still rounds up: −1 m at a corner, the others 0.
    func testBelowTheSeaHalfRoundsUp() throws {
        var world = world()
        try world.setGround([block(0, 0) { $0 == 0 && $1 == 0 ? -1 : 0 }])
        // −(4,096 − x) / 64: −32 / 64 is −0.5, 0; −33 / 64 is −1.
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 4_064, y: 0)), 0)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 4_063, y: 0)), -1)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 0, y: 0)), -64)
    }

    /// A block holds its own east and south edges: a point on the line
    /// between two blocks is the next block's, and each reads alone.
    func testABlockHoldsItsOwnEdges() throws {
        var world = world()
        try world.setGround([block(0, 1) { _, _ in 5 }])
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 65_536, y: 0)), 320, "the west edge of block (0, 1)")
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 131_071, y: 65_535)), 320)
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 65_535, y: 0)), "block (0, 0) is not read")
        try world.setGround([block(0, 0) { _, _ in 0 }, block(3, 3) { _, _ in 3_000 }])
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 65_535, y: 0)), 0)
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 262_143, y: 262_143)), 192_000, "3,000 m in the last block")
        XCTAssertEqual(world.ground.sortedBlocks.map(\.block), [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1), LandBlock(row: 3, column: 3)])
    }

    // MARK: - Refusals

    func testBadGroundIsRefusedAndChangesNothing() throws {
        var world = world()
        try world.setGround([block(0, 0) { _, _ in 1 }])
        let before = world
        for bad in [
            [],
            [block(4, 0) { _, _ in 1 }],
            [block(0, 4) { _, _ in 1 }],
            [block(1, 1) { _, _ in 1 }, block(1, 1) { _, _ in 2 }],
            [block(1, 1) { _, _ in 1 }, block(0, 0) { _, _ in 1 }],
        ] as [[GroundBlock]] {
            XCTAssertThrowsError(try world.setGround(bad)) { XCTAssertEqual($0 as? GameError, .invalidGround) }
            XCTAssertEqual(world, before, "a refused command changes nothing")
        }
        XCTAssertNil(GroundBlock(block: LandBlock(row: 0, column: 0), heights: Array(repeating: 0, count: 256)), "16 × 16 is a block's cells, not its corners")
        XCTAssertNil(GroundBlock(block: LandBlock(row: 0, column: 0), heights: Array(repeating: 0, count: 290)))
    }

    // MARK: - Saving

    func testTheGroundIsSavedAndBadGroundIsRefused() throws {
        var world = world()
        try world.setGround([block(2, 1) { $0 - $1 }, block(0, 3) { _, _ in -7 }])
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let saved = try XCTUnwrap((object["world"] as? [String: Any])?["ground"] as? [String: Any])
        let blocks = try XCTUnwrap(saved["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.map { [$0["row"] as? Int, $0["column"] as? Int] }, [[0, 3], [2, 1]], "by row and then column")
        XCTAssertEqual((blocks[1]["heights"] as? [Int])?.prefix(3), [0, -1, -2])
        XCTAssertEqual((blocks[1]["heights"] as? [Int])?.count, 289)
        // A world without ground writes none.
        let flat = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(self.world())) as? [String: Any])
        XCTAssertNil(flat["ground"])

        let heights = "[" + Array(repeating: "0", count: 289).joined(separator: ",") + "]"
        let base = String(decoding: try JSONEncoder().encode(self.world()), as: UTF8.self).dropLast()
        func decode(_ ground: String) throws -> GameWorld {
            try JSONDecoder().decode(GameWorld.self, from: Data((base + #","ground":\#(ground)}"#).utf8))
        }
        XCTAssertNoThrow(try decode(#"{"blocks":[{"row":3,"column":3,"heights":\#(heights)}]}"#))
        // Since save version 28 a world can have ground with no block read
        // yet (`mapGround()`).
        XCTAssertTrue(try decode(#"{"blocks":[]}"#).ground.isMapped)
        for bad in [
            #"{"blocks":[{"row":4,"column":0,"heights":\#(heights)}]}"#,
            #"{"blocks":[{"row":-1,"column":0,"heights":\#(heights)}]}"#,
            #"{"blocks":[{"row":0,"column":0,"heights":[0]}]}"#,
            #"{"blocks":[{"row":1,"column":0,"heights":\#(heights)},{"row":0,"column":0,"heights":\#(heights)}]}"#,
            #"{"blocks":[{"row":0,"column":0,"heights":\#(heights)},{"row":0,"column":0,"heights":\#(heights)}]}"#,
            #"{"blocks":[{"row":0,"column":0,"heights":[\#(Array(repeating: "40000", count: 289).joined(separator: ","))]}]}"#,
            "null",
        ] {
            XCTAssertThrowsError(try decode(bad), bad)
        }
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures")

    /// The version 26 world (sea, river, steep hillside, house and marina)
    /// with the ground of three of its four blocks read: block (r, c)'s
    /// corner (i, j) stands 100 r + 10 c + i + j metres high, run ten
    /// minutes more.
    static func groundWorld() throws -> GameWorld {
        var world = try SteepSlopeTests.slopeWorld()
        try world.setGround([LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1), LandBlock(row: 1, column: 0)].map { block in
            let heights = (0..<side).flatMap { i in (0..<side).map { j in Int16(100 * block.row + 10 * block.column + i + j) } }
            return GroundBlock(block: block, heights: heights)!
        })
        try world.advance(ticks: 10)
        return world
    }

    /// Version 27 (decision 124): the ground. It saves byte for byte and is
    /// the world the build that wrote it makes. The version 26 save has
    /// none.
    func testVersionTwentySevenKeepsTheGround() throws {
        let url = Self.fixtures.appendingPathComponent("v27-ground-height.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["GROUND_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: try Self.groundWorld())).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 27)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, try Self.groundWorld())
        XCTAssertEqual(world.ground.blocks.count, 3)
        // Block (1, 0)'s corner (2, 3) stands 105 m high: 6,720 units.
        XCTAssertEqual(world.groundHeight(at: PlanPoint(x: 3 * 4_096, y: 65_536 + 2 * 4_096)), 6_720)
        XCTAssertNil(world.groundHeight(at: PlanPoint(x: 70_000, y: 70_000)), "block (1, 1) is not read")
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 27,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))

        let older = try Data(contentsOf: Self.fixtures.appendingPathComponent("v26-steep-slopes.json"))
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: older).world.ground.isEmpty)
    }

    /// A save of version 26 or earlier has no ground: it is flat, as it was.
    func testAnEarlierSaveIsFlat() throws {
        let world = String(decoding: try JSONEncoder().encode(self.world()), as: UTF8.self)
        let saved = try JSONDecoder().decode(SavedGame.self, from: Data(#"{"saveVersion": 26, "world": \#(world)}"#.utf8))
        XCTAssertTrue(saved.world.ground.isEmpty)
        XCTAssertEqual(saved.world.groundHeight(at: PlanPoint(x: 100, y: 100)), 0)
    }
}
