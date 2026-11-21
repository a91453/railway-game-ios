import Foundation

/// Decision 916: the Finnish open double-deck car carrier (Gfot), the
/// white and green car with the dipped waist and the railing round its
/// upper deck that the night trains to and from Rovaniemi carry at their
/// back beside the closed one (``Map3DFinlandCarCarrier``), as the local
/// studio modelled it in Blender from photographs (26.40 m between
/// buffers, on the 1,524 mm gauge), one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-car-carrier-gfot-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// No company mark, lettering or car on its decks is drawn. The night
/// train's last car but one (``Map3DTrainSet/finlandNight(sr3:far:)``).
public enum Map3DFinlandCarCarrierGfot {
    /// The car.
    public static let name = "finland-car-carrier-gfot"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, green, interior, rail, mask, hardware, dark, taillamp;
    /// the double-deck coach's colours of the same names
    /// (``Map3DFinlandDoubleDeck/meshPalette``), the inner wall the halls'
    /// grey and the railing the overhead line's mast steel; no new colour.
    static let meshPalette: [UInt32] = {
        let coach = Map3DFinlandDoubleDeck.meshPalette
        return [coach[0], coach[2], Map3DPalette.hallWalls[2], Map3DPalette.mastSteel,
                coach[4], coach[7], coach[8], coach[6]]
    }()

    /// The car; `far`, the light version drawn from 500 m out. `nil` if
    /// its mesh does not decode. It has no glass.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }
}
