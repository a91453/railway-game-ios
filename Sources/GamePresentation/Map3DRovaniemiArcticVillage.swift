/// Decision 907: the Santa Claus village on the Arctic Circle: the red
/// main house with its pointed tower, two dark log houses, the stone
/// posts and the white line on the ground. Modelled by the local studio
/// from photographs and OpenStreetMap's outlines
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/rovaniemi-landmarks-2026-11/revision-4`,
/// #226), its white line along x (east), and written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DRovaniemiArcticVillage {
    static let registration = Map3DLandmarkRegistration(
        id: "rovaniemi-arctic-village", map: "rovaniemi",
        // The middle of the studio's footprint: its reference point
        // (66.5436, 25.8473; the white line 5 m north of it) moved 8.88 m
        // east and 8.52 m north (`revision-4/layout.json`).
        latitude: 66.5436771, longitude: 25.8475002,
        // roadGrey, stone, white (the line, frames), dark, roofDark,
        // timberRed, glass, logBrown.
        palette: [Map3DPalette.arcade, Map3DPalette.stone, Map3DPalette.tileWhite, Map3DPalette.dark,
                  Map3DPalette.cityRoofs[1].color, Map3DPalette.templeRidge, Map3DPalette.glazing, Map3DPalette.counters[1]],
        glass: [6],
        encoded: encoded,
        size: (128.15, 97.75, 25.5))
}
