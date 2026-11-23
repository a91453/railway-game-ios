import Foundation

/// Decision 930: the Taiwan Railway's EMU100 Tze-Chiang, as the local
/// studio modelled it in Blender from photographs (each car 20.00 m
/// between its coupling planes, 2.80 m wide, 3.80 m from the rail to the
/// roof, on the 1,067 mm gauge): the cream body with the yellow-orange
/// band under its windows, the orange cab end with its two lamps on the
/// roof, the grey roof and the folded pantograph, one palette colour a
/// triangle (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/tra-emu100-2026-11/revision-2`), written
/// here by `tools/train-models/glb_to_swift.py` (``encoded``). No company
/// mark, lettering or number is drawn.
public enum Map3DEMU100 {
    /// The cars the game draws: the cab car and the middle car.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "tra-emu100-cab"
        case middle = "tra-emu100-middle"

        public var isCab: Bool { self == .cab }
    }

    /// The key of its set (``Map3DTrainSet``): the type's code, so every
    /// EMU100 the player runs is drawn as it.
    public static let key = "EMU100"

    /// How many cars a set has (Chinese Wikipedia's 編組: five).
    public static let cars = 5

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names body, stripe, cab, roof, mask, glass, hardware, dark,
    /// taillamp, headlamp. The game's EMU100 livery
    /// (``TrainLivery/emu100``), the urban line train's roof silver, mask
    /// and greys (decision 786) and the lamps; no new colour.
    static let meshPalette: [UInt32] = [
        colour(TrainLivery.emu100.body), colour(TrainLivery.emu100.stripe), colour(TrainLivery.emu100.cab),
        Map3DPalette.mtrRoofSilver, Map3DMTRUrbanLine.meshPalette[5], Map3DTrainStyle.glass,
        Map3DMTRUrbanLine.meshPalette[10], Map3DMTRUrbanLine.meshPalette[11], Map3DPalette.lantern, Map3DTrainStyle.headlamp,
    ]

    private static func colour(_ rgb: Int?) -> UInt32 { Map3DColor.rgb(UInt32(rgb ?? 0)) }

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in.
    static let glassIndex = 5

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DEMU100 {
    /// Decision 782: its set, near and far, its showcase row and its
    /// cars' triangles (3,248 and 1,812 near, 1,140 and 668 far) and
    /// length (20.00 m).
    static let registration = Map3DTrainRegistration(
        id: "emu100",
        sets: [Map3DTrainSet.emu100(), .emu100(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "EMU100 Tze-Chiang", "EMU100 自強號", .taiwanRailway, cars: cars, most: 15),
        ],
        triangles: 660...3_300, length: 19.95...20.05)
}

extension Map3DTrainSet {
    /// Decision 930: the local studio's EMU100 cars (``Map3DEMU100``) in
    /// place of the plain commuter shell the type borrowed (decision
    /// 252): a cab car at each end, the back one turned round, and middle
    /// cars between; the ends' lamp lenses lit. Its models reach their
    /// coupling planes, so the cars are laid end to end.
    static func emu100(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DEMU100.key
        return Map3DTrainSet(key: far ? key + "Far" : key, far: far ? nil : key + "Far", reachesCouplers: true) {
            func model(_ unit: Map3DEMU100.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as the commuter shell
                // it had before rather than nothing.
                Map3DEMU100.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.middle), tail: litLenses(model(.cab).turned, front: false),
                        single: nil)
        }
    }
}
