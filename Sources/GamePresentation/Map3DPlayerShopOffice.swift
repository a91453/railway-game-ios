import Foundation

/// Decision 902: the player's shop and office block, as the local studio
/// modelled them in Blender from photographs of Taiwan's streets
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/player-shop-office-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``):
///
/// - `player-shop`: a row of four arcaded shophouses, each its own wall
///   colour and sign, a water tank and sheds on the roofs
///   (21.9 × 15.3 m, 13.5 m high);
/// - `player-office`: an office block of six floors, ribbon windows, the
///   top floor set back, a stone ground floor (27.3 × 23.4 m, 27.0 m).
///
/// Each faces −y (its arcade and doors), its middle on the plot's, the
/// ground at z 0; drawn close up in place of the yellow box, and from
/// farther as the box round it (``Map3DScene/Builder/PlacedKitLayout``).
enum Map3DPlayerShopOffice {
    /// The models' names in ``encoded``.
    static let shopName = "player-shop"
    static let officeName = "player-office"

    /// The studio's materials (the brief's table, §7), in the order
    /// `glb_to_swift.py --materials` gave them, each its game colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.houseWalls[1].color,   // wallCream #F2E2D6
        Map3DPalette.houseWalls[5].color,   // wallGrey #C9D3D6
        Map3DPalette.houseWalls[3].color,   // wallTan #D6C2B0
        Map3DPalette.houseWalls[7].color,   // wallSage #BFC8B4
        Map3DPalette.cityOfficeWalls[3],    // wallOffice #D9D4C8
        Map3DPalette.cityConcreteWalls[3],  // stoneBase #BBB2A9
        Map3DPalette.arcade,                // arcadeShade #6F6A64
        Map3DPalette.dark,                  // windowDark #2B2F36
        Map3DPalette.roof,                  // roofFlat #C4C8D6
        Map3DPalette.cityRoofs[5].color,    // roofSheet #B85A42
        Map3DPalette.tankSteel,             // tank #C8CDD2
        Map3DPalette.steel,                 // steel #8A9099
        Map3DScene.Builder.barrierRed,      // signRed #D9473F
        Map3DScene.Builder.barrierYellow,   // signYellow #F2C94C
        Map3DPalette.cityRoofs[3].color,    // signGreen #3C8A5A
        Map3DPalette.cityRoofs[4].color,    // signBlue #2D68AC
    ]

    /// The model called `name`, in its colours; `nil` if it does not decode.
    static func model(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    /// The angle (``Map3DScene/Builder/PlacedKitLayout``'s) that turns a
    /// model's front, −y, to a layout's front, +x.
    static let frontTurn: Float = -.pi / 2
}
