import Foundation

/// Decision 914: the Finnish closed car carrier (Gd), the white car with
/// the green band and green ramp panels the night trains to and from
/// Rovaniemi carry at their back, as the local studio modelled it in
/// Blender from photographs (26.70 m between buffers, on the 1,524 mm
/// gauge), one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-car-carrier-2026-11/revision-1`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// No company mark or lettering is drawn. The night train's last cars
/// (``Map3DTrainSet/finlandNight(sr3:far:)``).
public enum Map3DFinlandCarCarrier {
    /// The car.
    public static let name = "finland-car-carrier"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, roofSilver, green, mask, hardware, dark, taillamp, the
    /// double-deck coach's colours of the same names
    /// (``Map3DFinlandDoubleDeck/meshPalette``); no new colour.
    static let meshPalette: [UInt32] = {
        let coach = Map3DFinlandDoubleDeck.meshPalette
        return [coach[0], coach[1], coach[2], coach[4], coach[7], coach[8], coach[6]]
    }()

    /// The car; `far`, the light version drawn from 500 m out. `nil` if
    /// its mesh does not decode. It has no glass.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }
}
