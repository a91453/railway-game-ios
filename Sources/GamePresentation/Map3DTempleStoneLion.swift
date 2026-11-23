import Foundation

/// Decision 935: the pair of stone lions at a temple's door, the male on
/// the temple's left and its mirror image on the right.
///
/// Their shape follows the owner's Meshy model (text-to-3D, so the
/// data-source page says it is generated), rebuilt for the game by the
/// local studio and passed by its review (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/temple-stone-lion-2026-11/revision-3`,
/// branch `studio/temple-stone-lion-r2`; lessons in
/// `docs/studio/lessons/temple-stone-lion.md`). Written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``): the lion facing +x,
/// its plinth's foot (1.0 m by 0.62 m, 0.55 m tall) at z 0, 1.8 m in all.
public enum Map3DTempleStoneLion: String, CaseIterable, Sendable {
    /// The male, his forepaw on a ball: on the temple's left, looking out.
    case left = "stone-lion-left"
    /// Its mirror image: on the temple's right.
    case right = "stone-lion-right"

    /// The model's name.
    public var modelName: String { "temple-" + rawValue }

    /// The colours, in the order `glb_to_swift.py --materials` gave them
    /// (stone, plinth, shade): the lion's grey stone, the plinth's darker
    /// blue-grey and the mouth's and eyes' near black, chosen against the
    /// studio's photographs, all the game's own.
    static let palette: [UInt32] = [Map3DPalette.portal, Map3DPalette.cityRoofs[1].color, Map3DPalette.dark]

    /// The model; `nil` if its mesh does not decode.
    public var model: Map3DModelPack.Model? {
        guard let text = Self.encoded[rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: modelName, palette: Self.palette)
    }
}
