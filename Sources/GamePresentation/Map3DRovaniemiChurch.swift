/// Decision 907: Rovaniemi Church (Rovaniemen kirkko): a steep dark roof
/// over cream walls and the tall spire at one corner. Modelled by the
/// local studio from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/rovaniemi-landmarks-2026-11/revision-4`,
/// #226), turned 178.2° as OpenStreetMap's outline, its tower to the west,
/// and written here by `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DRovaniemiChurch {
    static let registration = Map3DLandmarkRegistration(
        id: "rovaniemi-church", map: "rovaniemi",
        // The middle of OpenStreetMap's outline.
        latitude: 66.4946115, longitude: 25.7287903,
        // stone (the base), wallCream, roofDark, dark (doors, the porch's
        // roof), glass, gold (the cross).
        palette: [Map3DPalette.stone, Map3DPalette.schoolWalls, Map3DPalette.cityRoofs[1].color, Map3DPalette.dark,
                  Map3DPalette.glazing, Map3DPalette.templeRoof],
        glass: [4],
        encoded: encoded,
        size: (56.83, 29.19, 53.7))
}
