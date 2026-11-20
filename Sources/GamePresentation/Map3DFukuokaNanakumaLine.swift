import Foundation

/// Decision 893: the four-car train of Fukuoka's subway Nanakuma line (its
/// small linear-motor cars), as the local studio modelled it in Blender
/// from photographs and the operator's dimensions (the cab car 16.75 m,
/// the middle car 16.50 m, 2.49 m wide, 3.145 m high, the 1,435 mm
/// gauge), one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-nanakuma-line-2026-11/revision-4`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A white body with a green window band and the doors' upper halves
/// green, a lime line along the band's top and a pale blue band at the
/// body's foot; a raked, rounded front with a black mask in a lime U frame
/// and a pale blue band across it. No company mark, lettering or number
/// is drawn.
public enum Map3DFukuokaNanakumaLine {
    /// The cars the game draws: the cab car (its lowered pantograph) and
    /// the middle car.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "fukuoka-nanakuma-line-cab"
        case middle = "fukuoka-nanakuma-line-middle"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 16.75 : 16.5 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "fukuokaNanakumaLine"

    /// How many cars its trains have.
    public static let cars = 4

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, green, lime, paleBlue, roofSilver, mask, glass, steel,
    /// dark, headlamp, taillamp. The white grey concrete's white, the gym's
    /// green (the cable cars' too), ``Map3DPalette/lime`` (decision 893's
    /// one new colour), the Airport line's pale sky blue
    /// (``Map3DPalette/skyBlue``, the same colour), the urban line train's
    /// roof silver, mask and dark grey (decision 786), steel and the lamps.
    static let meshPalette: [UInt32] = [
        Map3DPalette.cityConcreteWalls[4], Map3DPalette.gymGreen, Map3DPalette.lime, Map3DPalette.skyBlue,
        Map3DPalette.mtrRoofSilver, Map3DMTRUrbanLine.meshPalette[5], Map3DTrainStyle.glass, Map3DPalette.steel,
        Map3DMTRUrbanLine.meshPalette[11], Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in.
    static let glassIndex = 6

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

/// Decision 893: the Nanakuma line train's lime green (#A8D430, sampled
/// from the photographs), its front's U frame and the line along its
/// window band. The palette's crown green (#8DC27A) read as the green band
/// itself at the game's size. Kept with the train (decision 782).
extension Map3DPalette {
    public static let lime = Map3DColor.rgb(0xA8D430)
}

extension Map3DFukuokaNanakumaLine {
    /// Decision 782: its set, near and far, its showcase row (four cars)
    /// and its cars' triangles (3,158 to 7,672 near and 1,478 to 3,392
    /// far) and lengths (the cab car 16.75 m).
    static let registration = Map3DTrainRegistration(
        id: "fukuokaNanakumaLine",
        sets: [Map3DTrainSet.fukuokaNanakumaLine(), .fukuokaNanakumaLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Fukuoka subway Nanakuma line train", "福岡市地鐵七隈線列車", .japan, cars: cars, fixed: true,
                                gauge: 1.435),
        ],
        triangles: 1_400...7_700, length: 16.4...16.8)
}

extension Map3DTrainSet {
    /// Decision 893: the local studio's Nanakuma line cars
    /// (``Map3DFukuokaNanakumaLine``), each its own length, laid as the
    /// real four cars run: the cab car, two middle cars (the back one
    /// turned round), the second cab car turned round at the back. The
    /// ends' lamp lenses lit. Before the pack has its models, the generic
    /// metro car (``fallback``).
    static func fukuokaNanakumaLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DFukuokaNanakumaLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.middle],
                             ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DFukuokaNanakumaLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DFukuokaNanakumaLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.middle), tail: litLenses(model(.cab).turned, front: false),
                        single: nil, middleBack: model(.middle).turned)
        }
    }
}
