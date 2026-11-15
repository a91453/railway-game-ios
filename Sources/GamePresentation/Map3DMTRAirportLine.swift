import Foundation

/// Decision 780: the eight-car trains of Hong Kong's airport railway, built
/// 1996–97 for both of its lines, as the local studio modelled them in
/// Blender from photographs and the published dimensions (cab cars 24.6 m,
/// the others 22.5 m, 3.096 m wide, 3.7 m tall), one palette colour a
/// triangle, the windows, doors and bands faces of their own
/// (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/mtr-airport-line-2026-11/revision-4`), and
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// Two liveries on one shell: the Airport Express (royal blue, a teal
/// stripe over a pearl lower body behind the first bogie, a dark ribbon of
/// windows, two doors a side, and a baggage cab car at the airport end
/// with five container doors and no windows) and the Tung Chung line
/// (silver-grey, a cream lower body under a red line, five pairs of doors
/// a side). No company mark is drawn.
public enum Map3DMTRAirportLine {
    /// The cars the game draws: each line's cab car, its car without a
    /// pantograph (the Airport Express's F, G and J, the Tung Chung line's
    /// W, X and Z, alike outside) and the one with (H, Y), and the Airport
    /// Express's baggage cab car K.
    public enum Unit: String, CaseIterable, Sendable {
        case expressCab = "mtr-airport-express-cab"
        case expressCar = "mtr-airport-express-car"
        case expressPantograph = "mtr-airport-express-pantograph"
        case expressBaggage = "mtr-airport-express-baggage"
        case localCab = "mtr-tung-chung-cab"
        case localCar = "mtr-tung-chung-car"
        case localPantograph = "mtr-tung-chung-pantograph"

        public var cab: Bool { [.expressCab, .expressBaggage, .localCab].contains(self) }
        public var pitch: Float { cab ? 24.6 : 22.5 }
    }

    /// The keys of the two lines' sets (``Map3DTrainSet``).
    public static let expressKey = "mtrAirportExpress"
    public static let tungChungKey = "mtrTungChung"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names aelBlue, teal, pearl, silver, cream, mtrRed, roof, mask, glass,
    /// headlamp, taillamp, steel, hardware, dark. The glass and lamp lenses
    /// are the colours the game lights at night and the glass catches the
    /// sky in (``Map3DTrainLights``, ``Map3DTrainMaterial``).
    static let meshPalette: [UInt32] = [
        Map3DPalette.mtrAirportBlue, Map3DPalette.mtrTeal, Map3DPalette.mtrPearl, Map3DPalette.mtrSilver,
        Map3DPalette.mtrCream, Map3DPalette.mtrRed, Map3DPalette.mtrRoof, Map3DColor.rgb(0x1D2125),
        Map3DTrainStyle.glass, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DColor.rgb(0x7A858E),
        Map3DColor.rgb(0x4B535C), Map3DColor.rgb(0x30363D),
    ]

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }
}
