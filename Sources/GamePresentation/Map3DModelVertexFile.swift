import Foundation

/// Decision 750: the model pack's vertices (``Map3DModelPack``, some 287 MB
/// on the heaviest save's iPhone) written once to a file the system maps,
/// so the app can put on the GPU only the models a game draws, each the
/// first time it is drawn (a train bought later too), and hold the rest
/// nowhere in its own memory: a mapped file's pages are the file's, read
/// in as they are touched and let go of by the system, not the app's.
///
/// The file is removed as soon as it is mapped: the mapping keeps its
/// bytes for as long as this lives, and nothing is left on the disk after.
/// Each model's vertices are its bytes as the GPU reads them
/// (``Map3DVertex``, 40 bytes each), one model after another.
public final class Map3DModelVertexFile: @unchecked Sendable {
    private let data: Data
    private let ranges: [Range<Int>]

    /// How many models it holds, in the pack's order.
    public var count: Int { ranges.count }
    /// Bytes of every model's vertices.
    public var byteCount: Int { data.count }

    private init(data: Data, ranges: [Range<Int>]) {
        self.data = data
        self.ranges = ranges
    }

    /// Writes `pack`'s vertices to a new file in `directory`, maps it and
    /// removes it; `nil` when it cannot be written or mapped (the disk is
    /// full, say), and nothing is left behind.
    public static func write(_ pack: Map3DModelPack, in directory: URL) -> Map3DModelVertexFile? {
        let url = directory.appendingPathComponent("map3d-models-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return nil }
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(pack.models.count)
        do {
            let handle = try FileHandle(forWritingTo: url)
            var offset = 0
            do {
                for model in pack.models {
                    let bytes = model.vertices.withUnsafeBytes { Data($0) }
                    try handle.write(contentsOf: bytes)
                    ranges.append(offset ..< offset + bytes.count)
                    offset += bytes.count
                }
                try handle.close()
            } catch {
                try? handle.close()
                return nil
            }
            let data = try Data(contentsOf: url, options: .alwaysMapped)
            guard data.count == offset else { return nil }
            return Map3DModelVertexFile(data: data, ranges: ranges)
        } catch {
            return nil
        }
    }

    /// The bytes of model `index`'s vertices, for as long as `body` runs.
    public func withBytes<Result>(of index: Int, _ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        let range = ranges[index]
        return try data.withUnsafeBytes { all in
            try body(UnsafeRawBufferPointer(rebasing: all[range]))
        }
    }

    /// Model `index`'s vertices, read back (the tests compare them).
    public func vertices(of index: Int) -> [Map3DVertex] {
        withBytes(of: index) { bytes in
            let count = bytes.count / MemoryLayout<Map3DVertex>.stride
            return (0 ..< count).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Map3DVertex>.stride, as: Map3DVertex.self) }
        }
    }
}
