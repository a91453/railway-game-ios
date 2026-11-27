import Foundation

/// Decision 1035: the small things of a temple's square that the studio
/// made from the owner's Meshy models, beside decision 935's stone lions
/// and Tiangong burner: the cut-tile pair of dragons on the main hall's
/// ridge, the pair of dragon columns at the gate, the Tudigong figure at
/// a shrine's door, and a street dog and pigeons standing on a square.
///
/// Their shapes follow the owner's Meshy models (text-to-3D, so the
/// data-source page says they are generated), rebuilt for the game by
/// the local studio and passed by its review
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/meshy-temple-animals-2026-11/revision-3`;
/// lessons in `docs/studio/lessons/meshy-temple-animals.md`). Written here
/// by `tools/train-models/glb_to_swift.py` (``encoded``): each facing +x,
/// its foot at z 0 (the dragons' the bottom of their ridge seat).
public enum Map3DTempleProp: String, CaseIterable, Sendable {
    /// The two dragons chasing a pearl on a ridge seat, 2.4 m along the
    /// ridge (y), 1.2 m tall.
    case ridgeDragons = "temple-ridge-dragons"
    case ridgeDragonsFar = "temple-ridge-dragons-far"
    /// A stone column a dragon coils round, 3.2 m tall on a 0.7 m base.
    case dragonPillar = "temple-dragon-pillar"
    case dragonPillarFar = "temple-dragon-pillar-far"
    /// Tudigong in his red robe and black hat on a plinth, 1.2 m.
    case tudigong = "tudigong-statue"
    case tudigongFar = "tudigong-statue-far"
    /// A tawny Formosan street dog standing, 0.85 m long.
    case streetDog = "street-dog"
    case streetDogFar = "street-dog-far"
    /// A grey pigeon, 0.32 m long.
    case pigeon

    /// The model's name.
    public var modelName: String { "meshy-" + rawValue }

    /// The colours, in the order `glb_to_swift.py --materials` gave them
    /// (dragonGreen, flame, pearl, ridge, stone, bronze, beard, skin,
    /// plinth, fur, belly, feather, featherDark, foot), each the game's
    /// own as the studio's README matched it to its photographs.
    static let palette: [UInt32] = [
        Map3DPalette.crown, Map3DPalette.platformEdge, Map3DPalette.lantern, Map3DPalette.dark, Map3DPalette.portal,
        Map3DPalette.gold, Map3DPalette.tankSteel, Map3DStreetModel.skin, Map3DPalette.arcade, Map3DPalette.trunk,
        Map3DPalette.terrazzo, Map3DPalette.steel, Map3DPalette.dark, Map3DPalette.lantern,
    ]

    /// The model; `nil` if its mesh does not decode.
    public var model: Map3DModelPack.Model? { Self.models[self] ?? nil }

    private static let models: [Map3DTempleProp: Map3DModelPack.Model?] = Dictionary(uniqueKeysWithValues: allCases.map { prop in
        guard let text = encoded[prop.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return (prop, nil) }
        return (prop, Map3DRedCommuter.decodedMesh([UInt8](data), named: prop.modelName, palette: palette))
    })
}
