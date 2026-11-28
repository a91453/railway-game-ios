import Foundation

/// Decision 1041 (continued): the Kumamoto City Tram's two-section
/// low-floor tram (the 0800 type's, from 2009), its two sections and the
/// short articulation between them as one model, as the local studio
/// modelled it in Blender from photographs (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/kumamoto-tram-lowfloor-2026-11/revision-6`,
/// its `tools/build.py`), written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// The real tram: 18.40 m over both sections, 2.40 m wide, its roof 3.407 m
/// up and its single-arm pantograph raised to 5.10 m (as it always is on
/// the street), its floor 0.36 m, on the 1,435 mm gauge. The white body,
/// the wine side band round the windows and doors (``Map3DPalette/kumamotoWine``),
/// the navy V-shaped lamp band under each end's large curved windscreen,
/// two doors a side, point-symmetric. A cab at each end, so the model is
/// the same turned round. No company mark, lettering, number or
/// destination text is drawn.
public enum Map3DKumamotoTram {
    /// The studio's file name of the near model (the far one adds `-far`).
    public static let name = "kumamoto-tram-lowfloor"

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "kumamotoTram"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, wine, navy, glass, steel, dark, headlamp, taillamp.
    /// The tile white, the new wine, the EMU800's navy (the nearest to the
    /// photographs' lamp band), the trains' glass, the palette's steel and
    /// dark, and the lamps.
    static let meshPalette: [UInt32] = [
        Map3DPalette.tileWhite, Map3DPalette.kumamotoWine, Map3DEMU800.navy, Map3DTrainStyle.glass,
        Map3DPalette.steel, Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night.
    static let glassIndex = 3

    /// The tram, a cab at each end; `far`, the light version drawn from
    /// 500 m out. `nil` if its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }

    /// Decision 782: its sets, near and far, its showcase row and its
    /// models' triangles (7,526 near, 3,670 far) and length.
    static let registration = Map3DTrainRegistration(
        id: "kumamotoTram",
        sets: [Map3DTrainSet.kumamotoTram(), .kumamotoTram(far: true)],
        showcase: [Map3DShowcase.Entry(key, "Kumamoto City Tram low-floor tram", "熊本市電低地板電車", .japan, cars: 1, fixed: true,
                                       gauge: 1.435)],
        triangles: 3_500...7_600, length: 18.35...18.45)
}

extension Map3DPalette {
    /// Decision 1041 (continued): the Kumamoto low-floor tram's side band,
    /// a red-purple (the photographs' #902838 to #903848), which no colour
    /// of the palette is near (its reds read as a shop sign's red); the
    /// owner agreed to the new colour on 2026-11-28 (rule 56).
    public static let kumamotoWine = Map3DColor.rgb(0x943040)
}

extension Map3DTrainSet {
    /// Decision 1041 (continued): the Kumamoto tram (``Map3DKumamotoTram``),
    /// one model a train, the lamp lenses at both its ends lit (decision
    /// 449 then shows each frame's front and back ones). Before its mesh
    /// decodes, a plain car of its length.
    static func kumamotoTram(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DKumamotoTram.key
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, fixedCars: 1, far: far ? nil : key + "Far") {
            let car = litLenses(Map3DKumamotoTram.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: Map3DKumamotoTram.name), front: true)
            return Cars(head: car, middle: nil, tail: nil, single: litLenses(car, front: false))
        }
    }
}
