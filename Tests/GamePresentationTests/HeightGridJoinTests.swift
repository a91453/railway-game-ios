import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 943: a block read from the heights file beside blocks a save
/// holds from the file before it joins them, with no step between the two.
@MainActor
final class HeightGridJoinTests: XCTestCase {
    private static let grid: HeightGrid = {
        do {
            return try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let side = GroundBlock.side

    private func block(_ row: Int, _ column: Int, _ height: (Int, Int) -> Int) throws -> GroundBlock {
        let heights = (0..<Self.side).flatMap { i in (0..<Self.side).map { j in Int16(height(i, j)) } }
        return try XCTUnwrap(GroundBlock(block: LandBlock(row: row, column: column), heights: heights))
    }

    private func edge(_ block: GroundBlock, row: Int? = nil, column: Int? = nil) -> [Int16] {
        (0..<Self.side).map { block.heights[(row ?? $0) * Self.side + (column ?? $0)] }
    }

    func testABlockBesideNothingOrBesideTheFilesOwnBlocksIsTheFiles() throws {
        let fresh = try block(4, 4) { 100 + $0 + 2 * $1 }
        XCTAssertEqual(HeightGrid.joined(fresh, to: [:]), fresh)
        // A west neighbour whose east edge is this block's west edge.
        let west = try block(4, 3) { i, j in 100 + i + 2 * (j - 16) }
        XCTAssertEqual(HeightGrid.joined(fresh, to: [west.block: west]), fresh)
    }

    func testABlockTakesItsNeighboursEdgeAndFadesToTheFileAcrossItself() throws {
        let fresh = try block(4, 4) { 100 + $0 + 2 * $1 }
        // The block to the west stands 12 m above the file along the edge.
        let west = try block(4, 3) { i, j in 112 + i + 2 * (j - 16) }
        let joined = HeightGrid.joined(fresh, to: [west.block: west])
        XCTAssertEqual(edge(joined, column: 0), edge(west, column: 16), "the shared edge is the neighbour's")
        XCTAssertEqual(edge(joined, column: 16), edge(fresh, column: 16), "the far edge is the file's")
        for i in 0..<Self.side {
            for j in 0..<Self.side {
                let move = Int(joined.heights[i * Self.side + j]) - Int(fresh.heights[i * Self.side + j])
                // 12 m at the edge, falling evenly to nothing: 12 × (16 − j) / 16, rounded half up.
                XCTAssertEqual(move, (12 * (16 - j) + 8) / 16, "row \(i), column \(j)")
            }
        }
    }

    func testABlockAcrossACornerTakesTheCornerOnly() throws {
        let fresh = try block(4, 4) { _, _ in 50 }
        let northWest = try block(3, 3) { _, _ in 66 }
        let joined = HeightGrid.joined(fresh, to: [northWest.block: northWest])
        XCTAssertEqual(joined.heights[0], 66)
        XCTAssertEqual(joined.heights[8], 58, "halfway along the north edge")
        XCTAssertEqual(joined.heights[16], 50)
        XCTAssertEqual(joined.heights[8 * Self.side + 8], 54, "the middle: a quarter of the corner's 16 m")
        XCTAssertEqual(edge(joined, row: 16), edge(fresh, row: 16))
        XCTAssertEqual(edge(joined, column: 16), edge(fresh, column: 16))
    }

    /// Whichever of two blocks is read first, the edge between them and
    /// the blocks themselves come out the same.
    func testTheOrderBlocksAreReadInDoesNotMatter() throws {
        // The file's blocks agree along the edges they share, as one
        // grid's do; the earlier file's block does not.
        func file(_ row: Int, _ column: Int) throws -> GroundBlock {
            try block(row, column) { i, j in
                let y = row * 16 + i, x = column * 16 + j
                return 10 + (y * 5 + x * 3) % 7 + (y * x) % 4
            }
        }
        let old = try block(4, 4) { i, j in 30 + (i * 7 + j * 3) % 11 }
        let east = try file(4, 5), southEast = try file(5, 5), south = try file(5, 4)
        func read(_ order: [GroundBlock]) -> [LandBlock: GroundBlock] {
            var world = [old.block: old]
            for fresh in order { world[fresh.block] = HeightGrid.joined(fresh, to: world) }
            return world
        }
        let first = read([east, southEast, south])
        XCTAssertEqual(read([south, southEast, east]), first)
        XCTAssertEqual(read([southEast, east, south]), first)
        XCTAssertEqual(read([southEast, south, east]), first)
        XCTAssertEqual(edge(first[east.block]!, column: 0), edge(old, column: 16))
        XCTAssertEqual(edge(first[south.block]!, row: 0), edge(old, row: 16))
        XCTAssertEqual(edge(first[east.block]!, row: 16), edge(first[southEast.block]!, row: 0))
        XCTAssertEqual(edge(first[south.block]!, column: 16), edge(first[southEast.block]!, column: 0))
        XCTAssertEqual(first[southEast.block]!.heights[0], old.heights[Self.side * Self.side - 1], "the corner the three share with it")
    }

    /// A save made on the earlier file: its blocks stand above the file's.
    /// Track built on into the next block reads that block joined to them,
    /// and opening the save reads the ring of blocks round them, after
    /// which the ground not yet read is the file's.
    func testAWorldOnTheEarlierFileIsJoinedToThisOne() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let middle = LandBlock(row: 8, column: 8), east = LandBlock(row: 8, column: 9)
        let file = try XCTUnwrap(Self.grid.ground(of: [middle], frame: frame).first)
        let earlier = try XCTUnwrap(GroundBlock(block: middle, heights: file.heights.map { $0 + 13 }))

        var world = GameWorld.newGame(anchor: anchor)
        try world.setGround([earlier])
        var built = world
        try built.readGround(under: [PlanPoint(x: 9 * Land.blockLength + 64, y: 8 * Land.blockLength + 64)], from: Self.grid)
        let joined = try XCTUnwrap(built.ground.blocks[east])
        let fileEast = try XCTUnwrap(Self.grid.ground(of: [east], frame: frame).first)
        XCTAssertEqual(edge(joined, column: 0), edge(earlier, column: 16), "no step along the line between the two")
        XCTAssertEqual(edge(joined, column: 16), edge(fileEast, column: 16))

        let ring = world.groundJoining(Self.grid)
        XCTAssertEqual(ring.count, 8)
        try world.setGround(ring)
        XCTAssertTrue(world.groundJoining(Self.grid).isEmpty, "the ring's far edges are the file's")
        XCTAssertEqual(world.ground.blocks[east], joined, "as when track read it")

        // A session opening the save does the same, once.
        var saved = GameWorld.newGame(anchor: anchor)
        try saved.setGround([earlier])
        let session = GameSession(world: saved, language: .traditionalChinese)
        session.heights = Self.grid
        XCTAssertEqual(session.world.ground.blocks, world.ground.blocks)

        // A world on this file is left as it is.
        var current = GameWorld.newGame(anchor: anchor)
        try current.setGround([file])
        XCTAssertTrue(current.groundJoining(Self.grid).isEmpty)
        try current.readGround(under: [PlanPoint(x: 9 * Land.blockLength + 64, y: 8 * Land.blockLength + 64)], from: Self.grid)
        XCTAssertEqual(current.ground.blocks[east], fileEast)
    }
}
