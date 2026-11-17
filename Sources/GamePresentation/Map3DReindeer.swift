import Foundation

/// Decision 840: the local studio's reindeer (REINDEER, §29.17): the team
/// that pulls Santa's sleigh across the sky on Christmas Eve (decision
/// 831's stand-in replaced), and the semi-domesticated reindeer of
/// Rovaniemi's farms, standing, grazing and pulling a visitor's wooden
/// sled. Modelled in Blender from photographs (Commons; Finnish forest
/// and tundra reindeer in their winter coat), one palette colour a
/// triangle (`a91453/railway-assets-private`,
/// `game-art-previews/docs/art/reindeer-2026-11/revision-4`), and written
/// here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// In winter the bulls have shed their antlers; the cows and the
/// castrated draught reindeer keep theirs, so every reindeer drawn has
/// them. No name and no character is drawn.
public enum Map3DReindeer {
    /// The models: the sleigh team, and the reindeer on the ground.
    public enum Unit: String, CaseIterable, Sendable {
        case sleigh = "santa-sleigh-single"
        case standing = "reindeer-standing"
        case grazing = "reindeer-grazing"
        case sledRide = "reindeer-sled-ride"
    }

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names fur, mane, legs, antler, dark, red, gold, white, skin, wood,
    /// coat, noseLamp, lanternGlass. All the game's own colours: the
    /// winter coat's grey brown (``Map3DPalette/arcade``), the pale mane
    /// (``Map3DPalette/terrazzo``), the darker legs (``Map3DPalette/trunk``),
    /// the bone-grey antlers (``Map3DPalette/concrete``).
    static let meshPalette: [UInt32] = [
        Map3DPalette.arcade, Map3DPalette.terrazzo, Map3DPalette.trunk, Map3DPalette.concrete,
        Map3DPalette.dark, Map3DPalette.mtrRed, Map3DPalette.platformEdge, Map3DPalette.sidewalk,
        Map3DPalette.plaza, Map3DPalette.timber, Map3DPalette.canopy, Map3DPalette.lantern, Map3DPalette.tunnelLamp,
    ]

    /// The lamps' lenses, drawn lit: the leading reindeer's red nose and
    /// the sleigh's lantern (decision 831's lamps, their glow added at
    /// night by ``SantaFlight``).
    static let lenses: Set<UInt32> = [Map3DPalette.lantern, Map3DPalette.tunnelLamp]

    /// `unit`'s model, facing +x, its lamps' lenses lit; `far`, the light
    /// version. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette) else { return nil }
        guard unit == .sleigh else { return model }
        let lit = model.vertices.map { vertex -> Map3DVertex in
            var vertex = vertex
            if lenses.contains(vertex.color) { vertex.layer = Map3DVertex.glowing }
            return vertex
        }
        return Map3DModelPack.Model(name: name, vertices: lit, minimum: model.minimum, maximum: model.maximum)
    }
}
