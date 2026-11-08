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
/// - each triangle: its flags (UInt32; bit 0, lit from within at night;
///   decision 450: bit 1, a train's window glass, bit 2, its stainless
///   body, as `tools/train-models` writes them),
///   then three corners of x, y, z (Float32, metres, the model's space:
///   +x the front, +y the left, +z up, the ground at z 0) and colour
///   (UInt32, red in the low byte; alpha 0 where the instance's colour
///   shows, as the code-made vehicles' bodies).
///
/// Normals are not stored: each triangle has its own, flat, worked out
/// here as ``Map3DModelPack/Model/flat(named:from:)`` does; a triangle with
/// no area is left out, as there.
///
/// Decision 653: version 2 adds a model painted by a texture of its own,
/// as a model made from another game's or a modelling tool's files is
/// (its colours not baked to one a triangle):
/// - `M3DM`, the version (UInt16, 2), 0 (UInt16), the triangles (UInt32),
///   the provenance's length (UInt32), the texture's kind (UInt32,
///   ``Map3DModelTexture/Kind``, 0 for none) and its length in bytes
///   (UInt32);
/// - the provenance as in version 1, then the texture's bytes as its file
///   holds them (PNG, JPEG or KTX), padded with zeros to a multiple of
///   four bytes;
/// - each triangle: its flags (UInt32; version 1's, and bit 3, painted by
///   the texture, which neither glass nor steel may be), then three
///   corners of x, y, z, its normal's x, y, z, the texture's u, v (Float32;
///   u, v from the texture's top-left corner, repeating) and colour
///   (UInt32, as in version 1: the texture is tinted by it).
///
/// A corner's normal is its own (a smooth surface); a zero one takes the
/// triangle's flat normal. Version 1 files read as they always did.
public struct Map3DModelFile: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case notAModel
        case unsupportedVersion(Int)
        case wrongSize(expected: Int, actual: Int)
        case tooManyTriangles(Int)
        case noProvenance
        case unknownFlags(UInt32)
        case notFinite
        /// No triangle with any area: nothing to draw, and no size to
        /// scale or place it by.
        case nothingToDraw
        /// Decision 653: a texture of an unknown kind, too large, or whose
        /// bytes do not start as its kind's file does.
        case badTexture
        /// Decision 653: a triangle painted by the texture in a file
        /// that has none.
        case noTexture
    }

    /// The newest version written; every version up to it is read.
    public static let version = 2
    /// More than a trial model needs: ten times the bus's 1,500.
    public static let maximumTriangles = 15_000
    static let magic: [UInt8] = Array("M3DM".utf8)
    static let headerSize = 16
    static let triangleSize = 4 + 3 * 16
    /// Decision 653: version 2's header and triangle.
    static let texturedHeaderSize = 24
    static let texturedTriangleSize = 4 + 3 * 36
    static let glows: UInt32 = 1
    static let glass: UInt32 = 2
    static let steel: UInt32 = 4
    static let textured: UInt32 = 8

    public let model: Map3DModelPack.Model
    /// The generator's own record of the model, kept as it came.
    public let provenance: String

    public init(decoding data: Data, named name: String) throws(Error) {
        try self.init(decoding: [UInt8](data), named: name)
    }

    public init(decoding bytes: [UInt8], named name: String) throws(Error) {
        guard bytes.count >= Self.headerSize, Array(bytes[0..<4]) == Self.magic else { throw .notAModel }
        let version = Int(Self.uint16(bytes, 4))
        guard (1...Self.version).contains(version), Self.uint16(bytes, 6) == 0 else { throw .unsupportedVersion(version) }
        if version == 2 {
            let decoded = try Self.decodeTextured(bytes, named: name)
            model = decoded.0
            provenance = decoded.1
            return
        }
        let triangles = Int(Self.uint32(bytes, 8))
        guard triangles <= Self.maximumTriangles else { throw .tooManyTriangles(triangles) }
        let provenanceLength = Int(Self.uint32(bytes, 12))
        let padded = (provenanceLength + 3) / 4 * 4
        let expected = Self.headerSize + padded + triangles * Self.triangleSize
        guard bytes.count == expected else { throw .wrongSize(expected: expected, actual: bytes.count) }
        // Not `String(validating:as:)`: the app still runs before iOS 18.
        guard provenanceLength > 0,
              let provenance = String(bytes: bytes[Self.headerSize..<(Self.headerSize + provenanceLength)], encoding: .utf8),
              !provenance.allSatisfy(\.isWhitespace) else { throw .noProvenance }

        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(triangles * 3)
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        var offset = Self.headerSize + padded
        for _ in 0..<triangles {
            let flags = Self.uint32(bytes, offset)
            guard flags & ~(Self.glows | Self.glass | Self.steel) == 0, flags & Self.glass == 0 || flags & Self.steel == 0 else { throw .unknownFlags(flags) }
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
            let lit = flags & Self.glows != 0
            let layer = flags & Self.glass != 0 ? (lit ? Map3DVertex.trainGlassLit : Map3DVertex.trainGlass)
                : flags & Self.steel != 0 ? Map3DVertex.trainSteel : lit ? Map3DVertex.glowing : Map3DVertex.plain
            for (point, colour) in zip(points, colours) {
                vertices.append(Map3DVertex(point, normal: normal, color: colour, layer: layer))
                low = Map3DPoint(min(low.x, point.x), min(low.y, point.y), min(low.z, point.z))
                high = Map3DPoint(max(high.x, point.x), max(high.y, point.y), max(high.z, point.z))
            }
        }
        guard !vertices.isEmpty else { throw .nothingToDraw }
        model = Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
        self.provenance = provenance
    }

    /// Decision 653: a version 2 file's model and provenance.
    private static func decodeTextured(_ bytes: [UInt8], named name: String) throws(Error) -> (Map3DModelPack.Model, String) {
        guard bytes.count >= texturedHeaderSize else { throw .wrongSize(expected: texturedHeaderSize, actual: bytes.count) }
        let triangles = Int(uint32(bytes, 8))
        guard triangles <= maximumTriangles else { throw .tooManyTriangles(triangles) }
        let provenanceLength = Int(uint32(bytes, 12)), kindValue = uint32(bytes, 16), textureLength = Int(uint32(bytes, 20))
        let paddedProvenance = (provenanceLength + 3) / 4 * 4, paddedTexture = (textureLength + 3) / 4 * 4
        let expected = texturedHeaderSize + paddedProvenance + paddedTexture + triangles * texturedTriangleSize
        guard bytes.count == expected else { throw .wrongSize(expected: expected, actual: bytes.count) }
        guard provenanceLength > 0,
              let provenance = String(bytes: bytes[texturedHeaderSize..<(texturedHeaderSize + provenanceLength)], encoding: .utf8),
              !provenance.allSatisfy(\.isWhitespace) else { throw .noProvenance }
        var texture: Map3DModelTexture?
        if kindValue != 0 || textureLength != 0 {
            let start = texturedHeaderSize + paddedProvenance
            guard let kind = Map3DModelTexture.Kind(rawValue: kindValue),
                  let found = Map3DModelTexture(kind: kind, bytes: Array(bytes[start..<(start + textureLength)])) else { throw .badTexture }
            texture = found
        }

        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(triangles * 3)
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        var offset = texturedHeaderSize + paddedProvenance + paddedTexture
        for _ in 0..<triangles {
            let flags = uint32(bytes, offset)
            let painted = flags & textured != 0
            guard flags & ~(glows | glass | steel | textured) == 0, flags & glass == 0 || flags & steel == 0,
                  !painted || flags & (glass | steel) == 0 else { throw .unknownFlags(flags) }
            if painted && texture == nil { throw .noTexture }
            var points: [Map3DPoint] = [], normals: [Map3DPoint] = [], uvs: [(Float, Float)] = [], colours: [UInt32] = []
            for corner in 0..<3 {
                let at = offset + 4 + corner * 36
                let values = (0..<8).map { float(bytes, at + $0 * 4) }
                guard values.allSatisfy(\.isFinite) else { throw .notFinite }
                points.append(Map3DPoint(values[0], values[1], values[2]))
                normals.append(Map3DPoint(values[3], values[4], values[5]))
                uvs.append((values[6], values[7]))
                colours.append(uint32(bytes, at + 32))
            }
            offset += texturedTriangleSize
            guard let flat = (points[1] - points[0]).cross(points[2] - points[0]).normalized else { continue }
            let lit = flags & glows != 0
            let layer = painted ? (lit ? Map3DVertex.modelTextureLit : Map3DVertex.modelTexture)
                : flags & glass != 0 ? (lit ? Map3DVertex.trainGlassLit : Map3DVertex.trainGlass)
                : flags & steel != 0 ? Map3DVertex.trainSteel : lit ? Map3DVertex.glowing : Map3DVertex.plain
            for corner in 0..<3 {
                let point = points[corner]
                vertices.append(Map3DVertex(point, normal: normals[corner].normalized ?? flat, color: colours[corner],
                                            u: painted ? uvs[corner].0 : 0, v: painted ? uvs[corner].1 : 0, layer: layer))
                low = Map3DPoint(min(low.x, point.x), min(low.y, point.y), min(low.z, point.z))
                high = Map3DPoint(max(high.x, point.x), max(high.y, point.y), max(high.z, point.z))
            }
        }
        guard !vertices.isEmpty else { throw .nothingToDraw }
        return (Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high, texture: texture), provenance)
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
