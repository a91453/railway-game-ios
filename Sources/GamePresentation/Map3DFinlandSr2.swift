import Foundation

/// Decision 864: the Finnish Sr2 electric locomotive (green and white, the
/// livery it runs in now), as the local studio modelled it in Blender
/// from photographs and the published dimensions (19.02 m over buffers,
/// 3.00 m wide, 4.31 m to its lowered pantographs, Bo'Bo' on the 1,524 mm
/// gauge): a rounded cab at each end with a raked windscreen, the grey
/// roof band with its row of grilles, the green band and the green slanted
/// block at each side's left-hand end, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-sr2-loco-2026-11/revision-4`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``). No
/// company mark, lettering or number is drawn. Its cab windows are dark
/// and mirror the sky, but none lights at night (``maskIndex``).
public enum Map3DFinlandSr2 {
    /// The locomotive, one of its cabs at +x.
    public static let name = "finland-sr2-loco"

    /// The key of the intercity's set (``Map3DTrainSet``): the Sr2 and
    /// its double-deck coaches (``Map3DFinlandDoubleDeck``).
    public static let key = "finlandIntercity"

    /// How many cars Rovaniemi's intercity and night trains are drawn
    /// with: the Sr2 and six coaches.
    public static let cars = 7

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, roofSilver, green, skirt, mask, steel, dark, headlamp,
    /// taillamp. The double-deck coach's colours and the urban line
    /// train's greys (decision 786); no new colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.cityConcreteWalls[4], Map3DPalette.mtrRoofSilver, Map3DPalette.crown, Map3DColor.rgb(0x4B535C),
        Map3DColor.rgb(0x1D2125), Map3DPalette.steel, Map3DColor.rgb(0x30363D), Map3DTrainStyle.headlamp,
        Map3DPalette.lantern,
    ]

    /// The locomotive; `far`, the light version drawn from 500 m out.
    /// `nil` if its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        guard let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: maskIndex) else { return nil }
        // Only the cabs' dark windows mirror the sky: the doors' and the
        // door panels' thin frames, the same dark, stay plain.
        var vertices = model.vertices
        for start in stride(from: 0, to: vertices.count, by: 3) where vertices[start].layer == Map3DVertex.trainGlass {
            let x = (vertices[start].x + vertices[start + 1].x + vertices[start + 2].x) / 3
            guard abs(x) < cabWindows else { continue }
            for i in start..<start + 3 { vertices[i].layer = Map3DVertex.plain }
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// The palette index of the studio's `mask`, the cab windows' dark
    /// (and the doors' frames'): the work order gives the Sr2 no glass,
    /// so no window of it lights at night; its windscreens and cab side
    /// windows still mirror the sky as glass (decision 450).
    static let maskIndex = 4

    /// How far from the middle the cab windows start, metres: the cab
    /// side windows at 7.00 m, the doors' frames inside 6.88 m.
    static let cabWindows: Float = 6.95
}

extension Map3DFinlandSr2 {
    /// Decision 782: its set, near and far, its showcase row and its
    /// cars' triangles (the Sr2 11,644 near and 4,116 far, the coach
    /// 6,736 and 3,076, FINLAND-TRAINS-2's control car 7,104 and 3,362)
    /// and lengths (the Sr2 19.02 m, the coach 26.40 m, the control car
    /// 27.40 m).
    static let registration = Map3DTrainRegistration(
        id: "finlandIntercity",
        sets: [Map3DTrainSet.finlandIntercity(), .finlandIntercity(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Finnish intercity, Sr2 electric", "芬蘭城際列車（Sr2 電力機車）", .finland,
                                cars: cars, most: 10, gauge: 1.524),
        ],
        triangles: 3_000...11_700, length: 19.0...27.45)
}

extension Map3DTrainSet {
    /// Decision 864: the Sr2 (``Map3DFinlandSr2``), or FINLAND-TRAINS-2's
    /// Sr3 (``Map3DFinlandSr3``) when `sr3`, and its double-deck coaches
    /// (``Map3DFinlandDoubleDeck``) at their own lengths, the locomotive's
    /// front lamps lit. FINLAND-TRAINS-2: the control car
    /// (``Map3DFinlandControlCar``) at the back, its cab facing back and
    /// its tail lamps lit, as every intercity runs push-pull.
    static func finlandIntercity(sr3: Bool = false, far: Bool = false) -> Map3DTrainSet {
        let key = sr3 ? Map3DFinlandSr3.key : Map3DFinlandSr2.key
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, far: far ? nil : key + "Far") {
            // A model that fails to decode draws as a plain car of its
            // length rather than nothing.
            let coach = Map3DFinlandDoubleDeck.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: false).model(named: Map3DFinlandDoubleDeck.name)
            let control = Map3DFinlandControlCar.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: Map3DFinlandControlCar.name)
            return Cars(head: litLenses(finlandLocomotive(sr3: sr3, far: far), front: true), middle: coach,
                        tail: litLenses(control.turned, front: false), single: nil)
        }
    }
}
