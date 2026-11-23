import Foundation

/// Decision 930: the Finnish single-deck restaurant car (Rx), the low car
/// among the night train's double-deck ones, half green and half white
/// with a green band, as the local studio modelled it in Blender from
/// photographs (26.40 m between couplers, 3.20 m wide, 3.97 m tall, on the
/// 1,524 mm gauge), one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-restaurant-car-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// No company mark, lettering or picture is drawn. A car in the middle of
/// the night train (``Map3DTrainSet/finlandNight(sr3:far:)``).
public enum Map3DFinlandRestaurantCar {
    /// The car.
    public static let name = "finland-restaurant-car"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the double-deck coach's
    /// (``Map3DFinlandDoubleDeck``), material for material; no new colour.
    static let meshPalette: [UInt32] = Map3DFinlandDoubleDeck.meshPalette

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night.
    static let glassIndex = Map3DFinlandDoubleDeck.glassIndex

    /// The car; `far`, the light version drawn from 500 m out. `nil` if
    /// its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}
