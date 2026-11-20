import Foundation

/// Decision 786: the eight-car train of Hong Kong's urban lines (the Tsuen
/// Wan, Kwun Tong, Island and Tseung Kwan O lines), the new trains that
/// entered service from 2022 and replace the old ones by 2028, as the local
/// studio modelled them in Blender from photographs and the published
/// dimensions (cab cars 24.6 m, the others 22.55 m, about 3.1 m wide,
/// 3.7 m tall), one palette colour a triangle, the doors, windows and red
/// lines faces of their own (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/mtr-urban-line-2026-11/revision-6`), and
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A black front edged by a red U that runs on along the eaves of every
/// car, a stainless silver body with the doors and window bays in dark
/// grey, five pairs of doors a side. No company mark is drawn.
public enum Map3DMTRUrbanLine {
    /// The cars the game draws: the cab car (A), the car without a
    /// pantograph (B) and the one with (C), alike outside but for it.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "mtr-urban-line-cab"
        case car = "mtr-urban-line-car"
        case pantograph = "mtr-urban-line-pantograph"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 24.6 : 22.55 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "mtrUrbanLine"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names silver, frontSilver, roofSilver, charcoal, mtrRed, mask, glass,
    /// headlamp, taillamp, steel, hardware, dark. The glass and lamp lenses
    /// are the colours the game lights at night and the glass catches the
    /// sky in (``Map3DTrainLights``, ``Map3DTrainMaterial``).
    static let meshPalette: [UInt32] = [
        Map3DPalette.mtrSilver, Map3DPalette.mtrFrontSilver, Map3DPalette.mtrRoofSilver, Map3DPalette.mtrCharcoal,
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

/// Decision 786: the urban line train's own colours, from photographs:
/// the brighter silver of the front's frame, the light stainless roof and
/// the dark grey of its doors and window bays (its body silver and red
/// lines are the airport railway's, decision 780). Kept with the train
/// (decision 782).
extension Map3DPalette {
    public static let mtrFrontSilver = Map3DColor.rgb(0xC4C8CB)
    public static let mtrRoofSilver = Map3DColor.rgb(0xB4B9BD)
    public static let mtrCharcoal = Map3DColor.rgb(0x464B51)
}

extension Map3DMTRUrbanLine {
    /// Decision 782: its set, near and far, its showcase row (eight cars)
    /// and its cars' triangles (7,082 to 8,915 near and 2,338 to 3,125 far)
    /// and lengths (the cab car 24.6 m).
    static let registration = Map3DTrainRegistration(
        id: "mtrUrbanLine",
        sets: [Map3DTrainSet.mtrUrbanLine(), .mtrUrbanLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Hong Kong urban line train", "香港市區綫列車", .hongKong, cars: 8, fixed: true),
        ],
        triangles: 2_000...9_000, length: 22.5...24.7)
}

extension Map3DTrainSet {
    /// Decision 786: the local studio's urban line cars
    /// (``Map3DMTRUrbanLine``), each its own length, laid from the front
    /// as the real eight cars run, A C B C B C B A: a pantograph on each C
    /// car, the second cab car turned round at the back. The ends' lamp
    /// lenses lit. Before the pack has its models, the generic metro car
    /// (``fallback``).
    static func mtrUrbanLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DMTRUrbanLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.pantograph, .middle],
                             cycleFromFront: true, ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DMTRUrbanLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DMTRUrbanLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.car), tail: litLenses(model(.cab).turned, front: false),
                        single: nil, pantograph: model(.pantograph))
        }
    }
}
