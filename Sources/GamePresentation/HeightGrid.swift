import Foundation
import GameCore

// Taiwan's ground height on a real-world map (ARCHITECTURE decision 124):
// the Copernicus DEM (GLO-30; GLO-90 where only that is released) on the
// water file's grid (1.875″, some 58 × 53 m), the 3 × 3 median heights the
// steep slopes are found from, in whole metres; rivers and lakes at their
// surface and the open sea at 0 (decision 132; before it all water was 0,
// a pit in every mountain river). Bundled as
// `Resources/RealWorld/taiwan_heights.dat` by
// `tools/real-world-population/build_slope_grid.py`, whose docstring gives
// the format: each row on its own, as varint differences with runs of
// zeros, so a block's corners read only the rows they need of the
// 9,296 × 8,064 grid (150 MB as plain heights).
//
// Only the presentation reads it: a block's corners go to GameCore through
// `GameWorld.setGround(_:)`, and the world saves them, so a save does not
// depend on the file. The heights between the grid's cells are the
// bilinear blend of the four whose middles surround the point, in
// floating point; GameCore gets the corners rounded to whole metres.

/// The ground's height over a grid of Taiwan (decision 124).
public struct HeightGrid: Sendable {
    let north: Double
    let west: Double
    let cellDegrees: Double
    let rows: Int
    let columns: Int
    /// Where each row's bytes start in ``body``, and (last) where the last
    /// ends.
    let offsets: [Int]
    let body: [UInt8]
    /// The blocks' corners ``ground(of:frame:)`` has worked out, shared by
    /// every copy of this grid.
    let groundMemo = GroundMemo()

    /// Reads the app's heights file. Throws for a file out of shape: the
    /// wrong magic or version, a grid of no cells, or offsets out of order
    /// or past its end. A row is checked as it is read.
    public init(data: Data) throws {
        try self.init(data: data, magic: "TWHG")
    }

