import Foundation

/// A PMTiles v3 archive (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md):
/// the app's base map, `taiwan.pmtiles` (decision 151), read tile by tile
/// for the 3D map (decision 234). The 2D map's MapLibre reads the same
/// file itself.
///
/// The archive is read as `tools/basemap/build_basemap.py` writes it:
/// gzipped directories and tiles, a root directory with leaf directories
/// under it.
struct PMTilesArchive: Sendable {
    enum Failure: Error, Equatable {
        /// Not a PMTiles v3 archive, or one cut short.
        case malformed
        /// Compressed in a way this reader does not unpack.
        case unsupportedCompression
    }

    /// The archive's bytes, usually mapped from the file.
    let data: Data
    let rootOffset: Int, rootLength: Int
    let leafOffset: Int
    let tileDataOffset: Int
    /// 1 none, 2 gzip, of the directories and of the tiles.
    let directoryCompression: UInt8, tileCompression: UInt8
    let minimumZoom: Int, maximumZoom: Int

    init(data: Data) throws(Failure) {
        guard data.count >= 127, data.prefix(7) == Data("PMTiles".utf8), data[data.startIndex + 7] == 3 else { throw .malformed }
        self.data = data
        func number(_ at: Int) -> Int {
            var value: UInt64 = 0
            for byte in (0..<8).reversed() { value = value << 8 | UInt64(data[data.startIndex + at + byte]) }
            return Int(truncatingIfNeeded: value)
        }
        rootOffset = number(8)
        rootLength = number(16)
        leafOffset = number(40)
        tileDataOffset = number(56)
        directoryCompression = data[data.startIndex + 97]
        tileCompression = data[data.startIndex + 98]
        minimumZoom = Int(data[data.startIndex + 100])
        maximumZoom = Int(data[data.startIndex + 101])
        guard rootOffset + rootLength <= data.count else { throw .malformed }
        guard [1, 2].contains(directoryCompression), [1, 2].contains(tileCompression) else { throw .unsupportedCompression }
    }

    /// The tile at zoom `zoom`, column `x`, row `y` (from the north), its
    /// bytes unpacked; `nil` when the archive has none there.
    func tile(zoom: Int, x: Int, y: Int) throws(Failure) -> [UInt8]? {
        guard (minimumZoom...maximumZoom).contains(zoom), x >= 0, y >= 0, x < 1 << zoom, y < 1 << zoom else { return nil }
        let id = Self.tileID(zoom: zoom, x: x, y: y)
        var directory = try entries(offset: rootOffset, length: rootLength)
        for _ in 0..<4 {
            // The last entry starting at or before the tile.
            var low = 0, high = directory.count - 1, found: Entry?
            while low <= high {
                let middle = (low + high) / 2
                if directory[middle].tileID <= id {
                    found = directory[middle]
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            guard let entry = found else { return nil }
            if entry.runLength == 0 {
                directory = try entries(offset: leafOffset + entry.offset, length: entry.length)
                continue
            }
            guard id < entry.tileID + UInt64(entry.runLength) else { return nil }
            return try unpack(bytes(at: tileDataOffset + entry.offset, length: entry.length), compression: tileCompression)
        }
        return nil
    }

    /// A tile's number along the Hilbert curve of its zoom, after every
    /// tile of the zooms before it (the spec's `zxy_to_tileid`).
    static func tileID(zoom: Int, x: Int, y: Int) -> UInt64 {
        let before = ((UInt64(1) << (2 * UInt64(zoom))) - 1) / 3
        // Signed, as the spec's: a turn of a quadrant can take x and y
        // below zero, and the next bits are read from them as they are.
        var x = Int64(x), y = Int64(y), distance: Int64 = 0
        var side = (Int64(1) << Int64(zoom)) >> 1
        while side > 0 {
            let rx: Int64 = x & side != 0 ? 1 : 0
            let ry: Int64 = y & side != 0 ? 1 : 0
            distance += side * side * ((3 * rx) ^ ry)
            if ry == 0 {
                if rx == 1 {
                    x = side - 1 - x
                    y = side - 1 - y
                }
                swap(&x, &y)
            }
            side >>= 1
        }
        return before + UInt64(distance)
    }

    struct Entry: Equatable {
        let tileID: UInt64
        let offset: Int, length: Int
        /// How many tiles in a row share the bytes; 0 for a leaf directory.
        let runLength: Int
    }

    func entries(offset: Int, length: Int) throws(Failure) -> [Entry] {
        let bytes = try unpack(bytes(at: offset, length: length), compression: directoryCompression)
        var at = 0
        func varint() throws(Failure) -> UInt64 {
            var value: UInt64 = 0, shift: UInt64 = 0
            while true {
                guard at < bytes.count, shift < 64 else { throw .malformed }
                let byte = bytes[at]
                at += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
        }
        let count = Int(try varint())
        guard count <= bytes.count else { throw .malformed }
        var ids: [UInt64] = [], runs: [Int] = [], lengths: [Int] = [], offsets: [Int] = []
        var last: UInt64 = 0
        for _ in 0..<count {
            last += try varint()
            ids.append(last)
        }
        for _ in 0..<count { runs.append(Int(try varint())) }
        for _ in 0..<count { lengths.append(Int(try varint())) }
        for index in 0..<count {
            let value = Int(try varint())
            offsets.append(value == 0 && index > 0 ? offsets[index - 1] + lengths[index - 1] : value - 1)
        }
        return (0..<count).map { Entry(tileID: ids[$0], offset: offsets[$0], length: lengths[$0], runLength: runs[$0]) }
    }

    private func bytes(at offset: Int, length: Int) throws(Failure) -> [UInt8] {
        guard offset >= 0, length >= 0, offset + length <= data.count else { throw .malformed }
        let start = data.startIndex + offset
        return [UInt8](data[start..<(start + length)])
    }

    private func unpack(_ bytes: [UInt8], compression: UInt8) throws(Failure) -> [UInt8] {
        guard compression == 2 else { return bytes }
        do {
            return try Inflate.gunzip(bytes)
        } catch {
            throw .malformed
        }
    }
}
