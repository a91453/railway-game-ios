import Foundation

/// Decision 843: the nine-car train of Hong Kong's East Rail line (the
/// trains that entered service from 2021 and run the whole line since
/// 2022), as the local studio modelled them in Blender from photographs
/// and the published dimensions (cab cars 25.00 m, the others 24.136 m,
/// 3.22 m wide), one palette colour a triangle, the doors, windows and red
/// lines faces of their own (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/mtr-east-rail-line-2026-11/revision-6`), and
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A rounded front with a tall black mask edged by a red U that runs on
/// along the eaves of every car, a stainless silver body with the doors and
/// window bays in dark grey, five pairs of doors a side (two on the first
/// class car). No company mark is drawn.
public enum Map3DMTREastRailLine {
    /// The cars the game draws: the cab car (D), the car without a
    /// pantograph (M), the one with (P) and the first class car (F).
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "mtr-east-rail-line-cab"
        case car = "mtr-east-rail-line-car"
        case pantograph = "mtr-east-rail-line-pantograph"
        case first = "mtr-east-rail-line-first"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 25.0 : 24.136 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "mtrEastRailLine"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names silver, frontSilver, roofSilver, charcoal, mtrRed, mask, glass,
    /// headlamp, taillamp, steel, hardware, dark. The urban line train's
    /// colours (decision 786); no new colour.
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

extension Map3DMTREastRailLine {
    /// Decision 782: its set, near and far, its showcase row (nine cars)
    /// and its cars' triangles (6,098 to 11,614 near and 2,554 to 4,008
    /// far) and lengths (the cab car 25.00 m).
    static let registration = Map3DTrainRegistration(
        id: "mtrEastRailLine",
        sets: [Map3DTrainSet.mtrEastRailLine(), .mtrEastRailLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Hong Kong East Rail line train", "香港東鐵綫列車", .hongKong, cars: 9, fixed: true),
        ],
        triangles: 2_500...11_700, length: 24.1...25.1)
}

extension Map3DTrainSet {
    /// Decision 843: the local studio's East Rail line cars
    /// (``Map3DMTREastRailLine``), each its own length, laid from the front
    /// as the real nine cars run, D P M F P M M P D
    /// (``Map3DTrainSet/cycleFromFront``): the first class car (F) fourth,
    /// the last pantograph car and the back cab car turned round, so the two
    /// ends mirror each other. The ends' lamp lenses lit. Before the pack
    /// has its models, the generic metro car (``fallback``).
    static func mtrEastRailLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DMTREastRailLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key,
                             cycle: [.pantograph, .middle, .centre, .pantograph, .middle, .middle, .fourth],
                             cycleFromFront: true, ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DMTREastRailLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DMTREastRailLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.car), tail: litLenses(model(.cab).turned, front: false),
                        single: nil, pantograph: model(.pantograph), centre: model(.first), fourth: model(.pantograph).turned)
        }
    }
}
