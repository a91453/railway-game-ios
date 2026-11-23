import GameCore

// Decision 943: the heights file changed under saved games. A world keeps
// the ground it has read (decision 124), so a save made before the file's
// ground became the Ministry of the Interior's terrain model holds blocks
// of the surface model it replaced, some 6 m higher over the island and
// tens of metres higher in a city; a block read next to them from the new
// file stood a step below them along the 1 km line between the two.
//
// A block read beside blocks the world holds is therefore joined to them:
// it takes their heights along the edges and at the corners it shares with
// them, and what those stand above (or below) the file fades across the
// block to nothing at its far side. Where the world's blocks are the
// file's own, every new game and every save since, nothing stands above
// anything and the block is the file's, to the metre.

extension HeightGrid {
    /// ``ground(of:frame:)``, each block joined to the blocks of `read`
    /// round it and to those before it in the list (decision 943).
    func ground(of blocks: [LandBlock], frame: RealWorldFrame, joining read: [LandBlock: GroundBlock]) -> [GroundBlock] {
        var read = read
        return ground(of: blocks, frame: frame).map { fresh in
            let joined = Self.joined(fresh, to: read)
            read[joined.block] = joined
            return joined
        }
    }

    /// `fresh`, a block as the file has it, joined to the blocks of `read`
    /// round it (decision 943): along an edge it shares with one, that
    /// block's heights; along any other edge, the file's plus what the
    /// edge's two ends were moved by, one fading into the other; inside,
    /// the four edges blended (a Coons patch), in whole numbers so every
    /// platform joins alike. Blocks read in any order come out the same,
    /// and the edge between two of them has one set of heights.
    static func joined(_ fresh: GroundBlock, to read: [LandBlock: GroundBlock]) -> GroundBlock {
        let side = GroundBlock.side, last = side - 1
        let block = fresh.block
        func neighbour(_ rows: Int, _ columns: Int) -> GroundBlock? {
            guard block.row + rows >= 0, block.column + columns >= 0 else { return nil }
            return read[LandBlock(row: block.row + rows, column: block.column + columns)]
        }
        func height(_ block: GroundBlock, _ row: Int, _ column: Int) -> Int {
            Int(block.heights[row * side + column])
        }
        let north = neighbour(-1, 0), south = neighbour(1, 0), west = neighbour(0, -1), east = neighbour(0, 1)
        // How far a corner was moved: by a block along either edge that
        // meets there, else by the one across the corner.
        func moved(row: Int, column: Int, along: [(GroundBlock?, Int, Int)]) -> Int {
            for (block, itsRow, itsColumn) in along {
                if let block { return height(block, itsRow, itsColumn) - height(fresh, row, column) }
            }
            return 0
        }
        let northWest = moved(row: 0, column: 0, along: [(north, last, 0), (west, 0, last), (neighbour(-1, -1), last, last)])
        let northEast = moved(row: 0, column: last, along: [(north, last, last), (east, 0, 0), (neighbour(-1, 1), last, 0)])
        let southWest = moved(row: last, column: 0, along: [(south, 0, 0), (west, last, last), (neighbour(1, -1), 0, last)])
        let southEast = moved(row: last, column: last, along: [(south, 0, last), (east, last, 0), (neighbour(1, 1), 0, 0)])
        // Each edge's moves, in sixteenths of a metre.
        func edge(_ block: GroundBlock?, from: Int, to: Int, its: (Int) -> (Int, Int), mine: (Int) -> (Int, Int)) -> [Int] {
            (0..<side).map { index in
                if let block {
                    let (itsRow, itsColumn) = its(index), (row, column) = mine(index)
                    return (height(block, itsRow, itsColumn) - height(fresh, row, column)) * last
                }
                // To the whole metre, as the heights a neighbour read
                // later will find here: so the order does not matter.
                let move = from * (last - index) + to * index + last / 2
                return (move >= 0 ? move / last : -((last - 1 - move) / last)) * last
            }
        }
        let northEdge = edge(north, from: northWest, to: northEast, its: { (last, $0) }, mine: { (0, $0) })
        let southEdge = edge(south, from: southWest, to: southEast, its: { (0, $0) }, mine: { (last, $0) })
        let westEdge = edge(west, from: northWest, to: southWest, its: { ($0, last) }, mine: { ($0, 0) })
        let eastEdge = edge(east, from: northEast, to: southEast, its: { ($0, 0) }, mine: { ($0, last) })
        guard (northEdge + southEdge + westEdge + eastEdge).contains(where: { $0 != 0 }) else { return fresh }
        let whole = last * last
        var heights = fresh.heights
        for row in 0..<side {
            for column in 0..<side {
                let edges = (last - row) * northEdge[column] + row * southEdge[column]
                    + (last - column) * westEdge[row] + column * eastEdge[row]
                let corners = (last - column) * (last - row) * northWest + column * (last - row) * northEast
                    + (last - column) * row * southWest + column * row * southEast
                // Metres times `whole`; rounded half up.
                let move = (edges - corners + whole / 2).quotientAndRemainder(dividingBy: whole)
                let metres = move.remainder < 0 ? move.quotient - 1 : move.quotient
                heights[row * side + column] = Int16(clamping: Int(heights[row * side + column]) + metres)
            }
        }
        return GroundBlock(block: block, heights: heights) ?? fresh
    }
}

extension GameWorld {
    /// The blocks that join the ground a save holds to the heights file
    /// (decision 943): each block next to one the world holds whose
    /// heights the file would not meet, joined to it. Once they are read
    /// in, the ground the world has not read (which the 3D map draws from
    /// the file) begins a block away, where the two agree. None in a world
    /// whose ground is the file's, or without ground.
    func groundJoining(_ heights: HeightGrid) -> [GroundBlock] {
        guard ground.isMapped, !ground.blocks.isEmpty, let frame = RealWorldFrame(world: self) else { return [] }
        let rows = Land.blockRows(in: bounds), columns = Land.blockColumns(in: bounds)
        var beside: Set<LandBlock> = []
        for block in ground.blocks.keys {
            for row in max(block.row - 1, 0)...min(block.row + 1, rows - 1) {
                for column in max(block.column - 1, 0)...min(block.column + 1, columns - 1) {
                    let other = LandBlock(row: row, column: column)
                    if ground.blocks[other] == nil { beside.insert(other) }
                }
            }
        }
        let wanted = beside.sorted()
        let fresh = heights.ground(of: wanted, frame: frame)
        let joined = heights.ground(of: wanted, frame: frame, joining: ground.blocks)
        return zip(fresh, joined).filter { $0 != $1 }.map(\.1)
    }
}
