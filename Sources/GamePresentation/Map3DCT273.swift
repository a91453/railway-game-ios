import Foundation

/// Decision 930: the Taiwan Railway's CT273 steam locomotive and its
/// tender, the Midsummer Formosa's, as the local studio modelled it in
/// Blender from photographs (the locomotive 13.40 m between its coupler
/// faces, 2.96 m wide, 3.945 m tall; the tender 6.88 m; on the 1,067 mm
/// gauge): black, with the white lines along its running boards and the
/// white wheel rims, the red rods and number plates, the smoke
/// deflectors and the one headlamp, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/tra-ct273-steam-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``). No
/// lettering or number is drawn. The Midsummer Formosa's locomotive
/// (``Map3DTrainSet/steam(_:formation:coach:far:)``).
public enum Map3DCT273 {
    /// The two units.
    public enum Unit: String, CaseIterable, Sendable {
        case locomotive = "tra-ct273-loco"
        case tender = "tra-ct273-tender"
    }

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names body, white, rods, coal, hardware, glass, taillamp, headlamp.
    /// The Midsummer Formosa's black (``TrainLivery/midsummerFormosa``'s
    /// cab), the cable cars' white and red, the palette's dark, the urban
    /// line train's hardware grey (decision 786), the trains' glass and
    /// the lamps; no new colour.
    static let meshPalette: [UInt32] = [
        Map3DColor.rgb(UInt32(TrainLivery.midsummerFormosa.cab ?? 0)), CableParts.Paint.white, CableParts.Paint.red, Map3DPalette.dark,
        Map3DMTRUrbanLine.meshPalette[10], Map3DTrainStyle.glass, Map3DPalette.lantern, Map3DTrainStyle.headlamp,
    ]

    /// `unit`, its front at +x; `far`, the light version drawn from
    /// 500 m out. `nil` if its mesh does not decode. Its cab's windows are
    /// not marked as glass: they do not light at night.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }
}
