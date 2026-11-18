import Foundation

/// Decision 864: the Finnish intercity double-deck second-class coach (the
/// 2010 green and white livery), as the local studio modelled it in
/// Blender from photographs and the published dimensions (26.40 m between
/// couplers, 3.20 m wide, 5.20 m tall, on the 1,524 mm gauge), one palette
/// colour a triangle, the window bays one by one, the doors white with a
/// narrow window, the green band and the green blocks round the doors
/// faces of their own (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-ic-double-deck-2026-11/revision-6`),
/// and written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// The coaches the Sr2 hauls (``Map3DFinlandSr2``). No company mark,
/// lettering or the doors' pictures is drawn.
public enum Map3DFinlandDoubleDeck {
    /// The coach, its longer end section at +x.
    public static let name = "finland-ic-double-deck-coach"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, roofSilver, green, steel, mask, glass, taillamp,
    /// hardware, dark. Colours the game has (the work order's table); no
    /// new colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.cityConcreteWalls[4], Map3DPalette.mtrRoofSilver, Map3DPalette.crown, Map3DPalette.steel,
        Map3DColor.rgb(0x1D2125), Map3DTrainStyle.glass, Map3DPalette.lantern, Map3DColor.rgb(0x4B535C),
        Map3DColor.rgb(0x30363D),
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night.
    static let glassIndex = 5

    /// The coach; `far`, the light version drawn from 500 m out. `nil` if
    /// its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}
