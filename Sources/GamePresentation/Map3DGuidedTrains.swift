import Foundation

/// Decision 930: what the three guideway trains the local studio modelled
/// (``Map3DGuidedMonorail``, ``Map3DGuidedMaglev``, ``Map3DGuidedSkyrail``)
/// share: a white body with one band and one thin line under its windows,
/// which differ only in the band's and the line's colours, and a model
/// made about its guideway's running surface (decision 947 draws the
/// guideways, ``Map3DGuideway``).
enum Map3DGuidedTrains {
    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names body, band, accent, roof, mask, glass, hardware, dark, beam,
    /// taillamp, headlamp. The cable cars' white, `band` and `accent`
    /// (each train's own, colours the game has), the urban line train's
    /// roof silver, mask and greys (decision 786), `beam` (the beam
    /// sample's, which the game does not draw) and the lamps.
    static func palette(band: UInt32, accent: UInt32, beam: UInt32) -> [UInt32] {
        [CableParts.Paint.white, band, accent, Map3DPalette.mtrRoofSilver, Map3DMTRUrbanLine.meshPalette[5], Map3DTrainStyle.glass,
         Map3DMTRUrbanLine.meshPalette[10], Map3DMTRUrbanLine.meshPalette[11], beam, Map3DPalette.lantern, Map3DTrainStyle.headlamp]
    }

    /// The palette index of the studio's glass material.
    static let glassIndex = 5

    /// The mesh `name` of `encoded`, raised `lift` metres: the studio's
    /// models have z 0 at their guideway's running surface and reach under
    /// it (a straddling car's skirts beside its beam, a suspended car its
    /// whole body). Raised so each stands with its lowest point on the
    /// rail, where the track is ordinary; decision 947 draws a guideway's
    /// running surface `lift` over the rails, so on its own beam the car
    /// rides it. `nil` if it does not decode.
    static func model(_ name: String, in encoded: [String: String], palette: [UInt32], lift: Float) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: palette, glass: glassIndex) else { return nil }
        let vertices = model.vertices.map { v in
            Map3DVertex(Map3DPoint(v.x, v.y, v.z + lift), normal: Map3DPoint(v.nx, v.ny, v.nz), color: v.color, layer: v.layer)
        }
        return Map3DModelPack.Model(name: name, vertices: vertices,
                                    minimum: Map3DPoint(model.minimum.x, model.minimum.y, model.minimum.z + lift),
                                    maximum: Map3DPoint(model.maximum.x, model.maximum.y, model.maximum.z + lift))
    }

    /// A guideway train's set: a cab car at each end, the back one turned
    /// round, middle cars between, each at its own length and laid end to
    /// end; the ends' lamp lenses lit. `key` is the type's code, so every
    /// train of the type is drawn as it.
    static func set(_ key: String, far: Bool, cab: @escaping @Sendable (Bool) -> Map3DModelPack.Model?,
                    middle: @escaping @Sendable (Bool) -> Map3DModelPack.Model?) -> Map3DTrainSet {
        Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, far: far ? nil : key + "Far") {
            // A unit that fails to decode draws as a plain car rather
            // than nothing.
            let head = cab(far) ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: key)
            let car = middle(far) ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: false).model(named: key)
            return Map3DTrainSet.Cars(head: Map3DTrainSet.litLenses(head, front: true), middle: car,
                                      tail: Map3DTrainSet.litLenses(head.turned, front: false), single: nil)
        }
    }
}

/// Decision 930: the straddle monorail train (the type `MONORAIL`), as the
/// local studio modelled it in Blender from photographs of straddle
/// monorails (each car 15.00 m, 3.03 m wide, the 15 m the type's cars
/// are): a white body with a blue band and a thin red line, its skirts
/// reaching down beside the beam, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/guided-monorail-2026-11/revision-1`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``). A
/// generic train: no operator's livery, mark or lettering.
public enum Map3DGuidedMonorail {
    public static let key = "MONORAIL"
    public static let cab = "guided-monorail-cab"
    public static let middle = "guided-monorail-middle"

    /// How far its skirts reach under the beam's top, metres: the model
    /// is raised by it (``Map3DGuidedTrains/model(_:in:palette:lift:)``).
    static let lift: Float = Map3DGuideway.Kind.straddle.runningSurface

    /// The band the cable cars' blue, the line their red, the beam
    /// sample's the concrete's.
    static let meshPalette = Map3DGuidedTrains.palette(band: CableParts.Paint.blue, accent: CableParts.Paint.red, beam: Map3DPalette.concrete)

    /// The cab car (its cab at +x) or the middle car; `far`, the light
    /// version drawn from 500 m out.
    public static func model(cab: Bool, far: Bool = false) -> Map3DModelPack.Model? {
        Map3DGuidedTrains.model((cab ? Self.cab : middle) + (far ? "-far" : ""), in: encoded, palette: meshPalette, lift: lift)
    }

