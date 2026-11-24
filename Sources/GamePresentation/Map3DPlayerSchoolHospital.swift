import Foundation

/// Decision 963: the player's primary school and hospital, the author's
/// old SwiftRailMac 学校 and 病院 meshes with their textures cut into the
/// game's palette by the local studio
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/civic-school-hospital-2026-11/revision-3`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``):
///
/// - `civic-school-main`: an L of three- and four-storey classroom wings,
///   a corridor of windows, an outside stair (32.9 × 36.4 m, 11.5 m high);
/// - `civic-school-gym`: the arched gym (17.2 × 27.4 m, 10.6 m);
/// - `civic-hospital`: a tall front block with a blue sign and white
///   cross, a lower back block, an outside stair (26.8 × 21.9 m, 14.0 m).
///
/// Each faces −y (its gate or door), its middle at its own origin, the
/// ground at z 0; drawn close up, and from farther as the box round it
/// (``Map3DScene/Builder/PlacedKitLayout``), as decision 902's shop.
enum Map3DPlayerSchoolHospital {
    /// The models' names in ``encoded``.
    static let schoolName = "civic-school-main"
    static let gymName = "civic-school-gym"
    static let hospitalName = "civic-hospital"

    /// Where each stands on its plot (a ``Map3DScene/Builder/PlacedKitLayout``'s
    /// `x` ahead and `right`, its front turned to the layout's by
    /// ``Map3DPlayerShopOffice/frontTurn``): the brief's §11, its east
    /// the layout's left and its south the layout's front. The school
    /// 1 m in from the plot's front and right edges (±23 m), the gym
    /// 1 m in from the back and left, a yard 18.8 m across between the
    /// gym and the school's west wing; the hospital 2 m back from the
    /// middle of its 30 m plot, 6 m of drive before it.
    static let schoolAt: (x: Float, right: Float) = (3.80, 5.54)
    static let gymAt: (x: Float, right: Float) = (-8.29, -13.41)
    static let hospitalAt: (x: Float, right: Float) = (-2, 0)

    /// The school's two wings on its plot, what is drawn of it from
    /// farther (the brief's §6, about ``schoolAt``): the long wing with
    /// the corner block along the front, 11.49 m to its roof, and the
    /// west wing with its outside stair down the right side, 10.47 m.
    static let schoolWings: [(centre: Map3DPoint, length: Float, width: Float, height: Float)] = [
        (Map3DPoint(15.86, 0, 5.54), 12.28, 32.92, 11.49),
        (Map3DPoint(-2.34, 0, 17.835), 24.12, 8.33, 10.47),
    ]

    /// The studio's materials (the brief's table, §8), in the order
    /// `glb_to_swift.py --materials` gave them, each its game colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.schoolWalls,           // wallCream #EFE5CF
        Map3DPalette.tileWhite,             // wallTile #EDEFF0
        Map3DPalette.stone,                 // stone #BFBBB2
        Map3DPalette.concrete,              // concrete #CFCBC2
        Map3DDepotFacilities.glass,         // glass #26313D
        Map3DPalette.steel,                 // steel #8A9099
        Map3DPalette.roof,                  // roofGrey #C4C8D6
        Map3DPalette.cityRoofs[5].color,    // roofBrown #B85A42
        Map3DPalette.gymGreen,              // gymRoof #5E8F86
        Map3DPalette.canopy,                // signBlue #2F6DB5
    ]

    /// The model called `name`, in its colours; `nil` if it does not decode.
    static func model(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }
}
