import Foundation

/// Decision 852: the four-car train of Hong Kong's Disneyland Resort line
/// (the three trains rebuilt in 2005 from the urban lines' first cars of
/// 1979, three pairs of doors a side), as the local studio modelled them
/// in Blender from photographs and the dispatch's lengths (the cab car
/// 22.85 m, the middle car 22.00 m, 3.11 m wide), one palette colour a
/// triangle, the doors, windows and lines faces of their own
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/mtr-disneyland-line-2026-11/revision-5`),
/// and written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A white body with a dark blue lower band and roof, a thin gold line in
/// the band, a blue mask framed by a gold U and a red band on the front,
/// round and oval windows. No company or park mark, character shape or
/// lettering is drawn.
public enum Map3DMTRDisneylandLine {
    /// The cars the game draws: the cab car (A) and the middle car with a
    /// pantograph (C).
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "mtr-disneyland-line-cab"
        case pantograph = "mtr-disneyland-line-pantograph"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 22.85 : 22.0 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "mtrDisneylandLine"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names pearl, blue, gold, mtrRed, roofSilver, mask, glass, headlamp,
    /// taillamp, steel, hardware, dark. Colours the game has already
    /// (the dispatch's table): the Airport Express's pearl, the player's
    /// dark blue, the platform edge's gold and the urban line train's
    /// greys; no new colour. The real blue is a little lighter and more
    /// violet; kept, as the coordinator decided.
    static let meshPalette: [UInt32] = [
        Map3DPalette.mtrPearl, Map3DPalette.playerRim, Map3DPalette.platformEdge, Map3DPalette.mtrRed,
        Map3DPalette.mtrRoofSilver, Map3DColor.rgb(0x1D2125), Map3DTrainStyle.glass, Map3DTrainStyle.headlamp,
        Map3DPalette.lantern, Map3DColor.rgb(0x7A858E), Map3DColor.rgb(0x4B535C), Map3DColor.rgb(0x30363D),
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in. The dark blue of the mask, roof and band, the black
    /// window frames and the dark greys are close to the glass in colour
    /// and stay dark (decision 450's later note).
    static let glassIndex = 6

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DMTRDisneylandLine {
    /// Decision 782: its set, near and far, its showcase row (four cars)
    /// and its cars' triangles (9,502 to 11,862 near and 3,418 to 5,150
    /// far) and lengths (the cab car 22.85 m).
    static let registration = Map3DTrainRegistration(
        id: "mtrDisneylandLine",
        sets: [Map3DTrainSet.mtrDisneylandLine(), .mtrDisneylandLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Hong Kong Disneyland Resort line train", "香港迪士尼綫列車", .metro, cars: 4, fixed: true),
        ],
        triangles: 3_400...11_900, length: 21.9...22.9)
}

extension Map3DTrainSet {
    /// Decision 852: the local studio's Disneyland Resort line cars
    /// (``Map3DMTRDisneylandLine``), each its own length, laid as the
    /// real four cars run, A C C A: the cab car, the two pantograph cars
    /// between (``Map3DTrainSet/cycleFromFront``), the second cab car
    /// turned round at the back. The ends' lamp lenses lit. Before the
    /// pack has its models, the generic metro car (``fallback``).
    static func mtrDisneylandLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DMTRDisneylandLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.pantograph], cycleFromFront: true,
                             ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DMTRDisneylandLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DMTRDisneylandLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.pantograph),
                        tail: litLenses(model(.cab).turned, front: false), single: nil, pantograph: model(.pantograph))
        }
    }
}
