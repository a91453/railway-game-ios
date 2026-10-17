import Foundation

/// A 3D map model read from a file (`.m3dmodel`) rather than made in code:
/// the trial of a generated model (a city bus from Meshy) in the native 3D
/// map, `docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`. A tool in
/// `tools/` writes it from the generated GLB, its colours already baked to
/// one a triangle; the app reads it here.
///
/// The file, little-endian:
/// - `M3DM`, the version (UInt16, 1), 0 (UInt16), the triangles (UInt32),
///   and the provenance's length in bytes (UInt32);
/// - the provenance: UTF-8 JSON, the GLB's own `asset` and `extras` as
///   generated (Meshy's terms §2.4: a generated model keeps what says it is
///   generated), padded with zeros to a multiple of four bytes;
/// - each triangle: its flags (UInt32; bit 0, lit from within at night),
///   then three corners of x, y, z (Float32, metres, the model's space:
///   +x the front, +y the left, +z up, the ground at z 0) and colour
///   (UInt32, red in the low byte; alpha 0 where the instance's colour
///   shows, as the code-made vehicles' bodies).
///
/// Normals are not stored: each triangle has its own, flat, worked out
/// here as ``Map3DModelPack/Model/flat(named:from:)`` does; a triangle with
/// no area is left out, as there.
public struct Map3DModelFile: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case notAModel
        case unsupportedVersion(Int)
        case wrongSize(expected: Int, actual: Int)
        case tooManyTriangles(Int)
        case noProvenance
        case unknownFlags(UInt32)
        case notFinite
    }

    public static let version = 1
    /// More than a trial model needs: ten times the bus's 1,500.
    public static let maximumTriangles = 15_000
    static let magic: [UInt8] = Array("M3DM".utf8)
    static let headerSize = 16
    static let triangleSize = 4 + 3 * 16
    static let glows: UInt32 = 1

    public let model: Map3DModelPack.Model
    /// The generator's own record of the model, kept as it came.
    public let provenance: String

    public init(decoding data: Data, named name: String) throws(Error) {
        try self.init(decoding: [UInt8](data), named: name)
    }

    public init(decoding bytes: [UInt8], named name: String) throws(Error) {
        guard bytes.count >= Self.headerSize, Array(bytes[0..<4]) == Self.magic else { throw .notAModel }
        let version = Int(Self.uint16(bytes, 4))
        guard version == Self.version, Self.uint16(bytes, 6) == 0 else { throw .unsupportedVersion(version) }
        let triangles = Int(Self.uint32(bytes, 8))
        guard triangles <= Self.maximumTriangles else { throw .tooManyTriangles(triangles) }
        let provenanceLength = Int(Self.uint32(bytes, 12))
        let padded = (provenanceLength + 3) / 4 * 4
        let expected = Self.headerSize + padded + triangles * Self.triangleSize
        guard bytes.count == expected else { throw .wrongSize(expected: expected, actual: bytes.count) }
        guard provenanceLength > 0,
              let provenance = String(validating: bytes[Self.headerSize..<(Self.headerSize + provenanceLength)], as: UTF8.self),
              !provenance.allSatisfy(\.isWhitespace) else { throw .noProvenance }

        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(triangles * 3)
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        var offset = Self.headerSize + padded
        for _ in 0..<triangles {
            let flags = Self.uint32(bytes, offset)
            guard flags & ~Self.glows == 0 else { throw .unknownFlags(flags) }
            var points: [Map3DPoint] = [], colours: [UInt32] = []
            for corner in 0..<3 {
                let at = offset + 4 + corner * 16
                let point = Map3DPoint(Self.float(bytes, at), Self.float(bytes, at + 4), Self.float(bytes, at + 8))
                guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { throw .notFinite }
                points.append(point)
                colours.append(Self.uint32(bytes, at + 12))
            }
            offset += Self.triangleSize
            guard let normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized else { continue }
            let layer = flags & Self.glows == 0 ? Map3DVertex.plain : Map3DVertex.glowing
            for (point, colour) in zip(points, colours) {
                vertices.append(Map3DVertex(point, normal: normal, color: colour, layer: layer))
                low = Map3DPoint(min(low.x, point.x), min(low.y, point.y), min(low.z, point.z))
                high = Map3DPoint(max(high.x, point.x), max(high.y, point.y), max(high.z, point.z))
            }
        }
        model = Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
        self.provenance = provenance
    }

    private static func uint16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }

    private static func float(_ bytes: [UInt8], _ at: Int) -> Float {
        Float(bitPattern: uint32(bytes, at))
    }
}
