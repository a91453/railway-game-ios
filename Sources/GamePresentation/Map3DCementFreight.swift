import Foundation
import GameCore

/// Decision 1033: Taiwan Railway's cement trains and their silo yard, the
/// local studio's models (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/freight-cement-2026-11/revision-2`, #630;
/// lessons in `docs/studio/lessons/freight-cement.md`). They are a look of
/// building materials (``CargoKind/materials``), not a cargo of their own:
/// every other station's materials yard is a cement silo yard in place of
/// decision 837's stone yard (``Map3DFreightYard/isCement(_:)``), and a
/// train whose materials were loaded mostly at silo yards runs cement
/// wagons (``Map3DFreightLoad/cement``) in place of the stone hoppers.
///
/// The wagon is the silver arched covered hopper of the P35CH kind, 11.6 m
/// over its couplers, the last one with the red tail lamp; no logos,
/// lettering or numbers. Written here by `tools/train-models/glb_to_swift.py`
/// (``encoded``, +x the front, +y left, +z up, the rail at 0).
enum Map3DCementWagon {
    /// The colours of the mesh's palette indices, in `--materials` order:
    /// body, trimSteel, frame, bogie, metal, handwheel, taillamp.
    static let meshPalette: [UInt32] = [
        Map3DPalette.tankSteel, Map3DPalette.steel, Map3DContainerWagon.frame, Map3DContainerWagon.bogie,
        Map3DContainerWagon.metal, Map3DPalette.tankWhite, Map3DPalette.lantern,
    ]

    /// A wagon (the last one with its tail lamp lit), or, if its mesh does
    /// not decode, the stone hopper in its place.
    static func model(tail: Bool, far: Bool) -> Map3DModelPack.Model {
        let name = (tail ? "freight-cement-car-tail" : "freight-cement-car") + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let mesh = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
        else { return Map3DFreightWagons.model(tail ? .stoneTail : .stone, far: far) }
        return Map3DTrainSet.litLenses(mesh, front: false)
    }
}

/// Decision 1033: the studio's cement silo yard, 40 m along the line and
/// 18 m deep, its own paving: two pairs of silos, the preheater tower, the
/// conveyor bridge up to them, the blue loading canopy by the track and a
/// cement lorry. Written here by `tools/landmarks/glb_to_swift.py`
/// (``encoded``, raised 0.15 m so its paving's foot is at 0): +X its front
/// (away from the track), +Y along the line, z up.
enum Map3DCementSilo {
    /// Its materials' colours, in `--materials` order: concrete, terrazzo,
    /// tankSteel, steel, roof, canopy, tileWhite, dark.
    static let palette: [UInt32] = [
        Map3DPalette.concrete, Map3DPalette.terrazzo, Map3DPalette.tankSteel, Map3DPalette.steel,
        Map3DPalette.roof, Map3DPalette.canopy, Map3DPalette.tileWhite, Map3DPalette.dark,
    ]

    /// The model in full close by, or its far model; empty if it does not
    /// decode (`Map3DCementFreightTests` keeps that from happening).
    static func model(full: Bool) -> LandmarkMesh {
        let name = full ? "freight-cement-silo" : "freight-cement-silo-far"
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let mesh = LandmarkMesh.decodedLandmark(Array(data), full: full, palette: palette, glass: [])
        else { return LandmarkMesh(full: full) }
        return mesh
    }

    /// The yard as ``Map3DFreightYard/mesh(_:at:)`` builds one: +x its
    /// front, +y up, +z along the line, its paving's foot 0.15 m under the
    /// ground, as the stone yard's.
    /// The model's (x, y, z) is the yard's (x, z, −y), a turn, so no face
    /// is turned inside out.
    static func yard(full: Bool) -> Map3DMesh {
        model(full: full).placed(origin: Map3DPoint(0, 0, 0), ground: -Map3DFreightYard.pad / 2, rotation: 0)
    }
}

extension Map3DTrainSet {
    /// Decision 1033: a freight train carrying cement: the R200 and the
    /// cement wagons, the last one with the tail lamp.
    static func freightCement(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DFreightWagons.cementKey
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, far: far ? nil : key + "Far",
                             headOf: far ? "R200CKFar" : "R200CK") {
            Cars(head: litLenses(Map3DR200.model(far: far), front: true), middle: Map3DCementWagon.model(tail: false, far: far),
                 tail: Map3DCementWagon.model(tail: true, far: far), single: nil)
        }
    }
}
