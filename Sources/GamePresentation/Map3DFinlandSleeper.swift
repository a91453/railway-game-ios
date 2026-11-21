import Foundation

/// FINLAND-TRAINS-2: the Finnish night train's double-deck sleeping car
/// (the green and white livery), as the local studio modelled it in
/// Blender from photographs (26.40 m between couplers, 3.20 m wide, 5.20 m
/// tall its whole length, on the 1,524 mm gauge): the compartments' wide
/// windows on one side, the corridor's narrow ones on the other, one
/// palette colour a triangle (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-sleeper-double-deck-2026-11/revision-6`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// No company mark, lettering or the doors' pictures is drawn.
public enum Map3DFinlandSleeper {
    /// The car.
    public static let name = "finland-sleeper-double-deck-coach"

    /// The keys of the night train's sets: the Sr2 or the Sr3 and the
    /// sleeping cars.
    public static let key = "finlandNight"
    public static let sr3Key = "finlandNightSr3"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the double-deck coach's
    /// (``Map3DFinlandDoubleDeck``), material for material; no new colour.
    static let meshPalette: [UInt32] = Map3DFinlandDoubleDeck.meshPalette

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night.
    static let glassIndex = Map3DFinlandDoubleDeck.glassIndex

    /// The car; `far`, the light version drawn from 500 m out. `nil` if
    /// its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DFinlandSleeper {
    /// Decision 782: the night train's sets (behind the Sr2 and behind the
    /// Sr3), near and far, its showcase row and its cars' triangles (the
    /// sleeping car 6,790 near and 2,904 far, the Sr2 11,644 and 4,116, the
    /// Sr3 4,816 and 2,200, decision 914's closed car carrier 4,560 and
    /// 2,190, decision 916's open one 5,336 and 2,448) and lengths (the
    /// locomotives 19.02 and 19.05 m, the sleeping car and the open car
    /// carrier 26.40 m, the closed one 26.70 m).
    static let registration = Map3DTrainRegistration(
        id: "finlandNight",
        sets: [Map3DTrainSet.finlandNight(sr3: false), .finlandNight(sr3: false, far: true),
               .finlandNight(sr3: true), .finlandNight(sr3: true, far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Finnish night train, double-deck sleepers (Sr2)", "芬蘭夜車（雙層臥鋪車，Sr2）", .finland,
                                cars: Map3DFinlandSr2.cars, most: 10, gauge: 1.524),
            Map3DShowcase.Entry(sr3Key, "Finnish night train, double-deck sleepers (Sr3)", "芬蘭夜車（雙層臥鋪車，Sr3）", .finland,
                                cars: Map3DFinlandSr2.cars, most: 10, gauge: 1.524),
        ],
        triangles: 2_190...11_700, length: 19.0...26.75)
}

extension Map3DTrainSet {
    /// FINLAND-TRAINS-2: the night train, its locomotive (the Sr2, or the
    /// Sr3 when `sr3`) and its double-deck sleeping cars at their own
    /// lengths, the locomotive's front lamps lit. Decision 914: its last
    /// two cars the car carriers, the last the closed one
    /// (``Map3DFinlandCarCarrier``) with its tail lamps lit, decision 916:
    /// the one before it the open one (``Map3DFinlandCarCarrierGfot``); of
    /// a train of fewer than seven cars only the last.
    static func finlandNight(sr3: Bool, far: Bool = false) -> Map3DTrainSet {
        let key = sr3 ? Map3DFinlandSleeper.sr3Key : Map3DFinlandSleeper.key
        return Map3DTrainSet(key: far ? key + "Far" : key, centreCars: [Map3DFinlandSr2.cars - 2], ownLengths: true,
                             far: far ? nil : key + "Far") {
            let sleeper = Map3DFinlandSleeper.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: false).model(named: Map3DFinlandSleeper.name)
            let carrier = Map3DFinlandCarCarrier.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: false).model(named: Map3DFinlandCarCarrier.name)
            let open = Map3DFinlandCarCarrierGfot.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: false).model(named: Map3DFinlandCarCarrierGfot.name)
            return Cars(head: litLenses(finlandLocomotive(sr3: sr3, far: far), front: true), middle: sleeper,
                        tail: litLenses(carrier, front: false), single: nil, centre: open)
        }
    }

    /// The Finnish locomotive at the head of an intercity or a night
    /// train; a model that fails to decode draws as a plain cab car of its
    /// length rather than nothing.
    static func finlandLocomotive(sr3: Bool, far: Bool) -> Map3DModelPack.Model {
        sr3 ? Map3DFinlandSr3.model(far: far) ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: Map3DFinlandSr3.name)
            : Map3DFinlandSr2.model(far: far) ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: Map3DFinlandSr2.name)
    }
}
