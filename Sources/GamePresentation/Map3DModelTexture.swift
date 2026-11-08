/// Decision 653: the one texture a file-made model is painted with (a
/// `.m3dmodel` of version 2, ``Map3DModelFile``), kept as the file stores
/// it: the app hands the bytes to Metal's texture loader, which reads all
/// three kinds, so nothing here decodes an image (and it runs on Linux).
/// Its vertices say where in it they fall (``Map3DVertex/modelTexture``).
public struct Map3DModelTexture: Equatable, Sendable {
    public enum Kind: UInt32, Sendable, CaseIterable {
        case png = 1
        case jpeg = 2
        /// A KTX (version 1) file: what carries a texture compressed
        /// ahead for the GPU (ASTC on iPhone), its mipmaps made ahead too.
        case ktx = 3

        /// The bytes a file of this kind starts with.
        var signature: [UInt8] {
            switch self {
            case .png: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            case .jpeg: [0xFF, 0xD8, 0xFF]
            case .ktx: [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]
            }
        }
    }

    /// The largest texture a model may carry: 4 MB, as large as a 1024 ×
    /// 1024 picture is uncompressed.
    public static let maximumBytes = 4 << 20

    public let kind: Kind
    public let bytes: [UInt8]

    /// `nil` when `bytes` do not start as a file of `kind` does, or are
    /// more than ``maximumBytes``.
    public init?(kind: Kind, bytes: [UInt8]) {
        guard bytes.count <= Self.maximumBytes, bytes.count > kind.signature.count,
              Array(bytes.prefix(kind.signature.count)) == kind.signature else { return nil }
        self.kind = kind
        self.bytes = bytes
    }
}
