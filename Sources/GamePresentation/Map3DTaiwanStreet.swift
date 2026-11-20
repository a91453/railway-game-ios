import Foundation

/// Decision 903: Taiwan's street light, utility pole and traffic signal
/// (``Map3DProp/lamp``, ``Map3DProp/pole``, ``Map3DProp/signalGo``,
/// ``Map3DProp/signalStop``, ``Map3DProp/signalAmber``), modelled by the
/// local studio from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-street-props-2026-11/revision-1`, #214;
/// lessons in `docs/studio/lessons/tw-street-props.md`) and written here
/// by `tools/train-models/glb_to_swift.py` (``encoded``):
///
/// - the street light: a tapered galvanised pole 8.6 m tall on a flange,
///   bending in a wide arc over the road to a flat head lit underneath;
/// - the utility pole: a tapered concrete pole 10.2 m tall, two
///   galvanised crossarms with white insulators and fuse cut-outs, and a
///   grey-blue transformer hung on its side away from the road;
/// - the traffic signal: a galvanised post striped yellow and black at its
///   foot, an arm over the lanes and a level dark head of three lights
///   under their hoods, red nearest the road's middle, one model a light
///   it shows.
///
/// Built in the pack's space as the shapes before them were (the road
/// toward +y, a signal's lights facing −x), so nothing is turned. No word,
/// number or mark is drawn.
enum Map3DTaiwanStreet {
    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names steel, tankSteel, concrete, insulator, transformer, dark,
    /// stripeYellow, lamp_lit, red_lit, red_unlit, amber_lit, amber_unlit,
    /// green_lit, green_unlit (the brief's §4, each the game's own).
    static let meshPalette: [UInt32] = [
        Map3DPalette.steel, Map3DPalette.tankSteel, Map3DPalette.concrete, Map3DPalette.tileWhite,
        Map3DPalette.cityRoofs[1].color, Map3DProp.signalHousing, Map3DScene.Builder.barrierYellow, Map3DProp.lampLight,
        Map3DProp.signalLights[0].lit, Map3DProp.signalLights[0].unlit,
        Map3DProp.signalLights[1].lit, Map3DProp.signalLights[1].unlit,
        Map3DProp.signalLights[2].lit, Map3DProp.signalLights[2].unlit,
    ]

    /// The palette indices that glow: the street light's head and a
    /// signal's lit light.
    static let lit: Set<Int> = [7, 8, 10, 12]

    /// The studio's GLB for `prop`, `nil` for the props it did not make.
    static func glb(for prop: Map3DProp) -> String? {
        switch prop {
        case .lamp: "tw-lamp"
        case .pole: "tw-pole"
        case .signalStop: "tw-signal-red"
        case .signalAmber: "tw-signal-amber"
        case .signalGo: "tw-signal-green"
        case .tree, .busStop, .vending: nil
        }
    }

    /// `prop`'s model named as the pack names it, `nil` when the studio
    /// did not make it or its mesh does not decode.
    static func model(_ prop: Map3DProp) -> Map3DModelPack.Model? {
        guard let glb = glb(for: prop), let text = encoded[glb],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters)
        else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: prop.modelName, palette: meshPalette, lamps: lit)
    }
}
