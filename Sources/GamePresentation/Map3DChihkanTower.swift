/// Decision 928: Chihkan Tower (赤崁樓), Tainan: the two halls with their
/// double eaves (Haishen Temple before, Wenchang Pavilion behind) on the
/// brick platform of the Dutch fort, the nine steles on their stone
/// tortoises before it. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-chihkan-tower-2026-11/revision-3`,
/// #297; lessons in `docs/studio/lessons/tw-chihkan-tower.md`), turned
/// 9.3° clockwise as OpenStreetMap's Haishen Temple stands (way
/// 561994807), and written here by
/// `tools/landmarks/glb_to_swift.py --turn -9.3` (``encoded``).
enum Map3DChihkanTower {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-chihkan-tower", map: "taiwan",
        // The point midway between the two halls is OpenStreetMap's (ways
        // 561994807 and 183052614: 22.9975554, 120.2026125); the
        // footprint's middle is 4.3 m west of it.
        latitude: 22.9975581, longitude: 120.2025704,
        // brick, roofTile, ridge, column, wallCream, doorBlue, stele,
        // warm_lit.
        palette: [Map3DPalette.redBrick, Map3DPalette.templeRoof, Map3DPalette.mtrCharcoal, Map3DPalette.mtrRed,
                  Map3DPalette.schoolWalls, Map3DPalette.trimBlue, Map3DPalette.stone, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // The turned platform and forecourt, 41.4 m by 43.9 m; the
        // pavilion's ridge 17.95 m.
        size: (41.44, 43.92, 17.95))
}