    /// Reads a grid of whole numbers in the heights file's form under
    /// `magic` (decision 147: ``CoverageGrid``'s `TWCV`).
    init(data: Data, magic: String) throws {
        func corrupt(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: why))
        }
        let bytes = [UInt8](data)
        func integer(at offset: Int, size: Int) -> UInt64 {
            (0..<size).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
        }
        let header = 4 + 2 + 2 + 8 * 3 + 4 * 2
        guard bytes.count >= header, bytes.prefix(4).elementsEqual(magic.utf8), integer(at: 4, size: 2) == 1 else {
            throw corrupt("The file starts with \(magic) and version 1.")
        }
        north = Double(bitPattern: integer(at: 8, size: 8))
        west = Double(bitPattern: integer(at: 16, size: 8))
        cellDegrees = Double(bitPattern: integer(at: 24, size: 8))
        rows = Int(integer(at: 32, size: 4))
        columns = Int(integer(at: 36, size: 4))
        guard north.isFinite, west.isFinite, cellDegrees > 0, (1...1 << 20).contains(rows), (1...1 << 20).contains(columns),
              bytes.count >= header + 4 * (rows + 1)
        else {
            throw corrupt("The heights grid needs a corner, a positive cell size, its rows and columns and their offsets.")
        }
        let start = header + 4 * (rows + 1)
        offsets = (0...rows).map { Int(integer(at: header + 4 * $0, size: 4)) }
        guard offsets.first == 0, zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }), offsets.last == bytes.count - start else {
            throw corrupt("The heights file's rows are in order and fill it.")
        }
        body = Array(bytes[start...])
    }

    /// Row `row`'s heights from the west, in metres, or `nil` for a row
    /// that does not decode to ``columns`` heights.
    func row(_ row: Int) -> [Int16]? {
        var index = offsets[row]
        let end = offsets[row + 1]
        var heights: [Int16] = []
        heights.reserveCapacity(columns)
        func varint() -> Int? {
            var value = 0, shift = 0
            while index < end, shift < 35 {
                let byte = body[index]
                index += 1
                value |= Int(byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
            return nil
        }
        var height = 0
        while index < end {
            guard let value = varint() else { return nil }
            if value == 0 {
                guard let count = varint(), count > 0, heights.count + count <= columns else { return nil }
                heights.append(contentsOf: repeatElement(Int16(truncatingIfNeeded: height), count: count))
            } else {
                height += (value >> 1) ^ -(value & 1)
                guard heights.count < columns, Int(Int16.min)...Int(Int16.max) ~= height else { return nil }
                heights.append(Int16(height))
            }
        }
        return heights.count == columns ? heights : nil
    }

    /// Reads rows as asked, each once.
    struct Reader {
        let grid: HeightGrid
        private var rows: [Int: [Int16]] = [:]

        init(_ grid: HeightGrid) {
            self.grid = grid
        }

        /// The height at grid cell `row`, `column`, in metres: 0 outside the
        /// grid (the sea round it) or in a row that does not decode.
        mutating func height(row: Int, column: Int) -> Double {
            guard (0..<grid.rows).contains(row), (0..<grid.columns).contains(column) else { return 0 }
            if rows[row] == nil {
                rows[row] = grid.row(row) ?? []
            }
            guard let heights = rows[row], !heights.isEmpty else { return 0 }
            return Double(heights[column])
        }

        /// Forgets the rows read north of `row`: a caller going south
        /// keeps only the rows it may still need.
        mutating func forgetRows(above row: Int) {
            rows = rows.filter { $0.key >= row }
        }

        /// The grid row whose middle lies at or north of `latitude`: the
        /// first row ``height(latitude:longitude:)`` reads there.
        func row(at latitude: Double) -> Int {
            Int(((grid.north - latitude) / grid.cellDegrees - 0.5).rounded(.down))
        }

        /// The height at `latitude`, `longitude`, in metres: the bilinear
        /// blend of the four cells whose middles surround it.
        mutating func height(latitude: Double, longitude: Double) -> Double {
            let y = (grid.north - latitude) / grid.cellDegrees - 0.5, x = (longitude - grid.west) / grid.cellDegrees - 0.5
            let row = Int(y.rounded(.down)), column = Int(x.rounded(.down))
            let fy = y - Double(row), fx = x - Double(column)
            return height(row: row, column: column) * (1 - fx) * (1 - fy) + height(row: row, column: column + 1) * fx * (1 - fy)
                + height(row: row + 1, column: column) * (1 - fx) * fy + height(row: row + 1, column: column + 1) * fx * fy
        }
    }

    /// The height at `latitude`, `longitude`, in metres (see
    /// ``Reader/height(latitude:longitude:)``).
    public func height(latitude: Double, longitude: Double) -> Double {
        var reader = Reader(self)
        return reader.height(latitude: latitude, longitude: longitude)
    }

    /// The ground at `point` of a world laid over the Earth by `frame`, in
    /// metres.
    public func height(at point: PlanPoint, frame: RealWorldFrame) -> Double {
        let place = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
        return height(latitude: place.latitude, longitude: place.longitude)
    }

    /// The corners of `blocks` of a world laid over the Earth by `frame`
    /// (decision 124), each the height there rounded to whole metres, by
    /// row and then column of the blocks; the same corner of two blocks
    /// gets the same height.
    ///
    /// A block's corners are worked out once for each frame and kept
    /// (TRACELAG, decision 521): reading one decodes some twenty of the
    /// grid's rows, and the build tool's preview reads the same blocks
    /// into a copy of the world at every step of a drag.
    public func ground(of blocks: [LandBlock], frame: RealWorldFrame) -> [GroundBlock] {
        groundMemo.ground(of: blocks.sorted(), frame: frame) { workOutGround(of: $0, frame: frame) }
    }

    /// ``ground(of:frame:)`` worked out from the rows, kept nowhere.
    func workOutGround(of blocks: [LandBlock], frame: RealWorldFrame) -> [GroundBlock] {
        var reader = Reader(self)
        let side = GroundBlock.side, length = Double(Land.cellLength)
        return blocks.sorted().compactMap { block in
            // Web Mercator puts a point's latitude by its y alone and its
            // longitude by its x alone.
            let latitudes = (0..<side).map { i in
                frame.coordinate(worldX: 0, worldY: Double(block.row * Land.blockCells + i) * length).latitude
            }
            let longitudes = (0..<side).map { j in
                frame.coordinate(worldX: Double(block.column * Land.blockCells + j) * length, worldY: 0).longitude
            }
            let heights = latitudes.flatMap { latitude in
                longitudes.map { longitude in Int16(clamping: Int(reader.height(latitude: latitude, longitude: longitude).rounded())) }
            }
            return GroundBlock(block: block, heights: heights)
        }
    }
}

extension HeightGrid {
    /// The blocks' corners worked out for one frame (TRACELAG, decision
    /// 521). Locked, since the grid is read off the main actor too; the
    /// corners are worked out outside the lock, and the same block worked
    /// out twice at once comes out the same.
    final class GroundMemo: @unchecked Sendable {
        /// At most this many blocks (some 600 bytes each) are kept; past
        /// it the memo starts again.
        static let limit = 4_096

        private let lock = NSLock()
        private var frame: RealWorldFrame?
        private var blocks: [LandBlock: GroundBlock] = [:]
        private var workedOut = 0

        /// `wanted`'s corners, in its order: those kept, and the rest from
        /// `workOut`, which are kept from now on.
        func ground(of wanted: [LandBlock], frame: RealWorldFrame, workOut: ([LandBlock]) -> [GroundBlock]) -> [GroundBlock] {
            var kept: [LandBlock: GroundBlock] = [:]
            lock.withLock {
                if self.frame != frame {
                    self.frame = frame
                    blocks = [:]
                }
                for block in wanted {
                    kept[block] = blocks[block]
                }
            }
            let missing = wanted.filter { kept[$0] == nil }
            if !missing.isEmpty {
                let fresh = workOut(missing)
                for block in fresh {
                    kept[block.block] = block
                }
                lock.withLock {
                    workedOut += fresh.count
                    guard self.frame == frame else { return }
                    if blocks.count + fresh.count > Self.limit { blocks = [:] }
                    for block in fresh {
                        blocks[block.block] = block
                    }
                }
            }
            return wanted.compactMap { kept[$0] }
        }

        /// How many blocks have been worked out from the rows.
        var blocksWorkedOut: Int {
            lock.withLock { workedOut }
        }
    }
}
