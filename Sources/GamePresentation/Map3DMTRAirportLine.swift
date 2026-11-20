import Foundation

/// Decision 780: the eight-car trains of Hong Kong's airport railway, built
/// 1996–97 for both of its lines, as the local studio modelled them in
/// Blender from photographs and the published dimensions (cab cars 24.6 m,
/// the others 22.5 m, 3.096 m wide, 3.7 m tall), one palette colour a
/// triangle, the windows, doors and bands faces of their own
/// (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/mtr-airport-line-2026-11/revision-5`), and
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
    /// headlamp, taillamp, steel, hardware, dark; the roof, light grey as in
    /// the photographs, is the silver (studio revision 5). The glass and lamp lenses
    /// are the colours the game lights at night and the glass catches the
    /// sky in (``Map3DTrainLights``, ``Map3DTrainMaterial``).
    static let meshPalette: [UInt32] = [
        Map3DPalette.mtrAirportBlue, Map3DPalette.mtrTeal, Map3DPalette.mtrPearl, Map3DPalette.mtrSilver,
        Map3DPalette.mtrCream, Map3DPalette.mtrRed, Map3DPalette.mtrSilver, Map3DColor.rgb(0x1D2125),
        Map3DTrainStyle.glass, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DColor.rgb(0x7A858E),
        Map3DColor.rgb(0x4B535C), Map3DColor.rgb(0x30363D),
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in. The dark greys round the doors and windows are close
    /// to the glass in colour and stay dark (decision 450's later note).
    static let glassIndex = 8

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

/// Decision 780: the Hong Kong airport railway's trains
/// (``Map3DMTRAirportLine``), from photographs: the Airport Express's
/// royal blue, teal stripe and pearl lower body; the Tung Chung line's
/// silver-grey, cream lower body and red line, the red lamp band both
/// share. The roofs take the silver (studio revision 5). Decision 782: kept with the train.
extension Map3DPalette {
    public static let mtrAirportBlue = Map3DColor.rgb(0x2457C0)
    public static let mtrTeal = Map3DColor.rgb(0x1C9C93)
    public static let mtrPearl = Map3DColor.rgb(0xDCDDD6)
    public static let mtrSilver = Map3DColor.rgb(0xA5AAAF)
    public static let mtrCream = Map3DColor.rgb(0xE2DAC4)
    public static let mtrRed = Map3DColor.rgb(0xC1272F)
}

extension Map3DMTRAirportLine {
    /// Decision 782: the two lines' sets, near and far, their showcase
    /// rows (eight cars each) and their cars' triangles (4,446 to 7,701
    /// near and 1,019 to 1,794 far) and lengths (the cab cars 24.6 m).
    static let registration = Map3DTrainRegistration(
        id: "mtrAirportLine",
        sets: [Map3DTrainSet.mtrAirportExpress(), .mtrAirportExpress(far: true), .mtrTungChung(), .mtrTungChung(far: true)],
        showcase: [
            Map3DShowcase.Entry(expressKey, "Hong Kong Airport Express train", "香港機場快綫列車", .hongKong, cars: 8, fixed: true),
            Map3DShowcase.Entry(tungChungKey, "Hong Kong Tung Chung line train", "香港東涌綫列車", .hongKong, cars: 8, fixed: true),
        ],
        triangles: 1_000...8_000, length: 22.4...24.7)
}

extension Map3DTrainSet {
    /// Decision 780: the local studio's cars of Hong Kong's airport
    /// railway (``Map3DMTRAirportLine``), each its own length, laid from
    /// the front as the real eight cars run: the Airport Express's E F G H
    /// F G J K, its baggage car K turned round at the back, the pantograph
    /// on the fourth car (H); the Tung Chung line's V W X Y W X Z V, the
    /// cab car turned round at the back, the pantograph on Y. The ends'
    /// lamp lenses lit. Before the pack has its models, the generic metro
    /// car (``fallback``).
    static func mtrAirportLine(_ key: String, far: Bool, head: Map3DMTRAirportLine.Unit, tail: Map3DMTRAirportLine.Unit,
                               car: Map3DMTRAirportLine.Unit, pantograph: Map3DMTRAirportLine.Unit) -> Map3DTrainSet {
        Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.middle, .middle, .pantograph, .middle, .middle, .middle],
                      cycleFromFront: true, ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DMTRAirportLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DMTRAirportLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.cab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(head), front: true), middle: model(car), tail: litLenses(model(tail).turned, front: false),
                        single: nil, pantograph: model(pantograph))
        }
    }

    /// Decision 780: the Airport Express's eight cars.
    static func mtrAirportExpress(far: Bool = false) -> Map3DTrainSet {
        mtrAirportLine(Map3DMTRAirportLine.expressKey, far: far, head: .expressCab, tail: .expressBaggage,
                       car: .expressCar, pantograph: .expressPantograph)
    }

    /// Decision 780: the Tung Chung line's eight cars.
    static func mtrTungChung(far: Bool = false) -> Map3DTrainSet {
        mtrAirportLine(Map3DMTRAirportLine.tungChungKey, far: far, head: .localCab, tail: .localCab,
                       car: .localCar, pantograph: .localPantograph)
    }
}
