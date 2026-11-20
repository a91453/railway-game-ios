import Foundation

/// FINLAND-TRAINS-2: the Finnish intercity's double-deck control car (the
/// 2010 green and white livery), the coach's body with a cab at one end,
/// as the local studio modelled it in Blender from photographs (27.40 m
/// between couplers, 3.20 m wide, 5.20 m tall, on the 1,524 mm gauge), one
/// palette colour a triangle (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-ic-control-car-2026-11/revision-3`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// Every intercity runs one at its back, push-pull, so the
/// intercity's sets (``Map3DTrainSet/finlandIntercity(sr3:far:)``) end with
/// it, its cab facing back. No company mark, lettering or picture is drawn.
public enum Map3DFinlandControlCar {
    /// The car, its cab at +x.
    public static let name = "finland-ic-control-car-cab"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, roofSilver, green, steel, mask, glass, taillamp,
    /// hardware, dark, headlamp. The double-deck coach's colours
    /// (``Map3DFinlandDoubleDeck``) and the headlamps' white; no new colour.
    static let meshPalette: [UInt32] = Map3DFinlandDoubleDeck.meshPalette + [Map3DTrainStyle.headlamp]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night (the cab's,
    /// at the car's end, are not lit).
    static let glassIndex = Map3DFinlandDoubleDeck.glassIndex

    /// The car; `far`, the light version drawn from 500 m out. `nil` if
    /// its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}
