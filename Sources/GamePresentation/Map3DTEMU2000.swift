import Foundation

/// TEMU2000: the operating Puyuma's cars since decision 484 and the static
/// studies' units; decision 905: the local studio's models in place of
/// #1456's recipe. Model space: +x the front, +y the left, +z up, metres,
/// the rail at z 0.
public enum Map3DTEMU2000 {
    public enum Unit: String, CaseIterable, Sendable {
        case leading, tema, tep, temb, trailing
    }
    public static let bodyWidth: Float = 2.900
    public static let leadingOverallLength: Float = 22.095
    public static let intermediateOverallLength: Float = 20.700
    public static let formationLength: Float = 168.390
    public static let white = Map3DPalette.tileWhite
    /// The TRA production palette: the forehead and nose red, the double
    /// waist band's deeper red and the dark of the frames and bogies.
    public static let red = Map3DColor.rgb(0xE64053)
    public static let band = Map3DColor.rgb(0xC92035)
    public static let dark = Map3DColor.rgb(0x273039)
    public static let glass = Map3DColor.rgb(0x405560)
    public static let silver = Map3DColor.rgb(0xAAB7BF)

    public static func model(_ unit: Unit) -> Map3DModelPack.Model { model(unit, far: false) }

    /// Decision 905: the local studio's units
    /// (`a91453/railway-assets-private-2`
    /// `game-art-previews/docs/art/tra-temu2000-fix-2026-11/revision-3`,
    /// #225; lessons in `docs/studio/lessons/tra-temu2000-fix.md`),
    /// written in with `tools/train-models/glb_to_swift.py`
    /// (``encoded``): `temu2000-leading`, `-tem` (both TEMA and TEMB) and
    /// `-tep`, each with its `-far` version drawn from 500 m out. The
    /// trailing cab is the leading one turned round (its x and y negated:
    /// no sine, the same to the bit on Linux and on a Mac).
    ///
    /// `lamps` (decision 484, the operating set's cab cars): the cab's
    /// head lamps (white) and tail lamps (red) glow, for decision 449's
    /// lights to find; the static studies draw them unlit.
    public static func model(_ unit: Unit, far: Bool, lamps: Bool = false) -> Map3DModelPack.Model {
        let file: String
        switch unit {
        case .leading, .trailing: file = "temu2000-leading"
        case .tema, .temb: file = "temu2000-tem"
        case .tep: file = "temu2000-tep"
        }
        let name = "temu2000-\(unit.rawValue)" + (far ? "-far" : "")
        guard let text = encoded[file + (far ? "-far" : "")], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let decoded = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: 4,
                                                       lamps: lamps ? [9, 10] : [])
        else { preconditionFailure("\(file): its mesh does not decode") }
        guard unit == .leading || unit == .trailing else { return decoded }
        let model = windscreen(of: decoded)
        guard unit == .trailing else { return model }
        let turned = model.vertices.map { vertex -> Map3DVertex in
            var vertex = vertex
            (vertex.x, vertex.y, vertex.nx, vertex.ny) = (-vertex.x, -vertex.y, -vertex.nx, -vertex.ny)
            return vertex
        }
        return Map3DModelPack.Model(name: name, vertices: turned,
                                    minimum: Map3DPoint(-model.maximum.x, -model.maximum.y, model.minimum.z),
                                    maximum: Map3DPoint(-model.minimum.x, -model.minimum.y, model.maximum.z))
    }

    /// Decision 905: the studio drew the cab's windscreen in the black
    /// mask's material, not the glass's (the real car's windscreen sits in
    /// its black face). Its faces of the mask facing forward, within
    /// ``windscreenReach`` of the front and over ``windscreenFloor``, are
    /// the cab's window glass (``Map3DVertex/trainGlass``), so its glass
    /// shines and the Christmas wreath (decision 806) finds the windscreen
    /// and stays under it; the mask's lower nose and its band along the
    /// side windows stay as they are.
    static func windscreen(of model: Map3DModelPack.Model) -> Map3DModelPack.Model {
        var vertices = model.vertices
        let front = model.maximum.x
        for first in stride(from: 0, to: vertices.count - 2, by: 3) {
            let face = vertices[first ..< first + 3]
            guard face.allSatisfy({ $0.color == dark && $0.layer == Map3DVertex.plain }), vertices[first].nx > 0.3,
                  vertices[first].nz >= Map3DTrainMaterial.lowestNormal,
                  face.allSatisfy({ $0.x > front - windscreenReach && $0.z > windscreenFloor }) else { continue }
            for index in first ..< first + 3 { vertices[index].layer = Map3DVertex.trainGlass }
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// Metres back from the cab's front, and up from the rail, that its
    /// windscreen lies within: the black of the mask over 2.2 m (the
    /// headlamps' and the nose's black are lower), in the front 5 m.
    static let windscreenReach: Float = 5
    static let windscreenFloor: Float = 2.2

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py` (the
    /// brief's §4, each the game's own): white, red, band, mask, glass,
    /// roofSilver, roofCover, dark, arcGrey, headlamp, taillamp.
    static let meshPalette: [UInt32] = [
        white, red, band, dark, glass, silver, Map3DPalette.stone, Map3DPalette.dark, Map3DPalette.arcade,
        Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// Symmetric official TED–TEMA–TEP–TEMB–TEMB–TEP–TEMA–TED order.
    /// The negative-X TED is reversed in its own geometry, so both cabs face out.
    public static let order: [Unit] = [
        .trailing, .tema, .tep, .temb, .temb, .tep, .tema, .leading
    ]
    public static let centres: [Float] = [
        -73.1475, -51.75, -31.05, -10.35, 10.35, 31.05, 51.75, 73.1475
    ]
    /// Each TEP's pantograph points outward. Decision 905: the studio's
    /// TEP has it toward its +x, so the first one (toward car 1) is the
    /// one turned round.
    public static let rotations: [Float] = [
        0, 0, .pi, 0, 0, 0, 0, 0
    ]

    public static func formation() -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        for (index, unit) in order.enumerated() {
            builder.add(model(unit), at: Map3DPoint(centres[index], 0, 0),
                        angle: rotations[index])
        }
        return .flat(named: "temu2000-formation", from: builder.mesh)
    }
}
