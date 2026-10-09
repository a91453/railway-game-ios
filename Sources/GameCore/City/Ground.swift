// The ground's height (ARCHITECTURE decision 124, the first step of
// docs/research/TERRAIN_HEIGHT_DESIGN.md): how high the ground stands
// above the sea, under a real-world map's track. It is kept where it is
// read, a block of land (``LandBlock``, 1,024 m) at a time, as the height
// in whole metres at each corner of the block's 64 m cells: 17 corners a
// side, so a block holds its own east and south edges (which its
// neighbours hold too) and gives the height anywhere in it alone. Between
// the corners the height is the bilinear blend of the cell's four, in
// world units, worked out once in whole numbers and rounded half up, the
// same on every platform.
//
// Where the heights come from (a real-world map's DEM, Copernicus GLO-30)
// is GamePresentation's (`HeightGrid`), as the water is (`WaterGrid`); a
// block's corners come in through ``GameWorld/setGround(_:)``. A world that
// has read none, every blank map and every save before version 27, is flat
// at 0 m, as the railway has always taken it to be (decision 30).
//
// Since the design's second step a world *has ground* from the moment it
// reads its first block, or from ``GameWorld/mapGround()``, which a new
// real-world game calls before it has any track: from then on the ground
// is unknown wherever no block has been read, track is measured from it
// (``TrackSectionKind``), and its water needs a bridge or a tunnel. A
// world without ground keeps Stage S4's rules.
//
// The references hold no ground the game can use (gap): the `Railway/`
// site's 3D view reads Mapterhorn DEM tiles that are not in the snapshot,
// and `Simulator/`'s layout terrain is cells of whole layers for a model
// railway. The corner lattice is OpenTTD's idea (heights at tile corners;
// GPL, read for the idea only).

/// The ground's height over one block (decision 124): the corners of its
/// 64 m cells, ``GroundBlock/side`` a side from its north-west corner, row
/// by row from the north, in whole metres above the sea.
public struct GroundBlock: Hashable, Sendable {
    /// Corners along a block's side: one more than its cells.
    public static let side = Land.blockCells + 1

    public let block: LandBlock
    /// ``side`` × ``side`` heights, in metres.
    public let heights: [Int16]

    /// The block's heights, or `nil` unless there are ``side`` × ``side``.
    public init?(block: LandBlock, heights: [Int16]) {
        guard heights.count == Self.side * Self.side else { return nil }
        self.block = block
        self.heights = heights
    }

    /// The height at corner `row`, `column` of the block, in metres.
    func corner(row: Int, column: Int) -> Int64 {
        Int64(heights[row * Self.side + column])
    }
}

/// The world's ground (decision 124): the blocks whose heights it has read.
public struct Ground: Hashable, Sendable {
    /// The heights read, by block.
    public private(set) var blocks: [LandBlock: GroundBlock] = [:]
    /// Whether the world has ground: its heights are real where read and
    /// unknown elsewhere, and track is measured from them. A world without
    /// ground is flat at 0 m.
    public private(set) var isMapped = false

    public init() {}

    public var isEmpty: Bool {
        blocks.isEmpty
    }

    /// The blocks read, by row and then column.
    public var sortedBlocks: [GroundBlock] {
        blocks.values.sorted { $0.block < $1.block }
    }

    /// The ground's height at `point`, in world units, or `nil` where its
    /// block has not been read. `point` must not be west or north of the
    /// world's origin.
    public func height(at point: PlanPoint) -> Int64? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let cell = Land.cellLength
        let block = LandBlock(row: Int(point.y / Land.blockLength), column: Int(point.x / Land.blockLength))
        guard let heights = blocks[block] else { return nil }
        let column = Int(point.x % Land.blockLength / cell), row = Int(point.y % Land.blockLength / cell)
        let dx = point.x % cell, dy = point.y % cell
        // The four corners weighted by the point's place in the cell, out of
        // cell² (2^24); in metres, so the sum is at most 2^15 · 2^24.
        let sum = heights.corner(row: row, column: column) * (cell - dx) * (cell - dy)
            + heights.corner(row: row, column: column + 1) * dx * (cell - dy)
            + heights.corner(row: row + 1, column: column) * (cell - dx) * dy
            + heights.corner(row: row + 1, column: column + 1) * dx * dy
        // Metres to world units, and the weights out: × 64 / 2^24, rounded
        // half up (towards +∞ on a tie, below the sea too).
        let divisor = cell * cell / WorldCoordinate.unitsPerMetre
        return Self.floorDivision(sum + divisor / 2, by: divisor)
    }

    /// Adds `fresh`, none of them read yet; the world has ground from now
    /// on.
    mutating func add(_ fresh: [GroundBlock]) {
        isMapped = true
        for block in fresh {
            blocks[block.block] = block
        }
    }

    /// Why the ground breaks a rule in a world of `bounds`, or `nil`: every
    /// block in the world.
    func problem(in bounds: WorldBounds) -> String? {
        let rows = Land.blockRows(in: bounds), columns = Land.blockColumns(in: bounds)
        guard blocks.keys.allSatisfy({ (0..<rows).contains($0.row) && (0..<columns).contains($0.column) }) else {
            return "Ground lies outside the world."
        }
        return nil
    }

    private static func floorDivision(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }
}

