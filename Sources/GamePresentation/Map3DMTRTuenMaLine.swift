import Foundation

/// Decision 839: the eight-car train of Hong Kong's Tuen Ma line (the
/// trains built from 2003 for the West Rail and Ma On Shan lines, joined
/// into one line in 2021), as the local studio modelled them in Blender
/// from photographs and the published dimensions (cab cars 25.28 m, the
/// others 24.136 m, 3.1 m wide), one palette colour a triangle, the doors,
/// windows and blue band faces of their own (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/mtr-tuen-ma-line-2026-11/revision-4`), and
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A round bullet nose with a wide wrap-round windscreen, a stainless
/// silver body with a navy band along the windows, red doors, five pairs
/// a side. No company mark is drawn.
public enum Map3DMTRTuenMaLine {
    /// The cars the game draws: the cab car (D), the car without a
    /// pantograph (M and T, alike outside) and the one with (P).
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "mtr-tuen-ma-line-cab"
        case car = "mtr-tuen-ma-line-car"
        case pantograph = "mtr-tuen-ma-line-pantograph"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 25.28 : 24.136 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "mtrTuenMaLine"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names silver, frontSilver, roofSilver, navy, mtrRed, mask, glass,
    /// headlamp, taillamp, steel, hardware, dark. The urban line train's
    /// colours (decision 786) but the navy band, the player's rim colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.mtrSilver, Map3DPalette.mtrFrontSilver, Map3DPalette.mtrRoofSilver, Map3DPalette.playerRim,
        Map3DPalette.mtrRed, Map3DColor.rgb(0x1D2125), Map3DTrainStyle.glass, Map3DTrainStyle.headlamp,
        Map3DPalette.lantern, Map3DColor.rgb(0x7A858E), Map3DColor.rgb(0x4B535C), Map3DColor.rgb(0x30363D),
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in. The dark greys round the doors and windows are close
    /// to the glass in colour and stay dark (decision 450's later note).
    static let glassIndex = 6

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DMTRTuenMaLine {
    /// Decision 782: its set, near and far, its showcase row (eight cars)
    /// and its cars' triangles (3,350 to 6,225 near and 1,530 to 2,117
    /// far) and lengths (the cab car 25.28 m).
    static let registration = Map3DTrainRegistration(
        id: "mtrTuenMaLine",
        sets: [Map3DTrainSet.mtrTuenMaLine(), .mtrTuenMaLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Hong Kong Tuen Ma line train", "香港屯馬綫列車", .hongKong, cars: 8, fixed: true),
        ],
        triangles: 1_500...6_300, length: 24.1...25.3)
}

extension Map3DTrainSet {
    /// Decision 839: the local studio's Tuen Ma line cars
    /// (``Map3DMTRTuenMaLine``), each its own length, laid as the real
    /// eight cars run, D P M T T M P D: the front half's cars after the cab
    /// one after another (``Map3DTrainSet/cycle``), the back half its
    /// mirror image with each car turned round, the second cab car turned
    /// round at the back. The ends' lamp lenses lit. Before the pack has
    /// its models, the generic metro car (``fallback``).
    static func mtrTuenMaLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DMTRTuenMaLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.pantograph, .middle, .centre],
                             ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DMTRTuenMaLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DMTRTuenMaLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.car), tail: litLenses(model(.cab).turned, front: false),
                        single: nil, pantograph: model(.pantograph), centre: model(.car),
                        middleBack: model(.car).turned, pantographBack: model(.pantograph).turned, centreBack: model(.car).turned)
        }
    }
}
