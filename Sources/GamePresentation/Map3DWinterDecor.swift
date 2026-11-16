import Foundation

/// The winter event's decorations (`docs/research/WINTER_EVENT_2026-11-15.md`
/// §2.2, §2.3): two Christmas trees, a string of lights to hang under a
/// station's eaves, and the Christmas livery's colours. Made by the local
/// studio in Blender (`winter-decor`, the assets repository's
/// `game-art-previews/docs/art/winter-decor-2026-11/`), one palette colour a
/// triangle, and passed by its review against photographs.
///
/// This only holds the models and colours; where they stand, when they
/// show and which trains wear the livery are the event's own work
/// (WINTER-LIGHTS, WINTER-LIVERY), so nothing here is in the model pack
/// yet. The bulbs (``Material/isBulb``) are drawn lit
/// (``Map3DVertex/glowing``), so ``Map3DGlow`` gives each a glow at night.
public enum Map3DWinterDecor: String, CaseIterable, Sendable {
    /// A 6 m fir in four tiers on a red planter, a gold star, baubles and
    /// a spiral of warm bulbs: before a station's front.
    case treeMedium = "xmas-tree-medium"
    case treeMediumFar = "xmas-tree-medium-far"
    /// An 18 m slender cone, eight lit bands to a big star: the plazas
    /// (Banqiao's, Tsim Sha Tsui's waterfront, the Santa Claus village).
    case treeLarge = "xmas-tree-large"
    case treeLargeFar = "xmas-tree-large-far"
    /// A 4 m length of wire, its ends at x ±2 m and z 0 (where it hangs),
    /// sagging 0.25 m, eight bulbs warm white, red, green and gold.
    case lightString = "light-string-4m"

    /// The model's name in a pack.
    public var modelName: String { "winter-" + rawValue }

    /// The studio's materials, in the meshes' palette order
    /// (`tools/train-models/glb_to_swift.py --materials`).
    public enum Material: Int, CaseIterable, Sendable {
        case firGreen, firShade, trunk, starGold, ornamentRed, ornamentGold, ornamentWhite, wire
        case bulbWarm, bulbRed, bulbGreen, bulbGold

        /// Its colour: the game's own nearest colour to the studio's
        /// (CIELAB ΔE in brackets), so the decorations bring no new
        /// colour into the palette.
        public var colour: UInt32 {
            switch self {
            case .firGreen: Map3DContainerWagon.green // #2F6B45 (7.3)
            case .firShade: Map3DAlishan.green // #1F4D33 (9.2)
            case .trunk: Map3DPalette.trunk // the same
            case .starGold: Map3DAlishan.beacon // the same
            case .ornamentRed: Map3DPalette.mtrRed // #C8282E (3.4)
            case .ornamentGold: Map3DCityBus.destinationBoard // #E0A93A (7.3)
            case .ornamentWhite: Map3DScene.Builder.Airfield.paint // #F2F1EC (0.9)
            case .wire: Map3DProp.signalHousing // #2B2F33 (2.1)
            case .bulbWarm: Map3DPalette.tunnelLamp // #FFD98A (11.1)
            case .bulbRed: Map3DStreetModel.tailLamp // #FF5A4E (10.6)
            case .bulbGreen: Map3DStudyColor.lampGreen // #5EE08A (17.0)
            case .bulbGold: Map3DPalette.player // the same
            }
        }

        /// Whether it is lit at night.
        public var isBulb: Bool { self.rawValue >= Material.bulbWarm.rawValue }
    }

    /// The palette the meshes are decoded with.
    static let palette: [UInt32] = Material.allCases.map(\.colour)

    /// The model, its bulbs lit; `nil` if its mesh does not decode.
    public var model: Map3DModelPack.Model? {
        guard let text = Self.encoded[rawValue],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let plain = Map3DRedCommuter.decodedMesh([UInt8](data), named: modelName, palette: Self.palette)
        else { return nil }
        let lit = Set(Material.allCases.filter(\.isBulb).map { Self.palette[$0.rawValue] })
        let vertices = plain.vertices.map { vertex -> Map3DVertex in
            guard lit.contains(vertex.color) else { return vertex }
            var glowing = vertex
            glowing.layer = Map3DVertex.glowing
            return glowing
        }
        return Map3DModelPack.Model(name: modelName, vertices: vertices, minimum: plain.minimum, maximum: plain.maximum)
    }
}
