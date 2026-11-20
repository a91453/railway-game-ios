import Foundation

/// Decision 893: the six-car train of Fukuoka's subway Airport line (the
/// newest trains, from 2024, which the Hakozaki line runs too), as the
/// local studio modelled it in Blender from photographs and the published
/// dimensions (the cab car 20.435 m, the middle cars 20.000 m, 2.80 m
/// wide, the 1,067 mm gauge), one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-airport-line-2026-11/revision-3`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A white body with a pale sky-blue band through the windows and the
/// doors' upper halves, a thin blue line along the roof's edge, a flat
/// front with a blue cap, a black mask round a narrow and a wide window
/// and a blue lower half curved at its foot, two pantographs on the
/// second and fifth cars. No company mark, lettering or number is drawn.
public enum Map3DFukuokaAirportLine {
    /// The cars the game draws: the cab car, the middle car with two
    /// pantographs and the middle car without.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "fukuoka-airport-line-cab"
        case pantograph = "fukuoka-airport-line-pantograph"
        case middle = "fukuoka-airport-line-middle"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 20.435 : 20.0 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "fukuokaAirportLine"

    /// How many cars its trains have.
    public static let cars = 6

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, skyBlue, blue, roofSilver, skirt, mask, glass, steel,
    /// dark, headlamp, taillamp. The white grey concrete's white, the band
    /// ``Map3DPalette/skyBlue`` (decision 893, the one new name; the
    /// colour was the station skylights' already), the water tanks' blue,
    /// the urban line train's roof silver, mask and dark grey (decision
    /// 786), steel and the lamps. The skirt is the roof's silver, kept a
    /// palette index of its own as the studio drew it.
    static let meshPalette: [UInt32] = [
        Map3DPalette.cityConcreteWalls[4], Map3DPalette.skyBlue, Map3DPalette.tankBlue, Map3DPalette.mtrRoofSilver,
        Map3DPalette.mtrRoofSilver, Map3DMTRUrbanLine.meshPalette[5], Map3DTrainStyle.glass, Map3DPalette.steel,
        Map3DMTRUrbanLine.meshPalette[11], Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in. The black mask and window frames stay dark.
    static let glassIndex = 6

    /// `unit`'s car, its cab (if it has one) at +x; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

/// Decision 893: the Airport line train's band, a pale sky blue (#BFE3E5,
/// the colour the station skylights had already,
/// ``Map3DStationExteriorBatch2``): the photographs' band is a little
/// deeper; the palette's water blue (#86D3E3) was too green and too
/// strong beside the white at the game's size. Kept with the train
/// (decision 782).
extension Map3DPalette {
    public static let skyBlue = Map3DColor.rgb(0xBFE3E5)
}

extension Map3DFukuokaAirportLine {
    /// Decision 782: its set, near and far, its showcase row (six cars)
    /// and its cars' triangles (5,582 to 7,172 near and 2,400 to 3,154
    /// far) and lengths (the cab car 20.435 m).
    static let registration = Map3DTrainRegistration(
        id: "fukuokaAirportLine",
        sets: [Map3DTrainSet.fukuokaAirportLine(), .fukuokaAirportLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Fukuoka subway Airport line train", "福岡市地鐵空港線列車", .japan, cars: cars, fixed: true,
                                gauge: 1.067),
        ],
        triangles: 2_300...7_300, length: 19.9...20.5)
}

extension Map3DTrainSet {
    /// Decision 893: the local studio's Airport line cars
    /// (``Map3DFukuokaAirportLine``), each its own length, laid as the
    /// real six cars run: the cab car, the pantograph car, a middle car,
    /// then the front half's mirror image with each car turned round
    /// (``Map3DTrainSet/cycle``), the second cab car turned round at the
    /// back. The ends' lamp lenses lit. Before the pack has its models, the
    /// generic metro car (``fallback``).
    static func fukuokaAirportLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DFukuokaAirportLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, cycle: [.pantograph, .middle],
                             ownLengths: true, far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DFukuokaAirportLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DFukuokaAirportLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.middle), tail: litLenses(model(.cab).turned, front: false),
                        single: nil, pantograph: model(.pantograph),
                        middleBack: model(.middle).turned, pantographBack: model(.pantograph).turned)
        }
    }
}
