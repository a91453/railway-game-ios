import Foundation

/// The TEMU1000 (the Taroko): the operating set's cars and the static
/// studies' units. Decision 906: the local studio's models
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tra-temu1000-redo-2026-11/revision-4`,
/// #223; lessons in `docs/studio/lessons/tra-temu1000-redo.md`), written
/// in with `tools/train-models/glb_to_swift.py` (``encoded``) in place of
/// the drawn recipe: a tall blunt round face, a dark window band through
/// the doors to the car ends, the real train's orange band and two roof
/// boxes a car, each car its real length. Model space: +x the front, +y
/// the left, +z up, metres, the rail at z 0, the origin mid-car.
public enum Map3DTEMU1000 {
    public enum Unit: String, CaseIterable, Sendable { case leading, middle, pantograph, trailing }
    /// Each car's length from coupler face to coupler face (eight cars
    /// 166.99 m).
    public static let cabLength: Float = 21.995
    public static let carLength: Float = 20.5
    public static let shell = Map3DPalette.tileWhite
    /// Decision 906: the real train's orange (the studio's sample from a
    /// sunlit photograph), the band's only colour.
    public static let band = Map3DPalette.temu1000Orange
    /// The game's own grey-green the band was until decision 906, kept
    /// for a livery the player may choose later.
    public static let greenBand = Map3DPalette.gymGreen
    /// The windscreen, corner windows and lamp housings (the studio's
    /// `mask`, the Hong Kong cars' near-black).
    public static let glass = Map3DMTRUrbanLine.meshPalette[5]
    public static let passengerGlass = Map3DColor.rgb(0x405560)

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py` (the
    /// brief's §4): white, band, windowBand, glass, mask, roofSilver,
    /// roofCover, skirt, dark, headlamp, taillamp.
    static let meshPalette: [UInt32] = [
        shell, band, Map3DTEMU2000.dark, passengerGlass, glass, Map3DTEMU2000.silver, Map3DPalette.stone,
        Map3DPalette.tankSteel, Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    public static func model(_ unit: Unit) -> Map3DModelPack.Model { model(unit, far: false) }

    /// `far`: the studio's light version drawn from 500 m out (decision
    /// 420). `lamps` (the operating set's cab cars): the head lamps (white)
    /// and tail lamps (red) glow, for decision 449's lights to find; the
    /// static studies draw them unlit. The trailing cab is the leading one
    /// turned round (x and y negated: no sine, the same to the bit on
    /// Linux and on a Mac).
    public static func model(_ unit: Unit, far: Bool, lamps: Bool = false) -> Map3DModelPack.Model {
        let file: String
        switch unit {
        case .leading, .trailing: file = "temu1000-leading"
        case .middle: file = "temu1000-middle"
        case .pantograph: file = "temu1000-pantograph"
        }
        let name = "temu1000-\(unit.rawValue)" + (far ? "-far" : "")
        guard let text = encoded[file + (far ? "-far" : "")], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: 3,
                                                       lamps: lamps ? [9, 10] : [])
        else { preconditionFailure("\(file): its mesh does not decode") }
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

    public static let order: [Unit] = [.trailing, .middle, .pantograph, .middle,
                                       .middle, .pantograph, .middle, .leading]

    /// Each car's length, ``order``'s.
    static func length(_ unit: Unit) -> Float { unit == .leading || unit == .trailing ? cabLength : carLength }

    /// The eight cars coupled, centred on the origin.
    public static func formation() -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        var x = -order.reduce(0) { $0 + length($1) } / 2
        for unit in order {
            let length = length(unit)
            builder.add(model(unit), at: Map3DPoint(x + length / 2, 0, 0))
            x += length
        }
        return .flat(named: "temu1000-formation", from: builder.mesh)
    }
}

extension Map3DPalette {
    /// Decision 906: the TEMU1000's orange band.
    public static let temu1000Orange = Map3DColor.rgb(0xEE8A22)
}