    /// Decision 782: its set, near and far, its showcase row and its
    /// cars' triangles (2,594 and 1,960 near, 1,186 and 888 far) and
    /// length (15.00 m).
    static let registration = Map3DTrainRegistration(
        id: "guidedMonorail",
        sets: [Map3DGuidedTrains.set(key, far: false, cab: { model(cab: true, far: $0) }, middle: { model(cab: false, far: $0) }),
               Map3DGuidedTrains.set(key, far: true, cab: { _ in model(cab: true, far: true) }, middle: { _ in model(cab: false, far: true) })],
        showcase: [Map3DShowcase.Entry(key, "Monorail train", "單軌列車", .other, cars: 4, most: 8, gauge: 1.435)],
        triangles: 880...2_600, length: 14.95...15.05)
}

/// Decision 930: the maglev train (the type `MAGLEV`), as the local studio
/// modelled it in Blender from photographs of low-speed urban maglevs
/// (each car 15.00 m, 3.70 m wide over the arms that wrap its guideway):
/// a white body with a dark navy band that dips at the nose and a thin
/// orange line, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/guided-maglev-2026-11/revision-3`), written
/// here by `tools/train-models/glb_to_swift.py` (``encoded``). A generic
/// train: no operator's livery, mark or lettering.
public enum Map3DGuidedMaglev {
    public static let key = "MAGLEV"
    public static let cab = "guided-maglev-cab"
    public static let middle = "guided-maglev-middle"

    /// How far its arms reach under the guideway's top, metres.
    static let lift: Float = Map3DGuideway.Kind.maglev.runningSurface

    /// The band the cable cars' dark navy, the line the EMU100's
    /// yellow-orange band (``TrainLivery/emu100``), the beam sample's
    /// the concrete's.
    static let meshPalette = Map3DGuidedTrains.palette(band: CableParts.Paint.dark, accent: Map3DEMU100.meshPalette[1],
                                                      beam: Map3DPalette.concrete)

    /// The cab car (its cab at +x) or the middle car; `far`, the light
    /// version drawn from 500 m out.
    public static func model(cab: Bool, far: Bool = false) -> Map3DModelPack.Model? {
        Map3DGuidedTrains.model((cab ? Self.cab : middle) + (far ? "-far" : ""), in: encoded, palette: meshPalette, lift: lift)
    }

    /// Decision 782: its set, near and far, its showcase row and its
    /// cars' triangles (4,014 and 2,316 near, 1,362 and 1,024 far) and
    /// length (15.00 m).
    static let registration = Map3DTrainRegistration(
        id: "guidedMaglev",
        sets: [Map3DGuidedTrains.set(key, far: false, cab: { model(cab: true, far: $0) }, middle: { model(cab: false, far: $0) }),
               Map3DGuidedTrains.set(key, far: true, cab: { _ in model(cab: true, far: true) }, middle: { _ in model(cab: false, far: true) })],
        showcase: [Map3DShowcase.Entry(key, "Maglev train", "磁浮列車", .other, cars: 4, most: 8, gauge: 1.435)],
        triangles: 1_020...4_020, length: 14.95...15.05)
}

/// Decision 930: the suspended light monorail train (the type `SKYRAIL`),
/// as the local studio modelled it in Blender from photographs of
/// suspended monorails (each car 12.00 m, 2.60 m wide, the 12 m the type's
/// cars are): a white body with a green band and a thin navy line, its
/// bogies' housing on its roof where it hangs from its beam, one palette
/// colour a triangle (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/guided-skyrail-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``). A
/// generic train: no operator's livery, mark or lettering.
public enum Map3DGuidedSkyrail {
    public static let key = "SKYRAIL"
    public static let cab = "guided-skyrail-cab"
    public static let middle = "guided-skyrail-middle"

    /// How far its floor hangs under the beam's running surface, metres:
    /// hung from its beam (decision 947) its floor is at the rails' height;
    /// on track another line shares it stands on the rail.
    static let lift: Float = Map3DGuideway.Kind.suspended.runningSurface

    /// The band the cable cars' green, the line their dark navy, the
    /// beam sample's the palette's steel.
    static let meshPalette = Map3DGuidedTrains.palette(band: CableParts.Paint.green, accent: CableParts.Paint.dark, beam: Map3DPalette.steel)

    /// The cab car (its cab at +x) or the middle car; `far`, the light
    /// version drawn from 500 m out.
    public static func model(cab: Bool, far: Bool = false) -> Map3DModelPack.Model? {
        Map3DGuidedTrains.model((cab ? Self.cab : middle) + (far ? "-far" : ""), in: encoded, palette: meshPalette, lift: lift)
    }

    /// Decision 782: its set, near and far, its showcase row and its
    /// cars' triangles (2,826 and 2,260 near, 1,246 and 892 far) and
    /// length (12.00 m).
    static let registration = Map3DTrainRegistration(
        id: "guidedSkyrail",
        sets: [Map3DGuidedTrains.set(key, far: false, cab: { model(cab: true, far: $0) }, middle: { model(cab: false, far: $0) }),
               Map3DGuidedTrains.set(key, far: true, cab: { _ in model(cab: true, far: true) }, middle: { _ in model(cab: false, far: true) })],
        showcase: [Map3DShowcase.Entry(key, "Light monorail", "輕型單軌", .other, cars: 3, most: 6, gauge: 1.435)],
        triangles: 890...2_830, length: 11.95...12.05)
}
