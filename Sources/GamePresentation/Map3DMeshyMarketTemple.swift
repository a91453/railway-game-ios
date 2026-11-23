import Foundation

/// Decision 935: the night market's string of bulbs, striped canopy and
/// snack cart, and the Tiangong burner before a temple.
///
/// Their shapes follow the owner's Meshy models (`meshy-batch-2026-10`'s
/// `nm-bulb-string`, `nm-canopy`, `nm-stall-cart` and `tiangong-burner`,
/// text-to-3D, so the data-source page says they are generated), rebuilt
/// for the game by the local studio and passed by its review
/// (`a91453/railway-assets-private-2` `game-art-previews/docs/art/`
/// `meshy-night-market-2026-11/revision-1`, #275, and
/// `meshy-temple-front-2026-11/revision-1`, #262; lessons in
/// `docs/studio/lessons/meshy-night-market.md` and `meshy-temple-front.md`).
/// Written here by `tools/train-models/glb_to_swift.py` (``encoded``): the
/// market pieces' long side along +x and their fronts, where people stand,
/// at +y; the burner's front, away from the temple, at +x; each on its
/// foot at z 0. Only the bulbs (``Material/warmLit``) are lit at night.
///
/// Not in the model pack: they are laid into the night markets' and
/// temples' own meshes (``Map3DScene/Builder/placedKitLayouts``,
/// ``Map3DScene/Builder/commerceModels``, ``Map3DScene/Builder/templeModels``),
/// drawn close up only, as the kits' stalls and burners beside them are.
public enum Map3DMeshyMarketTemple: String, CaseIterable, Sendable {
    /// Two 2.6 m posts 4 m apart, a sagging wire and twelve warm bulbs.
    case bulbString = "nm-bulb-string"
    /// A 3 m by 2 m red and white striped canopy on four poles, a
    /// valance along its front.
    case canopy = "nm-canopy"
    /// A 1.5 m stainless snack cart, a glass case on top, four wheels and
    /// a gas cylinder under it.
    case stallCart = "nm-stall-cart"
    /// A 1.6 m Tiangong burner: a red pedestal, a round gold burner with
    /// its lid, knob and two upright handles.
    case tiangongBurner = "tiangong-burner"

    /// The model's name.
    public var modelName: String { "meshy-" + rawValue }

    /// The studio's materials, in the meshes' palette order
    /// (`glb_to_swift.py --materials`), each one of the game's own colours
    /// (the briefs' §5).
    public enum Material: Int, CaseIterable, Sendable {
        case pole, foot, warmLit, stripeRed, stripeWhite, steelTop, glazing, cylinder, pedestal, bronze, shade

        public var colour: UInt32 {
            switch self {
            case .pole: Map3DPalette.steel
            case .foot: Map3DPalette.dark
            case .warmLit: Map3DPalette.tunnelLamp
            case .stripeRed: Map3DPalette.lantern
            case .stripeWhite: Map3DPalette.awningCream
            case .steelTop: Map3DPalette.mtrSilver
            case .glazing: Map3DPalette.glazing
            case .cylinder: Map3DPalette.tankWhite
            case .pedestal: Map3DPalette.templeWall
            case .bronze: Map3DPalette.gold
            case .shade: Map3DPalette.arcade
            }
        }
    }

    /// The palette the meshes are decoded with.
    static let palette: [UInt32] = Material.allCases.map(\.colour)

    /// The model, its bulbs lit (``Map3DVertex/glowing``); `nil` if its
    /// mesh does not decode.
    public var model: Map3DModelPack.Model? {
        guard let text = Self.encoded[rawValue],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let plain = Map3DRedCommuter.decodedMesh([UInt8](data), named: modelName, palette: Self.palette)
        else { return nil }
        // The bulbs' colour is no other material's, so it alone is lit.
        let lit = Material.warmLit.colour
        let vertices = plain.vertices.map { vertex -> Map3DVertex in
            guard vertex.color == lit else { return vertex }
            var glowing = vertex
            glowing.layer = Map3DVertex.glowing
            return glowing
        }
        return Map3DModelPack.Model(name: modelName, vertices: vertices, minimum: plain.minimum, maximum: plain.maximum)
    }

    /// Decision 935: where the market pieces stand in the night market
    /// alley (``Map3DCommercialKit/Example/nightMarketAlley``, in
    /// ``StationKitBuilder``'s frame: x across the alley, its rows of
    /// stalls at ±5 facing each other, z along it): a string of bulbs
    /// along each row's front, two lengths a side, and the canopy over the
    /// cart in the right row's gap, their fronts to the aisle.
    static let alley: [(piece: Self, x: Float, z: Float, angle: Float)] = [
        (.bulbString, -3.4, -4, .pi / 2), (.bulbString, -3.4, 4, .pi / 2),
        (.bulbString, 3.4, -4, -.pi / 2), (.bulbString, 3.4, 4, -.pi / 2),
        (.canopy, 5, 0.5, -.pi / 2), (.stallCart, 4.6, 0.5, -.pi / 2),
    ]

    /// ``alley``'s pieces that decode, each `lift` up (the alley's square).
    static func alleyParts(lift: Float) -> [(model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float)] {
        alley.compactMap { place in place.piece.model.map { ($0, place.x, place.z, lift, place.angle) } }
    }
}
