import Foundation

/// Decision 909: Hong Kong's green and white double-ended harbour ferry
/// (``Map3DFerry/Boat/hongKong``) and its two piers, the long finger pier
/// and the hall pier with its colonnade (``Map3DFerry/PierKind``), from the
/// local studio's models (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-harbour-ferry-2026-11/revision-3`, #228;
/// lessons in `docs/studio/lessons/hk-harbour-ferry.md`), written in with
/// `tools/train-models/glb_to_swift.py --centimetres`
/// (``Map3DHongKongFerryMesh``): the finger pier reaches 72 m, past the
/// millimetre encoding's 32.7 m. No name, operator's mark or lettering.
///
/// The models' own space is ``Map3DFerry``'s: metres, +x the bow (either
/// end) or, for a pier, out over the water, +y the left, +z up, the
/// waterline at z 0; a boat's origin its middle, a pier's on the bank's
/// edge at the middle of its width. Piles and hull go down to z −0.6.
enum Map3DHongKongFerry {
    enum Model: String, Sendable {
        case boat = "hk-harbour-ferry", finger = "hk-ferry-pier-finger", hall = "hk-ferry-pier-hall"
    }

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py` (the
    /// brief's §4, each the game's own): hullGreen, white, cream,
    /// roofGreen, deck, dark, steel, red, glass, cabin_lit.
    static let meshPalette: [UInt32] = [
        Map3DPalette.hallRoofs[1], CableParts.Paint.white, Map3DPalette.sidewalk, CableParts.Paint.green, CableParts.Paint.deck,
        Map3DPalette.dark, CableParts.Paint.steel, CableParts.Paint.red, CableParts.Paint.glass, CableParts.Paint.warm,
    ]
    /// `cabin_lit`: the boat's window bands and deck ceilings, lit at night.
    static let lamps: Set<Int> = [9]

    /// `model` near or `far`, named `name`; `nil` if its mesh does not
    /// decode.
    static func model(_ model: Model, far: Bool, named name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[model.rawValue + (far ? "-far" : "")],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, lamps: lamps, perMetre: 100)
    }
}
