import Foundation

/// Decision 1037: the riding scooters (機車) from the local studio's
/// models (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/scooter-old-2026-11/revision-2`; lessons in
/// `docs/studio/lessons/scooter-old.md`), made for the game in Blender by
/// script, no brand marks, no delivery platform's colours: the 125 cc
/// step-through (its top case), the battery-swap e-scooter and the
/// delivery scooter, each with its rider, the step-through with its
/// pillion, and farther one mesh each for a scooter ridden alone and two
/// up. Written here by `tools/train-models/glb_to_swift.py`
/// (``Map3DScooterMesh``): +x the front, +y the left, +z up, the wheels'
/// contact at the origin; the rider and the pillion in the scooter's own
/// space, so a ridden scooter is one model, one instance, as before.
///
/// The arcades' parked rows keep decision 446's (about 60 triangles a
/// scooter; the studio's parked ones are 120, and a street of shops parks
/// hundreds), so their meshes are not drawn yet.
enum Map3DScooterModels {
    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: paint (alpha 0: the
    /// instance's colour), tyre, black, metal, seat, trim, plate, topCase,
    /// box, headFace, tailFace, helmetWhite, helmetYellow, visor,
    /// riderShirt, pillionShirt, trousers, skin. All the game's own
    /// (decision 446's scooters and riders).
    static let palette: [UInt32] = [
        Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF, Map3DStreetModel.tyre, Map3DScooter.black, Map3DScooter.metal, Map3DStreetModel.seat,
        Map3DScooter.trim, Map3DScooter.plate, Map3DScooter.topCase, Map3DScooter.box, Map3DStreetModel.headlamp, Map3DStreetModel.tailLamp,
        Map3DStreetModel.helmets[1], Map3DStreetModel.helmets[0], Map3DStreetModel.glass, Map3DStreetModel.riderShirt,
        Map3DStreetModel.pillionShirt, Map3DStreetModel.trousers, Map3DStreetModel.skin,
    ]
    /// The head and tail lamps' faces, lit at night.
    static let lamps: Set<Int> = [9, 10]

    /// The meshes `model` is put together from, in the studio's names;
    /// `nil` for a street model that is not a riding scooter.
    static func parts(of model: Map3DStreetModel) -> [String]? {
        switch model {
        case .stepScooter: ["scooter-step", "scooter-rider"]
        case .stepScooterPair: ["scooter-step", "scooter-rider", "scooter-pillion"]
        case .electricScooter: ["scooter-electric", "scooter-rider"]
        case .deliveryScooter: ["scooter-delivery", "scooter-rider"]
        case .scooter: ["scooter-far"]
        case .scooterPair: ["scooter-pair-far"]
        default: nil
        }
    }

    /// `model` as one mesh, named as it, the step-through two up without
    /// its top case (the pillion sits there); `nil` if it is not a riding
    /// scooter or a part does not decode.
    static func model(_ model: Map3DStreetModel) -> Map3DModelPack.Model? {
        guard let parts = parts(of: model) else { return nil }
        var vertices: [Map3DVertex] = []
        for part in parts {
            guard let text = encoded[part], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
                  let mesh = Map3DRedCommuter.decodedMesh([UInt8](data), named: part, palette: palette, lamps: lamps) else { return nil }
            vertices += model == .stepScooterPair ? mesh.vertices.filter { $0.color != Map3DScooter.topCase } : mesh.vertices
        }
        let low = vertices.reduce(Map3DPoint(.infinity, .infinity, .infinity)) { Map3DPoint(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
        let high = vertices.reduce(Map3DPoint(-.infinity, -.infinity, -.infinity)) { Map3DPoint(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
        return Map3DModelPack.Model(name: model.modelName, vertices: vertices, minimum: low, maximum: high)
    }
}
