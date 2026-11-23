import Foundation

/// Decision 930: Hong Kong's orange, white and green fast catamaran of the
/// outlying island routes (``Map3DFerry/Boat/hongKongOutlying``), from the
/// local studio's model (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-outlying-ferry-2026-11/revision-2`,
/// #306; lessons in `docs/studio/lessons/hk-outlying-ferry.md`), written
/// in with `tools/train-models/glb_to_swift.py`
/// (``Map3DHKOutlyingFerryMesh``): two orange hulls with the dark arch
/// between them under a high bow, a white cabin of two decks with long
/// dark window bands, the upper deck's roof green, a radar mast. 40.1 m
/// long, 11.2 m across. No name, operator's mark or lettering.
///
/// The model's own space is ``Map3DFerry``'s: metres, +x the bow, +y the
/// left, +z up, the waterline at z 0, its origin its middle; the hulls go
/// down to z −0.8.
enum Map3DHKOutlyingFerry {
    static let name = "hk-outlying-ferry"

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py` (the
    /// brief's §4, each the game's own): hull, white, green, deck, dark,
    /// steel, glass, cabin_lit.
    static let meshPalette: [UInt32] = [
        Map3DEMU100.meshPalette[2], CableParts.Paint.white, Map3DPalette.hallRoofs[1], CableParts.Paint.deck,
        Map3DPalette.dark, CableParts.Paint.steel, Map3DTrainStyle.glass, CableParts.Paint.warm,
    ]
    /// `cabin_lit`: the two decks' window bands, lit at night.
    static let lamps: Set<Int> = [7]

    /// The boat near or `far`, named `name`; `nil` if its mesh does not
    /// decode.
    static func model(far: Bool, named name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[Self.name + (far ? "-far" : "")],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, lamps: lamps)
    }
}
