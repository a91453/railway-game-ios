import Foundation

/// Decision 893: the two-car train of Fukuoka's Kaizuka line (the
/// Nishitetsu line from Kaizuka to Nishitetsu-Shingu, its steel cars of
/// the 1960s), as the local studio modelled it in Blender from
/// photographs and the published dimensions (19.50 m a car, 2.67 m wide,
/// the 1,067 mm gauge), one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-kaizuka-line-2026-11/revision-3`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// A yellow body with a red band at the waist, broken at the doors and
/// round the flat front, three windows a front, the lamps in an oval
/// silver frame each side on the band, pale roof coolers, a diamond
/// pantograph on the motor car. No company mark, lettering or number is
/// drawn.
///
/// The band and the tail lamps are the same red (``Map3DPalette/lantern``),
/// two of the studio's materials: the lamps are lit by their material
/// (``lampIndices``), and the game takes this train's lit faces alone for
/// its lamps (``Map3DTrainLights/marksOwnLamps(_:)``), so the band never
/// lights at night.
public enum Map3DFukuokaKaizukaLine {
    /// The cars the game draws: the motor car with the pantograph and the
    /// trailer, each a cab at +x.
    public enum Unit: String, CaseIterable, Sendable {
        case motor = "fukuoka-kaizuka-line-motor"
        case trailer = "fukuoka-kaizuka-line-trailer"

        public var pitch: Float { 19.5 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "fukuokaKaizukaLine"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names yellow, red, roofSilver, mask, glass, steel, cooler, dark,
    /// headlamp, taillamp. The player's yellow, the lamps' red for the
    /// band, the urban line train's roof silver, mask and dark grey
    /// (decision 786), the tanks' pale steel for the coolers; no new colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.player, Map3DPalette.lantern, Map3DPalette.mtrRoofSilver, Map3DMTRUrbanLine.meshPalette[5],
        Map3DTrainStyle.glass, Map3DPalette.steel, Map3DPalette.tankSteel, Map3DMTRUrbanLine.meshPalette[11],
        Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in.
    static let glassIndex = 4
    /// The palette index of the red band (``bandIndex``) and of the lamp
    /// lenses, headlamp and taillamp (``lampIndices``), lit face by face.
    static let bandIndex = 1
    static let lampIndices: Set<Int> = [8, 9]

    /// `unit`'s car, its cab at +x, its lamp lenses lit; `far`, the light
    /// version drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex, lamps: lampIndices)
    }
}

extension Map3DFukuokaKaizukaLine {
    /// Decision 782: its set, near and far, its showcase row (two cars)
    /// and its cars' triangles (6,946 to 7,106 near and 2,608 to 2,780
    /// far) and lengths (19.5 m).
    static let registration = Map3DTrainRegistration(
        id: "fukuokaKaizukaLine",
        sets: [Map3DTrainSet.fukuokaKaizukaLine(), .fukuokaKaizukaLine(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Fukuoka Kaizuka line train", "福岡貝塚線列車", .japan, cars: 2, fixed: true, gauge: 1.067),
        ],
        triangles: 2_500...7_200, length: 19.4...19.6)
}

extension Map3DTrainSet {
    /// Decision 893: the local studio's Kaizuka line cars
    /// (``Map3DFukuokaKaizukaLine``), laid as the real two cars run, the
    /// motor car and the trailer turned round, their cabs outward. Their
    /// lamps lit by material, not by colour (the band is the tail lamps'
    /// red). Before the pack has its models, the generic metro car
    /// (``fallback``).
    static func fukuokaKaizukaLine(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DFukuokaKaizukaLine.key
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, fixedCars: 2,
                             far: far ? nil : key + "Far", fallback: "metroGeneric") {
            func model(_ unit: Map3DFukuokaKaizukaLine.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain metro car
                // of its length rather than nothing.
                Map3DFukuokaKaizukaLine.model(unit, far: far)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: unit.rawValue)
            }
            return Cars(head: model(.motor), middle: nil, tail: model(.trailer).turned, single: nil)
        }
    }
}
