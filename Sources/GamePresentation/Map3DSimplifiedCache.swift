import Foundation

/// Decision 467: a model's lighter versions (``Map3DMeshSimplifier``), made
/// off the main thread and kept in a folder of the device's caches, so a
/// model is simplified once on a device rather than each time the map
/// opens (decision 420 measured 4.6 s for the whole pack's three levels).
///
/// A version is found by its key: the model's corners (FNV-1a 64 of their
/// bytes), the share, the limit and the simplifier's ``Map3DMeshSimplifier/version``.
/// So a changed model, share or simplifier misses and is made again; a
/// file that cannot be read (cut short, from another format) is made
/// again and written over. Nothing here is game state: deleting the folder
/// costs only the time to make the versions again.
public struct Map3DSimplifiedCache: Sendable {
    /// The folder the versions are kept in (the app's: a folder in its
    /// Caches, which the system may empty).
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The file's first bytes, and its format.
    static let magic: [UInt8] = Array("M3DL".utf8)
    static let format: UInt32 = 1

    /// The key of `model`'s version with `share` of its triangles, the
    /// surface moving no more than `maxError`.
    public static func key(of model: Map3DModelPack.Model, share: Double, maxError: Double?) -> String {
        var hash = FNV1a()
        for vertex in model.vertices {
            for value in [vertex.x, vertex.y, vertex.z, vertex.nx, vertex.ny, vertex.nz, vertex.u, vertex.v, vertex.layer] {
                hash.add(value.bitPattern)
            }
            hash.add(vertex.color)
        }
        hash.add(share.bitPattern)
        hash.add((maxError ?? -1).bitPattern)
        hash.add(UInt64(Map3DMeshSimplifier.version))
        return String(hash.value, radix: 16)
    }

    func url(of key: String) -> URL {
        folder.appendingPathComponent("lod-\(key).m3dlod")
    }

    /// `model` with each of `shares` of its triangles, the surface moving
    /// no more than `maxError` (the game's limit unless asked): from the folder
    /// where it has them, otherwise made on a background task and written
    /// there. Each comes back with the model's name and box.
    public func versions(of model: Map3DModelPack.Model, shares: [Double],
                         maxError: Double? = Map3DMeshSimplifier.recommendedMaxError) async -> [Map3DModelPack.Model] {
        let keys = shares.map { Self.key(of: model, share: $0, maxError: maxError) }
        let found = keys.map { read(key: $0) }
        if found.allSatisfy({ $0 != nil }) {
            return found.map { Map3DModelPack.Model(name: model.name, vertices: $0!, minimum: model.minimum, maximum: model.maximum) }
        }
        let made = await Task.detached(priority: .utility) {
            model.simplified(to: shares, maxError: maxError)
        }.value
        for (key, version) in zip(keys, made) { write(version.vertices, key: key) }
        return made
    }

    /// The corners kept under `key`; `nil` when there are none or the file
    /// cannot be read.
    func read(key: String) -> [Map3DVertex]? {
        guard let data = try? Data(contentsOf: url(of: key)) else { return nil }
        let bytes = [UInt8](data)
        guard bytes.count >= 12, Array(bytes[0..<4]) == Self.magic, word(bytes, at: 4) == Self.format else { return nil }
        let count = Int(word(bytes, at: 8))
        guard count % 3 == 0, bytes.count == 12 + count * 40 else { return nil }
        return (0..<count).map { index in
            let at = 12 + index * 40
            func float(_ field: Int) -> Float { Float(bitPattern: word(bytes, at: at + field * 4)) }
            return Map3DVertex(Map3DPoint(float(0), float(1), float(2)), normal: Map3DPoint(float(3), float(4), float(5)),
                               color: word(bytes, at: at + 24), u: float(7), v: float(8), layer: float(9))
        }
    }

    /// Keeps `corners` under `key`, whole or not at all (written aside,
    /// then moved in).
    func write(_ corners: [Map3DVertex], key: String) {
        var bytes = Self.magic
        bytes.reserveCapacity(12 + corners.count * 40)
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }
        append(Self.format)
        append(UInt32(corners.count))
        for c in corners {
            for value in [c.x, c.y, c.z, c.nx, c.ny, c.nz] { append(value.bitPattern) }
            append(c.color)
            for value in [c.u, c.v, c.layer] { append(value.bitPattern) }
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(bytes).write(to: url(of: key), options: .atomic)
    }

    private func word(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

/// FNV-1a, 64 bits, fed whole words byte by byte (low byte first).
private struct FNV1a {
    var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func add(_ word: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { byte(UInt8(truncatingIfNeeded: word >> UInt32(shift))) }
    }

    mutating func add(_ word: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) { byte(UInt8(truncatingIfNeeded: word >> UInt64(shift))) }
    }

    private mutating func byte(_ b: UInt8) {
        value = (value ^ UInt64(b)) &* 0x0000_0100_0000_01B3
    }
}
