import Foundation

/// Decision 851: the three-car train of Hong Kong's South Island line (the
/// driverless trains it opened with in 2016, a short version of the Kwun
/// Tong line's), as the local studio modelled them in Blender from
/// photographs and the published width (3.12 m; the cab car about 23.0 m
/// and the middle car 22.0 m, measured from the photographs), one palette
/// colour a triangle, the doors, windows and red lines faces of their own
/// (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/mtr-south-island-line-2026-11/revision-4`),
/// and written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A flatter front than the urban line train's, a black mask edged by a
/// red U that runs on along the eaves of every car, small round headlamps
/// in dark housings, a stainless silver body whose doors and window bays
/// are nearly all dark grey, five pairs of doors a side. No company mark is
/// drawn.
public enum Map3DMTRSouthIslandLine {
    /// The cars the game draws: the cab car (A) and the middle car with a
    /// pantograph (B).
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "mtr-south-island-line-cab"
        case pantograph = "mtr-south-island-line-pantograph"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 23.0 : 22.0 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "mtrSouthIslandLine"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names silver, frontSilver, roofSilver, charcoal, mtrRed, mask, glass,
    /// headlamp, taillamp, steel, hardware, dark. The urban line train's
    /// colours (decision 786); no new colour (this train's models do not
    /// use roofSilver: its roof is steel).
    static let meshPalette: [UInt32] = [
        Map3DPalette.mtrSilver, Map3DPalette.mtrFrontSilver, Map3DPalette.mtrRoofSilver, Map3DPalette.mtrCharcoal,
        Map3DPalette.mtrRed, Map3DColor.rgb(0x1D2125), Map3DTrainStyle.glass, Map3DTrainStyle.headlamp,
        Map3DPalette.lantern, Map3DColor.rgb(0x7A858E), Map3DColor.rgb(0x4B535C), Map3DColor.rgb(0x30363D),
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in. The black mask and window frames and the dark grey
    /// doors and bays are close to the glass in colour and stay dark
    /// (decision 450's later note).
    static let glassIndex = 6

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DMTRSouthIslandLine {
    /// Decision 782: its set, near and far, its showcase row (three cars)
    /// and its cars' triangles (7,890 to 11,456 near and 3,186 to 4,984
    /// far) and lengths (the cab car 23.0 m).
    static let registration = Map3DTrainRegistration(
        id: "mtrSouthIslandLine",
        sets: [Map3DTrainSet.mtrSouthIslandLine(), .mtrSouthIslandLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Hong Kong South Island line train", "香港南港島綫列車", .hongKong, cars: 3, fixed: true),
        ],
        triangles: 3_100...11_500, length: 21.9...23.1)
}

extension Map3DTrainSet {
    /// Decision 851: the local studio's South Island line cars
    /// (``Map3DMTRSouthIslandLine``), each its own length, laid as the
    /// real three cars run, A B A: the cab car, the pantograph car between
    /// (``Map3DTrainSet/cycleFromFront``), the second cab car turned round
    /// at the back. The ends' lamp lenses lit. Before the pack has its
    /// models, the generic metro car (``fallback``).
    static func mtrSouthIslandLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DMTRSouthIslandLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.pantograph], cycleFromFront: true,
                             ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DMTRSouthIslandLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DMTRSouthIslandLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.pantograph),
                        tail: litLenses(model(.cab).turned, front: false), single: nil, pantograph: model(.pantograph))
        }
    }
}