extension GameWorld {
    /// Adds the heights of `blocks`, in any order (decision 124): a
    /// real-world map's ground, from GamePresentation's `HeightGrid`. A
    /// block's ground is read once and does not change. The world has
    /// ground from now on.
    ///
    /// - Throws: ``GameError/invalidGround`` when `blocks` is empty, or
    ///   lists a block outside the world, twice, or already read; or when a
    ///   world without ground has track, as ``mapGround()``.
    public mutating func setGround(_ blocks: [GroundBlock]) throws(GameError) {
        let rows = Land.blockRows(in: bounds), columns = Land.blockColumns(in: bounds)
        let sorted = blocks.sorted { $0.block < $1.block }
        guard ground.isMapped || network.nodes.isEmpty, !sorted.isEmpty,
              sorted.allSatisfy({
                  (0..<rows).contains($0.block.row) && (0..<columns).contains($0.block.column) && ground.blocks[$0.block] == nil
              }),
              zip(sorted, sorted.dropFirst()).allSatisfy({ $0.block < $1.block })
        else { throw .invalidGround }
        ground.add(sorted)
    }

    /// Gives a world ground before it has read any (decision 124): a new
    /// real-world game, whose blocks the app reads as track comes to them.
    ///
    /// - Throws: ``GameError/invalidGround`` when the world has ground
    ///   already or has track: track built on a flat world is not measured
    ///   from ground that came later.
    public mutating func mapGround() throws(GameError) {
        guard !ground.isMapped, network.nodes.isEmpty else { throw .invalidGround }
        ground.add([])
    }

    /// The ground's height at `point`, in world units (decision 124): 0 m
    /// anywhere in a world without ground (a blank map, or a save before
    /// version 27); otherwise `nil` outside the world or the blocks read.
    public func groundHeight(at point: PlanPoint) -> Int64? {
        guard bounds.contains(point) else { return nil }
        return ground.isMapped ? ground.height(at: point) : 0
    }

    /// The blocks a world with ground has not read whose ground `points`
    /// stand on (decision 124), by row and then column: what the app reads
    /// before it builds there. Empty in a world without ground.
    public func missingGroundBlocks(under points: [PlanPoint]) -> [LandBlock] {
        guard ground.isMapped else { return [] }
        var missing: Set<LandBlock> = []
        for point in points where bounds.contains(point) {
            let block = LandBlock(row: Int(point.y / Land.blockLength), column: Int(point.x / Land.blockLength))
            if ground.blocks[block] == nil { missing.insert(block) }
        }
        return missing.sorted()
    }
}

// MARK: - Codable

extension GroundBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case row, column, heights
    }

    /// Decodes `{"row", "column", "heights": [m, …]}`, ``side`` × ``side``
    /// heights row by row.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let row = try container.decode(Int.self, forKey: .row), column = try container.decode(Int.self, forKey: .column)
        guard row >= 0, column >= 0,
              let block = Self(block: LandBlock(row: row, column: column), heights: try container.decode([Int16].self, forKey: .heights))
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .heights, in: container, debugDescription: "A ground block lies in the world and has \(Self.side * Self.side) heights."
            )
        }
        self = block
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(block.row, forKey: .row)
        try container.encode(block.column, forKey: .column)
        try container.encode(heights, forKey: .heights)
    }
}

extension Ground: Codable {
    private enum CodingKeys: String, CodingKey {
        case blocks
    }

    /// Decodes `{"blocks": [block, …]}` by row and then column, none twice;
    /// the world checks they lie in its bounds. Present, the world has
    /// ground, even with no block read yet (save version 28).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([GroundBlock].self, forKey: .blocks)
        guard zip(list, list.dropFirst()).allSatisfy({ $0.block < $1.block }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .blocks, in: container, debugDescription: "Ground lists its blocks in order, none twice."
            )
        }
        add(list)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sortedBlocks, forKey: .blocks)
    }
}
